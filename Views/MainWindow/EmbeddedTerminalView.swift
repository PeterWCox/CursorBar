import SwiftUI
import AppKit
import SwiftTerm
import Darwin

#if os(macOS)

/// SwiftUI wrapper for SwiftTerm's LocalProcessTerminalView. Runs a shell in the given workspace directory.
struct EmbeddedTerminalView: NSViewRepresentable {
    /// Container that draws a terminal-like background and insets the terminal content so text doesn't hug the edges.
    final class TerminalContainerView: NSView {
        static let contentInset: CGFloat = 12

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.backgroundColor = NSColor.black.cgColor
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
    let workspacePath: String
    /// When true, the terminal view is made first responder so it receives key events (e.g. Control+C).
    var isSelected: Bool = true

    func makeNSView(context: Context) -> TerminalContainerView {
        let container = TerminalContainerView(frame: .zero)
        container.translatesAutoresizingMaskIntoConstraints = false

        let terminal = LocalProcessTerminalView(frame: .zero)
        terminal.caretColor = .systemGreen
        terminal.getTerminal().setCursorStyle(.steadyBlock)
        terminal.processDelegate = context.coordinator
        terminal.translatesAutoresizingMaskIntoConstraints = false

        let shell = Self.userShell
        let execName = "-" + (shell as NSString).lastPathComponent
        let dir = (workspacePath as NSString).expandingTildeInPath
        terminal.startProcess(
            executable: shell,
            args: [],
            environment: nil,
            execName: execName,
            currentDirectory: dir
        )

        context.coordinator.terminalView = terminal
        container.addSubview(terminal)
        let inset = TerminalContainerView.contentInset
        NSLayoutConstraint.activate([
            terminal.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
            terminal.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset),
            terminal.topAnchor.constraint(equalTo: container.topAnchor, constant: inset),
            terminal.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -inset),
        ])
        return container
    }

    func updateNSView(_ nsView: TerminalContainerView, context: Context) {
        guard isSelected, let terminal = context.coordinator.terminalView else { return }
        // Make the terminal first responder so it receives key events (Control+C, etc.).
        DispatchQueue.main.async {
            terminal.window?.makeFirstResponder(terminal)
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
