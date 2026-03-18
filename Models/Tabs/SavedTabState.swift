import Foundation

struct SavedTabState: Codable {
    static let currentSchemaVersion = 3

    var schemaVersion: Int
    var tabs: [SavedAgentTab]
    var recentlyClosedTabs: [SavedAgentTab]
    var selectedTabID: UUID?
    var projects: [SavedProject]
    var selectedProjectPath: String?
    var selectedAddProjectView: Bool

    init(
        tabs: [SavedAgentTab],
        recentlyClosedTabs: [SavedAgentTab],
        selectedTabID: UUID?,
        projects: [SavedProject],
        selectedProjectPath: String?,
        selectedAddProjectView: Bool
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.tabs = tabs
        self.recentlyClosedTabs = recentlyClosedTabs
        self.selectedTabID = selectedTabID
        self.projects = projects
        self.selectedProjectPath = selectedProjectPath
        self.selectedAddProjectView = selectedAddProjectView
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case tabs
        case recentlyClosedTabs
        case selectedTabID
        case projects
        case selectedProjectPath
        case selectedAddProjectView
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        tabs = try container.decodeIfPresent([SavedAgentTab].self, forKey: .tabs) ?? []
        recentlyClosedTabs = try container.decodeIfPresent([SavedAgentTab].self, forKey: .recentlyClosedTabs) ?? []
        selectedTabID = try container.decodeIfPresent(UUID.self, forKey: .selectedTabID)
        projects = try container.decodeIfPresent([SavedProject].self, forKey: .projects) ?? []
        selectedProjectPath = try container.decodeIfPresent(String.self, forKey: .selectedProjectPath)
        selectedAddProjectView = try container.decodeIfPresent(Bool.self, forKey: .selectedAddProjectView) ?? false
    }
}
