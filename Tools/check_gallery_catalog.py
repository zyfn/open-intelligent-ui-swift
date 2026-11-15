#!/usr/bin/env python3
"""Check Gallery resource ownership and catalog integrity without running Swift.

The Gallery's --validate-fixtures command separately checks each program against
its actual native library. This check only validates data and packaging inputs.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path, PurePosixPath
import re
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
LIBRARIES = {"openui", "openintelligentui"}
IDENTIFIER = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*")


def check_catalogs(resources: Path) -> dict:
    resources = resources.resolve()
    problems: list[str] = []
    identifiers: set[str] = set()
    total_programs = 0
    counts: dict[str, int] = {}
    by_library = {name: 0 for name in sorted(LIBRARIES)}
    for group in ("Cases", "Diagnostics"):
        directory = resources / group
        manifest = directory / "catalog.json"
        if not manifest.is_file():
            problems.append(f"Missing catalog: {group}/catalog.json")
            continue
        try:
            catalog = json.loads(manifest.read_text(encoding="utf-8"))
        except (ValueError, OSError) as error:
            problems.append(f"{manifest}: {error}")
            continue
        if not isinstance(catalog, dict) or catalog.get("schemaVersion") != 1:
            problems.append(f"{group}: expected catalog schemaVersion 1")
            continue
        cases = catalog.get("cases")
        if not isinstance(cases, list) or not cases:
            problems.append(f"{group}: expected a nonempty cases array")
            continue
        counts[group] = len(cases)
        referenced: set[Path] = set()
        for index, item in enumerate(cases):
            label = f"{group}[{index}]"
            if not isinstance(item, dict):
                problems.append(f"{label}: expected an object")
                continue
            identifier = item.get("id")
            if not isinstance(identifier, str) or not IDENTIFIER.fullmatch(identifier):
                problems.append(f"{label}: id must be a stable lowercase identifier")
            elif identifier in identifiers:
                problems.append(f"{label}: duplicate id {identifier}")
            else:
                identifiers.add(identifier)
                label = f"{group}/{identifier}"
            for key in ("title", "summary", "category"):
                if not isinstance(item.get(key), str) or not item[key].strip():
                    problems.append(f"{label}: missing {key}")
            tags = item.get("tags")
            if not isinstance(tags, list) or not all(isinstance(tag, str) and tag.strip() for tag in tags):
                problems.append(f"{label}: tags must be an array of nonempty strings")
            programs = item.get("programs")
            if not isinstance(programs, dict) or not programs or set(programs) - LIBRARIES:
                problems.append(f"{label}: programs must name openui and/or openintelligentui")
                continue
            if group == "Cases" and set(programs) != LIBRARIES:
                problems.append(f"{label}: every curated scene must provide both libraries")
            for library, relative in programs.items():
                if not isinstance(relative, str) or not relative:
                    problems.append(f"{label}/{library}: expected a program path")
                    continue
                path = PurePosixPath(relative)
                if path.is_absolute() or ".." in path.parts or "\\" in relative or path.suffix != ".openui":
                    problems.append(f"{label}/{library}: invalid relative .openui path {relative}")
                    continue
                source = (directory / relative).resolve()
                if not source.is_relative_to(directory.resolve()):
                    problems.append(f"{label}/{library}: program escapes its catalog directory")
                    continue
                if source in referenced:
                    problems.append(f"{label}/{library}: program is referenced more than once: {relative}")
                referenced.add(source)
                if not source.is_file():
                    problems.append(f"{label}/{library}: program does not exist: {relative}")
                    continue
                try:
                    text = source.read_text(encoding="utf-8")
                except (UnicodeError, OSError) as error:
                    problems.append(f"{label}/{library}: {error}")
                    continue
                if not text.strip():
                    problems.append(f"{label}/{library}: empty program")
                total_programs += 1
                by_library[library] += 1
            if group == "Cases":
                origin = item.get("origin")
                if not isinstance(origin, dict):
                    problems.append(f"{label}: curated scenes must record their source")
                else:
                    if not isinstance(origin.get("revision"), str) or not re.fullmatch(r"[0-9a-f]{40}", origin["revision"]):
                        problems.append(f"{label}: origin must pin a complete Git revision")
                    for key in ("repository", "path"):
                        if not isinstance(origin.get(key), str) or not origin[key].strip():
                            problems.append(f"{label}: origin is missing {key}")
        actual = {path.resolve() for path in directory.rglob("*.openui")}
        for unused in sorted(actual - referenced):
            problems.append(f"{group}: unreferenced program {unused.relative_to(directory.resolve())}")
    component_counts: dict[str, int] = {}
    component_directories = {"Layout", "Content", "Controls", "DataDisplay", "Media"}
    intelligent_directories: dict[str, str] = {}
    source_directory = ROOT / "Sources/SwiftIntelligentUI/Components"
    for source_file in source_directory.rglob("*.swift"):
        for component_name in re.findall(r'OpenUIComponent\(name: "([A-Za-z0-9]+)"', source_file.read_text()):
            intelligent_directories[component_name] = source_file.parent.name
    for component_name in re.findall(r'\("([A-Z][A-Za-z0-9]*)",', (source_directory / "Media/SVG.swift").read_text()):
        intelligent_directories[component_name] = "Media"
    for library in sorted(LIBRARIES):
        try:
            samples = json.loads((resources / "Components" / f"{library}.json").read_text(encoding="utf-8"))
            if not isinstance(samples, dict) or not samples:
                raise ValueError("expected a nonempty component example object")
            component_counts[library] = len(samples)
            for name, sample in samples.items():
                if not isinstance(sample, dict) or not sample.get("category") or not sample.get("program"):
                    problems.append(f"Components/{library}/{name}: missing category or program")
                elif sample["category"] not in component_directories:
                    problems.append(f"Components/{library}/{name}: unknown source directory {sample['category']}")
                elif library == "openintelligentui" and sample["category"] != intelligent_directories.get(name):
                    problems.append(f"Components/{library}/{name}: directory does not match its SDK source")
                elif f"{name}(" not in sample["program"]:
                    problems.append(f"Components/{library}/{name}: example does not use its component")
        except (ValueError, OSError) as error:
            problems.append(f"Components/{library}: {error}")
    image_count = 0
    image_directory = resources / "Images"
    image_manifest = image_directory / "catalog.json"
    try:
        image_catalog = json.loads(image_manifest.read_text(encoding="utf-8"))
        images = image_catalog.get("images") if isinstance(image_catalog, dict) else None
        if not isinstance(images, list) or not images:
            problems.append("Images: expected a nonempty images array")
        else:
            names: set[str] = set()
            sources: set[str] = set()
            for asset in images:
                if not isinstance(asset, dict):
                    problems.append("Images: expected image objects")
                    continue
                name, source = asset.get("file"), asset.get("source")
                if not isinstance(name, str) or Path(name).name != name or "\\" in name or not name.endswith(".jpg"):
                    problems.append(f"Images: invalid image file {name}")
                    continue
                if name in names:
                    problems.append(f"Images: duplicate image file {name}")
                names.add(name)
                if not isinstance(source, str) or urlsplit(source).scheme != "https" or not urlsplit(source).hostname:
                    problems.append(f"Images/{name}: expected the original HTTPS image URL")
                elif source in sources:
                    problems.append(f"Images/{name}: repeated source URL")
                else:
                    sources.add(source)
                image = image_directory / name
                if not image.is_file() or image.stat().st_size == 0:
                    problems.append(f"Images/{name}: missing or empty image")
                else:
                    image_count += 1
            for unused in sorted(path.name for path in image_directory.glob("*.jpg") if path.name not in names):
                problems.append(f"Images: unreferenced image {unused}")
    except (ValueError, OSError) as error:
        problems.append(f"Images/catalog.json: {error}")
    if problems:
        raise ValueError("\n".join(problems))
    return {
        "catalogs": counts,
        "programs": total_programs,
        "programsByLibrary": by_library,
        "componentExamples": component_counts,
        "bundledImages": image_count,
        "result": "PASS (catalog and resource integrity; not native rendering)",
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--resources", type=Path,
                        default=ROOT / "Examples/Gallery/Resources")
    args = parser.parse_args()
    try:
        result = check_catalogs(args.resources)
    except ValueError as error:
        parser.exit(1, str(error) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
