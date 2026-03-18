import Foundation
import Combine

class AgentTab: ObservableObject, Identifiable {
    let id: UUID
    @Published var title: String
    @Published var providerID: AgentProviderID
    @Published var workspacePath: String = ""
    @Published var currentBranch: String = ""
    @Published var prompt = ""
    @Published var turns: [ConversationTurn] = []
    @Published var isRunning = false
    @Published var errorMessage: String?
    @Published var hasAttachedScreenshot = false
    @Published var scrollToken = UUID()
    @Published var followUpQueue: [QueuedFollowUp] = []
    @Published var linkedTaskID: UUID?
    @Published var modelId: String?
    var streamTask: Task<Void, Never>?
    var activeRunID: UUID?
    var activeTurnID: UUID?
    var cachedConversationCharacterCount: Int
    var lastAutoScrollAt: TimeInterval = 0
    var lastStreamUIUpdateAt: TimeInterval = 0
    var conversationID: String?
    var pendingCompressRunID: UUID?
    var isCompressRequest: Bool = false
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
