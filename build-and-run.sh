#!/bin/bash
set -e

# Get script directory (project root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Building Cursor Metro..."
xcodebuild -project CursorMetro.xcodeproj -scheme CursorMetro -configuration Debug -derivedDataPath build clean build

APP_SOURCE="$SCRIPT_DIR/build/Build/Products/Debug/CursorMetro.app"
APP_DEST="$SCRIPT_DIR/CursorMetro.app"

if [[ -d "$APP_SOURCE" ]]; then
    echo "Copying CursorMetro.app to project root..."
    rm -rf "$APP_DEST"
    cp -R "$APP_SOURCE" "$APP_DEST"
    echo "Build complete. CursorMetro.app is at $APP_DEST"
else
    echo "Error: Build succeeded but app not found at $APP_SOURCE"
    exit 1
fi

echo "Sending Stop then Run to Xcode..."
# Activate Xcode and press Stop (Cmd+.) then Run (Cmd+R)
# Requires: System Settings → Privacy & Security → Accessibility → enable Terminal/Cursor
if osascript <<'APPLESCRIPT'
tell application "Xcode" to activate
delay 0.3
tell application "System Events"
    tell process "Xcode"
        -- Stop (⌘.)
        key code 47 using command down
        delay 0.5
        -- Run (⌘R)
        keystroke "r" using command down
    end tell
end tell
APPLESCRIPT
then
    echo "Done. Xcode should be running the app."
else
    echo "Note: Could not send keystrokes to Xcode (allow Terminal/Cursor in Accessibility to fix). Run the app from Xcode (⌘R) or open CursorMetro.app."
fi
