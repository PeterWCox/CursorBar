import Foundation

// MARK: - Quick action command (configurable Fix build, Commit & push, etc.)

struct QuickActionCommand: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var prompt: String
    var icon: String  // SF Symbol name
    var scope: Scope

    enum Scope: String, Codable, CaseIterable {
        case global
        case project
    }

    init(id: UUID = UUID(), title: String, prompt: String, icon: String, scope: Scope) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.icon = icon
        self.scope = scope
    }
}

// MARK: - Default commands (same as original Fix build / Commit & push)

extension QuickActionCommand {
    static let defaultFixBuild = QuickActionCommand(
        title: "Fix build",
        prompt: """
        Fix the build. Identify and fix any compile errors, test failures, or other issues preventing the project from building successfully. Run the build (and tests if applicable) and iterate until everything passes.
        """,
        icon: "hammer.fill",
        scope: .global
    )

    static let defaultCommitAndPush = QuickActionCommand(
        title: "Commit & push",
        prompt: """
        Review the current git changes (e.g. git status and diff). Summarise them in a single, clear commit message and create one atomic commit, then push to the current branch. Only commit if the changes look intentional and ready to ship.
        """,
        icon: "square.and.arrow.up",
        scope: .global
    )

    static var defaultCommands: [QuickActionCommand] {
        [defaultFixBuild, defaultCommitAndPush]
    }
}

// MARK: - Icon picker (SF Symbols + RNG)

enum QuickActionIcons {
    static let pickerIcons: [String] = [
        "wrench.and.screwdriver",
        "arrow.up.circle",
        "hammer",
        "doc.text",
        "terminal",
        "gearshape",
        "leaf",
        "star",
        "bolt",
        "sparkles",
        "wand.and.stars",
        "paintbrush",
        "scroll",
        "checkmark.circle",
        "arrow.triangle.2.circlepath",
        "square.and.pencil",
    ]

    static var randomIcon: String {
        pickerIcons.randomElement() ?? "sparkles"
    }
}

// MARK: - Storage (global in UserDefaults, project in .cursor/quick-actions.json)

private let globalCommandsKey = "quickActionCommands_global"

enum QuickActionStorage {
    static func loadGlobalCommands() -> [QuickActionCommand] {
        guard let data = UserDefaults.standard.data(forKey: globalCommandsKey),
              let decoded = try? JSONDecoder().decode([QuickActionCommand].self, from: data) else {
            return QuickActionCommand.defaultCommands
        }
        return decoded
    }

    static func saveGlobalCommands(_ commands: [QuickActionCommand]) {
        guard let data = try? JSONEncoder().encode(commands) else { return }
        UserDefaults.standard.set(data, forKey: globalCommandsKey)
    }

    static func projectCommandsURL(workspacePath: String) -> URL {
        let url = URL(fileURLWithPath: workspacePath).appendingPathComponent(".cursor")
        return url.appendingPathComponent("quick-actions.json")
    }

    static func loadProjectCommands(workspacePath: String) -> [QuickActionCommand] {
        let url = projectCommandsURL(workspacePath: workspacePath)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([QuickActionCommand].self, from: data) else {
            return []
        }
        return decoded.map { cmd in
            var c = cmd
            if c.scope != .project { c.scope = .project }
            return c
        }
    }

    static func saveProjectCommands(workspacePath: String, _ commands: [QuickActionCommand]) {
        let url = projectCommandsURL(workspacePath: workspacePath)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let toSave = commands.map { cmd in
            var c = cmd
            c.scope = .project
            return c
        }
        guard let data = try? JSONEncoder().encode(toSave) else { return }
        try? data.write(to: url)
    }

    /// Returns global + project-specific commands for the given workspace. Project commands are last.
    static func commandsForWorkspace(workspacePath: String) -> [QuickActionCommand] {
        let global = loadGlobalCommands()
        let project = loadProjectCommands(workspacePath: workspacePath)
        return global + project
    }
}
