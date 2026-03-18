import Foundation

struct SavedProject: Codable, Equatable {
    var path: String
    var source: ProjectSource

    init(path: String, source: ProjectSource = .manual) {
        self.path = path
        self.source = source
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        source = try container.decodeIfPresent(ProjectSource.self, forKey: .source) ?? .manual
    }
}
