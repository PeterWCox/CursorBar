import SwiftUI
import AppKit
import SwiftTerm
import Darwin

#if os(macOS)

/// SwiftUI wrapper for SwiftTerm's LocalProcessTerminalView. Runs a shell in the given workspace directory.
struct EmbeddedTerminalView: NSViewRepresentable {
    /// Container that draws a terminal-like background and insets the terminal content so text doesn't hug the edges.
    /// Forwards first responder and mouse clicks to the embedded terminal so Control+C (SIGINT) and other keys reach the process.
    final class TerminalContainerView: NSView {
        static let contentInset: CGFloat = 18
        weak var embeddedTerminal: LocalProcessTerminalView?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.backgroundColor = NSColor.black.cgColor
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var acceptsFirstResponder: Bool { true }

        override func becomeFirstResponder() -> Bool {
            guard let terminal = embeddedTerminal ?? subviews.first as? LocalProcessTerminalView else { return false }
            return window?.makeFirstResponder(terminal) ?? false
        }

        override func mouseDown(with event: NSEvent) {
            if let terminal = embeddedTerminal ?? subviews.first as? LocalProcessTerminalView {
                window?.makeFirstResponder(terminal)
            }
            super.mouseDown(with: event)
        }
    }
    let workspacePath: String
    /// When true, the terminal view is made first responder so it receives key events (e.g. Control+C).
    var isSelected: Bool = true
    /// If set, run this command in the shell at startup (e.g. project startup script). Runs in workspace directory.
    var initialCommand: String? = nil

    func makeNSView(context: Context) -> TerminalContainerView {
        let container = TerminalContainerView(frame: .zero)
        container.translatesAutoresizingMaskIntoConstraints = false

        let terminal = LocalProcessTerminalView(frame: .zero)
        terminal.caretColor = .systemGreen
        terminal.getTerminal().setCursorStyle(.steadyBlock)
        terminal.processDelegate = context.coordinator
        terminal.translatesAutoresizingMaskIntoConstraints = false

        let dir = projectRootForTerminal(workspacePath: workspacePath)
        let cmd = initialCommand?.trimmingCharacters(in: .whitespacesAndNewlines)
        let shell = Self.userShellForTerminal
        let execName = "-" + (shell as NSString).lastPathComponent
        terminal.startProcess(
            executable: shell,
            args: [],
            environment: nil,
            execName: execName,
            currentDirectory: dir
        )

        context.coordinator.terminalView = terminal
        container.embeddedTerminal = terminal
        container.addSubview(terminal)
        let inset = TerminalContainerView.contentInset
        NSLayoutConstraint.activate([
            terminal.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
            terminal.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset),
            terminal.topAnchor.constraint(equalTo: container.topAnchor, constant: inset),
            terminal.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -inset),
        ])
        // Clear the terminal after the shell has started so it opens with a clean screen (avoids
        // repeated prompt lines from layout/resize when the app is reopened and the terminal is first to focus).
        // When an initial command is provided, run it inside the user's login shell so PATH managers
        // like nvm/asdf behave the same as when the user types the command manually.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak terminal] in
            if let cmd = cmd, !cmd.isEmpty {
                terminal?.send(txt: "clear\n\(cmd)\n")
            } else {
                terminal?.send(txt: "clear\n")
            }
        }
        return container
    }

    func updateNSView(_ nsView: TerminalContainerView, context: Context) {
        guard isSelected else { return }
        // Focus the container once so the terminal receives key events (Control+C/SIGINT, etc.). Only set when
        // not already first responder to avoid repeated focus/layout cycles that can cause prompt redraws.
        DispatchQueue.main.async {
            guard nsView.window?.firstResponder !== nsView,
                  nsView.window?.firstResponder !== nsView.embeddedTerminal else { return }
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        var terminalView: LocalProcessTerminalView?
        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func processTerminated(source: TerminalView, exitCode: Int32?) {}
    }
}

// MARK: - Persistent terminal store (outlives SwiftUI view lifecycle)

/// Holds terminal container views keyed by tab id so shell sessions survive when
/// MultiTerminalHostView is recreated (e.g. on tab/project switch). Must be used from main thread.
final class TerminalHostStore {
    private var containers: [UUID: EmbeddedTerminalView.TerminalContainerView] = [:]

    var containerIds: [UUID] { Array(containers.keys) }

    func container(for id: UUID) -> EmbeddedTerminalView.TerminalContainerView? {
        containers[id]
    }

    func setContainer(_ container: EmbeddedTerminalView.TerminalContainerView?, for id: UUID) {
        if let container = container {
            containers[id] = container
        } else {
            containers.removeValue(forKey: id)
        }
    }

    func removeContainers(where predicate: (UUID) -> Bool) {
        for id in containers.keys where predicate(id) {
            containers[id]?.removeFromSuperview()
            containers.removeValue(forKey: id)
        }
    }
}

// MARK: - Persistent multi-terminal host (keeps all shell sessions alive when switching tabs)

/// Hosts one terminal session per tab in a single NSView. Uses TerminalHostStore so sessions
/// persist when the view is recreated (e.g. switching to another terminal and back).
struct MultiTerminalHostView: NSViewRepresentable {
    /// (id, workspacePath, initialCommand) for each tab. Order preserved. initialCommand runs at startup when non-nil.
    var tabs: [(id: UUID, workspacePath: String, initialCommand: String?)]
    var selectedID: UUID?
    /// Store that outlives this view; holds containers so shells survive view recreation.
    var store: TerminalHostStore

    func makeNSView(context: Context) -> MultiTerminalHostContainerView {
        let host = MultiTerminalHostContainerView(frame: .zero)
        host.translatesAutoresizingMaskIntoConstraints = false
        syncTerminals(host: host, context: context)
        return host
    }

    func updateNSView(_ host: MultiTerminalHostContainerView, context: Context) {
        syncTerminals(host: host, context: context)
    }

    private func syncTerminals(host: MultiTerminalHostContainerView, context: Context) {
        let coordinator = context.coordinator
        let currentIDs = Set(tabs.map(\.id))
        // Remove terminals for tabs that no longer exist (closed); remove from host and store
        for id in store.containerIds where !currentIDs.contains(id) {
            if let container = store.container(for: id) {
                container.removeFromSuperview()
                store.setContainer(nil, for: id)
            }
        }
        // Add or update terminals: get from store or create, attach to host, show/hide by selection
        for item in tabs {
            let container: EmbeddedTerminalView.TerminalContainerView
            if let existing = store.container(for: item.id) {
                container = existing
                existing.embeddedTerminal?.processDelegate = coordinator
            } else {
                container = makeTerminalContainer(workspacePath: item.workspacePath, initialCommand: item.initialCommand, coordinator: coordinator)
                store.setContainer(container, for: item.id)
            }
            if container.superview !== host {
                container.removeFromSuperview()
                host.addSubview(container)
                container.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    container.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                    container.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                    container.topAnchor.constraint(equalTo: host.topAnchor),
                    container.bottomAnchor.constraint(equalTo: host.bottomAnchor),
                ])
            }
            let isSelected = item.id == selectedID
            container.isHidden = !isSelected
        }
        // Focus the selected terminal so it receives key events
        if let selectedID, let container = store.container(for: selectedID) {
            DispatchQueue.main.async {
                guard host.window?.firstResponder !== container,
                      host.window?.firstResponder !== container.embeddedTerminal else { return }
                host.window?.makeFirstResponder(container)
            }
        }
    }

    private func makeTerminalContainer(workspacePath: String, initialCommand: String?, coordinator: MultiTerminalHostView.Coordinator) -> EmbeddedTerminalView.TerminalContainerView {
        let container = EmbeddedTerminalView.TerminalContainerView(frame: .zero)
        let terminal = LocalProcessTerminalView(frame: .zero)
        terminal.caretColor = .systemGreen
        terminal.getTerminal().setCursorStyle(.steadyBlock)
        terminal.processDelegate = coordinator
        terminal.translatesAutoresizingMaskIntoConstraints = false

        let dir = projectRootForTerminal(workspacePath: workspacePath)
        let shell = EmbeddedTerminalView.userShellForTerminal
        let execName = "-" + (shell as NSString).lastPathComponent
        terminal.startProcess(
            executable: shell,
            args: [],
            environment: nil,
            execName: execName,
            currentDirectory: dir
        )

        container.embeddedTerminal = terminal
        container.addSubview(terminal)
        let inset = EmbeddedTerminalView.TerminalContainerView.contentInset
        NSLayoutConstraint.activate([
            terminal.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
            terminal.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset),
            terminal.topAnchor.constraint(equalTo: container.topAnchor, constant: inset),
            terminal.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -inset),
        ])
        let cmd = initialCommand?.trimmingCharacters(in: .whitespacesAndNewlines)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak terminal] in
            if let cmd, !cmd.isEmpty {
                terminal?.send(txt: "clear\n\(cmd)\n")
            } else {
                terminal?.send(txt: "clear\n")
            }
        }
        return container
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class MultiTerminalHostContainerView: NSView {
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.backgroundColor = NSColor.black.cgColor
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override var acceptsFirstResponder: Bool { true }
        override func mouseDown(with event: NSEvent) {
            if let first = subviews.first as? EmbeddedTerminalView.TerminalContainerView {
                window?.makeFirstResponder(first)
            }
            super.mouseDown(with: event)
        }
    }

    class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func processTerminated(source: TerminalView, exitCode: Int32?) {}
    }
}

extension EmbeddedTerminalView {
    /// Exposed for use by MultiTerminalHostView.
    static var userShellForTerminal: String {
        let bufsize = sysconf(_SC_GETPW_R_SIZE_MAX)
        guard bufsize > 0 else { return "/bin/zsh" }
        let buffer = UnsafeMutablePointer<Int8>.allocate(capacity: bufsize)
        defer { buffer.deallocate() }
        var pwd = passwd()
        var result: UnsafeMutablePointer<passwd>?
        guard getpwuid_r(getuid(), &pwd, buffer, bufsize, &result) == 0, result != nil else {
            return "/bin/zsh"
        }
        return String(cString: pwd.pw_shell)
    }
}
#endif
