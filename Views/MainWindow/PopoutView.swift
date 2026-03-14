import SwiftUI
import AppKit
#if DEBUG
import Inject
#endif

// MARK: - Tasks view Cmd+T coordinator (so key monitor can trigger SwiftUI state)
private final class TasksViewShortcutCoordinator: ObservableObject {
    var onTrigger: (() -> Void)?
    var keyMonitor: Any?

    deinit {
        //
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }
}

/// Installs Cmd+T key monitor when Tasks panel is visible so shortcuts work when focus is inside the list.
/// Also handles appState.requestShowTasksAndNewTask (from panel performKeyEquivalent) so Cmd+T always works when the panel is key.
private struct TasksViewShortcutMonitorModifier: ViewModifier {
    @ObservedObject var tabManager: TabManager
    let selectedProjectPath: String?
    @Binding var tasksViewTriggerAddNew: Bool
    @ObservedObject var coordinator: TasksViewShortcutCoordinator
    @Binding var requestShowTasksAndNewTask: Bool
    var onRequestNewTask: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear { installMonitorIfNeeded() }
            .onChange(of: tabManager.selectedTasksViewPath) { _, _ in installMonitorIfNeeded() }
            .onChange(of: tabManager.selectedProjectPath) { _, _ in installMonitorIfNeeded() }
            .onChange(of: tabManager.selectedTerminalID) { _, _ in installMonitorIfNeeded() }
            .onChange(of: requestShowTasksAndNewTask) { _, requested in
                if requested {
                    requestShowTasksAndNewTask = false
                    onRequestNewTask()
                }
            }
    }

    private func installMonitorIfNeeded() {
        let tasksVisible = tabManager.selectedTerminalID == nil
            && tabManager.selectedTasksViewPath != nil
            && tabManager.selectedTasksViewPath == selectedProjectPath
        if tasksVisible {
            coordinator.onTrigger = { tasksViewTriggerAddNew = true }
            if coordinator.keyMonitor == nil {
                let coord = coordinator
                coordinator.keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    let key = event.charactersIgnoringModifiers?.lowercased()
                    let isCmdT = mods.contains(.command) && key == "t"
                    if isCmdT {
                        DispatchQueue.main.async { coord.onTrigger?() }
                        return nil
                    }
                    return event
                }
            }
        } else {
            if let m = coordinator.keyMonitor {
                NSEvent.removeMonitor(m)
                coordinator.keyMonitor = nil
            }
            coordinator.onTrigger = nil
        }
    }
}

// MARK: - Sidebar tab group (by project)

private struct TabSidebarGroup {
    let path: String
    let displayName: String
    let tabs: [AgentTab]
    let terminalTabs: [TerminalTab]
}

/// Wrapper that observes a single tab so only this subtree re-renders when that tab streams.
/// Use for the active-tab content area so background tabs don't invalidate the whole window.
private struct ObservedTabView<Content: View>: View {
    @ObservedObject var tab: AgentTab
    @ViewBuilder let content: (AgentTab) -> Content
    var body: some View { content(tab) }
}

/// Sidebar chip for a terminal tab (terminal icon + title).
private struct TerminalTabChip: View {
    @Environment(\.colorScheme) private var colorScheme
    let terminalTab: TerminalTab
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? CursorTheme.textPrimary(for: colorScheme) : CursorTheme.textSecondary(for: colorScheme))
                Text(terminalTab.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? CursorTheme.textPrimary(for: colorScheme) : CursorTheme.textSecondary(for: colorScheme))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                isSelected ? CursorTheme.surfaceRaised(for: colorScheme) : CursorTheme.surfaceMuted(for: colorScheme),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? CursorTheme.borderStrong(for: colorScheme) : CursorTheme.border(for: colorScheme).opacity(0.6), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
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
    #if DEBUG
    @ObserveInjection var inject
    #endif
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    var dismiss: () -> Void = {}
    @AppStorage("workspacePath") private var workspacePath: String = FileManager.default.homeDirectoryForCurrentUser.path
    @AppStorage(AppPreferences.projectsRootPathKey) private var projectsRootPath: String = AppPreferences.defaultProjectsRootPath
    @AppStorage(AppPreferences.preferredTerminalAppKey) private var preferredTerminalAppRawValue: String = PreferredTerminalApp.automatic.rawValue
    @AppStorage(AppPreferences.disabledModelIdsKey) private var disabledModelIdsRaw: String = AppPreferences.defaultDisabledModelIdsRaw
    @AppStorage("selectedModel") private var selectedModel: String = AvailableModels.autoID
    @AppStorage("messagesSentForUsage") private var messagesSentForUsage: Int = 0
    @AppStorage("showPinnedQuestionsPanel") private var showPinnedQuestionsPanel: Bool = true
    @EnvironmentObject var tabManager: TabManager

    /// App always uses dark mode; theme picker is disabled.
    private var resolvedColorScheme: ColorScheme? { .dark }
    @State private var devFolders: [URL] = []
    @State private var gitBranches: [String] = []
    @State private var currentBranch: String = ""
    @State private var quickActionCommands: [QuickActionCommand] = []
    @State private var composerTextHeight: CGFloat = 24
    @State private var showCreateDebugScriptSheet: Bool = false
    /// When set, show "Are you sure?" before closing this tab (agent still processing).
    @State private var closeTabConfirmationTabID: UUID? = nil
    @State private var screenshotPreviewURL: URL? = nil
    /// Workspace paths for groups that are collapsed in the sidebar (accordion).
    @State private var collapsedGroupPaths: Set<String> = []
    /// When set, the queued follow-up with this ID is in edit mode; draft text is in editingFollowUpDraft.
    @State private var editingFollowUpID: UUID? = nil
    @State private var editingFollowUpDraft: String = ""
    /// When true, Cmd+T in Tasks view should add a new task; set by window-level shortcut and observed by TasksListView.
    @State private var tasksViewTriggerAddNew: Bool = false
    @State private var dashboardTabsByWorkspacePath: [String: DashboardTab] = [:]
    @StateObject private var tasksViewShortcutCoordinator = TasksViewShortcutCoordinator()
    /// Tab whose agent header prompt accordion is expanded (show full prompt below title).
    @State private var expandedPromptTabID: UUID? = nil
    /// When true, hide main agent content and show only title bar + tab sidebar (uses AppState so panel can resize).
    private var isMainContentCollapsed: Bool { appState.isMainContentCollapsed }

    /// Active tab when there is at least one; otherwise nil (splash state).
    private var tab: AgentTab? { tabManager.activeTab }

    private var selectedProjectPath: String? {
        tabManager.activeProjectPath
    }

    private var hasOpenProjects: Bool {
        appState.openProjectCount > 0
    }

    /// Workspace path for the current context: active tab's workspace, selected project, or app storage fallback.
    private var currentWorkspacePath: String {
        tab?.workspacePath ?? selectedProjectPath ?? workspacePath
    }

    private func previewURL(for workspacePath: String) -> URL? {
        guard let urlString = ProjectSettingsStorage.getDebugURL(workspacePath: workspacePath) else {
            return nil
        }
        return URL(string: urlString)
    }

    private func openPreview(for workspacePath: String) {
        guard let url = previewURL(for: workspacePath) else { return }
        openURLInChrome(url)
    }


    /// Request to close a tab. If the agent is still running, shows a confirmation alert; otherwise closes immediately.
    private func requestCloseTab(_ tabToClose: AgentTab) {
        if tabToClose.isRunning {
            closeTabConfirmationTabID = tabToClose.id
        } else {
            stopStreaming(for: tabToClose)
            tabManager.closeTab(tabToClose.id)
        }
    }

    /// Agent status linked to this task for sidebar and task list display.
    private func linkedTaskState(for tab: AgentTab) -> AgentTaskState? {
        guard let taskID = tab.linkedTaskID else { return nil }
        let tasks = ProjectTasksStorage.tasks(workspacePath: tab.workspacePath)
        guard let task = tasks.first(where: { $0.id == taskID }) else { return nil }
        if task.taskState == .backlog { return .none }
        if tab.isRunning { return .processing }
        if tab.turns.last?.displayState == .stopped { return .stopped }
        if tab.turns.last?.displayState == .completed { return .review }
        return .todo
    }

    /// Agent status of a task in this workspace if any agent tab is linked to it.
    private func linkedTaskStateForTask(taskID: UUID, workspacePath: String) -> AgentTaskState? {
        guard let tab = tabManager.tabs.first(where: { $0.workspacePath == workspacePath && $0.linkedTaskID == taskID }) else { return nil }
        return linkedTaskState(for: tab)
    }

    /// Builds [taskID: status] for the given workspace so the Tasks list has an explicit dependency on tab state and updates when linked tabs run/complete.
    private func linkedStatusesForWorkspace(_ workspacePath: String) -> [UUID: AgentTaskState] {
        var result: [UUID: AgentTaskState] = [:]
        for tab in tabManager.tabs where tab.workspacePath == workspacePath {
            guard let taskID = tab.linkedTaskID else { continue }
            result[taskID] = linkedTaskState(for: tab)
        }
        return result
    }

    private func showTasksComposer(workspacePath path: String?, startNewTask: Bool = true) {
        let resolved = (path ?? tabManager.activeProjectPath ?? currentWorkspacePath)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolved.isEmpty else { return }
        tabManager.addProject(path: resolved, select: true)
        if appState.isMainContentCollapsed {
            withAnimation(.easeInOut(duration: 0.2)) { appState.isMainContentCollapsed = false }
        }
        tabManager.showTasksView(workspacePath: resolved)
        if startNewTask {
            // Defer so TasksListView is in the hierarchy first; then onChange(triggerAddNewTask) will fire.
            DispatchQueue.main.async {
                tasksViewTriggerAddNew = true
            }
        }
    }

    private func selectLinkedAgentTab(_ tabID: UUID) {
        guard tabManager.selectAgentTab(id: tabID) else { return }
        if appState.isMainContentCollapsed {
            withAnimation(.easeInOut(duration: 0.2)) { appState.isMainContentCollapsed = false }
        }
    }

    private func openLinkedAgent(for task: ProjectTask, workspacePath: String) {
        if let agentTabID = ProjectTasksStorage.linkedAgentTabID(workspacePath: workspacePath, taskID: task.id),
           tabManager.tabs.contains(where: { $0.id == agentTabID }) {
            selectLinkedAgentTab(agentTabID)
            return
        }
        if tabManager.reopenLinkedTaskTab(
            workspacePath: workspacePath,
            taskID: task.id,
            preferredTabID: ProjectTasksStorage.linkedAgentTabID(workspacePath: workspacePath, taskID: task.id)
        ) {
            return
        }
        guard let tab = tabManager.tabs.first(where: { $0.workspacePath == workspacePath && $0.linkedTaskID == task.id }) else { return }
        ProjectTasksStorage.assignAgentTab(workspacePath: workspacePath, taskID: task.id, agentTabID: tab.id)
        selectLinkedAgentTab(tab.id)
    }

    private func sendTaskToAgent(prompt: String, taskID: UUID, screenshotPaths: [String], modelId: String, workspacePath: String, selectAgent: Bool = false) {
        if let existingAgentTabID = ProjectTasksStorage.linkedAgentTabID(workspacePath: workspacePath, taskID: taskID),
           tabManager.tabs.contains(where: { $0.id == existingAgentTabID }) {
            if selectAgent {
                selectLinkedAgentTab(existingAgentTabID)
            }
            return
        }

        var initialPrompt = prompt
        for path in screenshotPaths {
            initialPrompt += "\n\n[Screenshot attached: .metro/\(path)]"
        }

        if let newTab = addNewAgentTab(
            initialPrompt: initialPrompt,
            lastWorkspacePath: workspacePath,
            modelId: modelId,
            select: selectAgent
        ) {
            newTab.linkedTaskID = taskID
            ProjectTasksStorage.assignAgentTab(workspacePath: workspacePath, taskID: taskID, agentTabID: newTab.id)
            if !screenshotPaths.isEmpty {
                newTab.hasAttachedScreenshot = true
            }
        }
    }

    private func createLinkedTaskAndAgent(taskContent: String, agentPrompt: String? = nil, workspacePath: String, modelId: String = AvailableModels.autoID, selectAgent: Bool = true) {
        let trimmedTaskContent = taskContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAgentPrompt = (agentPrompt ?? taskContent).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTaskContent.isEmpty, !trimmedAgentPrompt.isEmpty else { return }

        let task = ProjectTasksStorage.addTask(workspacePath: workspacePath, content: trimmedTaskContent, modelId: modelId)
        sendTaskToAgent(
            prompt: trimmedAgentPrompt,
            taskID: task.id,
            screenshotPaths: task.screenshotPaths,
            modelId: task.modelId,
            workspacePath: workspacePath,
            selectAgent: selectAgent
        )
        appState.notifyTasksDidUpdate()
    }

    private func tasksListContent(tasksPath: String, triggerAddNewTask: Binding<Bool>) -> some View {
        let linkedStatuses = linkedStatusesForWorkspace(tasksPath)
        return TasksListView(
            workspacePath: tasksPath,
            triggerAddNewTask: triggerAddNewTask,
            linkedStatuses: linkedStatuses,
            models: modelPickerModels(including: nil),
            onSendToAgent: { prompt, taskID, screenshotPaths, modelId in
                if let taskID {
                    sendTaskToAgent(
                        prompt: prompt,
                        taskID: taskID,
                        screenshotPaths: screenshotPaths,
                        modelId: modelId,
                        workspacePath: tasksPath,
                        selectAgent: false
                    )
                }
                // Keep user on Tasks view; do not switch to the new agent tab
            },
            onOpenLinkedAgent: { task in
                openLinkedAgent(for: task, workspacePath: tasksPath)
            },
            onTasksDidUpdate: { appState.notifyTasksDidUpdate() },
            onDismiss: { tabManager.hideTasksView() }
        )
        .id(tasksPath)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
    }

    private func dashboardContent(dashboardPath: String) -> some View {
        DashboardView(
            workspacePath: dashboardPath,
            onDismiss: { tabManager.hideDashboardView() },
            onRemoveProject: {
                removeProject(workspacePath: dashboardPath)
            },
            selectedTab: Binding(
                get: { dashboardTabsByWorkspacePath[dashboardPath] ?? .preview },
                set: { dashboardTabsByWorkspacePath[dashboardPath] = $0 }
            ),
            onLaunchSetupAgent: { path in
                _ = addNewAgentTab(initialPrompt: DashboardView.setupAgentPrompt, lastWorkspacePath: path)
                tabManager.hideDashboardView()
            }
        )
        .id(dashboardPath)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
    }

    /// Removes a project (all tabs for that workspace path) from the sidebar. Stops any running agents first.
    private func removeProject(workspacePath path: String) {
        for t in tabManager.tabs where t.workspacePath == path {
            stopStreaming(for: t)
        }
        tabManager.removeProject(path)
    }

    /// Opens the folder picker and always creates a new agent tab for the chosen project.
    private func addProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = "Select Workspace"
        panel.message = "Choose the repository directory where Cursor agent will work."

        if !workspacePath.isEmpty && FileManager.default.fileExists(atPath: workspacePath) {
            panel.directoryURL = URL(fileURLWithPath: workspacePath)
        } else {
            panel.directoryURL = URL(fileURLWithPath: AppPreferences.resolvedProjectsRootPath(projectsRootPath))
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        openProjectInNewAgentTab(url.path)
    }

    private func openProjectInNewAgentTab(_ path: String) {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return }

        tabManager.addProject(path: trimmedPath, select: true)
        showTasksComposer(workspacePath: trimmedPath, startNewTask: true)
        workspacePath = trimmedPath
        appState.workspacePath = trimmedPath

        let (cur, list) = loadGitBranches(workspacePath: trimmedPath)
        currentBranch = cur
        gitBranches = list
        tabManager.activeTab?.errorMessage = nil
        tabManager.activeTab?.currentBranch = cur
    }

    private func openProjectInCursor(_ path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Cursor", path]
        try? process.run()
    }

    private func openCurrentProjectInCursor() {
        guard hasOpenProjects else {
            addProject()
            return
        }
        let path = currentWorkspacePath
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return }
        openProjectInCursor(path)
    }

    private func focusDashboardTab(_ tab: DashboardTab) {
        guard hasOpenProjects else {
            addProject()
            return
        }
        let path = currentWorkspacePath
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return }
        dashboardTabsByWorkspacePath[path] = tab
        tabManager.showDashboardView(workspacePath: path)
        if appState.isMainContentCollapsed {
            withAnimation(.easeInOut(duration: 0.2)) { appState.isMainContentCollapsed = false }
        }
    }

    private var globalShortcutOverlay: some View {
        Group {
            hiddenShortcutButton("Settings", key: ",") {
                appState.showSettingsSheet = true
            }

            hiddenShortcutButton("Open in Browser", key: "o") {
                openInBrowserOrShowSetURLSheet()
            }

            hiddenShortcutButton("Open in Cursor", key: ".") {
                openCurrentProjectInCursor()
            }

            hiddenShortcutButton("New Task", key: "t") {
                showTasksComposer(workspacePath: selectedProjectPath, startNewTask: true)
            }

            hiddenShortcutButton("Reopen Closed Tab", key: "t", modifiers: [.command, .shift]) {
                if tabManager.reopenLastClosedTab(), appState.isMainContentCollapsed {
                    withAnimation(.easeInOut(duration: 0.2)) { appState.isMainContentCollapsed = false }
                }
            }
            .disabled(tabManager.recentlyClosedTabs.isEmpty)

            if let active = tabManager.activeTab, tabManager.tabs.count >= 1 {
                hiddenShortcutButton("Close Tab", key: "w") {
                    requestCloseTab(active)
                }
            }

            if let activeTerminal = tabManager.activeTerminalTab {
                hiddenShortcutButton("Close Terminal", key: "w") {
                    tabManager.closeTerminalTab(activeTerminal.id)
                }
            }

            // Only claim Control+C when an agent tab is active so the terminal can receive it for SIGINT.
            if tabManager.activeTerminalTab == nil {
                hiddenShortcutButton("Stop Agent", key: "c", modifiers: .control) {
                    if tabManager.activeTab?.isRunning == true {
                        stopStreaming()
                    }
                }
            }

            hiddenShortcutButton("Toggle main window", key: "b") {
                withAnimation(.easeInOut(duration: 0.2)) { appState.isMainContentCollapsed.toggle() }
            }

            hiddenShortcutButton("Toggle main window", key: "s") {
                withAnimation(.easeInOut(duration: 0.2)) { appState.isMainContentCollapsed.toggle() }
            }
        }
        .allowsHitTesting(false)
    }

    private func hiddenShortcutButton(
        _ title: String,
        key: KeyEquivalent,
        modifiers: EventModifiers = .command,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .keyboardShortcut(key, modifiers: modifiers)
            .opacity(0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openProjectOnGitHub(_ path: String) {
        guard let githubURL = gitHubRepositoryURL(workspacePath: path) else { return }
        NSWorkspace.shared.open(githubURL)
    }

    private func runGitInit(workspacePath path: String) {
        guard gitInit(workspacePath: path) == nil else { return }
        if path == tabManager.activeProjectPath, let active = tabManager.activeTab {
            let (cur, list) = loadGitBranches(workspacePath: path)
            currentBranch = cur
            gitBranches = list
            active.currentBranch = cur
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
    /// Adds a new agent tab. If initialPrompt is provided, the prompt is submitted automatically (e.g. when sending a task from the Tasks list).
    /// When modelId is provided (e.g. from a task), that tab uses that model; otherwise the tab uses the app default (Auto) until the user changes it.
    /// When select is false, the new tab is created but the current view (e.g. Tasks list) is not changed.
    /// Returns the new tab so callers can set linkedTaskID etc.
    @discardableResult
    private func addNewAgentTab(initialPrompt: String? = nil, lastWorkspacePath: String? = nil, modelId: String? = nil, select: Bool = true) -> AgentTab? {
        let targetWorkspacePath = lastWorkspacePath ?? tabManager.activeProjectPath
        guard let targetWorkspacePath else { return nil }
        if appState.isMainContentCollapsed {
            withAnimation(.easeInOut(duration: 0.2)) { appState.isMainContentCollapsed = false }
        }
        guard let newTab = tabManager.addTab(initialPrompt: initialPrompt, workspacePath: targetWorkspacePath, modelId: modelId, select: select) else { return nil }
        // Refresh branch for the new tab so empty state shows correct branch immediately (avoids "No branch" on first paint).
        let (cur, list) = loadGitBranches(workspacePath: newTab.workspacePath)
        currentBranch = cur
        gitBranches = list
        newTab.currentBranch = cur
        if let prompt = initialPrompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sendPrompt(tab: newTab)
        }
        return newTab
    }

    /// Adds a new terminal tab for the given or current project.
    private func addNewTerminalTab(lastWorkspacePath: String? = nil) {
        let targetWorkspacePath = lastWorkspacePath ?? tabManager.activeProjectPath
        guard let targetWorkspacePath else { return }
        if appState.isMainContentCollapsed {
            withAnimation(.easeInOut(duration: 0.2)) { appState.isMainContentCollapsed = false }
        }
        tabManager.addTerminalTab(workspacePath: targetWorkspacePath)
    }
    private var preferredTerminalApp: PreferredTerminalApp {
        PreferredTerminalApp(rawValue: preferredTerminalAppRawValue) ?? .automatic
    }

    /// Models to show in the picker (respects "disabled" preference; uses default-enabled set when never set). Includes effectiveSelection if it was hidden so the UI stays consistent.
    private func modelPickerModels(including effectiveSelection: String? = nil) -> [ModelOption] {
        let allIds = Set(appState.availableModels.map(\.id))
        let disabled = AppPreferences.effectiveDisabledModelIds(allIds: allIds, raw: disabledModelIdsRaw)
        var visible = appState.visibleModels(disabledIds: disabled)
        let currentId = effectiveSelection ?? selectedModel
        if !visible.contains(where: { $0.id == currentId }), let current = appState.model(for: currentId) {
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

    /// Linked agent tabs are shown only for in-progress tasks that still need agent visibility.
    private func isAgentTabVisibleInSidebar(_ tab: AgentTab) -> Bool {
        guard let taskID = tab.linkedTaskID else { return true }
        guard let task = ProjectTasksStorage.task(workspacePath: tab.workspacePath, id: taskID) else { return false }
        guard task.taskState == .inProgress else { return false }
        let agentState = linkedTaskState(for: tab)
        return agentState == .processing || agentState == .review || agentState == .stopped
    }

    /// Tabs grouped by workspace path, order preserved by first occurrence. Linked agent tabs only appear while their tasks are actively in progress.
    private var tabGroups: [TabSidebarGroup] {
        _ = appState.taskListRevision
        let visibleTabs = tabManager.tabs.filter { isAgentTabVisibleInSidebar($0) }
        let groupedTabs = Dictionary(grouping: visibleTabs, by: \.workspacePath)
        let groupedTerminals = Dictionary(grouping: tabManager.terminalTabs, by: \.workspacePath)
        return tabManager.projects.map { project in
            let path = project.path
            let displayName = appState.workspaceDisplayName(for: path)
            return TabSidebarGroup(
                path: path,
                displayName: displayName.isEmpty ? "Project" : displayName,
                tabs: groupedTabs[path] ?? [],
                terminalTabs: groupedTerminals[path] ?? []
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
                        .fill(CursorTheme.border(for: colorScheme).opacity(0.9))
                        .frame(height: 1)
                }

            // Agent tabs and projects sidebar always visible. When collapsed, only the main agent content is hidden; sidebar stays full width.
            GeometryReader { geometry in
                let contentWidth = max(0, geometry.size.width)
                let effectiveSidebarWidth = sidebarWidth
                let agentWidth = isMainContentCollapsed ? 0 : max(0, contentWidth - effectiveSidebarWidth)
                HStack(alignment: .top, spacing: 0) {
                    // Tab sidebar: always full width (projects + agent tabs visible even when collapsed).
                    tabSidebar
                        .frame(width: effectiveSidebarWidth)
                        .clipped()

                    // Agent window + composer: takes remaining width when expanded; 0 width when collapsed.
                    // Terminal views are always kept in the hierarchy (hidden when not selected) so switching
                    // back from Agent to Terminal preserves the shell session instead of starting a new process.
                    Group {
                        if isMainContentCollapsed {
                            Color.clear
                                .frame(width: 0)
                                .clipped()
                        } else {
                            ZStack {
                                ForEach(tabManager.terminalTabs) { tab in
                                    EmbeddedTerminalView(
                                        workspacePath: tab.workspacePath,
                                        isSelected: tabManager.selectedTerminalID == tab.id
                                    )
                                        .id(tab.id)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .opacity(tabManager.selectedTerminalID == tab.id ? 1 : 0)
                                        .allowsHitTesting(tabManager.selectedTerminalID == tab.id)
                                }
                                if tabManager.selectedTasksViewPath != nil, let tasksPath = tabManager.selectedTasksViewPath, tasksPath == selectedProjectPath {
                                    tasksListContent(tasksPath: tasksPath, triggerAddNewTask: $tasksViewTriggerAddNew)
                                } else if tabManager.selectedDashboardViewPath != nil, let dashboardPath = tabManager.selectedDashboardViewPath, dashboardPath == selectedProjectPath {
                                    dashboardContent(dashboardPath: dashboardPath)
                                } else if tabManager.selectedTerminalID == nil {
                                    if let active = tabManager.activeTab {
                                        ObservedTabView(tab: active) { tab in
                                            agentAreaContent(tab: tab, expandedPromptTabID: $expandedPromptTabID)
                                        }
                                    } else if hasOpenProjects, let projectPath = selectedProjectPath {
                                        projectEmptyStateContent(projectPath: projectPath)
                                    } else {
                                        splashContentArea()
                                    }
                                }
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
        .preferredColorScheme(resolvedColorScheme)
        .background(CursorTheme.panelGradient(for: colorScheme))
        .onKeyPress(.tab) {
            if isPromptFirstResponder?() == true {
                return .ignored
            }
            focusPromptInput?()
            return .handled
        }
        .background {
            Button("") {
                showTasksComposer(workspacePath: selectedProjectPath, startNewTask: true)
            }
            .keyboardShortcut("t", modifiers: .command)
            .hidden()
        }
        .modifier(TasksViewShortcutMonitorModifier(
            tabManager: tabManager,
            selectedProjectPath: selectedProjectPath,
            tasksViewTriggerAddNew: $tasksViewTriggerAddNew,
            coordinator: tasksViewShortcutCoordinator,
            requestShowTasksAndNewTask: Binding(get: { appState.requestShowTasksAndNewTask }, set: { appState.requestShowTasksAndNewTask = $0 }),
            onRequestNewTask: { showTasksComposer(workspacePath: selectedProjectPath, startNewTask: true) }
        ))
        .onAppear {
            sanitizeSelectedModel()
            devFolders = loadDevFolders(rootPath: projectsRootPath)
            tabManager.setProjectsFromPaths(devFolders.map(\.path))
            quickActionCommands = QuickActionStorage.commandsForWorkspace(workspacePath: currentWorkspacePath)
            let path = currentWorkspacePath
            let (cur, list) = loadGitBranches(workspacePath: path)
            currentBranch = cur
            gitBranches = list
            tabManager.activeTab?.currentBranch = cur
        }
        .onChange(of: workspacePath) { _, _ in
            quickActionCommands = QuickActionStorage.commandsForWorkspace(workspacePath: workspacePath)
        }
        .onChange(of: projectsRootPath) { _, _ in
            devFolders = loadDevFolders(rootPath: projectsRootPath)
            tabManager.setProjectsFromPaths(devFolders.map(\.path))
        }
        .onChange(of: selectedModel) { _, _ in
            sanitizeSelectedModel()
        }
        .onChange(of: tabManager.selectedTabID) { _, _ in
            let path = currentWorkspacePath
            let (cur, list) = loadGitBranches(workspacePath: path)
            currentBranch = cur
            gitBranches = list
            tabManager.activeTab?.currentBranch = cur
        }
        .onChange(of: tabManager.selectedProjectPath) { _, _ in
            let path = currentWorkspacePath
            quickActionCommands = QuickActionStorage.commandsForWorkspace(workspacePath: path)
            let (cur, list) = loadGitBranches(workspacePath: path)
            currentBranch = cur
            gitBranches = list
            tabManager.activeTab?.currentBranch = cur
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.black.opacity(0.36), radius: 28, y: 16)
        .sheet(isPresented: Binding(
            get: { appState.showSettingsSheet },
            set: { appState.showSettingsSheet = $0 }
        )) {
            SettingsModalView()
        }
        .onChange(of: appState.requestOpenInBrowser) {
            if appState.requestOpenInBrowser {
                appState.requestOpenInBrowser = false
                openInBrowserOrShowSetURLSheet()
            }
        }
        .onChange(of: appState.requestOpenInCursor) {
            if appState.requestOpenInCursor {
                appState.requestOpenInCursor = false
                openCurrentProjectInCursor()
            }
        }
        .sheet(isPresented: $showCreateDebugScriptSheet) {
            CreateDebugScriptSheet(
                workspacePath: currentWorkspacePath,
                onSave: {
                    tabManager.activeTab?.errorMessage = nil
                },
                onRunAfterSave: {
                    if let t = tab { runDebugScript(tab: t) }
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
        .overlay(globalShortcutOverlay)
        #if DEBUG
        .enableInjection()
        #endif
    }

    // MARK: - Unified header

    /// Light blue used for agent-tab progress spinner.
    private static let agentSpinnerBlue = CursorTheme.spinnerBlue
    /// Dark green for debug build badge (only visible in Debug configuration).
    private static let debugBadgeDarkGreen = Color(red: 0.0, green: 0.45, blue: 0.2)

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
            // Logo: always show when expanded; when collapsed show only the logo (no BETA/DEBUG).
            Image("CursorPlusLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: isMainContentCollapsed ? 28 : 36)

            if !isMainContentCollapsed {
                VStack(alignment: .leading, spacing: 4) {
                    Text("BETA")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color(red: 1, green: 0.88, blue: 0.1))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(red: 1, green: 0.88, blue: 0.1).opacity(0.28), in: RoundedRectangle(cornerRadius: 4, style: .continuous))

                    if Self.isDebugBuild {
                        Text("DEBUG")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Self.debugBadgeDarkGreen)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Self.debugBadgeDarkGreen.opacity(0.22), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
            }

            Spacer(minLength: 0)

            if isMainContentCollapsed {
                // Collapsed: 3-dot menu then expand.
                ThreeDotMenuButton(size: .medium, help: "More options") {
                    Button(action: { appState.showSettingsSheet = true }) {
                        Label("Settings", systemImage: "gearshape")
                    }
                    Button(action: dismiss) {
                        Label("Minimise", systemImage: "minus")
                    }
                }

                IconButton(icon: "chevron.right.2", action: { withAnimation(.easeInOut(duration: 0.2)) { appState.isMainContentCollapsed.toggle() } }, help: "Expand")
            } else {
                IconButton(icon: "chevron.left.2", action: { withAnimation(.easeInOut(duration: 0.2)) { appState.isMainContentCollapsed.toggle() } }, help: "Collapse")
                IconButton(icon: "gearshape", action: { appState.showSettingsSheet = true }, help: "Settings")
                IconButton(icon: "minus", action: dismiss, help: "Minimise")
            }
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
                            HStack(spacing: 4) {
                                Button {
                                    tabManager.selectProject(group.path)
                                    if appState.isMainContentCollapsed {
                                        withAnimation(.easeInOut(duration: 0.2)) { appState.isMainContentCollapsed = false }
                                    }
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if isCollapsed {
                                            collapsedGroupPaths.remove(group.path)
                                        } else {
                                            collapsedGroupPaths.insert(group.path)
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 4) {
                                                if !group.path.isEmpty {
                                                    ProjectIconView(path: group.path)
                                                        .frame(width: 12, height: 12)
                                                }
                                                Text(group.displayName)
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundStyle(CursorTheme.colorForWorkspace(path: group.path))
                                                    .lineLimit(1)
                                                    .truncationMode(.middle)
                                            }
                                            let groupBranch = group.path == currentWorkspacePath ? currentBranch : (group.tabs.first?.currentBranch ?? "")
                                            if !groupBranch.isEmpty && !isCollapsed {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "arrow.triangle.branch")
                                                        .font(.system(size: 9, weight: .medium))
                                                    Text(groupBranch)
                                                        .font(.system(size: 11, weight: .regular))
                                                        .italic()
                                                }
                                                .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                                .padding(.leading, 14)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                                            .font(.system(size: 8, weight: .semibold))
                                            .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                                            .frame(width: 10, alignment: .trailing)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)

                            }
                            if !isCollapsed {
                                let isPreviewSelected = tabManager.selectedDashboardViewPath == group.path
                                Button {
                                    dashboardTabsByWorkspacePath[group.path] = .preview
                                    tabManager.showDashboardView(workspacePath: group.path)
                                    if appState.isMainContentCollapsed {
                                        withAnimation(.easeInOut(duration: 0.2)) { appState.isMainContentCollapsed = false }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "square.grid.2x2")
                                            .font(.system(size: 12))
                                            .foregroundStyle(isPreviewSelected ? CursorTheme.textPrimary(for: colorScheme) : CursorTheme.textSecondary(for: colorScheme))
                                        Text("Preview")
                                            .font(.system(size: 12, weight: isPreviewSelected ? .semibold : .medium))
                                            .foregroundStyle(isPreviewSelected ? CursorTheme.textPrimary(for: colorScheme) : CursorTheme.textSecondary(for: colorScheme))
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(
                                        isPreviewSelected ? CursorTheme.surfaceRaised(for: colorScheme) : CursorTheme.surfaceMuted(for: colorScheme),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(isPreviewSelected ? CursorTheme.borderStrong(for: colorScheme) : CursorTheme.border(for: colorScheme).opacity(0.6), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .help("Preview: terminal, Start Preview, Configure Setup")
                                let isTasksSelected = tabManager.selectedTasksViewPath == group.path
                                Button {
                                    tabManager.showTasksView(workspacePath: group.path)
                                    if appState.isMainContentCollapsed {
                                        withAnimation(.easeInOut(duration: 0.2)) { appState.isMainContentCollapsed = false }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "checklist")
                                            .font(.system(size: 12))
                                            .foregroundStyle(isTasksSelected ? CursorTheme.textPrimary(for: colorScheme) : CursorTheme.textSecondary(for: colorScheme))
                                        Text("Tasks")
                                            .font(.system(size: 12, weight: isTasksSelected ? .semibold : .medium))
                                            .foregroundStyle(isTasksSelected ? CursorTheme.textPrimary(for: colorScheme) : CursorTheme.textSecondary(for: colorScheme))
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(
                                        isTasksSelected ? CursorTheme.surfaceRaised(for: colorScheme) : CursorTheme.surfaceMuted(for: colorScheme),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(isTasksSelected ? CursorTheme.borderStrong(for: colorScheme) : CursorTheme.border(for: colorScheme).opacity(0.6), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .help("View tasks for this project")
                                ForEach(group.tabs) { t in
                                    ObservedTabChip(
                                        tab: t,
                                        isSelected: t.id == tabManager.selectedTabID,
                                        showClose: true,
                                        onSelect: {
                                            selectLinkedAgentTab(t.id)
                                        },
                                        onClose: { requestCloseTab(t) }
                                    )
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                ForEach(group.terminalTabs) { term in
                                    TerminalTabChip(
                                        terminalTab: term,
                                        isSelected: term.id == tabManager.selectedTerminalID,
                                        onSelect: {
                                            tabManager.selectedTerminalID = term.id
                                            tabManager.selectedTabID = nil
                                            tabManager.selectedTasksViewPath = nil
                                            tabManager.selectedDashboardViewPath = nil
                                            tabManager.selectedProjectPath = term.workspacePath
                                            if appState.isMainContentCollapsed {
                                                withAnimation(.easeInOut(duration: 0.2)) { appState.isMainContentCollapsed = false }
                                            }
                                        },
                                        onClose: { tabManager.closeTerminalTab(term.id) }
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

            Button(action: addProject) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 12))
                        .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                    Text("Add Project")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(CursorTheme.surfaceMuted(for: colorScheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(CursorTheme.border(for: colorScheme).opacity(0.6), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Self.sidebarContentPadding)
        .frame(width: sidebarWidth)
        .clipped()
        .padding(.trailing, 12)
    }

    // MARK: - Splash content (no projects: invite to add a project)

    private func splashContentArea() -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)
            VStack(spacing: 28) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 64, weight: .medium))
                    .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: 12) {
                    Text("Add a project to get started")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                        .multilineTextAlignment(.center)

                    Text("Choose a folder on your Mac to open as a project. You can then ask questions, run the agent, and use Cursor from the menu bar.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 320)
                }

                Button(action: addProject) {
                    HStack(spacing: 10) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Add Project")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(CursorTheme.brandBlue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(32)
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func projectEmptyStateContent(projectPath: String) -> some View {
        let projectName = appState.workspaceDisplayName(for: projectPath).isEmpty
            ? ((projectPath as NSString).lastPathComponent.isEmpty ? "Project" : (projectPath as NSString).lastPathComponent)
            : appState.workspaceDisplayName(for: projectPath)
        let branch = projectPath == currentWorkspacePath ? currentBranch : ""

        return VStack(spacing: 0) {
            Spacer(minLength: 40)
            VStack(spacing: 24) {
                ProjectIconView(path: projectPath)
                    .frame(width: 56, height: 56)

                VStack(spacing: 10) {
                    Text(projectName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                        .multilineTextAlignment(.center)

                    Text("This project is open, but it does not have any task-linked agent conversations yet.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)

                    if !branch.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 12, weight: .medium))
                            Text(branch)
                                .font(.system(size: 13, weight: .medium))
                                .italic()
                        }
                        .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                    }
                }

                HStack(spacing: 12) {
                    Button(action: {
                        showTasksComposer(workspacePath: projectPath, startNewTask: true)
                    }) {
                        Label("New Task", systemImage: "checklist")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 13)
                            .background(CursorTheme.brandBlue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        openProjectInCursor(projectPath)
                    }) {
                        Label("Cursor", systemImage: "arrow.up.forward.app")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 13)
.background(CursorTheme.surfaceMuted(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(CursorTheme.border(for: colorScheme), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(32)
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Agent area content (observed by tab; only this subtree re-renders when active tab streams)

    /// Display status for the agent header and status bar (Processing / Review / Stopped / Completed / Ready).
    private func agentDisplayStatus(for tab: AgentTab) -> (label: String, isProcessing: Bool, isPendingReview: Bool, isStopped: Bool, isCompleted: Bool) {
        if tab.isRunning {
            return ("Processing", true, false, false, false)
        }
        if let taskID = tab.linkedTaskID {
            let tasks = ProjectTasksStorage.tasks(workspacePath: tab.workspacePath)
            if let task = tasks.first(where: { $0.id == taskID }), task.taskState == .completed {
                return ("Completed", false, false, false, true)
            }
            let status = linkedTaskState(for: tab)
            if status == .stopped {
                return ("Stopped", false, false, true, false)
            }
            if status == .review {
                return ("Pending Review", false, true, false, false)
            }
        }
        return ("Ready", false, false, false, false)
    }

    private func agentHeader(tab: AgentTab, fullPrompt: String, isExpanded: Bool, onToggleExpand: @escaping () -> Void) -> some View {
        let status = agentDisplayStatus(for: tab)
        let hasExpandablePrompt = !fullPrompt.isEmpty
        let titleFont = Font.system(size: CursorTheme.fontTitle, weight: .semibold)
        let titleColor = CursorTheme.textPrimary(for: colorScheme)
        let displayTitle = (isExpanded && hasExpandablePrompt) ? userPromptDisplayText(from: fullPrompt) : tab.title
        return HStack(alignment: .top, spacing: CursorTheme.spaceM) {
            agentStatusIcon(tab: tab, status: status)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top, spacing: CursorTheme.spaceXS) {
                    Text(displayTitle)
                        .font(titleFont)
                        .foregroundStyle(titleColor)
                        .lineLimit(isExpanded ? nil : 1)
                        .truncationMode(.tail)
                        .textSelection(.enabled)
                    if hasExpandablePrompt {
                        Button(action: onToggleExpand) {
                            HStack(spacing: 4) {
                                Text("…")
                                    .font(titleFont)
                                    .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                                Text(isExpanded ? "Hide full prompt" : "Show full prompt")
                                    .font(.system(size: CursorTheme.fontCaption, weight: .medium))
                                    .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(CursorTheme.surfaceMuted(for: colorScheme).opacity(0.8), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack(spacing: CursorTheme.spaceXS) {
                    Image(systemName: "folder")
                        .font(.system(size: CursorTheme.fontCaption, weight: .medium))
                        .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                    Text((tab.workspacePath as NSString).lastPathComponent)
                        .font(.system(size: CursorTheme.fontSecondary, weight: .regular))
                        .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, CursorTheme.paddingHeaderHorizontal)
        .padding(.vertical, CursorTheme.paddingHeaderVertical)
    }

    private func fullPromptAccordionContent(fullPrompt: String, workspacePath: String) -> some View {
        let displayText = userPromptDisplayText(from: fullPrompt)
        return VStack(alignment: .leading, spacing: 0) {
            Text(displayText)
                .font(.system(size: CursorTheme.fontSecondary, weight: .regular))
                .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(CursorTheme.paddingCard)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CursorTheme.surfaceMuted(for: colorScheme), in: RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous)
                .stroke(CursorTheme.border(for: colorScheme), lineWidth: 1)
        )
        .padding(.horizontal, CursorTheme.paddingHeaderHorizontal)
        .padding(.bottom, CursorTheme.spaceS)
    }

    @ViewBuilder
    private func agentStatusIcon(tab: AgentTab, status: (label: String, isProcessing: Bool, isPendingReview: Bool, isStopped: Bool, isCompleted: Bool)) -> some View {
        if status.isProcessing {
            LightBlueSpinner(size: CursorTheme.fontIconList)
        } else if status.isStopped {
            Image(systemName: "square.fill")
                .font(.system(size: CursorTheme.fontIconList - 2, weight: .semibold))
                .foregroundStyle(CursorTheme.semanticError)
        } else if status.isPendingReview {
            Image(systemName: "clock.fill")
                .font(.system(size: CursorTheme.fontIconList, weight: .medium))
                .foregroundStyle(CursorTheme.semanticReview)
        } else if status.isCompleted {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: CursorTheme.fontIconList))
                .foregroundStyle(CursorTheme.brandBlue)
        } else {
            Image(systemName: "person.crop.circle")
                .font(.system(size: CursorTheme.fontIconList, weight: .medium))
                .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
        }
    }

    private func agentAreaContent(tab: AgentTab, expandedPromptTabID: Binding<UUID?>) -> some View {
        let fullPrompt = (tab.turns.first?.userPrompt ?? tab.prompt).trimmingCharacters(in: .whitespacesAndNewlines)
        let isExpanded = expandedPromptTabID.wrappedValue == tab.id
        return VStack(spacing: 0) {
            agentHeader(tab: tab, fullPrompt: fullPrompt, isExpanded: isExpanded, onToggleExpand: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expandedPromptTabID.wrappedValue == tab.id {
                        expandedPromptTabID.wrappedValue = nil
                    } else {
                        expandedPromptTabID.wrappedValue = tab.id
                    }
                }
            })
            Divider()
                .background(CursorTheme.border(for: colorScheme))

            VStack(spacing: 12) {
                if let error = tab.errorMessage {
                    Text(error)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CursorTheme.semanticErrorTint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(cardBackground.opacity(0.96), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(CursorTheme.semanticError.opacity(0.25), lineWidth: 1)
                        )
                }

                outputCard(tab: tab)
                    .frame(maxHeight: .infinity)
                    .id(tab.id)

                composerDock(tab: tab)
            }
            .padding(.horizontal, CursorTheme.paddingPanel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        let modelLabel = appState.model(for: selectedModel)?.label ?? "Auto"
        // Use view's currentBranch when tab's is empty (e.g. new tab before onChange runs) so we don't flash "No branch".
        let branchDisplay = tab.currentBranch.isEmpty ? currentBranch : tab.currentBranch
        return VStack(spacing: 0) {
                Spacer(minLength: 24)
                VStack(spacing: 20) {
                    Text(projectName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                            Text(branchDisplay.isEmpty ? "No branch" : branchDisplay)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "cpu")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                            Text(modelLabel)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                        }
                    }

                    Text("Ask a question below to start")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                        .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(CursorTheme.surfaceMuted(for: colorScheme).opacity(0.8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(CursorTheme.border(for: colorScheme), lineWidth: 1)
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
                    onCommand: { cmd in
                        if cmd.title == QuickActionCommand.defaultFixBuild.title {
                            _ = addNewAgentTab(initialPrompt: cmd.prompt, lastWorkspacePath: tab.workspacePath, select: true)
                        } else {
                            sendInCurrentTab(prompt: cmd.prompt, tab: tab)
                        }
                    },
                    onAdd: {},
                    onCommandsChanged: { quickActionCommands = QuickActionStorage.commandsForWorkspace(workspacePath: tab.workspacePath) }
                )
                Spacer()
                ComposerActionButtonsView(
                    showPinnedQuestionsPanel: $showPinnedQuestionsPanel,
                    hasContext: !tab.turns.isEmpty || !tab.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    isRunning: tab.isRunning
                )
            }

            queuedFollowUpsView(tab: tab)

            ForEach(Array(attachedPaths.enumerated()), id: \.offset) { _, path in
                ScreenshotCardView(
                    path: path,
                    workspacePath: tab.workspacePath,
                    onDelete: { deleteScreenshot(path: path, tab: tab) },
                    onTapPreview: { screenshotPreviewURL = screenshotFileURL(path: path, workspacePath: tab.workspacePath) }
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
                        onSubmit: { submitOrQueuePrompt(tab: tab) },
                        onPasteImage: { pasteScreenshot(tab: tab) },
                        onHeightChange: { newHeight in
                            composerTextHeight = newHeight
                        },
                        onFocusRequested: { focus, isFirstResponder in
                            focusPromptInput = focus
                            isPromptFirstResponder = isFirstResponder
                        },
                        colorScheme: colorScheme
                    )
                    .frame(height: composerHeight)

                    if userPromptDisplayText(from: tab.prompt).isEmpty && screenshotPaths(from: tab.prompt).isEmpty {
                        Text("Send message and/or ⌘V to paste one or more screenshots from clipboard. Press Enter to submit and ⇧Enter for new line.")
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                            .padding(.leading, 4)
                            .padding(.top, 6)
                            .padding(.trailing, 8)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                sendStopButton(tab: tab)
                    .padding(.bottom, 2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(CursorTheme.editor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(CursorTheme.border(for: colorScheme), lineWidth: 1)
            )

            HStack(alignment: .center, spacing: 8) {
                ModelPickerView(
                    selectedModelId: tab.modelId ?? selectedModel,
                    models: modelPickerModels(including: tab.modelId ?? selectedModel),
                    onSelect: { tab.modelId = $0 }
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

    private func openInBrowserOrFolder(tab: AgentTab) {
        if previewURL(for: tab.workspacePath) != nil {
            openPreview(for: tab.workspacePath)
        } else {
            openWorkspaceInFinder(workspacePath: tab.workspacePath)
        }
    }

    /// Cmd+O: open in browser if URL is set, otherwise open workspace in Finder. With no project, opens Add Project so the shortcut always does something.
    private func openInBrowserOrShowSetURLSheet() {
        guard hasOpenProjects else {
            addProject()
            return
        }
        let path = currentWorkspacePath
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return }
        if previewURL(for: path) != nil {
            openPreview(for: path)
        } else {
            openWorkspaceInFinder(workspacePath: path)
        }
    }

    private func sendStopButton(tab: AgentTab) -> some View {
        Button(action: {
            if tab.isRunning {
                stopStreaming(for: tab)
            } else {
                submitOrQueuePrompt(tab: tab)
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
            .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
            .frame(width: 28, height: 28)
            .background {
                if tab.isRunning {
                    Circle().fill(CursorTheme.surfaceRaised(for: colorScheme))
                } else {
                    Circle().fill(CursorTheme.brandGradient)
                }
            }
            .overlay(
                Circle()
                    .stroke(
                        tab.isRunning
                            ? CursorTheme.borderStrong(for: colorScheme)
                            : CursorTheme.textPrimary(for: colorScheme).opacity(0.14),
                        lineWidth: 1
                    )
            )
            .opacity(tab.isRunning || canSend(tab: tab) ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!tab.isRunning && !canSend(tab: tab))
    }

    private var composerHeight: CGFloat {
        min(132, max(56, composerTextHeight + 16))
    }

    // MARK: - Helpers

    private func sanitizeSelectedModel() {
        guard appState.model(for: selectedModel) == nil else { return }
        selectedModel = AvailableModels.autoID
    }

    private var cardBackground: some ShapeStyle {
        CursorTheme.surface(for: colorScheme)
    }

    private var editorBackground: some ShapeStyle {
        CursorTheme.surfaceMuted(for: colorScheme)
    }

    private var cardBorder: Color {
        CursorTheme.border(for: colorScheme)
    }

    @ViewBuilder
    private func queuedFollowUpsView(tab: AgentTab) -> some View {
        if !tab.followUpQueue.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(tab.followUpQueue) { item in
                    HStack(spacing: 8) {
                        if editingFollowUpID == item.id {
                            TextField("Message", text: $editingFollowUpDraft, axis: .vertical)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                                .lineLimit(2 ... 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .onSubmit { applyEditedFollowUp(itemID: item.id, tab: tab) }
                            Button(action: {
                                applyEditedFollowUp(itemID: item.id, tab: tab)
                            }) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                            }
                            .buttonStyle(.plain)
                            .help("Save")
                            Button(action: {
                                editingFollowUpID = nil
                                editingFollowUpDraft = ""
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                            }
                            .buttonStyle(.plain)
                            .help("Cancel")
                        } else {
                            Text(item.text)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button(action: {
                                sendQueuedFollowUpToNewTab(item, tab: tab)
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 13, weight: .semibold))
                                    Text("Task Agent")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(CursorTheme.surfaceRaised(for: colorScheme), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .help("Create a linked task agent")
                            Button(action: {
                                editingFollowUpID = item.id
                                editingFollowUpDraft = item.text
                            }) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                            }
                            .buttonStyle(.plain)
                            .help("Edit message")
                            Button(action: {
                                tab.followUpQueue.removeAll(where: { $0.id == item.id })
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(CursorTheme.surfaceMuted(for: colorScheme).opacity(0.8), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    private func applyEditedFollowUp(itemID: UUID, tab: AgentTab) {
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

    private func canSend(tab: AgentTab) -> Bool {
        !tab.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Submit the current prompt: send immediately if idle, or queue as follow-up if agent is running.
    private func submitOrQueuePrompt(tab: AgentTab) {
        let trimmed = tab.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if tab.isRunning {
            updateTabTitle(for: trimmed, in: tab)
            tab.followUpQueue.append(QueuedFollowUp(text: trimmed))
            tab.prompt = ""
            tab.hasAttachedScreenshot = false
            return
        }
        sendPrompt(tab: tab)
    }

    private static let compressPrompt = "Summarize our entire conversation so far into a single concise summary that preserves key context, decisions, and next steps. Reply with only that summary, no other text."

    /// Compress context: ask the agent to summarize the conversation, then replace context with that summary (new chat). If no context, clears instead.
    private func compressContext(tab: AgentTab) {
        guard !tab.isRunning else { return }
        let hasContext = !tab.turns.isEmpty || !tab.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !hasContext {
            clearContext(tab: tab)
            return
        }
        tab.prompt = Self.compressPrompt
        tab.isCompressRequest = true
        sendPrompt(tab: tab)
    }

    private func clearContext(tab: AgentTab) {
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

    private func deleteScreenshot(path: String, tab: AgentTab) {
        let reference = "\n\n[Screenshot attached: \(path)]"
        tab.prompt = tab.prompt.replacingOccurrences(of: reference, with: "")
        if !tab.prompt.contains("[Screenshot attached:") {
            tab.hasAttachedScreenshot = false
        }
        let imageURL = screenshotFileURL(path: path, workspacePath: tab.workspacePath)
        try? FileManager.default.removeItem(at: imageURL)
    }

    private func pasteScreenshot(tab: AgentTab) {
        let currentPaths = screenshotPaths(from: tab.prompt)
        guard currentPaths.count < AppLimits.maxScreenshots else { return }

        let pasteboard = NSPasteboard.general
        guard let image = SubmittableTextEditor.imageFromPasteboard(pasteboard) else {
            return
        }

        let cachePath = nextScreenshotCachePath()
        let destURL = URL(fileURLWithPath: cachePath)

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return
        }

        do {
            try pngData.write(to: destURL)
            let reference = "\n\n[Screenshot attached: \(cachePath)]"
            tab.prompt += reference
            tab.hasAttachedScreenshot = true
        } catch {
            return
        }
    }

    private func sendInCurrentTab(prompt: String, tab: AgentTab) {
        guard !tab.isRunning else { return }
        tab.prompt = prompt
        sendPrompt(tab: tab)
    }

    private func handleDebugAction(tab: AgentTab) {
        if debugScriptExists(workspacePath: tab.workspacePath) {
            runDebugScript(tab: tab)
        } else {
            showCreateDebugScriptSheet = true
        }
    }

    private func runDebugScript(tab: AgentTab) {
        if let error = launchDebugScript(
            workspacePath: tab.workspacePath,
            preferredTerminal: preferredTerminalApp
        ) {
            tab.errorMessage = error
            return
        }

        tab.errorMessage = nil
    }

    private func sendQueuedFollowUpToNewTab(_ item: QueuedFollowUp, tab: AgentTab) {
        let prompt = item.text
        let workspacePath = tab.workspacePath
        tab.followUpQueue.removeAll(where: { $0.id == item.id })
        let modelId = tab.modelId ?? AvailableModels.autoID
        let task = ProjectTasksStorage.addTask(workspacePath: workspacePath, content: prompt, modelId: modelId)
        sendTaskToAgent(
            prompt: prompt,
            taskID: task.id,
            screenshotPaths: task.screenshotPaths,
            modelId: task.modelId,
            workspacePath: workspacePath,
            selectAgent: true
        )
    }

    // MARK: - Streaming

    private func sendPrompt(tab currentTab: AgentTab) {
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
                let modelToUse = currentTab.modelId ?? selectedModel
                let stream = try AgentRunner.stream(prompt: trimmed, workspacePath: currentTab.workspacePath, model: modelToUse, conversationId: currentTab.cursorChatId)
                guard currentTab.activeRunID == runID, currentTab.activeTurnID == turnID else { return }
                // Coalesce text chunks and flush at ~100ms to reduce main-actor and UI churn during long runs.
                var thinkingBuffer = ""
                var assistantBuffer = ""
                var flushTask: Task<Void, Never>?
                let flushIntervalNs: UInt64 = 100_000_000 // 100ms
                func flushBatched() {
                    let thinking = thinkingBuffer
                    let assistant = assistantBuffer
                    thinkingBuffer = ""
                    assistantBuffer = ""
                    Task { @MainActor in
                        if !thinking.isEmpty {
                            appendThinkingText(thinking, to: turnID, in: currentTab)
                        }
                        if !assistant.isEmpty {
                            mergeAssistantText(assistant, into: currentTab, turnID: turnID)
                        }
                        requestAutoScroll(for: currentTab)
                    }
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
                    sendPrompt(tab: currentTab)
                }
            }
        }

        currentTab.streamTask = task
    }

    private func stopStreaming(for currentTab: AgentTab? = nil) {
        guard let tabToStop = currentTab ?? tab else { return }
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
