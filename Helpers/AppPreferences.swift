import Foundation
import SwiftUI

/// User preference for app appearance: dark, light, or follow system.
enum PreferredAppearance: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// Resolves to a concrete color scheme when combined with the current system preference.
    func resolvedScheme(systemScheme: ColorScheme) -> ColorScheme {
        switch self {
        case .system: return systemScheme
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AppPreferences {
    static let projectsRootPathKey = "projectsRootPath"
    static let projectScanRootsKey = "projectScanRoots"
    static let preferredTerminalAppKey = "preferredTerminalApp"
    static let preferredAppearanceKey = "preferredAppearance"
    /// Key for placing the agent tabs sidebar and logo on the right (mirrored layout). Persisted via UserDefaults.
    static let sidebarOnRightKey = "sidebarOnRight"
    /// Popout window: project list sidebar width (points). Persisted via UserDefaults.
    static let sidebarWidthKey = "sidebarWidthPoints"
    static let defaultSidebarWidth: Double = 340
    /// Key for model IDs to hide from the model picker. Persisted via UserDefaults when used with @AppStorage.
    static let disabledModelIdsKey = "disabledModelIds"
    /// Default value: no models disabled, so all models are shown in the picker.
    static let defaultDisabledModelIdsRaw: String = ""
    /// Key for the default model used for new tasks/agents (e.g. "auto"). Persisted via UserDefaults when used with @AppStorage.
    static let defaultModelIdKey = "defaultModelId"
    /// Default value for default model: "auto" (Auto model).
    static let defaultDefaultModelId: String = "auto"
    /// Key for project paths to hide from the agent sidebar. Persisted via UserDefaults when used with @AppStorage.
    static let hiddenProjectPathsKey = "hiddenProjectPaths"
    /// Default value: no projects hidden, so all projects are shown in the sidebar.
    static let defaultHiddenProjectPathsRaw: String = ""
    /// Default appearance: follow system light/dark.
    static let defaultPreferredAppearance: String = PreferredAppearance.system.rawValue

    static var defaultProjectsRootPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("dev")
            .path
    }

    static var defaultProjectScanRoots: [String] {
        [defaultProjectsRootPath]
    }

    static let defaultProjectScanRootsRaw: String = ""

    static func resolvedProjectsRootPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let expanded = (trimmed as NSString).expandingTildeInPath
        return expanded.isEmpty ? defaultProjectsRootPath : expanded
    }

    static func projectScanRoots(from raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var seen = Set<String>()
        return trimmed
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { ($0 as NSString).expandingTildeInPath }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

    static func rawFrom(projectScanRoots roots: [String]) -> String {
        var seen = Set<String>()
        return roots
            .map { normalizedProjectPath($0) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
            .joined(separator: ",")
    }

    /// Resolves stored scan roots. When raw is non-empty, returns parsed roots.
    /// When raw is empty, returns [] so the user can have zero folders (e.g. to simulate out-of-box state).
    /// Legacy fallback is no longer used so "Remove" on the last folder actually clears the list.
    static func resolvedProjectScanRoots(raw: String, legacyRootPath: String) -> [String] {
        projectScanRoots(from: raw)
    }

    static func preferredProjectBrowserRoot(raw: String, legacyRootPath: String) -> String {
        resolvedProjectScanRoots(raw: raw, legacyRootPath: legacyRootPath).first ?? defaultProjectsRootPath
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

    /// Effective disabled set: when raw is empty (first run), only the provider's default-enabled models remain visible.
    static func effectiveDisabledModelIds(
        allIds: Set<String>,
        raw: String,
        defaultEnabledModelIds: Set<String>,
        defaultModelID: String
    ) -> Set<String> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let enabled = defaultEnabledModelIds.union([defaultModelID])
            return allIds.subtracting(enabled)
        }
        return disabledModelIds(from: raw)
    }

    /// Parses the stored hidden project paths string (comma-separated, normalized) into a set.
    static func hiddenProjectPaths(from raw: String) -> Set<String> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return Set(trimmed.split(separator: ",").map { path in
            String(path).trimmingCharacters(in: .whitespaces)
        }.map(normalizedProjectPath).filter { !$0.isEmpty })
    }

    /// Serializes a set of hidden project paths to the stored string format (normalized).
    static func rawFrom(hiddenPaths: Set<String>) -> String {
        hiddenPaths.map(normalizedProjectPath).filter { !$0.isEmpty }.sorted().joined(separator: ",")
    }

    /// Normalizes a project path for storage and comparison (e.g. expand tilde).
    static func normalizedProjectPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return (trimmed as NSString).expandingTildeInPath
    }

    /// Current default model ID for new tasks/agents (e.g. "auto"). Used when a tab or task has no explicit model set.
    static var defaultModelId: String {
        get {
            UserDefaults.standard.string(forKey: defaultModelIdKey) ?? defaultDefaultModelId
        }
        set {
            UserDefaults.standard.set(newValue, forKey: defaultModelIdKey)
        }
    }
}
