import Foundation

struct ToolCallSegmentData: Codable, Equatable {
    let callID: String
    var title: String
    var detail: String
    var status: ToolCallSegmentStatus
}
