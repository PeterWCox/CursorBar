import Foundation

struct SavedAgentTab: Codable {
    var id: UUID
    var title: String
    var workspacePath: String
    var currentBranch: String
    var prompt: String
    var turns: [ConversationTurn]
    var hasAttachedScreenshot: Bool
    var followUpQueue: [QueuedFollowUp]
    var linkedTaskID: UUID?
    var providerID: AgentProviderID
    var conversationID: String?
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
