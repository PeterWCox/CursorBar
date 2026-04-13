import Foundation

/// A message queued to send as soon as the agent finishes its current response.
struct QueuedFollowUp: Identifiable, Equatable, Codable {
    let id: UUID
    var text: String
    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}
