import SwiftUI
import AppKit

// MARK: - Sidebar tab group (by project)

private struct TabSidebarGroup {
    let path: String
    let displayName: String
    let tabs: [AgentTab]
}

// MARK: - Main popout panel view

struct PopoutView: View {
    @EnvironmentObject var appState: AppState
    var dismiss: () -> Void = {}
    @AppStorage("workspacePath") private var workspacePath: String = FileManager.default.homeDirectoryForCurrentUser.path
    @AppStorage(AppPreferences.projectsRootPathKey) private var projectsRootPath: String = AppPreferences.defaultProjectsRootPath
    @AppStorage("selectedModel") private var selectedModel: String = AvailableModels.autoID
    @AppStorage("messagesSentForUsage") private var messagesSentForUsage: Int = 0
    @AppStorage("showPinnedQuestionsPanel") private var showPinnedQuestionsPanel: Bool = true
    @EnvironmentObject var tabManager: TabManager
    @State private var devFolders: [URL] = []
    @State private var gitBranches: [String] = []
    @State private var currentBranch: String = ""
    @State private var quickActionCommands: [QuickActionCommand] = []
    @State private var composerTextHeight: CGFloat = 24
    @State private var showSetDebugURLSheet: Bool = false

    private var tab: AgentTab { tabManager.activeTab }

    private var apiUsagePercent: Int {
        min(100, (messagesSentForUsage * 100) / AppLimits.includedAPIQuota)
    }

    private let sidebarWidth: CGFloat = 200

    /// Tab focuses the prompt input; these are set by SubmittableTextEditor via onFocusRequested.
    @State private var focusPromptInput: (() -> Void)?
    @State private var isPromptFirstResponder: (() -> Bool)?

    /// Tabs grouped by workspace path, order preserved by first occurrence.
    private var tabGroups: [TabSidebarGroup] {
        var groupedTabs: [String: [AgentTab]] = [:]
        var orderedPaths: [String] = []

        for currentTab in tabManager.tabs {
            let path = currentTab.workspacePath
            if groupedTabs[path] == nil {
                orderedPaths.append(path)
            }
            groupedTabs[path, default: []].append(currentTab)
        }

        return orderedPaths.map { path in
            let displayName = appState.workspaceDisplayName(for: path)
            return TabSidebarGroup(
                path: path,
                displayName: displayName.isEmpty ? "Project" : displayName,
                tabs: groupedTabs[path] ?? []
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 14)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(CursorTheme.border.opacity(0.9))
                        .frame(height: 1)
                }

            HStack(alignment: .top, spacing: 0) {
                tabSidebar

                VStack(spacing: 12) {
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
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topLeading) {
                    if showPinnedQuestionsPanel {
                        PinnedQuestionsStackView(tab: tab)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                    }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 360, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
        .background(CursorTheme.panelGradient)
        .onKeyPress(.tab) {
            if isPromptFirstResponder?() == true {
                return .ignored
            }
            focusPromptInput?()
            return .handled
        }
        .onAppear {
            sanitizeSelectedModel()
            devFolders = loadDevFolders(rootPath: projectsRootPath)
            for t in tabManager.tabs where t.workspacePath.isEmpty {
                t.workspacePath = workspacePath
            }
            quickActionCommands = QuickActionStorage.commandsForWorkspace(workspacePath: workspacePath)
            let (cur, list) = loadGitBranches(workspacePath: tab.workspacePath)
            currentBranch = cur
            gitBranches = list
            tab.currentBranch = cur
        }
        .onChange(of: workspacePath) { _, _ in
            quickActionCommands = QuickActionStorage.commandsForWorkspace(workspacePath: workspacePath)
        }
        .onChange(of: projectsRootPath) { _, _ in
            devFolders = loadDevFolders(rootPath: projectsRootPath)
        }
        .onChange(of: selectedModel) { _, _ in
            sanitizeSelectedModel()
        }
        .onChange(of: tabManager.selectedTabID) { _, _ in
            let active = tabManager.activeTab
            let (cur, list) = loadGitBranches(workspacePath: active.workspacePath)
            currentBranch = cur
            gitBranches = list
            active.currentBranch = cur
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.black.opacity(0.36), radius: 28, y: 16)
        .sheet(isPresented: Binding(
            get: { appState.showSettingsSheet },
            set: { appState.showSettingsSheet = $0 }
        )) {
            SettingsModalView()
        }
        .sheet(isPresented: $showSetDebugURLSheet) {
            SetDebugURLSheet(
                workspacePath: tab.workspacePath,
                initialURL: ProjectSettingsStorage.getDebugURL(workspacePath: tab.workspacePath) ?? "",
                onSave: { _ in },
                onOpenAfterSave: nil
            )
        }
        .overlay(
            Group {
                Button("New Tab") {
                    tabManager.addTab(lastWorkspacePath: tab.workspacePath)
                }
                .keyboardShortcut("t", modifiers: .command)
                .opacity(0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Button("New Tab") {
                    tabManager.addTab(lastWorkspacePath: tab.workspacePath)
                }
                .keyboardShortcut("n", modifiers: .command)
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

                Button("Stop Agent") {
                    if tab.isRunning {
                        stopStreaming()
                    }
                }
                .keyboardShortcut("c", modifiers: .control)
                .opacity(0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        )
    }

    // MARK: - Unified header

    private var topBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 12) {
                BrandAppIconView(size: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Cursor+")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(CursorTheme.textPrimary)
                }
                }

            Spacer()

            Button(action: { appState.showSettingsSheet = true }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CursorTheme.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(CursorTheme.surfaceMuted, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Settings")

            Button(action: dismiss) {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CursorTheme.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(CursorTheme.surfaceMuted, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Minimise")
        }
    }

    private static let sidebarContentPadding: CGFloat = 10

    private var tabSidebar: some View {
        VStack(spacing: 6) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(tabGroups, id: \.path) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    if !group.path.isEmpty {
                                        ProjectIconView(path: group.path)
                                            .frame(width: 10, height: 10)
                                    }
                                    Text(group.displayName)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(CursorTheme.colorForWorkspace(path: group.path))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                let groupBranch = group.path == tab.workspacePath ? currentBranch : (group.tabs.first?.currentBranch ?? "")
                                if !groupBranch.isEmpty {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.triangle.branch")
                                            .font(.system(size: 8, weight: .medium))
                                        Text(groupBranch)
                                            .font(.system(size: 9, weight: .regular))
                                            .italic()
                                    }
                                    .foregroundStyle(CursorTheme.textTertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                }
                            }
                            ForEach(group.tabs) { t in
                                let isSelected = t.id == tabManager.selectedTabID
                                TabChip(
                                    title: t.title,
                                    subtitle: nil,
                                    workspacePath: nil,
                                    branchName: nil,
                                    isSelected: isSelected,
                                    isRunning: t.isRunning,
                                    latestTurnState: t.turns.last?.displayState,
                                    hasPrompted: !t.turns.isEmpty,
                                    showClose: tabManager.tabs.count > 1,
                                    compact: false,
                                    onSelect: { tabManager.selectedTabID = t.id },
                                    onClose: {
                                        stopStreaming(for: t)
                                        tabManager.closeTab(t.id)
                                    }
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: .infinity)

            Button(action: { tabManager.addTab(lastWorkspacePath: tab.workspacePath) }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CursorTheme.textSecondary)
                    .frame(width: 32, height: 32)
                    .frame(maxWidth: .infinity)
                    .background(CursorTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(CursorTheme.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
        .padding(.horizontal, Self.sidebarContentPadding)
        .frame(width: sidebarWidth)
        .padding(.trailing, 12)
    }

    // MARK: - Empty state (new tab)

    private var emptyStateContent: some View {
        let projectName = appState.workspaceDisplayName(for: tab.workspacePath).isEmpty
            ? ((tab.workspacePath as NSString).lastPathComponent.isEmpty ? "Project" : (tab.workspacePath as NSString).lastPathComponent)
            : appState.workspaceDisplayName(for: tab.workspacePath)
        let modelLabel = AvailableModels.model(for: selectedModel)?.label ?? "Auto"
        return VStack(spacing: 0) {
                Spacer(minLength: 24)
                VStack(spacing: 20) {
                    Text(projectName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(CursorTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(CursorTheme.textTertiary)
                            Text(tab.currentBranch.isEmpty ? "No branch" : tab.currentBranch)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(CursorTheme.textSecondary)
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "cpu")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(CursorTheme.textTertiary)
                            Text(modelLabel)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(CursorTheme.textSecondary)
                        }
                    }

                    Text("Ask a question below to start")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CursorTheme.textTertiary)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(CursorTheme.surfaceMuted.opacity(0.8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(CursorTheme.border, lineWidth: 1)
                        )
                )
                .frame(maxWidth: 320)
                Spacer(minLength: 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Output card

    private var outputCard: some View {
        OutputScrollView(
            tab: tab,
            scrollToken: tab.scrollToken,
            content: {
                VStack(alignment: .leading, spacing: 18) {
                    if tab.turns.isEmpty {
                        emptyStateContent
                    } else {
                        ForEach(tab.turns) { turn in
                            ConversationTurnView(turn: turn, workspacePath: tab.workspacePath)
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

    // MARK: - Composer dock

    private var composerDock: some View {
        let attachedPaths = screenshotPaths(from: tab.prompt)
        return VStack(alignment: .leading, spacing: 12) {
            QuickActionButtonsView(
                commands: quickActionCommands,
                isDisabled: tab.isRunning,
                workspacePath: workspacePath,
                onCommand: { sendInCurrentTab(prompt: $0.prompt) },
                onAdd: {},
                onCommandsChanged: { quickActionCommands = QuickActionStorage.commandsForWorkspace(workspacePath: workspacePath) }
            )

            queuedFollowUpsView

            ForEach(Array(attachedPaths.enumerated()), id: \.offset) { _, path in
                ScreenshotCardView(
                    path: path,
                    workspacePath: tab.workspacePath,
                    onDelete: { deleteScreenshot(path: path) }
                )
            }

            HStack(alignment: .bottom, spacing: 12) {
                ZStack(alignment: .topLeading) {
                    SubmittableTextEditor(
                        text: Binding(
                            get: { tab.prompt },
                            set: { newValue in
                                tab.prompt = newValue
                                tab.hasAttachedScreenshot = !screenshotPaths(from: newValue).isEmpty
                            }
                        ),
                        isDisabled: false,
                        onSubmit: submitOrQueuePrompt,
                        onPasteImage: pasteScreenshot,
                        onHeightChange: { newHeight in
                            composerTextHeight = newHeight
                        },
                        onFocusRequested: { focus, isFirstResponder in
                            focusPromptInput = focus
                            isPromptFirstResponder = isFirstResponder
                        }
                    )
                    .frame(height: composerHeight)

                    if tab.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Send message and/or ⌘V to paste one or more screenshots from clipboard")
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .foregroundStyle(CursorTheme.textTertiary)
                            .padding(.leading, 4)
                            .padding(.top, 6)
                            .padding(.trailing, 8)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                sendStopButton
                    .padding(.bottom, 2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(CursorTheme.editor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(CursorTheme.border, lineWidth: 1)
            )

            HStack(alignment: .center, spacing: 8) {
                viewInBrowserMenu

                WorkspacePickerView(
                    displayName: appState.workspaceDisplayName(for: tab.workspacePath),
                    folders: devFolders,
                    selectedPath: tab.workspacePath,
                    onSelectFolder: { path in
                        tabManager.addTab(lastWorkspacePath: path)
                        workspacePath = path
                        appState.workspacePath = path
                    },
                    onBrowse: {
                        appState.changeWorkspace { path in
                            tabManager.addTab(lastWorkspacePath: path)
                            workspacePath = path
                            appState.workspacePath = path
                        }
                    },
                    onAppear: { devFolders = loadDevFolders(rootPath: projectsRootPath) }
                )

                ModelPickerView(
                    selectedModelId: selectedModel,
                    models: AvailableModels.all,
                    onSelect: { selectedModel = $0 }
                )

                GitBranchPickerView(
                    branches: gitBranches,
                    currentBranch: currentBranch,
                    onSelectBranch: { branch in
                        if branch != currentBranch {
                            if let err = gitCheckout(branch: branch, workspacePath: tab.workspacePath) {
                                tab.errorMessage = err
                            } else {
                                let (cur, list) = loadGitBranches(workspacePath: tab.workspacePath)
                                currentBranch = cur
                                gitBranches = list
                                tab.currentBranch = cur
                                tab.errorMessage = nil
                            }
                        }
                    },
                    onAppear: {
                        let (cur, list) = loadGitBranches(workspacePath: tab.workspacePath)
                        currentBranch = cur
                        gitBranches = list
                        tab.currentBranch = cur
                    }
                )
                .onChange(of: tab.workspacePath) { _, _ in
                    let (cur, list) = loadGitBranches(workspacePath: tab.workspacePath)
                    currentBranch = cur
                    gitBranches = list
                    tab.currentBranch = cur
                }

                ComposerActionButtonsView(
                    showPinnedQuestionsPanel: $showPinnedQuestionsPanel,
                    hasContext: !tab.turns.isEmpty || !tab.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    isRunning: tab.isRunning,
                    contextUsed: estimatedContextTokens(
                        prompt: tab.prompt,
                        conversationCharacterCount: tab.cachedConversationCharacterCount
                    ).used,
                    contextLimit: AppLimits.contextTokenLimit
                )
            }
        }
        .padding(14)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
        )
    }

    private var viewInBrowserMenu: some View {
        Menu {
            Button("View in Browser") {
                if let urlString = ProjectSettingsStorage.getDebugURL(workspacePath: tab.workspacePath),
                   let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                } else {
                    showSetDebugURLSheet = true
                }
            }
            Button("Set debug URL…") {
                showSetDebugURLSheet = true
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                Text("View in Browser")
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
        .fixedSize(horizontal: true, vertical: false)
        .help("Open project debug URL in browser, or set it if not configured")
    }

    private var sendStopButton: some View {
        Button(action: {
            if tab.isRunning {
                stopStreaming()
            } else {
                submitOrQueuePrompt()
            }
        }) {
            Group {
                if tab.isRunning {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 10, weight: .black))
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                }
            }
            .foregroundStyle(CursorTheme.textPrimary)
            .frame(width: 28, height: 28)
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

    private var composerHeight: CGFloat {
        min(132, max(56, composerTextHeight + 16))
    }

    // MARK: - Helpers

    private func sanitizeSelectedModel() {
        guard AvailableModels.model(for: selectedModel) == nil else { return }
        selectedModel = AvailableModels.autoID
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

    @ViewBuilder
    private var queuedFollowUpsView: some View {
        if !tab.followUpQueue.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(tab.followUpQueue) { item in
                    HStack(spacing: 8) {
                        Text(item.text)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(CursorTheme.textPrimary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button(action: {
                            sendQueuedFollowUpToNewTab(item)
                        }) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(CursorTheme.textSecondary)
                                .frame(width: 24, height: 24)
                                .background(CursorTheme.surfaceRaised, in: Circle())
                        }
                        .buttonStyle(.plain)
                        Button(action: {
                            tab.followUpQueue.removeAll { $0.id == item.id }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(CursorTheme.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(CursorTheme.surfaceMuted.opacity(0.8), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    private var canSend: Bool {
        !tab.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Submit the current prompt: send immediately if idle, or queue as follow-up if agent is running.
    private func submitOrQueuePrompt() {
        let trimmed = tab.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if tab.isRunning {
            updateTabTitle(for: trimmed, in: tab)
            tab.followUpQueue.append(QueuedFollowUp(text: trimmed))
            tab.prompt = ""
            tab.hasAttachedScreenshot = false
            return
        }
        sendPrompt()
    }

    private static let compressPrompt = "Summarize our entire conversation so far into a single concise summary that preserves key context, decisions, and next steps. Reply with only that summary, no other text."

    /// Compress context: ask the agent to summarize the conversation, then replace context with that summary (new chat). If no context, clears instead.
    private func compressContext() {
        guard !tab.isRunning else { return }
        let hasContext = !tab.turns.isEmpty || !tab.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !hasContext {
            clearContext()
            return
        }
        tab.prompt = Self.compressPrompt
        tab.isCompressRequest = true
        sendPrompt()
    }

    private func clearContext() {
        guard !tab.isRunning else { return }
        tab.turns = []
        tab.cachedConversationCharacterCount = 0
        tab.prompt = ""
        tab.hasAttachedScreenshot = false
        tab.errorMessage = nil
    }

    private static func fullAssistantText(for turn: ConversationTurn) -> String {
        turn.segments
            .filter { $0.kind == .assistant }
            .map(\.text)
            .joined()
    }

    private func deleteScreenshot(path: String) {
        let reference = "\n\n[Screenshot attached: \(path)]"
        tab.prompt = tab.prompt.replacingOccurrences(of: reference, with: "")
        if !tab.prompt.contains("[Screenshot attached:") {
            tab.hasAttachedScreenshot = false
        }
        let imageURL = URL(fileURLWithPath: tab.workspacePath).appendingPathComponent(path)
        try? FileManager.default.removeItem(at: imageURL)
    }

    private func pasteScreenshot() {
        let currentPaths = screenshotPaths(from: tab.prompt)
        guard currentPaths.count < AppLimits.maxScreenshots,
              let relPath = nextScreenshotPath(currentPaths: currentPaths) else {
            return
        }

        let pasteboard = NSPasteboard.general
        guard let image = SubmittableTextEditor.imageFromPasteboard(pasteboard) else {
            return
        }

        let destURL = URL(fileURLWithPath: tab.workspacePath).appendingPathComponent(relPath)
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

    private func sendInCurrentTab(prompt: String) {
        guard !tab.isRunning else { return }
        tab.prompt = prompt
        sendPrompt()
    }

    private func sendQueuedFollowUpToNewTab(_ item: QueuedFollowUp) {
        let prompt = item.text
        let workspacePath = tab.workspacePath
        tab.followUpQueue.removeAll { $0.id == item.id }
        tabManager.addTab(initialPrompt: prompt, lastWorkspacePath: workspacePath)
        sendPrompt()
    }

    // MARK: - Streaming

    private func sendPrompt() {
        let currentTab = tab
        let trimmed = currentTab.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        updateTabTitle(for: trimmed, in: currentTab)

        let runID = UUID()
        let turnID = UUID()
        if currentTab.isCompressRequest {
            currentTab.pendingCompressRunID = runID
            currentTab.isCompressRequest = false
        }
        currentTab.streamTask?.cancel()
        currentTab.errorMessage = nil
        currentTab.isRunning = true
        currentTab.activeRunID = runID
        currentTab.activeTurnID = turnID
        currentTab.turns.append(ConversationTurn(id: turnID, userPrompt: trimmed, isStreaming: true, wasStopped: false))
        currentTab.cachedConversationCharacterCount += trimmed.count
        currentTab.prompt = ""
        currentTab.hasAttachedScreenshot = false
        requestAutoScroll(for: currentTab, force: true)
        messagesSentForUsage += 1

        let task = Task {
            do {
                if currentTab.cursorChatId == nil {
                    let chatId = try AgentRunner.createChat()
                    guard currentTab.activeRunID == runID else { return }
                    currentTab.cursorChatId = chatId
                }
                let stream = try AgentRunner.stream(prompt: trimmed, workspacePath: currentTab.workspacePath, model: selectedModel, conversationId: currentTab.cursorChatId)
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
                    requestAutoScroll(for: currentTab)
                }
                finishStreaming(for: currentTab, runID: runID, turnID: turnID)
            } catch is CancellationError {
                finishStreaming(for: currentTab, runID: runID, turnID: turnID)
            } catch let error as AgentRunnerError {
                finishStreaming(for: currentTab, runID: runID, turnID: turnID, errorMessage: error.userMessage)
            } catch {
                finishStreaming(for: currentTab, runID: runID, turnID: turnID, errorMessage: error.localizedDescription)
            }

            if currentTab.pendingCompressRunID == runID {
                Task { @MainActor in
                    let summary: String
                    if let idx = currentTab.turns.firstIndex(where: { $0.id == turnID }) {
                        summary = Self.fullAssistantText(for: currentTab.turns[idx])
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        summary = ""
                    }
                    currentTab.pendingCompressRunID = nil
                    do {
                        let newId = try AgentRunner.createChat()
                        currentTab.cursorChatId = newId
                        currentTab.turns = []
                        currentTab.cachedConversationCharacterCount = 0
                        currentTab.prompt = summary
                        currentTab.hasAttachedScreenshot = false
                        currentTab.errorMessage = nil
                    } catch {
                        currentTab.errorMessage = (error as? AgentRunnerError)?.userMessage ?? error.localizedDescription
                    }
                }
            }

            Task { @MainActor in
                if let first = currentTab.followUpQueue.first {
                    currentTab.followUpQueue.removeFirst()
                    currentTab.prompt = first.text
                    sendPrompt()
                }
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
            tabToStop.turns[index].wasStopped = true
            for segmentIndex in tabToStop.turns[index].segments.indices {
                if tabToStop.turns[index].segments[segmentIndex].toolCall?.status == .running {
                    tabToStop.turns[index].segments[segmentIndex].toolCall?.status = .stopped
                }
            }
        }
        tabToStop.activeRunID = nil
        tabToStop.activeTurnID = nil
        tabToStop.isRunning = false
        tabToStop.streamTask?.cancel()
        tabToStop.streamTask = nil
        requestAutoScroll(for: tabToStop, force: true)
    }

    private func finishStreaming(for currentTab: AgentTab, runID: UUID, turnID: UUID, errorMessage: String? = nil) {
        guard currentTab.activeRunID == runID else { return }
        if let index = currentTab.turns.firstIndex(where: { $0.id == turnID }) {
            currentTab.turns[index].isStreaming = false
            currentTab.turns[index].lastStreamPhase = nil
            currentTab.turns[index].wasStopped = false
        }
        currentTab.errorMessage = errorMessage
        currentTab.isRunning = false
        currentTab.streamTask = nil
        currentTab.activeRunID = nil
        currentTab.activeTurnID = nil
        requestAutoScroll(for: currentTab, force: true)
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
        tab.cachedConversationCharacterCount += incoming.count
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
            tab.cachedConversationCharacterCount += incoming.count
            return
        }

        let lastIndex = tab.turns[index].segments.count - 1
        let existing = tab.turns[index].segments[lastIndex].text

        if existing == incoming {
            return
        }

        if incoming.hasPrefix(existing) {
            tab.turns[index].segments[lastIndex].text = incoming
            tab.cachedConversationCharacterCount += incoming.count - existing.count
            return
        }

        tab.turns[index].segments[lastIndex].text += incoming
        tab.cachedConversationCharacterCount += incoming.count
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

    private func requestAutoScroll(for tab: AgentTab, force: Bool = false) {
        let now = CFAbsoluteTimeGetCurrent()
        guard force || now - tab.lastAutoScrollAt >= 0.12 else { return }
        tab.lastAutoScrollAt = now
        tab.scrollToken = UUID()
    }

    private func updateTabTitle(for prompt: String, in tab: AgentTab) {
        guard !tab.isCompressRequest,
              let generatedTitle = autoGeneratedTabTitle(from: prompt) else {
            return
        }
        tab.title = generatedTitle
    }
}
