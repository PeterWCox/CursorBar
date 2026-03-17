import Foundation
import Combine

// MARK: - Persisted tab state (for save/restore across launches)

struct SavedProject: Codable, Equatable {
    var path: String
}

struct SavedAgentTab: Codable {
    var id: UUID
    var title: String
    var workspacePath: String
    var currentBranch: String
    var prompt: String
    var turns: [ConversationTurn]
    var hasAttachedScreenshot: Bool
    var followUpQueue: [QueuedFollowUp]
    /// When set, this agent is linked to a project task; used to show task status (open / processing / done) in the sidebar.
    var linkedTaskID: UUID?
    /// Agent provider used for this tab (e.g. Cursor now, Claude Code later).
    var providerID: AgentProviderID
    /// Provider conversation ID; when set, used to continue the same conversation after restart.
    var conversationID: String?
    /// Model ID for this tab (e.g. "auto", "gpt-5.4-medium"). When set, used when sending; otherwise app default is used.
    var modelId: String?

    init(id: UUID, title: String, workspacePath: String, currentBranch: String, prompt: String, turns: [ConversationTurn], hasAttachedScreenshot: Bool, followUpQueue: [QueuedFollowUp], linkedTaskID: UUID? = nil, providerID: AgentProviderID = .cursor, conversationID: String? = nil, modelId: String? = nil) {
        self.id = id
        self.title = title
        self.workspacePath = workspacePath
        self.currentBranch = currentBranch
        self.prompt = prompt
        self.turns = turns
        self.hasAttachedScreenshot = hasAttachedScreenshot
        self.followUpQueue = followUpQueue
        self.linkedTaskID = linkedTaskID
        self.providerID = providerID
        self.conversationID = conversationID
        self.modelId = modelId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        workspacePath = try c.decode(String.self, forKey: .workspacePath)
        currentBranch = try c.decode(String.self, forKey: .currentBranch)
        prompt = try c.decode(String.self, forKey: .prompt)
        turns = try c.decode([ConversationTurn].self, forKey: .turns)
        hasAttachedScreenshot = try c.decode(Bool.self, forKey: .hasAttachedScreenshot)
        followUpQueue = try c.decode([QueuedFollowUp].self, forKey: .followUpQueue)
        linkedTaskID = try c.decodeIfPresent(UUID.self, forKey: .linkedTaskID)
        let rawProviderID = try c.decodeIfPresent(String.self, forKey: .providerID)
        providerID = AgentProviders.resolvedProviderID(rawProviderID ?? AgentProviderID.cursor.rawValue)
        conversationID = try c.decodeIfPresent(String.self, forKey: .conversationID)
            ?? c.decodeIfPresent(String.self, forKey: .cursorChatId)
        modelId = try c.decodeIfPresent(String.self, forKey: .modelId)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, workspacePath, currentBranch, prompt, turns, hasAttachedScreenshot, followUpQueue, linkedTaskID, providerID, conversationID, cursorChatId, modelId
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(workspacePath, forKey: .workspacePath)
        try c.encode(currentBranch, forKey: .currentBranch)
        try c.encode(prompt, forKey: .prompt)
        try c.encode(turns, forKey: .turns)
        try c.encode(hasAttachedScreenshot, forKey: .hasAttachedScreenshot)
        try c.encode(followUpQueue, forKey: .followUpQueue)
        try c.encodeIfPresent(linkedTaskID, forKey: .linkedTaskID)
        try c.encode(providerID, forKey: .providerID)
        try c.encodeIfPresent(conversationID, forKey: .conversationID)
        try c.encodeIfPresent(modelId, forKey: .modelId)
    }

    /// Streaming work cannot survive an app relaunch, so restore persisted turns as settled state.
    var restoredTurns: [ConversationTurn] {
        turns.map { turn in
            guard turn.isStreaming else { return turn }

            var restored = turn
            restored.isStreaming = false
            restored.lastStreamPhase = nil

            var didStopRunningTool = false
            for index in restored.segments.indices {
                if restored.segments[index].toolCall?.status == .running {
                    restored.segments[index].toolCall?.status = .stopped
                    didStopRunningTool = true
                }
            }

            if didStopRunningTool {
                restored.wasStopped = true
            }

            return restored
        }
    }

    var restoredLastTurnState: ConversationTurnDisplayState? {
        restoredTurns.last?.displayState
    }
}

struct SavedTabState: Codable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var tabs: [SavedAgentTab]
    var recentlyClosedTabs: [SavedAgentTab]
    var selectedTabID: UUID?
    var projects: [SavedProject]
    var selectedProjectPath: String?

    init(
        tabs: [SavedAgentTab],
        recentlyClosedTabs: [SavedAgentTab],
        selectedTabID: UUID?,
        projects: [SavedProject],
        selectedProjectPath: String?
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.tabs = tabs
        self.recentlyClosedTabs = recentlyClosedTabs
        self.selectedTabID = selectedTabID
        self.projects = projects
        self.selectedProjectPath = selectedProjectPath
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case tabs
        case recentlyClosedTabs
        case selectedTabID
        case projects
        case selectedProjectPath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        tabs = try container.decodeIfPresent([SavedAgentTab].self, forKey: .tabs) ?? []
        recentlyClosedTabs = try container.decodeIfPresent([SavedAgentTab].self, forKey: .recentlyClosedTabs) ?? []
        selectedTabID = try container.decodeIfPresent(UUID.self, forKey: .selectedTabID)
        projects = try container.decodeIfPresent([SavedProject].self, forKey: .projects) ?? []
        selectedProjectPath = try container.decodeIfPresent(String.self, forKey: .selectedProjectPath)
    }
}

// MARK: - Linked agent status (for task and sidebar display)

/// Status of agent work linked to a task. This is separate from the task lifecycle state.
enum AgentTaskState: String, Equatable {
    case none
    case todo
    case processing
    case review
    case stopped
}

enum TabManagerPersistence {
    private static let fileName = "cursor_plus_tabs.json"

    static var saveURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CursorPlus", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    static func load() -> SavedTabState? {
        let data: Data
        do {
            data = try Data(contentsOf: saveURL)
        } catch {
            return nil
        }
        guard let state = try? JSONDecoder().decode(SavedTabState.self, from: data) else {
            return nil
        }
        if state.schemaVersion < SavedTabState.currentSchemaVersion {
            try? FileManager.default.removeItem(at: saveURL)
            return nil
        }
        return state
    }

    static func save(_ state: SavedTabState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: saveURL)
    }
}

// MARK: - Tab and conversation state

/// A message queued to send as soon as the agent finishes its current response.
struct QueuedFollowUp: Identifiable, Equatable, Codable {
    let id: UUID
    var text: String
    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

/// A terminal tab: shell session in a workspace. Not persisted across launches.
class TerminalTab: ObservableObject, Identifiable {
    let id: UUID
    @Published var title: String
    let workspacePath: String

    init(id: UUID = UUID(), title: String, workspacePath: String) {
        self.id = id
        self.title = title
        self.workspacePath = workspacePath
    }
}

class AgentTab: ObservableObject, Identifiable {
    let id: UUID
    @Published var title: String
    @Published var providerID: AgentProviderID
    /// Project/workspace path for this tab. When creating a new tab, it is set to the last-used path (e.g. the active tab’s workspace).
    @Published var workspacePath: String = ""
    /// Last-known git branch for this tab’s workspace (kept in sync when tab is active or on switch).
    @Published var currentBranch: String = ""
    @Published var prompt = ""
    @Published var turns: [ConversationTurn] = []
    @Published var isRunning = false
    @Published var errorMessage: String?
    @Published var hasAttachedScreenshot = false
    @Published var scrollToken = UUID()
    /// Messages to send one-by-one as soon as the agent finishes each response.
    @Published var followUpQueue: [QueuedFollowUp] = []
    /// When set, this agent is linked to a project task; sidebar shows that task's status (open / processing / done).
    @Published var linkedTaskID: UUID?
    /// Model ID for this tab when sending (e.g. "auto"). When nil, app default is used.
    @Published var modelId: String?
    var streamTask: Task<Void, Never>?
    var activeRunID: UUID?
    var activeTurnID: UUID?
    var cachedConversationCharacterCount: Int
    var lastAutoScrollAt: TimeInterval = 0
    /// Last time we pushed a streaming UI update; used to throttle to ~100ms.
    var lastStreamUIUpdateAt: TimeInterval = 0
    /// Provider conversation ID for this tab; set after first message so follow-ups use the same conversation.
    var conversationID: String?

    /// If set, the run with this ID is a "compress context" run; when it finishes we replace context with the assistant's summary.
    var pendingCompressRunID: UUID?
    /// Set to true before sending so the next sendPrompt() marks that run as compress (used by Summarize button).
    var isCompressRequest: Bool = false

    /// Turn IDs the user has dismissed from the pinned-questions stack (not persisted).
    @Published var dismissedPinnedTurnIDs: Set<UUID> = []

    init(title: String = "Agent", workspacePath: String = "", providerID: AgentProviderID = .cursor) {
        self.id = UUID()
        self.title = title
        self.providerID = providerID
        self.workspacePath = workspacePath
        self.cachedConversationCharacterCount = 0
    }

    init(from saved: SavedAgentTab) {
        self.id = saved.id
        self.title = saved.title
        self.workspacePath = saved.workspacePath
        self.currentBranch = saved.currentBranch
        self.prompt = saved.prompt
        self.turns = saved.restoredTurns
        self.hasAttachedScreenshot = saved.hasAttachedScreenshot
        self.followUpQueue = saved.followUpQueue
        self.linkedTaskID = saved.linkedTaskID
        self.providerID = saved.providerID
        self.conversationID = saved.conversationID
        self.modelId = saved.modelId
        self.cachedConversationCharacterCount = Self.conversationCharacterCount(for: saved.restoredTurns)
    }

    func toSaved() -> SavedAgentTab {
        SavedAgentTab(
            id: id,
            title: title,
            workspacePath: workspacePath,
            currentBranch: currentBranch,
            prompt: prompt,
            turns: turns,
            hasAttachedScreenshot: hasAttachedScreenshot,
            followUpQueue: followUpQueue,
            linkedTaskID: linkedTaskID,
            providerID: providerID,
            conversationID: conversationID,
            modelId: modelId
        )
    }

    static func conversationCharacterCount(for turns: [ConversationTurn]) -> Int {
        turns.reduce(into: 0) { total, turn in
            total += turn.userPrompt.count
            total += turn.segments.reduce(into: 0) { subtotal, segment in
                subtotal += segment.text.count
            }
        }
    }
}

struct ProjectState: Identifiable, Codable, Equatable {
    var path: String

    var id: String { path }
}

class TabManager: ObservableObject {
    private static let autosaveDelay: TimeInterval = 0.35

    private struct LinkedTaskStatusSignature: Equatable {
        let linkedTaskID: UUID
        let isRunning: Bool
        let lastTurnState: ConversationTurnDisplayState?
    }

    @Published private(set) var projects: [ProjectState] = []
    @Published var tabs: [AgentTab] = []
    @Published var terminalTabs: [TerminalTab] = []
    @Published var selectedTabID: UUID?
    @Published var selectedTerminalID: UUID?
    /// When non-nil, main content shows the Tasks view for this project (instead of Agent or Terminal).
    @Published var selectedTasksViewPath: String?
    @Published var selectedProjectPath: String?
    /// Stack of recently closed tabs (most recent last) for "Reopen closed tab" (Cmd+Shift+T). Capped at 20.
    @Published private(set) var recentlyClosedTabs: [SavedAgentTab] = []
    private static let maxRecentlyClosedTabs = 20
    /// No longer forwarding each tab's objectWillChange — only structural changes (tabs, selectedTabID) publish.
    /// Content and sidebar chips observe their specific AgentTab to avoid re-rendering the whole window when one tab streams.
    private var tabSubscriptions: [UUID: AnyCancellable] = [:]
    private var linkedTaskStatusSignatures: [UUID: LinkedTaskStatusSignature] = [:]
    private var persistenceSubscriptions = Set<AnyCancellable>()
    private var pendingAutosaveWorkItem: DispatchWorkItem?
    /// Holds terminal container views so shell sessions survive MultiTerminalHostView recreation (e.g. tab/project switch).
    let terminalHostStore = TerminalHostStore()

    init(loadedState: SavedTabState? = nil) {
        if let saved = loadedState {
            let restoredTabs = saved.tabs
                .filter { $0.linkedTaskID != nil }
                .map { AgentTab(from: $0) }
            let filteredTabs = restoredTabs.filter { TabManager.workspacePathExists($0.workspacePath) }
            let restoredRecentlyClosedTabs = saved.recentlyClosedTabs
                .filter { $0.linkedTaskID != nil }
                .filter { TabManager.workspacePathExists($0.workspacePath) }
            let restoredProjects = saved.projects
                .map { ProjectState(path: $0.path) }
                .filter { TabManager.workspacePathExists($0.path) }
            let tabProjects = filteredTabs.map { ProjectState(path: $0.workspacePath) }

            tabs = filteredTabs
            recentlyClosedTabs = restoredRecentlyClosedTabs
            projects = Self.mergeProjects(savedProjects: restoredProjects, tabProjects: tabProjects)
            selectedTabID = saved.selectedTabID
            selectedProjectPath = saved.selectedProjectPath
        }
        reconcileSelection()
        bindTabChanges()
        configurePersistenceObservers()
    }

    /// True if the path exists and is a directory (project can be opened).
    private static func workspacePathExists(_ path: String) -> Bool {
        guard !path.isEmpty else { return false }
        let expanded = (path as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir) && isDir.boolValue
    }

    /// Persist current tabs and selected tab to disk (call on quit or periodically).
    func saveState() {
        let state = SavedTabState(
            tabs: tabs
                .filter { $0.linkedTaskID != nil }
                .map { $0.toSaved() },
            recentlyClosedTabs: recentlyClosedTabs
                .filter { $0.linkedTaskID != nil && Self.workspacePathExists($0.workspacePath) },
            selectedTabID: selectedTabID,
            projects: projects.map { SavedProject(path: $0.path) },
            selectedProjectPath: selectedProjectPath
        )
        TabManagerPersistence.save(state)
    }

    private func configurePersistenceObservers() {
        $projects
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleSaveState()
            }
            .store(in: &persistenceSubscriptions)

        $tabs
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleSaveState()
            }
            .store(in: &persistenceSubscriptions)

        $selectedTabID
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleSaveState()
            }
            .store(in: &persistenceSubscriptions)

        $selectedProjectPath
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleSaveState()
            }
            .store(in: &persistenceSubscriptions)
    }

    private func scheduleSaveState() {
        pendingAutosaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.saveState()
        }
        pendingAutosaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autosaveDelay, execute: workItem)
    }

    /// Current agent tab, or nil when a terminal tab, tasks view, or no tab is selected.
    var activeTab: AgentTab? {
        guard selectedTerminalID == nil, selectedTasksViewPath == nil, let selectedTabID else { return nil }
        return tabs.first { $0.id == selectedTabID }
    }

    /// Current terminal tab, or nil when an agent tab, tasks view, or no terminal is selected.
    var activeTerminalTab: TerminalTab? {
        guard selectedTasksViewPath == nil, let selectedTerminalID else { return nil }
        return terminalTabs.first { $0.id == selectedTerminalID }
    }

    var activeProjectPath: String? {
        activeTerminalTab?.workspacePath ?? activeTab?.workspacePath ?? selectedProjectPath ?? projects.first?.path
    }

    var openProjectCount: Int {
        projects.count
    }

    /// Replaces the project list with paths discovered on disk (e.g. from loadDevFolders). Keeps selectedProjectPath if it’s still in the new list.
    func setProjectsFromPaths(_ paths: [String]) {
        let normalized = paths.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { Self.workspacePathExists($0) }
        let newProjects = normalized.map { ProjectState(path: $0) }
        let validPaths = Set(normalized)
        projects = newProjects
        if let current = selectedProjectPath, !validPaths.contains(current) {
            selectedProjectPath = projects.first?.path
        }
        reconcileSelection(preferredProjectPath: selectedProjectPath)
    }

    func addProject(path: String, select: Bool = true) {
        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.workspacePathExists(normalizedPath) else { return }
        if !projects.contains(where: { $0.path == normalizedPath }) {
            projects.append(ProjectState(path: normalizedPath))
        }
        if select {
            selectedProjectPath = normalizedPath
            if let existingTab = activeTab, existingTab.workspacePath == normalizedPath {
                selectedTabID = existingTab.id
                selectedTerminalID = nil
            } else if let existingTerminal = activeTerminalTab, existingTerminal.workspacePath == normalizedPath {
                selectedTerminalID = existingTerminal.id
                selectedTabID = nil
            } else if !tabs.contains(where: { $0.id == selectedTabID && $0.workspacePath == normalizedPath }),
                      !terminalTabs.contains(where: { $0.id == selectedTerminalID && $0.workspacePath == normalizedPath }) {
                selectedTabID = nil
                selectedTerminalID = nil
            }
        }
        reconcileSelection(preferredProjectPath: normalizedPath)
    }

    func selectProject(_ path: String) {
        guard projects.contains(where: { $0.path == path }) else { return }
        selectedProjectPath = path
        if let selectedTab = activeTab, selectedTab.workspacePath == path { return }
        if let selectedTerminal = activeTerminalTab, selectedTerminal.workspacePath == path { return }
        if selectedTasksViewPath == path { return }
        if let firstTab = tabs.first(where: { $0.workspacePath == path }) {
            selectedTabID = firstTab.id
            selectedTerminalID = nil
            selectedTasksViewPath = nil
        } else if let firstTerminal = terminalTabs.first(where: { $0.workspacePath == path }) {
            selectedTerminalID = firstTerminal.id
            selectedTabID = nil
            selectedTasksViewPath = nil
        } else {
            selectedTabID = nil
            selectedTerminalID = nil
            selectedTasksViewPath = path
        }
    }

    /// Show the Tasks view for the given project (like selecting a Terminal tab).
    func showTasksView(workspacePath path: String) {
        let resolved = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard projects.contains(where: { $0.path == resolved }) else { return }
        selectedProjectPath = resolved
        selectedTasksViewPath = resolved
        selectedTabID = nil
        selectedTerminalID = nil
    }

    @discardableResult
    func selectAgentTab(id: UUID) -> Bool {
        guard let tab = tabs.first(where: { $0.id == id }) else { return false }
        selectedTabID = tab.id
        selectedTerminalID = nil
        selectedTasksViewPath = nil
        selectedProjectPath = tab.workspacePath
        return true
    }

    /// Leave Tasks view and return to Agent/Terminal selection for the current project.
    func hideTasksView() {
        selectedTasksViewPath = nil
        reconcileSelection(preferredProjectPath: selectedProjectPath)
    }

    /// Adds a new tab under the selected or supplied project. When `select` is false, the new tab is created but the current selection (e.g. Tasks view or another tab) is left unchanged.
    @discardableResult
    func addTab(initialPrompt: String? = nil, workspacePath: String? = nil, modelId: String? = nil, providerID: AgentProviderID = .cursor, select: Bool = true) -> AgentTab? {
        let path = workspacePath ?? activeProjectPath ?? activeTab?.workspacePath ?? ""
        let resolved = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.workspacePathExists(resolved) else { return nil }

        addProject(path: resolved, select: select)

        let tab = AgentTab(title: "Agent \(tabs.count + 1)", workspacePath: resolved, providerID: providerID)
        if let prompt = initialPrompt, !prompt.isEmpty {
            tab.prompt = prompt
        }
        if let modelId = modelId {
            tab.modelId = modelId
        }
        tabs.append(tab)
        observe(tab)
        if select {
            selectedTabID = tab.id
            selectedTerminalID = nil
            selectedTasksViewPath = nil
            selectedProjectPath = resolved
        }
        return tab
    }

    /// Adds a new terminal tab for the given (or current) project. Returns nil if workspace path is invalid.
    @discardableResult
    func addTerminalTab(workspacePath path: String? = nil) -> TerminalTab? {
        let resolved = (path ?? activeProjectPath ?? activeTab?.workspacePath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.workspacePathExists(resolved) else { return nil }
        addProject(path: resolved, select: true)
        let count = terminalTabs.filter { $0.workspacePath == resolved }.count + 1
        let tab = TerminalTab(title: "Terminal \(count)", workspacePath: resolved)
        terminalTabs.append(tab)
        selectedTerminalID = tab.id
        selectedTabID = nil
        selectedTasksViewPath = nil
        selectedProjectPath = resolved
        return tab
    }

    func closeTerminalTab(_ id: UUID) {
        guard let index = terminalTabs.firstIndex(where: { $0.id == id }) else { return }
        let tabToClose = terminalTabs[index]
        let wasSelected = selectedTerminalID == id
        let closedPath = tabToClose.workspacePath
        terminalTabs.remove(at: index)
        if wasSelected {
            if let replacement = terminalTabs.first(where: { $0.workspacePath == closedPath }) {
                selectedTerminalID = replacement.id
                selectedTasksViewPath = nil
            } else if let firstAgent = tabs.first(where: { $0.workspacePath == closedPath }) {
                selectedTerminalID = nil
                selectedTabID = firstAgent.id
                selectedTasksViewPath = nil
            } else {
                selectedTerminalID = nil
                selectedTasksViewPath = (selectedTasksViewPath == closedPath ? closedPath : selectedTasksViewPath)
            }
            selectedProjectPath = closedPath
        }
    }

    func closeTab(_ id: UUID) {
        if let index = tabs.firstIndex(where: { $0.id == id }) {
            let tabToClose = tabs[index]
            if let taskID = tabToClose.linkedTaskID {
                let linkedTask = ProjectTasksStorage.task(workspacePath: tabToClose.workspacePath, id: taskID)
                if linkedTask?.taskState != .completed {
                    ProjectTasksStorage.clearAgentTab(workspacePath: tabToClose.workspacePath, taskID: taskID)
                }
            }
            recentlyClosedTabs.append(tabToClose.toSaved())
            if recentlyClosedTabs.count > Self.maxRecentlyClosedTabs {
                recentlyClosedTabs.removeFirst()
            }
            let wasSelected = selectedTabID == id
            let closedProjectPath = tabToClose.workspacePath
            tabs.remove(at: index)
            tabSubscriptions[id] = nil
            linkedTaskStatusSignatures[id] = nil
            if wasSelected {
                if let replacement = tabs.first(where: { $0.workspacePath == closedProjectPath }) {
                    selectedTabID = replacement.id
                    selectedTerminalID = nil
                    selectedTasksViewPath = nil
                    selectedProjectPath = replacement.workspacePath
                } else if let firstTerminal = terminalTabs.first(where: { $0.workspacePath == closedProjectPath }) {
                    selectedTabID = nil
                    selectedTerminalID = firstTerminal.id
                    selectedTasksViewPath = nil
                    selectedProjectPath = closedProjectPath
                } else {
                    selectedTabID = nil
                    selectedTerminalID = nil
                    selectedTasksViewPath = (selectedTasksViewPath == closedProjectPath ? closedProjectPath : selectedTasksViewPath)
                    selectedProjectPath = closedProjectPath
                }
            }
            reconcileSelection(preferredProjectPath: closedProjectPath)
        }
    }

    func removeProject(_ path: String) {
        let toClose = tabs.filter { $0.workspacePath == path }
        for tab in toClose {
            if let taskID = tab.linkedTaskID {
                let linkedTask = ProjectTasksStorage.task(workspacePath: path, id: taskID)
                if linkedTask?.taskState != .completed {
                    ProjectTasksStorage.clearAgentTab(workspacePath: path, taskID: taskID)
                }
            }
            recentlyClosedTabs.append(tab.toSaved())
            if recentlyClosedTabs.count > Self.maxRecentlyClosedTabs {
                recentlyClosedTabs.removeFirst()
            }
            tabSubscriptions[tab.id] = nil
            linkedTaskStatusSignatures[tab.id] = nil
        }
        let selectedProjectWasRemoved = selectedProjectPath == path
        tabs.removeAll { $0.workspacePath == path }
        terminalTabs.removeAll { $0.workspacePath == path }
        projects.removeAll { $0.path == path }

        if selectedProjectWasRemoved {
            selectedProjectPath = nil
        }
        if selectedTasksViewPath == path {
            selectedTasksViewPath = nil
        }
        if let activeTab, activeTab.workspacePath == path {
            selectedTabID = nil
        }
        if let activeTerminal = activeTerminalTab, activeTerminal.workspacePath == path {
            selectedTerminalID = nil
        }
        reconcileSelection()
    }

    /// Reopens the most recently closed tab. Returns true if a tab was restored.
    func reopenLastClosedTab() -> Bool {
        guard let saved = recentlyClosedTabs.popLast() else { return false }
        guard saved.linkedTaskID != nil else { return false }
        guard Self.workspacePathExists(saved.workspacePath) else { return false }
        addProject(path: saved.workspacePath, select: true)
        let tab = AgentTab(from: saved)
        tabs.append(tab)
        observe(tab)
        if let taskID = tab.linkedTaskID {
            ProjectTasksStorage.assignAgentTab(workspacePath: tab.workspacePath, taskID: taskID, agentTabID: tab.id)
        }
        return selectAgentTab(id: tab.id)
    }

    /// Reopens the most recently closed tab linked to a specific task.
    func reopenLinkedTaskTab(workspacePath: String, taskID: UUID, preferredTabID: UUID? = nil) -> Bool {
        let matchIndex = recentlyClosedTabs.indices.reversed().first { index in
            let saved = recentlyClosedTabs[index]
            guard saved.workspacePath == workspacePath, saved.linkedTaskID == taskID else { return false }
            return preferredTabID == nil || saved.id == preferredTabID
        }
        guard let matchIndex else { return false }

        let saved = recentlyClosedTabs.remove(at: matchIndex)
        guard Self.workspacePathExists(saved.workspacePath) else { return false }
        addProject(path: saved.workspacePath, select: true)
        let tab = AgentTab(from: saved)
        tabs.append(tab)
        observe(tab)
        ProjectTasksStorage.assignAgentTab(workspacePath: saved.workspacePath, taskID: taskID, agentTabID: tab.id)
        return selectAgentTab(id: tab.id)
    }

    private func bindTabChanges() {
        tabs.forEach(observe)
    }

    /// We only forward tab.objectWillChange when the Tasks view is showing and this tab is linked to a task in that workspace,
    /// so the task list can update "processing" / "done" badges without re-rendering the whole window on every stream chunk.
    private func observe(_ tab: AgentTab) {
        guard tabSubscriptions[tab.id] == nil else { return }
        linkedTaskStatusSignatures[tab.id] = linkedTaskStatusSignature(for: tab)
        tabSubscriptions[tab.id] = tab.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.scheduleSaveState()
                let previousStatus = self.linkedTaskStatusSignatures[tab.id]
                let currentStatus = self.linkedTaskStatusSignature(for: tab)
                self.linkedTaskStatusSignatures[tab.id] = currentStatus
                if self.selectedTasksViewPath == tab.workspacePath,
                   previousStatus != currentStatus,
                   currentStatus != nil {
                    self.objectWillChange.send()
                }
            }
    }

    private func linkedTaskStatusSignature(for tab: AgentTab) -> LinkedTaskStatusSignature? {
        guard let linkedTaskID = tab.linkedTaskID else { return nil }
        return LinkedTaskStatusSignature(
            linkedTaskID: linkedTaskID,
            isRunning: tab.isRunning,
            lastTurnState: tab.turns.last?.displayState
        )
    }

    private func reconcileSelection(preferredProjectPath: String? = nil) {
        let validProjectPaths = Set(projects.map(\.path))
        let validTabIDs = Set(tabs.map(\.id))
        let validTerminalIDs = Set(terminalTabs.map(\.id))

        if let selectedTabID, !validTabIDs.contains(selectedTabID) {
            self.selectedTabID = nil
        }
        if let selectedTerminalID, !validTerminalIDs.contains(selectedTerminalID) {
            self.selectedTerminalID = nil
        }
        if let selectedProjectPath, !validProjectPaths.contains(selectedProjectPath) {
            self.selectedProjectPath = nil
        }

        if let activeTab {
            selectedProjectPath = activeTab.workspacePath
            return
        }
        if let activeTerminalTab {
            selectedProjectPath = activeTerminalTab.workspacePath
            return
        }

        if let preferredProjectPath, validProjectPaths.contains(preferredProjectPath) {
            selectedProjectPath = preferredProjectPath
            if activeTab == nil, activeTerminalTab == nil, selectedTasksViewPath != preferredProjectPath {
                selectedTasksViewPath = preferredProjectPath
            }
            return
        }

        if selectedProjectPath == nil {
            selectedProjectPath = projects.first?.path
        }

        if let path = selectedProjectPath, activeTab == nil, activeTerminalTab == nil, selectedTasksViewPath != path {
            selectedTasksViewPath = path
        }
    }

    private static func mergeProjects(savedProjects: [ProjectState], tabProjects: [ProjectState]) -> [ProjectState] {
        var merged: [ProjectState] = []
        for project in savedProjects + tabProjects where !project.path.isEmpty {
            if !merged.contains(where: { $0.path == project.path }) {
                merged.append(project)
            }
        }
        return merged
    }
}
