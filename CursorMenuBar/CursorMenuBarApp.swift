import SwiftUI
import AppKit

enum CursorAppIcon {
    private static let cursorAppPaths = [
        "/Applications/Cursor.app",
        FileManager.default.homeDirectoryForCurrentUser.path + "/Applications/Cursor.app",
    ]

    static func load() -> NSImage? {
        for path in cursorAppPaths where FileManager.default.fileExists(atPath: path) {
            let icnsPath = (path as NSString).appendingPathComponent("Contents/Resources/Cursor.icns")
            if let image = NSImage(contentsOfFile: icnsPath) {
                return image
            }
        }
        return nil
    }

    static func makeStatusBarImage(size: CGFloat = 18) -> NSImage {
        if let cursorIcon = load() {
            let img = NSImage(size: NSSize(width: size, height: size))
            img.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .high
            cursorIcon.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
            img.unlockFocus()
            img.isTemplate = false
            return img
        }
        return BrandStatusIcon.makeFallbackImage()
    }
}

enum BrandStatusIcon {
    static func makeImage() -> NSImage {
        CursorAppIcon.makeStatusBarImage()
    }

    static func makeFallbackImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let ringRect = rect.insetBy(dx: 3.5, dy: 3.5)
            let ring = NSBezierPath(ovalIn: ringRect)
            ring.lineWidth = 1.7
            NSColor.labelColor.setStroke()
            ring.stroke()

            let dotRect = NSRect(x: rect.midX - 1.8, y: rect.midY - 1.8, width: 3.6, height: 3.6)
            NSBezierPath(ovalIn: dotRect).fill()

            let spark = NSBezierPath()
            spark.lineWidth = 1.5
            spark.lineCapStyle = .round
            spark.move(to: NSPoint(x: rect.maxX - 5.7, y: rect.maxY - 3.9))
            spark.line(to: NSPoint(x: rect.maxX - 2.9, y: rect.maxY - 1.1))
            spark.move(to: NSPoint(x: rect.maxX - 5.7, y: rect.maxY - 1.1))
            spark.line(to: NSPoint(x: rect.maxX - 2.9, y: rect.maxY - 3.9))
            spark.stroke()

            let orbit = NSBezierPath()
            orbit.lineWidth = 1.3
            orbit.lineCapStyle = .round
            orbit.move(to: NSPoint(x: rect.minX + 2.8, y: rect.midY - 1.2))
            orbit.curve(
                to: NSPoint(x: rect.midX + 5.2, y: rect.minY + 3.1),
                controlPoint1: NSPoint(x: rect.minX + 5.0, y: rect.minY + 1.8),
                controlPoint2: NSPoint(x: rect.midX + 1.8, y: rect.minY + 2.2)
            )
            orbit.stroke()

            return true
        }
        image.isTemplate = true
        return image
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

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var panel: FloatingPanel!
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = BrandStatusIcon.makeImage()
            button.image?.accessibilityDescription = "Cursor+"
            button.action = #selector(togglePanel)
            button.target = self
        }

        panel = FloatingPanel()
        let hostingView = NSHostingView(
            rootView: PopoutView(dismiss: { [weak self] in
                self?.panel.orderOut(nil)
            })
            .environmentObject(appState)
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
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 780),
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
        contentMaxSize = NSSize(width: 900, height: 1200)
    }

    override var canBecomeKey: Bool { true }
}

class AppState: ObservableObject {
    @AppStorage("workspacePath") var workspacePath: String = FileManager.default.homeDirectoryForCurrentUser.path

    var workspaceDisplayName: String {
        guard !workspacePath.isEmpty else { return "" }
        let url = URL(fileURLWithPath: workspacePath)
        if workspacePath == FileManager.default.homeDirectoryForCurrentUser.path {
            return "~/"
        }
        return url.lastPathComponent.isEmpty ? url.deletingLastPathComponent().lastPathComponent : url.lastPathComponent
    }

    func changeWorkspace() {
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
            }
        }
    }
}
