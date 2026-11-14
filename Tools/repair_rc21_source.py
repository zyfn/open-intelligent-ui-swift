#!/usr/bin/env python3
"""Apply or verify the reviewed RC21 source candidate without moving its base HEAD.

The candidate is the immutable source revision plus the exact changes declared in
Validation/source-rc21/manifest.json. It is not the unmodified RC21 source.
Both modes verify the complete candidate tree, including after core regeneration.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "Validation/source-rc21/manifest.json"


def fail(message: str) -> None:
    raise ValueError(message)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def git(source: Path, *args: str, env: dict | None = None) -> bytes:
    result = subprocess.run(["git", "-C", str(source), *args],
                            env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        fail(f"git {' '.join(args)} failed: {result.stderr.decode(errors='replace').strip()}")
    return result.stdout


def relative_path(value: str) -> str:
    path = PurePosixPath(value)
    if not value or path.is_absolute() or ".." in path.parts or str(path) != value:
        fail(f"Invalid relative path in source repair manifest: {value!r}")
    return value


def regular_file(root: Path, relative: str) -> Path:
    path = root / relative_path(relative)
    if not path.is_file() or path.resolve() != path:
        fail(f"Expected a regular file without symlink parents: {path}")
    return path


def load_manifest() -> tuple[dict, bytes, Path]:
    raw = MANIFEST.read_bytes()
    manifest = json.loads(raw)
    if manifest.get("schema_version") != 1:
        fail("Unsupported source repair manifest version")
    files = manifest["files"]
    paths = [relative_path(item["path"]) for item in files]
    if not paths or len(set(paths)) != len(paths):
        fail("Source repair manifest must declare a nonempty, unique file set")
    for item in files:
        if item["operation"] not in {"patch", "copy"}:
            fail(f"Unknown repair operation for {item['path']}")
        for key in ("before_sha256", "after_sha256"):
            if not re.fullmatch(r"[0-9a-f]{64}", item[key]):
                fail(f"Invalid {key} for {item['path']}")
        if item["before_sha256"] == item["after_sha256"]:
            fail(f"Unchanged file must not be declared as a repair: {item['path']}")
        if item["operation"] == "copy":
            payload = regular_file(ROOT, item["copy_from"])
            if sha256(payload.read_bytes()) != item["after_sha256"]:
                fail(f"Reviewed copy payload differs: {item['copy_from']}")
    for value in (manifest["base"]["revision"], manifest["base"]["tree"],
                  manifest["candidate_tree"]):
        if not re.fullmatch(r"[0-9a-f]{40}", value):
            fail("Expected exact Git object IDs for the source base and candidate")
    patch = regular_file(MANIFEST.parent, manifest["patch"]["path"])
    if sha256(patch.read_bytes()) != manifest["patch"]["sha256"]:
        fail("Reviewed source repair patch SHA-256 does not match its manifest")
    return manifest, raw, patch


def check_base(source: Path, manifest: dict) -> None:
    if Path(git(source, "rev-parse", "--show-toplevel").decode().strip()).resolve() != source:
        fail("--source must be the root of the frozen source checkout")
    for expression, expected in (("HEAD", manifest["base"]["revision"]),
                                 ("HEAD^{tree}", manifest["base"]["tree"])):
        actual = git(source, "rev-parse", expression).decode().strip()
        if actual != expected:
            fail(f"Frozen source {expression} changed: expected {expected}, found {actual}")
    if git(source, "diff", "--cached", "--name-only", "HEAD", "--"):
        fail("The source checkout index must remain identical to the frozen HEAD")


def check_files(source: Path, manifest: dict, phase: str) -> list[dict]:
    result = []
    for item in manifest["files"]:
        data = regular_file(source, item["path"]).read_bytes()
        actual = sha256(data)
        if actual != item[f"{phase}_sha256"]:
            fail(f"Unexpected {phase} content for {item['path']}: {actual}")
        result.append({"path": item["path"], "sha256": actual, "bytes": len(data)})
    return result


def status(source: Path) -> bytes:
    return git(source, "status", "--porcelain=v1", "-z", "--untracked-files=all",
               "--ignore-submodules=none")


def candidate_tree(source: Path) -> str:
    # A fresh temporary index also observes tracked changes hidden by flags in
    # the checkout's real index. Neither mode stages files or changes HEAD.
    with tempfile.TemporaryDirectory(prefix="openui-source-index-") as directory:
        env = dict(os.environ, GIT_INDEX_FILE=str(Path(directory) / "index"))
        git(source, "read-tree", "HEAD", env=env)
        git(source, "-c", "core.filemode=true", "add", "--update", "--", ".", env=env)
        return git(source, "write-tree", env=env).decode().strip()


def verify_candidate(source: Path, manifest: dict) -> tuple[str, list[dict]]:
    check_base(source, manifest)
    files = check_files(source, manifest, "after")
    expected = {f" M {item['path']}".encode() for item in manifest["files"]}
    actual = set(status(source).rstrip(b"\0").split(b"\0"))
    if actual != expected:
        fail("Source working tree differs from the allowed repair file set: "
             + repr(sorted(entry.decode(errors="replace") for entry in actual ^ expected)))
    tree = candidate_tree(source)
    if tree != manifest["candidate_tree"]:
        fail(f"Complete source candidate tree differs: expected {manifest['candidate_tree']}, found {tree}")
    return tree, files


def apply_candidate(source: Path, manifest: dict, patch: Path) -> tuple[str, list[dict]]:
    check_base(source, manifest)
    if status(source):
        fail("Source repair requires a clean checkout, including untracked files")
    check_files(source, manifest, "before")
    if candidate_tree(source) != manifest["base"]["tree"]:
        fail("Tracked source files differ from the immutable base tree")
    declared = {item["path"] for item in manifest["files"] if item["operation"] == "patch"}
    patch_stats = git(source, "apply", "--numstat", "-z", str(patch))
    patched = set()
    for entry in patch_stats.rstrip(b"\0").split(b"\0"):
        fields = entry.decode().split("\t", 2)
        if len(fields) != 3:
            fail("Source repair patch must contain only modifications of declared files")
        patched.add(fields[2])
    if patched != declared:
        fail("Source repair patch file set differs from the manifest")
    git(source, "apply", "--check", "--whitespace=error", str(patch))
    originals = {item["path"]: (source / item["path"]).read_bytes() for item in manifest["files"]}
    try:
        git(source, "apply", "--whitespace=error", str(patch))
        for item in manifest["files"]:
            if item["operation"] == "copy":
                (source / item["path"]).write_bytes(regular_file(ROOT, item["copy_from"]).read_bytes())
        return verify_candidate(source, manifest)
    except Exception:
        for relative, data in originals.items():
            (source / relative).write_bytes(data)
        raise


def record_evidence(source: Path, evidence: Path, manifest: dict, raw: bytes,
                    patch: Path, tree: str, files: list[dict], verifying: bool) -> dict:
    evidence.mkdir(parents=True, exist_ok=True)
    record = {
        "schema_version": 1,
        "result": "PASS",
        "mode": "verify" if verifying else "apply",
        "checked_at": datetime.now(timezone.utc).isoformat(),
        "description": "Frozen RC21 source plus reviewed fixes; not an unmodified source checkout",
        "base": manifest["base"],
        "candidate_tree": tree,
        "controller_revision": git(ROOT, "rev-parse", "HEAD").decode().strip(),
        "repair_manifest_sha256": sha256(raw),
        "repair_patch_sha256": manifest["patch"]["sha256"],
        "files": files,
    }
    (evidence / "repair-manifest.json").write_bytes(raw)
    (evidence / "reviewed-source-fixes.patch").write_bytes(patch.read_bytes())
    (evidence / "source-candidate.diff").write_bytes(
        git(source, "diff", "--no-ext-diff", "--no-textconv", "--binary", "HEAD", "--"))
    (evidence / "candidate-provenance.json").write_text(json.dumps(record, indent=2) + "\n")
    with (evidence / "candidate-verifications.jsonl").open("a") as stream:
        stream.write(json.dumps(record, separators=(",", ":")) + "\n")
    return record


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path, help="Clean checkout of the frozen source revision")
    parser.add_argument("--evidence", required=True, type=Path, help="Evidence directory outside the source checkout")
    parser.add_argument("--verify", action="store_true", help="Verify the complete repaired candidate without applying changes")
    args = parser.parse_args()
    source, evidence = args.source.resolve(), args.evidence.resolve()
    if source == evidence or source in evidence.parents:
        fail("--evidence must be outside the source checkout")
    manifest, raw, patch = load_manifest()
    tree, files = (verify_candidate(source, manifest) if args.verify
                   else apply_candidate(source, manifest, patch))
    record = record_evidence(source, evidence, manifest, raw, patch, tree, files, args.verify)
    print(json.dumps(record, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, json.JSONDecodeError) as error:
        sys.exit(f"RC21 source repair failed: {error}")
