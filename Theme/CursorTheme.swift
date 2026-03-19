import SwiftUI

// MARK: - Design system and app constants

enum CursorTheme {
    // Dark palette (default)
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

    // Light palette
    private static let chromeLight = Color(red: 0.96, green: 0.96, blue: 0.97)
    private static let panelLight = Color(red: 0.94, green: 0.94, blue: 0.96)
    private static let surfaceLight = Color(red: 1.0, green: 1.0, blue: 1.0)
    private static let surfaceRaisedLight = Color(red: 0.97, green: 0.97, blue: 0.98)
    private static let surfaceMutedLight = Color(red: 0.96, green: 0.96, blue: 0.98)
    private static let editorLight = Color(red: 0.98, green: 0.98, blue: 0.99)
    private static let borderLight = Color.black.opacity(0.12)
    private static let borderStrongLight = Color.black.opacity(0.20)
    private static let textPrimaryLight = Color.black.opacity(0.90)
    private static let textSecondaryLight = Color.black.opacity(0.65)
    private static let textTertiaryLight = Color.black.opacity(0.50)

    /// Returns the semantic color for the given color scheme. Use in views with `@Environment(\.colorScheme)`.
    static func chrome(for colorScheme: ColorScheme) -> Color { colorScheme == .dark ? chrome : chromeLight }
    static func panel(for colorScheme: ColorScheme) -> Color { colorScheme == .dark ? panel : panelLight }
    static func surface(for colorScheme: ColorScheme) -> Color { colorScheme == .dark ? surface : surfaceLight }
    static func surfaceRaised(for colorScheme: ColorScheme) -> Color { colorScheme == .dark ? surfaceRaised : surfaceRaisedLight }
    static func surfaceMuted(for colorScheme: ColorScheme) -> Color { colorScheme == .dark ? surfaceMuted : surfaceMutedLight }
    static func editor(for colorScheme: ColorScheme) -> Color { colorScheme == .dark ? editor : editorLight }
    static func border(for colorScheme: ColorScheme) -> Color { colorScheme == .dark ? border : borderLight }
    static func borderStrong(for colorScheme: ColorScheme) -> Color { colorScheme == .dark ? borderStrong : borderStrongLight }
    static func textPrimary(for colorScheme: ColorScheme) -> Color { colorScheme == .dark ? textPrimary : textPrimaryLight }
    static func textSecondary(for colorScheme: ColorScheme) -> Color { colorScheme == .dark ? textSecondary : textSecondaryLight }
    static func textTertiary(for colorScheme: ColorScheme) -> Color { colorScheme == .dark ? textTertiary : textTertiaryLight }

    static let brandBlue = Color(red: 0.40, green: 0.61, blue: 1.00)
    static let brandPurple = Color(red: 0.55, green: 0.40, blue: 0.98)
    static let brandAmber = Color(red: 0.98, green: 0.76, blue: 0.31)
    static let brandOrange = Color(red: 1.0, green: 0.55, blue: 0.0)
    static let premiumGold = Color(red: 1.00, green: 0.84, blue: 0.39)
    static let premiumRose = Color(red: 0.98, green: 0.50, blue: 0.71)
    /// Bright gold for selected premium model text/icon so it’s obvious at a glance.
    static let premiumBright = Color(red: 1.00, green: 0.92, blue: 0.55)
    static let cursorPlusTeal = Color(red: 0.0, green: 0.83, blue: 0.71)
    /// Metro subtitle: bright blue (script-style branding).
    static let metroBlue = Color(red: 0.20, green: 0.45, blue: 0.95)
    /// Metro accent: red underline. Also use for semantic error / destructive.
    static let metroRed = Color(red: 0.90, green: 0.22, blue: 0.20)
    /// Tesco blue for Metro speech bubble (brand-style).
    static let tescoBlue = Color(red: 0, green: 83/255, blue: 159/255)

    // MARK: - Semantic and shared UI colors (use instead of hardcoded Color.red / .green / etc.)

    /// Error, destructive, or stopped state. Prefer over Color.red.
    static let semanticError = metroRed
    /// Success or “done” state. Prefer over Color.green for status.
    static let semanticSuccess = Color(red: 0.2, green: 0.78, blue: 0.35)
    /// "Needs review" state (e.g. agent finished or stopped). Use for Review tab and stopped agent tabs.
    static let semanticReview = Color(red: 1.0, green: 0.58, blue: 0.22)
    /// Spinner and loading accent (e.g. agent running). Use for progress/activity.
    static let spinnerBlue = Color(red: 0.45, green: 0.68, blue: 1.0)
    /// Debug/breakpoint accent (e.g. Visual Studio–style debug button).
    static let semanticDebug = Color(red: 0.0, green: 0.48, blue: 0.78)
    /// Soft error background (e.g. error card tint).
    static let semanticErrorTint = Color(red: 1.0, green: 0.64, blue: 0.67)

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

    // MARK: - Spacing (use for padding, gaps, and layout consistency)

    /// Extra small: inline gaps (e.g. icon + label).
    static let spaceXXS: CGFloat = 2
    /// Small: tight grouping (e.g. badge padding, compact controls).
    static let spaceXS: CGFloat = 4
    /// Default small: between related elements (e.g. list item spacing).
    static let spaceS: CGFloat = 8
    /// Medium: card padding, section inner spacing.
    static let spaceM: CGFloat = 12
    /// Large: headers, screen padding.
    static let spaceL: CGFloat = 16
    /// Extra large: section separation, modal padding.
    static let spaceXL: CGFloat = 24
    /// Double extra large: major sections, empty states.
    static let spaceXXL: CGFloat = 32

    /// Gap between a section/group title and its content (e.g. "Backlog" and first task).
    static let gapSectionTitleToContent: CGFloat = 16
    /// Padding inside cards (task row, conversation card, chip).
    static let paddingCard: CGFloat = 12
    /// Padding around scroll content or panel insets.
    static let paddingPanel: CGFloat = 12
    /// Horizontal padding for list/section headers.
    static let paddingHeaderHorizontal: CGFloat = 16
    /// Vertical padding for list/section headers.
    static let paddingHeaderVertical: CGFloat = 12
    /// Spacing between list items (e.g. task rows in a section).
    static let spacingListItems: CGFloat = 8
    /// Vertical gap between major sections (e.g. Todo vs Backlog).
    static let gapBetweenSections: CGFloat = 20
    /// Corner radius for the main popout window (clip and border).
    static let radiusWindow: CGFloat = 28
    /// Corner radius for cards (task row, raised surfaces).
    static let radiusCard: CGFloat = 12
    /// Corner radius for panel tab bar selected pill (Tasks, Projects, Preview).
    static let radiusTabBarPill: CGFloat = 6
    /// Small padding for badges and tags (horizontal).
    static let paddingBadgeHorizontal: CGFloat = 5
    /// Small padding for badges and tags (vertical).
    static let paddingBadgeVertical: CGFloat = 2
    /// Minimum width for capsule action buttons (Fix build, Commit & push, Add Task, etc.) so they stay consistent.
    static let actionButtonMinWidth: CGFloat = 128

    // MARK: - Typography (use for font sizes to keep UI consistent)

    /// Tiny / caption: badges, metadata, timestamps.
    static let fontTiny: CGFloat = 9
    /// Small caption: secondary labels, compact UI.
    static let fontCaption: CGFloat = 10
    /// Small: buttons, tertiary text, chips.
    static let fontSmall: CGFloat = 11
    /// Secondary: labels, filters, list secondary text.
    static let fontSecondary: CGFloat = 12
    /// Body small: dense content, descriptions.
    static let fontBodySmall: CGFloat = 13
    /// Body: main content, task text, default readable size.
    static let fontBody: CGFloat = 14
    /// Body emphasis: slightly larger for emphasis.
    static let fontBodyEmphasis: CGFloat = 15
    /// Subtitle: section subtitles, card titles.
    static let fontSubtitle: CGFloat = 16
    /// Title small: modal titles, section headers in settings.
    static let fontTitleSmall: CGFloat = 17
    /// Title: panel headers, list section titles.
    static let fontTitle: CGFloat = 18
    /// Title large: prominent headings.
    static let fontTitleLarge: CGFloat = 20
    /// Display small: splash headings.
    static let fontDisplaySmall: CGFloat = 22
    /// Display: modal/sheet main title.
    static let fontDisplay: CGFloat = 24
    /// Icon/circle size for list bullets and toggles (visual, not font).
    static let fontIconList: CGFloat = 18

    /// Panel background gradient for the given color scheme.
    static func panelGradient(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: [panel(for: colorScheme), chrome(for: colorScheme)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static var premiumGradient: LinearGradient {
        LinearGradient(
            colors: [premiumGold, premiumRose],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Brighter gradient for premium icon/text (gold → rose); pairs with dark background.
    static var premiumForegroundGradient: LinearGradient {
        LinearGradient(
            colors: [premiumGold, Color(red: 0.98, green: 0.65, blue: 0.55), premiumRose],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Stable color for a workspace path so the same project always gets the same colour (avoids confusion across tabs).
    static func colorForWorkspace(path: String) -> Color {
        guard !path.isEmpty else { return textTertiary }
        var hash = 0
        for byte in path.utf8 {
            hash = (hash &* 31 &+ Int(byte)) % 360
        }
        let hue = Double((hash + 360) % 360) / 360.0
        return Color(hue: hue, saturation: 0.58, brightness: 0.88)
    }

    // MARK: - Composer placeholder (Agent Input & Add Task)

    /// Placeholder hint for the composer when empty. Reused for Agent Input and Add Task.
    /// Describes: ⌘V paste screenshots, ⇧Enter new line, Enter to send.
    static let composerPlaceholderHint = "⌘V to paste screenshots, ⇧Enter for new line, Enter to send"

    /// Placeholder when the agent is running; message is queued until the agent finishes.
    static let composerPlaceholderWhenRunning = "Enter to queue message (sends when agent finishes). ⇧Enter for new line."
}

struct ModelOption: Identifiable {
    let id: String
    let label: String
    let isPremium: Bool
}

/// Model options for the Cursor agent (id for CLI, label for UI).
enum AvailableModels {
    static let autoID = "auto"

    /// Model IDs enabled (shown in picker) out of the box when user has never changed preferences.
    static let defaultEnabledModelIds: Set<String> = [
        "composer-1.5",
        "gpt-5.3-codex",
        "gpt-5.4-medium",
        "sonnet-4.6",
        "opus-4.6",
    ]

    /// Model IDs to show in the Models settings list by default; "View All Models" shows the full list.
    static let defaultShownModelIds: Set<String> = [
        "composer-1.5",
        "composer-1",
        "gpt-5.3-codex",
        "gpt-5.3-codex-low",
        "gpt-5.3-codex-low-fast",
        "gpt-5.4-medium",
        "sonnet-4.6",
        "opus-4.6",
    ]

    /// Fallback when CLI is unavailable or fails; also used as initial value before load.
    static let fallback: [ModelOption] = [
        ModelOption(id: autoID, label: "Auto", isPremium: false),
        ModelOption(id: "gpt-5.4-medium", label: "GPT-5.4", isPremium: true),
        ModelOption(id: "composer-1.5", label: "Composer 1.5", isPremium: true),
    ]

    static func model(for id: String, in list: [ModelOption]) -> ModelOption? {
        list.first { $0.id == id }
    }

    /// Models to show in the picker; excludes any whose id is in `disabledIds`. By default (empty set) returns all.
    static func visible(from list: [ModelOption], disabledIds: Set<String>) -> [ModelOption] {
        guard !disabledIds.isEmpty else { return list }
        let filtered = list.filter { !disabledIds.contains($0.id) }
        return filtered.isEmpty ? list : filtered
    }

    /// Whether a model is in the default "shown" set (for Models settings initial list).
    static func isDefaultShown(modelId: String) -> Bool {
        defaultShownModelIds.contains(modelId)
    }
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

