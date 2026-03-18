import Foundation

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

extension ConversationTurn {
    var displayState: ConversationTurnDisplayState {
        if isStreaming {
            return .processing
        }

        if wasStopped == true {
            return .stopped
        }

        if segments.contains(where: { $0.toolCall?.status == .stopped }) {
            return .stopped
        }

        return .completed
    }
}
