#!/bin/bash
set -euo pipefail

GALLERY_DIR="$(cd "$(dirname "$0")" && pwd)"
GALLERY_REPO="$(cd "$GALLERY_DIR/../.." && pwd)"
GALLERY_EVIDENCE="$GALLERY_REPO/outputs/verification/gallery-contracts"
mkdir -p "$GALLERY_EVIDENCE"
swift test --package-path "$GALLERY_DIR"
swift run --package-path "$GALLERY_DIR" OpenUIGallery --validate-fixtures
swift run --package-path "$GALLERY_DIR" OpenUIGallery \
  --export-contracts "$GALLERY_EVIDENCE"
