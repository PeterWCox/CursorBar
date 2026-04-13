import Foundation

struct SavedTabState: Codable {
    static let currentSchemaVersion = 3

    var schemaVersion: Int
    var tabs: [SavedAgentTab]
    var recentlyClosedTabs: [SavedAgentTab]
    var selectedTabID: UUID?
    var projects: [SavedProject]
    var selectedProjectPath: String?

    init(
        tabs: [SavedAgentTab],
        recentlyClosedTabs: [SavedAgentTab],
        selectedTabID: UUID?,
        projects: [SavedProject],
        selectedProjectPath: String?
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.tabs = tabs
        self.recentlyClosedTabs = recentlyClosedTabs
        self.selectedTabID = selectedTabID
        self.projects = projects
        self.selectedProjectPath = selectedProjectPath
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
        _ = try container.decodeIfPresent(Bool.self, forKey: .selectedAddProjectView)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(tabs, forKey: .tabs)
        try container.encode(recentlyClosedTabs, forKey: .recentlyClosedTabs)
        try container.encode(selectedTabID, forKey: .selectedTabID)
        try container.encode(projects, forKey: .projects)
        try container.encode(selectedProjectPath, forKey: .selectedProjectPath)
    }
}
