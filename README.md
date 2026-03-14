# Cursor+

<div style="background-color: #15161B; padding: 2.5rem 2.5rem; border-radius: 8px; margin: 0 -0.5rem 1.5rem -0.5rem;">

![Cursor+](MarketingAssets/CursorPlusLogo.png)

<p style="font-size: 1.5rem; font-weight: 700; color: #fafafa; line-height: 1.4; margin: 1rem 0 0.5rem 0;">Cursor’s AI agent in your menu bar. Code in your editor, get help without leaving the flow.</p>

<p style="font-size: 1rem; font-weight: 400; color: #a1a1aa; line-height: 1.6; margin: 0;">A native macOS app that talks to the Cursor Agent CLI. One floating panel, multiple projects, real-time streaming—no need to switch into the full IDE when you just want to ask the agent something.</p>

</div>

---

## What it is

**Cursor+** is an unofficial, native macOS app that gives you quick access to Cursor’s AI agent from the **menu bar**. It uses the same Cursor Agent CLI that powers the IDE, so you get the same models and context—without running the full Cursor app.

Open the panel, pick a project, type a prompt, and watch responses stream in. The window stays where you put it (or collapses to a slim sidebar), so it fits how you work: single monitor, laptop, or multi-screen.

---

## Who it’s for

- **Laptop / single-screen coders** who don’t want the IDE eating half the display—Cursor+ stays out of the way until you need it.
- **Multi-project workflows**—switch repos and workspaces in one window, each with its own conversation and quick actions.
- **Anyone who prefers their main editor** (VS Code, Xcode, Neovim, etc.) but still wants Cursor’s agent on tap from the menu bar.
- **“Vibe coding” and quick iterations**—Fix build, Commit & push, or custom prompts in one click while you stay in flow.

---

## What you get

| Feature | Benefit |
|--------|---------|
| **Menu bar launcher** | Open the agent panel from anywhere; no need to bring Cursor to the front. |
| **Floating panel** | Stays on top and where you place it—or collapse to a sidebar to free space and still see when the agent is done. |
| **Real-time streaming** | See agent output as it’s generated, same as in the IDE. |
| **Multiple projects in one window** | Tabs per workspace; switch repos without opening separate windows. |
| **Quick actions** | One-click **Fix build** and **Commit & push** (and optional project-specific commands) so common tasks stay fast. |
| **Workspace & model picker** | Choose project folder and model (with optional hiding of models you don’t use). |
| **Project rules** | Uses `.cursor/rules` and `AGENTS.md` from your workspace, so the agent knows your project. |
| **History** | Recent questions per tab so you can revisit or re-run prompts. |
| **View in Browser / Debug** | Open your app in the browser or run a debug script from the current workspace. |

---

## Screenshots

<img src="MarketingAssets/metro-dashboard-cursor-split.png" alt="Cursor+ full view with dashboard" style="flex: 1; min-width: 280px; max-width: 50%; border-radius: 6px;" />
<img src="MarketingAssets/cursor-metro-sidebar.png" alt="Cursor+ collapsed sidebar" style="flex: 1; min-width: 280px; max-width: 50%; border-radius: 6px;" />

![Cursor+ Dashboard](MarketingAssets/metro-dashboard-screenshot.png)

---

## What you need

- **macOS** (recent version)
- **Cursor CLI** (the `agent` tool)—used to create chats and stream responses
- **Xcode** (from the Mac App Store) or **Xcode Command Line Tools**—to build the app

---

## 1. Install the Cursor CLI

Cursor+ talks to Cursor through the **Cursor CLI**. Install it and log in once:

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

The first run will create **Cursor+.app** in the project folder (or in the build products directory). You can drag **Cursor+.app** into **Applications** if you like.

### Option B: Using the terminal

From the project folder:

**Release build** (recommended for normal use):

```bash
./build-app.sh
```

This produces **Cursor+.app** in the project directory. Copy it to Applications or run it from there.

**Debug build** (if you’re changing the code):

```bash
./build-and-run.sh
```

---

## 3. Run Cursor+

- **First time:** Open **Cursor+.app** (from the project folder or from Applications). The Cursor+ icon appears in the **menu bar** (top right).
- **Open the panel:** Click the menu bar icon. A floating panel opens with the composer and conversation.
- **Settings:** Click the **⚙️** icon or use **⌘,** to set your default workspace (project folder).
- **Quit:** Right‑click the menu bar icon → **Quit Cursor+**, or use **⌘Q** when the panel is focused.

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
| **“Try running ’agent login’”** | In Terminal, run `agent login` and complete the sign-in. Then try again in Cursor+. |
| **Panel doesn’t open** | Check that Cursor+ is allowed in **System Settings → Privacy & Security → Accessibility** (needed for the floating panel). |
| **Build fails in Xcode** | Ensure you’re on a recent Xcode and macOS. Open the project with **File → Packages → Reset Package Caches** if dependency errors persist. |

---

## Not supported (yet)

- **Billing / usage** — not exposed via the Cursor Agent CLI.
- **File tagging with @** — may or may not be possible via CLI.
- **Running skills with /** — not available in this app.
- **Plan mode** — not available.
- **Agent list on the right** — layout option not implemented.

---

## Planned

- **Terminal per project** — run sessions without leaving Cursor+ (e.g. no need to open iTerm/Ghostty).
- **Open in browser** — improved support.
- **Task lists** — for planning and tracking.
- **Claude Code interoperability** — where supported by the CLI.
- **Rendering improvements** — smoother experience in very long conversations.

---

## For developers

- **Cursor Agent CLI:** See [docs/cursor-agent-cli.md](docs/cursor-agent-cli.md) for what the `agent` CLI can do, its commands and arguments, and how Cursor+ uses it.
- **Source layout:** See [docs/agent-streaming-and-rendering.md](docs/agent-streaming-and-rendering.md) for how streaming and rendering work.
- **Code structure:** The app is split by responsibility: `CursorPlusApp.swift` (app lifecycle, panel, status bar), `PopoutView.swift` (main UI and streaming), `AgentRunner.swift` (Cursor CLI), `ConversationModels.swift` and `AgentTabState.swift` (domain and tab state), plus smaller view and helper modules. MARK comments are used in longer files.
