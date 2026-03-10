import Foundation

enum AppPreferences {
    static let projectsRootPathKey = "projectsRootPath"
    static let preferredTerminalAppKey = "preferredTerminalApp"

    static var defaultProjectsRootPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("dev")
            .path
    }

    static func resolvedProjectsRootPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let expanded = (trimmed as NSString).expandingTildeInPath
        return expanded.isEmpty ? defaultProjectsRootPath : expanded
    }
}
