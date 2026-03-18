import Foundation
import Combine

/// A terminal tab: shell session in a workspace. Not persisted across launches.
class TerminalTab: ObservableObject, Identifiable {
    let id: UUID
    @Published var title: String
    let workspacePath: String
    var initialCommand: String?
    var isDashboardTab: Bool

    init(id: UUID = UUID(), title: String, workspacePath: String, initialCommand: String? = nil, isDashboardTab: Bool = false) {
        self.id = id
        self.title = title
        self.workspacePath = workspacePath
        self.initialCommand = initialCommand
        self.isDashboardTab = isDashboardTab
    }
}
