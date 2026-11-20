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


def resolve_component_example(samples: dict, name: str) -> dict:
    visited: set[str] = set()
    while name not in visited:
        visited.add(name)
        sample = samples.get(name)
        if not isinstance(sample, dict):
            raise ValueError(f"{name}: expected a component example object")
        parent = sample.get("container")
        if parent is None:
            return sample
        if not isinstance(parent, str) or parent not in samples:
            raise ValueError(f"{name}: unknown parent component {parent!r}")
        if sample.get("category") is not None or sample.get("examples") is not None:
            raise ValueError(f"{name}: nested components inherit their parent's category and examples")
        name = parent
    raise ValueError(f"{name}: component example parent cycle")


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
    example_counts: dict[str, int] = {}
    intelligent_categories = {"Layout", "Content", "Controls", "Media", "DataDisplay"}
    for library in sorted(LIBRARIES):
        try:
            samples = json.loads((resources / "Components" / f"{library}.json").read_text(encoding="utf-8"))
            if not isinstance(samples, dict) or not samples:
                raise ValueError("expected a nonempty component example object")
            component_counts[library] = len(samples)
            example_counts[library] = 0
            for name in samples:
                label = f"Components/{library}/{name}"
                try:
                    sample = resolve_component_example(samples, name)
                except ValueError as error:
                    problems.append(f"{label}: {error}")
                    continue
                category, examples = sample.get("category"), sample.get("examples")
                if library == "openintelligentui":
                    if not isinstance(category, str) or category not in intelligent_categories:
                        problems.append(f"{label}: unknown OpenIntelligentUI group {category!r}")
                elif category is not None and (not isinstance(category, str) or not category.strip()):
                    problems.append(f"{label}: expected a group name for an ungrouped component")
                if not isinstance(examples, list) or not examples:
                    problems.append(f"{label}: expected a nonempty examples array")
                    continue
                if sample is not samples[name]:
                    if not any(isinstance(item, dict) and isinstance(item.get("program"), str)
                               and f"{name}(" in item["program"] for item in examples):
                        problems.append(f"{label}: this component is missing from its parent's examples")
                    continue
                ids: set[str] = set()
                for item in examples:
                    if not isinstance(item, dict):
                        problems.append(f"{label}: examples must be objects")
                        continue
                    identifier = item.get("id")
                    if not isinstance(identifier, str) or not IDENTIFIER.fullmatch(identifier) or identifier in ids:
                        problems.append(f"{label}: invalid or duplicate example ID {identifier!r}")
                        continue
                    ids.add(identifier)
                    title, program = item.get("title"), item.get("program")
                    if not isinstance(title, str) or not title.strip():
                        problems.append(f"{label}/{identifier}: missing title")
                    if not isinstance(program, str) or f"{name}(" not in program:
                        problems.append(f"{label}/{identifier}: program does not use {name}")
                    example_counts[library] += 1
        except (ValueError, OSError) as error:
            problems.append(f"Components/{library}: {error}")
    try:
        tokens = json.loads((resources / "DesignSystem" / "muse.tokens.json").read_text(encoding="utf-8"))
        revision = tokens.get("revision") if isinstance(tokens, dict) else None
        if not isinstance(revision, str) or not re.fullmatch(r"[0-9a-f]{40}", revision):
            problems.append("DesignSystem: Muse token source must pin a complete Git revision")
    except (ValueError, OSError) as error:
        problems.append(f"DesignSystem: {error}")
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
        "components": component_counts,
        "componentExamples": example_counts,
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
