import SwiftUI
import AppKit
import Combine

final class PasteAwareTextView: NSTextView {
    var onPasteImage: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCommandV = modifiers.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "v"

        if isCommandV {
            let pasteboard = NSPasteboard.general
            if onPasteImage != nil, SubmittableTextEditor.imageFromPasteboard(pasteboard) != nil {
                onPasteImage?()
                return true
            }
            if let string = pasteboard.string(forType: .string), !string.isEmpty {
                insertText(string, replacementRange: selectedRange())
                return true
            }
        }

        return super.performKeyEquivalent(with: event)
    }

    override func paste(_ sender: Any?) {
        if onPasteImage != nil, SubmittableTextEditor.imageFromPasteboard(.general) != nil {
            onPasteImage?()
            return
        }
        super.paste(sender)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        if onPasteImage != nil, SubmittableTextEditor.imageFromPasteboard(.general) != nil {
            onPasteImage?()
            return
        }
        super.pasteAsPlainText(sender)
    }

    override func pasteAsRichText(_ sender: Any?) {
        if onPasteImage != nil, SubmittableTextEditor.imageFromPasteboard(.general) != nil {
            onPasteImage?()
            return
        }
        super.pasteAsRichText(sender)
    }
}

struct SubmittableTextEditor: NSViewRepresentable {
    @Binding var text: String
    var isDisabled: Bool
    var onSubmit: () -> Void
    var onPasteImage: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = PasteAwareTextView()
        textView.delegate = context.coordinator
        textView.onPasteImage = onPasteImage
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.backgroundColor = .clear
        textView.textColor = NSColor.white.withAlphaComponent(0.92)
        textView.insertionPointColor = NSColor.white.withAlphaComponent(0.9)
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        if textView.string != text {
            textView.string = text
        }
        textView.isEditable = true
        (textView as? PasteAwareTextView)?.onPasteImage = onPasteImage
    }

    /// Extracts an image from the pasteboard using multiple methods (NSImage, file URL, raw PNG/TIFF).
    static func imageFromPasteboard(_ pasteboard: NSPasteboard) -> NSImage? {
        if pasteboard.canReadObject(forClasses: [NSImage.self], options: nil),
           let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first {
            return image
        }
        if pasteboard.canReadObject(forClasses: [NSURL.self], options: nil),
           let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let url = urls.first,
           let image = NSImage(contentsOf: url) {
            return image
        }
        let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]
        for type in imageTypes {
            if let data = pasteboard.data(forType: type), let image = NSImage(data: data) {
                return image
            }
        }
        return nil
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SubmittableTextEditor
        weak var textView: NSTextView?

        init(_ parent: SubmittableTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.text = tv.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if NSEvent.modifierFlags.contains(.shift) {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                } else if !parent.isDisabled {
                    parent.onSubmit()
                }
                return true
            }
            return false
        }
    }
}

enum ConversationSegmentKind {
    case thinking
    case assistant
    case toolCall
}

enum ToolCallSegmentStatus {
    case running
    case completed
    case failed
}

struct ToolCallSegmentData {
    let callID: String
    var title: String
    var detail: String
    var status: ToolCallSegmentStatus
}

struct ConversationSegment: Identifiable {
    let id: UUID
    let kind: ConversationSegmentKind
    var text: String
    var toolCall: ToolCallSegmentData?

    init(id: UUID = UUID(), kind: ConversationSegmentKind, text: String) {
        self.id = id
        self.kind = kind
        self.text = text
        toolCall = nil
    }

    init(id: UUID = UUID(), toolCall: ToolCallSegmentData) {
        self.id = id
        kind = .toolCall
        text = ""
        self.toolCall = toolCall
    }
}

struct ConversationTurn: Identifiable {
    let id: UUID
    let userPrompt: String
    var segments: [ConversationSegment]
    var isStreaming: Bool
    var lastStreamPhase: StreamPhase?

    init(
        id: UUID = UUID(),
        userPrompt: String,
        segments: [ConversationSegment] = [],
        isStreaming: Bool = false,
        lastStreamPhase: StreamPhase? = nil
    ) {
        self.id = id
        self.userPrompt = userPrompt
        self.segments = segments
        self.isStreaming = isStreaming
        self.lastStreamPhase = lastStreamPhase
    }
}

enum StreamPhase {
    case thinking
    case assistant
    case toolCall
}

private let maxScreenshots = 3

class AgentTab: ObservableObject, Identifiable {
    let id: UUID
    @Published var title: String
    @Published var prompt = ""
    @Published var turns: [ConversationTurn] = []
    @Published var isRunning = false
    @Published var errorMessage: String?
    @Published var hasAttachedScreenshot = false
    @Published var scrollToken = UUID()
    var streamTask: Task<Void, Never>?
    var activeRunID: UUID?
    var activeTurnID: UUID?

    init(title: String = "Agent") {
        self.id = UUID()
        self.title = title
    }
}

class TabManager: ObservableObject {
    @Published var tabs: [AgentTab] = []
    @Published var selectedTabID: UUID
    private var tabSubscriptions: [UUID: AnyCancellable] = [:]

    init() {
        let first = AgentTab(title: "Agent 1")
        tabs = [first]
        selectedTabID = first.id
        bindTabChanges()
    }

    var activeTab: AgentTab {
        tabs.first { $0.id == selectedTabID } ?? tabs[0]
    }

    func addTab(initialPrompt: String? = nil) {
        let tab = AgentTab(title: "Agent \(tabs.count + 1)")
        if let prompt = initialPrompt, !prompt.isEmpty {
            tab.prompt = prompt
        }
        tabs.append(tab)
        observe(tab)
        selectedTabID = tab.id
    }

    func closeTab(_ id: UUID) {
        guard tabs.count > 1 else { return }
        if let index = tabs.firstIndex(where: { $0.id == id }) {
            let wasSelected = selectedTabID == id
            tabs.remove(at: index)
            tabSubscriptions[id] = nil
            if wasSelected {
                let newIndex = min(index, tabs.count - 1)
                selectedTabID = tabs[newIndex].id
            }
        }
    }

    private func bindTabChanges() {
        tabs.forEach(observe)
    }

    private func observe(_ tab: AgentTab) {
        guard tabSubscriptions[tab.id] == nil else { return }
        tabSubscriptions[tab.id] = tab.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }
}

/// Extracts screenshot paths from prompt (e.g. ".cursor/pasted-screenshot-1.png"), capped at maxScreenshots.
private func screenshotPaths(from prompt: String) -> [String] {
    let pattern = "\\[Screenshot attached:\\s*([^\\]]+)\\]"
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(prompt.startIndex..., in: prompt)
    let matches = regex.matches(in: prompt, range: range)
    var paths: [String] = []
    for m in matches {
        if m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: prompt) {
            let path = String(prompt[r]).trimmingCharacters(in: .whitespaces)
            if !path.isEmpty, !paths.contains(path) {
                paths.append(path)
            }
        }
    }
    return Array(paths.prefix(maxScreenshots))
}

/// Approximate token count for context (Cursor CLI uses this conversation as context). ~4 chars per token.
private let contextTokenLimit = 128_000

private func estimatedContextTokens(prompt: String, turns: [ConversationTurn]) -> (used: Int, limit: Int) {
    var chars = prompt.count
    for turn in turns {
        chars += turn.userPrompt.count
        for seg in turn.segments {
            chars += seg.text.count
        }
    }
    let used = max(0, chars / 4)
    return (used, contextTokenLimit)
}

private func autoGeneratedTabTitle(from prompt: String) -> String? {
    let firstContentLine = prompt
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty && !$0.hasPrefix("[Screenshot attached:") }

    guard let firstContentLine else { return nil }

    let normalized = firstContentLine.replacingOccurrences(
        of: #"\s+"#,
        with: " ",
        options: .regularExpression
    )

    let truncated = String(normalized.prefix(72)).trimmingCharacters(in: .whitespacesAndNewlines)
    return truncated.isEmpty ? nil : truncated
}

private let availableModels: [(id: String, label: String)] = [
    ("composer-1.5", "Composer 1.5"),
    ("composer-1", "Composer 1"),
    ("auto", "Auto"),
    ("opus-4.6-thinking", "Claude 4.6 Opus (Thinking)"),
    ("sonnet-4.6-thinking", "Claude 4.6 Sonnet (Thinking)"),
    ("sonnet-4.6", "Claude 4.6 Sonnet"),
    ("gpt-5.4-high", "GPT-5.4 High"),
    ("gpt-5.4-medium", "GPT-5.4"),
    ("gemini-3.1-pro", "Gemini 3.1 Pro"),
]

private enum CursorTheme {
    static let chrome = Color(red: 0.055, green: 0.059, blue: 0.075)
    static let panel = Color(red: 0.082, green: 0.086, blue: 0.106)
    static let surface = Color(red: 0.118, green: 0.122, blue: 0.145)
    static let surfaceRaised = Color(red: 0.145, green: 0.149, blue: 0.176)
    static let surfaceMuted = Color(red: 0.099, green: 0.103, blue: 0.123)
    static let editor = Color(red: 0.148, green: 0.152, blue: 0.178)
    static let border = Color.white.opacity(0.08)
    static let borderStrong = Color.white.opacity(0.13)
    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.42)
    static let brandBlue = Color(red: 0.40, green: 0.61, blue: 1.00)
    static let brandPurple = Color(red: 0.55, green: 0.40, blue: 0.98)
    static let brandAmber = Color(red: 0.98, green: 0.76, blue: 0.31)
    static let cursorPlusTeal = Color(red: 0.0, green: 0.83, blue: 0.71)

    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [brandBlue, brandPurple],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var panelGradient: LinearGradient {
        LinearGradient(
            colors: [panel, chrome],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

struct BrandMark: View {
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            if let nsImage = CursorAppIcon.load() {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                            .stroke(CursorTheme.cursorPlusTeal.opacity(0.8), lineWidth: max(1, size * 0.025))
                    )
            } else {
                fallbackIcon
            }
        }
        .frame(width: size, height: size)
        .shadow(color: CursorTheme.cursorPlusTeal.opacity(0.25), radius: 12, y: 6)
    }

    private var fallbackIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(CursorTheme.surfaceMuted)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    CursorTheme.cursorPlusTeal.opacity(0.9),
                                    CursorTheme.brandBlue.opacity(0.8)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: max(1, size * 0.025)
                        )
                )

            Circle()
                .stroke(CursorTheme.textPrimary, lineWidth: size * 0.07)
                .frame(width: size * 0.48, height: size * 0.48)

            Circle()
                .fill(CursorTheme.textPrimary)
                .frame(width: size * 0.11, height: size * 0.11)

            Path { path in
                path.move(to: CGPoint(x: size * 0.18, y: size * 0.6))
                path.addCurve(
                    to: CGPoint(x: size * 0.58, y: size * 0.78),
                    control1: CGPoint(x: size * 0.26, y: size * 0.86),
                    control2: CGPoint(x: size * 0.44, y: size * 0.84)
                )
            }
            .stroke(CursorTheme.textPrimary.opacity(0.75), style: StrokeStyle(lineWidth: size * 0.055, lineCap: .round))

            Image(systemName: "sparkle")
                .font(.system(size: size * 0.18, weight: .bold))
                .foregroundStyle(CursorTheme.textPrimary)
                .offset(x: size * 0.22, y: -size * 0.22)
        }
    }
}

private struct OutputScrollView<Content: View>: View {
    let tab: AgentTab
    let scrollToken: UUID
    @ViewBuilder let content: () -> Content

    @State private var bottomVisibleID: AnyHashable?

    private var showScrollPill: Bool {
        guard !tab.turns.isEmpty else { return false }
        return bottomVisibleID != nil && bottomVisibleID != AnyHashable("outputEnd")
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content()
            }
            .scrollPosition(id: $bottomVisibleID, anchor: .bottom)
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 2)
            .overlay(alignment: .bottomTrailing) {
                if showScrollPill {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("outputEnd", anchor: .bottom)
                        }
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(CursorTheme.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(CursorTheme.surfaceMuted, in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(CursorTheme.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                }
            }
            .onChange(of: scrollToken) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("outputEnd", anchor: .bottom)
                }
            }
        }
    }
}

private let devFolderPath = "/Users/petercox/dev"

private func loadDevFolders() -> [URL] {
    let url = URL(fileURLWithPath: devFolderPath)
    guard let contents = try? FileManager.default.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    ) else { return [] }
    return contents
        .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
}

/// Returns (current branch name, sorted list of local branch names) for the workspace. Empty if not a git repo.
private func loadGitBranches(workspacePath: String) -> (current: String, branches: [String]) {
    let url = URL(fileURLWithPath: workspacePath)
    guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return ("", []) }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["for-each-ref", "--format=%(refname:short)", "refs/heads/"]
    process.currentDirectoryURL = url
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return ("", []) }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return ("", []) }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let list = (String(data: data, encoding: .utf8) ?? "")
        .split(separator: "\n")
        .map(String.init)
        .filter { !$0.isEmpty }
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    let currentProcess = Process()
    currentProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    currentProcess.arguments = ["rev-parse", "--abbrev-ref", "HEAD"]
    currentProcess.currentDirectoryURL = url
    let currentPipe = Pipe()
    currentProcess.standardOutput = currentPipe
    currentProcess.standardError = FileHandle.nullDevice
    guard (try? currentProcess.run()) != nil else { return (list.first ?? "", list) }
    currentProcess.waitUntilExit()
    let currentData = currentPipe.fileHandleForReading.readDataToEndOfFile()
    let current = (String(data: currentData, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return (current.isEmpty ? (list.first ?? "") : current, list)
}

/// Run `git checkout <branch>` in the workspace. Returns nil on success, error message otherwise.
private func gitCheckout(branch: String, workspacePath: String) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["checkout", branch]
    process.currentDirectoryURL = URL(fileURLWithPath: workspacePath)
    let pipe = Pipe()
    process.standardOutput = pipe
    let errPipe = Pipe()
    process.standardError = errPipe
    guard (try? process.run()) != nil else { return "Failed to run git" }
    process.waitUntilExit()
    guard process.terminationStatus != 0 else { return nil }
    let err = (try? String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)) ?? "Unknown error"
    return err.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Included API requests per month (Cursor Pro typical). Used to compute usage %.
private let includedAPIQuota = 500

private let fixBuildPrompt = """
Fix the build. Identify and fix any compile errors, test failures, or other issues preventing the project from building successfully. Run the build (and tests if applicable) and iterate until everything passes.
"""

private let commitAndPushPrompt = """
Review the current git changes (e.g. git status and diff). Summarise them in a single, clear commit message and create one atomic commit, then push to the current branch. Only commit if the changes look intentional and ready to ship.
"""

struct PopoutView: View {
    @EnvironmentObject var appState: AppState
    var dismiss: () -> Void = {}
    @AppStorage("workspacePath") private var workspacePath: String = FileManager.default.homeDirectoryForCurrentUser.path
    @AppStorage("selectedModel") private var selectedModel: String = "composer-1.5"
    @AppStorage("messagesSentForUsage") private var messagesSentForUsage: Int = 0
    @StateObject private var tabManager = TabManager()
    @State private var devFolders: [URL] = []
    @State private var gitBranches: [String] = []
    @State private var currentBranch: String = ""
    
    private var tab: AgentTab { tabManager.activeTab }
    
    private var apiUsagePercent: Int {
        min(100, (messagesSentForUsage * 100) / includedAPIQuota)
    }

    var body: some View {
        VStack(spacing: 12) {
            topBar
            tabBar

            if let error = tab.errorMessage {
                Text(error)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(red: 1.0, green: 0.64, blue: 0.67))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(cardBackground.opacity(0.96), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.red.opacity(0.25), lineWidth: 1)
                    )
            }

            outputCard
                .frame(maxHeight: .infinity)
                .id(tab.id)

            composerDock
        }
        .padding(16)
        .frame(minWidth: 360, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
        .background(CursorTheme.panelGradient)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(CursorTheme.borderStrong, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.36), radius: 28, y: 16)
        .overlay(
            Group {
                Button("New Tab") {
                    tabManager.addTab()
                }
                .keyboardShortcut("t", modifiers: .command)
                .opacity(0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if tabManager.tabs.count > 1 {
                    Button("Close Tab") {
                        stopStreaming(for: tabManager.activeTab)
                        tabManager.closeTab(tabManager.activeTab.id)
                    }
                    .keyboardShortcut("w", modifiers: .command)
                    .opacity(0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        )
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            BrandMark(size: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text("Cursor+")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CursorTheme.textPrimary)

                HStack(spacing: 6) {
                    Circle()
                        .fill(tab.isRunning ? CursorTheme.brandBlue : CursorTheme.textTertiary)
                        .frame(width: 6, height: 6)

                    Text(tab.isRunning ? "Streaming response" : "Ready")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CursorTheme.textSecondary)
                }
            }

            Spacer()

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CursorTheme.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(CursorTheme.surfaceMuted, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }

    private var quickActionButtons: some View {
        HStack(spacing: 8) {
            Button {
                openNewTabAndSend(prompt: fixBuildPrompt)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "wrench.and.screwdriver")
                    Text("Fix build")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CursorTheme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(CursorTheme.surfaceMuted, in: Capsule())
                .overlay(Capsule().stroke(CursorTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(tab.isRunning)

            Button {
                openNewTabAndSend(prompt: commitAndPushPrompt)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.circle")
                    Text("Commit & push")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CursorTheme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(CursorTheme.surfaceMuted, in: Capsule())
                .overlay(Capsule().stroke(CursorTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(tab.isRunning)
        }
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(tabManager.tabs) { t in
                    let isSelected = t.id == tabManager.selectedTabID
                    TabChip(
                        title: t.title,
                        isSelected: isSelected,
                        isRunning: t.isRunning,
                        showClose: tabManager.tabs.count > 1,
                        onSelect: { tabManager.selectedTabID = t.id },
                        onClose: {
                            stopStreaming(for: t)
                            tabManager.closeTab(t.id)
                        }
                    )
                }

                Button(action: { tabManager.addTab() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CursorTheme.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(CursorTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(CursorTheme.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
        }
    }

    private var composerDock: some View {
        let attachedPaths = screenshotPaths(from: tab.prompt)
        return VStack(alignment: .leading, spacing: 12) {
            quickActionButtons

            ForEach(Array(attachedPaths.enumerated()), id: \.offset) { _, path in
                screenshotCard(path: path)
            }

            ZStack(alignment: .topLeading) {
                SubmittableTextEditor(
                    text: Binding(
                        get: { tab.prompt },
                        set: { newValue in
                            tab.prompt = newValue
                            tab.hasAttachedScreenshot = !screenshotPaths(from: newValue).isEmpty
                        }
                    ),
                    isDisabled: tab.isRunning,
                    onSubmit: sendPrompt,
                    onPasteImage: pasteScreenshot
                )
                .frame(height: 88)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(CursorTheme.editor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(CursorTheme.border, lineWidth: 1)
                )

                if tab.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Send message and/or ⌘V to paste one or more screenshots from clipboard")
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundStyle(CursorTheme.textTertiary)
                        .padding(.leading, 16)
                        .padding(.top, 14)
                        .allowsHitTesting(false)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Menu {
                    ForEach(devFolders, id: \.path) { folder in
                        Button {
                            workspacePath = folder.path
                            appState.workspacePath = folder.path
                        } label: {
                            if folder.path == workspacePath {
                                Label(folder.lastPathComponent, systemImage: "checkmark")
                            } else {
                                Text(folder.lastPathComponent)
                            }
                        }
                    }
                    Divider()
                    Button("Browse other folder...") {
                        appState.changeWorkspace()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                        Text(appState.workspaceDisplayName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CursorTheme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CursorTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(CursorTheme.border, lineWidth: 1)
                    )
                }
                .menuStyle(.borderlessButton)
                .foregroundColor(.white)
                .colorScheme(.dark)
                .onAppear { devFolders = loadDevFolders() }

                Menu {
                    ForEach(availableModels, id: \.id) { model in
                        Button {
                            selectedModel = model.id
                        } label: {
                            if model.id == selectedModel {
                                Label(model.label, systemImage: "checkmark")
                            } else {
                                Text(model.label)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "cpu")
                        Text(selectedModelLabel)
                            .lineLimit(1)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CursorTheme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CursorTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(CursorTheme.border, lineWidth: 1)
                    )
                }
                .menuStyle(.borderlessButton)
                .foregroundColor(.white)
                .colorScheme(.dark)

                Menu {
                    ForEach(gitBranches, id: \.self) { branch in
                        Button {
                            if branch != currentBranch {
                                if let err = gitCheckout(branch: branch, workspacePath: workspacePath) {
                                    tab.errorMessage = err
                                } else {
                                    let (cur, list) = loadGitBranches(workspacePath: workspacePath)
                                    currentBranch = cur
                                    gitBranches = list
                                    tab.errorMessage = nil
                                }
                            }
                        } label: {
                            if branch == currentBranch {
                                Label(branch, systemImage: "checkmark")
                            } else {
                                Text(branch)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.branch")
                        Text(currentBranch.isEmpty ? "No branch" : currentBranch)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CursorTheme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CursorTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(CursorTheme.border, lineWidth: 1)
                    )
                }
                .menuStyle(.borderlessButton)
                .foregroundColor(.white)
                .colorScheme(.dark)
                .disabled(gitBranches.isEmpty)
                .onAppear {
                    let (cur, list) = loadGitBranches(workspacePath: workspacePath)
                    currentBranch = cur
                    gitBranches = list
                }
                .onChange(of: workspacePath) { _, _ in
                    let (cur, list) = loadGitBranches(workspacePath: workspacePath)
                    currentBranch = cur
                    gitBranches = list
                }
            }

            HStack(spacing: 10) {
                Spacer()

                Button {
                    clearContext()
                } label: {
                    let hasContext = !tab.turns.isEmpty || !tab.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                        Text("Summarize")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(hasContext ? CursorTheme.textPrimary : CursorTheme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        hasContext
                            ? CursorTheme.surfaceRaised
                            : CursorTheme.surfaceMuted,
                        in: Capsule()
                    )
                    .overlay(
                        Capsule()
                            .stroke(CursorTheme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(tab.isRunning)

                Button(action: {
                    if tab.isRunning {
                        stopStreaming()
                    } else {
                        sendPrompt()
                    }
                }) {
                    Group {
                        if tab.isRunning {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 12, weight: .black))
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 15, weight: .bold))
                        }
                    }
                    .foregroundStyle(CursorTheme.textPrimary)
                    .frame(width: 36, height: 36)
                    .background {
                        if tab.isRunning {
                            Circle().fill(CursorTheme.surfaceRaised)
                        } else {
                            Circle().fill(CursorTheme.brandGradient)
                        }
                    }
                    .overlay(
                        Circle()
                            .stroke(
                                tab.isRunning
                                    ? CursorTheme.borderStrong
                                    : Color.white.opacity(0.14),
                                lineWidth: 1
                            )
                    )
                    .opacity(tab.isRunning || canSend ? 1 : 0.45)
                }
                .buttonStyle(.plain)
                .disabled(!tab.isRunning && !canSend)
            }

            contextUsageView
        }
        .padding(14)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
        )
    }

    private var contextUsageView: some View {
        let (used, limit) = estimatedContextTokens(prompt: tab.prompt, turns: tab.turns)
        let fraction = limit > 0 ? Double(used) / Double(limit) : 0
        let usedK = used / 1000
        let limitK = limit / 1000
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Context")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CursorTheme.textTertiary)
                Spacer()
                Text("~\(usedK)k / \(limitK)k tokens")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(CursorTheme.textSecondary)
            }
            ProgressView(value: min(1, fraction))
                .tint(fraction > 0.85 ? CursorTheme.brandAmber : CursorTheme.brandBlue)
                .background(CursorTheme.surfaceMuted)
                .scaleEffect(y: 1.2, anchor: .center)
        }
    }

    private func clearContext() {
        guard !tab.isRunning else { return }
        tab.turns = []
        tab.prompt = ""
        tab.hasAttachedScreenshot = false
        tab.errorMessage = nil
    }

    private func screenshotCard(path: String) -> some View {
        let imageURL = URL(fileURLWithPath: workspacePath).appendingPathComponent(path)

        return Group {
            if let nsImage = NSImage(contentsOf: imageURL) {
                HStack(spacing: 12) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Attached screenshot")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CursorTheme.textPrimary)

                        Text(path)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CursorTheme.textSecondary)
                            .lineLimit(1)

                        Text("Included with your next prompt")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CursorTheme.textSecondary)
                    }

                    Spacer()

                    Button(action: { deleteScreenshot(path: path) }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(CursorTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(editorBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
        }
    }

    private var outputCard: some View {
        OutputScrollView(
            tab: tab,
            scrollToken: tab.scrollToken,
            content: {
                VStack(alignment: .leading, spacing: 18) {
                    if tab.turns.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Responses appear here")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(CursorTheme.textSecondary)

                            Text("Ask a question below and Cursor will stream the answer into this panel.")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(CursorTheme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                    } else {
                        ForEach(tab.turns) { turn in
                            conversationTurnView(turn)
                                .id(turn.id)
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("outputEnd")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
        )
    }

    private var selectedModelLabel: String {
        availableModels.first { $0.id == selectedModel }?.label ?? selectedModel
    }

    private var cardBackground: some ShapeStyle {
        CursorTheme.surface
    }

    private var editorBackground: some ShapeStyle {
        CursorTheme.surfaceMuted
    }

    private var cardBorder: Color {
        CursorTheme.border
    }

    private var canSend: Bool {
        !tab.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !tab.isRunning
    }

    private func visibleSegments(for turn: ConversationTurn) -> [ConversationSegment] {
        turn.segments.compactMap { segment in
            if segment.kind == .toolCall {
                guard let title = segment.toolCall?.title.trimmingCharacters(in: .whitespacesAndNewlines),
                      !title.isEmpty else {
                    return nil
                }
                return segment
            }
            let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return segment
        }
    }

    private var processingPlaceholder: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(CursorTheme.textSecondary)

            TimelineView(.periodic(from: .now, by: 0.4)) { timeline in
                let dotCount = (Int(timeline.date.timeIntervalSince1970 * 2.5) % 3) + 1
                Text("Processing request" + String(repeating: ".", count: dotCount))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CursorTheme.textSecondary)
                    .animation(.easeInOut(duration: 0.2), value: dotCount)
            }
        }
    }

    /// Inserts line breaks at natural boundaries so run-on summary text is readable.
    private func normalizedAssistantText(_ raw: String) -> String {
        var result = raw
        // "). " or ")." followed by capital (e.g. ").Intentionally") -> paragraph break
        result = result.replacingOccurrences(of: "). ", with: ").\n\n")
        if let regex = try? NSRegularExpression(pattern: "\\)\\.([A-Z])", options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: ").\n\n$1"
            )
        }
        // Sentence boundary: ". " before capital letter, but not "1. " numbered lists
        if let regex = try? NSRegularExpression(pattern: "([a-z])\\. ([A-Z])", options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: "$1.\n\n$2"
            )
        }
        return result
    }

    private func assistantAttributedText(_ raw: String) -> AttributedString {
        let normalized = normalizedAssistantText(raw)
        return (try? AttributedString(markdown: normalized, options: .init(interpretedSyntax: .full))) ?? AttributedString(normalized)
    }

    @ViewBuilder
    private func conversationSegmentView(_ segment: ConversationSegment) -> some View {
        switch segment.kind {
        case .thinking:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(CursorTheme.textSecondary)

                    Text("Thinking")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CursorTheme.textSecondary)
                }

                Text(segment.text)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(CursorTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(CursorTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(CursorTheme.border, lineWidth: 1)
            )
        case .assistant:
            Text(assistantAttributedText(segment.text))
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(CursorTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(4)
                .textSelection(.enabled)
        case .toolCall:
            if let toolCall = segment.toolCall {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: toolCallIcon(for: toolCall.status))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(toolCallTint(for: toolCall.status))

                        Text(toolCall.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CursorTheme.textPrimary)
                            .lineLimit(2)

                        Spacer(minLength: 8)

                        Text(toolCallStatusLabel(for: toolCall.status))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(toolCallTint(for: toolCall.status))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(toolCallTint(for: toolCall.status).opacity(0.14), in: Capsule())
                    }

                    if !toolCall.detail.isEmpty {
                        Text(assistantAttributedText(toolCall.detail))
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(CursorTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(CursorTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(toolCallTint(for: toolCall.status).opacity(0.18), lineWidth: 1)
                )
            }
        }
    }

    @ViewBuilder
    private func conversationTurnView(_ turn: ConversationTurn) -> some View {
        let segments = visibleSegments(for: turn)
        let hasAssistantContent = segments.contains { $0.kind == .assistant }

        VStack(alignment: .leading, spacing: 12) {
            Text(turn.userPrompt)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(CursorTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(CursorTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(CursorTheme.border, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 14) {
                ForEach(segments) { segment in
                    conversationSegmentView(segment)
                }

                if !hasAssistantContent && turn.isStreaming {
                    processingPlaceholder
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private func deleteScreenshot(path: String) {
        let reference = "\n\n[Screenshot attached: \(path)]"
        tab.prompt = tab.prompt.replacingOccurrences(of: reference, with: "")
        if !tab.prompt.contains("[Screenshot attached:") {
            tab.hasAttachedScreenshot = false
        }
        let imageURL = URL(fileURLWithPath: workspacePath).appendingPathComponent(path)
        try? FileManager.default.removeItem(at: imageURL)
    }

    /// Picks the next available screenshot filename not in current paths (legacy .cursor/pasted-screenshot.png first, then -1, -2, -3).
    private func nextScreenshotPath(currentPaths: [String]) -> String? {
        let legacy = ".cursor/pasted-screenshot.png"
        if !currentPaths.contains(legacy) { return legacy }
        for i in 1...maxScreenshots {
            let candidate = ".cursor/pasted-screenshot-\(i).png"
            if !currentPaths.contains(candidate) { return candidate }
        }
        return nil
    }

    private func pasteScreenshot() {
        let currentPaths = screenshotPaths(from: tab.prompt)
        guard currentPaths.count < maxScreenshots,
              let relPath = nextScreenshotPath(currentPaths: currentPaths) else {
            return
        }

        let pasteboard = NSPasteboard.general
        guard let image = SubmittableTextEditor.imageFromPasteboard(pasteboard) else {
            return
        }

        let destURL = URL(fileURLWithPath: workspacePath).appendingPathComponent(relPath)
        let cursorDir = destURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: cursorDir, withIntermediateDirectories: true)
        } catch {
            return
        }

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return
        }

        do {
            try pngData.write(to: destURL)
            let reference = "\n\n[Screenshot attached: \(relPath)]"
            tab.prompt += reference
            tab.hasAttachedScreenshot = true
        } catch {
            return
        }
    }
    
    private func openNewTabAndSend(prompt: String) {
        tabManager.addTab(initialPrompt: prompt)
        sendPrompt()
    }

    private func sendPrompt() {
        let currentTab = tab
        let trimmed = currentTab.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if currentTab.turns.isEmpty, let generatedTitle = autoGeneratedTabTitle(from: trimmed) {
            currentTab.title = generatedTitle
        }
        
        let runID = UUID()
        let turnID = UUID()
        currentTab.streamTask?.cancel()
        currentTab.errorMessage = nil
        currentTab.isRunning = true
        currentTab.activeRunID = runID
        currentTab.activeTurnID = turnID
        currentTab.turns.append(ConversationTurn(id: turnID, userPrompt: trimmed, isStreaming: true))
        currentTab.prompt = ""
        currentTab.hasAttachedScreenshot = false
        currentTab.scrollToken = UUID()
        messagesSentForUsage += 1
        
        let task = Task {
            do {
                let stream = try AgentRunner.stream(prompt: trimmed, workspacePath: workspacePath, model: selectedModel)
                guard currentTab.activeRunID == runID, currentTab.activeTurnID == turnID else { return }
                for try await chunk in stream {
                    guard currentTab.activeRunID == runID, currentTab.activeTurnID == turnID, !Task.isCancelled else { return }
                    switch chunk {
                    case .thinkingDelta(let text):
                        appendThinkingText(text, to: turnID, in: currentTab)
                    case .thinkingCompleted:
                        completeThinking(for: turnID, in: currentTab)
                    case .assistantText(let text):
                        mergeAssistantText(text, into: currentTab, turnID: turnID)
                    case .toolCall(let update):
                        mergeToolCall(update, into: currentTab, turnID: turnID)
                    }
                    currentTab.scrollToken = UUID()
                }
                finishStreaming(for: currentTab, runID: runID, turnID: turnID)
            } catch is CancellationError {
                finishStreaming(for: currentTab, runID: runID, turnID: turnID)
            } catch let error as AgentRunnerError {
                finishStreaming(for: currentTab, runID: runID, turnID: turnID, errorMessage: error.userMessage)
            } catch {
                finishStreaming(for: currentTab, runID: runID, turnID: turnID, errorMessage: error.localizedDescription)
            }
        }
        
        currentTab.streamTask = task
    }

    private func stopStreaming(for currentTab: AgentTab? = nil) {
        let tabToStop = currentTab ?? tab
        if let turnID = tabToStop.activeTurnID,
           let index = tabToStop.turns.firstIndex(where: { $0.id == turnID }) {
            tabToStop.turns[index].isStreaming = false
            tabToStop.turns[index].lastStreamPhase = nil
        }
        tabToStop.activeRunID = nil
        tabToStop.activeTurnID = nil
        tabToStop.isRunning = false
        tabToStop.streamTask?.cancel()
        tabToStop.streamTask = nil
        tabToStop.scrollToken = UUID()
    }

    private func finishStreaming(for currentTab: AgentTab, runID: UUID, turnID: UUID, errorMessage: String? = nil) {
        guard currentTab.activeRunID == runID else { return }
        if let index = currentTab.turns.firstIndex(where: { $0.id == turnID }) {
            currentTab.turns[index].isStreaming = false
            currentTab.turns[index].lastStreamPhase = nil
        }
        currentTab.errorMessage = errorMessage
        currentTab.isRunning = false
        currentTab.streamTask = nil
        currentTab.activeRunID = nil
        currentTab.activeTurnID = nil
        currentTab.scrollToken = UUID()
    }

    private func appendThinkingText(_ incoming: String, to turnID: UUID, in tab: AgentTab) {
        guard !incoming.isEmpty,
              let index = tab.turns.firstIndex(where: { $0.id == turnID }) else {
            return
        }

        if tab.turns[index].lastStreamPhase != .thinking
            || tab.turns[index].segments.last?.kind != .thinking {
            tab.turns[index].segments.append(ConversationSegment(kind: .thinking, text: incoming))
        } else {
            tab.turns[index].segments[tab.turns[index].segments.count - 1].text += incoming
        }
        tab.turns[index].lastStreamPhase = .thinking
    }

    private func completeThinking(for turnID: UUID, in tab: AgentTab) {
        guard let index = tab.turns.firstIndex(where: { $0.id == turnID }) else { return }
        if tab.turns[index].lastStreamPhase == .thinking {
            tab.turns[index].lastStreamPhase = nil
        }
    }

    private func mergeAssistantText(_ incoming: String, into tab: AgentTab, turnID: UUID) {
        guard !incoming.isEmpty else { return }
        guard let index = tab.turns.firstIndex(where: { $0.id == turnID }) else { return }

        tab.turns[index].lastStreamPhase = .assistant

        if tab.turns[index].segments.last?.kind != .assistant {
            tab.turns[index].segments.append(ConversationSegment(kind: .assistant, text: incoming))
            return
        }

        let lastIndex = tab.turns[index].segments.count - 1
        let existing = tab.turns[index].segments[lastIndex].text

        if existing == incoming {
            return
        }

        if incoming.hasPrefix(existing) {
            tab.turns[index].segments[lastIndex].text = incoming
            return
        }

        tab.turns[index].segments[lastIndex].text += incoming
    }

    private func mergeToolCall(_ update: AgentToolCallUpdate, into tab: AgentTab, turnID: UUID) {
        guard let index = tab.turns.firstIndex(where: { $0.id == turnID }) else { return }

        tab.turns[index].lastStreamPhase = .toolCall

        let mappedStatus: ToolCallSegmentStatus
        switch update.status {
        case .started:
            mappedStatus = .running
        case .completed:
            mappedStatus = .completed
        case .failed:
            mappedStatus = .failed
        }

        if let segmentIndex = tab.turns[index].segments.lastIndex(where: { $0.toolCall?.callID == update.callID }) {
            tab.turns[index].segments[segmentIndex].toolCall?.title = update.title
            if !update.detail.isEmpty {
                tab.turns[index].segments[segmentIndex].toolCall?.detail = update.detail
            }
            tab.turns[index].segments[segmentIndex].toolCall?.status = mappedStatus
            return
        }

        tab.turns[index].segments.append(
            ConversationSegment(
                toolCall: ToolCallSegmentData(
                    callID: update.callID,
                    title: update.title,
                    detail: update.detail,
                    status: mappedStatus
                )
            )
        )
    }

    private func toolCallIcon(for status: ToolCallSegmentStatus) -> String {
        switch status {
        case .running:
            return "hammer"
        case .completed:
            return "checkmark.circle"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    private func toolCallStatusLabel(for status: ToolCallSegmentStatus) -> String {
        switch status {
        case .running:
            return "Running"
        case .completed:
            return "Done"
        case .failed:
            return "Failed"
        }
    }

    private func toolCallTint(for status: ToolCallSegmentStatus) -> Color {
        switch status {
        case .running:
            return CursorTheme.brandBlue
        case .completed:
            return CursorTheme.textSecondary
        case .failed:
            return Color(red: 1.0, green: 0.64, blue: 0.67)
        }
    }
}

struct TabChip: View {
    let title: String
    let isSelected: Bool
    let isRunning: Bool
    let showClose: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                if isRunning {
                    ProgressView()
                        .scaleEffect(0.45)
                        .frame(width: 10, height: 10)
                        .tint(.white)
                }

                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? CursorTheme.textPrimary : CursorTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 160, alignment: .leading)

                if showClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(CursorTheme.textTertiary)
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                isSelected
                    ? CursorTheme.surfaceRaised
                    : CursorTheme.surfaceMuted,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? CursorTheme.borderStrong : CursorTheme.border.opacity(0.6), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

