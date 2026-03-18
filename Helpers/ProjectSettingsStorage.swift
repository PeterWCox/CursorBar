import Foundation

// MARK: - Per-project settings (debug URL, startup script)
// Stored in .metro/project.json (like Cursor uses .cursor)

private struct ProjectSettingsFile: Codable {
    var debugUrl: String?
    /// Deprecated: startup script is now in scripts array. Kept for decoding old project.json.
    var startupScript: String?
    /// Commands to run when starting preview; each entry is run in its own terminal (e.g. ["npm run backend", "npm run frontend"]).
    var scripts: [String]?
    /// Optional display names for each script (e.g. ["backend", "frontend"]). Same length as scripts; used for tab/window titles.
    var scriptLabels: [String]?
    /// Instructions for the agent when debugging (e.g. "when the terminal is opened" context). Used when creating a debug agent from Preview.
    var debugInstructions: String?
}

enum ProjectSettingsStorage {
    static let didChangeNotification = Notification.Name("ProjectSettingsStorageDidChange")
    private static var cachedSettingsByWorkspace: [String: ProjectSettingsFile] = [:]
    /// File modification dates when we cached; if project.json on disk is newer, we re-read so setup agent or manual edits are visible.
    private static var cachedModDatesByWorkspace: [String: Date] = [:]

    private static func normalizedWorkspacePath(_ workspacePath: String) -> String {
        workspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func projectSettingsURL(workspacePath: String) -> URL {
        URL(fileURLWithPath: workspacePath)
            .appendingPathComponent(".metro")
            .appendingPathComponent("project.json")
    }

    /// Legacy path for migration from .cursor/project-settings.json
    private static func legacyProjectSettingsURL(workspacePath: String) -> URL {
        URL(fileURLWithPath: workspacePath)
            .appendingPathComponent(".cursor")
            .appendingPathComponent("project-settings.json")
    }

    private static func load(workspacePath: String) -> ProjectSettingsFile {
        let normalizedPath = normalizedWorkspacePath(workspacePath)
        migrateCursormetroToMetroIfNeeded(workspacePath: workspacePath)
        let url = projectSettingsURL(workspacePath: workspacePath)

        // If we have a cache, re-read from disk when project.json was modified (e.g. by Configure Setup or manual edit).
        if let cached = cachedSettingsByWorkspace[normalizedPath],
           let cachedDate = cachedModDatesByWorkspace[normalizedPath] {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let modDate = attrs[.modificationDate] as? Date,
               modDate <= cachedDate {
                return cached
            }
            cachedSettingsByWorkspace[normalizedPath] = nil
            cachedModDatesByWorkspace[normalizedPath] = nil
        }

        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(ProjectSettingsFile.self, from: data) {
            cachedSettingsByWorkspace[normalizedPath] = decoded
            cachedModDatesByWorkspace[normalizedPath] = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
            return decoded
        }
        // Migrate from legacy .cursor/project-settings.json
        let legacyURL = legacyProjectSettingsURL(workspacePath: workspacePath)
        if let data = try? Data(contentsOf: legacyURL),
           let legacy = try? JSONDecoder().decode(ProjectSettingsFile.self, from: data) {
            save(workspacePath: workspacePath, legacy)
            return legacy
        }
        let empty = ProjectSettingsFile(debugUrl: nil, startupScript: nil, scripts: nil, scriptLabels: nil, debugInstructions: nil)
        cachedSettingsByWorkspace[normalizedPath] = empty
        cachedModDatesByWorkspace[normalizedPath] = nil
        return empty
    }

    private static func save(workspacePath: String, _ file: ProjectSettingsFile) {
        let url = projectSettingsURL(workspacePath: workspacePath)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: url)
        let normalizedPath = normalizedWorkspacePath(workspacePath)
        cachedSettingsByWorkspace[normalizedPath] = file
        cachedModDatesByWorkspace[normalizedPath] = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        NotificationCenter.default.post(
            name: didChangeNotification,
            object: nil,
            userInfo: ["workspacePath": normalizedPath]
        )
    }

    // MARK: - Debug URL (View in Browser)

    static func getDebugURL(workspacePath: String) -> String? {
        let trimmed = load(workspacePath: workspacePath).debugUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    static func setDebugURL(workspacePath: String, _ value: String?) {
        var existing = load(workspacePath: workspacePath)
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        existing.debugUrl = trimmed?.isEmpty == false ? trimmed : nil
        save(workspacePath: workspacePath, existing)
    }

    // MARK: - Startup scripts (array in project.json; each run in its own terminal)

    /// Returns the array of script commands from `.metro/project.json`. Migrates from legacy startupScript or `.metro/startup.sh` if needed.
    static func getStartupScripts(workspacePath: String) -> [String] {
        var file = load(workspacePath: workspacePath)
        if let scripts = file.scripts, !scripts.isEmpty {
            return scripts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        // Migrate from legacy startupScript in project.json
        if let legacy = file.startupScript?.trimmingCharacters(in: .whitespacesAndNewlines), !legacy.isEmpty {
            file.scripts = [legacy]
            file.startupScript = nil
            save(workspacePath: workspacePath, file)
            return [legacy]
        }
        // Migrate from .metro/startup.sh
        let scriptURL = URL(fileURLWithPath: workspacePath)
            .appendingPathComponent(".metro")
            .appendingPathComponent("startup.sh")
        if let data = try? Data(contentsOf: scriptURL),
           let contents = String(data: data, encoding: .utf8),
           !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
            file.scripts = [trimmed]
            save(workspacePath: workspacePath, file)
            return [trimmed]
        }
        return []
    }

    /// Saves the scripts array to `.metro/project.json`. Does not write any .sh file.
    static func setStartupScripts(workspacePath: String, _ scripts: [String]) {
        var file = load(workspacePath: workspacePath)
        let trimmed = scripts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        file.scripts = trimmed.isEmpty ? nil : trimmed
        save(workspacePath: workspacePath, file)
    }

    /// Returns display names for each startup script (for tab and window titles). Same length as `getStartupScripts`; uses `scriptLabels` from project.json when present and valid, otherwise "1", "2", … or "Preview" for a single script.
    static func getStartupScriptDisplayLabels(workspacePath: String) -> [String] {
        let scripts = getStartupScripts(workspacePath: workspacePath)
        guard !scripts.isEmpty else { return [] }
        let raw = load(workspacePath: workspacePath).scriptLabels
        return (0..<scripts.count).map { index in
            if let labels = raw, index < labels.count {
                let label = labels[index].trimmingCharacters(in: .whitespacesAndNewlines)
                if !label.isEmpty { return label }
            }
            return scripts.count > 1 ? "\(index + 1)" : "Preview"
        }
    }

    // MARK: - Debug instructions (prefilled when creating debug agent from Preview)

    static func getDebugInstructions(workspacePath: String) -> String? {
        let trimmed = load(workspacePath: workspacePath).debugInstructions?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    static func setDebugInstructions(workspacePath: String, _ value: String?) {
        var existing = load(workspacePath: workspacePath)
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        existing.debugInstructions = trimmed?.isEmpty == false ? trimmed : nil
        save(workspacePath: workspacePath, existing)
    }
}
