#!/usr/bin/env python3
"""Verify the evaluated SwiftPM graph and native module ownership."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
PRODUCTS = {"OpenUILang", "OpenUICore", "OpenSwiftUI", "OpenIntelligentSwiftUI"}
ALLOWED = {
    "COpenUIRegExp": set(),
    "OpenUILang": {"COpenUIRegExp"},
    "OpenUICore": {"OpenUILang"},
    "OpenSwiftUI": {"OpenUILang", "OpenUICore"},
    "OpenIntelligentSwiftUI": {"OpenUILang", "OpenUICore"},
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
    products = {product["name"]: product for product in manifest["products"]
                if "library" in product["type"]}
    if set(products) != PRODUCTS:
        problems.append(f"Expected exactly four library products, found {sorted(products)}")
    for name in PRODUCTS:
        if products.get(name, {}).get("targets") != [name]:
            problems.append(f"Product {name} must export its single owning target")

    graph = {name: dependencies(target) for name, target in targets.items()}
    for name, allowed in ALLOWED.items():
        if name not in targets:
            problems.append(f"Missing native module: {name}")
            continue
        declared_path = root / (targets[name].get("path") or f"Sources/{name}")
        if declared_path.resolve() != (root / "Sources" / name).resolve() or not declared_path.is_dir():
            problems.append(f"{name} must be owned by its existing Sources/{name} directory")
        local = graph[name] & targets.keys()
        if local - allowed:
            problems.append(f"{name} has an invalid dependency: {sorted(local - allowed)}")
        if name in {"OpenSwiftUI", "OpenIntelligentSwiftUI"} and "OpenUICore" not in local:
            problems.append(f"{name} must directly depend on shared OpenUICore")
        if name == "OpenUICore" and graph[name] != {"OpenUILang"}:
            problems.append("OpenUICore must depend only on OpenUILang")
        if name == "OpenUILang" and graph[name] != {"COpenUIRegExp"}:
            problems.append("OpenUILang must retain its bounded native regular-expression backend")

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

    for first, second in [("OpenSwiftUI", "OpenIntelligentSwiftUI"),
                          ("OpenIntelligentSwiftUI", "OpenSwiftUI")]:
        if second in reachable(first):
            problems.append(f"{first} still transitively depends on peer {second}")
    if "OpenUICoreTests" not in targets or "OpenUICore" not in graph.get("OpenUICoreTests", set()):
        problems.append("An independently owned Core behavior test target is required")
    if reachable("OpenUICoreTests") & {"OpenSwiftUI", "OpenIntelligentSwiftUI"}:
        problems.append("Core behavior tests must run without either UI library")

    for name in PRODUCTS:
        forbidden = PRODUCTS - ALLOWED[name] - {name}
        if name == "OpenUILang":
            forbidden |= {"SwiftUI", "UIKit", "AppKit"}
        for path in (root / "Sources" / name).rglob("*.swift"):
            source = path.read_text()
            leaked = set(IMPORT.findall(source)) & forbidden
            if leaked:
                problems.append(f"{path.relative_to(root)} imports forbidden modules {sorted(leaked)}")
            if name == "OpenUICore" and re.search(
                r"\b(OpenUIStandardComponents|OpenUIThemeValues|IntelligentUITheme)\b", source
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
