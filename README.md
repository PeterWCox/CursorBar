# Cursor Metro

## 1. What is it?

**Cursor Metro** is a lightweight, open-source macOS app that wraps the [Cursor Agent CLI](https://cursor.com) for fast, focused “vibe coding.”

The name *Metro* is a nod to small convenience stores or quick transit: you drop in, get the essentials, and move on—without full-screen Cursor windows and scattered terminals.

It is meant to stay on screen (or collapsed to a slim side panel) so you can track agent progress across projects without losing context in a maze of tabs.

![Cursor Metro screenshot 1](docs/img1.jpeg)

## 2. Features

- **Tasks and agents** — Create tasks, delegate them to agents, and watch status in the sidebar until you are ready to review and complete them.
- **Integrated terminal** — Run builds and shell commands next to your tasks; the app can help wire this up if you are unsure how.
- **Always-on, low-footprint UX** — Designed for multiple projects and fewer distractions than juggling many Cursor windows and terminals.

**Planned**

- Creating and scaffolding new projects  
- Remote agents  
- Claude Code interoperability  

![Cursor Metro screenshot 2](docs/im2.jpg)

![Cursor Metro screenshot 3](docs/img3.jpg)

![Cursor Metro screenshot 4](docs/img4.jpg)

![Cursor Metro screenshot 5](docs/img5.jpg)

## 3. Get started

**Requirements:** macOS 15 or later. To run agents, you need the **Cursor Agent CLI** installed and available on your `PATH` (commonly `~/.local/bin` after install). This applies to both options below.

---

### Option 1 — Release artifact (downloaded `.app`)

1. Download and unzip the release, then move **Cursor Metro.app** where you want it (for example **Applications**).

2. **First launch and permissions (Gatekeeper)**  
   Unsigned or non-notarized builds may be blocked the first time you open them.

   - **Finder:** Control-click (right-click) **Cursor Metro.app** → **Open** → confirm **Open** when macOS asks.  
   - **Terminal:** Remove the quarantine flag, then open the app as usual:

     ```bash
     xattr -cr "/path/to/Cursor Metro.app"
     ```

     Replace `/path/to/Cursor Metro.app` with the real path (for example the copy in your Downloads folder or **Applications**).

3. If macOS still refuses to open the app, open **System Settings** → **Privacy & Security**, scroll to the message about **Cursor Metro** being blocked, and choose **Open Anyway** (you may need a failed open attempt first for this button to appear).

---

### Option 2 — Build with Xcode

1. Install **Xcode** from the Mac App Store (or Apple’s developer tools) and open it once to accept the license and install components.

2. Install the **Cursor Agent CLI** so Metro can spawn agents (same requirement as Option 1).

3. From the **repository root**, build and run without opening Xcode:

   ```bash
   ./build-and-run.sh
   ```

   This produces a Debug build and launches **Cursor Metro.app**.

4. **Alternatively**, open `CursorMetro.xcodeproj` in Xcode, select the **CursorMetro** scheme, then **Product** → **Run** (⌘R).

**Release-style build from the command line** (optimized output under `build/`):

```bash
xcodebuild -project "CursorMetro.xcodeproj" -scheme "CursorMetro" -configuration Release -derivedDataPath build clean build
```

The built app is at `build/Build/Products/Release/Cursor Metro.app`.
