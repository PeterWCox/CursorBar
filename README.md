# CursorBar

A native macOS menu bar app that lets you run the Cursor CLI agent from anywhere—without leaving your current app. Open a floating panel, type or paste a prompt, and watch responses stream live. Pick the repo and model, then keep working.

<img width="681" height="908" alt="image" src="https://github.com/user-attachments/assets/a0135093-cb93-48b0-9a82-374c8047e214" />

## Features

- **Menu bar only** — No Dock icon; stays out of the way until you need it
- **Floating panel** — Polished window anchored near the menu bar icon
- **Live streaming** — See agent thinking and final output as it happens
- **Multiple tabs** — Separate conversations, each with its own history
- **Model picker** — Choose the Cursor model (Composer, Claude, GPT, Gemini) per run
- **Workspace switching** — Point the agent at any repo from the UI; respects `.cursor/rules` and `AGENTS.md`
- **Screenshot prompts** — Attach or paste images; they’re included in the next prompt automatically

## Requirements

- **macOS 14+**
- **Xcode** (to build and run)
- **Cursor CLI** — [install](https://cursor.com/install) then run `agent login` to authenticate

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

Attach a screenshot from the clipboard by clicking **Attach**, pasting into the prompt area, or pressing **⌘⇧V**. The image is saved in the workspace and automatically referenced in your next prompt so the agent can see it.

### Tabs And History

- Use the `+` button to open another agent tab
- Each tab keeps its own prompt/response history
- Closing a tab stops any active stream in that tab first

## How It Works

The app runs the Cursor CLI in non-interactive mode with streaming output, so you see responses as they’re generated. It uses your chosen workspace and model for each run.

---

**Setup:** Ensure the [Cursor CLI](https://cursor.com/install) is installed and you’ve run `agent login`. The app looks for `agent` in `~/.local/bin`, `/usr/local/bin`, `/opt/homebrew/bin`, or your `PATH`. If something goes wrong, the panel shows CLI output so you can debug from there.
