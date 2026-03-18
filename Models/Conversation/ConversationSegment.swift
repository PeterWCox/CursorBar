import Foundation

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
