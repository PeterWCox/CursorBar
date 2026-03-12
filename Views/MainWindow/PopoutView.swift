import SwiftUI
import AppKit

// MARK: - Sidebar tab group (by project)

private struct TabSidebarGroup {
    let path: String
    let displayName: String
    let tabs: [AgentTab]
}

/// Wrapper that observes a single tab so only this subtree re-renders when that tab streams.
/// Use for the active-tab content area so background tabs don't invalidate the whole window.
private struct ObservedTabView<Content: View>: View {
    @ObservedObject var tab: AgentTab
    @ViewBuilder let content: (AgentTab) -> Content
    var body: some View { content(tab) }
}

/// Sidebar chip that observes its tab so only this chip re-renders when that tab's state changes (e.g. isRunning).
private struct ObservedTabChip: View {
    @ObservedObject var tab: AgentTab
    let isSelected: Bool
    let showClose: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        TabChip(
            title: tab.title,
            subtitle: nil,
            workspacePath: nil,
            branchName: nil,
            isSelected: isSelected,
            isRunning: tab.isRunning,
            latestTurnState: tab.turns.last?.displayState,
            hasPrompted: !tab.turns.isEmpty,
            showClose: showClose,
            compact: false,
            onSelect: onSelect,
            onClose: onClose
        )
    }
}

// MARK: - Main popout panel view

struct PopoutView: View {
    @EnvironmentObject var appState: AppState
    var dismiss: () -> Void = {}
    @AppStorage("workspacePath") private var workspacePath: String = FileManager.default.homeDirectoryForCurrentUser.path
    @AppStorage(AppPreferences.projectsRootPathKey) private var projectsRootPath: String = AppPreferences.defaultProjectsRootPath
    @AppStorage(AppPreferences.preferredTerminalAppKey) private var preferredTerminalAppRawValue: String = PreferredTerminalApp.automatic.rawValue
    @AppStorage(AppPreferences.disabledModelIdsKey) private var disabledModelIdsRaw: String = ""
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
    @State private var showCreateDebugScriptSheet: Bool = false
    /// When set, show "Are you sure?" before closing this tab (agent still processing).
    @State private var closeTabConfirmationTabID: UUID? = nil
    @State private var screenshotPreviewURL: URL? = nil
    /// Workspace paths for groups that are collapsed in the sidebar (accordion).
    @State private var collapsedGroupPaths: Set<String> = []
    /// When set, the queued follow-up with this ID is in edit mode; draft text is in editingFollowUpDraft.
    @State private var editingFollowUpID: UUID? = nil
    @State private var editingFollowUpDraft: String = ""
    /// When true, hide main agent content and show only title bar + tab sidebar (uses AppState so panel can resize).
    private var isMainContentCollapsed: Bool { appState.isMainContentCollapsed }

    private var tab: AgentTab { tabManager.activeTab }

    /// Request to close a tab. If the agent is still running, shows a confirmation alert; otherwise closes immediately.
    private func requestCloseTab(_ tabToClose: AgentTab) {
        guard tabManager.tabs.count > 1 else { return }
        if tabToClose.isRunning {
            closeTabConfirmationTabID = tabToClose.id
        } else {
            stopStreaming(for: tabToClose)
            tabManager.closeTab(tabToClose.id)
        }
    }

    private func confirmCloseTab() {
        guard let id = closeTabConfirmationTabID else { return }
        if let tabToClose = tabManager.tabs.first(where: { $0.id == id }) {
            stopStreaming(for: tabToClose)
            tabManager.closeTab(id)
        }
        closeTabConfirmationTabID = nil
    }
    /// Adds a new agent tab and resets model to Auto so each new window starts with the default.
    private func addNewAgentTab(initialPrompt: String? = nil, lastWorkspacePath: String? = nil) {
        if appState.isMainContentCollapsed {
            withAnimation(.easeInOut(duration: 0.2)) { appState.isMainContentCollapsed = false }
        }
        tabManager.addTab(initialPrompt: initialPrompt, lastWorkspacePath: lastWorkspacePath)
        selectedModel = AvailableModels.autoID
        // Refresh branch for the new tab so empty state shows correct branch immediately (avoids "No branch" on first paint).
        let active = tabManager.activeTab
        let (cur, list) = loadGitBranches(workspacePath: active.workspacePath)
        currentBranch = cur
        gitBranches = list
        active.currentBranch = cur
    }
    private var preferredTerminalApp: PreferredTerminalApp {
        PreferredTerminalApp(rawValue: preferredTerminalAppRawValue) ?? .automatic
    }

    /// Models to show in the picker (respects "disabled" preference). Includes current selection if it was hidden so the UI stays consistent.
    private var modelPickerModels: [ModelOption] {
        let disabled = AppPreferences.disabledModelIds(from: disabledModelIdsRaw)
        var visible = AvailableModels.visible(disabledIds: disabled)
        if !visible.contains(where: { $0.id == selectedModel }), let current = AvailableModels.model(for: selectedModel) {
            visible = visible + [current]
        }
        return visible
    }

    private var apiUsagePercent: Int {
        min(100, (messagesSentForUsage * 100) / AppLimits.includedAPIQuota)
    }

    private let sidebarWidth: CGFloat = 250

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

            // Agent tabs (sidebar) never shrink or disappear. Only the agent window and user input area shrink when the window is narrowed.
            GeometryReader { geometry in
                let contentWidth = max(0, geometry.size.width)
                let agentWidth = isMainContentCollapsed ? 0 : max(0, contentWidth - sidebarWidth)
                HStack(alignment: .top, spacing: 0) {
                    // Tab sidebar: fixed width; never reduced or clipped.
                    tabSidebar
                        .frame(width: sidebarWidth)

                    // Agent window + composer: take remaining width; this is the only area that shrinks horizontally.
                    Group {
                        if isMainContentCollapsed {
                            Color.clear
                                .frame(width: 0)
                                .clipped()
                        } else {
                            ObservedTabView(tab: tabManager.activeTab) { tab in
                                agentAreaContent(tab: tab)
                            }
                        }
                    }
                    .frame(width: agentWidth)
                    .clipped()
                }
                .clipped()
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(minWidth: isMainContentCollapsed ? 260 : (sidebarWidth + 110), maxWidth: .infinity, minHeight: isMainContentCollapsed ? 280 : 400, maxHeight: .infinity)
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
        .sheet(isPresented: $showCreateDebugScriptSheet) {
            CreateDebugScriptSheet(
                workspacePath: tab.workspacePath,
                onSave: {
                    tab.errorMessage = nil
                },
                onRunAfterSave: {
                    runDebugScript()
                }
            )
        }
        .alert("Close tab while agent is running?", isPresented: Binding(
            get: { closeTabConfirmationTabID != nil },
            set: { if !$0 { closeTabConfirmationTabID = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                closeTabConfirmationTabID = nil
            }
            Button("Close Tab", role: .destructive) {
                confirmCloseTab()
            }
        } message: {
            Text("This agent is still processing. Closing will cancel the current run. Are you sure you want to close this tab?")
        }
        .overlay {
            if let url = screenshotPreviewURL {
                ScreenshotPreviewModal(imageURL: url, isPresented: Binding(
                    get: { true },
                    set: { if !$0 { screenshotPreviewURL = nil } }
                ))
            }
        }
        .overlay(
            Group {
                Button("Settings") {
                    appState.showSettingsSheet = true
                }
                .keyboardShortcut(",", modifiers: .command)
                .opacity(0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Button("New Tab") {
                    addNewAgentTab(lastWorkspacePath: tab.workspacePath)
                }
                .keyboardShortcut("t", modifiers: .command)
                .opacity(0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Button("Reopen Closed Tab") {
                    if tabManager.reopenLastClosedTab(), appState.isMainContentCollapsed {
                        withAnimation(.easeInOut(duration: 0.2)) { appState.isMainContentCollapsed = false }
                    }
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(tabManager.recentlyClosedTabs.isEmpty)
                .opacity(0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Button("New Tab") {
                    addNewAgentTab(lastWorkspacePath: tab.workspacePath)
                }
                .keyboardShortcut("n", modifiers: .command)
                .opacity(0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if tabManager.tabs.count > 1 {
                    Button("Close Tab") {
                        requestCloseTab(tabManager.activeTab)
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

                Button("Toggle main window") {
                    withAnimation(.easeInOut(duration: 0.2)) { appState.isMainContentCollapsed.toggle() }
                }
                .keyboardShortcut("b", modifiers: .command)
                .opacity(0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Button("Toggle main window") {
                    withAnimation(.easeInOut(duration: 0.2)) { appState.isMainContentCollapsed.toggle() }
                }
                .keyboardShortcut("s", modifiers: .command)
                .opacity(0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .allowsHitTesting(false)
        )
    }

    // MARK: - Unified header

    /// Light blue used for agent-tab progress spinner; reused for beta badge.
    private static let agentSpinnerBlue = Color(red: 0.45, green: 0.68, blue: 1.0)
    /// Amber for debug build badge (only visible in Debug configuration).
    private static let debugBadgeAmber = Color(red: 1.0, green: 0.6, blue: 0.2)

    /// True when built with Debug configuration (SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG).
    private static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Image("CursorMetroLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 36)

            Text("BETA")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Self.agentSpinnerBlue)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Self.agentSpinnerBlue.opacity(0.18), in: RoundedRectangle(cornerRadius: 4, style: .continuous))

            if Self.isDebugBuild && !isMainContentCollapsed {
                Text("DEBUG")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Self.debugBadgeAmber)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Self.debugBadgeAmber.opacity(0.22), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }

            Spacer()

            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { appState.isMainContentCollapsed.toggle() } }) {
                Image(systemName: isMainContentCollapsed ? "chevron.right.2" : "chevron.left.2")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CursorTheme.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(CursorTheme.surfaceMuted, in: Circle())
            }
            .buttonStyle(.plain)

            if !isMainContentCollapsed {
                Button(action: { appState.showSettingsSheet = true }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CursorTheme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(CursorTheme.surfaceMuted, in: Circle())
                }
                .buttonStyle(.plain)
            }

            Button(action: dismiss) {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CursorTheme.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(CursorTheme.surfaceMuted, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private static let sidebarContentPadding: CGFloat = 10

    private var tabSidebar: some View {
        VStack(spacing: 6) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(tabGroups, id: \.path) { group in
                        let isCollapsed = collapsedGroupPaths.contains(group.path)
                        VStack(alignment: .leading, spacing: 6) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if isCollapsed {
                                        collapsedGroupPaths.remove(group.path)
                                    } else {
                                        collapsedGroupPaths.insert(group.path)
                                    }
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                                            .font(.system(size: 8, weight: .semibold))
                                            .foregroundStyle(CursorTheme.textTertiary)
                                            .frame(width: 10, alignment: .leading)
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
                                    if !groupBranch.isEmpty && !isCollapsed {
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
                                        .padding(.leading, 14)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if !isCollapsed {
                                ForEach(group.tabs) { t in
                                    ObservedTabChip(
                                        tab: t,
                                        isSelected: t.id == tabManager.selectedTabID,
                                        showClose: tabManager.tabs.count > 1,
                                        onSelect: {
                                            tabManager.selectedTabID = t.id
                                            if appState.isMainContentCollapsed {
                                                withAnimation(.easeInOut(duration: 0.2)) { appState.isMainContentCollapsed = false }
                                            }
                                        },
                                        onClose: { requestCloseTab(t) }
                                    )
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: .infinity)

            Button(action: { addNewAgentTab(lastWorkspacePath: tab.workspacePath) }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text("New Agent")
                        .font(.system(size: 13, weight: .medium))
                    Spacer(minLength: 4)
                    Text("⌘T")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(CursorTheme.textTertiary)
                }
                .foregroundStyle(CursorTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(CursorTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(CursorTheme.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help("New tab (⌘T or ⌘N)")
            .padding(.top, 10)
        }
        .padding(.horizontal, Self.sidebarContentPadding)
        .frame(width: sidebarWidth)
        .clipped()
        .padding(.trailing, 12)
    }

    // MARK: - Agent area content (observed by tab; only this subtree re-renders when active tab streams)

    private func agentAreaContent(tab: AgentTab) -> some View {
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

            outputCard(tab: tab)
                .frame(maxHeight: .infinity)
                .id(tab.id)

            composerDock(tab: tab)
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) {
            if showPinnedQuestionsPanel {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    PinnedQuestionsStackView(tab: tab, onClose: { showPinnedQuestionsPanel = false })
                    Spacer(minLength: 0)
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Empty state (new tab)

    private func emptyStateContent(tab: AgentTab) -> some View {
        let projectName = appState.workspaceDisplayName(for: tab.workspacePath).isEmpty
            ? ((tab.workspacePath as NSString).lastPathComponent.isEmpty ? "Project" : (tab.workspacePath as NSString).lastPathComponent)
            : appState.workspaceDisplayName(for: tab.workspacePath)
        let modelLabel = AvailableModels.model(for: selectedModel)?.label ?? "Auto"
        // Use view's currentBranch when tab's is empty (e.g. new tab before onChange runs) so we don't flash "No branch".
        let branchDisplay = tab.currentBranch.isEmpty ? currentBranch : tab.currentBranch
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
                            Text(branchDisplay.isEmpty ? "No branch" : branchDisplay)
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

    private func outputCard(tab: AgentTab) -> some View {
        OutputScrollView(
            tab: tab,
            scrollToken: tab.scrollToken,
            content: {
                // VStack (not LazyVStack): LazyVStack in ScrollView can fail to re-layout when appending
                // a new turn, so nothing renders until e.g. switching tabs. Conversation length is
                // typically small; equatable + throttling keep redraw cost low.
                VStack(alignment: .leading, spacing: 18) {
                    if tab.turns.isEmpty {
                        emptyStateContent(tab: tab)
                    } else {
                        ForEach(tab.turns) { turn in
                            ConversationTurnView(turn: turn, workspacePath: tab.workspacePath, screenshotPreviewURL: $screenshotPreviewURL)
                                .equatable()
                                .id(turn.id)
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("outputEnd")
                }
                .scrollTargetLayout()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
        )
    }

    // MARK: - Composer dock

    private func composerDock(tab: AgentTab) -> some View {
        let attachedPaths = screenshotPaths(from: tab.prompt)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                QuickActionButtonsView(
                    commands: quickActionCommands,
                    isDisabled: tab.isRunning,
                    workspacePath: tab.workspacePath,
                    onCommand: { sendInCurrentTab(prompt: $0.prompt) },
                    // onDebug: { handleDebugAction() },
                    onAdd: {},
                    onCommandsChanged: { quickActionCommands = QuickActionStorage.commandsForWorkspace(workspacePath: tab.workspacePath) }
                )
                Spacer()
                ComposerActionButtonsView(
                    showPinnedQuestionsPanel: $showPinnedQuestionsPanel,
                    hasContext: !tab.turns.isEmpty || !tab.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    isRunning: tab.isRunning
                )
                openInCursorButton
                if gitHubRepositoryURL(workspacePath: tab.workspacePath) != nil {
                    openInCursorMoreMenu
                }
            }

            queuedFollowUpsView

            ForEach(Array(attachedPaths.enumerated()), id: \.offset) { _, path in
                ScreenshotCardView(
                    path: path,
                    workspacePath: tab.workspacePath,
                    onDelete: { deleteScreenshot(path: path) },
                    onTapPreview: { screenshotPreviewURL = URL(fileURLWithPath: tab.workspacePath).appendingPathComponent(path) }
                )
            }

            HStack(alignment: .bottom, spacing: 12) {
                ZStack(alignment: .topLeading) {
                    SubmittableTextEditor(
                        text: Binding(
                            get: { tab.prompt },
                            set: { newValue in
                                tab.prompt = newValue
                                tab.hasAttachedScreenshot = !screenshotPaths(from: tab.prompt).isEmpty
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

                    if userPromptDisplayText(from: tab.prompt).isEmpty {
                        Text("Send message and/or ⌘V to paste one or more screenshots from clipboard. Press Enter to submit and Shift+Enter for new line.")
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
                // viewInBrowserMenu

                WorkspacePickerView(
                    displayName: appState.workspaceDisplayName(for: tab.workspacePath),
                    folders: devFolders,
                    selectedPath: tab.workspacePath,
                    onSelectFolder: { path in
                        addNewAgentTab(lastWorkspacePath: path)
                        workspacePath = path
                        appState.workspacePath = path
                    },
                    onOpenMenu: { devFolders = loadDevFolders(rootPath: projectsRootPath) }
                )

                ModelPickerView(
                    selectedModelId: selectedModel,
                    models: modelPickerModels,
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
                    onOpenMenu: {
                        let (cur, list) = loadGitBranches(workspacePath: tab.workspacePath)
                        currentBranch = cur
                        gitBranches = list
                        tab.currentBranch = cur
                    },
                    onCreateBranch: { name in
                        if let err = gitCreateBranch(name: name, workspacePath: tab.workspacePath) {
                            return err
                        }
                        let (cur, list) = loadGitBranches(workspacePath: tab.workspacePath)
                        currentBranch = cur
                        gitBranches = list
                        tab.currentBranch = cur
                        tab.errorMessage = nil
                        return nil
                    }
                )
                .onChange(of: tab.workspacePath) { _, _ in
                    let (cur, list) = loadGitBranches(workspacePath: tab.workspacePath)
                    currentBranch = cur
                    gitBranches = list
                    tab.currentBranch = cur
                }

                Spacer()

                ContextUsageView(
                    contextUsed: estimatedContextTokens(
                        prompt: tab.prompt,
                        conversationCharacterCount: tab.cachedConversationCharacterCount
                    ).used,
                    contextLimit: AppLimits.contextTokenLimit
                )

                UsageView()
            }
        }
        .padding(14)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
        )
    }

    private var openInCursorButton: some View {
        Button {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", "Cursor", tab.workspacePath]
            try? process.run()
        } label: {
            HStack(spacing: 8) {
                Image("OpenInCursorIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                Text("Open in Cursor")
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(CursorTheme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(CursorTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(CursorTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .help("Open this workspace in Cursor")
    }

    /// Three-dot menu after "Open in Cursor": e.g. Open in Github when remote is GitHub.
    private var openInCursorMoreMenu: some View {
        Menu {
            if let githubURL = gitHubRepositoryURL(workspacePath: tab.workspacePath) {
                Button("Open in Github") {
                    NSWorkspace.shared.open(githubURL)
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CursorTheme.textPrimary)
                .frame(width: 28, height: 28)
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
        .help("More actions")
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
                        if editingFollowUpID == item.id {
                            TextField("Message", text: $editingFollowUpDraft, axis: .vertical)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(CursorTheme.textPrimary)
                                .lineLimit(2 ... 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .onSubmit { applyEditedFollowUp(itemID: item.id) }
                            Button(action: {
                                applyEditedFollowUp(itemID: item.id)
                            }) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(CursorTheme.textPrimary)
                            }
                            .buttonStyle(.plain)
                            .help("Save")
                            Button(action: {
                                editingFollowUpID = nil
                                editingFollowUpDraft = ""
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(CursorTheme.textTertiary)
                            }
                            .buttonStyle(.plain)
                            .help("Cancel")
                        } else {
                            Text(item.text)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(CursorTheme.textPrimary)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button(action: {
                                sendQueuedFollowUpToNewTab(item)
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 13, weight: .semibold))
                                    Text("New Agent")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundStyle(CursorTheme.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(CursorTheme.surfaceRaised, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .help("Send to new agent")
                            Button(action: {
                                editingFollowUpID = item.id
                                editingFollowUpDraft = item.text
                            }) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(CursorTheme.textSecondary)
                            }
                            .buttonStyle(.plain)
                            .help("Edit message")
                            Button(action: {
                                tab.followUpQueue.removeAll { $0.id == item.id }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(CursorTheme.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(CursorTheme.surfaceMuted.opacity(0.8), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    private func applyEditedFollowUp(itemID: UUID) {
        guard let idx = tab.followUpQueue.firstIndex(where: { $0.id == itemID }) else {
            editingFollowUpID = nil
            editingFollowUpDraft = ""
            return
        }
        let trimmed = editingFollowUpDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            tab.followUpQueue.remove(at: idx)
        } else {
            let existing = tab.followUpQueue[idx]
            tab.followUpQueue[idx] = QueuedFollowUp(id: existing.id, text: trimmed)
        }
        editingFollowUpID = nil
        editingFollowUpDraft = ""
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

    private func handleDebugAction() {
        if debugScriptExists(workspacePath: tab.workspacePath) {
            runDebugScript()
        } else {
            showCreateDebugScriptSheet = true
        }
    }

    private func runDebugScript() {
        if let error = launchDebugScript(
            workspacePath: tab.workspacePath,
            preferredTerminal: preferredTerminalApp
        ) {
            tab.errorMessage = error
            return
        }

        tab.errorMessage = nil
    }

    private func sendQueuedFollowUpToNewTab(_ item: QueuedFollowUp) {
        let prompt = item.text
        let workspacePath = tab.workspacePath
        tab.followUpQueue.removeAll { $0.id == item.id }
        addNewAgentTab(initialPrompt: prompt, lastWorkspacePath: workspacePath)
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
                // Coalesce text chunks and flush at ~100ms to reduce main-actor and UI churn during long runs.
                var thinkingBuffer = ""
                var assistantBuffer = ""
                var flushTask: Task<Void, Never>?
                let flushIntervalNs: UInt64 = 100_000_000 // 100ms
                func flushBatched() {
                    if !thinkingBuffer.isEmpty {
                        appendThinkingText(thinkingBuffer, to: turnID, in: currentTab)
                        thinkingBuffer = ""
                    }
                    if !assistantBuffer.isEmpty {
                        mergeAssistantText(assistantBuffer, into: currentTab, turnID: turnID)
                        assistantBuffer = ""
                    }
                    requestAutoScroll(for: currentTab)
                }
                func scheduleFlush() {
                    flushTask?.cancel()
                    flushTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: flushIntervalNs)
                        guard currentTab.activeRunID == runID, currentTab.activeTurnID == turnID else { return }
                        flushBatched()
                        flushTask = nil
                    }
                }
                for try await chunk in stream {
                    guard currentTab.activeRunID == runID, currentTab.activeTurnID == turnID, !Task.isCancelled else { return }
                    switch chunk {
                    case .thinkingDelta(let text):
                        thinkingBuffer += text
                        scheduleFlush()
                    case .thinkingCompleted:
                        flushBatched()
                        completeThinking(for: turnID, in: currentTab)
                        requestAutoScroll(for: currentTab)
                    case .assistantText(let text):
                        assistantBuffer += text
                        scheduleFlush()
                    case .toolCall(let update):
                        flushBatched()
                        mergeToolCall(update, into: currentTab, turnID: turnID)
                        requestAutoScroll(for: currentTab)
                    }
                }
                flushTask?.cancel()
                flushBatched()
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
            notifyTurnsChanged(tabToStop)
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
            notifyTurnsChanged(currentTab)
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
        notifyTurnsChangedIfThrottled(tab)
    }

    private func completeThinking(for turnID: UUID, in tab: AgentTab) {
        guard let index = tab.turns.firstIndex(where: { $0.id == turnID }) else { return }
        if tab.turns[index].lastStreamPhase == .thinking {
            tab.turns[index].lastStreamPhase = nil
            notifyTurnsChanged(tab)
        }
    }

    private func mergeAssistantText(_ incoming: String, into tab: AgentTab, turnID: UUID) {
        guard !incoming.isEmpty else { return }
        guard let index = tab.turns.firstIndex(where: { $0.id == turnID }) else { return }

        tab.turns[index].lastStreamPhase = .assistant

        if tab.turns[index].segments.last?.kind != .assistant {
            tab.turns[index].segments.append(ConversationSegment(kind: .assistant, text: incoming))
            tab.cachedConversationCharacterCount += incoming.count
            notifyTurnsChangedIfThrottled(tab)
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
        } else {
            tab.turns[index].segments[lastIndex].text += incoming
            tab.cachedConversationCharacterCount += incoming.count
        }
        notifyTurnsChangedIfThrottled(tab)
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
            notifyTurnsChanged(tab)
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
        notifyTurnsChanged(tab)
    }

    /// Notify SwiftUI that turns (or nested segment state) changed so the view refreshes.
    /// In-place mutations to turns/segments don't trigger @Published.
    private func notifyTurnsChanged(_ tab: AgentTab) {
        Task { @MainActor in
            tab.objectWillChange.send()
        }
    }

    /// Throttled notification for streaming text updates (~100ms) to reduce CPU from per-token re-renders.
    /// Call notifyTurnsChanged directly when streaming ends or for discrete events (e.g. tool calls).
    private func notifyTurnsChangedIfThrottled(_ tab: AgentTab) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - tab.lastStreamUIUpdateAt >= 0.1 else { return }
        tab.lastStreamUIUpdateAt = now
        notifyTurnsChanged(tab)
    }

    /// Only update scroll token when this tab is the selected one (visible), so background streaming doesn't do scroll work.
    private func requestAutoScroll(for tab: AgentTab, force: Bool = false) {
        guard tab.id == tabManager.selectedTabID else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard force || now - tab.lastAutoScrollAt >= 0.15 else { return }
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
