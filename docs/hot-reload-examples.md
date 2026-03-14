# Hot Reload: What You Can and Can’t Change

With **Inject + InjectionIII** enabled, these are concrete examples from the Cursor+ codebase.

---

## ✅ Change these → save (⌘S) → UI updates (no restart)

All of these are **inside** SwiftUI views that have `@ObserveInjection` and `.enableInjection()`: **PopoutView**, **DashboardView**, **SettingsView**, **SettingsModalView**.

### Layout and styling

- **Spacing and padding**  
  In `PopoutView`’s `topBar`: change `HStack(spacing: 14)` to `HStack(spacing: 20)`.  
  In `DashboardView`’s header: change `.padding(.horizontal, CursorTheme.paddingHeaderHorizontal)` to use a different value.

- **Font size and weight**  
  In `PopoutView`: change BETA/DEBUG badges from `.font(.system(size: 9, weight: .semibold))` to e.g. `size: 11` or `weight: .bold`.  
  In `DashboardView`: change `"Preview"` from `.font(.system(size: CursorTheme.fontTitle, ...))` to a fixed size like `size: 18`.

- **Colors**  
  In `DashboardView`: change `.foregroundStyle(CursorTheme.textPrimary(for: colorScheme))` to e.g. `.foregroundStyle(.blue)` or another `CursorTheme` color.  
  In `SettingsView` / `SettingsModalView`: change any `CursorTheme.*` or `.foregroundStyle(...)` usage.

- **Frame and size**  
  In `PopoutView`: change logo `.frame(height: isMainContentCollapsed ? 28 : 36)` to e.g. `24` and `32`.  
  In `SettingsView`: change `.frame(width: 480, height: 420)` to different dimensions.

- **Shapes and backgrounds**  
  In `PopoutView`: change `RoundedRectangle(cornerRadius: 4, style: .continuous)` to `cornerRadius: 8`.  
  In `SettingsModalView`: change `.clipShape(RoundedRectangle(cornerRadius: 20, ...))` or shadow/overlay modifiers.

### Copy and structure (within the same view)

- **Label text**  
  In `PopoutView`: change `Label("Settings", systemImage: "gearshape")` to `Label("Preferences", systemImage: "gearshape")`.  
  In `DashboardView`: change `Text("Preview")` to `Text("Overview")`.  
  In `SettingsView`: change section headers like `Text("Project settings")` or footer text.

- **SF Symbol names**  
  Change `Image(systemName: "square.grid.2x2")` to `"square.grid.2x2.fill"` or another symbol.  
  Change `IconButton(icon: "gearshape", ...)` to a different icon string.

- **Adding/removing/reordering view modifiers**  
  Add `.padding(8)` to a view, or an extra `.overlay { ... }`, or reorder `.font` / `.foregroundStyle` on the same view.

- **Conditional UI**  
  Change the condition that shows BETA/DEBUG badges, or tweak the `if isMainContentCollapsed { ... } else { ... }` layout (e.g. swap labels or icons).

### View structure (still inside an injectable view)

- **New subviews** (computed properties or `@ViewBuilder` functions in the same file that are used by the view’s `body`).  
  Example: add a new `private var footer: some View { ... }` and use it in `body` in **PopoutView** or **DashboardView**.

- **Changing the content of a `Section` or `List`** in **SettingsView** (e.g. add a new row or toggle), as long as you’re only changing the view hierarchy and modifiers.

---

## ❌ Change these → need full rebuild and run

### App and lifecycle

- **`CursorPlusApp`**  
  Anything in `@main struct CursorPlusApp`, e.g. adding a new `Scene` or changing `init()` (including the InjectionIII bundle load).

- **`AppDelegate`**  
  Any code in `applicationDidFinishLaunching`, menu setup, `FloatingPanel` creation, `NSHostingView(rootView: PopoutView(...))`, or other `NSApplicationDelegate` logic.

- **`FloatingPanel`**  
  Style mask, `contentMinSize`, notifications, or `performKeyEquivalent` in the panel subclass.

### Types and non-view code

- **New or changed types**  
  Adding/removing/renaming structs, classes, enums (e.g. `DashboardTab`, `SettingsPane`, `ModelOption`).  
  Changing stored properties or method signatures of `AppState`, `TabManager`, etc.

- **Non-SwiftUI code**  
  Changes in `AgentRunner`, `WorkspaceHelpers`, `ProjectSettingsStorage`, `CursorTheme` (the type/API), or any code that isn’t “inside a View’s body or its private view helpers”.

### SwiftUI views that don’t have injection

- **Views without `@ObserveInjection` and `.enableInjection()`**  
  Changing a view that never calls `.enableInjection()` (e.g. a small child view used only inside an injectable view) can sometimes still work when its parent is reinjected, but the **reliable** set is: **PopoutView**, **DashboardView**, **SettingsView**, **SettingsModalView**. For others, if hot reload doesn’t update, do a full rebuild.

### Structural view changes that are risky

- **Adding or removing `@ObserveInjection` / `.enableInjection()`**  
  That’s a one-line change inside a view, but it changes how InjectionIII sees the type; do a full build after changing injection wiring.

- **Moving a big chunk of `body` into another file** (e.g. new “SubView.swift”)  
  The new file’s type might not be injected until you add injection there and rebuild once.

---

## Quick reference

| Change | Hot reload? |
|--------|-------------|
| Text, font, color, padding, spacing, frame in PopoutView / DashboardView / SettingsView / SettingsModalView | ✅ Yes |
| New modifier or subview inside those views | ✅ Yes |
| Icon (SF Symbol) or label copy | ✅ Yes |
| `CursorPlusApp`, `AppDelegate`, `FloatingPanel` | ❌ Rebuild |
| New type or changed `AppState` / `TabManager` API | ❌ Rebuild |
| Another view file that doesn’t have `.enableInjection()` | ⚠️ Maybe; if not, rebuild |

**Usage:** Edit a view that has injection → **⌘S** → InjectionIII injects → UI updates. If it doesn’t update, run a full build and run.
