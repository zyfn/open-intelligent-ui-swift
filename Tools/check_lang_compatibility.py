#!/usr/bin/env python3
"""Compare complete historical reader contracts with the pinned RC20 baseline.

This checks exported native contracts; it is not an OpenUI Lang parser.
Description changes are allowed. Names, positional signatures, binding markers,
nested fields, types, enums, required/default values and functions/actions are
preserved. SearchImage is included via a non-network provider.
"""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

BASELINE = "ed3f6f82abf6f7cc9e307e9bb2eb21073a1f7d79"


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
            before, after = temporary / "before", temporary / "after"
            run(["swift", "run", "--package-path", str(checkout), "ContractExport", str(before)], root)
            run(["swift", "run", "ContractExport", "--reader-contract", "--include-search", str(after)], root)
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

