#!/bin/bash
set -e

# Get script directory (project root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Building Cursor Metro..."
xcodebuild -project "CursorMetro.xcodeproj" -scheme "CursorMetro" -configuration Release -derivedDataPath build clean build

APP_SOURCE="$SCRIPT_DIR/build/Build/Products/Release/CursorMetro.app"
APP_DEST="$SCRIPT_DIR/CursorMetro.app"

if [[ -d "$APP_SOURCE" ]]; then
    echo "Copying CursorMetro.app to source directory..."
    rm -rf "$APP_DEST"
    cp -R "$APP_SOURCE" "$APP_DEST"
    echo "Done! CursorMetro.app is at $APP_DEST"
else
    echo "Error: Build succeeded but app not found at $APP_SOURCE"
    exit 1
fi
