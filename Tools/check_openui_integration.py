#!/usr/bin/env python3
"""Check module ownership and pinned runtime inputs; no network or UI claims."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    problems: list[str] = []
    if (ROOT / "SwiftOpenUI").exists() or (ROOT / "SwiftOpenUI").is_symlink():
        problems.append("Obsolete nested SDK directory remains at repository root")
    package = (ROOT / "Package.swift").read_text()
    if "https://github.com/zyfn/openui.git" in package:
        problems.append("Old fork SwiftPM dependency remains")
    for relative in ["Package.resolved", "Examples/Gallery/Package.resolved",
                     "Examples/Gallery/OpenUIGallery.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
                     "Tools/ContractExport/Package.resolved", "Validation/Performance/Package.resolved"]:
        path = ROOT / relative
        if any(pin["identity"] == "openui" for pin in json.loads(path.read_text())["pins"]):
            problems.append(f"Obsolete fork pin: {path.relative_to(ROOT)}")
    gallery = (ROOT / "Examples/Gallery/OpenUIGallery.xcodeproj/project.pbxproj").read_text()
    if "https://github.com/zyfn/openui.git" in gallery or "XCRemoteSwiftPackageReference" in gallery:
        problems.append("Gallery still resolves a separate native runtime")
    for path in (ROOT / "Tools").rglob("package-lock.json"):
        if "node_modules" in path.parts:
            continue
        for package_info in json.loads(path.read_text()).get("packages", {}).values():
            url = package_info.get("resolved", "")
            if url and not url.startswith("https://registry.npmjs.org/"):
                problems.append(f"Non-public generator registry: {path.relative_to(ROOT)}")
    lock = json.loads((ROOT / "Tools/upstream.json").read_text())
    patch = ROOT / "Tools" / lock["core"]["sourcePatch"]
    if sha(patch) != lock["core"]["sourcePatchSHA256"]:
        problems.append("Unreviewed upstream signature patch")
    resource = ROOT / "Sources/SwiftLang/Resources"
    core = json.loads((resource / "core-manifest.json").read_text())
    if core["sha256"] != sha(resource / "lang-core.js") or core["sourceTree"] != lock["core"]["adaptedTree"]:
        problems.append("Generated core does not match its pinned provenance")
    for key, expected in (("upstream", lock["core"]["revision"]),
                          ("dependencyRepository", lock["repository"]),
                          ("dependencyPackage", lock["core"]["package"]),
                          ("dependencyVersion", lock["core"]["version"])):
        if core.get(key) != expected:
            problems.append(f"Generated core {key} differs from the reviewed source lock")
    files = ["entry.ts", "captures.ts", "authoring.ts", "compat.mjs", "bridge-compat.mjs", "budget.ts", "readiness.ts", "readiness-compat.mjs", "source-preprocess.ts", "adaptations.json", "patches/serializer-roundtrip.patch", "build.mjs", "../upstream.mjs", "../upstream.json", "patches/positional-omittability.patch"]
    adapter = "\n".join((ROOT / "Tools/Core" / name).read_text() for name in files)
    if hashlib.sha256(adapter.encode()).hexdigest() != core["adapterSha256"]:
        problems.append("Generated manifest does not describe the current bridge builder")
    if core["lockSha256"] != sha(ROOT / "Tools/Core/package-lock.json"):
        problems.append("Core npm lock differs from its manifest")
    for forbidden in ["packages/lang-core", "packages/react-ui", "packages/react-lang", "sites"]:
        if (ROOT / forbidden).exists():
            problems.append(f"Upstream monorepo content imported into native workspace: {forbidden}")
    if problems:
        raise SystemExit("\n".join(problems))
    print(json.dumps({"coreRevision": lock["core"]["revision"], "coreSHA256": core["sha256"], "products": 3, "result": "PASS (source/ownership only; not native acceptance)"}, ensure_ascii=False, indent=2))

if __name__ == "__main__":
    main()
