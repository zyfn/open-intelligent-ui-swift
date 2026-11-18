#!/usr/bin/env python3
"""Verify the evaluated SwiftPM graph and native module ownership."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
PRODUCTS = {"swift-lang": "SwiftLang", "swift-ui": "SwiftOpenUI", "swift-intelligent-ui": "SwiftIntelligentUI"}
MODULES = set(PRODUCTS.values())
ALLOWED = {
    "COpenUIRegExp": set(),
    "SwiftLang": {"COpenUIRegExp"},
    "SwiftOpenUI": {"SwiftLang"},
    "SwiftIntelligentUI": {"SwiftLang"},
}
IMPORT = re.compile(
    r"(?m)^\s*(?:@(?:_exported|testable|preconcurrency)\s+)*"
    r"(?:(?:public|package|internal|fileprivate|private)\s+)?import"
    r"(?:\s+(?:typealias|struct|class|enum|protocol|let|var|func))?\s+([A-Za-z_]\w*)"
)


def dependencies(target: dict) -> set[str]:
    result = set()
    for dependency in target.get("dependencies", []):
        for kind in ("byName", "target", "product"):
            if kind in dependency:
                result.add(dependency[kind][0])
                break
    return result


def check(manifest: dict, root: Path) -> dict:
    problems = []
    targets = {target["name"]: target for target in manifest["targets"]}
    products = {product["name"]: product for product in manifest["products"]}
    if len(targets) != len(manifest["targets"]) or len(products) != len(manifest["products"]):
        problems.append("Targets and products must each have one declaration")
    native_targets = {target["name"] for target in manifest["targets"] if target["type"] != "test"}
    if native_targets != set(ALLOWED):
        problems.append(f"Expected only canonical modules and the internal regex backend, found {sorted(native_targets)}")
    if set(products) != set(PRODUCTS):
        problems.append(f"Expected exactly three library products, found {sorted(products)}")
    if any("library" not in product["type"] for product in products.values()):
        problems.append("Development executables must not be products of the client SDK package")
    for name, module in PRODUCTS.items():
        if products.get(name, {}).get("targets") != [module]:
            problems.append(f"Product {name} must export its single owning target")

    graph = {name: dependencies(target) for name, target in targets.items()}
    dependency_names = {name for names in graph.values() for name in names}
    # dump-package encodes each package dependency as a one-element case array.
    for dependency in manifest.get("dependencies", []):
        for kind in ("sourceControl", "fileSystem", "registry"):
            dependency_names.update(settings["identity"] for settings in dependency.get(kind, []))
    forbidden_dependencies = sorted(name for name in dependency_names
                                    if name.lower().rsplit(".", 1)[-1] in {"react-ui", "react-headless"})
    if forbidden_dependencies:
        problems.append(f"Native SDK must not depend on web UI packages/products: {forbidden_dependencies}")
    for name, allowed in ALLOWED.items():
        if name not in targets:
            problems.append(f"Missing native module: {name}")
            continue
        if targets[name]["type"] != "regular":
            problems.append(f"{name} must remain a regular library target")
        declared_path = root / (targets[name].get("path") or f"Sources/{name}")
        if declared_path.resolve() != (root / "Sources" / name).resolve() or not declared_path.is_dir():
            problems.append(f"{name} must be owned by its existing Sources/{name} directory")
        local = graph[name] & targets.keys()
        if local - allowed:
            problems.append(f"{name} has an invalid dependency: {sorted(local - allowed)}")
        if name in {"SwiftOpenUI", "SwiftIntelligentUI"} and "SwiftLang" not in local:
            problems.append(f"{name} must directly depend on shared SwiftLang")
        if name == "SwiftLang" and graph[name] != {"COpenUIRegExp"}:
            problems.append("SwiftLang must retain its bounded native regular-expression backend")

    def reachable(start: str) -> set[str]:
        seen = set()
        pending = list(graph.get(start, set()))
        while pending:
            name = pending.pop()
            if name in seen:
                continue
            seen.add(name)
            pending.extend(graph.get(name, set()))
        return seen

    for first, second in [("SwiftOpenUI", "SwiftIntelligentUI"),
                          ("SwiftIntelligentUI", "SwiftOpenUI")]:
        if second in reachable(first):
            problems.append(f"{first} still transitively depends on peer {second}")
    if "SwiftLangTests" not in targets or "SwiftLang" not in graph.get("SwiftLangTests", set()):
        problems.append("An independently owned platform adapter test target is required")
    if reachable("SwiftLangTests") & {"SwiftOpenUI", "SwiftIntelligentUI"}:
        problems.append("Platform adapter tests must run without either component library")

    for name in MODULES:
        forbidden = MODULES - ALLOWED[name] - {name}
        for path in (root / "Sources" / name).rglob("*.swift"):
            source = path.read_text()
            leaked = set(IMPORT.findall(source)) & forbidden
            if leaked:
                problems.append(f"{path.relative_to(root)} imports forbidden modules {sorted(leaked)}")
            if name == "SwiftLang" and "Language" in path.relative_to(root / "Sources" / name).parts:
                if set(IMPORT.findall(source)) & ({"SwiftUI", "UIKit", "AppKit"} | MODULES):
                    problems.append(f"{path.relative_to(root)} imports presentation or an SDK facade into the language bridge")
            if name == "SwiftLang" and re.search(
                r"\b(OpenUIComponents|OpenUIThemeValues|OpenIntelligentUITheme)\b", source
            ):
                problems.append(f"{path.relative_to(root)} contains component-library design policy")
    if problems:
        raise SystemExit("\n".join(problems))
    return {"products": sorted(PRODUCTS),
            "nativeDependencies": {name: sorted(graph[name]) for name in sorted(ALLOWED)},
            "result": "PASS (evaluated SwiftPM graph and source boundaries)"}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path,
                        help="A saved swift package dump-package result; otherwise evaluates SwiftPM now")
    args = parser.parse_args()
    text = args.manifest.read_text() if args.manifest else subprocess.check_output(
        ["swift", "package", "dump-package"], cwd=ROOT, text=True)
    print(json.dumps(check(json.loads(text), ROOT), indent=2))


if __name__ == "__main__":
    main()
