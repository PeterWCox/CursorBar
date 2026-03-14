---
name: build-cursorplus
description: Creates a Debug or Release build of the Cursor+ macOS app. Use when the user asks for a release build, debug build, "build for release", "build for debugging", or to build the Cursor+ app in a specific configuration.
---

# Build Cursor+ (Debug / Release)

Build the Cursor+ macOS app in either **Debug** or **Release** configuration. Run from the project root.

## Debug build

Use for development: includes debug symbols, DEBUG badge in UI, no optimizations.

```bash
xcodebuild -project "CursorMetro.xcodeproj" -scheme "CursorMetro" -configuration Debug -derivedDataPath build clean build 2>&1
```

- **Output**: `build/Build/Products/Debug/Cursor+.app`
- Optional: copy to project root with  
  `cp -R build/Build/Products/Debug/Cursor+.app .`

## Release build

Use for distribution (e.g. GitHub releases): optimized, no DEBUG badge, smaller and faster.

```bash
xcodebuild -project "CursorMetro.xcodeproj" -scheme "CursorMetro" -configuration Release -derivedDataPath build clean build 2>&1
```

- **Output**: `build/Build/Products/Release/Cursor+.app`
- Optional: copy to project root with  
  `cp -R build/Build/Products/Release/Cursor+.app .`

## Notes

- Project scripts: `./build-and-run.sh` (Debug + copy + Xcode Run), `./build-app.sh` (Release + copy).
- If the user only says "release build" or "debug build", run the matching command and report success or failure and the app path.
