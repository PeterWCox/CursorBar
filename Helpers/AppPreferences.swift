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
    static let preferredTerminalAppKey = "preferredTerminalApp"
    static let preferredAppearanceKey = "preferredAppearance"
    /// Key for placing the agent tabs sidebar and logo on the right (mirrored layout). Persisted via UserDefaults.
    static let sidebarOnRightKey = "sidebarOnRight"
    /// Key for forcing the agent CLI to allow commands without prompting (CLI -f / --force). Default: false.
    static let agentForceAllowCommandsKey = "agentForceAllowCommands"
    /// Key for model IDs to hide from the model picker. Persisted via UserDefaults when used with @AppStorage.
    static let disabledModelIdsKey = "disabledModelIds"
    /// Default value: no models disabled, so all models are shown in the picker.
    static let defaultDisabledModelIdsRaw: String = ""
    /// Default appearance: follow system light/dark.
    static let defaultPreferredAppearance: String = PreferredAppearance.system.rawValue

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

    /// Effective disabled set: when raw is empty (first run), only default-enabled models (+ auto) are visible.
    static func effectiveDisabledModelIds(allIds: Set<String>, raw: String) -> Set<String> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let enabled = AvailableModels.defaultEnabledModelIds.union([AvailableModels.autoID])
            return allIds.subtracting(enabled)
        }
        return disabledModelIds(from: raw)
    }
}
