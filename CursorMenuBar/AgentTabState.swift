import Foundation
import Combine

// MARK: - Tab and conversation state

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
    /// Cursor CLI chat ID for this tab; set after first message so follow-ups use the same conversation.
    var cursorChatId: String?

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
