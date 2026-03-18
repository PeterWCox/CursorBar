import Foundation

struct ProjectState: Identifiable, Codable, Equatable {
    var path: String
    var source: ProjectSource = .manual

    var id: String { path }
}
