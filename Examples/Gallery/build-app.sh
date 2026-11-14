#!/bin/bash
set -euo pipefail

GALLERY_DIR="$(cd "$(dirname "$0")" && pwd)"
GALLERY_BUILD="$GALLERY_DIR/.build/app"
xcodebuild -project "$GALLERY_DIR/OpenUIGallery.xcodeproj" \
  -scheme OpenUIGallery -destination 'platform=macOS' \
  -configuration Debug -derivedDataPath "$GALLERY_BUILD" \
  CODE_SIGNING_ALLOWED=NO build
printf 'Built: %s\n' "$GALLERY_BUILD/Build/Products/Debug/OpenUIGallery.app"
