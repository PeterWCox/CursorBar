import Foundation

enum AppPreferences {
    static let projectsRootPathKey = "projectsRootPath"
    static let preferredTerminalAppKey = "preferredTerminalApp"
    /// Key for model IDs to hide from the model picker. Persisted via UserDefaults when used with @AppStorage.
    static let disabledModelIdsKey = "disabledModelIds"
    /// Default value: no models disabled, so all models are shown in the picker.
    static let defaultDisabledModelIdsRaw: String = ""

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

    /// Parses the stored disabled model IDs string (comma-separated) into a set. Empty or missing value → all models shown.
    static func disabledModelIds(from raw: String) -> Set<String> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return Set(trimmed.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    /// Serializes a set of disabled model IDs to the stored string format.
    static func rawFrom(disabledIds: Set<String>) -> String {
        disabledIds.sorted().joined(separator: ",")
    }
}
