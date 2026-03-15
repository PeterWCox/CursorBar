---
name: verify-build-after-changes
description: Ensures the Cursor Metro app still compiles after agent-made code changes. Use after editing Swift or other source files, refactoring, or applying fixes—run a build and fix any compile errors before considering the task done.
---

# Verify Build After Changes

After **any** code changes (edits, refactors, fixes), run a build and fix compile errors. Do not treat the task as complete until the build succeeds.

## Workflow

1. **Make your changes** as requested.
2. **Run the build** from the project root:

   ```bash
   xcodebuild -scheme CursorMetro -configuration Debug build 2>&1
   ```

3. **If the build fails**:
   - Read the compiler errors (e.g. `error:` lines in the output).
   - Fix the reported issues in the relevant files.
   - Run the build again. Repeat until the build succeeds.
4. **If the build succeeds**: You can report completion.

## Build command (quick)

From project root:

```bash
cd /Users/petercox/dev/CursorMetro && xcodebuild -scheme CursorMetro -configuration Debug build 2>&1
```

To see only errors: append `| grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"`.

## When to apply

- After editing any `.swift` or project source files.
- After fixing build errors (re-verify).
- After refactoring or adding new code.
- Not required for docs-only or non-code changes (e.g. README, comments-only).

## Reference

- Full build options (Debug/Release, output paths): use the **build-cursorplus** skill when the user explicitly asks for a build or release (skill refers to Cursor Metro).
