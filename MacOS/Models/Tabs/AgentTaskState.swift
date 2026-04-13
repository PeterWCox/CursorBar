import Foundation

/// Status of agent work linked to a task. This is separate from the task lifecycle state.
enum AgentTaskState: String, Equatable {
    case none
    case todo
    case processing
    case review
    case stopped
}
