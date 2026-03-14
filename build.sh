#!/usr/bin/env bash
# Build Cursor Metro macOS app from the command line.
# Run from the project root. Output: build/Build/Products/Debug/CursorMetro.app

set -e
cd "$(dirname "$0")"

xcodebuild \
  -project "CursorMetro.xcodeproj" \
  -scheme "CursorMetro" \
  -configuration Debug \
  -derivedDataPath build \
  clean build \
  2>&1

echo ""
echo "Build succeeded: build/Build/Products/Debug/Cursor Metro.app"
