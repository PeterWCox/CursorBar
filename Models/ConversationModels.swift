import Foundation

// MARK: - Conversation domain models

enum ConversationSegmentKind: String, Codable, Equatable {
    case thinking
    case assistant
    case toolCall
}

enum ToolCallSegmentStatus: String, Codable, Equatable {
    case running
    case completed
    case failed
    case stopped
}

struct ToolCallSegmentData: Codable, Equatable {
    let callID: String
    var title: String
    var detail: String
    var status: ToolCallSegmentStatus
}

struct ConversationSegment: Identifiable, Codable, Equatable {
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

struct ConversationTurn: Identifiable, Codable, Equatable {
    let id: UUID
    let userPrompt: String
    var segments: [ConversationSegment]
    var isStreaming: Bool
    var lastStreamPhase: StreamPhase?
    var wasStopped: Bool?

    init(
        id: UUID = UUID(),
        userPrompt: String,
        segments: [ConversationSegment] = [],
        isStreaming: Bool = false,
        lastStreamPhase: StreamPhase? = nil,
        wasStopped: Bool? = false
    ) {
        self.id = id
        self.userPrompt = userPrompt
        self.segments = segments
        self.isStreaming = isStreaming
        self.lastStreamPhase = lastStreamPhase
        self.wasStopped = wasStopped
    }
}

enum StreamPhase: String, Codable, Equatable {
    case thinking
    case assistant
    case toolCall
}

enum ConversationTurnDisplayState: Equatable {
    case processing
    case completed
    case stopped
}

extension ConversationTurn {
    var displayState: ConversationTurnDisplayState {
        if isStreaming {
            return .processing
        }

        if wasStopped == true {
            return .stopped
        }

        return .completed
    }
}
