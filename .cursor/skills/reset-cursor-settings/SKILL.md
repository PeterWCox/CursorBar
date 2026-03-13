---
name: reset-cursor-settings
description: Resets Cursor user settings and keybindings to factory defaults. Use when the user wants a fresh Cursor configuration, to clean settings, start over, or "as if opened fresh."
---

# Reset Cursor Settings to Fresh State

Reset the current user's Cursor editor settings and keybindings to their default (empty) state, as if Cursor had just been opened for the first time.

## File Locations (macOS)

| File | Path |
|------|------|
| User settings | `~/Library/Application Support/Cursor/User/settings.json` |
| Keybindings | `~/Library/Application Support/Cursor/User/keybindings.json` |

## Instructions

1. **Reset settings.json** – write an empty object:
   ```json
   {}
   ```

2. **Reset keybindings.json** – write an empty array (keep the standard comment):
   ```
   // Place your key bindings in this file to override the defaults
   []
   ```

3. **Inform the user** that Cursor should be restarted for changes to take effect.

## What This Clears

- **settings.json**: All custom preferences ( themes, word wrap, auto-save, fonts, extensions config, etc.)
- **keybindings.json**: All custom keybinding overrides

## Platform Paths

| OS | settings.json | keybindings.json |
|----|---------------|------------------|
| macOS | `~/Library/Application Support/Cursor/User/settings.json` | Same dir `/keybindings.json` |
| Linux | `~/.config/Cursor/User/settings.json` | Same dir `/keybindings.json` |
| Windows | `%APPDATA%\Cursor\User\settings.json` | Same dir `\keybindings.json` |

Use the path appropriate for the user's OS when resetting.
