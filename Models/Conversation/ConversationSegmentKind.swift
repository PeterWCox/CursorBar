import Foundation

enum ConversationSegmentKind: String, Codable, Equatable {
    case thinking
    case assistant
    case toolCall
}
