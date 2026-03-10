import Foundation

// MARK: - Conversation domain models

enum ConversationSegmentKind: String, Codable {
    case thinking
    case assistant
    case toolCall
}

enum ToolCallSegmentStatus: String, Codable {
    case running
    case completed
    case failed
}

struct ToolCallSegmentData: Codable {
    let callID: String
    var title: String
    var detail: String
    var status: ToolCallSegmentStatus
}

struct ConversationSegment: Identifiable, Codable {
    let id: UUID
    let kind: ConversationSegmentKind
    var text: String
    var toolCall: ToolCallSegmentData?

    init(id: UUID = UUID(), kind: ConversationSegmentKind, text: String) {
        self.id = id
        self.kind = kind
        self.text = text
        toolCall = nil
    }

    init(id: UUID = UUID(), toolCall: ToolCallSegmentData) {
        self.id = id
        kind = .toolCall
        text = ""
        self.toolCall = toolCall
    }
}

struct ConversationTurn: Identifiable, Codable {
    let id: UUID
    let userPrompt: String
    var segments: [ConversationSegment]
    var isStreaming: Bool
    var lastStreamPhase: StreamPhase?

    init(
        id: UUID = UUID(),
        userPrompt: String,
        segments: [ConversationSegment] = [],
        isStreaming: Bool = false,
        lastStreamPhase: StreamPhase? = nil
    ) {
        self.id = id
        self.userPrompt = userPrompt
        self.segments = segments
        self.isStreaming = isStreaming
        self.lastStreamPhase = lastStreamPhase
    }
}

enum StreamPhase: String, Codable {
    case thinking
    case assistant
    case toolCall
}
