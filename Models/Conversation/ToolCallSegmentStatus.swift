import Foundation

enum ToolCallSegmentStatus: String, Codable, Equatable {
    case running
    case completed
    case failed
    case stopped
}
