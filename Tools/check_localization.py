#!/usr/bin/env python3
"""Check package-localized SDK copy, format arguments and literal call sites."""
from __future__ import annotations
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "Sources/SwiftIntelligentUI/Resources"
LANGUAGES = ("en", "zh-Hans", "ar")
ENTRY = re.compile(r'^\s*("(?:[^"\\]|\\.)*")\s*=\s*("(?:[^"\\]|\\.)*")\s*;\s*$')
PLACEHOLDER = re.compile(r'%(?!%)(?:(\d+)\$)?(?:[-+ #0]*)(?:\d+)?(?:\.\d+)?(ll|l|hh|h)?([@diufFeEgGsc])')

def read_table(language: str) -> dict[str, str]:
    path = RESOURCES / f"{language}.lproj/IntelligentUI.strings"
    entries: dict[str, str] = {}
    for number, line in enumerate(path.read_text().splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("//"):
            continue
        match = ENTRY.fullmatch(line)
        if not match:
            raise ValueError(f"{path.relative_to(ROOT)}:{number}: invalid strings entry")
        key, value = (json.loads(part) for part in match.groups())
        if key in entries:
            raise ValueError(f"{language}: duplicate key {key}")
        entries[key] = value
    return entries

def placeholders(value: str) -> list[tuple[int, str, str]]:
    # Keep argument type and position; permit translators to reorder explicitly.
    return sorted((int(m[1]) if m[1] else index, m[2] or "", m[3])
                  for index, m in enumerate(PLACEHOLDER.finditer(value.replace("%%", "")), 1))

def main() -> int:
    tables = {language: read_table(language) for language in LANGUAGES}
    reference = tables["en"]
    errors: list[str] = []
    for language, table in tables.items():
        for key in sorted(reference.keys() - table.keys()):
            errors.append(f"{language}: missing {key}")
        for key in sorted(table.keys() - reference.keys()):
            errors.append(f"{language}: unexpected {key}")
        for key in reference.keys() & table.keys():
            if placeholders(reference[key]) != placeholders(table[key]):
                errors.append(f"{language}: incompatible format arguments for {key}")
    # Include literal keys in conditional first arguments. Computed key families
    # are covered by native tests and explicit resource review.
    used: set[str] = set()
    for path in (ROOT / "Sources/SwiftIntelligentUI").rglob("*.swift"):
        source = path.read_text()
        for call in re.finditer(r"SDKStrings\.text\((.*?)\blocale\s*:", source, re.S):
            for key in re.findall(r'"([A-Za-z][A-Za-z0-9]*\.[A-Za-z0-9._]+)"', call[1]):
                if key.endswith("."):
                    continue  # Prefix of an explicitly computed key family.
                used.add(key)
                if key not in reference:
                    errors.append(f"{path.relative_to(ROOT)}: missing key {key}")
    if errors:
        print("\n".join(sorted(set(errors))), file=sys.stderr)
        return 1
    print(f"Localization resources: {len(reference)} keys × {len(tables)} languages; "
          f"{len(used)} literal call-site keys checked.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())

