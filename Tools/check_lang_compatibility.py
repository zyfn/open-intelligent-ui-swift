#!/usr/bin/env python3
"""Compare complete historical reader contracts with the pinned RC20 baseline.

This checks exported native contracts; it is not an OpenUI Lang parser.
Description changes are allowed. Names, positional signatures, binding markers,
nested fields, types, enums, required/default values and functions/actions are
preserved. SearchImage is included via a non-network provider.
"""
import argparse
import difflib
import hashlib
import json
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile

BASELINE = "ed3f6f82abf6f7cc9e307e9bb2eb21073a1f7d79"
BASELINE_LOCK_SHA256 = "d4798e33b262c773f839e5740114c31c54f5d117cbb78468afcc85e88cf36c4f"
BASELINE_OPENUI_REVISION = "b8ea283916b9630ce8590338c8f8dc5b71fd75e4"
BASELINE_SLIDER_PATH = "packages/swift-ui/Sources/OpenUISwiftUI/Components/NativeSlider.swift"
BASELINE_SLIDER_SHA256 = "03c587e2ddf459f980d55c96e00dcfad13e5b7d264344a4badde124f711f5ca6"
BASELINE_SLIDER_PATCHED_SHA256 = "f2512377b174fbae0ea7686b709299beeff4a3232967269991a39eea6df83ee6"
BASELINE_SLIDER_EXPRESSION = (
    "    let index = dragging ?? values.indices.min { "
    "abs(14 + width * fraction(values[$0]) - start.x) < "
    "abs(14 + width * fraction(values[$1]) - start.x) } ?? 0\n"
)
BASELINE_SLIDER_REPLACEMENT = """    let index: Int
    if let dragging = dragging {
      index = dragging
    } else {
      let closest: Int? = values.indices.min { (left: Int, right: Int) -> Bool in
        let leftPosition: CGFloat = 14 + width * fraction(values[left])
        let rightPosition: CGFloat = 14 + width * fraction(values[right])
        let leftDistance: CGFloat = abs(leftPosition - start.x)
        let rightDistance: CGFloat = abs(rightPosition - start.x)
        return leftDistance < rightDistance
      }
      index = closest ?? 0
    }
"""


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def git_output(checkout, *arguments):
    return subprocess.check_output(["git", *arguments], cwd=checkout, text=True).strip()


def verify_baseline_compile_shim(checkout, pins):
    dependency = checkout / ".build/checkouts/openui"
    if json.loads((checkout / "Package.resolved").read_bytes())["pins"] != pins:
        raise SystemExit("Baseline dependency pins changed; the historical comparison is invalid")
    if git_output(dependency, "rev-parse", "HEAD") != BASELINE_OPENUI_REVISION:
        raise SystemExit("Baseline OpenUI checkout changed revision; refusing the historical comparison")
    if git_output(dependency, "diff", "HEAD", "--name-only") != BASELINE_SLIDER_PATH:
        raise SystemExit("Baseline compile shim changed files beyond the single reviewed UI expression")
    if sha256((dependency / BASELINE_SLIDER_PATH).read_bytes()) != BASELINE_SLIDER_PATCHED_SHA256:
        raise SystemExit("Baseline slider differs from the reviewed compile shim")


def prepare_baseline_compile_shim(root, checkout):
    """Decompose one old UI expression only in the pinned temporary checkout.

    Current Swift toolchains time out checking this RC20 slider expression. The
    same min comparator, arithmetic order and dragging short circuit remain;
    no Lang/Core source or exported contract is patched. Other baseline refs
    retain the original tool behavior and receive no third-party source shim.
    """
    revision = git_output(checkout, "rev-parse", "HEAD")
    if revision != BASELINE:
        print(f"No baseline compile shim for {revision}; compiling the requested baseline unchanged")
        return None
    lock = checkout / "Package.resolved"
    original_lock = lock.read_bytes()
    if sha256(original_lock) != BASELINE_LOCK_SHA256:
        raise SystemExit("Pinned RC20 dependency lock changed; review before applying the compile shim")
    pins = json.loads(original_lock)["pins"]
    openui = [pin for pin in pins if pin["identity"] == "openui"]
    if len(openui) != 1 or openui[0]["state"]["revision"] != BASELINE_OPENUI_REVISION:
        raise SystemExit("Pinned RC20 OpenUI dependency does not match the reviewed compile shim")
    run(["swift", "package", "--package-path", str(checkout), "resolve"], root)
    resolved_lock = lock.read_bytes()
    if json.loads(resolved_lock)["pins"] != pins:
        raise SystemExit("Resolving the baseline changed dependency pins; refusing to compare")
    dependency = checkout / ".build/checkouts/openui"
    if git_output(dependency, "rev-parse", "HEAD") != BASELINE_OPENUI_REVISION:
        raise SystemExit("Resolved OpenUI checkout is not the pinned RC20 dependency")
    if git_output(dependency, "diff", "HEAD", "--name-only"):
        raise SystemExit("Resolved baseline dependency is already modified; refusing to apply the shim")
    slider = dependency / BASELINE_SLIDER_PATH
    original = slider.read_bytes()
    text = original.decode("utf-8")
    if sha256(original) != BASELINE_SLIDER_SHA256 or text.count(BASELINE_SLIDER_EXPRESSION) != 1:
        raise SystemExit("Pinned RC20 slider source changed; review instead of broadening the compile shim")
    patched = text.replace(BASELINE_SLIDER_EXPRESSION, BASELINE_SLIDER_REPLACEMENT).encode("utf-8")
    if sha256(patched) != BASELINE_SLIDER_PATCHED_SHA256:
        raise SystemExit("Baseline slider compile shim does not match its reviewed result")
    # SwiftPM may protect resolved source files; only this temporary UI file
    # receives owner-write permission. The dependency revision stays pinned.
    slider.chmod(slider.stat().st_mode | stat.S_IWUSR)
    slider.write_bytes(patched)
    verify_baseline_compile_shim(checkout, pins)
    evidence = root / "outputs/verification"
    evidence.mkdir(parents=True, exist_ok=True)
    patch = "".join(difflib.unified_diff(
        text.splitlines(keepends=True), patched.decode("utf-8").splitlines(keepends=True),
        fromfile="a/" + BASELINE_SLIDER_PATH, tofile="b/" + BASELINE_SLIDER_PATH,
    ))
    (evidence / "historical-baseline-slider-shim.patch").write_text(patch)
    report = {
        "baseline_commit": revision,
        "dependency_repository": openui[0]["location"],
        "dependency_revision": BASELINE_OPENUI_REVISION,
        "source_path": BASELINE_SLIDER_PATH,
        "source_before_sha256": sha256(original),
        "source_after_sha256": sha256(patched),
        "lock_before_sha256": sha256(original_lock),
        "lock_after_resolution_sha256": sha256(resolved_lock),
        "dependency_pins_unchanged": True,
        "dependency_pins": pins,
        "patch_sha256": sha256(patch.encode("utf-8")),
        "scope": "Temporary RC20 UI compile shim only; Lang/Core and contract comparison are unchanged",
    }
    (evidence / "historical-baseline-slider-shim.json").write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n"
    )
    print(f"Baseline-only NativeSlider compile shim: {sha256(original)} -> {sha256(patched)}")
    print(f"Baseline compile shim patch and provenance: {evidence}")
    return pins


def schema_contract(value):
    if not isinstance(value, dict):
        return value
    result = {}
    mappings = {"properties", "$defs", "definitions", "patternProperties", "dependentSchemas"}
    children = {"items", "additionalProperties", "additionalItems", "not", "contains",
                "if", "then", "else", "propertyNames", "unevaluatedProperties", "unevaluatedItems"}
    arrays = {"allOf", "anyOf", "oneOf", "prefixItems"}
    for key, item in value.items():
        if key in {"description", "$comment"}:
            continue
        if key in mappings and isinstance(item, dict):
            # A business field NAMED description is part of the contract.
            result[key] = {name: schema_contract(child) for name, child in item.items()}
        elif key in children:
            result[key] = [schema_contract(v) for v in item] if isinstance(item, list) else schema_contract(item)
        elif key in arrays and isinstance(item, list):
            result[key] = [schema_contract(v) for v in item]
        else:
            # Defaults/enums/const are source data, not schema annotations.
            result[key] = item
    return result


def contract(spec):
    return {
        "root": spec.get("root"),
        "components": [(name, entry["signature"]) for name, entry in spec.get("components", {}).items()],
        "functions": [(name, entry["signature"]) for name, entry in spec.get("functions", {}).items()],
        "actions": [(name, entry["signature"]) for name, entry in spec.get("actions", {}).items()],
        "schema": schema_contract(spec["schema"]),
    }


def compare(before, after):
    original, current = contract(before), contract(after)
    changed = [key for key in original if original[key] != current[key]]
    if changed:
        raise SystemExit("Historical lang contract changed: " + ", ".join(changed))
    names = [name for name, _ in current["components"]]
    if len(names) != 61 or "SearchImage" not in names:
        raise SystemExit("Compatibility export must cover all 61 entries, including SearchImage")
    print("Historical lang contract unchanged: 61 components, positional signatures and full schemas")


def run(command, cwd):
    subprocess.run(command, cwd=cwd, check=True)


def verify_native(root, baseline):
    with tempfile.TemporaryDirectory(prefix="intelligentui-lang-") as temporary:
        temporary = Path(temporary)
        checkout = temporary / "baseline"
        run(["git", "worktree", "add", "--detach", str(checkout), baseline], root)
        try:
            export = checkout / "Tools/ContractExport/Export.swift"
            text = export.read_text()
            original = "let library = try IntelligentUILibrary(excludingComponents: excluded)"
            replacement = (
                'let library = try IntelligentUILibrary(imageSearch: IntelligentUIImageSearch { query in '
                '.init(url: "https://example.invalid/contract-only.jpg", alt: query) }, excludingComponents: excluded)'
            )
            if text.count(original) != 1:
                raise SystemExit("Baseline export hook changed; review the pinned baseline instead of regenerating it")
            export.write_text(text.replace(original, replacement))
            shim_pins = prepare_baseline_compile_shim(root, checkout)
            before, after = temporary / "before", temporary / "after"
            run(["swift", "run", "--package-path", str(checkout), "ContractExport", str(before)], root)
            if shim_pins is not None:
                verify_baseline_compile_shim(checkout, shim_pins)
            evidence = root / "outputs/verification"
            evidence.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(before / "spec.json", evidence / "historical-reader-before.json")
            run(["swift", "run", "ContractExport", "--reader-contract", "--include-search", str(after)], root)
            shutil.copyfile(after / "reader-spec.json", evidence / "historical-reader-after.json")
            compare(json.loads((before / "spec.json").read_text()),
                    json.loads((after / "reader-spec.json").read_text()))
        finally:
            run(["git", "worktree", "remove", "--force", str(checkout)], root)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-ref", default=BASELINE)
    parser.add_argument("--compare", nargs=2, metavar=("BEFORE", "AFTER"),
                        help="Compare two already-exported all-component reader specs")
    args = parser.parse_args()
    if args.compare:
        compare(*(json.loads(Path(path).read_text()) for path in args.compare))
    else:
        verify_native(Path(__file__).resolve().parents[1], args.baseline_ref)


if __name__ == "__main__":
    main()

