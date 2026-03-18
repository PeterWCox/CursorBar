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

private let projectSetupAgentPrompt = """
Set up Cursor Metro for this project from scratch and make it fully runnable for the user without extra manual terminal steps.

1) Create or update `.metro/project.json` with a `"scripts"` array. Each element must be a **shell command string** to run (for example `"npm run dev"` or `"cd backend && npm run dev"`), NOT a filename. Do not put `"startup.sh"` or any file path in the scripts array. Do not create or reference `.metro/startup.sh`. **Always** add a `"scriptLabels"` array of the same length as `scripts` so Preview terminal tabs show clear names: for multiple scripts use descriptive names like `["backend", "frontend"]` or `["api", "web"]`; for a single script use `["Preview"]` or the app name. Tabs without scriptLabels fall back to "1", "2", etc.

2) Commands are run with the shell's current working directory set to the **project root** (the directory that contains `.metro`), and Cursor Metro executes each script via `/bin/bash -c`. Use commands like `npm run dev` if `package.json` is in the project root, or `cd budget && npm run dev` if the app lives in a subfolder. Do not cd into `.metro`.

3) If this is a web app, add or update the `"debugUrl"` field in `.metro/project.json` with the URL where the app is served (for example `http://localhost:3000`).

4) **Port cleanup:** For each script, ensure the ports it will use are free before starting. Include in the script string commands to kill any process already bound to those ports—for example prefix with `lsof -ti:PORT | xargs kill -9 2>/dev/null; ` (using the actual port number, e.g. 3000, 5000). Determine the port from the app's config (e.g. package.json, Vite/Next config, or framework default). Use `2>/dev/null` so that if no process is using the port, the command does not fail. Example: `"lsof -ti:3000 | xargs kill -9 2>/dev/null; npm run dev"`.

5) Detect the project type from the repo and configure startup commands that are **self-contained and ready to run in a fresh terminal**. Do not assume the user has already activated a virtual environment, sourced a shell file, or run install steps manually.

6) If any backend or service uses Python, the generated startup command must take care of the Python environment for the user:
   - detect the correct backend directory
   - create a local virtual environment automatically if it does not exist
   - prefer the repo's existing convention (`venv`, `.venv`, Poetry, Pipenv, etc.) when clearly present; otherwise default to `.venv`
   - follow any clearly documented repo setup conventions from files like `README.md` or `AGENTS.md`
   - install dependencies when needed using the dependency files present in the repo
   - activate the environment in the same command
   - use `python -m pip ...` instead of bare `pip`
   - start Python servers with `python -m ...` when possible (for example `python -m uvicorn ...`) instead of relying on a bare executable being on PATH
   - do not tell the user to activate the venv manually

7) For multi-service apps, create one script per long-running process (for example backend and frontend), and make each script robust enough that Preview runs it in a clean terminal session.

8) Make the best reasonable choice from the repository contents and finish the setup instead of asking the user to do follow-up configuration. Always include `scriptLabels` so Preview tabs have clear names (e.g. "backend", "frontend" for multi-service apps, or "Preview" / the app name for a single script). After writing `.metro/project.json`, briefly summarize the exact scripts, scriptLabels, and debug URL you configured.
"""

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

private struct GitBranchSnapshot: Equatable {
    let current: String
    let branches: [String]
}

private enum AddProjectMode: String, CaseIterable, Identifiable {
    case existing
    case new
    case github

    var id: String { rawValue }

    var title: String {
        switch self {
        case .existing: return "Existing"
        case .new: return "New"
        case .github: return "GitHub"
        }
    }
}

/// Tab for the Projects panel (matches Agent/Preview style).
private enum ProjectsPanelTab: String, CaseIterable, Identifiable {
    case turnOnOff = "Projects"
    case newProject = "New"
    case github = "GitHub"

    var id: String { rawValue }
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
                    .frame(width: 16, height: 16, alignment: .center)
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

/// Wraps the agent header content so it observes the tab and re-renders when isRunning/turns change (keeps header icon in sync with sidebar).
private struct ObservedAgentTitleContent<Content: View>: View {
    @ObservedObject var tab: AgentTab
    @Binding var expandedPromptTabID: UUID?
    @ViewBuilder let content: (AgentTab) -> Content

    var body: some View {
        content(tab)
    }
}

// MARK: - Tasks list content wrapper (reduces type-checker load in PopoutView body)

private struct PopoutTasksListContent: View {
    let tasksPath: String
    @Binding var triggerAddNewTask: Bool
    let linkedStatuses: [UUID: AgentTaskState]
    let newTaskProviderID: AgentProviderID
    let modelsForProvider: (AgentProviderID) -> [ModelOption]
    let onSendToAgent: (String, UUID?, [String], AgentProviderID, String) -> Void
    let onOpenLinkedAgent: (ProjectTask) -> Void
    let onContinueAgent: (ProjectTask) -> Void
    let onResetAgent: (ProjectTask) -> Void
    let onStopAgent: (ProjectTask) -> Void
    let onTasksDidUpdate: () -> Void
    let onDismiss: () -> Void
    var onLaunchSetupAgent: ((String) -> Void)? = nil
    var showHeader: Bool = true

    var body: some View {
        TasksListView(
            workspacePath: tasksPath,
            triggerAddNewTask: $triggerAddNewTask,
            linkedStatuses: linkedStatuses,
            newTaskProviderID: newTaskProviderID,
            modelsForProvider: modelsForProvider,
            onSendToAgent: onSendToAgent,
            onOpenLinkedAgent: onOpenLinkedAgent,
            onContinueAgent: onContinueAgent,
            onResetAgent: onResetAgent,
            onStopAgent: onStopAgent,
            onTasksDidUpdate: onTasksDidUpdate,
            onDismiss: onDismiss,
            showHeader: showHeader,
            onLaunchSetupAgent: onLaunchSetupAgent
        )
        .id(tasksPath)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
    }
}

/// Sidebar logo: loads from bundle so we can fall back when asset is missing (avoids green placeholder). Uses original rendering so the logo art shows.
private struct CursorMetroLogoView: View {
    let height: CGFloat
    let projectColor: Color

    var body: some View {
        if let nsImage = NSImage(named: "CursorMetroLogo") {
            Image(nsImage: nsImage)
                .resizable()
                .renderingMode(.original)
                .aspectRatio(contentMode: .fit)
                .frame(height: height)
        } else {
            Image(nsImage: CursorAppIcon.load())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: height)
        }
    }
}
private struct SidebarLogoView: View {
    let height: CGFloat
    let projectColor: Color

    var body: some View {
        CursorMetroLogoView(height: height, projectColor: projectColor)
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
    @AppStorage(AppPreferences.projectScanRootsKey) private var projectScanRootsRaw: String = AppPreferences.defaultProjectScanRootsRaw
    @AppStorage(AppPreferences.preferredTerminalAppKey) private var preferredTerminalAppRawValue: String = PreferredTerminalApp.automatic.rawValue
    @AppStorage(AppPreferences.disabledModelIdsKey) private var disabledModelIdsRaw: String = AppPreferences.defaultDisabledModelIdsRaw
    @AppStorage(AppPreferences.defaultModelIdKey) private var appDefaultModelId: String = AppPreferences.defaultDefaultModelId
    @AppStorage(AppPreferences.hiddenProjectPathsKey) private var hiddenProjectPathsRaw: String = AppPreferences.defaultHiddenProjectPathsRaw
    @AppStorage("selectedModel") private var selectedModel: String = AvailableModels.autoID
    @AppStorage("messagesSentForUsage") private var messagesSentForUsage: Int = 0
    @AppStorage("showPinnedQuestionsPanel") private var showPinnedQuestionsPanel: Bool = true
    @AppStorage(AppPreferences.sidebarOnRightKey) private var isSidebarOnRight: Bool = false
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject private var projectTasksStore: ProjectTasksStore
    @EnvironmentObject private var projectSettingsStore: ProjectSettingsStore

    /// App always uses dark mode; theme picker is disabled.
    private var resolvedColorScheme: ColorScheme? { .dark }
    @State private var devFolders: [URL] = []
    @State private var gitBranches: [String] = []
    @State private var currentBranch: String = ""
    @State private var gitBranchSnapshotsByWorkspace: [String: GitBranchSnapshot] = [:]
    @State private var quickActionSnapshotsByWorkspace: [String: [QuickActionCommand]] = [:]
    @State private var quickActionCommands: [QuickActionCommand] = []
    @State private var composerTextHeight: CGFloat = 24
    @State private var showCreateDebugScriptSheet: Bool = false
    /// When set, show "Are you sure?" before closing this tab (agent still processing).
    @State private var closeTabConfirmationTabID: UUID? = nil
    @State private var screenshotPreviewURLs: [URL] = []
    @State private var screenshotPreviewIndex: Int = 0
    /// Workspace paths for groups that are collapsed in the sidebar (accordion).
    @State private var collapsedGroupPaths: Set<String> = []
    /// When true, Cmd+T in Tasks view should add a new task; set by window-level shortcut and observed by TasksListView.
    @State private var tasksViewTriggerAddNew: Bool = false
    @StateObject private var tasksViewShortcutCoordinator = TasksViewShortcutCoordinator()
    @StateObject private var agentSessionStore = AgentSessionStore()
    /// Tab whose agent header prompt accordion is expanded (show full prompt below title).
    @State private var expandedPromptTabID: UUID? = nil
    /// How many of the most recent turns are mounted for each tab. `Int.max` means full history.
    @State private var visibleTurnLimitsByTabID: [UUID: Int] = [:]
    @State private var projectsPanelTab: ProjectsPanelTab = .turnOnOff
    @State private var selectedExistingProjectPath: String?
    @State private var newProjectName: String = ""
    @State private var newProjectParentPath: String = ""
    @State private var newProjectIdea: String = ""
    @State private var gitRepositoryURL: String = ""
    @State private var gitCloneParentPath: String = ""
    @State private var gitCloneFolderName: String = ""
    @State private var projectHubErrorMessage: String?
    @State private var projectHubStatusMessage: String?
    @State private var isProjectHubBusy: Bool = false
    /// When true, hide main agent content and show only title bar + tab sidebar (uses AppState so panel can resize).
    private var isMainContentCollapsed: Bool { appState.isMainContentCollapsed }

    private static let defaultVisibleTurnLimit = 40
    private static let visibleTurnPageSize = 30

    /// Active tab when there is at least one; otherwise nil (splash state).
    private var tab: AgentTab? { tabManager.activeTab }

    private var selectedProjectPath: String? {
        tabManager.activeProjectPath
    }

    private var hasOpenProjects: Bool {
        appState.openProjectCount > 0
    }

    private var projectScanRoots: [String] {
        AppPreferences.resolvedProjectScanRoots(raw: projectScanRootsRaw, legacyRootPath: projectsRootPath)
    }

    private var preferredProjectBrowserRoot: String {
        AppPreferences.preferredProjectBrowserRoot(raw: projectScanRootsRaw, legacyRootPath: projectsRootPath)
    }

    /// Workspace path for the current context: active tab's workspace, selected project, or app storage fallback.
    private var currentWorkspacePath: String {
        tab?.workspacePath ?? selectedProjectPath ?? workspacePath
    }

    private func previewURL(for workspacePath: String) -> URL? {
        guard let urlString = projectSettingsStore.debugURL(for: workspacePath) else {
            return nil
        }
        return URL(string: urlString)
    }

    private func showScreenshotPreview(paths: [String], selectedPath: String, workspacePath: String) {
        let urls = paths.map { screenshotFileURL(path: $0, workspacePath: workspacePath) }
        guard !urls.isEmpty else { return }
        screenshotPreviewURLs = urls
        screenshotPreviewIndex = max(0, paths.firstIndex(of: selectedPath) ?? 0)
    }

    private func openPreview(for workspacePath: String) {
        guard let url = previewURL(for: workspacePath) else { return }
        openURLInChrome(url)
    }

    private func visibleTurnLimit(for tab: AgentTab) -> Int {
        if let storedLimit = visibleTurnLimitsByTabID[tab.id] {
            return storedLimit
        }

        return tab.turns.count > Self.defaultVisibleTurnLimit
            ? Self.defaultVisibleTurnLimit
            : Int.max
    }

    private func displayedTurns(for tab: AgentTab) -> [ConversationTurn] {
        let limit = visibleTurnLimit(for: tab)
        guard limit != Int.max, tab.turns.count > limit else {
            return tab.turns
        }
        return Array(tab.turns.suffix(limit))
    }

    private func hiddenTurnCount(for tab: AgentTab) -> Int {
        max(0, tab.turns.count - displayedTurns(for: tab).count)
    }

    private func showOlderTurns(for tab: AgentTab) {
        let currentLimit = visibleTurnLimit(for: tab)
        let baseLimit = currentLimit == Int.max ? tab.turns.count : currentLimit
        let nextLimit = min(tab.turns.count, baseLimit + Self.visibleTurnPageSize)
        visibleTurnLimitsByTabID[tab.id] = nextLimit >= tab.turns.count ? Int.max : nextLimit
    }

    private func showAllTurns(for tab: AgentTab) {
        visibleTurnLimitsByTabID[tab.id] = Int.max
    }

    private func conversationWindowBar(tab: AgentTab, hiddenTurnCount: Int, visibleTurnCount: Int) -> some View {
        return Group {
            if hiddenTurnCount > 0 {
                HStack(alignment: .center, spacing: 10) {
                    Text("Showing latest \(visibleTurnCount) of \(tab.turns.count) messages")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))

                    Spacer(minLength: 0)

                    Button("Show \(min(hiddenTurnCount, Self.visibleTurnPageSize)) older") {
                        showOlderTurns(for: tab)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CursorTheme.brandBlue)

                    Button("Show all") {
                        showAllTurns(for: tab)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(CursorTheme.surfaceMuted(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(CursorTheme.border(for: colorScheme), lineWidth: 1)
                )
            }
        }
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
        linkedTaskState(for: tab, taskStatesByID: taskStatesByID(for: tab.workspacePath))
    }

    private func linkedTaskState(for tab: AgentTab, taskStatesByID: [UUID: TaskState]) -> AgentTaskState? {
        guard let taskID = tab.linkedTaskID else { return nil }
        guard let taskState = taskStatesByID[taskID] else { return nil }
        if taskState == .backlog { return .none }
        if tab.isRunning { return .processing }
        if tab.turns.last?.displayState == .stopped { return .stopped }
        if tab.turns.last?.displayState == .completed { return .review }
        return .todo
    }

    private func linkedTaskState(for savedTab: SavedAgentTab) -> AgentTaskState? {
        linkedTaskState(for: savedTab, taskStatesByID: taskStatesByID(for: savedTab.workspacePath))
    }

    private func linkedTaskState(for savedTab: SavedAgentTab, taskStatesByID: [UUID: TaskState]) -> AgentTaskState? {
        guard let taskID = savedTab.linkedTaskID else { return nil }
        guard let taskState = taskStatesByID[taskID] else { return nil }
        if taskState == .backlog { return .none }
        if savedTab.restoredLastTurnState == .stopped { return .stopped }
        if savedTab.restoredLastTurnState == .completed { return .review }
        return .todo
    }

    private func taskStatesByID(for workspacePath: String) -> [UUID: TaskState] {
        projectTasksStore.taskStatesByID(for: workspacePath)
    }

    /// Agent status of a task in this workspace if any agent tab is linked to it.
    private func linkedTaskStateForTask(taskID: UUID, workspacePath: String) -> AgentTaskState? {
        let taskStates = taskStatesByID(for: workspacePath)
        if let tab = tabManager.tabs.first(where: { $0.workspacePath == workspacePath && $0.linkedTaskID == taskID }) {
            return linkedTaskState(for: tab, taskStatesByID: taskStates)
        }
        guard let savedTab = tabManager.recentlyClosedTabs.reversed().first(where: { $0.workspacePath == workspacePath && $0.linkedTaskID == taskID }) else {
            return nil
        }
        return linkedTaskState(for: savedTab, taskStatesByID: taskStates)
    }

    /// Builds [taskID: status] for the given workspace so the Tasks list has an explicit dependency on tab state and updates when linked tabs run/complete.
    private func linkedStatusesForWorkspace(_ workspacePath: String) -> [UUID: AgentTaskState] {
        let taskStates = taskStatesByID(for: workspacePath)
        var result: [UUID: AgentTaskState] = [:]
        for savedTab in tabManager.recentlyClosedTabs where savedTab.workspacePath == workspacePath {
            guard let taskID = savedTab.linkedTaskID else { continue }
            result[taskID] = linkedTaskState(for: savedTab, taskStatesByID: taskStates)
        }
        for tab in tabManager.tabs where tab.workspacePath == workspacePath {
            guard let taskID = tab.linkedTaskID else { continue }
            result[taskID] = linkedTaskState(for: tab, taskStatesByID: taskStates)
        }
        return result
    }

    private func hangDiagnosticsSnapshot() -> [String: String] {
        let currentPath = tabManager.activeProjectPath ?? currentWorkspacePath
        let runningTabs = tabManager.tabs.filter(\.isRunning).count
        var snapshot: [String: String] = [
            "activeProjectPath": currentPath,
            "openProjects": "\(tabManager.projects.count)",
            "openAgentTabs": "\(tabManager.tabs.count)",
            "recentlyClosedTaskTabs": "\(tabManager.recentlyClosedTabs.count)",
            "runningAgentTabs": "\(runningTabs)",
            "selectedAgentTab": tabManager.selectedTabID?.uuidString ?? "nil",
            "selectedTasksPath": tabManager.selectedTasksViewPath ?? "nil",
            "selectedTerminal": tabManager.selectedTerminalID?.uuidString ?? "nil"
        ]

        if let tasksPath = tabManager.selectedTasksViewPath {
            let tasks = projectTasksStore.tasks(for: tasksPath)
            let linkedStatuses = linkedStatusesForWorkspace(tasksPath)
            snapshot["tasksPath"] = tasksPath
            snapshot["tasksTotal"] = "\(tasks.count)"
            snapshot["tasksBacklog"] = "\(tasks.filter { $0.taskState == .backlog }.count)"
            snapshot["tasksInProgress"] = "\(tasks.filter { $0.taskState == .inProgress }.count)"
            snapshot["tasksCompleted"] = "\(tasks.filter { $0.taskState == .completed }.count)"
            snapshot["tasksProcessing"] = "\(linkedStatuses.values.filter { $0 == .processing }.count)"
            snapshot["tasksReview"] = "\(linkedStatuses.values.filter { $0 == .review }.count)"
            snapshot["tasksStopped"] = "\(linkedStatuses.values.filter { $0 == .stopped }.count)"
            snapshot["tasksTodo"] = "\(linkedStatuses.values.filter { $0 == .todo || $0 == .none }.count)"
        }

        return snapshot
    }

    private func updateHangDiagnosticsSnapshot() {
        HangDiagnostics.shared.updateSnapshot(hangDiagnosticsSnapshot())
    }

    private func recordHangEvent(_ event: String, metadata: [String: String] = [:]) {
        updateHangDiagnosticsSnapshot()
        HangDiagnostics.shared.record(event, metadata: metadata)
    }

    private func showTasksComposer(workspacePath path: String?, startNewTask: Bool = true) {
        let resolved = (path ?? tabManager.activeProjectPath ?? currentWorkspacePath)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolved.isEmpty else { return }
        recordHangEvent("show-tasks-composer", metadata: [
            "workspacePath": resolved,
            "startNewTask": startNewTask ? "true" : "false"
        ])
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

    /// Focuses the agent tab linked to the task (reopens from recently closed if needed). Does not send a prompt.
    private func openLinkedAgent(for task: ProjectTask, workspacePath: String) {
        if let agentTabID = projectTasksStore.linkedAgentTabID(workspacePath: workspacePath, taskID: task.id),
           tabManager.tabs.contains(where: { $0.id == agentTabID }) {
            selectLinkedAgentTab(agentTabID)
            return
        }
        if tabManager.reopenLinkedTaskTab(
            workspacePath: workspacePath,
            taskID: task.id,
            preferredTabID: projectTasksStore.linkedAgentTabID(workspacePath: workspacePath, taskID: task.id)
        ) {
            return
        }
        guard let tab = tabManager.tabs.first(where: { $0.workspacePath == workspacePath && $0.linkedTaskID == task.id }) else { return }
        projectTasksStore.assignAgentTab(workspacePath: workspacePath, taskID: task.id, agentTabID: tab.id)
        selectLinkedAgentTab(tab.id)
    }

    /// Focuses the linked agent tab then sends the "continue" prompt.
    private func continueAgent(for task: ProjectTask, workspacePath: String) {
        recordHangEvent("continue-agent", metadata: [
            "workspacePath": workspacePath,
            "taskID": task.id.uuidString
        ])
        openLinkedAgent(for: task, workspacePath: workspacePath)
        sendContinueToLinkedConversation(task: task, workspacePath: workspacePath)
    }

    /// Unlinks and closes the current agent for the task, then starts a fresh agent with the task content.
    private func resetAgent(for task: ProjectTask, workspacePath: String) {
        recordHangEvent("reset-agent", metadata: [
            "workspacePath": workspacePath,
            "taskID": task.id.uuidString
        ])
        if let tab = tabManager.tabs.first(where: { $0.workspacePath == workspacePath && $0.linkedTaskID == task.id }) {
            stopStreaming(for: tab)
            tabManager.closeTab(tab.id)
        }
        projectTasksStore.clearAgentTab(workspacePath: workspacePath, taskID: task.id)
        appState.notifyTasksDidUpdate()
        sendTaskToAgent(
            prompt: task.content,
            taskID: task.id,
            screenshotPaths: task.screenshotPaths,
            providerID: task.providerID,
            modelId: task.modelId,
            workspacePath: workspacePath,
            selectAgent: true
        )
    }

    /// Sends a "continue" prompt to the conversation linked to the task so the user can restart the agent from the 3-dot menu.
    private func sendContinueToLinkedConversation(task: ProjectTask, workspacePath: String) {
        guard let tab = tabManager.tabs.first(where: { $0.workspacePath == workspacePath && $0.linkedTaskID == task.id }) else { return }
        sendInCurrentTab(prompt: "continue", tab: tab)
    }

    private func sendTaskToAgent(
        prompt: String,
        taskID: UUID,
        screenshotPaths: [String],
        providerID: AgentProviderID,
        modelId: String,
        workspacePath: String,
        selectAgent: Bool = false
    ) {
        recordHangEvent("queue-agent", metadata: [
            "workspacePath": workspacePath,
            "taskID": taskID.uuidString,
            "promptLength": "\(prompt.count)",
            "screenshots": "\(screenshotPaths.count)",
            "selectAgent": selectAgent ? "true" : "false"
        ])
        if let existingAgentTabID = projectTasksStore.linkedAgentTabID(workspacePath: workspacePath, taskID: taskID),
           tabManager.tabs.contains(where: { $0.id == existingAgentTabID }) {
            if selectAgent {
                selectLinkedAgentTab(existingAgentTabID)
            }
            return
        }

        var initialPrompt = prompt
        for path in screenshotPaths {
            let screenshotURL = ProjectTasksStorage.taskScreenshotFileURL(workspacePath: workspacePath, screenshotPath: path)
            initialPrompt += "\n\n[Screenshot attached: \(screenshotURL.path)]"
        }

        if let newTab = addNewAgentTab(
            initialPrompt: initialPrompt,
            lastWorkspacePath: workspacePath,
            modelId: modelId,
            providerID: providerID,
            select: selectAgent
        ) {
            newTab.linkedTaskID = taskID
            projectTasksStore.assignAgentTab(workspacePath: workspacePath, taskID: taskID, agentTabID: newTab.id)
            if !screenshotPaths.isEmpty {
                newTab.hasAttachedScreenshot = true
            }
        }
    }

    private func createLinkedTaskAndAgent(
        taskContent: String,
        agentPrompt: String? = nil,
        workspacePath: String,
        providerID: AgentProviderID,
        modelId: String,
        selectAgent: Bool = true
    ) {
        let trimmedTaskContent = taskContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAgentPrompt = (agentPrompt ?? taskContent).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTaskContent.isEmpty, !trimmedAgentPrompt.isEmpty else { return }

        let task = projectTasksStore.addTask(
            workspacePath: workspacePath,
            content: trimmedTaskContent,
            providerID: providerID,
            modelId: modelId
        )
        sendTaskToAgent(
            prompt: trimmedAgentPrompt,
            taskID: task.id,
            screenshotPaths: task.screenshotPaths,
            providerID: task.providerID,
            modelId: task.modelId,
            workspacePath: workspacePath,
            selectAgent: selectAgent
        )
        appState.notifyTasksDidUpdate()
    }

    private func stopAgentForTask(_ task: ProjectTask, workspacePath: String) {
        recordHangEvent("stop-agent", metadata: [
            "workspacePath": workspacePath,
            "taskID": task.id.uuidString
        ])
        guard let tab = tabManager.tabs.first(where: { $0.workspacePath == workspacePath && $0.linkedTaskID == task.id }) else { return }
        stopStreaming(for: tab)
    }

    private func tasksListContent(tasksPath: String, triggerAddNewTask: Binding<Bool>) -> some View {
        let linkedStatuses = linkedStatusesForWorkspace(tasksPath)
        return PopoutTasksListContent(
            tasksPath: tasksPath,
            triggerAddNewTask: triggerAddNewTask,
            linkedStatuses: linkedStatuses,
            newTaskProviderID: appState.selectedAgentProviderID,
            modelsForProvider: { providerID in
                modelPickerModels(for: providerID, including: nil)
            },
            onSendToAgent: { prompt, taskID, screenshotPaths, providerID, modelId in
                if let taskID {
                    sendTaskToAgent(
                        prompt: prompt,
                        taskID: taskID,
                        screenshotPaths: screenshotPaths,
                        providerID: providerID,
                        modelId: modelId,
                        workspacePath: tasksPath,
                        selectAgent: false
                    )
                }
            },
            onOpenLinkedAgent: { task in openLinkedAgent(for: task, workspacePath: tasksPath) },
            onContinueAgent: { task in continueAgent(for: task, workspacePath: tasksPath) },
            onResetAgent: { task in resetAgent(for: task, workspacePath: tasksPath) },
            onStopAgent: { task in stopAgentForTask(task, workspacePath: tasksPath) },
            onTasksDidUpdate: { appState.notifyTasksDidUpdate() },
            onDismiss: { tabManager.hideTasksView() },
            onLaunchSetupAgent: { path in
                _ = addNewAgentTab(initialPrompt: projectSetupAgentPrompt, lastWorkspacePath: path)
            },
            showHeader: false
        )
    }

    /// Opens Dashboard: in-app tabbed terminals running each startup script for the project.
    private func openDashboard(workspacePath path: String) {
        let root = projectRootForTerminal(workspacePath: path)
        let scripts = ProjectSettingsStorage.getStartupScripts(workspacePath: root)
        guard !scripts.isEmpty else { return }
        let labels = ProjectSettingsStorage.getStartupScriptDisplayLabels(workspacePath: root)
        if tabManager.addDashboardTabs(workspacePath: path, scripts: scripts, labels: labels) {
            if appState.isMainContentCollapsed {
                withAnimation(.easeInOut(duration: 0.2)) { appState.isMainContentCollapsed = false }
            }
        }
    }

    /// Removes a project (all tabs for that workspace path) from the sidebar. Stops any running agents first.
    private func removeProject(workspacePath path: String) {
        for t in tabManager.tabs where t.workspacePath == path {
            stopStreaming(for: t)
        }
        tabManager.removeProject(path)
    }

    private func addProject() {
        seedProjectHubDefaults()
        tabManager.showAddProjectView()
    }

    private func seedProjectHubDefaults() {
        if newProjectParentPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            newProjectParentPath = preferredProjectBrowserRoot
        }
        if gitCloneParentPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            gitCloneParentPath = preferredProjectBrowserRoot
        }
        if let selectedExistingProjectPath,
           !tabManager.projects.contains(where: { $0.path == selectedExistingProjectPath }),
           selectedExistingProjectPath != currentWorkspacePath {
            self.selectedExistingProjectPath = nil
        }
        if selectedExistingProjectPath == nil {
            selectedExistingProjectPath = tabManager.projects.first?.path ?? devFolders.first?.path
        }
    }

    private func selectFolder(
        title: String,
        message: String,
        startingAt path: String? = nil
    ) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = title
        panel.message = message

        let preferredPath = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedPath = preferredPath.isEmpty ? preferredProjectBrowserRoot : preferredPath
        if FileManager.default.fileExists(atPath: resolvedPath) {
            panel.directoryURL = URL(fileURLWithPath: resolvedPath)
        }

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }

    private func updateProjectContext(to path: String) {
        workspacePath = path
        appState.workspacePath = path
        tabManager.activeTab?.errorMessage = nil
        refreshGitState(for: path, force: true)
    }

    private func openProjectInTasksView(_ path: String) {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return }

        tabManager.addProject(path: trimmedPath, select: true)
        tabManager.showTasksView(workspacePath: trimmedPath)
        updateProjectContext(to: trimmedPath)
    }

    private func openProjectInNewAgentTab(_ path: String) {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return }

        tabManager.addProject(path: trimmedPath, select: true)
        showTasksComposer(workspacePath: trimmedPath, startNewTask: true)
        updateProjectContext(to: trimmedPath)
    }

    private func launchProjectCreationAgent(in path: String, idea: String) {
        let trimmedIdea = idea.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIdea.isEmpty else {
            openProjectInTasksView(path)
            return
        }
        tabManager.addProject(path: path, select: true)
        updateProjectContext(to: path)
        let prompt = """
Create a brand new project in this empty workspace based on the user's request: "\(trimmedIdea)".

Build the initial app or service structure directly in this repository, choose sensible defaults, and make it runnable without making the user decide every low-level detail.

\(projectSetupAgentPrompt)
"""
        _ = addNewAgentTab(initialPrompt: prompt, lastWorkspacePath: path)
    }

    private func openExistingProjectFromHub(_ path: String) {
        projectHubErrorMessage = nil
        projectHubStatusMessage = nil
        selectedExistingProjectPath = path
        openProjectInTasksView(path)
    }

    private func browseForExistingProject() {
        guard let path = selectFolder(
            title: "Open Project",
            message: "Choose a project folder to add to Cursor Metro.",
            startingAt: selectedExistingProjectPath ?? currentWorkspacePath
        ) else { return }
        selectedExistingProjectPath = path
        openExistingProjectFromHub(path)
    }

    private func createEmptyProjectFromHub() {
        projectHubErrorMessage = nil
        projectHubStatusMessage = nil
        switch createProjectDirectory(parentPath: newProjectParentPath, folderName: newProjectName) {
        case .success(let path):
            projectHubStatusMessage = "Created \(appState.workspaceDisplayName(for: path))."
            tabManager.addProject(path: path, select: false)
        case .failure(let error):
            projectHubErrorMessage = error.localizedDescription
        }
    }

    private func createProjectWithAgentFromHub() {
        projectHubErrorMessage = nil
        projectHubStatusMessage = nil
        switch createProjectDirectory(parentPath: newProjectParentPath, folderName: newProjectName) {
        case .success(let path):
            projectHubStatusMessage = "Created \(appState.workspaceDisplayName(for: path))."
            launchProjectCreationAgent(in: path, idea: newProjectIdea)
        case .failure(let error):
            projectHubErrorMessage = error.localizedDescription
        }
    }

    private func cloneProjectFromHub(runSetupAgent: Bool) {
        projectHubErrorMessage = nil
        projectHubStatusMessage = nil
        isProjectHubBusy = true
        let repositoryURL = gitRepositoryURL
        let parentPath = gitCloneParentPath
        let folderName = gitCloneFolderName
        DispatchQueue.global(qos: .userInitiated).async {
            let result = cloneRepository(
                repositoryURL: repositoryURL,
                destinationParentPath: parentPath,
                folderName: folderName.isEmpty ? nil : folderName
            )
            DispatchQueue.main.async {
                isProjectHubBusy = false
                switch result {
                case .success(let path):
                    projectHubStatusMessage = "Cloned \(appState.workspaceDisplayName(for: path))."
                    if runSetupAgent {
                        tabManager.addProject(path: path, select: true)
                        updateProjectContext(to: path)
                        _ = addNewAgentTab(initialPrompt: projectSetupAgentPrompt, lastWorkspacePath: path)
                    } else {
                        openProjectInTasksView(path)
                    }
                case .failure(let error):
                    projectHubErrorMessage = error.localizedDescription
                }
            }
        }
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

            hiddenShortcutButton("Add Task", key: "t") {
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
                hiddenShortcutButton("Stop", key: "c", modifiers: .control) {
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
            active.currentBranch = ""
            refreshGitState(for: path, force: true)
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
    private func addNewAgentTab(
        initialPrompt: String? = nil,
        lastWorkspacePath: String? = nil,
        modelId: String? = nil,
        providerID: AgentProviderID? = nil,
        select: Bool = true
    ) -> AgentTab? {
        let targetWorkspacePath = lastWorkspacePath ?? tabManager.activeProjectPath
        guard let targetWorkspacePath else { return nil }
        let resolvedProviderID = providerID ?? appState.selectedAgentProviderID
        // Pass through explicit modelId; nil means new tab will use app default from Settings.
        if appState.isMainContentCollapsed {
            withAnimation(.easeInOut(duration: 0.2)) { appState.isMainContentCollapsed = false }
        }
        guard let newTab = tabManager.addTab(
            initialPrompt: initialPrompt,
            workspacePath: targetWorkspacePath,
            modelId: modelId,
            providerID: resolvedProviderID,
            select: select
        ) else { return nil }
        if let snapshot = gitBranchSnapshotsByWorkspace[newTab.workspacePath] {
            currentBranch = snapshot.current
            gitBranches = snapshot.branches
            newTab.currentBranch = snapshot.current
        } else {
            refreshGitState(for: newTab.workspacePath)
        }
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

    /// Models to show in the picker (respects "disabled" preference; uses provider defaults when never set). Includes effectiveSelection if it was hidden so the UI stays consistent.
    private func modelPickerModels(for providerID: AgentProviderID = .cursor, including effectiveSelection: String? = nil) -> [ModelOption] {
        let allIds = Set(appState.availableModels(for: providerID).map(\.id))
        let disabled = AppPreferences.effectiveDisabledModelIds(
            allIds: allIds,
            raw: disabledModelIdsRaw,
            defaultEnabledModelIds: AgentProviders.defaultEnabledModelIds(for: providerID),
            defaultModelID: AgentProviders.defaultModelID(for: providerID)
        )
        var visible = appState.visibleModels(for: providerID, disabledIds: disabled)
        let currentId = effectiveSelection ?? selectedModel
        if !visible.contains(where: { $0.id == currentId }),
           let current = appState.model(for: currentId, providerID: providerID) {
            visible = visible + [current]
        }
        return visible
    }

    private func effectiveSelectedModel(for providerID: AgentProviderID) -> String {
        if appState.model(for: selectedModel, providerID: providerID) != nil {
            return selectedModel
        }
        return appState.defaultModelID(for: providerID)
    }

    /// Effective model for a tab: tab's explicit model, or app default from Settings, sanitized against available models.
    private func effectiveModelForTab(_ tab: AgentTab) -> String {
        let raw = tab.modelId ?? appDefaultModelId
        if appState.model(for: raw, providerID: tab.providerID) != nil {
            return raw
        }
        return appState.defaultModelID(for: tab.providerID)
    }

    private var apiUsagePercent: Int {
        min(100, (messagesSentForUsage * 100) / AppLimits.includedAPIQuota)
    }

    private func refreshQuickActions(for workspacePath: String, force: Bool = false) {
        let normalizedPath = workspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else {
            quickActionCommands = []
            return
        }

        if let cached = quickActionSnapshotsByWorkspace[normalizedPath] {
            quickActionCommands = cached
            if !force {
                return
            }
        }

        Task.detached(priority: .utility) {
            let commands = QuickActionStorage.commandsForWorkspace(workspacePath: normalizedPath)
            await MainActor.run {
                quickActionSnapshotsByWorkspace[normalizedPath] = commands
                guard currentWorkspacePath == normalizedPath else { return }
                quickActionCommands = commands
            }
        }
    }

    private func refreshGitState(for workspacePath: String, force: Bool = false) {
        let normalizedPath = workspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else {
            currentBranch = ""
            gitBranches = []
            return
        }

        if let cached = gitBranchSnapshotsByWorkspace[normalizedPath] {
            currentBranch = cached.current
            gitBranches = cached.branches
            if let active = tabManager.activeTab, active.workspacePath == normalizedPath {
                active.currentBranch = cached.current
            }
            if !force {
                return
            }
        } else {
            if let active = tabManager.activeTab, active.workspacePath == normalizedPath {
                currentBranch = active.currentBranch
            } else {
                currentBranch = ""
            }
            gitBranches = []
        }

        Task.detached(priority: .utility) {
            let result = loadGitBranches(workspacePath: normalizedPath)
            let snapshot = GitBranchSnapshot(current: result.current, branches: result.branches)
            await MainActor.run {
                gitBranchSnapshotsByWorkspace[normalizedPath] = snapshot
                guard currentWorkspacePath == normalizedPath else { return }
                currentBranch = snapshot.current
                gitBranches = snapshot.branches
                tabManager.activeTab?.currentBranch = snapshot.current
            }
        }
    }

    private let sidebarWidth: CGFloat = 250

    /// Tab focuses the prompt input; these are set by SubmittableTextEditor via onFocusRequested.
    @State private var focusPromptInput: (() -> Void)?
    @State private var isPromptFirstResponder: (() -> Bool)?

    /// Linked agent tabs are shown only for in-progress tasks that still need agent visibility.
    private func isAgentTabVisibleInSidebar(_ tab: AgentTab) -> Bool {
        guard let taskID = tab.linkedTaskID else { return true }
        guard let task = projectTasksStore.task(for: tab.workspacePath, id: taskID) else { return false }
        guard task.taskState == .inProgress else { return false }
        let agentState = linkedTaskState(for: tab)
        return agentState == .processing || agentState == .review || agentState == .stopped
    }

    /// Tabs grouped by workspace path, order preserved by first occurrence. Linked agent tabs only appear while their tasks are actively in progress. Projects hidden in Settings are excluded.
    /// Terminal tabs are not shown in the sidebar; they appear only as tabs in the Dashboard panel (Dashboard + one tab per terminal).
    private var tabGroups: [TabSidebarGroup] {
        _ = appState.taskListRevision
        let visibleTabs = tabManager.tabs.filter { isAgentTabVisibleInSidebar($0) }
        let groupedTabs = Dictionary(grouping: visibleTabs, by: \.workspacePath)
        let hiddenPaths = AppPreferences.hiddenProjectPaths(from: hiddenProjectPathsRaw)
        return tabManager.projects
            .filter { !hiddenPaths.contains(AppPreferences.normalizedProjectPath($0.path)) }
            .map { project in
                let path = project.path
                let displayName = appState.workspaceDisplayName(for: path)
                return TabSidebarGroup(
                    path: path,
                    displayName: displayName.isEmpty ? "Project" : displayName,
                    tabs: groupedTabs[path] ?? [],
                    terminalTabs: [] // Terminal tabs live in Dashboard panel tab bar only, not in sidebar
                )
            }
    }

    /// Terminals for the current project when in Dashboard view (for panel tab bar).
    private func dashboardPanelTerminals(for workspacePath: String) -> [TerminalTab] {
        tabManager.terminalTabs.filter { $0.workspacePath == workspacePath }
    }

    /// True when Dashboard view is selected, we have terminals, but no terminal tab is selected (show overview).
    private var showingDashboardOverview: Bool {
        guard let path = selectedProjectPath,
              tabManager.selectedDashboardViewPath == path,
              tabManager.selectedTerminalID == nil else { return false }
        return !dashboardPanelTerminals(for: path).isEmpty
    }

    @ViewBuilder
    private var mainContentZStack: some View {
        if tabManager.selectedAddProjectView || !hasOpenProjects {
            addProjectHubContent
        } else {
            let showingDashboardEmpty = selectedProjectPath != nil
                && tabManager.selectedDashboardViewPath == selectedProjectPath
                && tabManager.dashboardTabs(for: selectedProjectPath!).isEmpty
            ZStack {
                if !tabManager.terminalTabs.isEmpty {
                    MultiTerminalHostView(
                        tabs: tabManager.terminalTabs.map { ($0.id, $0.workspacePath, $0.initialCommand) },
                        selectedID: tabManager.selectedTerminalID,
                        store: tabManager.terminalHostStore
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if tabManager.selectedTasksViewPath != nil, let tasksPath = tabManager.selectedTasksViewPath, tasksPath == selectedProjectPath {
                    tasksListContent(tasksPath: tasksPath, triggerAddNewTask: $tasksViewTriggerAddNew)
                }
                if showingDashboardEmpty {
                    dashboardEmptyStateView(workspacePath: selectedProjectPath!)
                }
                if showingDashboardOverview {
                    dashboardOverviewView()
                }
                if tabManager.selectedTerminalID == nil, !showingDashboardEmpty, !showingDashboardOverview {
                    agentOrEmptyContent
                }
            }
        }
    }

    /// Tab bar shown in the Dashboard panel (same style as PanelTabBarView: chrome strip + pill). Preview + terminal tabs with close.
    @ViewBuilder
    private func dashboardPanelTabBar(workspacePath path: String) -> some View {
        let terminals = dashboardPanelTerminals(for: path)
        HStack(spacing: 0) {
            Button {
                tabManager.selectedTerminalID = nil
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "eye")
                        .font(.system(size: 13))
                    Text("Preview")
                        .font(.system(size: 13, weight: tabManager.selectedTerminalID == nil ? .semibold : .medium))
                }
                .foregroundStyle(tabManager.selectedTerminalID == nil ? CursorTheme.textPrimary(for: colorScheme) : CursorTheme.textSecondary(for: colorScheme))
                .padding(.horizontal, CursorTheme.spaceM)
                .padding(.vertical, CursorTheme.spaceS + CursorTheme.spaceXXS)
            }
            .buttonStyle(.plain)
            .background(tabManager.selectedTerminalID == nil ? CursorTheme.surfaceMuted(for: colorScheme) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: CursorTheme.radiusTabBarPill, style: .continuous))
            .help("Preview overview")
            ForEach(terminals) { term in
                HStack(spacing: 0) {
                    Button {
                        tabManager.selectedTerminalID = term.id
                        tabManager.selectedTabID = nil
                        tabManager.selectedTasksViewPath = nil
                        tabManager.selectedProjectPath = term.workspacePath
                        tabManager.selectedDashboardViewPath = term.isDashboardTab ? term.workspacePath : nil
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "terminal")
                                .font(.system(size: 13))
                            Text(term.title)
                                .font(.system(size: 13, weight: term.id == tabManager.selectedTerminalID ? .semibold : .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(term.id == tabManager.selectedTerminalID ? CursorTheme.textPrimary(for: colorScheme) : CursorTheme.textSecondary(for: colorScheme))
                        .padding(.leading, CursorTheme.spaceM)
                        .padding(.trailing, CursorTheme.spaceS)
                        .padding(.vertical, CursorTheme.spaceS + CursorTheme.spaceXXS)
                    }
                    .buttonStyle(.plain)
                    .help(term.title)
                    Button(action: { tabManager.closeTerminalTab(term.id) }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                            .frame(width: 14, height: 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, CursorTheme.spaceS)
                }
                .background(term.id == tabManager.selectedTerminalID ? CursorTheme.surfaceMuted(for: colorScheme) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: CursorTheme.radiusTabBarPill, style: .continuous))
            }
        }
        .padding(.horizontal, CursorTheme.paddingHeaderHorizontal)
        .padding(.vertical, CursorTheme.spaceXS)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CursorTheme.chrome(for: colorScheme))
    }

    /// Shown when Preview tab is selected and terminals exist (user should pick a tab).
    private func dashboardOverviewView() -> some View {
        VStack(spacing: 16) {
            Image(systemName: "eye")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                .symbolRenderingMode(.hierarchical)
            Text("Select a tab above")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Shown when Preview is selected but Run has not been clicked yet.
    private func dashboardEmptyStateView(workspacePath path: String) -> some View {
        let root = projectRootForTerminal(workspacePath: path)
        let isConfigured = !ProjectSettingsStorage.getStartupScripts(workspacePath: root).isEmpty
        return VStack(spacing: CursorTheme.spaceXL) {
            Image(systemName: "eye")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                .symbolRenderingMode(.hierarchical)
            Text("Click Run to start your startup scripts")
                .font(.system(size: CursorTheme.fontBodyEmphasis, weight: .medium))
                .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
            HStack(spacing: CursorTheme.spaceS) {
                Spacer(minLength: 0)
                if isConfigured {
                    ActionButton(
                        title: "Run",
                        icon: "play.fill",
                        action: { openDashboard(workspacePath: path) },
                        help: "Run each startup script in its own Preview tab",
                        style: .primary
                    )
                }
                ActionButton(
                    title: isConfigured ? "Regenerate Setup" : "Configure Setup",
                    icon: "gearshape",
                    action: { _ = addNewAgentTab(initialPrompt: projectSetupAgentPrompt, lastWorkspacePath: path) },
                    help: isConfigured ? "Launch an agent to regenerate .metro/project.json scripts and debug URL" : "Launch an agent to set up .metro/project.json scripts and debug URL for this project",
                    style: .primary
                )
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var agentOrEmptyContent: some View {
        if let active = tabManager.activeTab {
            ObservedTabView(tab: active) { tab in
                agentAreaContent(tab: tab, expandedPromptTabID: $expandedPromptTabID)
            }
        } else if hasOpenProjects, selectedProjectPath != nil {
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            splashContentArea()
        }
    }

    private var bodyContent: some View {
        mainContentWithSidebar
    }

    @ViewBuilder
    private var mainContentWithSidebar: some View {
        GeometryReader { geometry in
            let contentWidth = max(0, geometry.size.width)
            let effectiveSidebarWidth = sidebarWidth
            let agentWidth = isMainContentCollapsed ? 0 : max(0, contentWidth - effectiveSidebarWidth - 1) // 1 for divider
            let sidebarColumn = VStack(spacing: 0) {
                leftColumnHeader
                tabSidebar
            }
            .frame(width: effectiveSidebarWidth)
            .clipped()
            .padding(isSidebarOnRight ? .leading : .trailing, CursorTheme.spaceS)
            let dividerView = Group {
                if !isMainContentCollapsed {
                    Divider()
                        .frame(width: 1)
                        .background(CursorTheme.border(for: colorScheme))
                        .frame(maxHeight: .infinity)
                }
            }
            let mainColumn = Group {
                if isMainContentCollapsed {
                    Color.clear.frame(width: 0).clipped()
                } else {
                    VStack(spacing: 0) {
                        mainColumnHeaderArea
                        if tabManager.selectedDashboardViewPath == selectedProjectPath, let path = selectedProjectPath, !path.isEmpty {
                            dashboardPanelTabBar(workspacePath: path)
                        }
                        mainContentZStack
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(width: agentWidth)
            .clipped()
            .padding(isSidebarOnRight ? .trailing : .leading, CursorTheme.spaceS)

            HStack(alignment: .top, spacing: 0) {
                if isSidebarOnRight {
                    mainColumn
                    dividerView
                    sidebarColumn
                } else {
                    sidebarColumn
                    dividerView
                    mainColumn
                }
            }
            .clipped()
            .frame(maxWidth: .infinity, alignment: isSidebarOnRight ? .trailing : .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private var bodyWithDashboardPersistence: some View {
        bodyContent
            .padding(16)
            .frame(minWidth: isMainContentCollapsed ? 260 : (sidebarWidth + 110), maxWidth: .infinity, minHeight: isMainContentCollapsed ? 280 : 400, maxHeight: .infinity)
            .preferredColorScheme(resolvedColorScheme)
            .background(CursorTheme.panelGradient(for: colorScheme))
    }

    private var bodyWithShortcuts: some View {
        bodyWithDashboardPersistence
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
    }

    private var bodyWithLifecycle: some View {
        bodyWithShortcuts
        .onAppear {
            sanitizeSelectedModel()
            devFolders = loadDevFolders(rootPaths: projectScanRoots)
            tabManager.setDiscoveredProjectsFromPaths(devFolders.map(\.path))
            seedProjectHubDefaults()
            refreshQuickActions(for: currentWorkspacePath)
            refreshGitState(for: currentWorkspacePath)
            updateHangDiagnosticsSnapshot()
        }
        .onChange(of: workspacePath) { _, _ in
            refreshQuickActions(for: workspacePath, force: true)
            updateHangDiagnosticsSnapshot()
        }
        .onChange(of: projectScanRootsRaw) { _, _ in
            devFolders = loadDevFolders(rootPaths: projectScanRoots)
            tabManager.setDiscoveredProjectsFromPaths(devFolders.map(\.path))
            seedProjectHubDefaults()
            updateHangDiagnosticsSnapshot()
        }
        .onChange(of: projectsRootPath) { _, _ in
            devFolders = loadDevFolders(rootPaths: projectScanRoots)
            tabManager.setDiscoveredProjectsFromPaths(devFolders.map(\.path))
            seedProjectHubDefaults()
            updateHangDiagnosticsSnapshot()
        }
        .onChange(of: selectedModel) { _, _ in
            sanitizeSelectedModel()
            updateHangDiagnosticsSnapshot()
        }
        .onChange(of: tabManager.selectedTabID) { _, _ in
            refreshGitState(for: currentWorkspacePath)
            updateHangDiagnosticsSnapshot()
        }
        .onChange(of: tabManager.selectedProjectPath) { _, _ in
            let path = currentWorkspacePath
            refreshQuickActions(for: path)
            refreshGitState(for: path)
            updateHangDiagnosticsSnapshot()
        }
        .onChange(of: tabManager.selectedTasksViewPath) { _, _ in
            updateHangDiagnosticsSnapshot()
        }
        .onChange(of: tabManager.selectedTerminalID) { _, _ in
            updateHangDiagnosticsSnapshot()
        }
        .onChange(of: appState.taskListRevision) { _, _ in
            updateHangDiagnosticsSnapshot()
        }
    }

    private var composedBody: some View {
        bodyWithLifecycle
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
            if !screenshotPreviewURLs.isEmpty {
                ScreenshotPreviewModal(imageURLs: screenshotPreviewURLs, initialIndex: screenshotPreviewIndex, isPresented: Binding(
                    get: { true },
                    set: {
                        if !$0 {
                            screenshotPreviewURLs = []
                            screenshotPreviewIndex = 0
                        }
                    }
                ))
            }
        }
        .overlay(globalShortcutOverlay)
        #if DEBUG
        .enableInjection()
        #endif
    }

    var body: some View {
        composedBody
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

    /// Logo + BETA/DEBUG in sidebar column; when sidebar on right, header is mirrored (expand/menu on leading edge). Logo uses active project color.
    private var leftColumnHeader: some View {
        let expandChevron = isSidebarOnRight ? "chevron.left.2" : "chevron.right.2"
        let projectColor = currentWorkspacePath.isEmpty
            ? CursorTheme.textPrimary(for: colorScheme)
            : CursorTheme.colorForWorkspace(path: currentWorkspacePath)
        return HStack(spacing: 14) {
            SidebarLogoView(height: 36, projectColor: projectColor)

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
            if isSidebarOnRight, isMainContentCollapsed {
                IconButton(icon: expandChevron, action: { withAnimation(.easeInOut(duration: 0.2)) { appState.isMainContentCollapsed.toggle() } }, help: "Expand")
                ThreeDotMenuButton(size: .medium, help: "More options") {
                    Button(action: { appState.showSettingsSheet = true }) {
                        Label("Settings", systemImage: "gearshape")
                    }
                    Button(action: dismiss) {
                        Label("Minimise", systemImage: "minus")
                    }
                }
            }
            if !isSidebarOnRight, isMainContentCollapsed {
                ThreeDotMenuButton(size: .medium, help: "More options") {
                    Button(action: { appState.showSettingsSheet = true }) {
                        Label("Settings", systemImage: "gearshape")
                    }
                    Button(action: dismiss) {
                        Label("Minimise", systemImage: "minus")
                    }
                }
                IconButton(icon: expandChevron, action: { withAnimation(.easeInOut(duration: 0.2)) { appState.isMainContentCollapsed.toggle() } }, help: "Expand")
            }
        }
        .padding(.horizontal, isSidebarOnRight ? 0 : Self.sidebarHeaderPadding)
        .padding(.leading, isSidebarOnRight ? CursorTheme.spaceS : 10)
        .padding(.trailing, isSidebarOnRight ? CursorTheme.spaceM : Self.sidebarHeaderPadding)
        .padding(.top, Self.sidebarHeaderVerticalPadding)
        .padding(.bottom, Self.sidebarHeaderVerticalPadding)
    }

    /// Single title row: icon + header (e.g. Tasks / agent title) on the left, title bar buttons (collapse, sidebar, settings, minimise) on the right.
    private var mainColumnTitleRow: some View {
        let collapseChevron = isSidebarOnRight ? "chevron.right.2" : "chevron.left.2"
        return HStack(alignment: .center, spacing: 0) {
            mainColumnTitleContent
            Spacer(minLength: 0)
            IconButton(icon: collapseChevron, action: { withAnimation(.easeInOut(duration: 0.2)) { appState.isMainContentCollapsed.toggle() } }, help: "Collapse")
            IconButton(icon: isSidebarOnRight ? "sidebar.leading" : "sidebar.trailing", action: {
                withAnimation(.easeInOut(duration: 0.2)) { isSidebarOnRight.toggle() }
            }, help: isSidebarOnRight ? "Move sidebar to left" : "Move sidebar to right")
            IconButton(icon: "gearshape", action: { appState.showSettingsSheet = true }, help: "Settings")
            IconButton(icon: "minus", action: dismiss, help: "Minimise")
        }
        .padding(.leading, CursorTheme.paddingHeaderHorizontal)
        .padding(.trailing, CursorTheme.spaceS)
        .padding(.vertical, CursorTheme.paddingHeaderVertical)
    }

    /// Header area: title row (agent prompt expands in place by wrapping, no separate card). When Dashboard is running, show Stop/Open in Browser row.
    @ViewBuilder
    private var mainColumnHeaderArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            mainColumnTitleRow
            if tabManager.selectedDashboardViewPath == selectedProjectPath,
               let path = selectedProjectPath, !path.isEmpty,
               !tabManager.dashboardTabs(for: path).isEmpty {
                dashboardButtonsRow(workspacePath: path)
            }
        }
    }

    /// Stop, Open in Browser — shown in Dashboard header only when Preview tabs are running (Run/Configure live in empty state).
    private func dashboardButtonsRow(workspacePath path: String) -> some View {
        let debugURL = (ProjectSettingsStorage.getDebugURL(workspacePath: path) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let isDashboardRunning = !tabManager.dashboardTabs(for: path).isEmpty
        let hasPreviewURL = !debugURL.isEmpty
        return HStack(spacing: CursorTheme.spaceS) {
            if isDashboardRunning {
                ActionButton(
                    title: "Stop",
                    icon: "stop.fill",
                    action: { tabManager.closeDashboardTabs(workspacePath: path) },
                    help: "Close Preview tabs",
                    style: .primary
                )
                if hasPreviewURL {
                    ActionButton(
                        title: "Open in Browser",
                        icon: "safari",
                        action: {
                            guard let url = URL(string: debugURL) else { return }
                            openURLInChrome(url)
                        },
                        help: "Open the preview URL in Chrome",
                        style: .primary
                    )
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, CursorTheme.paddingHeaderHorizontal)
        .padding(.trailing, CursorTheme.spaceS)
        .padding(.bottom, CursorTheme.paddingHeaderVertical)
    }

    @ViewBuilder
    private var mainColumnTitleContent: some View {
        if tabManager.selectedAddProjectView || !hasOpenProjects {
            addProjectTitleContent()
        } else if let tasksPath = tabManager.selectedTasksViewPath, tasksPath == selectedProjectPath {
            tasksTitleContent(workspacePath: tasksPath)
        } else if (tabManager.selectedTerminalID != nil || tabManager.selectedDashboardViewPath == selectedProjectPath), let path = selectedProjectPath {
            terminalTitleContent(workspacePath: path)
        } else if let tab = tabManager.activeTab {
            ObservedAgentTitleContent(tab: tab, expandedPromptTabID: $expandedPromptTabID) { tab in
                agentTitleContent(tab: tab, expandedPromptTabID: $expandedPromptTabID)
            }
        } else {
            EmptyView()
        }
    }

    private func addProjectTitleContent() -> some View {
        PanelHeaderView(icon: "gearshape", title: "Projects") {
            Text("Open an existing workspace, create a new one, or clone from GitHub.")
                .font(.system(size: CursorTheme.fontSecondary, weight: .regular))
                .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                .lineLimit(2)
        }
    }

    private func tasksTitleContent(workspacePath path: String) -> some View {
        let projectColor = path.isEmpty
            ? CursorTheme.textTertiary(for: colorScheme)
            : CursorTheme.colorForWorkspace(path: path)
        return PanelHeaderView(icon: "checklist", title: "Tasks") {
            HStack(spacing: CursorTheme.spaceXS) {
                Image(systemName: "folder")
                    .font(.system(size: CursorTheme.fontCaption, weight: .medium))
                    .foregroundStyle(projectColor)
                Text((path as NSString).lastPathComponent)
                    .font(.system(size: CursorTheme.fontSecondary, weight: .regular))
                    .foregroundStyle(projectColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func terminalTitleContent(workspacePath path: String) -> some View {
        let projectColor = path.isEmpty
            ? CursorTheme.textTertiary(for: colorScheme)
            : CursorTheme.colorForWorkspace(path: path)
        return PanelHeaderView(icon: "eye", title: "Preview") {
            HStack(spacing: CursorTheme.spaceXS) {
                Image(systemName: "folder")
                    .font(.system(size: CursorTheme.fontCaption, weight: .medium))
                    .foregroundStyle(projectColor)
                Text((path as NSString).lastPathComponent)
                    .font(.system(size: CursorTheme.fontSecondary, weight: .regular))
                    .foregroundStyle(projectColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func agentTitleContent(tab: AgentTab, expandedPromptTabID: Binding<UUID?>) -> some View {
        let status = agentDisplayStatus(for: tab)
        let fullPrompt = (tab.turns.first?.userPrompt ?? tab.prompt).trimmingCharacters(in: .whitespacesAndNewlines)
        let hasExpandablePrompt = !fullPrompt.isEmpty
        let isExpanded = expandedPromptTabID.wrappedValue == tab.id
        let displayTitle = (isExpanded && hasExpandablePrompt) ? userPromptDisplayText(from: fullPrompt) : tab.title
        return HStack(alignment: .top, spacing: CursorTheme.spaceM) {
            agentStatusIcon(tab: tab, status: status)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top, spacing: CursorTheme.spaceXS) {
                    Text(displayTitle)
                        .font(.system(size: CursorTheme.fontTitle, weight: .semibold))
                        .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                        .lineLimit(isExpanded ? nil : 1)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    if hasExpandablePrompt {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if expandedPromptTabID.wrappedValue == tab.id {
                                    expandedPromptTabID.wrappedValue = nil
                                } else {
                                    expandedPromptTabID.wrappedValue = tab.id
                                }
                            }
                        }) {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                                .contentShape(Rectangle())
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .help(isExpanded ? "Hide full prompt" : "Show full prompt")
                    }
                }
                HStack(spacing: CursorTheme.spaceXS) {
                    let projectColor = tab.workspacePath.isEmpty
                        ? CursorTheme.textTertiary(for: colorScheme)
                        : CursorTheme.colorForWorkspace(path: tab.workspacePath)
                    Image(systemName: "folder")
                        .font(.system(size: CursorTheme.fontCaption, weight: .medium))
                        .foregroundStyle(projectColor)
                    Text((tab.workspacePath as NSString).lastPathComponent)
                        .font(.system(size: CursorTheme.fontSecondary, weight: .regular))
                        .foregroundStyle(projectColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private static let sidebarContentPadding: CGFloat = 10
    private static let sidebarHeaderPadding: CGFloat = 16
    private static let sidebarHeaderVerticalPadding: CGFloat = 18

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
                                                    Image(systemName: "folder")
                                                        .font(.system(size: 12, weight: .medium))
                                                        .foregroundStyle(CursorTheme.colorForWorkspace(path: group.path))
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
                                            .frame(width: 16, height: 16, alignment: .center)
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
                                let isDashboardSelected = tabManager.selectedDashboardViewPath == group.path
                                Button {
                                    tabManager.showDashboardView(workspacePath: group.path)
                                    if appState.isMainContentCollapsed {
                                        withAnimation(.easeInOut(duration: 0.2)) { appState.isMainContentCollapsed = false }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "eye")
                                            .font(.system(size: 12))
                                            .foregroundStyle(isDashboardSelected ? CursorTheme.textPrimary(for: colorScheme) : CursorTheme.textSecondary(for: colorScheme))
                                            .frame(width: 16, height: 16, alignment: .center)
                                        Text("Preview")
                                            .font(.system(size: 12, weight: isDashboardSelected ? .semibold : .medium))
                                            .foregroundStyle(isDashboardSelected ? CursorTheme.textPrimary(for: colorScheme) : CursorTheme.textSecondary(for: colorScheme))
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(
                                        isDashboardSelected ? CursorTheme.surfaceRaised(for: colorScheme) : CursorTheme.surfaceMuted(for: colorScheme),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(isDashboardSelected ? CursorTheme.borderStrong(for: colorScheme) : CursorTheme.border(for: colorScheme).opacity(0.6), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .help("Preview: run startup scripts in tabs")
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
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: .infinity)

            ActionButton(
                title: "Projects",
                icon: "gearshape",
                action: addProject,
                help: "Projects",
                style: .primary
            )
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Self.sidebarContentPadding)
        .frame(width: sidebarWidth)
        .clipped()
        .padding(.trailing, 12)
    }

    // MARK: - Projects hub

    private var addProjectHubContent: some View {
        VStack(spacing: 0) {
            projectsPanelTabBar

            if let message = projectHubErrorMessage, !message.isEmpty {
                projectHubBanner(message, tint: CursorTheme.semanticErrorTint, border: CursorTheme.semanticError)
                    .padding(.horizontal, CursorTheme.paddingPanel)
                    .padding(.top, CursorTheme.spaceS)
            }

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: CursorTheme.gapBetweenSections) {
                    switch projectsPanelTab {
                    case .turnOnOff:
                        turnOnOffProjectsSection
                    case .newProject:
                        newProjectSection
                    case .github:
                        githubProjectSection
                    }
                }
                .padding(CursorTheme.paddingPanel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Tab bar for Projects panel (shared PanelTabBarView style: chrome strip + pill).
    private var projectsPanelTabBar: some View {
        PanelTabBarView(
            tabs: ProjectsPanelTab.allCases.map { PanelTabItem(id: $0, label: $0.rawValue, count: nil) },
            selection: $projectsPanelTab,
            onSelect: { projectsPanelTab = $0 }
        )
    }

    private func projectHubBanner(_ message: String, tint: Color, border: Color) -> some View {
        Text(message)
            .font(.system(size: CursorTheme.fontBodySmall, weight: .medium))
            .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(CursorTheme.paddingCard)
            .background(tint, in: RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous)
                    .stroke(border.opacity(0.45), lineWidth: 1)
            )
    }

    /// Inline success toast for "Created X" / "Cloned X" in the Projects hub.
    private func projectHubSuccessToast(_ message: String) -> some View {
        HStack(spacing: CursorTheme.spaceS) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: CursorTheme.fontBodySmall))
                .foregroundStyle(CursorTheme.semanticSuccess)
            Text(message)
                .font(.system(size: CursorTheme.fontCaption, weight: .medium))
                .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
        }
        .padding(.horizontal, CursorTheme.paddingCard)
        .padding(.vertical, CursorTheme.spaceS)
        .background(CursorTheme.semanticSuccess.opacity(0.15), in: Capsule())
    }

    private func projectHubCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: CursorTheme.spaceM) {
            VStack(alignment: .leading, spacing: CursorTheme.spaceXS) {
                Text(title)
                    .font(.system(size: CursorTheme.fontSubtitle, weight: .semibold))
                    .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                Text(subtitle)
                    .font(.system(size: CursorTheme.fontBodySmall))
                    .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            content()
        }
        .padding(CursorTheme.paddingCard)
        .background(CursorTheme.surfaceRaised(for: colorScheme), in: RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous)
                .stroke(CursorTheme.border(for: colorScheme), lineWidth: 1)
        )
    }

    /// "Projects" tab: turn projects on/off, add scan directories, open or browse.
    private var turnOnOffProjectsSection: some View {
        let projects = tabManager.projects.sorted { lhs, rhs in
            if lhs.source != rhs.source {
                return lhs.source == .discovered
            }
            return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }
        return projectHubCard(
            title: "Turn on/off projects",
            subtitle: "Choose which folders to scan, then show or hide projects in the sidebar. Open or browse to add more."
        ) {
            VStack(alignment: .leading, spacing: CursorTheme.spaceM) {
                // Scan directories
                VStack(alignment: .leading, spacing: CursorTheme.spaceXS) {
                    Text("Folders to scan")
                        .font(.system(size: CursorTheme.fontBodySmall, weight: .medium))
                        .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                    scanRootsList
                    ActionButton(
                        title: "Add folder",
                        icon: "folder.badge.plus",
                        action: addProjectScanRoot,
                        help: "Add a folder to scan for projects",
                        style: .secondary
                    )
                }

                Divider()
                    .padding(.vertical, CursorTheme.spaceXS)

                HStack(spacing: CursorTheme.spaceS) {
                    ActionButton(
                        title: "Open Selected",
                        icon: "folder",
                        action: {
                            if let path = selectedExistingProjectPath {
                                openExistingProjectFromHub(path)
                            }
                        },
                        isDisabled: selectedExistingProjectPath == nil,
                        help: "Open the selected project in Tasks",
                        style: .primary
                    )
                    ActionButton(
                        title: "Browse Folder",
                        icon: "folder.badge.plus",
                        action: browseForExistingProject,
                        help: "Choose any folder on your Mac",
                        style: .secondary
                    )
                    Spacer(minLength: 0)
                }

                if projects.isEmpty {
                    Text("No projects discovered yet. Add folders to scan or browse to a folder.")
                        .font(.system(size: CursorTheme.fontBodySmall))
                        .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                } else {
                    VStack(alignment: .leading, spacing: CursorTheme.spaceS) {
                        ForEach(projects, id: \.path) { project in
                            let isSelected = selectedExistingProjectPath == project.path
                            let normalized = AppPreferences.normalizedProjectPath(project.path)
                            let isVisible = !AppPreferences.hiddenProjectPaths(from: hiddenProjectPathsRaw).contains(normalized)
                            HStack(alignment: .center, spacing: CursorTheme.spaceM) {
                                Button {
                                    selectedExistingProjectPath = project.path
                                } label: {
                                    HStack(alignment: .center, spacing: CursorTheme.spaceM) {
                                        Image(systemName: project.source == .discovered ? "sparkles" : "folder")
                                            .font(.system(size: CursorTheme.fontBody, weight: .medium))
                                            .foregroundStyle(CursorTheme.colorForWorkspace(path: project.path))
                                            .frame(width: 18, height: 18)
                                        Text(appState.workspaceDisplayName(for: project.path))
                                            .font(.system(size: CursorTheme.fontBody, weight: .semibold))
                                            .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                                            .lineLimit(1)
                                        Spacer(minLength: 0)
                                    }
                                }
                                .buttonStyle(.plain)
                                Toggle("", isOn: Binding(
                                    get: { isVisible },
                                    set: { visible in
                                        var hidden = AppPreferences.hiddenProjectPaths(from: hiddenProjectPathsRaw)
                                        if visible {
                                            hidden.remove(normalized)
                                        } else {
                                            hidden.insert(normalized)
                                        }
                                        hiddenProjectPathsRaw = AppPreferences.rawFrom(hiddenPaths: hidden)
                                    }
                                ))
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .labelsHidden()
                                .help("Show in sidebar")
                            }
                            .padding(CursorTheme.paddingCard)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                isSelected ? CursorTheme.surfaceMuted(for: colorScheme) : CursorTheme.editor(for: colorScheme),
                                in: RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous)
                                    .stroke(isSelected ? CursorTheme.borderStrong(for: colorScheme) : CursorTheme.border(for: colorScheme), lineWidth: 1)
                            )
                        }
                    }
                }
            }
        }
    }

    private var scanRootsList: some View {
        let roots = projectScanRoots
        if roots.isEmpty {
            return AnyView(
                Text("No folders added. Use “Add folder” or set Projects root in Settings.")
                    .font(.system(size: CursorTheme.fontBodySmall))
                    .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
            )
        }
        return AnyView(
            VStack(alignment: .leading, spacing: CursorTheme.spaceXS) {
                ForEach(roots, id: \.self) { path in
                    HStack(spacing: CursorTheme.spaceS) {
                        Text(path)
                            .font(.system(size: CursorTheme.fontSecondary))
                            .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        Button {
                            removeProjectScanRoot(path)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Remove folder from scan")
                    }
                    .padding(.horizontal, CursorTheme.spaceS)
                    .padding(.vertical, CursorTheme.spaceXS)
                    .background(CursorTheme.surfaceMuted(for: colorScheme), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
        )
    }

    private func addProjectScanRoot() {
        let startPath = projectScanRoots.first ?? (projectsRootPath as NSString).expandingTildeInPath
        if let path = selectFolder(
            title: "Add folder to scan",
            message: "Choose a folder. Its subfolders will be scanned for Metro projects.",
            startingAt: startPath
        ) {
            var roots = projectScanRoots
            let normalized = (path as NSString).standardizingPath
            if !roots.contains(normalized) {
                roots.append(normalized)
                projectScanRootsRaw = AppPreferences.rawFrom(projectScanRoots: roots)
            }
        }
    }

    private func removeProjectScanRoot(_ path: String) {
        var roots = projectScanRoots
        roots.removeAll { ($0 as NSString).standardizingPath == (path as NSString).standardizingPath }
        projectScanRootsRaw = roots.isEmpty ? "" : AppPreferences.rawFrom(projectScanRoots: roots)
    }

    private var newProjectSection: some View {
        projectHubCard(
            title: "Create New Project",
            subtitle: "Create an empty workspace or let the agent scaffold the first version from your idea."
        ) {
            VStack(alignment: .leading, spacing: CursorTheme.spaceM) {
                if let message = projectHubStatusMessage, message.hasPrefix("Created") {
                    projectHubSuccessToast(message)
                }
                VStack(alignment: .leading, spacing: CursorTheme.spaceXS) {
                    Text("Project name")
                        .font(.system(size: CursorTheme.fontBodySmall, weight: .medium))
                        .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                    TextField("my-app", text: Binding(
                        get: { newProjectName },
                        set: { newProjectName = sanitizedProjectName($0) }
                    ))
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: CursorTheme.spaceXS) {
                    Text("Destination")
                        .font(.system(size: CursorTheme.fontBodySmall, weight: .medium))
                        .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                    HStack(spacing: CursorTheme.spaceS) {
                        TextField("~/dev", text: $newProjectParentPath)
                            .textFieldStyle(.roundedBorder)
                        ActionButton(
                            title: "Browse",
                            icon: "folder",
                            action: {
                                if let path = selectFolder(
                                    title: "Choose New Project Destination",
                                    message: "Choose where the new project folder should be created.",
                                    startingAt: newProjectParentPath
                                ) {
                                    newProjectParentPath = path
                                }
                            },
                            style: .secondary
                        )
                    }
                }

                VStack(alignment: .leading, spacing: CursorTheme.spaceXS) {
                    Text("What should it be?")
                        .font(.system(size: CursorTheme.fontBodySmall, weight: .medium))
                        .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                    TextField("Example: a small Next.js app for tracking invoices", text: $newProjectIdea, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                }

                HStack(spacing: CursorTheme.spaceS) {
                    ActionButton(
                        title: "Create Empty",
                        icon: "plus.square",
                        action: createEmptyProjectFromHub,
                        isDisabled: sanitizedProjectName(newProjectName).isEmpty,
                        help: "Create the folder and open it in Tasks",
                        style: .primary
                    )
                    ActionButton(
                        title: "Create With Agent",
                        icon: "wand.and.stars",
                        action: createProjectWithAgentFromHub,
                        isDisabled: sanitizedProjectName(newProjectName).isEmpty,
                        help: "Create the folder and ask the agent to scaffold the project",
                        style: .accent
                    )
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var githubProjectSection: some View {
        projectHubCard(
            title: "Clone From GitHub",
            subtitle: "Clone a repository into one of your working directories, then open it directly in Cursor Metro."
        ) {
            VStack(alignment: .leading, spacing: CursorTheme.spaceM) {
                if let message = projectHubStatusMessage, message.hasPrefix("Cloned") {
                    projectHubSuccessToast(message)
                }
                VStack(alignment: .leading, spacing: CursorTheme.spaceXS) {
                    Text("Repository URL")
                        .font(.system(size: CursorTheme.fontBodySmall, weight: .medium))
                        .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                    TextField("https://github.com/owner/repo", text: $gitRepositoryURL)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: CursorTheme.spaceXS) {
                    Text("Clone into")
                        .font(.system(size: CursorTheme.fontBodySmall, weight: .medium))
                        .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                    HStack(spacing: CursorTheme.spaceS) {
                        TextField("~/dev", text: $gitCloneParentPath)
                            .textFieldStyle(.roundedBorder)
                        ActionButton(
                            title: "Browse",
                            icon: "folder",
                            action: {
                                if let path = selectFolder(
                                    title: "Choose Clone Destination",
                                    message: "Choose the parent directory where the repository should be cloned.",
                                    startingAt: gitCloneParentPath
                                ) {
                                    gitCloneParentPath = path
                                }
                            },
                            style: .secondary
                        )
                    }
                }

                VStack(alignment: .leading, spacing: CursorTheme.spaceXS) {
                    Text("Folder name override")
                        .font(.system(size: CursorTheme.fontBodySmall, weight: .medium))
                        .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                    TextField("Optional", text: $gitCloneFolderName)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: CursorTheme.spaceS) {
                    ActionButton(
                        title: isProjectHubBusy ? "Cloning..." : "Clone Project",
                        icon: "arrow.down.doc",
                        action: { cloneProjectFromHub(runSetupAgent: false) },
                        isDisabled: isProjectHubBusy || gitRepositoryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        help: "Clone the repository and open it in Tasks",
                        style: .primary
                    )
                    ActionButton(
                        title: isProjectHubBusy ? "Cloning..." : "Clone + Setup",
                        icon: "wand.and.stars",
                        action: { cloneProjectFromHub(runSetupAgent: true) },
                        isDisabled: isProjectHubBusy || gitRepositoryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        help: "Clone the repository and launch the setup agent",
                        style: .accent
                    )
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func projectHubTag(_ title: String) -> some View {
        Text(title)
            .font(.system(size: CursorTheme.fontCaption, weight: .medium))
            .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
            .padding(.horizontal, CursorTheme.paddingBadgeHorizontal)
            .padding(.vertical, CursorTheme.paddingBadgeVertical)
            .background(CursorTheme.surfaceMuted(for: colorScheme), in: Capsule())
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

                ActionButton(
                    title: "Projects",
                    icon: "gearshape",
                    action: addProject,
                    help: "Projects",
                    style: .primary
                )
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
            if let task = projectTasksStore.task(for: tab.workspacePath, id: taskID), task.taskState == .completed {
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

    @ViewBuilder
    private func agentStatusIcon(tab: AgentTab, status: (label: String, isProcessing: Bool, isPendingReview: Bool, isStopped: Bool, isCompleted: Bool)) -> some View {
        if status.isProcessing {
            LightBlueSpinner(size: CursorTheme.fontIconList - 4)
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
        return VStack(spacing: 0) {
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
        let modelLabel = appState.model(
            for: effectiveModelForTab(tab),
            providerID: tab.providerID
        )?.label ?? "Auto"
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
        let visibleTurns = displayedTurns(for: tab)
        let hiddenTurnTotal = hiddenTurnCount(for: tab)
        return OutputScrollView(
            tab: tab,
            scrollToken: tab.scrollToken
        ) {
            // Keep the stack eager for reliable append/layout behavior, but mount only the most
            // recent slice by default so long conversations do not keep every markdown view alive.
            VStack(alignment: .leading, spacing: 18) {
                if tab.turns.isEmpty {
                    emptyStateContent(tab: tab)
                } else {
                    conversationWindowBar(
                        tab: tab,
                        hiddenTurnCount: hiddenTurnTotal,
                        visibleTurnCount: visibleTurns.count
                    )

                    ForEach(visibleTurns) { turn in
                        ConversationTurnView(
                            turn: turn,
                            workspacePath: tab.workspacePath,
                            onPreviewScreenshots: { paths, selectedPath in
                                showScreenshotPreview(paths: paths, selectedPath: selectedPath, workspacePath: tab.workspacePath)
                            }
                        )
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
    }

    // MARK: - Composer dock

    private func composerDock(tab: AgentTab) -> some View {
        let attachedPaths = screenshotPaths(from: tab.prompt)
        let displayPrompt = userPromptDisplayText(from: tab.prompt)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                QuickActionButtonsView(
                    commands: quickActionCommands,
                    isDisabled: tab.isRunning,
                    onCommand: { cmd in
                        if cmd.title == QuickActionCommand.defaultFixBuild.title {
                            _ = addNewAgentTab(initialPrompt: cmd.prompt, lastWorkspacePath: tab.workspacePath, select: true)
                        } else {
                            sendInCurrentTab(prompt: cmd.prompt, tab: tab)
                        }
                    }
                )
                Spacer()
                ComposerActionButtonsView(
                    showPinnedQuestionsPanel: $showPinnedQuestionsPanel,
                    hasContext: !tab.turns.isEmpty || !tab.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    isRunning: tab.isRunning
                )
            }

            VStack(alignment: .leading, spacing: 0) {
                if !attachedPaths.isEmpty {
                    HStack(alignment: .center, spacing: 6) {
                        ForEach(attachedPaths, id: \.self) { path in
                            ScreenshotThumbnailView(
                                imageURL: screenshotFileURL(path: path, workspacePath: tab.workspacePath),
                                size: CGSize(width: 56, height: 56),
                                cornerRadius: 6,
                                onTapPreview: {
                                    showScreenshotPreview(paths: attachedPaths, selectedPath: path, workspacePath: tab.workspacePath)
                                },
                                onDelete: { deleteScreenshot(path: path, tab: tab) }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    Rectangle()
                        .fill(CursorTheme.border(for: colorScheme))
                        .frame(height: 1)
                        .padding(.horizontal, 12)
                }

                if tab.isRunning && !tab.followUpQueue.isEmpty {
                    queuedSectionContent(tab: tab)
                    Rectangle()
                        .fill(CursorTheme.border(for: colorScheme))
                        .frame(height: 1)
                        .padding(.horizontal, 12)
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

                        if displayPrompt.isEmpty && attachedPaths.isEmpty {
                            Text(placeholderText(whenRunning: tab.isRunning))
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
            }
            .background(CursorTheme.editor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(CursorTheme.border(for: colorScheme), lineWidth: 1)
            )

            HStack(alignment: .center, spacing: 8) {
                ModelPickerView(
                    selectedModelId: effectiveModelForTab(tab),
                    models: modelPickerModels(
                        for: tab.providerID,
                        including: effectiveModelForTab(tab)
                    ),
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
                                tab.errorMessage = nil
                                refreshGitState(for: tab.workspacePath, force: true)
                            }
                        }
                    },
                    onOpenMenu: {
                        refreshGitState(for: tab.workspacePath, force: true)
                    },
                    onCreateBranch: { name in
                        if let err = gitCreateBranch(name: name, workspacePath: tab.workspacePath) {
                            return err
                        }
                        tab.errorMessage = nil
                        refreshGitState(for: tab.workspacePath, force: true)
                        return nil
                    }
                )
                .onChange(of: tab.workspacePath) { _, _ in
                    refreshGitState(for: tab.workspacePath)
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

    @ViewBuilder
    private func sendStopButton(tab: AgentTab) -> some View {
        if tab.isRunning {
            Button(action: { stopStreaming(for: tab) }) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(CursorTheme.semanticError))
                    .overlay(
                        Circle()
                            .stroke(CursorTheme.semanticError.opacity(0.5), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("Stop the agent")
        } else {
            Button(action: { submitOrQueuePrompt(tab: tab) }) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(CursorTheme.brandGradient))
                    .overlay(
                        Circle()
                            .stroke(CursorTheme.textPrimary(for: colorScheme).opacity(0.14), lineWidth: 1)
                    )
                    .opacity(canSend(tab: tab) ? 1 : 0.45)
            }
            .buttonStyle(.plain)
            .disabled(!canSend(tab: tab))
        }
    }

    private var composerHeight: CGFloat {
        min(132, max(56, composerTextHeight + 16))
    }

    // MARK: - Helpers

    private func sanitizeSelectedModel() {
        let providerID = appState.selectedAgentProviderID
        guard appState.model(for: selectedModel, providerID: providerID) == nil else { return }
        selectedModel = appState.defaultModelID(for: providerID)
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

    private func canSend(tab: AgentTab) -> Bool {
        !tab.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func placeholderText(whenRunning isRunning: Bool) -> String {
        if isRunning {
            return CursorTheme.composerPlaceholderWhenRunning
        }
        return CursorTheme.composerPlaceholderHint
    }

    private func queuedCountLabel(_ count: Int) -> String {
        count == 1 ? "1 message queued" : "\(count) messages queued"
    }

    private func queuedSectionHeaderLabel(_ count: Int) -> String {
        count == 1 ? "1 Queued" : "\(count) Queued"
    }

    @ViewBuilder
    private func queuedSectionContent(tab: AgentTab) -> some View {
        VStack(alignment: .leading, spacing: CursorTheme.spaceS) {
            Text(queuedSectionHeaderLabel(tab.followUpQueue.count))
                .font(.system(size: CursorTheme.fontSecondary, weight: .medium))
                .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))

            ForEach(Array(tab.followUpQueue.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .center, spacing: CursorTheme.spaceS) {
                    Text(userPromptDisplayText(from: item.text))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .font(.system(size: CursorTheme.fontBodySmall, weight: .regular, design: .monospaced))
                        .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button(action: { removeQueuedFollowUp(tab: tab, at: index) }) {
                        Image(systemName: "trash")
                            .font(.system(size: CursorTheme.fontIconList))
                            .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                    }
                    .buttonStyle(.plain)
                    .help("Remove from queue")
                }
                .padding(.horizontal, CursorTheme.spaceM)
                .padding(.vertical, CursorTheme.spaceS)
                .background(CursorTheme.surfaceMuted(for: colorScheme), in: RoundedRectangle(cornerRadius: CursorTheme.spaceXS, style: .continuous))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    /// Remove a queued follow-up at the given index.
    private func removeQueuedFollowUp(tab: AgentTab, at index: Int) {
        guard index >= 0, index < tab.followUpQueue.count else { return }
        tab.followUpQueue.remove(at: index)
    }

    /// Submit the current prompt: send immediately if idle, or queue to send when agent finishes if running.
    private func submitOrQueuePrompt(tab: AgentTab) {
        agentSessionStore.submitOrQueuePrompt(
            tab: tab,
            selectedModel: effectiveModelForTab(tab),
            incrementUsage: { messagesSentForUsage += 1 },
            recordHangEvent: recordHangEvent(_:metadata:),
            updateTabTitle: updateTabTitle(for:in:),
            requestAutoScroll: requestAutoScroll(for:force:)
        )
    }

    /// Queue the current prompt to be sent as soon as the agent finishes its current response.
    private func queueFollowUp(tab: AgentTab) {
        let trimmed = tab.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tab.followUpQueue.append(QueuedFollowUp(text: tab.prompt))
        tab.prompt = ""
        tab.hasAttachedScreenshot = false
    }

    /// Process the next queued follow-up: set prompt and send. Called from finishStreaming when queue is non-empty.
    private func processNextQueuedFollowUp(tab: AgentTab) {
        agentSessionStore.submitOrQueuePrompt(
            tab: tab,
            selectedModel: effectiveModelForTab(tab),
            incrementUsage: { messagesSentForUsage += 1 },
            recordHangEvent: recordHangEvent(_:metadata:),
            updateTabTitle: updateTabTitle(for:in:),
            requestAutoScroll: requestAutoScroll(for:force:)
        )
    }

    private static let compressPrompt = "Summarize our entire conversation so far into a single concise summary that preserves key context, decisions, and next steps. Reply with only that summary, no other text."

    /// Compress context: ask the agent to summarize the conversation, then replace context with that summary (new chat). If no context, clears instead.
    private func compressContext(tab: AgentTab) {
        agentSessionStore.compressContext(
            tab: tab,
            selectedModel: effectiveModelForTab(tab),
            incrementUsage: { messagesSentForUsage += 1 },
            recordHangEvent: recordHangEvent(_:metadata:),
            updateTabTitle: updateTabTitle(for:in:),
            requestAutoScroll: requestAutoScroll(for:force:)
        )
    }

    private func clearContext(tab: AgentTab) {
        agentSessionStore.clearContext(tab: tab)
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
        agentSessionStore.sendInCurrentTab(
            prompt: prompt,
            tab: tab,
            selectedModel: effectiveModelForTab(tab),
            incrementUsage: { messagesSentForUsage += 1 },
            recordHangEvent: recordHangEvent(_:metadata:),
            updateTabTitle: updateTabTitle(for:in:),
            requestAutoScroll: requestAutoScroll(for:force:)
        )
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

    // MARK: - Streaming

    private func sendPrompt(tab currentTab: AgentTab) {
        agentSessionStore.sendPrompt(
            tab: currentTab,
            selectedModel: effectiveModelForTab(currentTab),
            incrementUsage: { messagesSentForUsage += 1 },
            recordHangEvent: recordHangEvent(_:metadata:),
            updateTabTitle: updateTabTitle(for:in:),
            requestAutoScroll: requestAutoScroll(for:force:)
        )
    }

    private func stopStreaming(for currentTab: AgentTab? = nil) {
        guard let tabToStop = currentTab ?? tab else { return }
        agentSessionStore.stopStreaming(
            for: tabToStop,
            recordHangEvent: recordHangEvent(_:metadata:),
            requestAutoScroll: requestAutoScroll(for:force:)
        )
    }

    private func finishStreaming(for currentTab: AgentTab, runID: UUID, turnID: UUID, errorMessage: String? = nil) {
        guard currentTab.activeRunID == runID else { return }
        recordHangEvent("finish-streaming", metadata: [
            "tabID": currentTab.id.uuidString,
            "workspacePath": currentTab.workspacePath,
            "linkedTaskID": currentTab.linkedTaskID?.uuidString ?? "nil",
            "hadError": errorMessage == nil ? "false" : "true"
        ])
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
        if !currentTab.followUpQueue.isEmpty {
            processNextQueuedFollowUp(tab: currentTab)
        }
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
        if Thread.isMainThread {
            tab.objectWillChange.send()
        } else {
            DispatchQueue.main.async {
                tab.objectWillChange.send()
            }
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
