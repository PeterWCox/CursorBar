---
name: fb
description: Fixes build errors for the Cursor+ macOS app. Runs the build, parses xcodebuild errors, applies fixes, and re-builds until the build succeeds. Use when the user says /fb, "fix the build", or wants to fix compile errors in the Cursor+ project.
---

# Fix Build (/fb)

Fix the Cursor+ app build by building, reading errors, and applying fixes until the build succeeds.

## Workflow

1. **Build** from the project root:
   ```bash
   xcodebuild -project "Cursor+.xcodeproj" -scheme "Cursor+" -configuration Debug build 2>&1
   ```
   Capture full stdout and stderr.

2. **Parse errors** from xcodebuild output:
   - Look for lines like `path/to/file.swift:line:column: error: message`
   - Note file path (relative to project root), line, and message.

3. **Fix** each reported error in the source file(s):
   - Open the file at the given path.
   - Address the error (missing import, type mismatch, unknown symbol, etc.).
   - Prefer minimal, targeted edits.

4. **Re-run the build.** If new errors appear, repeat from step 2. Stop when the build succeeds.

5. **Report** to the user: either "Build fixed" and a brief summary of changes, or that the build is still failing and what remains.

## Notes

- If you see "requires Xcode" or toolchain errors, tell the user to run:
  ```bash
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  ```
- Swift errors often come in chains (one fix may clear several). Fix the first/root cause first, then rebuild.
- Do not guess at large refactors; fix only what the compiler reports unless the user asks for more.
