import Foundation

// MARK: - Conversation domain models

enum ConversationSegmentKind {
    case thinking
    case assistant
    case toolCall
}

enum ToolCallSegmentStatus {
    case running
    case completed
    case failed
}

struct ToolCallSegmentData {
    let callID: String
    var title: String
    var detail: String
    var status: ToolCallSegmentStatus
}

struct ConversationSegment: Identifiable {
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

struct ConversationTurn: Identifiable {
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

enum StreamPhase {
    case thinking
    case assistant
    case toolCall
}
