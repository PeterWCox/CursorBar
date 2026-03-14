#!/usr/bin/env bash
# Build Cursor+ (Debug) and launch the app. Run from project root.
# Use this instead of Xcode Play when you just want to run the app; re-run to "restart."

set -e
cd "$(dirname "$0")"

# Kill any existing Cursor+ instances so we build and launch fresh.
if killall "Cursor+" 2>/dev/null; then
  echo "Killed existing Cursor+."
fi

xcodebuild \
  -project "CursorMetro.xcodeproj" \
  -scheme "CursorMetro" \
  -configuration Debug \
  -derivedDataPath build \
  build \
  2>&1

APP_PATH="build/Build/Products/Debug/Cursor+.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app not found: $APP_PATH"
  exit 1
fi

echo ""
echo "Launching Cursor+..."
open "$APP_PATH"
