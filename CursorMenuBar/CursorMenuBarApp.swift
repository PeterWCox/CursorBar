import SwiftUI
import AppKit

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

// MARK: - Legacy (Dock icon is in AppIcon.appiconset; popout uses BrandMark)

enum CursorAppIcon {
    static func load() -> NSImage? { nil }
}

enum BrandStatusIcon {
    static func makeImage() -> NSImage {
        MenuBarIcon.makeImage()
    }
}

@main
struct CursorMenuBarApp: App {
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

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var panel: FloatingPanel!
    let appState = AppState()

    func applicationWillTerminate(_ notification: Notification) {
        appState.saveTabState()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let image = BrandStatusIcon.makeImage()
        image.accessibilityDescription = "Cursor+"

        let menu = NSMenu()
        let quitItem = NSMenuItem(title: "Quit Cursor+", action: #selector(quitApp), keyEquivalent: "q")
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
    }

    @objc func togglePanel() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            positionNearStatusItem()
            panel.makeKeyAndOrderFront(nil)
        }
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
}

class FloatingPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 960),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isOpaque = false
        backgroundColor = .clear
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        level = .floating
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        contentMinSize = NSSize(width: 360, height: 400)
        contentMaxSize = NSSize(width: 1400, height: 1600)
    }

    override var canBecomeKey: Bool { true }
}

class AppState: ObservableObject {
    @AppStorage("workspacePath") var workspacePath: String = FileManager.default.homeDirectoryForCurrentUser.path
    let tabManager = TabManager(loadedState: TabManagerPersistence.load())

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
                panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            }

            if panel.runModal() == .OK, let url = panel.url {
                self.workspacePath = url.path
                completion?(url.path)
            }
        }
    }
}
