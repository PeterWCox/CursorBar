# Cursor Metro

![Cursor Metro](Assets.xcassets/CursorMetroLogo.imageset/CursorMetroLogo.png)

A native **macOS menu bar app** that gives you quick access to Cursor’s AI agent—without leaving your current app. Open the panel from the menu bar, pick a project, type a prompt, and get streaming responses in a compact window.

---

## What you need

- **macOS** (recent version)
- **Cursor CLI** (the `agent` tool)—used to create chats and stream responses
- **Xcode** (from the Mac App Store) or **Xcode Command Line Tools**—to build the app

---

## 1. Install the Cursor CLI

Cursor Metro talks to Cursor through the **Cursor CLI**. Install it and log in once:

```bash
curl https://cursor.com/install -fsSL | bash
```

This usually installs the `agent` binary to `~/.local/bin/agent`. If that directory isn’t in your PATH, add it (e.g. in `~/.zshrc`):

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Then log in so the CLI can use your Cursor account:

```bash
agent login
```

---

## 2. Build the app

### Option A: Using Xcode

1. Open **`CursorMetro.xcodeproj`** in Xcode.
2. Choose the **CursorMetro** scheme and your Mac as the run destination.
3. Press **⌘B** to build, then **⌘R** to run.

The first run will create **CursorMetro.app** in the project folder (or in the build products directory). You can drag **CursorMetro.app** into **Applications** if you like.

### Option B: Using the terminal

From the project folder:

**Release build** (recommended for normal use):

```bash
./build-app.sh
```

This produces **CursorMetro.app** in the project directory. Copy it to Applications or run it from there.

**Debug build** (if you’re changing the code):

```bash
./build-and-run.sh
```

---

## 3. Run Cursor Metro

- **First time:** Open **CursorMetro.app** (from the project folder or from Applications). The Cursor Metro icon appears in the **menu bar** (top right).
- **Open the panel:** Click the menu bar icon. A floating panel opens with the composer and conversation.
- **Settings:** Click the **⚙️** icon or use **⌘,** to set your default workspace (project folder).
- **Quit:** Right‑click the menu bar icon → **Quit Cursor Metro**, or use **⌘Q** when the panel is focused.

---

## 4. First steps

1. Click the menu bar icon to open the panel.
2. If prompted, set your **workspace** (the project folder the agent will use) in Settings (⌘,) or via the workspace picker in the panel.
3. Type a message in the composer and press **Return** (or click Send). The agent reply streams in the conversation area.
4. Use the **sidebar** to switch or add tabs, each with its own conversation and workspace.

---

## Troubleshooting

| Issue | What to try |
|--------|----------------|
| **“Agent not found”** | Install the Cursor CLI (step 1) and ensure `~/.local/bin` is in your `PATH`. Restart the app after changing PATH. |
| **“Try running ’agent login’”** | In Terminal, run `agent login` and complete the sign-in. Then try again in Cursor Metro. |
| **Panel doesn’t open** | Check that Cursor Metro is allowed in **System Settings → Privacy & Security → Accessibility** (needed for the floating panel). |
| **Build fails in Xcode** | Ensure you’re on a recent Xcode and macOS. Open the project with **File → Packages → Reset Package Caches** if dependency errors persist. |

---

## For developers

- **Source layout:** See [docs/agent-streaming-and-rendering.md](docs/agent-streaming-and-rendering.md) for how streaming and rendering work.
- **Code structure:** The app is split by responsibility: `CursorPlusApp.swift` (app lifecycle, panel, status bar), `PopoutView.swift` (main UI and streaming), `AgentRunner.swift` (Cursor CLI), `ConversationModels.swift` and `AgentTabState.swift` (domain and tab state), plus smaller view and helper modules. MARK comments are used in longer files.
