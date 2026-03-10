import Foundation

// MARK: - Per-project settings (e.g. debug URL for "View in Browser")
// Stored in .cursor/project-settings.json

private struct ProjectSettingsFile: Codable {
    var debugUrl: String?
}

enum ProjectSettingsStorage {
    static func projectSettingsURL(workspacePath: String) -> URL {
        URL(fileURLWithPath: workspacePath)
            .appendingPathComponent(".cursor")
            .appendingPathComponent("project-settings.json")
    }

    static func getDebugURL(workspacePath: String) -> String? {
        let url = projectSettingsURL(workspacePath: workspacePath)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(ProjectSettingsFile.self, from: data) else {
            return nil
        }
        let trimmed = decoded.debugUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    static func setDebugURL(workspacePath: String, _ value: String?) {
        let url = projectSettingsURL(workspacePath: workspacePath)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        let newUrl = trimmed?.isEmpty == false ? trimmed : nil

        var existing = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(ProjectSettingsFile.self, from: $0) } ?? ProjectSettingsFile(debugUrl: nil)
        existing.debugUrl = newUrl

        guard let data = try? JSONEncoder().encode(existing) else { return }
        try? data.write(to: url)
    }
}
