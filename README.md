# CursorBar

`CursorBar` is a native macOS menu bar app for sending prompts to the Cursor CLI agent without switching back to the editor. It opens as a floating panel, streams agent output live, and runs against the repository you choose.

## What It Does

- Lives in the macOS menu bar with no Dock icon
- Opens a polished floating panel anchored near the status item
- Streams both agent thinking and final response output in real time
- Supports multiple agent tabs with separate conversation history
- Lets you choose the Cursor model for each run
- Lets you switch workspaces/repositories from the UI
- Accepts pasted screenshots and includes them in the next prompt
- Handles common CLI failures like missing `agent` or missing auth

## Requirements

1. `macOS 14+`
2. `Xcode` for building and running the app
3. `Cursor CLI`, installed and authenticated

Install and authenticate the CLI:

```bash
curl https://cursor.com/install -fsSL | bash
agent login
```

The app looks for `agent` in common install locations such as `~/.local/bin`, `/usr/local/bin`, `/opt/homebrew/bin`, and your `PATH`.

## Build And Run

Open the project in Xcode:

```bash
open CursorMenuBar.xcodeproj
```

Then:

1. Select the `CursorMenuBar` scheme.
2. Press `Cmd+R`.
3. Click the `CursorBar` icon in the menu bar to open the panel.

## Usage

### First Run

1. Launch the app from Xcode.
2. Click the menu bar icon.
3. Choose your workspace folder if needed.
4. Pick a model from the model menu.
5. Type a prompt and send it.

### Prompting

- Press `Return` to send the current prompt
- Press `Shift+Return` to insert a newline
- Click the send button to start a run
- Click the stop button while a run is streaming to cancel it

### Workspace Selection

Use the workspace chip in the composer area, or open the settings window, to choose the repository the agent should run in.

The selected workspace is where Cursor CLI will execute, and where it will pick up repo-specific context like `.cursor/rules` and `AGENTS.md`.

### Model Selection

The panel includes a model picker for supported Cursor models, including:

- `Composer 1.5`
- `Composer 1`
- `Auto`
- `Claude 4.6 Opus (Thinking)`
- `Claude 4.6 Sonnet`
- `Claude 4.6 Sonnet (Thinking)`
- `GPT-5.4`
- `GPT-5.4 High`
- `Gemini 3.1 Pro`

### Screenshots

You can attach a screenshot from the clipboard in either of these ways:

- Click `Attach`
- Paste an image directly into the prompt editor
- Press `Cmd+Shift+V`

When attached, the image is written to:

```text
.cursor/pasted-screenshot.png
```

The app automatically appends a reference to that file in the next prompt so the agent can use it.

### Tabs And History

- Use the `+` button to open another agent tab
- Each tab keeps its own prompt/response history
- Closing a tab stops any active stream in that tab first

## How It Works

`CursorBar` shells out to Cursor CLI using non-interactive prompt mode and requests JSON streaming output so the UI can update live as the agent responds.

At a high level it runs the equivalent of:

```bash
agent -f -p "<prompt>" --workspace "<repo>" --output-format stream-json --stream-partial-output
```

If a model is selected, the app also passes `--model <model>`.

## Troubleshooting

### `Cursor CLI not found`

Install the CLI and make sure `agent` is available in one of the standard locations or on your `PATH`.

### `Not authenticated`

Run:

```bash
agent login
```

### Agent exits with an error

The app surfaces stderr from the CLI in the panel so you can see the failure directly.

## Project Structure

- `CursorMenuBar/CursorMenuBarApp.swift` - app entry point, status item, floating panel, shared app state
- `CursorMenuBar/PopoutView.swift` - main UI, tabs, prompt composer, screenshot attachment, streaming transcript rendering
- `CursorMenuBar/AgentRunner.swift` - launches `agent`, parses stream JSON events, converts them into UI updates
- `CursorMenuBar/SettingsView.swift` - workspace picker and repository configuration
- `CursorMenuBar/Info.plist` - app metadata, including `LSUIElement` so it stays out of the Dock
