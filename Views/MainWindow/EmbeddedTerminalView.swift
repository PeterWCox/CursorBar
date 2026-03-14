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
        if let cmd = cmd, !cmd.isEmpty {
            terminal.startProcess(
                executable: "/bin/bash",
                args: ["-c", cmd],
                environment: nil,
                execName: "bash",
                currentDirectory: dir
            )
        } else {
            let shell = Self.userShell
            let execName = "-" + (shell as NSString).lastPathComponent
            terminal.startProcess(
                executable: shell,
                args: [],
                environment: nil,
                execName: execName,
                currentDirectory: dir
            )
        }

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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak terminal] in
            terminal?.send(txt: "clear\n")
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

    private static var userShell: String {
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

    class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        var terminalView: LocalProcessTerminalView?
        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func processTerminated(source: TerminalView, exitCode: Int32?) {}
    }
}
#endif
