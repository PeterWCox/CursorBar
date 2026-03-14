# Improving the Cursor+ Debugging Experience

Recommendations to reduce the need to hit Xcode’s Play/Stop and to iterate faster.

---

## 1. **Hot reload (SwiftUI without full restart)**

Yes — you can get **hot reload** for SwiftUI using **Inject** + **InjectionIII**. Changed view code is re-applied when you save (⌘S) without rebuilding or relaunching.

### Setup (one-time)

1. **Install InjectionIII**  
   - [Mac App Store](https://apps.apple.com/us/app/injectioniii/id1380446739) or [GitHub](https://github.com/johnno1962/InjectionIII).  
   - Keep it running in the menu bar while developing.

2. **Add the Inject package**  
   - In Xcode: **File → Add Package Dependencies**.  
   - URL: `https://github.com/krzysztofzablocki/Inject.git`  
   - Add the **Inject** library to the Cursor+ target.

3. **Other Linker Flags (Debug only)**  
   - Select the **CursorMetro** target (or Cursor+ scheme) → **Build Settings**.  
   - Search for **Other Linker Flags**.  
   - For the **Debug** configuration, add: `-Xlinker -interposable`.

4. **Load the injection bundle (macOS)**  
   In `App/CursorPlusApp.swift`, load the bundle at app launch so InjectionIII can inject into your running app:

   ```swift
   #if DEBUG
   import Inject
   #endif

   @main
   struct CursorPlusApp: App {
       @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

       init() {
           #if DEBUG
           Bundle(path: "/Applications/InjectionIII.app/Contents/Resources/macOSInjection.bundle")?.load()
           #endif
       }
       // ...
   }
   ```

5. **Enable injection in views you want to hot reload**  
   In any SwiftUI view (e.g. `PopoutView`, `DashboardView`):

   ```swift
   import Inject

   struct SomeView: View {
       @ObserveInjection var inject

       var body: some View {
           // ... your view code ...
           .enableInjection()
       }
   }
   ```

6. **Sandbox**  
   If the app uses App Sandbox, injection may not work; disable sandbox for Debug if you need hot reload.

**Usage:** Run the app from Xcode (or from the terminal script below). Edit a view that has `@ObserveInjection` and `.enableInjection()`, then press **⌘S**. InjectionIII will inject the changes; the UI updates without restarting the app.

**Limitations:** Hot reload applies to SwiftUI view code. Changes to `@main`, `App`/`Scene` setup, `AppDelegate`, or non-view code still require a full rebuild and run.

---

## 2. **Run from terminal instead of Xcode Play/Stop**

Avoid using the Run/Stop buttons in Xcode for routine “run the app” workflows:

- **Option A – Script:** From the project root run:
  ```bash
  ./build-and-run.sh
  ```
  This builds (Debug) and launches **Cursor+.app**. To “restart,” run the script again (it will build and then open the app; you can close the previous instance first or let the new one open).

- **Option B – Build once, run the .app:**  
  ```bash
  ./build.sh
  open "build/Build/Products/Debug/Cursor+.app"
  ```
  Re-run `open "build/Build/Products/Debug/Cursor+.app"` whenever you want to start the app again; use `./build.sh` only when you’ve changed code.

- **Option C – Xcode for build, Finder/terminal for run:**  
  Build in Xcode (⌘B), then run the app by double‑clicking the built `.app` in Finder or with `open` as above. You don’t need to use the Run button to launch.

This doesn’t replace a debugger, but it makes “build → run → close → run again” much faster without touching Play/Stop in Xcode.

---

## 3. **Attach to the running app for breakpoints**

You can run the app from the script (or from Finder) and still use Xcode’s debugger:

1. Run the app (e.g. via `./build-and-run.sh` or by opening the built `.app`).
2. In Xcode: **Debug → Attach to Process by PID or Name…** (or **Run → Attach to Process**).
3. Choose **Cursor+** (or the process name of your app).
4. Set breakpoints in Xcode as usual; they will hit when that code runs in the already-running app.

So: build in Xcode (or with `build.sh`), run from terminal/Finder, attach when you need breakpoints. No need to start the app with the Play button every time.

---

## 4. **SwiftUI Previews for UI-only changes**

For layout and styling, use **SwiftUI Previews** in Xcode:

- Open a view file and ensure a `#Preview { ... }` (or `PreviewProvider`) is present.
- Use the Canvas (⌥⌘↩) to see the view.
- Many edits to that view update the preview without running the full app.

Previews don’t replace running the real app (menu bar, agents, etc.) but they speed up UI iteration and reduce the number of full runs you need.

---

## 5. **Summary**

| Goal                         | Approach                                              |
|-----------------------------|--------------------------------------------------------|
| See UI changes without restart | **Inject + InjectionIII** (hot reload)                |
| Avoid Xcode Play/Stop for run | **`./build-and-run.sh`** or **`open` the built .app** |
| Breakpoints without Run      | **Attach to Process** in Xcode                        |
| Fast UI iteration            | **SwiftUI Previews** + hot reload                     |

Implementing **Inject + InjectionIII** and using **`build-and-run.sh`** (or the equivalent `build.sh` + `open`) will give you the biggest improvement: hot reload for views and a run workflow that doesn’t depend on Xcode’s Play and Stop buttons.
