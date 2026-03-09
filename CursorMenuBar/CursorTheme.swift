import SwiftUI

// MARK: - Design system and app constants

enum CursorTheme {
    static let chrome = Color(red: 0.055, green: 0.059, blue: 0.075)
    static let panel = Color(red: 0.082, green: 0.086, blue: 0.106)
    static let surface = Color(red: 0.118, green: 0.122, blue: 0.145)
    static let surfaceRaised = Color(red: 0.145, green: 0.149, blue: 0.176)
    static let surfaceMuted = Color(red: 0.099, green: 0.103, blue: 0.123)
    static let editor = Color(red: 0.148, green: 0.152, blue: 0.178)
    static let border = Color.white.opacity(0.08)
    static let borderStrong = Color.white.opacity(0.13)
    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.42)
    static let brandBlue = Color(red: 0.40, green: 0.61, blue: 1.00)
    static let brandPurple = Color(red: 0.55, green: 0.40, blue: 0.98)
    static let brandAmber = Color(red: 0.98, green: 0.76, blue: 0.31)
    static let cursorPlusTeal = Color(red: 0.0, green: 0.83, blue: 0.71)

    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [brandBlue, brandPurple],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var panelGradient: LinearGradient {
        LinearGradient(
            colors: [panel, chrome],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// Model options for the Cursor agent (id for CLI, label for UI).
enum AvailableModels {
    static let all: [(id: String, label: String)] = [
        ("composer-1.5", "Composer 1.5"),
        ("composer-1", "Composer 1"),
        ("auto", "Auto"),
        ("opus-4.6-thinking", "Claude 4.6 Opus (Thinking)"),
        ("sonnet-4.6-thinking", "Claude 4.6 Sonnet (Thinking)"),
        ("sonnet-4.6", "Claude 4.6 Sonnet"),
        ("gpt-5.4-high", "GPT-5.4 High"),
        ("gpt-5.4-medium", "GPT-5.4"),
        ("gemini-3.1-pro", "Gemini 3.1 Pro"),
    ]
}

/// Predefined quick-action prompts.
enum QuickActionPrompts {
    static let fixBuild = """
    Fix the build. Identify and fix any compile errors, test failures, or other issues preventing the project from building successfully. Run the build (and tests if applicable) and iterate until everything passes.
    """

    static let commitAndPush = """
    Review the current git changes (e.g. git status and diff). Summarise them in a single, clear commit message and create one atomic commit, then push to the current branch. Only commit if the changes look intentional and ready to ship.
    """
}

/// Limits used for context and screenshots.
enum AppLimits {
    static let maxScreenshots = 3
    /// Approximate token count for context (Cursor CLI). ~4 chars per token.
    static let contextTokenLimit = 128_000
    /// Included API requests per month (Cursor Pro typical). Used for usage %.
    static let includedAPIQuota = 500
}

/// Dev folder path for workspace picker.
let devFolderPath = "/Users/petercox/dev"
