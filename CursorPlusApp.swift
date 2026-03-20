import SwiftUI
import AppKit
import Carbon
import Combine
#if DEBUG
import Inject
#endif

// MARK: - Menu bar icon (template, adapts to light/dark menu bar)

enum MenuBarIcon {
    static func makeImage(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let s = rect.width
            let pad: CGFloat = s * 0.18
            let inner = rect.insetBy(dx: pad, dy: pad)

            // Ring
            let ringRect = inner.insetBy(dx: inner.width * 0.08, dy: inner.height * 0.08)
            let ring = NSBezierPath(ovalIn: ringRect)
            ring.lineWidth = max(1, s * 0.09)
            NSColor.labelColor.setStroke()
            ring.stroke()

            // Center dot
            let dotR = s * 0.055
            let dotRect = NSRect(x: rect.midX - dotR, y: rect.midY - dotR, width: dotR * 2, height: dotR * 2)
            NSColor.labelColor.setFill()
            NSBezierPath(ovalIn: dotRect).fill()

            // Spark (X) top-right
            let sparkCx = rect.maxX - pad - s * 0.08
            let sparkCy = rect.minY + pad + s * 0.22
            let d = s * 0.08
            let spark = NSBezierPath()
            spark.lineWidth = max(1, s * 0.08)
            spark.lineCapStyle = .round
            spark.move(to: NSPoint(x: sparkCx - d, y: sparkCy - d))
            spark.line(to: NSPoint(x: sparkCx + d, y: sparkCy + d))
            spark.move(to: NSPoint(x: sparkCx - d, y: sparkCy + d))
            spark.line(to: NSPoint(x: sparkCx + d, y: sparkCy - d))
            NSColor.labelColor.setStroke()
            spark.stroke()

            // Plus (bottom-right)
            let plusCx = rect.maxX - pad - s * 0.2
            let plusCy = rect.minY + pad + s * 0.2
            let hw = s * 0.12
            let thick = max(1, s * 0.08)
            NSColor.labelColor.setFill()
            NSBezierPath(rect: NSRect(x: plusCx - hw, y: plusCy - thick/2, width: hw * 2, height: thick)).fill()
            NSBezierPath(rect: NSRect(x: plusCx - thick/2, y: plusCy - hw, width: thick, height: hw * 2)).fill()

            return true
        }
        image.isTemplate = true
        return image
    }
}

// MARK: - Legacy (Dock icon is in AppIcon.appiconset; popout uses AppIconImage)

enum CursorAppIcon {
    static func load() -> NSImage {
        if let image = NSApplication.shared.applicationIconImage {
            return image
        }
        if let image = NSImage(named: NSImage.applicationIconName) {
            return image
        }
        return MenuBarIcon.makeImage(size: 128)
    }
}

struct BrandAppIconView: View {
    let size: CGFloat

    var body: some View {
        Image(nsImage: CursorAppIcon.load())
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}

/// Computes the total number of tasks in the "review" stage (agent finished, awaiting user) across all open projects.
enum TasksInReviewCount {
    /// Normalize path so "~/foo", "/Users/me/foo", and "/Users/me/foo/" all match when comparing tab vs project paths.
    private static func normalizedPath(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return (expanded as NSString).standardizingPath
    }

    @MainActor
    static func count(tabManager: TabManager, projectTasksStore: ProjectTasksStore) -> Int {
        let paths = tabManager.projects.map(\.path)
        return paths.reduce(0) { total, workspacePath in
            let tasks = projectTasksStore.tasks(for: workspacePath).filter { $0.taskState == .inProgress }
            let linkedStatuses = linkedStatusesForWorkspace(workspacePath, tabManager: tabManager, projectTasksStore: projectTasksStore)
            // Only review (agent finished); exclude processing, stopped, todo, none.
            return total + tasks.filter { linkedStatuses[$0.id] == .review }.count
        }
    }

    @MainActor
    private static func linkedTaskState(for tab: AgentTab, taskStatesByID: [UUID: TaskState]) -> AgentTaskState? {
        guard let taskID = tab.linkedTaskID else { return nil }
        guard let taskState = taskStatesByID[taskID] else { return nil }
        if taskState == .backlog { return .none }
        if tab.isRunning { return .processing }
        if tab.turns.last?.displayState == .stopped { return .stopped }
        if tab.turns.last?.displayState == .completed { return .review }
        return .todo
    }

    @MainActor
    private static func linkedTaskState(for savedTab: SavedAgentTab, taskStatesByID: [UUID: TaskState]) -> AgentTaskState? {
        guard let taskID = savedTab.linkedTaskID else { return nil }
        guard let taskState = taskStatesByID[taskID] else { return nil }
        if taskState == .backlog { return .none }
        if savedTab.restoredLastTurnState == .stopped { return .stopped }
        if savedTab.restoredLastTurnState == .completed { return .review }
        return .todo
    }

    @MainActor
    private static func linkedStatusesForWorkspace(_ workspacePath: String, tabManager: TabManager, projectTasksStore: ProjectTasksStore) -> [UUID: AgentTaskState] {
        let taskStatesByID = projectTasksStore.taskStatesByID(for: workspacePath)
        let normalized = normalizedPath(workspacePath)
        var result: [UUID: AgentTaskState] = [:]
        for savedTab in tabManager.recentlyClosedTabs where normalizedPath(savedTab.workspacePath) == normalized {
            guard let taskID = savedTab.linkedTaskID else { continue }
            result[taskID] = linkedTaskState(for: savedTab, taskStatesByID: taskStatesByID)
        }
        for tab in tabManager.tabs where normalizedPath(tab.workspacePath) == normalized {
            guard let taskID = tab.linkedTaskID else { continue }
            result[taskID] = linkedTaskState(for: tab, taskStatesByID: taskStatesByID)
        }
        return result
    }
}

enum BrandStatusIcon {
    /// Menubar icon: uses the dedicated branded icon asset for crisp small-size rendering.
    static func makeImage(size: CGFloat = 22) -> NSImage {
        let source = NSImage(named: "AppIconImage") ?? CursorAppIcon.load()
        let target = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        return target
    }
}

@main
struct CursorPlusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        #if DEBUG
        Bundle(path: "/Applications/InjectionIII.app/Contents/Resources/macOSInjection.bundle")?.load()
        #endif
    }

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.appState)
                .environmentObject(appDelegate.projectTasksStore)
                .environmentObject(appDelegate.projectSettingsStore)
        }
    }
}

/// Status bar view that shows the icon, toggles panel on left click, and shows a context menu on right click.
private final class StatusItemView: NSView {
    var image: NSImage?
    var onLeftClick: (() -> Void)?
    var contextMenu: NSMenu?

    override func draw(_ dirtyRect: NSRect) {
        guard let image = image else { return }
        let size = min(bounds.width, bounds.height, 18)
        let rect = NSRect(
            x: (bounds.width - size) / 2,
            y: (bounds.height - size) / 2,
            width: size,
            height: size
        )
        image.draw(in: rect)
    }

    override func mouseDown(with event: NSEvent) {
        if event.type == .rightMouseDown {
            showMenu()
        } else {
            onLeftClick?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        showMenu()
    }

    private func showMenu() {
        guard let contextMenu = contextMenu else { return }
        let location = NSPoint(x: bounds.midX, y: bounds.minY)
        contextMenu.popUp(positioning: nil, at: location, in: self)
    }
}

/// Width of the panel when collapsed to sidebar-only (title bar + tab sidebar).
private let collapsedPanelWidth: CGFloat = 310
/// Minimum height when collapsed so the window can shrink and avoid empty space below the sidebar.
private let collapsedPanelMinHeight: CGFloat = 280
/// Minimum width when expanded; prevents shrinking below a usable size (e.g. comfortable on 14" MacBook).
private let minExpandedPanelWidth: CGFloat = 440

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var panel: FloatingPanel!
    let appState = AppState()
    let projectTasksStore = ProjectTasksStore()
    let projectSettingsStore = ProjectSettingsStore()
    private var cancellables = Set<AnyCancellable>()
    private var requestNewTaskObserver: NSObjectProtocol?
    private var tasksStorageObserver: NSObjectProtocol?
    private var openInBrowserKeyMonitor: Any?
    private var openInCursorKeyMonitor: Any?
    private var savedExpandedPanelWidth: CGFloat = 720
    private var savedExpandedPanelHeight: CGFloat?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard appState.tabManager.runningAgentCount > 0 else {
            return .terminateNow
        }
        let alert = NSAlert()
        alert.messageText = "Agents Are Running"
        alert.informativeText = "One or more agents are still processing. Quit anyway? Their work will be interrupted."
        alert.addButton(withTitle: "Quit Anyway")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        NSApp.reply(toApplicationShouldTerminate: response == .alertFirstButtonReturn)
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.saveTabState()
        PanelFrameStorage.save(panel.frame)
        deleteScreenshotCacheOlderThan(days: 20)
    }

    func applicationDidResignActive(_ notification: Notification) {
        // Persist panel frame when user hides app (Cmd+H) or switches away so reopen restores current size.
        if panel.isVisible {
            PanelFrameStorage.save(panel.frame)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let image = BrandStatusIcon.makeImage(size: 22)
        image.accessibilityDescription = "Cursor Metro"

        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let centerPanelItem = NSMenuItem(title: "Center Popup", action: #selector(centerPanelFromMenu), keyEquivalent: "0")
        centerPanelItem.target = self
        menu.addItem(centerPanelItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        let iconSize: CGFloat = 22
        let view = StatusItemView(frame: NSRect(x: 0, y: 0, width: iconSize, height: iconSize))
        view.image = image
        view.toolTip = "Cursor Metro"
        view.contextMenu = menu
        view.onLeftClick = { [weak self] in
            self?.togglePanel()
        }
        statusItem.view = view

        panel = FloatingPanel()
        if let expanded = PanelFrameStorage.loadExpandedSize() {
            savedExpandedPanelWidth = expanded.width
            savedExpandedPanelHeight = expanded.height
        }
        let hostingView = NSHostingView(
            rootView: PopoutView(dismiss: { [weak self] in
                self?.panel.orderOut(nil)
            })
            .environmentObject(appState)
            .environmentObject(projectTasksStore)
            .environmentObject(projectSettingsStore)
            .environmentObject(appState.tabManager)
        )
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = CursorTheme.radiusWindow
        hostingView.layer?.masksToBounds = true
        panel.contentView = hostingView

        appState.$isMainContentCollapsed
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] collapsed in
                self?.applyCollapsedState(collapsed)
            }
            .store(in: &cancellables)

        appState.tabManager.$tabs
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshDockBadge()
            }
            .store(in: &cancellables)
        appState.tabManager.tabStateDidChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshDockBadge()
            }
            .store(in: &cancellables)

        tasksStorageObserver = NotificationCenter.default.addObserver(
            forName: ProjectTasksStorage.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshDockBadge()
        }

        requestNewTaskObserver = NotificationCenter.default.addObserver(
            forName: FloatingPanel.requestNewTaskNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.appState.requestShowTasksAndNewTask = true
        }

        openInBrowserKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let isCmdO = event.modifierFlags.contains(.command)
                && event.charactersIgnoringModifiers?.lowercased() == "o"
            if isCmdO {
                self.handleOpenInBrowser()
                return nil
            }
            return event
        }

        openInCursorKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isCmdPeriod = mods == .command && event.charactersIgnoringModifiers == "."
            if isCmdPeriod {
                self.handleOpenInCursor()
                return nil
            }
            return event
        }

        appState.loadModelsFromCLI()
        refreshDockBadge()
    }

    func applicationWillUpdate(_ notification: Notification) {
        // Steer Cmd+O (File > Open) to our "Open in Browser" so the system doesn't show the file picker when no project or URL is set.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let fileMenu = NSApplication.shared.mainMenu?.item(withTitle: "File")
            let openItem = fileMenu?.submenu?.item(withTitle: "Open…")
            ?? fileMenu?.submenu?.item(withTitle: "Open")
            if let openItem {
                openItem.target = self
                openItem.action = #selector(self.handleOpenInBrowser)
            }
        }
    }

    @objc func handleOpenInBrowser() {
        if !panel.isVisible {
            togglePanel()
        }
        appState.requestOpenInBrowser = true
    }

    @objc func handleOpenInCursor() {
        if !panel.isVisible {
            togglePanel()
        }
        appState.requestOpenInCursor = true
    }

    private func applyCollapsedState(_ collapsed: Bool) {
        guard let panel = panel else { return }
        var style = panel.styleMask
        let preserveTrailingEdge = UserDefaults.standard.bool(forKey: AppPreferences.sidebarOnRightKey)
        if collapsed {
            style.remove(.resizable)
            panel.styleMask = style
            savedExpandedPanelWidth = panel.frame.width
            savedExpandedPanelHeight = panel.frame.height
            panel.contentMinSize = NSSize(width: collapsedPanelWidth, height: collapsedPanelMinHeight)
            var frame = panel.frame
            let trailingEdgeX = frame.maxX
            frame.size.width = collapsedPanelWidth
            if preserveTrailingEdge {
                frame.origin.x = trailingEdgeX - frame.width
            }
            // Keep current height when collapsing; only width changes.
            panel.setFrame(frame, display: true, animate: true)
        } else {
            style.insert(.resizable)
            panel.styleMask = style
            panel.contentMinSize = NSSize(width: minExpandedPanelWidth, height: 400)
            var frame = panel.frame
            let trailingEdgeX = frame.maxX
            frame.size.width = max(minExpandedPanelWidth, savedExpandedPanelWidth)
            if preserveTrailingEdge {
                frame.origin.x = trailingEdgeX - frame.width
            }
            if let h = savedExpandedPanelHeight, h >= 400 {
                frame.size.height = h
            }
            savedExpandedPanelHeight = nil
            panel.setFrame(frame, display: true, animate: true)
        }
    }

    @objc func togglePanel() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            restoreOrPositionPanel()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    @objc func showSettings() {
        if !panel.isVisible {
            togglePanel()
        }
        appState.showSettingsSheet = true
    }

    @objc func centerPanelFromMenu() {
        NSApp.activate(ignoringOtherApps: true)
        centerPanelOnPreferredScreen()
        panel.makeKeyAndOrderFront(nil)
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }

    /// Updates the dock icon badge to show how many tasks are in the review stage (like unread count).
    private func refreshDockBadge() {
        let count = TasksInReviewCount.count(tabManager: appState.tabManager, projectTasksStore: projectTasksStore)
        NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Launch or reactivate from Dock: show the panel
        if !panel.isVisible {
            togglePanel()
        }
        return true
    }

    private func positionNearStatusItem() {
        guard let button = statusItem.button,
              let buttonWindow = button.window else { return }
        let screenFrame = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(screenFrame)
        let x = screenRect.midX - panel.frame.width / 2
        let y = screenRect.minY - panel.frame.height - 4
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func centerPanelOnPreferredScreen() {
        guard let screen = preferredPanelScreen() else { return }
        let visibleFrame = screen.visibleFrame
        var frame = panel.frame
        frame.origin.x = visibleFrame.midX - frame.width / 2
        frame.origin.y = visibleFrame.midY - frame.height / 2
        panel.setFrame(frame, display: true, animate: true)
    }

    private func ensurePanelIsVisibleOnScreen() {
        guard let screen = bestScreenForPanelFrame() ?? preferredPanelScreen() else { return }
        let visibleFrame = screen.visibleFrame
        var frame = panel.frame

        if frame.width > visibleFrame.width {
            frame.size.width = visibleFrame.width
        }
        if frame.height > visibleFrame.height {
            frame.size.height = visibleFrame.height
        }

        frame.origin.x = min(max(frame.origin.x, visibleFrame.minX), visibleFrame.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, visibleFrame.minY), visibleFrame.maxY - frame.height)

        panel.setFrame(frame, display: false)
    }

    private func bestScreenForPanelFrame() -> NSScreen? {
        let frame = panel.frame
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }

        return screens.max { lhs, rhs in
            intersectionArea(frame, lhs.visibleFrame) < intersectionArea(frame, rhs.visibleFrame)
        }
    }

    private func intersectionArea(_ lhs: NSRect, _ rhs: NSRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }

    private func preferredPanelScreen() -> NSScreen? {
        if let screen = panel.screen {
            return screen
        }
        if let screen = statusItem.button?.window?.screen {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    /// Only position near the menu bar when we have no saved frame (first launch).
    private func restoreOrPositionPanel() {
        if FloatingPanel.hasSavedFrame() {
            FloatingPanel.restoreSavedFrame(to: panel)
            ensurePanelIsVisibleOnScreen()
            if panel.frame.width <= collapsedPanelWidth + 20 {
                appState.isMainContentCollapsed = true
                panel.contentMinSize = NSSize(width: collapsedPanelWidth, height: 400)
            } else {
                appState.isMainContentCollapsed = false
                // Keep agent tabs sidebar full width: never allow window narrower than sidebar + min agent area.
                if panel.frame.width < minExpandedPanelWidth {
                    var frame = panel.frame
                    frame.size.width = minExpandedPanelWidth
                    panel.setFrame(frame, display: false)
                }
                panel.contentMinSize = NSSize(width: minExpandedPanelWidth, height: 400)
            }
        } else {
            positionNearStatusItem()
        }
    }
}

// MARK: - Panel frame persistence

private enum PanelFrameStorage {
    static let xKey = "panelFrameX"
    static let yKey = "panelFrameY"
    static let widthKey = "panelFrameWidth"
    static let heightKey = "panelFrameHeight"
    static let expandedWidthKey = "panelFrameExpandedWidth"
    static let expandedHeightKey = "panelFrameExpandedHeight"

    /// Saves the current frame. When the frame is expanded (width > collapsed + 20), also saves it as the preferred expanded size for next session.
    static func save(_ frame: NSRect) {
        UserDefaults.standard.set(frame.origin.x, forKey: xKey)
        UserDefaults.standard.set(frame.origin.y, forKey: yKey)
        UserDefaults.standard.set(frame.size.width, forKey: widthKey)
        UserDefaults.standard.set(frame.size.height, forKey: heightKey)
        if frame.size.width > collapsedPanelWidth + 20 {
            UserDefaults.standard.set(frame.size.width, forKey: expandedWidthKey)
            UserDefaults.standard.set(frame.size.height, forKey: expandedHeightKey)
        }
    }

    static func load() -> NSRect? {
        let x = UserDefaults.standard.double(forKey: xKey)
        let y = UserDefaults.standard.double(forKey: yKey)
        let w = UserDefaults.standard.double(forKey: widthKey)
        let h = UserDefaults.standard.double(forKey: heightKey)
        guard w > 0, h > 0 else { return nil }
        return NSRect(x: x, y: y, width: w, height: h)
    }

    /// Returns (width, height) for the preferred expanded size from last session, or nil if not set.
    static func loadExpandedSize() -> (width: CGFloat, height: CGFloat)? {
        let w = UserDefaults.standard.double(forKey: expandedWidthKey)
        let h = UserDefaults.standard.double(forKey: expandedHeightKey)
        guard w >= CGFloat(minExpandedPanelWidth), w <= 1400, h >= 400, h <= 1600 else { return nil }
        return (CGFloat(w), CGFloat(h))
    }
}

class FloatingPanel: NSPanel {
    private static let defaultWidth: CGFloat = 720
    private static let defaultHeight: CGFloat = 960

    /// Returns true if we have valid saved dimensions. Caller should then restore and use ensurePanelIsVisibleOnScreen() to clamp if off-screen.
    static func hasSavedFrame() -> Bool {
        guard let frame = PanelFrameStorage.load() else { return false }
        let minW: CGFloat = collapsedPanelWidth
        let maxW: CGFloat = 1400
        let minH: CGFloat = 400, maxH: CGFloat = 1600
        return frame.size.width >= minW && frame.size.width <= maxW
            && frame.size.height >= minH && frame.size.height <= maxH
    }

    static func restoreSavedFrame(to panel: NSPanel) {
        guard let frame = PanelFrameStorage.load() else { return }
        panel.setFrame(frame, display: false)
    }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.defaultWidth, height: Self.defaultHeight),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        level = .floating
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        contentMinSize = NSSize(width: minExpandedPanelWidth, height: 400)
        contentMaxSize = NSSize(width: 1400, height: 1600)
        if Self.hasSavedFrame(), let frame = PanelFrameStorage.load() {
            setFrame(frame, display: false)
        }
    }

    override func orderOut(_ sender: Any?) {
        PanelFrameStorage.save(frame)
        super.orderOut(sender)
    }

    override var canBecomeKey: Bool { true }

    /// So Cmd+T always creates/focuses a new task when the panel is key (SwiftUI shortcuts can miss when focus is in list/text). Cmd+Shift+T is left for Reopen Closed Tab.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.contains(.command), !mods.contains(.shift) else { return super.performKeyEquivalent(with: event) }
        let key = event.charactersIgnoringModifiers?.lowercased()
        if key == "t" {
            NotificationCenter.default.post(name: FloatingPanel.requestNewTaskNotification, object: self)
            return true
        }
        // US `[` / `]` keys; also match ANSI virtual keys when Option/layout changes charactersIgnoringModifiers.
        if key == "[" || event.keyCode == UInt16(kVK_ANSI_LeftBracket) {
            NotificationCenter.default.post(
                name: FloatingPanel.cycleSidebarWorkspaceNotification,
                object: self,
                userInfo: [FloatingPanel.cycleSidebarDirectionUserInfoKey: -1]
            )
            return true
        }
        if key == "]" || event.keyCode == UInt16(kVK_ANSI_RightBracket) {
            NotificationCenter.default.post(
                name: FloatingPanel.cycleSidebarWorkspaceNotification,
                object: self,
                userInfo: [FloatingPanel.cycleSidebarDirectionUserInfoKey: 1]
            )
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    static let requestNewTaskNotification = Notification.Name("FloatingPanelRequestNewTask")
    static let cycleSidebarWorkspaceNotification = Notification.Name("FloatingPanelCycleSidebarWorkspace")
    static let cycleSidebarDirectionUserInfoKey = "direction"
}

final class HangDiagnostics {
    static let shared = HangDiagnostics()

    static var logURL: URL {
        shared.fileURL
    }

    private let queue = DispatchQueue(label: "CursorPlus.HangDiagnostics")
    private let fileURL: URL
    private let formatter = ISO8601DateFormatter()
    private var isStarted = false
    private var watchdogTimer: DispatchSourceTimer?
    private var lastHeartbeatAt = Date()
    private var lastStallLoggedAt: Date?
    private var snapshot: [String: String] = [:]

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CursorPlus", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("hang-diagnostics.log")
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func start() {
        queue.async {
            guard !self.isStarted else { return }
            self.isStarted = true
            self.appendLocked(event: "diagnostics-started", metadata: [
                "logPath": self.fileURL.path
            ])
            self.startWatchdogLocked()
            DispatchQueue.main.async {
                self.scheduleHeartbeat()
            }
        }
    }

    func updateSnapshot(_ snapshot: [String: String]) {
        queue.async {
            self.snapshot = snapshot
        }
    }

    func record(_ event: String, metadata: [String: String] = [:]) {
        queue.async {
            self.appendLocked(event: event, metadata: metadata)
        }
    }

    private func scheduleHeartbeat() {
        queue.async {
            self.lastHeartbeatAt = Date()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.scheduleHeartbeat()
        }
    }

    private func startWatchdogLocked() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            self?.checkForStallLocked()
        }
        watchdogTimer = timer
        timer.resume()
    }

    private func checkForStallLocked() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastHeartbeatAt)
        guard elapsed >= 2.0 else { return }
        if let lastStallLoggedAt, now.timeIntervalSince(lastStallLoggedAt) < 8.0 {
            return
        }
        lastStallLoggedAt = now

        var metadata = snapshot
        metadata["stallSeconds"] = String(format: "%.2f", elapsed)
        appendLocked(event: "main-thread-stall-detected", metadata: metadata)
    }

    private func appendLocked(event: String, metadata: [String: String]) {
        let timestamp = formatter.string(from: Date())
        let payload = metadata
            .sorted { $0.key < $1.key }
            .map { key, value in
                let sanitized = value.replacingOccurrences(of: "\n", with: "\\n")
                return "\(key)=\(sanitized)"
            }
            .joined(separator: " ")
        let line = payload.isEmpty ? "\(timestamp) \(event)\n" : "\(timestamp) \(event) \(payload)\n"
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        guard let data = line.data(using: .utf8) else { return }
        do {
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

class AppState: ObservableObject {
    @AppStorage("workspacePath") var workspacePath: String = FileManager.default.homeDirectoryForCurrentUser.path
    @AppStorage(AppPreferences.projectsRootPathKey) var projectsRootPath: String = AppPreferences.defaultProjectsRootPath
    @Published var showSettingsSheet: Bool = false
    /// Incremented when tasks are updated (e.g. completed) so the sidebar can hide agent tabs for completed tasks.
    @Published var taskListRevision: UUID = UUID()
    /// When true, PopoutView should run "Open in Browser" (used when File > Open / Cmd+O is triggered so we handle it instead of the system file picker).
    @Published var requestOpenInBrowser: Bool = false
    /// When true, PopoutView should open the current project in Cursor (triggered by Cmd+.).
    @Published var requestOpenInCursor: Bool = false
    /// When true, PopoutView should show Tasks and focus new-task input (triggered by Cmd+T from panel or menu).
    @Published var requestShowTasksAndNewTask: Bool = false
    /// When true, main agent content is hidden and panel is resized to sidebar-only width.
    @Published var isMainContentCollapsed: Bool = false
    @Published private(set) var openProjectCount: Int = 0
    /// Available agent models keyed by provider; falls back to provider defaults until loaded.
    @Published private var availableModelsByProvider: [AgentProviderID: [ModelOption]] = [
        .cursor: AgentProviders.fallbackModels(for: .cursor)
    ]
    let tabManager: TabManager
    private var cancellables = Set<AnyCancellable>()

    var selectedAgentProviderID: AgentProviderID {
        .cursor
    }

    var availableModels: [ModelOption] {
        availableModels(for: selectedAgentProviderID)
    }

    func availableModels(for providerID: AgentProviderID) -> [ModelOption] {
        availableModelsByProvider[providerID] ?? AgentProviders.fallbackModels(for: providerID)
    }

    func defaultModelID(for providerID: AgentProviderID) -> String {
        AgentProviders.defaultModelID(for: providerID)
    }

    func loadModelsFromCLI() {
        loadModels(for: selectedAgentProviderID)
    }

    func loadModels(for providerID: AgentProviderID) {
        let provider = AgentProviders.provider(for: providerID)
        Task { @MainActor in
            guard let models = try? await provider.listModels(), !models.isEmpty else { return }
            availableModelsByProvider[providerID] = models
        }
    }

    func visibleModels(disabledIds: Set<String>) -> [ModelOption] {
        visibleModels(for: selectedAgentProviderID, disabledIds: disabledIds)
    }

    func visibleModels(for providerID: AgentProviderID, disabledIds: Set<String>) -> [ModelOption] {
        AvailableModels.visible(from: availableModels(for: providerID), disabledIds: disabledIds)
    }

    func model(for id: String, providerID: AgentProviderID? = nil) -> ModelOption? {
        let resolvedProviderID = providerID ?? selectedAgentProviderID
        return AvailableModels.model(for: id, in: availableModels(for: resolvedProviderID))
    }

    func isDefaultShown(modelId: String, for providerID: AgentProviderID) -> Bool {
        AgentProviders.defaultShownModelIds(for: providerID).contains(modelId)
    }

    init() {
        HangDiagnostics.shared.start()
        let loadedState = TabManagerPersistence.load()
        let manager = TabManager(loadedState: loadedState)
        tabManager = manager
        openProjectCount = manager.openProjectCount

        manager.$projects
            .map(\.count)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.openProjectCount = $0
            }
            .store(in: &cancellables)
    }

    func saveTabState() {
        tabManager.saveState()
    }

    /// Call when tasks are updated (e.g. toggled completed) so the sidebar refreshes and can hide completed-task agent tabs.
    func notifyTasksDidUpdate() {
        taskListRevision = UUID()
        HangDiagnostics.shared.record("tasks-did-update")
    }

    var workspaceDisplayName: String {
        workspaceDisplayName(for: workspacePath)
    }

    func workspaceDisplayName(for path: String) -> String {
        guard !path.isEmpty else { return "" }
        let url = URL(fileURLWithPath: path)
        if path == FileManager.default.homeDirectoryForCurrentUser.path {
            return "~/"
        }
        return url.lastPathComponent.isEmpty ? url.deletingLastPathComponent().lastPathComponent : url.lastPathComponent
    }

    /// Presents the folder picker. If user selects a folder, updates `workspacePath` and calls `completion` with the path (so the caller can set the current tab's workspace).
    func changeWorkspace(completion: ((String) -> Void)? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = true
            panel.title = "Select Workspace"
            panel.message = "Choose the repository directory where Cursor agent will work."

            if !self.workspacePath.isEmpty && FileManager.default.fileExists(atPath: self.workspacePath) {
                panel.directoryURL = URL(fileURLWithPath: self.workspacePath)
            } else {
                panel.directoryURL = URL(fileURLWithPath: AppPreferences.resolvedProjectsRootPath(self.projectsRootPath))
            }

            if panel.runModal() == .OK, let url = panel.url {
                let path = url.path
                self.workspacePath = path
                // Defer completion to next run loop so the modal is fully dismissed and UI updates reliably.
                DispatchQueue.main.async {
                    completion?(path)
                }
            }
        }
    }
}
