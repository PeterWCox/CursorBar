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

9) **Metro Preview terminals:** The in-app Preview panel runs each entry in `.metro/project.json` `scripts` (with matching `scriptLabels`) as its own terminal tab, and uses `debugUrl` for “Open in Browser.” Completing this configuration is mandatory whenever you set up or regenerate project config—do not skip Preview so the user can run dev servers from Metro.
"""

/// Builds the setup agent prompt, optionally appending git-commit instructions and user context (create/clone flows).
private func makeProjectSetupPrompt(includeInitialGitCommit: Bool = false, userSupplement: String = "") -> String {
    var parts: [String] = [projectSetupAgentPrompt.trimmingCharacters(in: .whitespacesAndNewlines)]
    let extra = userSupplement.trimmingCharacters(in: .whitespacesAndNewlines)
    if !extra.isEmpty {
        parts.append("\n\n— User context —\n\(extra)")
    }
    if includeInitialGitCommit {
        parts.append("""

— Git (requested) —
If the workspace is not a git repository yet, run `git init`. After your setup changes, if there are uncommitted files, stage them and create an initial commit with a clear message (e.g. "Initial project setup"). If the repo already has meaningful history and the tree is clean, you may skip committing.
""")
    }
    return parts.joined()
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

/// One navigable sidebar row, in the same order as `tabSidebar` (Tasks → Preview → visible agent tabs, per project).
private enum SidebarCycleDestination: Equatable {
    case tasks(path: String)
    case preview(path: String)
    case agentTab(id: UUID)
}

private struct GitBranchSnapshot: Equatable {
    let current: String
    let branches: [String]
}

private enum CreateProjectWorkflowMode: String, CaseIterable, Identifiable {
    case newWithAgent
    case cloneFromGitHub

    var id: String { rawValue }
}

private enum CreateProjectInspirationType: String, CaseIterable, Identifiable {
    case webApp
    case game
    case stack
    case api
    case mobileApp
    case cli

    var id: String { rawValue }

    var title: String {
        switch self {
        case .webApp: return "Web App"
        case .game: return "Game"
        case .stack: return "Stack"
        case .api: return "API"
        case .mobileApp: return "Mobile App"
        case .cli: return "CLI"
        }
    }

    var icon: String {
        switch self {
        case .webApp: return "globe"
        case .game: return "gamecontroller"
        case .stack: return "square.3.layers.3d"
        case .api: return "server.rack"
        case .mobileApp: return "iphone"
        case .cli: return "terminal"
        }
    }

    var promptLabel: String {
        switch self {
        case .webApp: return "web app"
        case .game: return "game"
        case .stack: return "full-stack app"
        case .api: return "developer-friendly API"
        case .mobileApp: return "mobile app"
        case .cli: return "CLI tool"
        }
    }

    var fallbackFolderName: String {
        switch self {
        case .webApp: return "web-app"
        case .game: return "game-project"
        case .stack: return "full-stack-app"
        case .api: return "api-service"
        case .mobileApp: return "mobile-app"
        case .cli: return "cli-tool"
        }
    }

    var placeholderIdea: String {
        switch self {
        case .webApp:
            return "A small Next.js app for invoices"
        case .game:
            return "A cozy browser puzzle game with daily challenges"
        case .stack:
            return "A full-stack app for managing local events"
        case .api:
            return "An API for a recipe app with auth and search"
        case .mobileApp:
            return "A habit tracker app with streaks and reminders"
        case .cli:
            return "A CLI to summarize git activity across repos"
        }
    }

    var surpriseIdeas: [String] {
        switch self {
        case .webApp:
            return [
                "A lightweight kanban board for projects",
                "A notes app with markdown and search",
                "A dashboard for tracking freelance invoices",
                "A local-first recipe organizer with smart filters",
                "A simple booking page for a neighborhood studio"
            ]
        case .game:
            return [
                "A cozy word puzzle game with daily challenges",
                "A memory card game with unlockable themes",
                "A top-down dungeon crawler with simple upgrades",
                "A browser tower defense game with short rounds",
                "A pixel-art trivia game with score streaks"
            ]
        case .stack:
            return [
                "A full-stack habit tracker with streaks and shared teams",
                "A marketplace for digital products with seller dashboards",
                "A CRM for small agencies with notes and follow-ups",
                "A project portal with an API, admin panel, and worker jobs",
                "A meal planner with auth, syncing, and shopping lists"
            ]
        case .api:
            return [
                "An API for a note-taking app with auth and search",
                "A webhook relay service with retries and logs",
                "A backend for habit tracking with streak analytics",
                "An inventory API with roles, audit history, and exports",
                "A subscriptions API with billing-ready data models"
            ]
        case .mobileApp:
            return [
                "A mobile habit tracker with reminders and streaks",
                "A running log with maps, splits, and weekly goals",
                "A focus timer app with sessions and reflections",
                "A travel checklist app with offline packing lists",
                "A shared grocery list app with quick add widgets"
            ]
        case .cli:
            return [
                "A CLI to scaffold release notes from merged PRs",
                "A terminal tool to inspect local ports and processes",
                "A repo health CLI for stale branches and TODOs",
                "A developer CLI to bootstrap feature folders and tests",
                "A command-line dashboard for personal finance CSVs"
            ]
        }
    }
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
            HStack(spacing: CursorTheme.spaceS) {
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
            .padding(.horizontal, CursorTheme.paddingSidebarRowHorizontal)
            .padding(.vertical, CursorTheme.paddingSidebarRowVertical)
            .background(
                isSelected
                    ? CursorTheme.surfaceRaised(for: colorScheme)
                    : CursorTheme.surfaceMuted(for: colorScheme).opacity(0.58),
                in: RoundedRectangle(cornerRadius: CursorTheme.radiusSidebarRow, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CursorTheme.radiusSidebarRow, style: .continuous)
                    .stroke(
                        isSelected ? CursorTheme.borderStrong(for: colorScheme) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

/// Shared sidebar page chip used by project-level pages (Tasks, Preview).
private struct SidebarPageChip: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let icon: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: CursorTheme.spaceS) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? CursorTheme.textPrimary(for: colorScheme) : CursorTheme.textSecondary(for: colorScheme))
                    .frame(width: 16, height: 16, alignment: .center)
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? CursorTheme.textPrimary(for: colorScheme) : CursorTheme.textSecondary(for: colorScheme))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, CursorTheme.paddingSidebarRowHorizontal)
            .padding(.vertical, CursorTheme.paddingSidebarRowVertical)
            .background(
                isSelected
                    ? CursorTheme.surfaceRaised(for: colorScheme)
                    : CursorTheme.surfaceMuted(for: colorScheme).opacity(0.58),
                in: RoundedRectangle(cornerRadius: CursorTheme.radiusSidebarRow, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CursorTheme.radiusSidebarRow, style: .continuous)
                    .stroke(
                        isSelected ? CursorTheme.borderStrong(for: colorScheme) : Color.clear,
                        lineWidth: 1
                    )
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
    var workspaceDisplayName: String?
    @Binding var triggerAddNewTask: Bool
    let linkedStatuses: [UUID: AgentTaskState]
    let userFollowUpsByTaskID: [UUID: [String]]
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
            workspaceDisplayName: workspaceDisplayName,
            triggerAddNewTask: $triggerAddNewTask,
            linkedStatuses: linkedStatuses,
            userFollowUpsByTaskID: userFollowUpsByTaskID,
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
            embeddedInMainWindow: true,
            onLaunchSetupAgent: onLaunchSetupAgent
        )
        .id(tasksPath)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    @AppStorage(AppPreferences.createProjectPreferredTypeKey) private var createProjectPreferredTypeRaw: String = AppPreferences.defaultCreateProjectPreferredTypeRaw
    @AppStorage(AppPreferences.createProjectTypeUsageKey) private var createProjectTypeUsageRaw: String = AppPreferences.defaultCreateProjectTypeUsageRaw
    @AppStorage("selectedModel") private var selectedModel: String = AvailableModels.autoID
    @AppStorage("messagesSentForUsage") private var messagesSentForUsage: Int = 0
    @AppStorage("showPinnedQuestionsPanel") private var showPinnedQuestionsPanel: Bool = true
    @AppStorage(AppPreferences.sidebarOnRightKey) private var isSidebarOnRight: Bool = false
    @AppStorage(AppPreferences.sidebarWidthKey) private var sidebarWidthStored: Double = AppPreferences.defaultSidebarWidth
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
    /// When true, Cmd+T in Tasks view should add a new task; set by window-level shortcut and observed by TasksListView.
    @State private var tasksViewTriggerAddNew: Bool = false
    @StateObject private var tasksViewShortcutCoordinator = TasksViewShortcutCoordinator()
    @StateObject private var agentSessionStore = AgentSessionStore()
    /// Tab whose agent header shows the full user prompt (double-click title to toggle).
    @State private var expandedPromptTabID: UUID? = nil
    /// How many of the most recent turns are mounted for each tab. `Int.max` means full history.
    @State private var visibleTurnLimitsByTabID: [UUID: Int] = [:]
    @State private var showCreateProjectPage = false
    @State private var createProjectMode: CreateProjectWorkflowMode = .newWithAgent
    @State private var createProjectGitURL = ""
    @State private var createProjectParentPath = ""
    @State private var createProjectFolderName = ""
    @State private var createProjectFolderNameEditedByUser = false
    @State private var createProjectIdea = ""
    @State private var createProjectModelId: String = AppPreferences.defaultModelId
    @State private var createProjectSelectedTypeRaw = ""
    @State private var createProjectInitialGitCommit = false
    @State private var createProjectBusy = false
    @State private var createProjectError: String?
    @State private var addProjectError: String?
    /// Baseline sidebar width when a drag begins (so translation stacks correctly).
    @State private var sidebarDragStartWidth: CGFloat?
    /// When true, hide main agent content and show only title bar + tab sidebar (uses AppState so panel can resize).
    private var isMainContentCollapsed: Bool { appState.isMainContentCollapsed }

    private var sidebarWidth: CGFloat { CGFloat(sidebarWidthStored) }
    private var collapsedSidebarContentWidth: CGFloat { max(sidebarWidth, 320) }
    private var collapsedSidebarWindowWidth: CGFloat {
        collapsedSidebarContentWidth + (CursorTheme.paddingSidebarCollapsedOuter * 2)
    }
    private var minimumExpandedWindowWidth: CGFloat {
        max(sidebarWidth, SidebarSplitMetrics.minSidebar)
            + SidebarSplitMetrics.dragHandleWidth
            + SidebarSplitMetrics.minMainColumn
            + CursorTheme.paddingChrome
    }

    private enum SidebarSplitMetrics {
        static let minSidebar: CGFloat = 300
        static let minMainColumn: CGFloat = 420
        static let dragHandleWidth: CGFloat = 11
    }

    /// Keeps the project sidebar within bounds so the main agent column stays usable.
    private func clampedSidebarWidth(totalWidth: CGFloat) -> CGFloat {
        let minS = SidebarSplitMetrics.minSidebar
        let minMain = SidebarSplitMetrics.minMainColumn
        guard totalWidth > 1 else { return minS }
        let maxSidebar = max(minS, totalWidth - minMain - 1)
        return min(max(sidebarWidth, minS), maxSidebar)
    }

    /// Writes the clamped width to storage when the window is too narrow for the saved value (e.g. after resize).
    private func syncSidebarWidthToClamped(totalWidth: CGFloat) {
        let clamped = clampedSidebarWidth(totalWidth: totalWidth)
        if abs(clamped - sidebarWidth) > 0.5 {
            sidebarWidthStored = Double(clamped)
        }
    }

    private static let defaultVisibleTurnLimit = 20
    private static let visibleTurnPageSize = 30
    /// Collapsed agent header: wrap up to this many lines, then tail ellipsis (`...`).
    private static let agentHeaderPromptCollapsedLineLimit = 3

    /// Active tab when there is at least one; otherwise nil (splash state).
    private var tab: AgentTab? { tabManager.activeTab }

    private var selectedProjectPath: String? {
        tabManager.activeProjectPath
    }

    private var hasOpenProjects: Bool {
        tabManager.openProjectCount > 0
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

    /// Move linked task between columns; same rules as the Tasks list row (including disabled while processing).
    @ViewBuilder
    private func agentTabLinkedTaskMoveMenu(for tab: AgentTab) -> some View {
        if let taskID = tab.linkedTaskID,
           let task = projectTasksStore.task(for: tab.workspacePath, id: taskID) {
            let agentState = linkedTaskState(for: tab) ?? .none
            let isProcessing = agentState == .processing
            let canMoveToBacklog = task.taskState == .inProgress && (agentState == .none || agentState == .todo)
            Menu("Move to…", systemImage: "arrow.right.square") {
                if canMoveToBacklog {
                    Button("Backlog", systemImage: "tray.full") {
                        projectTasksStore.updateTask(workspacePath: tab.workspacePath, id: taskID, taskState: .backlog)
                    }
                }
                if task.taskState == .backlog || task.taskState == .completed {
                    Button("In Progress", systemImage: "arrow.right.circle") {
                        projectTasksStore.updateTask(workspacePath: tab.workspacePath, id: taskID, taskState: .inProgress)
                    }
                }
                if task.taskState != .completed {
                    Button("Completed", systemImage: "checkmark.circle") {
                        projectTasksStore.updateTask(workspacePath: tab.workspacePath, id: taskID, taskState: .completed)
                    }
                }
                if task.taskState != .deleted {
                    Button("Deleted", systemImage: "trash", role: .destructive) {
                        projectTasksStore.updateTask(workspacePath: tab.workspacePath, id: taskID, taskState: .deleted)
                    }
                }
            }
            .disabled(isProcessing)
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

    /// User prompts after the first message in the linked agent conversation (open tabs override recently closed).
    private func userFollowUpsForWorkspace(_ workspacePath: String) -> [UUID: [String]] {
        var result: [UUID: [String]] = [:]
        for savedTab in tabManager.recentlyClosedTabs where savedTab.workspacePath == workspacePath {
            guard let taskID = savedTab.linkedTaskID else { continue }
            result[taskID] = savedTab.restoredTurns.userFollowUpPrompts
        }
        for tab in tabManager.tabs where tab.workspacePath == workspacePath {
            guard let taskID = tab.linkedTaskID else { continue }
            result[taskID] = tab.turns.userFollowUpPrompts
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
        let userFollowUpsByTaskID = userFollowUpsForWorkspace(tasksPath)
        let displayName = appState.workspaceDisplayName(for: tasksPath)
        return PopoutTasksListContent(
            tasksPath: tasksPath,
            workspaceDisplayName: displayName.isEmpty ? nil : displayName,
            triggerAddNewTask: triggerAddNewTask,
            linkedStatuses: linkedStatuses,
            userFollowUpsByTaskID: userFollowUpsByTaskID,
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
                _ = addNewAgentTab(initialPrompt: makeProjectSetupPrompt(), lastWorkspacePath: path)
            },
            showHeader: false
        )
    }

    /// Opens Preview and starts configured startup scripts immediately when needed.
    private func openDashboard(workspacePath path: String) {
        let root = projectRootForTerminal(workspacePath: path)
        let scripts = ProjectSettingsStorage.getStartupScripts(workspacePath: root)
        let hasRunningPreviewTabs = !tabManager.dashboardTabs(for: path).isEmpty
        if !scripts.isEmpty, !hasRunningPreviewTabs {
            let labels = ProjectSettingsStorage.getStartupScriptDisplayLabels(workspacePath: root)
            _ = tabManager.addDashboardTabs(workspacePath: path, scripts: scripts, labels: labels)
        } else {
            tabManager.showDashboardView(workspacePath: path)
        }
        if appState.isMainContentCollapsed {
            withAnimation(.easeInOut(duration: 0.2)) { appState.isMainContentCollapsed = false }
        }
    }

    private func stopDashboard(workspacePath path: String) {
        tabManager.closeDashboardTabs(workspacePath: path)
        tabManager.showTasksView(workspacePath: path)
    }

    /// Removes a project (all tabs for that workspace path) from the sidebar. Stops any running agents first.
    private func removeProject(workspacePath path: String) {
        for t in tabManager.tabs where t.workspacePath == path {
            stopStreaming(for: t)
        }
        tabManager.removeProject(path)
    }

    private func addProject() {
        showCreateProjectPage = false
        addProjectError = nil
        guard let path = selectFolder(
            title: "Add project",
            message: "Choose a folder to open as a project.",
            startingAt: preferredProjectBrowserRoot
        ) else { return }
        let normalized = (path as NSString).standardizingPath
        guard tabManager.addProject(path: normalized, select: true) else {
            addProjectError = "Could not open that folder. Check that it exists and you have access."
            return
        }
        updateProjectContext(to: normalized)
        if appState.isMainContentCollapsed {
            withAnimation(.easeInOut(duration: 0.2)) { appState.isMainContentCollapsed = false }
        }
    }

    private func prepareCreateProjectForm() {
        createProjectError = nil
        if createProjectParentPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            createProjectParentPath = preferredProjectBrowserRoot
        }
        if appState.model(for: createProjectModelId, providerID: .cursor) == nil {
            createProjectModelId = appState.defaultModelID(for: .cursor)
        }
        if createProjectSelectedTypeRaw.isEmpty {
            createProjectSelectedTypeRaw = createProjectPreferredTypeRaw
        }
        if createProjectMode == .newWithAgent {
            syncFolderNameFromIdeaIfNeeded()
        }
    }

    private func openCreateProjectPage() {
        prepareCreateProjectForm()
        withAnimation(.easeInOut(duration: 0.2)) {
            showCreateProjectPage = true
        }
        if appState.isMainContentCollapsed {
            withAnimation(.easeInOut(duration: 0.2)) { appState.isMainContentCollapsed = false }
        }
    }

    private func dismissCreateProjectPageIfNeeded() {
        guard showCreateProjectPage else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            showCreateProjectPage = false
        }
        createProjectError = nil
    }

    private func runCreateProjectSetup(path: String, supplement: String) {
        let prompt = makeProjectSetupPrompt(
            includeInitialGitCommit: createProjectInitialGitCommit,
            userSupplement: supplement
        )
        tabManager.addProject(path: path, select: true)
        updateProjectContext(to: path)
        createProjectBusy = false
        showCreateProjectPage = false
        createProjectError = nil
        if appState.isMainContentCollapsed {
            withAnimation(.easeInOut(duration: 0.2)) { appState.isMainContentCollapsed = false }
        }
        _ = addNewAgentTab(
            initialPrompt: prompt,
            lastWorkspacePath: path,
            modelId: effectiveCreateProjectModelID()
        )
    }

    private func submitCreateProject() {
        createProjectError = nil
        switch createProjectMode {
        case .newWithAgent:
            let folder = createProjectFolderName
            guard !sanitizedProjectName(folder).isEmpty else {
                createProjectError = "Enter a project folder name."
                return
            }
            createProjectBusy = true
            switch createProjectDirectory(parentPath: createProjectParentPath, folderName: folder) {
            case .success(let path):
                let idea = createProjectIdea.trimmingCharacters(in: .whitespacesAndNewlines)
                let selectedType = createProjectSelectedType ?? preferredCreateProjectType
                if let selectedType {
                    rememberCreateProjectType(selectedType, weight: 2)
                }
                let supplement: String
                if idea.isEmpty {
                    if let selectedType {
                        supplement = "Create a new project in this empty folder. Build a \(selectedType.promptLabel) and choose a thoughtful concept that fits the user's Create preferences. Scaffold a minimal runnable starting point."
                    } else {
                        supplement = "Create a new project in this empty folder. Scaffold a minimal runnable app from what you detect in the stack."
                    }
                } else {
                    if let selectedType {
                        supplement = "Create a new project in this empty folder based on this request: \(idea). Favor a \(selectedType.promptLabel) unless the request clearly implies a different shape."
                    } else {
                        supplement = "Create a new project in this empty folder based on this request: \(idea)"
                    }
                }
                runCreateProjectSetup(path: path, supplement: supplement)
            case .failure(let error):
                createProjectBusy = false
                createProjectError = error.message
            }
        case .cloneFromGitHub:
            let url = createProjectGitURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty else {
                createProjectError = "Enter a repository URL."
                return
            }
            createProjectBusy = true
            let parent = createProjectParentPath
            let folder = createProjectFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
            let folderOpt: String? = folder.isEmpty ? nil : folder
            DispatchQueue.global(qos: .userInitiated).async {
                let result = cloneRepository(repositoryURL: url, destinationParentPath: parent, folderName: folderOpt)
                DispatchQueue.main.async {
                    switch result {
                    case .success(let path):
                        let supplement = "This workspace was cloned from \(url). Configure Metro Preview terminals via `.metro/project.json` and finish setup."
                        runCreateProjectSetup(path: path, supplement: supplement)
                    case .failure(let error):
                        createProjectBusy = false
                        createProjectError = error.message
                    }
                }
            }
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
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let resolved = url.resolvingSymlinksInPath()
        return (resolved.path as NSString).standardizingPath
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

            if sidebarCycleDestinations().count > 1 {
                hiddenShortcutButton("Cycle tabs forward", key: "=") {
                    cycleSidebarWorkspace(direction: 1)
                }
                hiddenShortcutButton("Cycle tabs backward", key: "-") {
                    cycleSidebarWorkspace(direction: -1)
                }
            }

            hiddenShortcutButton("Cycle left-dock layout", key: "[", modifiers: .command) {
                NotificationCenter.default.post(
                    name: FloatingPanel.sidebarShortcutNotification,
                    object: nil,
                    userInfo: [FloatingPanel.sidebarShortcutActionUserInfoKey: FloatingPanel.SidebarShortcutAction.cycleLeftAnchor.rawValue]
                )
            }

            hiddenShortcutButton("Cycle right-dock layout", key: "]", modifiers: .command) {
                NotificationCenter.default.post(
                    name: FloatingPanel.sidebarShortcutNotification,
                    object: nil,
                    userInfo: [FloatingPanel.sidebarShortcutActionUserInfoKey: FloatingPanel.SidebarShortcutAction.cycleRightAnchor.rawValue]
                )
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

    private func toggleMainContentCollapsed() {
        withAnimation(.easeInOut(duration: 0.2)) {
            appState.isMainContentCollapsed.toggle()
        }
    }

    private func openProjectHostingRemote(_ path: String) {
        guard let destination = repositoryHostingDestination(workspacePath: path) else { return }
        NSWorkspace.shared.open(destination.url)
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
            newTab.currentBranch = snapshot.current
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
        if tabManager.addTerminalTab(workspacePath: targetWorkspacePath) != nil {
            tabManager.selectedDashboardViewPath = targetWorkspacePath
        }
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
        if !visible.contains(where: { $0.id == AvailableModels.autoID }) {
            visible.insert(AvailableModels.autoOption, at: 0)
        }
        return visible
    }

    private func effectiveSelectedModel(for providerID: AgentProviderID) -> String {
        if appState.model(for: selectedModel, providerID: providerID) != nil {
            return selectedModel
        }
        return appState.defaultModelID(for: providerID)
    }

    private func effectiveCreateProjectModelID(for providerID: AgentProviderID = .cursor) -> String {
        if appState.model(for: createProjectModelId, providerID: providerID) != nil {
            return createProjectModelId
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
            for tab in tabManager.tabs where tab.workspacePath == normalizedPath {
                tab.currentBranch = cached.current
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
                for tab in tabManager.tabs where tab.workspacePath == normalizedPath {
                    tab.currentBranch = snapshot.current
                }
                guard currentWorkspacePath == normalizedPath else { return }
                currentBranch = snapshot.current
                gitBranches = snapshot.branches
            }
        }
    }

    /// Applies cached git snapshot (or the active tab’s remembered branch) to picker state without running `git`.
    private func syncGitPickerUIFromCache(for workspacePath: String) {
        let normalizedPath = workspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else {
            currentBranch = ""
            gitBranches = []
            return
        }
        if let cached = gitBranchSnapshotsByWorkspace[normalizedPath] {
            currentBranch = cached.current
            gitBranches = cached.branches
            return
        }
        if let active = tabManager.activeTab, active.workspacePath == normalizedPath, !active.currentBranch.isEmpty {
            currentBranch = active.currentBranch
        } else {
            currentBranch = ""
        }
        gitBranches = []
    }

    private func displayedGitBranch(for tab: AgentTab) -> String {
        let fromTab = tab.currentBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fromTab.isEmpty { return fromTab }
        return currentBranch.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum SidebarEdge: Equatable {
        case leading
        case trailing

        var alignment: Alignment {
            switch self {
            case .leading:
                return .leading
            case .trailing:
                return .trailing
            }
        }
    }

    private enum WindowLayoutOption: String, CaseIterable, Identifiable {
        case dockLeft
        case expandedLeft
        case expandedRight
        case dockRight

        var id: String { rawValue }

        var title: String {
            switch self {
            case .dockLeft:
                return "Dock Left"
            case .expandedLeft:
                return "Expanded Left"
            case .expandedRight:
                return "Expanded Right"
            case .dockRight:
                return "Dock Right"
            }
        }

        var shortcutSymbolName: String {
            switch self {
            case .dockLeft:
                return "1.circle"
            case .expandedLeft:
                return "2.circle"
            case .expandedRight:
                return "3.circle"
            case .dockRight:
                return "4.circle"
            }
        }

        var selectedShortcutSymbolName: String {
            switch self {
            case .dockLeft:
                return "1.circle.fill"
            case .expandedLeft:
                return "2.circle.fill"
            case .expandedRight:
                return "3.circle.fill"
            case .dockRight:
                return "4.circle.fill"
            }
        }

        var shortcutDisplay: String {
            switch self {
            case .dockLeft, .expandedLeft:
                return "⌘["
            case .expandedRight, .dockRight:
                return "⌘]"
            }
        }

        var shortcutAction: FloatingPanel.SidebarShortcutAction {
            switch self {
            case .dockLeft:
                return .collapseLeft
            case .expandedLeft:
                return .expandLeft
            case .expandedRight:
                return .expandRight
            case .dockRight:
                return .collapseRight
            }
        }
    }

    private var sidebarEdge: SidebarEdge { isSidebarOnRight ? .trailing : .leading }

    private var selectedWindowLayout: WindowLayoutOption {
        switch (isMainContentCollapsed, isSidebarOnRight) {
        case (true, false):
            return .dockLeft
        case (false, false):
            return .expandedLeft
        case (false, true):
            return .expandedRight
        case (true, true):
            return .dockRight
        }
    }

    private func applyWindowLayout(_ layout: WindowLayoutOption) {
        NotificationCenter.default.post(
            name: FloatingPanel.sidebarShortcutNotification,
            object: nil,
            userInfo: [FloatingPanel.sidebarShortcutActionUserInfoKey: layout.shortcutAction.rawValue]
        )
    }

    @ViewBuilder
    private func layoutMenuIcon(_ layout: WindowLayoutOption, isSelected: Bool = false) -> some View {
        Image(systemName: isSelected ? layout.selectedShortcutSymbolName : layout.shortcutSymbolName)
    }

    private var layoutMenuButton: some View {
        Menu {
            ForEach(WindowLayoutOption.allCases) { layout in
                Button {
                    applyWindowLayout(layout)
                } label: {
                    HStack(spacing: CursorTheme.spaceS) {
                        layoutMenuIcon(layout, isSelected: layout == selectedWindowLayout)
                            .frame(width: CursorTheme.spaceL)
                        Text(layout.title)
                        Spacer(minLength: CursorTheme.spaceL)
                        Text(layout.shortcutDisplay)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } label: {
            layoutMenuIcon(selectedWindowLayout)
                .font(.system(size: IconButton.Size.medium.iconFontSize, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                .frame(width: IconButton.Size.medium.dimension, height: IconButton.Size.medium.dimension)
                .background(CursorTheme.surfaceMuted(for: colorScheme), in: Circle())
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(CursorTheme.textPrimary(for: colorScheme))
        .fixedSize()
        .help("View layout")
    }

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

    /// Flat list of sidebar rows in visual order (Tasks → Preview → each visible agent tab, for each project group).
    private func sidebarCycleDestinations() -> [SidebarCycleDestination] {
        var result: [SidebarCycleDestination] = []
        for group in tabGroups {
            result.append(.tasks(path: group.path))
            result.append(.preview(path: group.path))
            for tab in group.tabs {
                result.append(.agentTab(id: tab.id))
            }
        }
        return result
    }

    private func terminalWorkspaceForSelectedTerminal() -> String? {
        guard let tid = tabManager.selectedTerminalID else { return nil }
        return tabManager.terminalTabs.first { $0.id == tid }?.workspacePath
    }

    private func isTasksPageSelected(for path: String) -> Bool {
        tabManager.selectedTabID == nil && tabManager.selectedTasksViewPath == path
    }

    private func isPreviewPageSelected(for path: String) -> Bool {
        guard tabManager.selectedTabID == nil else { return false }
        guard tabManager.selectedTasksViewPath != path else { return false }
        if tabManager.selectedDashboardViewPath == path { return true }
        return terminalWorkspaceForSelectedTerminal() == path
    }

    private func destinationMatchesCurrentSelection(_ dest: SidebarCycleDestination) -> Bool {
        switch dest {
        case .tasks(let path):
            guard tabManager.selectedTabID == nil else { return false }
            return tabManager.selectedTasksViewPath == path
        case .preview(let path):
            guard tabManager.selectedTabID == nil else { return false }
            guard tabManager.selectedTasksViewPath != path else { return false }
            if tabManager.selectedDashboardViewPath == path { return true }
            if let termPath = terminalWorkspaceForSelectedTerminal(), termPath == path { return true }
            return false
        case .agentTab(let id):
            return tabManager.selectedTabID == id
        }
    }

    private func sidebarCycleCurrentIndex(in list: [SidebarCycleDestination]) -> Int {
        if let i = list.firstIndex(where: { destinationMatchesCurrentSelection($0) }) {
            return i
        }
        if let sid = tabManager.selectedTabID,
           let tab = tabManager.tabs.first(where: { $0.id == sid }) {
            let p = tab.workspacePath
            return list.firstIndex { dest in
                if case .tasks(let path) = dest { return path == p }
                return false
            } ?? 0
        }
        return 0
    }

    private func applySidebarCycleDestination(_ dest: SidebarCycleDestination) {
        switch dest {
        case .tasks(let path):
            tabManager.showTasksView(workspacePath: path)
        case .preview(let path):
            openDashboard(workspacePath: path)
        case .agentTab(let id):
            selectLinkedAgentTab(id)
        }
        if appState.isMainContentCollapsed {
            withAnimation(.easeInOut(duration: 0.2)) { appState.isMainContentCollapsed = false }
        }
    }

    private func cycleSidebarWorkspace(direction: Int) {
        guard hasOpenProjects else { return }
        let list = sidebarCycleDestinations()
        guard list.count > 1 else { return }
        let currentIdx = sidebarCycleCurrentIndex(in: list)
        let n = list.count
        let nextIdx = ((currentIdx + direction) % n + n) % n
        applySidebarCycleDestination(list[nextIdx])
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
        if showCreateProjectPage {
            createProjectContentArea()
        } else if !hasOpenProjects {
            splashContentArea()
        } else {
            // Hide when any Preview terminal exists (manual or Run); empty state is only for no terminals yet.
            let showingDashboardEmpty = selectedProjectPath != nil
                && tabManager.selectedDashboardViewPath == selectedProjectPath
                && tabManager.dashboardTabs(for: selectedProjectPath!).isEmpty
                && dashboardPanelTerminals(for: selectedProjectPath!).isEmpty
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
        let previewDisplayName = appState.workspaceDisplayName(for: path)
        PanelChromeStrip(horizontalPadding: CursorTheme.paddingChrome) {
            HStack(spacing: 0) {
                Button {
                    tabManager.selectedTerminalID = nil
                } label: {
                    HStack(spacing: 6) {
                        WorkspaceAvatarView(
                            workspacePath: path,
                            displayName: previewDisplayName.isEmpty ? nil : previewDisplayName,
                            size: 15
                        )
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
                            tabManager.selectedDashboardViewPath = term.workspacePath
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
        }
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
        let isConfigured = !projectSettingsStore.startupScripts(for: root).isEmpty
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
                    title: "Add Terminal",
                    icon: "plus",
                    action: { addNewTerminalTab(lastWorkspacePath: path) },
                    help: "Open a manual terminal tab in Preview",
                    style: .secondary
                )
                ActionButton(
                    title: isConfigured ? "Regenerate Setup" : "Configure Setup",
                    icon: "gearshape",
                    action: { _ = addNewAgentTab(initialPrompt: makeProjectSetupPrompt(), lastWorkspacePath: path) },
                    help: isConfigured ? "Launch an agent to regenerate .metro/project.json scripts and debug URL" : "Launch an agent to set up .metro/project.json scripts and debug URL for this project",
                    style: .primary
                )
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            projectSettingsStore.reload(workspacePath: root)
        }
        .onChange(of: path) { _, newPath in
            projectSettingsStore.reload(workspacePath: projectRootForTerminal(workspacePath: newPath))
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            projectSettingsStore.reload(workspacePath: projectRootForTerminal(workspacePath: path))
        }
        // Setup agent writes project.json via the CLI (no in-app save → no storage notification). Poll briefly so Run appears when the file lands.
        .task(id: path) {
            let r = projectRootForTerminal(workspacePath: path)
            for _ in 0..<90 {
                if Task.isCancelled { return }
                projectSettingsStore.reload(workspacePath: r)
                if !projectSettingsStore.startupScripts(for: r).isEmpty { return }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
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

    private func sidebarColumn(width: CGFloat) -> some View {
        VStack(spacing: CursorTheme.gapSectionTitleToContent) {
            leftColumnHeader
            tabSidebar
        }
        .padding(.horizontal, CursorTheme.paddingSidebarUniform)
        .padding(.vertical, CursorTheme.paddingChrome)
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
    }

    private func splitDividerDrag(totalWidth: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .frame(width: SidebarSplitMetrics.dragHandleWidth)
                .contentShape(Rectangle())
            Divider()
                .background(CursorTheme.border(for: colorScheme))
                .frame(maxHeight: .infinity)
        }
        .frame(width: SidebarSplitMetrics.dragHandleWidth)
        .accessibilityLabel("Sidebar width")
        .accessibilityHint("Drag left or right to resize the project sidebar")
        .accessibilityAddTraits(.isButton)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if sidebarDragStartWidth == nil {
                        sidebarDragStartWidth = clampedSidebarWidth(totalWidth: totalWidth)
                    }
                    guard let start = sidebarDragStartWidth else { return }
                    let minS = SidebarSplitMetrics.minSidebar
                    let minMain = SidebarSplitMetrics.minMainColumn
                    let maxSidebar = max(minS, totalWidth - minMain - 1)
                    let proposed = start + value.translation.width
                    let clamped = min(max(proposed, minS), maxSidebar)
                    sidebarWidthStored = Double(clamped)
                }
                .onEnded { _ in
                    sidebarDragStartWidth = nil
                }
        )
        .onHover { hovering in
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .help("Drag to resize sidebar")
    }

    @ViewBuilder
    private var mainColumnSecondaryBar: some View {
        if tabManager.selectedDashboardViewPath == selectedProjectPath,
           let path = selectedProjectPath,
           !path.isEmpty {
            dashboardPanelTabBar(workspacePath: path)
        }
    }

    private var shouldShowMainColumnSecondaryBar: Bool {
        tabManager.selectedDashboardViewPath == selectedProjectPath
            && selectedProjectPath?.isEmpty == false
    }

    private var mainColumn: some View {
        VStack(spacing: 0) {
            mainColumnHeaderArea
            if shouldShowMainColumnSecondaryBar {
                mainColumnSecondaryBar
            }
            Divider()
                .background(CursorTheme.border(for: colorScheme))
            mainContentZStack
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    @ViewBuilder
    private var mainContentWithSidebar: some View {
        if isMainContentCollapsed {
            sidebarColumn(width: collapsedSidebarContentWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            GeometryReader { geometry in
                let contentWidth = max(0, geometry.size.width)
                let sidebarW = clampedSidebarWidth(totalWidth: contentWidth)
                let agentWidth = max(0, contentWidth - sidebarW - 1)

                HStack(alignment: .top, spacing: 0) {
                    if sidebarEdge == .trailing {
                        mainColumn
                            .frame(width: agentWidth)
                        splitDividerDrag(totalWidth: contentWidth)
                        sidebarColumn(width: sidebarW)
                    } else {
                        sidebarColumn(width: sidebarW)
                        splitDividerDrag(totalWidth: contentWidth)
                        mainColumn
                            .frame(width: agentWidth)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: sidebarEdge.alignment)
                .onChange(of: contentWidth) { _, newWidth in
                    syncSidebarWidthToClamped(totalWidth: newWidth)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var bodyWithDashboardPersistence: some View {
        bodyContent
            .padding(.vertical, CursorTheme.paddingChrome)
            .padding(.leading, isMainContentCollapsed ? CursorTheme.paddingSidebarCollapsedOuter : (sidebarEdge == .trailing ? CursorTheme.paddingChrome : 0))
            .padding(.trailing, isMainContentCollapsed ? CursorTheme.paddingSidebarCollapsedOuter : (sidebarEdge == .leading ? CursorTheme.paddingChrome : 0))
            .frame(minWidth: isMainContentCollapsed ? collapsedSidebarWindowWidth : minimumExpandedWindowWidth)
            .frame(width: isMainContentCollapsed ? collapsedSidebarWindowWidth : nil)
            .frame(maxWidth: isMainContentCollapsed ? collapsedSidebarWindowWidth : .infinity, minHeight: isMainContentCollapsed ? 300 : 400, maxHeight: .infinity)
            .preferredColorScheme(resolvedColorScheme)
            .background(CursorTheme.panelGradient(for: colorScheme))
    }

    private var bodyWithShortcuts: some View {
        bodyWithDashboardPersistence
            .onKeyPress(.tab) {
                // Let the embedded SwiftTerm terminal receive Tab for shell completion (readline/zsh).
                if tabManager.selectedTerminalID != nil {
                    return .ignored
                }
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
            reloadProjectDiscovery()
            refreshQuickActions(for: currentWorkspacePath)
            refreshGitState(for: currentWorkspacePath)
            updateHangDiagnosticsSnapshot()
        }
        .onChange(of: workspacePath) { _, _ in
            refreshQuickActions(for: workspacePath, force: true)
            updateHangDiagnosticsSnapshot()
        }
        .onChange(of: projectScanRootsRaw) { _, _ in
            reloadProjectDiscovery()
            updateHangDiagnosticsSnapshot()
        }
        .onChange(of: projectsRootPath) { _, _ in
            reloadProjectDiscovery()
            updateHangDiagnosticsSnapshot()
        }
        .onChange(of: selectedModel) { _, _ in
            sanitizeSelectedModel()
            updateHangDiagnosticsSnapshot()
        }
        .onChange(of: tabManager.selectedTabID) { _, _ in
            dismissCreateProjectPageIfNeeded()
            syncGitPickerUIFromCache(for: currentWorkspacePath)
            updateHangDiagnosticsSnapshot()
        }
        .onChange(of: tabManager.selectedProjectPath) { _, _ in
            let path = currentWorkspacePath
            refreshQuickActions(for: path)
            refreshGitState(for: path)
            updateHangDiagnosticsSnapshot()
        }
        .onChange(of: tabManager.selectedTasksViewPath) { _, newValue in
            if newValue != nil {
                dismissCreateProjectPageIfNeeded()
            }
            updateHangDiagnosticsSnapshot()
        }
        .onChange(of: tabManager.selectedTerminalID) { _, newValue in
            if newValue != nil {
                dismissCreateProjectPageIfNeeded()
            }
            updateHangDiagnosticsSnapshot()
        }
        .onChange(of: tabManager.selectedDashboardViewPath) { _, newValue in
            if newValue != nil {
                dismissCreateProjectPageIfNeeded()
            }
            updateHangDiagnosticsSnapshot()
        }
        .onChange(of: appState.taskListRevision) { _, _ in
            updateHangDiagnosticsSnapshot()
        }
        .onReceive(NotificationCenter.default.publisher(for: FloatingPanel.cycleSidebarWorkspaceNotification)) { notification in
            let direction = (notification.userInfo?[FloatingPanel.cycleSidebarDirectionUserInfoKey] as? Int) ?? 1
            cycleSidebarWorkspace(direction: direction)
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
        .alert("Add project", isPresented: Binding(
            get: { addProjectError != nil },
            set: { if !$0 { addProjectError = nil } }
        )) {
            Button("OK", role: .cancel) { addProjectError = nil }
        } message: {
            Text(addProjectError ?? "")
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
            if isMainContentCollapsed {
                layoutMenuButton
                IconButton(icon: "gearshape", action: { appState.showSettingsSheet = true }, help: "Settings")
                IconButton(icon: "minus", action: dismiss, help: "Minimise")
            }
        }
    }

    /// Single title row: icon + header (e.g. Tasks / agent title) on the left, title bar buttons (collapse, sidebar, settings, minimise) on the right.
    private var mainColumnTitleRow: some View {
        return HStack(alignment: .center, spacing: 0) {
            mainColumnTitleContent
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            layoutMenuButton
            IconButton(icon: "gearshape", action: { appState.showSettingsSheet = true }, help: "Settings")
            IconButton(icon: "minus", action: dismiss, help: "Minimise")
        }
        .padding(.horizontal, CursorTheme.paddingChrome)
        .padding(.vertical, CursorTheme.paddingHeaderVertical)
    }

    /// Header area: title row (agent prompt expands in place by wrapping, no separate card). When Dashboard is running, show Stop/Open in Browser row.
    @ViewBuilder
    private var mainColumnHeaderArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            mainColumnTitleRow
            if !showCreateProjectPage,
               tabManager.selectedDashboardViewPath == selectedProjectPath,
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
                    action: { stopDashboard(workspacePath: path) },
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
            ActionButton(
                title: "Add Terminal",
                icon: "plus",
                action: { addNewTerminalTab(lastWorkspacePath: path) },
                help: "Open a manual terminal tab in Preview",
                style: .secondary
            )
            Spacer(minLength: 0)
        }
        .padding(.horizontal, CursorTheme.paddingChrome)
        .padding(.bottom, CursorTheme.paddingHeaderVertical)
    }

    @ViewBuilder
    private var mainColumnTitleContent: some View {
        if showCreateProjectPage {
            createProjectTitleContent()
        } else if !hasOpenProjects {
            welcomeTitleContent()
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

    private func welcomeTitleContent() -> some View {
        PanelHeaderView(title: "Cursor Metro") {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: CursorTheme.fontIconList, weight: .medium))
                .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
        } subtitle: {
            Text("Add an existing folder, or use Create to scaffold or clone and run the setup agent.")
                .font(.system(size: CursorTheme.fontSecondary, weight: .regular))
                .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                .lineLimit(2)
        }
    }

    private func createProjectTitleContent() -> some View {
        PanelHeaderView(title: "Create") {
            Image(systemName: "wand.and.stars")
                .font(.system(size: CursorTheme.fontIconList, weight: .medium))
                .foregroundStyle(CursorTheme.brandBlue)
        } subtitle: {
            Text("Create a folder or clone a repo, then Metro sets up Preview.")
                .font(.system(size: CursorTheme.fontSecondary, weight: .regular))
                .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                .lineLimit(2)
        }
    }

    private func tasksTitleContent(workspacePath path: String) -> some View {
        let projectColor = path.isEmpty
            ? CursorTheme.textTertiary(for: colorScheme)
            : CursorTheme.colorForWorkspace(path: path)
        let displayName = appState.workspaceDisplayName(for: path)
        return PanelHeaderView(title: "Tasks") {
            WorkspaceAvatarView(
                workspacePath: path,
                displayName: displayName.isEmpty ? nil : displayName,
                size: 32
            )
        } subtitle: {
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
        let displayName = appState.workspaceDisplayName(for: path)
        return PanelHeaderView(title: "Preview") {
            WorkspaceAvatarView(
                workspacePath: path,
                displayName: displayName.isEmpty ? nil : displayName,
                size: 32
            )
        } subtitle: {
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
        let agentProjectDisplay = appState.workspaceDisplayName(for: tab.workspacePath)
        let showsCenteredStatusIcon = status.isProcessing || status.isPendingReview || status.isStopped || status.isCompleted
        return HStack(alignment: .top, spacing: CursorTheme.spaceM) {
            WorkspaceAvatarView(
                workspacePath: tab.workspacePath,
                displayName: agentProjectDisplay.isEmpty ? nil : agentProjectDisplay,
                size: CursorTheme.sizeAgentHeaderAvatar,
                showsInitialsWhenNoLogo: false
            )
            .overlay {
                if showsCenteredStatusIcon {
                    Circle()
                        .fill(CursorTheme.surfaceRaised(for: colorScheme).opacity(0.96))
                        .frame(
                            width: CursorTheme.sizeAgentHeaderStatusBadge,
                            height: CursorTheme.sizeAgentHeaderStatusBadge
                        )
                        .overlay {
                            agentStatusIcon(tab: tab, status: status)
                                .frame(
                                    width: CursorTheme.sizeAgentHeaderStatusBadge,
                                    height: CursorTheme.sizeAgentHeaderStatusBadge
                                )
                        }
                        .overlay(
                            Circle()
                                .stroke(CursorTheme.borderStrong(for: colorScheme), lineWidth: 1)
                        )
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(agentProjectDisplay.isEmpty ? (tab.workspacePath as NSString).lastPathComponent : agentProjectDisplay), \(status.label)"
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .font(.system(size: CursorTheme.fontTitle, weight: .semibold))
                    .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                    .multilineTextAlignment(.leading)
                    .lineLimit(isExpanded ? nil : Self.agentHeaderPromptCollapsedLineLimit)
                    .truncationMode(.tail)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        guard hasExpandablePrompt else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if expandedPromptTabID.wrappedValue == tab.id {
                                expandedPromptTabID.wrappedValue = nil
                            } else {
                                expandedPromptTabID.wrappedValue = tab.id
                            }
                        }
                    }
                    .onHover { hovering in
                        guard hasExpandablePrompt else { return }
                        if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                    .help(
                        hasExpandablePrompt
                            ? (isExpanded ? "Double-click to collapse prompt" : "Double-click to show full prompt")
                            : ""
                    )
                let projectColor = tab.workspacePath.isEmpty
                    ? CursorTheme.textTertiary(for: colorScheme)
                    : CursorTheme.colorForWorkspace(path: tab.workspacePath)
                let projectSubtitle = agentProjectDisplay.isEmpty
                    ? (tab.workspacePath as NSString).lastPathComponent
                    : agentProjectDisplay
                Text(projectSubtitle)
                    .font(.system(size: CursorTheme.fontSecondary, weight: .regular))
                    .foregroundStyle(projectColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
    }

    private var tabSidebar: some View {
        VStack(spacing: CursorTheme.spaceS) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: CursorTheme.spaceM) {
                    ForEach(tabGroups, id: \.path) { group in
                        VStack(alignment: .leading, spacing: CursorTheme.spaceS) {
                            HStack(spacing: CursorTheme.spaceS) {
                                Button {
                                    tabManager.selectProject(group.path)
                                    if appState.isMainContentCollapsed {
                                        withAnimation(.easeInOut(duration: 0.2)) { appState.isMainContentCollapsed = false }
                                    }
                                } label: {
                                    HStack(spacing: CursorTheme.spaceS + CursorTheme.spaceXS) {
                                        if !group.path.isEmpty {
                                            WorkspaceAvatarView(
                                                workspacePath: group.path,
                                                displayName: group.displayName,
                                                size: 30
                                            )
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(group.displayName)
                                                .font(.system(size: CursorTheme.fontBodyEmphasis, weight: .semibold))
                                                .foregroundStyle(CursorTheme.colorForWorkspace(path: group.path))
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                            let groupBranch = group.path == currentWorkspacePath ? currentBranch : (group.tabs.first?.currentBranch ?? "")
                                            if !groupBranch.isEmpty {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "arrow.triangle.branch")
                                                        .font(.system(size: CursorTheme.fontTiny, weight: .medium))
                                                    Text(groupBranch)
                                                        .font(.system(size: CursorTheme.fontSmall, weight: .regular))
                                                        .italic()
                                                }
                                                .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                let hostingDestination = repositoryHostingDestination(workspacePath: group.path)
                                Menu {
                                    Menu("Open in…", systemImage: "arrow.up.forward.app") {
                                        Button("Cursor") {
                                            openProjectInCursor(group.path)
                                        }
                                        if let hostingDestination {
                                            Button(hostingDestination.provider.menuTitle, systemImage: "link") {
                                                openProjectHostingRemote(group.path)
                                            }
                                        }
                                    }
                                    Divider()
                                    Button(role: .destructive) {
                                        removeProject(workspacePath: group.path)
                                    } label: {
                                        Text("Remove")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.system(size: CursorTheme.fontBodySmall, weight: .medium))
                                        .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                                        .frame(width: 18, height: 30)
                                        .contentShape(Rectangle())
                                }
                                .menuStyle(.borderlessButton)
                                .menuIndicator(.hidden)
                                .help("Project actions")
                            }
                            .padding(.horizontal, CursorTheme.paddingSidebarGroupHeaderHorizontal)
                            .padding(.vertical, CursorTheme.paddingSidebarGroupHeaderVertical)
                            let isTasksSelected = isTasksPageSelected(for: group.path)
                            SidebarPageChip(
                                title: "Tasks",
                                icon: "checklist",
                                isSelected: isTasksSelected,
                                onSelect: {
                                    tabManager.showTasksView(workspacePath: group.path)
                                    if appState.isMainContentCollapsed {
                                        withAnimation(.easeInOut(duration: 0.2)) { appState.isMainContentCollapsed = false }
                                    }
                                }
                            )
                            .help("View tasks for this project")
                            .contextMenu {
                                Button("Add Task", systemImage: "plus.circle.fill") {
                                    showTasksComposer(workspacePath: group.path, startNewTask: true)
                                }
                            }
                            let isDashboardSelected = isPreviewPageSelected(for: group.path)
                            SidebarPageChip(
                                title: "Preview",
                                icon: "eye",
                                isSelected: isDashboardSelected,
                                onSelect: {
                                    openDashboard(workspacePath: group.path)
                                }
                            )
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
                                .contextMenu {
                                    if t.isRunning {
                                        Button("Stop", systemImage: "stop.fill") {
                                            stopStreaming(for: t)
                                        }
                                    }
                                    agentTabLinkedTaskMoveMenu(for: t)
                                    if t.isRunning || t.linkedTaskID != nil {
                                        Divider()
                                    }
                                    Button("Close Tab", systemImage: "xmark", role: .destructive) {
                                        requestCloseTab(t)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, CursorTheme.spaceXS)
            }
            .frame(maxHeight: .infinity)

            VStack(spacing: CursorTheme.spaceS) {
                ActionButton(
                    title: "Import",
                    icon: "folder.badge.plus",
                    action: addProject,
                    help: "Open an existing project folder",
                    style: .primary,
                    fillsAvailableWidth: true
                )
                .frame(maxWidth: .infinity)
                ActionButton(
                    title: "Create",
                    icon: "wand.and.stars",
                    action: openCreateProjectPage,
                    help: "Create or clone a project and run setup",
                    style: .secondary,
                    fillsAvailableWidth: true
                )
                .frame(maxWidth: .infinity)
            }
            .padding(.top, CursorTheme.spaceM)
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private func reloadProjectDiscovery(using roots: [String]? = nil) {
        let resolvedRoots = roots ?? projectScanRoots
        _ = seedMetroDirectories(rootPaths: resolvedRoots)
        devFolders = loadDevFolders(rootPaths: resolvedRoots)
        tabManager.setDiscoveredProjectsFromPaths(devFolders.map(\.path))
    }

    // MARK: - Create page (scaffold / clone)

    private var createIdeaSuggestions: [String] {
        if let type = createProjectSelectedType ?? preferredCreateProjectType {
            return type.surpriseIdeas
        }

        return Array(CreateProjectInspirationType.allCases.compactMap { $0.surpriseIdeas.first }.prefix(5))
    }

    private var createProjectSelectedType: CreateProjectInspirationType? {
        CreateProjectInspirationType(rawValue: createProjectSelectedTypeRaw)
    }

    private var preferredCreateProjectType: CreateProjectInspirationType? {
        CreateProjectInspirationType(rawValue: createProjectPreferredTypeRaw)
    }

    private var createProjectIdeaPlaceholder: String {
        (createProjectSelectedType ?? preferredCreateProjectType)?.placeholderIdea ?? "A small Next.js app for invoices"
    }

    private var suggestedFolderNameFromIdea: String {
        let sanitized = suggestedProjectFolderName(from: createProjectIdea)
        if !sanitized.isEmpty {
            return sanitized
        }

        return createProjectSelectedType?.fallbackFolderName
            ?? preferredCreateProjectType?.fallbackFolderName
            ?? "my-app"
    }

    private func syncFolderNameFromIdeaIfNeeded() {
        guard createProjectMode == .newWithAgent else { return }
        guard !createProjectFolderNameEditedByUser || createProjectFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        createProjectFolderName = suggestedFolderNameFromIdea
    }

    private func applyCreateIdeaSuggestion(_ suggestion: String) {
        createProjectIdea = suggestion
        syncFolderNameFromIdeaIfNeeded()
    }

    private func applyCreateProjectType(_ type: CreateProjectInspirationType) {
        createProjectSelectedTypeRaw = type.rawValue
        rememberCreateProjectType(type)
        syncFolderNameFromIdeaIfNeeded()
    }

    private func rememberCreateProjectType(_ type: CreateProjectInspirationType, weight: Int = 1) {
        createProjectPreferredTypeRaw = type.rawValue

        var usage = AppPreferences.createProjectTypeUsage(from: createProjectTypeUsageRaw)
        usage[type.rawValue, default: 0] += max(1, weight)
        createProjectTypeUsageRaw = AppPreferences.rawFrom(createProjectTypeUsage: usage)
    }

    private func surpriseCreateProjectType() -> CreateProjectInspirationType {
        if let selected = createProjectSelectedType {
            return selected
        }

        let usage = AppPreferences.createProjectTypeUsage(from: createProjectTypeUsageRaw)
        let weightedTypes = CreateProjectInspirationType.allCases.flatMap { type in
            let usageWeight = min(usage[type.rawValue, default: 0], 5)
            let preferredWeight = preferredCreateProjectType == type ? 2 : 0
            return Array(repeating: type, count: max(1, 1 + usageWeight + preferredWeight))
        }

        return weightedTypes.randomElement() ?? preferredCreateProjectType ?? .webApp
    }

    private func surpriseCreateIdea(for type: CreateProjectInspirationType) -> String {
        let currentIdea = createProjectIdea.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = type.surpriseIdeas.filter { $0 != currentIdea }
        return candidates.randomElement() ?? type.surpriseIdeas.first ?? type.placeholderIdea
    }

    private func applySurpriseCreateIdea() {
        let type = surpriseCreateProjectType()
        createProjectSelectedTypeRaw = type.rawValue
        rememberCreateProjectType(type, weight: 2)
        applyCreateIdeaSuggestion(surpriseCreateIdea(for: type))
    }

    private func createProjectContentArea() -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: CursorTheme.gapBetweenSections) {
                if let err = createProjectError, !err.isEmpty {
                    Text(err)
                        .font(.system(size: CursorTheme.fontBodySmall, weight: .medium))
                        .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(CursorTheme.paddingCard)
                        .background(CursorTheme.semanticErrorTint.opacity(0.2), in: RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous)
                                .stroke(CursorTheme.semanticError.opacity(0.45), lineWidth: 1)
                        )
                }

                VStack(alignment: .leading, spacing: CursorTheme.spaceM) {
                    Text("Source")
                        .font(.system(size: CursorTheme.fontCaption, weight: .semibold))
                        .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                    HStack(spacing: CursorTheme.spaceS) {
                        ForEach(CreateProjectWorkflowMode.allCases) { mode in
                            let isSelected = createProjectMode == mode
                            Button {
                                createProjectMode = mode
                                createProjectError = nil
                                if mode == .newWithAgent {
                                    syncFolderNameFromIdeaIfNeeded()
                                }
                            } label: {
                                HStack(spacing: CursorTheme.spaceXS) {
                                    Image(systemName: mode == .newWithAgent ? "wand.and.stars" : "arrow.down.doc")
                                        .font(.system(size: CursorTheme.fontBodySmall, weight: .semibold))
                                    Text(mode == .newWithAgent ? "New project" : "GitHub")
                                        .font(.system(size: CursorTheme.fontBodySmall, weight: .semibold))
                                }
                                .foregroundStyle(isSelected ? CursorTheme.textPrimary(for: colorScheme) : CursorTheme.textSecondary(for: colorScheme))
                                .padding(.horizontal, CursorTheme.paddingCard)
                                .padding(.vertical, CursorTheme.spaceS)
                                .background(
                                    isSelected ? CursorTheme.surfaceRaised(for: colorScheme) : CursorTheme.surfaceMuted(for: colorScheme),
                                    in: RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous)
                                        .stroke(isSelected ? CursorTheme.borderStrong(for: colorScheme) : CursorTheme.border(for: colorScheme).opacity(0.6), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(CursorTheme.paddingCard)
                .background(CursorTheme.surfaceRaised(for: colorScheme), in: RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous)
                        .stroke(CursorTheme.border(for: colorScheme), lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: CursorTheme.spaceM) {
                    if createProjectMode == .cloneFromGitHub {
                        VStack(alignment: .leading, spacing: CursorTheme.spaceXS) {
                            Text("Repository URL")
                                .font(.system(size: CursorTheme.fontBodySmall, weight: .medium))
                                .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                            TextField("https://github.com/owner/repo", text: $createProjectGitURL)
                                .textFieldStyle(.roundedBorder)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: CursorTheme.spaceM) {
                            Text("What should it be?")
                                .font(.system(size: CursorTheme.fontTitleLarge, weight: .semibold))
                                .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                                .frame(maxWidth: .infinity, alignment: .center)

                            Text("Pick a type, add details if you want, or let Metro surprise you.")
                                .font(.system(size: CursorTheme.fontBodySmall, weight: .regular))
                                .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                                .frame(maxWidth: .infinity, alignment: .center)

                            VStack(alignment: .leading, spacing: CursorTheme.spaceXS) {
                                HStack(spacing: CursorTheme.spaceS) {
                                    Text("Type")
                                        .font(.system(size: CursorTheme.fontBodySmall, weight: .medium))
                                        .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                                    Spacer(minLength: 0)
                                    Button {
                                        applySurpriseCreateIdea()
                                    } label: {
                                        HStack(spacing: CursorTheme.spaceXS) {
                                            Image(systemName: "sparkles")
                                                .font(.system(size: CursorTheme.fontBodySmall, weight: .semibold))
                                            Text("Surprise me")
                                                .font(.system(size: CursorTheme.fontBodySmall, weight: .semibold))
                                        }
                                        .foregroundStyle(CursorTheme.brandBlue)
                                        .padding(.horizontal, CursorTheme.spaceM)
                                        .padding(.vertical, CursorTheme.spaceXS)
                                        .background(
                                            CursorTheme.brandBlue.opacity(0.12),
                                            in: Capsule()
                                        )
                                        .overlay(
                                            Capsule()
                                                .stroke(CursorTheme.brandBlue.opacity(0.35), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: CursorTheme.spaceS) {
                                        ForEach(CreateProjectInspirationType.allCases) { type in
                                            let isSelected = createProjectSelectedType == type
                                            Button {
                                                applyCreateProjectType(type)
                                            } label: {
                                                HStack(spacing: CursorTheme.spaceXS) {
                                                    Image(systemName: type.icon)
                                                        .font(.system(size: CursorTheme.fontBodySmall, weight: .medium))
                                                    Text(type.title)
                                                        .font(.system(size: CursorTheme.fontBodySmall, weight: .semibold))
                                                }
                                                .foregroundStyle(
                                                    isSelected
                                                        ? CursorTheme.brandBlue
                                                        : CursorTheme.textPrimary(for: colorScheme)
                                                )
                                                .padding(.horizontal, CursorTheme.spaceM)
                                                .padding(.vertical, CursorTheme.spaceXS)
                                                .background(
                                                    isSelected
                                                        ? CursorTheme.brandBlue.opacity(0.12)
                                                        : CursorTheme.surfaceMuted(for: colorScheme),
                                                    in: Capsule()
                                                )
                                                .overlay(
                                                    Capsule()
                                                        .stroke(
                                                            isSelected
                                                                ? CursorTheme.brandBlue.opacity(0.35)
                                                                : CursorTheme.border(for: colorScheme),
                                                            lineWidth: 1
                                                        )
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.vertical, 1)
                                }
                            }

                            VStack(alignment: .leading, spacing: CursorTheme.spaceXS) {
                                Text("Description (optional)")
                                    .font(.system(size: CursorTheme.fontBodySmall, weight: .medium))
                                    .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))

                                TextField(
                                    createProjectIdeaPlaceholder,
                                    text: $createProjectIdea,
                                    axis: .vertical
                                )
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(4...10)
                            }

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: CursorTheme.spaceS) {
                                    ForEach(createIdeaSuggestions, id: \.self) { suggestion in
                                        Button {
                                            applyCreateIdeaSuggestion(suggestion)
                                        } label: {
                                            Text(suggestion)
                                                .font(.system(size: CursorTheme.fontBodySmall, weight: .medium))
                                                .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                                                .padding(.horizontal, CursorTheme.spaceM)
                                                .padding(.vertical, CursorTheme.spaceXS)
                                                .background(
                                                    CursorTheme.surfaceMuted(for: colorScheme),
                                                    in: Capsule()
                                                )
                                                .overlay(
                                                    Capsule()
                                                        .stroke(CursorTheme.border(for: colorScheme), lineWidth: 1)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(CursorTheme.paddingCard)
                .background(CursorTheme.surfaceRaised(for: colorScheme), in: RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous)
                        .stroke(CursorTheme.border(for: colorScheme), lineWidth: 1)
                )
                .onChange(of: createProjectIdea) { _, _ in
                    syncFolderNameFromIdeaIfNeeded()
                }

                Spacer(minLength: CursorTheme.spaceL)

                VStack(alignment: .leading, spacing: CursorTheme.spaceM) {
                    VStack(alignment: .leading, spacing: CursorTheme.spaceXS) {
                        Text("Default directory")
                            .font(.system(size: CursorTheme.fontBodySmall, weight: .medium))
                            .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                        HStack(spacing: CursorTheme.spaceS) {
                            TextField("~/dev", text: $createProjectParentPath)
                                .textFieldStyle(.roundedBorder)
                            ActionButton(
                                title: "Browse",
                                icon: "folder",
                                action: {
                                    if let p = selectFolder(
                                        title: "Choose parent folder",
                                        message: "The project is created or cloned inside this folder.",
                                        startingAt: createProjectParentPath
                                    ) {
                                        createProjectParentPath = p
                                    }
                                },
                                style: .secondary
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: CursorTheme.spaceXS) {
                        Text("Folder name")
                            .font(.system(size: CursorTheme.fontBodySmall, weight: .medium))
                            .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                        if createProjectMode == .newWithAgent {
                            TextField(
                                suggestedFolderNameFromIdea,
                                text: Binding(
                                    get: { createProjectFolderName },
                                    set: { newValue in
                                        createProjectFolderName = newValue
                                        createProjectFolderNameEditedByUser = !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            Text("Suggested from your idea or type: \(suggestedFolderNameFromIdea)")
                                .font(.system(size: CursorTheme.fontSecondary, weight: .regular))
                                .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                        } else {
                            TextField("Override cloned folder name", text: $createProjectFolderName)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    VStack(alignment: .leading, spacing: CursorTheme.spaceXS) {
                        Text("Model")
                            .font(.system(size: CursorTheme.fontBodySmall, weight: .medium))
                            .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                        ModelPickerView(
                            selectedModelId: effectiveCreateProjectModelID(),
                            models: modelPickerModels(
                                for: .cursor,
                                including: effectiveCreateProjectModelID()
                            ),
                            onSelect: { createProjectModelId = $0 }
                        )
                        Text("Used for the project setup agent.")
                            .font(.system(size: CursorTheme.fontSecondary, weight: .regular))
                            .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                    }

                    Toggle(isOn: $createProjectInitialGitCommit) {
                        Text("Create initial git commit after setup")
                            .font(.system(size: CursorTheme.fontBodySmall, weight: .medium))
                            .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                    }
                    .toggleStyle(.checkbox)

                    HStack(spacing: CursorTheme.spaceS) {
                        Spacer(minLength: 0)
                        ActionButton(
                            title: createProjectBusy ? "Working…" : (createProjectMode == .cloneFromGitHub ? "Clone & set up" : "Create & set up"),
                            icon: "wand.and.stars",
                            action: submitCreateProject,
                            isDisabled: createProjectBusy,
                            help: "Run the setup agent for `.metro/project.json` and Metro Preview",
                            style: .accent
                        )
                    }
                }
                .padding(CursorTheme.paddingCard)
                .background(CursorTheme.surfaceRaised(for: colorScheme), in: RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous)
                        .stroke(CursorTheme.border(for: colorScheme), lineWidth: 1)
                )
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(CursorTheme.paddingChrome)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Splash content (no projects)

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

                    Text("Open an existing folder, or use Create to scaffold a new app or clone from GitHub—the agent configures Preview and `.metro/project.json`.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 340)
                }

                VStack(spacing: CursorTheme.spaceM) {
                    ActionButton(
                        title: "Import",
                        icon: "folder.badge.plus",
                        action: addProject,
                        help: "Open an existing project folder",
                        style: .primary
                    )
                    .frame(maxWidth: .infinity)
                    ActionButton(
                        title: "Create",
                        icon: "wand.and.stars",
                        action: openCreateProjectPage,
                        help: "Create or clone a project and run setup",
                        style: .secondary
                    )
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: 360)
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
    private func agentStatusIcon(
        tab: AgentTab,
        status: (label: String, isProcessing: Bool, isPendingReview: Bool, isStopped: Bool, isCompleted: Bool),
        compact: Bool = false
    ) -> some View {
        let spinnerSize = compact ? CursorTheme.fontSmall : CursorTheme.fontIconList - 4
        let symbolSize = compact ? CursorTheme.fontSmall : CursorTheme.fontIconList
        if status.isProcessing {
            LightBlueSpinner(size: spinnerSize)
        } else if status.isStopped {
            Image(systemName: "square.fill")
                .font(.system(size: compact ? symbolSize - 1 : symbolSize - 2, weight: .semibold))
                .foregroundStyle(CursorTheme.semanticError)
        } else if status.isPendingReview {
            Image(systemName: "clock.fill")
                .font(.system(size: symbolSize, weight: .medium))
                .foregroundStyle(CursorTheme.semanticReview)
        } else if status.isCompleted {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: symbolSize))
                .foregroundStyle(CursorTheme.brandBlue)
        } else {
            Image(systemName: "person.crop.circle")
                .font(.system(size: symbolSize, weight: .medium))
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
                        .padding(.horizontal, CursorTheme.paddingChrome)
                        .padding(.vertical, CursorTheme.spaceM)
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
            .padding(.horizontal, CursorTheme.paddingChrome)
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
            // Keep only a small recent slice mounted by default for very long threads; within that
            // window, use a plain VStack so every row lays out up front (avoids lazy-stack blank/refocus quirks).
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
            .padding(CursorTheme.paddingChrome)
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
                    .padding(.horizontal, CursorTheme.paddingChrome)
                    .padding(.top, CursorTheme.spaceS)
                    .padding(.bottom, CursorTheme.spaceXS)
                    Rectangle()
                        .fill(CursorTheme.border(for: colorScheme))
                        .frame(height: 1)
                        .padding(.horizontal, CursorTheme.paddingChrome)
                }

                if tab.isRunning && !tab.followUpQueue.isEmpty {
                    queuedSectionContent(tab: tab)
                    Rectangle()
                        .fill(CursorTheme.border(for: colorScheme))
                        .frame(height: 1)
                        .padding(.horizontal, CursorTheme.paddingChrome)
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
                .padding(.horizontal, CursorTheme.paddingChrome)
                .padding(.vertical, CursorTheme.spaceS)
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
                    currentBranch: displayedGitBranch(for: tab),
                    onSelectBranch: { branch in
                        if branch != displayedGitBranch(for: tab) {
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
                .disabled(tab.workspacePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .onChange(of: tab.workspacePath) { _, _ in
                    refreshGitState(for: tab.workspacePath, force: true)
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
        .padding(CursorTheme.paddingChrome)
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

    /// Opens the current preview URL when configured; otherwise reveals the workspace in Finder.
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
        .padding(.horizontal, CursorTheme.paddingChrome)
        .padding(.top, CursorTheme.spaceS)
        .padding(.bottom, CursorTheme.spaceS)
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
