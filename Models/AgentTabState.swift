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
}

struct SavedTabState: Codable {
    var tabs: [SavedAgentTab]
    var selectedTabID: UUID?
    var projects: [SavedProject]
    var selectedProjectPath: String?

    init(
        tabs: [SavedAgentTab],
        selectedTabID: UUID?,
        projects: [SavedProject],
        selectedProjectPath: String?
    ) {
        self.tabs = tabs
        self.selectedTabID = selectedTabID
        self.projects = projects
        self.selectedProjectPath = selectedProjectPath
    }

    private enum CodingKeys: String, CodingKey {
        case tabs
        case selectedTabID
        case projects
        case selectedProjectPath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tabs = try container.decodeIfPresent([SavedAgentTab].self, forKey: .tabs) ?? []
        selectedTabID = try container.decodeIfPresent(UUID.self, forKey: .selectedTabID)
        projects = try container.decodeIfPresent([SavedProject].self, forKey: .projects) ?? []
        selectedProjectPath = try container.decodeIfPresent(String.self, forKey: .selectedProjectPath)
    }
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
        return try? JSONDecoder().decode(SavedTabState.self, from: data)
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

class AgentTab: ObservableObject, Identifiable {
    let id: UUID
    @Published var title: String
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
    var streamTask: Task<Void, Never>?
    var activeRunID: UUID?
    var activeTurnID: UUID?
    var cachedConversationCharacterCount: Int
    var lastAutoScrollAt: TimeInterval = 0
    /// Last time we pushed a streaming UI update; used to throttle to ~100ms.
    var lastStreamUIUpdateAt: TimeInterval = 0
    /// Cursor CLI chat ID for this tab; set after first message so follow-ups use the same conversation.
    var cursorChatId: String?

    /// If set, the run with this ID is a "compress context" run; when it finishes we replace context with the assistant's summary.
    var pendingCompressRunID: UUID?
    /// Set to true before sending so the next sendPrompt() marks that run as compress (used by Summarize button).
    var isCompressRequest: Bool = false

    /// Turn IDs the user has dismissed from the pinned-questions stack (not persisted).
    @Published var dismissedPinnedTurnIDs: Set<UUID> = []

    init(title: String = "Agent", workspacePath: String = "") {
        self.id = UUID()
        self.title = title
        self.workspacePath = workspacePath
        self.cachedConversationCharacterCount = 0
    }

    init(from saved: SavedAgentTab) {
        self.id = saved.id
        self.title = saved.title
        self.workspacePath = saved.workspacePath
        self.currentBranch = saved.currentBranch
        self.prompt = saved.prompt
        self.turns = saved.turns
        self.hasAttachedScreenshot = saved.hasAttachedScreenshot
        self.followUpQueue = saved.followUpQueue
        self.cachedConversationCharacterCount = Self.conversationCharacterCount(for: saved.turns)
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
            followUpQueue: followUpQueue
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
    @Published private(set) var projects: [ProjectState] = []
    @Published var tabs: [AgentTab] = []
    @Published var selectedTabID: UUID?
    @Published var selectedProjectPath: String?
    /// Stack of recently closed tabs (most recent last) for "Reopen closed tab" (Cmd+Shift+T). Capped at 20.
    @Published private(set) var recentlyClosedTabs: [SavedAgentTab] = []
    private static let maxRecentlyClosedTabs = 20
    /// No longer forwarding each tab's objectWillChange — only structural changes (tabs, selectedTabID) publish.
    /// Content and sidebar chips observe their specific AgentTab to avoid re-rendering the whole window when one tab streams.
    private var tabSubscriptions: [UUID: AnyCancellable] = [:]

    init(loadedState: SavedTabState? = nil) {
        if let saved = loadedState {
            let restoredTabs = saved.tabs.map { AgentTab(from: $0) }
            let filteredTabs = restoredTabs.filter { TabManager.workspacePathExists($0.workspacePath) }
            let restoredProjects = saved.projects
                .map { ProjectState(path: $0.path) }
                .filter { TabManager.workspacePathExists($0.path) }
            let tabProjects = filteredTabs.map { ProjectState(path: $0.workspacePath) }

            tabs = filteredTabs
            projects = Self.mergeProjects(savedProjects: restoredProjects, tabProjects: tabProjects)
            selectedTabID = saved.selectedTabID
            selectedProjectPath = saved.selectedProjectPath
        }
        reconcileSelection()
        bindTabChanges()
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
            tabs: tabs.map { $0.toSaved() },
            selectedTabID: selectedTabID,
            projects: projects.map { SavedProject(path: $0.path) },
            selectedProjectPath: selectedProjectPath
        )
        TabManagerPersistence.save(state)
    }

    /// Current tab, or nil when there are no tabs (splash state).
    var activeTab: AgentTab? {
        guard let selectedTabID else { return nil }
        return tabs.first { $0.id == selectedTabID }
    }

    var activeProjectPath: String? {
        activeTab?.workspacePath ?? selectedProjectPath ?? projects.first?.path
    }

    var openProjectCount: Int {
        projects.count
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
            } else if !tabs.contains(where: { $0.id == selectedTabID && $0.workspacePath == normalizedPath }) {
                selectedTabID = nil
            }
        }
        reconcileSelection(preferredProjectPath: normalizedPath)
    }

    func selectProject(_ path: String) {
        guard projects.contains(where: { $0.path == path }) else { return }
        selectedProjectPath = path
        if let selectedTab = activeTab, selectedTab.workspacePath == path {
            return
        }
        if let firstTab = tabs.first(where: { $0.workspacePath == path }) {
            selectedTabID = firstTab.id
        } else {
            selectedTabID = nil
        }
    }

    /// Adds a new tab under the selected or supplied project.
    @discardableResult
    func addTab(initialPrompt: String? = nil, workspacePath: String? = nil) -> AgentTab? {
        let path = workspacePath ?? activeProjectPath ?? activeTab?.workspacePath ?? ""
        let resolved = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.workspacePathExists(resolved) else { return nil }

        addProject(path: resolved, select: true)

        let tab = AgentTab(title: "Agent \(tabs.count + 1)", workspacePath: resolved)
        if let prompt = initialPrompt, !prompt.isEmpty {
            tab.prompt = prompt
        }
        tabs.append(tab)
        observe(tab)
        selectedTabID = tab.id
        selectedProjectPath = resolved
        return tab
    }

    func closeTab(_ id: UUID) {
        if let index = tabs.firstIndex(where: { $0.id == id }) {
            let tabToClose = tabs[index]
            recentlyClosedTabs.append(tabToClose.toSaved())
            if recentlyClosedTabs.count > Self.maxRecentlyClosedTabs {
                recentlyClosedTabs.removeFirst()
            }
            let wasSelected = selectedTabID == id
            let closedProjectPath = tabToClose.workspacePath
            tabs.remove(at: index)
            tabSubscriptions[id] = nil
            if wasSelected {
                if let replacement = tabs.first(where: { $0.workspacePath == closedProjectPath }) {
                    selectedTabID = replacement.id
                    selectedProjectPath = replacement.workspacePath
                } else {
                    selectedTabID = nil
                    selectedProjectPath = closedProjectPath
                }
            }
            reconcileSelection(preferredProjectPath: closedProjectPath)
        }
    }

    func removeProject(_ path: String) {
        let toClose = tabs.filter { $0.workspacePath == path }
        for tab in toClose {
            recentlyClosedTabs.append(tab.toSaved())
            if recentlyClosedTabs.count > Self.maxRecentlyClosedTabs {
                recentlyClosedTabs.removeFirst()
            }
            tabSubscriptions[tab.id] = nil
        }
        let selectedProjectWasRemoved = selectedProjectPath == path
        tabs.removeAll { $0.workspacePath == path }
        projects.removeAll { $0.path == path }

        if selectedProjectWasRemoved {
            selectedProjectPath = nil
        }
        if let activeTab, activeTab.workspacePath == path {
            selectedTabID = nil
        }
        reconcileSelection()
    }

    /// Reopens the most recently closed tab. Returns true if a tab was restored.
    func reopenLastClosedTab() -> Bool {
        guard let saved = recentlyClosedTabs.popLast() else { return false }
        guard Self.workspacePathExists(saved.workspacePath) else { return false }
        addProject(path: saved.workspacePath, select: true)
        let tab = AgentTab(from: saved)
        tabs.append(tab)
        observe(tab)
        selectedTabID = tab.id
        selectedProjectPath = tab.workspacePath
        return true
    }

    private func bindTabChanges() {
        tabs.forEach(observe)
    }

    /// Subscriptions are kept for potential future use (e.g. persistence triggers). We intentionally do *not*
    /// forward tab.objectWillChange to TabManager so that streaming in one tab doesn't invalidate the whole UI.
    private func observe(_ tab: AgentTab) {
        guard tabSubscriptions[tab.id] == nil else { return }
        tabSubscriptions[tab.id] = tab.objectWillChange.sink { _ in
            // No-op: do not call self?.objectWillChange.send(). Views that need tab updates observe the tab directly.
        }
    }

    private func reconcileSelection(preferredProjectPath: String? = nil) {
        let validProjectPaths = Set(projects.map(\.path))
        let validTabIDs = Set(tabs.map(\.id))

        if let selectedTabID, !validTabIDs.contains(selectedTabID) {
            self.selectedTabID = nil
        }
        if let selectedProjectPath, !validProjectPaths.contains(selectedProjectPath) {
            self.selectedProjectPath = nil
        }

        if let activeTab {
            selectedProjectPath = activeTab.workspacePath
            return
        }

        if let preferredProjectPath, validProjectPaths.contains(preferredProjectPath) {
            selectedProjectPath = preferredProjectPath
            return
        }

        if selectedProjectPath == nil {
            selectedProjectPath = projects.first?.path
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
