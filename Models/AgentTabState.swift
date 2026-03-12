import Foundation
import Combine

// MARK: - Persisted tab state (for save/restore across launches)

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
    var selectedTabID: UUID
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

class TabManager: ObservableObject {
    @Published var tabs: [AgentTab] = []
    @Published var selectedTabID: UUID
    /// Stack of recently closed tabs (most recent last) for "Reopen closed tab" (Cmd+Shift+T). Capped at 20.
    @Published private(set) var recentlyClosedTabs: [SavedAgentTab] = []
    private static let maxRecentlyClosedTabs = 20
    /// No longer forwarding each tab's objectWillChange — only structural changes (tabs, selectedTabID) publish.
    /// Content and sidebar chips observe their specific AgentTab to avoid re-rendering the whole window when one tab streams.
    private var tabSubscriptions: [UUID: AnyCancellable] = [:]

    init(loadedState: SavedTabState? = nil) {
        if let saved = loadedState, !saved.tabs.isEmpty {
            let restoredTabs = saved.tabs.map { AgentTab(from: $0) }
            let validSelected = saved.tabs.contains(where: { $0.id == saved.selectedTabID })
            tabs = restoredTabs
            selectedTabID = validSelected ? saved.selectedTabID : (restoredTabs.first?.id ?? UUID())
        } else {
            let first = AgentTab(title: "Agent 1")
            tabs = [first]
            selectedTabID = first.id
        }
        bindTabChanges()
    }

    /// Persist current tabs and selected tab to disk (call on quit or periodically).
    func saveState() {
        let state = SavedTabState(
            tabs: tabs.map { $0.toSaved() },
            selectedTabID: selectedTabID
        )
        TabManagerPersistence.save(state)
    }

    var activeTab: AgentTab {
        tabs.first { $0.id == selectedTabID } ?? tabs[0]
    }

    /// Adds a new tab. Its workspace is set to `lastWorkspacePath` (e.g. the active tab’s workspace) so new tabs inherit the last-focused project.
    func addTab(initialPrompt: String? = nil, lastWorkspacePath: String? = nil) {
        let path = lastWorkspacePath ?? activeTab.workspacePath
        let resolved = path.isEmpty ? FileManager.default.homeDirectoryForCurrentUser.path : path
        let tab = AgentTab(title: "Agent \(tabs.count + 1)", workspacePath: resolved)
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
            let tabToClose = tabs[index]
            recentlyClosedTabs.append(tabToClose.toSaved())
            if recentlyClosedTabs.count > Self.maxRecentlyClosedTabs {
                recentlyClosedTabs.removeFirst()
            }
            let wasSelected = selectedTabID == id
            tabs.remove(at: index)
            tabSubscriptions[id] = nil
            if wasSelected {
                let newIndex = min(index, tabs.count - 1)
                selectedTabID = tabs[newIndex].id
            }
        }
    }

    /// Reopens the most recently closed tab. Returns true if a tab was restored.
    func reopenLastClosedTab() -> Bool {
        guard let saved = recentlyClosedTabs.popLast() else { return false }
        let tab = AgentTab(from: saved)
        tabs.append(tab)
        observe(tab)
        selectedTabID = tab.id
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
}
