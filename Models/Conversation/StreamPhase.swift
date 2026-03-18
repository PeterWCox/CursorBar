import Foundation

enum StreamPhase: String, Codable, Equatable {
    case thinking
    case assistant
    case toolCall
}
