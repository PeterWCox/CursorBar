---
name: reset-cursor-metro-state
description: Resets Cursor Metro's local app state to a first-launch style state. Use when the user wants to simulate an out-of-box launch, clear restored projects/tabs, wipe app-local preferences, or start Cursor Metro fresh, with an optional deeper reset that also deletes repo-local `.metro` folders when explicitly requested.
---

# Reset Cursor Metro State

Reset Cursor Metro's local app state so the next launch behaves like a fresh install from the app's point of view.

By default, this skill clears app-local persistence only. It does not delete project repositories or per-project `.metro` files unless the user explicitly asks for that deeper reset.

## What This Clears

- Restored tabs and projects saved in app support
- App-level preferences stored in the `com.cursorplus.app` defaults domain
- UI state such as saved panel frame, scan roots, hidden projects, model preferences, and similar local settings

## What This Does Not Clear

- Any repositories in `~/dev` or elsewhere
- Per-project `.metro/project.json`
- Per-project tasks or other repo-local files

## Optional Deeper Reset

If the user explicitly asks to remove repo-local Cursor Metro state too, also delete every `.metro` folder under `~/dev`.

This still does not delete the repositories themselves. It only removes the repo-local `.metro` directories.

## macOS Locations

- App state file: `~/Library/Application Support/CursorPlus/cursor_plus_tabs.json`
- Defaults domain: `com.cursorplus.app`

## Workflow

1. If Cursor Metro is running, make sure it is fully quit first so it does not immediately save state again on termination.
2. Delete the saved tab/project state file:

```bash
rm -f ~/Library/Application\ Support/CursorPlus/cursor_plus_tabs.json
```

3. Clear the app defaults domain:

```bash
defaults delete com.cursorplus.app
```

4. If `defaults delete` reports that the domain does not exist, treat that as already clean rather than a failure.
5. If the user explicitly asks for a deeper reset, find and delete every `.metro` directory under `~/dev`.

```bash
python3 - <<'PY'
import os
root = os.path.expanduser('~/dev')
matches = []
for dirpath, dirnames, filenames in os.walk(root):
    if '.metro' in dirnames:
        matches.append(os.path.join(dirpath, '.metro'))
for path in sorted(matches):
    print(path)
PY
```

Then delete only the discovered `.metro` directories:

```bash
rm -rf "/absolute/path/to/repo/.metro" "/absolute/path/to/another-repo/.metro"
```

After deletion, verify that no `.metro` directories remain under `~/dev`.
6. Tell the user that the next launch/build should open with a fresh local app state.

## Notes

- Prefer this skill when the user says things like "out of the box", "fresh launch", "clear restored projects", or "reset local app state".
- If the user only wants restored projects/tabs cleared, deleting `cursor_plus_tabs.json` may be enough.
- If the goal is a full first-launch simulation, clear both the app support file and the defaults domain.
- If the user also wants repo-local Metro state gone, include deletion of the discovered `.metro` directories under `~/dev`.
