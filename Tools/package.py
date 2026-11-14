#!/usr/bin/env python3
"""Create a local source preview with exact file hashes; does not publish."""
import gzip
import hashlib
import json
from pathlib import Path
import tarfile

root = Path(__file__).resolve().parents[1]
version = "0.1.0-preview.29-design-revamp"
exported_manifest = root / "outputs/contracts/manifest.json"
if not exported_manifest.exists() or json.loads(exported_manifest.read_text()).get("version") != version:
    raise SystemExit("Contract version does not match source preview; export current contracts before packaging.")
output = root / "outputs/delivery"
output.mkdir(parents=True, exist_ok=True)
files = []
for directory in ["Sources", "Tests", "Tools", "Benchmarks", "Examples", "docs", ".github", "OpenUI"]:
    for path in (root / directory).rglob("*"):
        if path.is_file() and not any(part in {"node_modules", "__pycache__", "xcuserdata", ".DS_Store", ".build", ".swiftpm", ".git"} for part in path.parts):
            files.append((path, path.relative_to(root)))
for name in ["README.md", "Package.swift", "Package.resolved", "THIRD-PARTY-NOTICES.txt", ".gitignore"]:
    files.append((root / name, Path(name)))
for path in (root / "outputs/contracts").glob("*"):
    if path.is_file(): files.append((path, Path("contracts") / path.name))
files.sort(key=lambda item: str(item[1]))
manifest = {str(relative): hashlib.sha256(path.read_bytes()).hexdigest() for path, relative in files}
latest = output / "source-manifest.json"
if latest.exists():
    previous = json.loads(latest.read_text())
    (output / ("source-manifest-" + previous["version"] + ".json")).write_text(latest.read_text())
manifest_text = json.dumps({"version": version, "files": manifest}, indent=2)
latest.write_text(manifest_text)
(output / ("source-manifest-" + version + ".json")).write_text(manifest_text)
archive = output / ("OpenUISwiftSDK-" + version + ".tar.gz")
with archive.open("wb") as stream, gzip.GzipFile(filename="", mode="wb", fileobj=stream, mtime=0) as compressed:
    with tarfile.open(fileobj=compressed, mode="w") as tar:
        for path, relative in files:
            info = tar.gettarinfo(str(path), arcname="OpenUISwiftSDK-" + version + "/" + str(relative))
            info.mtime = 0; info.uid = 0; info.gid = 0; info.uname = ""; info.gname = ""
            with path.open("rb") as source: tar.addfile(info, source)
checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
(output / "SHA256SUMS").write_text("".join(hashlib.sha256(path.read_bytes()).hexdigest() + "  " + path.name + "\n" for path in sorted(output.glob("*.tar.gz"))))
with tarfile.open(archive) as tar:
    assert len(tar.getmembers()) == len(files)
print(json.dumps({"archive": str(archive), "files": len(files), "bytes": archive.stat().st_size, "sha256": checksum}, indent=2))
