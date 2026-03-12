import SwiftUI
import AppKit
import Combine

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

enum BrandStatusIcon {
    /// Menubar icon: reuses the actual application icon so dock and UI stay in sync.
    static func makeImage(size: CGFloat = 22) -> NSImage {
        let source = CursorAppIcon.load()
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

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.appState)
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

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var panel: FloatingPanel!
    let appState = AppState()
    private var cancellables = Set<AnyCancellable>()
    private var savedExpandedPanelWidth: CGFloat = 720
    private var savedExpandedPanelHeight: CGFloat?

    func applicationWillTerminate(_ notification: Notification) {
        appState.saveTabState()
        PanelFrameStorage.save(panel.frame)
        deleteScreenshotCacheOlderThan(days: 20)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let image = BrandStatusIcon.makeImage(size: 22)
        image.accessibilityDescription = "Cursor Metro"

        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit Cursor Metro", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        let iconSize: CGFloat = 22
        let view = StatusItemView(frame: NSRect(x: 0, y: 0, width: iconSize, height: iconSize))
        view.image = image
        view.contextMenu = menu
        view.onLeftClick = { [weak self] in
            self?.togglePanel()
        }
        statusItem.view = view

        panel = FloatingPanel()
        let hostingView = NSHostingView(
            rootView: PopoutView(dismiss: { [weak self] in
                self?.panel.orderOut(nil)
            })
            .environmentObject(appState)
            .environmentObject(appState.tabManager)
        )
        panel.contentView = hostingView

        appState.$isMainContentCollapsed
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] collapsed in
                self?.applyCollapsedState(collapsed)
            }
            .store(in: &cancellables)

        appState.loadModelsFromCLI()
    }

    private func applyCollapsedState(_ collapsed: Bool) {
        guard let panel = panel else { return }
        var style = panel.styleMask
        if collapsed {
            style.remove(.resizable)
            panel.styleMask = style
            savedExpandedPanelWidth = panel.frame.width
            savedExpandedPanelHeight = panel.frame.height
            panel.contentMinSize = NSSize(width: collapsedPanelWidth, height: collapsedPanelMinHeight)
            var frame = panel.frame
            frame.size.width = collapsedPanelWidth
            // Keep current height when collapsing; only width changes.
            panel.setFrame(frame, display: true, animate: true)
        } else {
            style.insert(.resizable)
            panel.styleMask = style
            panel.contentMinSize = NSSize(width: minExpandedPanelWidth, height: 400)
            var frame = panel.frame
            frame.size.width = max(minExpandedPanelWidth, savedExpandedPanelWidth)
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

    @objc func quitApp() {
        NSApp.terminate(nil)
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

    /// Only position near the menu bar when we have no saved frame (first launch).
    private func restoreOrPositionPanel() {
        if FloatingPanel.hasSavedFrame() {
            FloatingPanel.restoreSavedFrame(to: panel)
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

    static func save(_ frame: NSRect) {
        UserDefaults.standard.set(frame.origin.x, forKey: xKey)
        UserDefaults.standard.set(frame.origin.y, forKey: yKey)
        UserDefaults.standard.set(frame.size.width, forKey: widthKey)
        UserDefaults.standard.set(frame.size.height, forKey: heightKey)
    }

    static func load() -> NSRect? {
        let x = UserDefaults.standard.double(forKey: xKey)
        let y = UserDefaults.standard.double(forKey: yKey)
        let w = UserDefaults.standard.double(forKey: widthKey)
        let h = UserDefaults.standard.double(forKey: heightKey)
        guard w > 0, h > 0 else { return nil }
        return NSRect(x: x, y: y, width: w, height: h)
    }
}

class FloatingPanel: NSPanel {
    private static let defaultWidth: CGFloat = 720
    private static let defaultHeight: CGFloat = 960

    static func hasSavedFrame() -> Bool {
        guard let frame = PanelFrameStorage.load() else { return false }
        let minW: CGFloat = collapsedPanelWidth
        let maxW: CGFloat = 1400
        let minH: CGFloat = 400, maxH: CGFloat = 1600
        guard frame.size.width >= minW, frame.size.width <= maxW,
              frame.size.height >= minH, frame.size.height <= maxH else { return false }
        let onScreen = NSScreen.screens.contains { $0.frame.intersects(frame) }
        return onScreen
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
}

class AppState: ObservableObject {
    @AppStorage("workspacePath") var workspacePath: String = FileManager.default.homeDirectoryForCurrentUser.path
    @AppStorage(AppPreferences.projectsRootPathKey) var projectsRootPath: String = AppPreferences.defaultProjectsRootPath
    @Published var showSettingsSheet: Bool = false
    /// When true, main agent content is hidden and panel is resized to sidebar-only width.
    @Published var isMainContentCollapsed: Bool = false
    @Published private(set) var openProjectCount: Int = 0
    /// Available agent models (from CLI when loaded; otherwise fallback). Refreshed on launch.
    @Published var availableModels: [ModelOption] = AvailableModels.fallback
    let tabManager: TabManager
    private var cancellables = Set<AnyCancellable>()

    func loadModelsFromCLI() {
        Task { @MainActor in
            guard let models = try? await AgentRunner.listModels(), !models.isEmpty else { return }
            availableModels = models
        }
    }

    func visibleModels(disabledIds: Set<String>) -> [ModelOption] {
        AvailableModels.visible(from: availableModels, disabledIds: disabledIds)
    }

    func model(for id: String) -> ModelOption? {
        AvailableModels.model(for: id, in: availableModels)
    }

    init() {
        let manager = TabManager(loadedState: TabManagerPersistence.load())
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

    /// Presents the folder picker. If user selects a folder, updates `workspacePath` and calls `completion` with the path (so the caller can set the current tab’s workspace).
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
