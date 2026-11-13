#!/usr/bin/env python3
"""Check migration ownership and immutable imported runtime bytes; no network or UI claims."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main() -> None:
    manifest = json.loads((ROOT / "OpenUI/IMPORT.json").read_text())
    problems: list[str] = []
    for name, expected in manifest["runtimeFiles"].items():
        path = ROOT / name
        if not path.is_file() or sha(path) != expected["sha256"]:
            problems.append(f"Imported runtime changed without an explicit reviewed baseline: {name}")
    package = (ROOT / "Package.swift").read_text()
    if "https://github.com/zyfn/openui.git" in package:
        problems.append("Old fork SwiftPM dependency remains")
    for name in ["OpenUILang", "OpenUISwiftUI", "SwiftIntelligentUI"]:
        if len(re.findall(r'\.target\(name:\s*"' + name + r'"', package)) != 1:
            problems.append(f"Target must have exactly one owner: {name}")
    for path in [ROOT / "Package.resolved", ROOT / "Examples/Gallery/IntelligentUIGallery.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"]:
        if any(pin["identity"] == "openui" for pin in json.loads(path.read_text())["pins"]):
            problems.append(f"Obsolete fork pin: {path.relative_to(ROOT)}")
    gallery = (ROOT / "Examples/Gallery/IntelligentUIGallery.xcodeproj/project.pbxproj").read_text()
    if "https://github.com/zyfn/openui.git" in gallery or "XCRemoteSwiftPackageReference" in gallery:
        problems.append("Gallery still resolves a separate native runtime")
    for path in (ROOT / "OpenUI/Tools").rglob("package-lock.json"):
        for package_info in json.loads(path.read_text()).get("packages", {}).values():
            url = package_info.get("resolved", "")
            if url and not url.startswith("https://registry.npmjs.org/"):
                problems.append(f"Non-public generator registry: {path.relative_to(ROOT)}")
    lock = json.loads((ROOT / "OpenUI/Tools/upstream.json").read_text())
    patch = ROOT / "OpenUI/Tools" / lock["core"]["sourcePatch"]
    if sha(patch) != lock["core"]["sourcePatchSHA256"]:
        problems.append("Unreviewed upstream signature patch")
    resource = ROOT / "OpenUI/Sources/OpenUILang/Resources"
    core = json.loads((resource / "core-manifest.json").read_text())
    if core["sha256"] != sha(resource / "lang-core.js") or core["sourceTree"] != lock["core"]["adaptedTree"]:
        problems.append("Generated core does not match its pinned provenance")
    files = ["entry.ts", "captures.ts", "authoring.ts", "compat.mjs", "readiness.ts", "readiness-compat.mjs", "adaptations.json", "patches/serializer-roundtrip.patch", "build.mjs", "../upstream.mjs", "../upstream.json", "patches/positional-omittability.patch"]
    adapter = "\n".join((ROOT / "OpenUI/Tools/Core" / name).read_text() for name in files)
    if hashlib.sha256(adapter.encode()).hexdigest() != core["adapterSha256"]:
        problems.append("Generated manifest does not describe the current bridge builder")
    if core["lockSha256"] != sha(ROOT / "OpenUI/Tools/Core/package-lock.json"):
        problems.append("Core npm lock differs from its manifest")
    for forbidden in ["packages/lang-core", "packages/react-ui", "packages/react-lang", "sites"]:
        if (ROOT / forbidden).exists():
            problems.append(f"Upstream monorepo content imported into native workspace: {forbidden}")
    if problems:
        raise SystemExit("\n".join(problems))
    print(json.dumps({"importedRuntimeFiles": len(manifest["runtimeFiles"]), "source": manifest.get("sourceRevision", manifest.get("source")), "coreSHA256": core["sha256"], "products": 3, "result": "PASS (source/ownership only; not native acceptance)"}, ensure_ascii=False, indent=2))

if __name__ == "__main__":
    main()
