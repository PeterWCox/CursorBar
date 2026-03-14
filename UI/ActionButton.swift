import SwiftUI

// MARK: - Reusable capsule action button (icon + title)
// Use for consistent primary/secondary actions across the app.

struct ActionButton: View {
    @Environment(\.colorScheme) private var colorScheme

    var title: String
    var icon: String? = nil  // SF Symbol name
    var action: () -> Void
    var isDisabled: Bool = false
    var help: String? = nil
    var style: Style = .primary

    enum Style {
        case primary   // textPrimary, surfaceMuted
        case secondary // textSecondary, surfaceMuted.opacity(0.7)
        case play      // green (run/start)
        case stop      // red (stop/reset)
        case debug     // blue (VS-style debug)
        case accent    // purple (AI / configure)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                }
                Text(title)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, CursorTheme.paddingCard)
            .padding(.vertical, CursorTheme.spaceS)
            .background(backgroundFill, in: Capsule())
            .overlay(Capsule().stroke(borderColor, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .modifier(OptionalHelpModifier(help: help))
    }

    private var foregroundColor: Color {
        switch style {
        case .primary: return CursorTheme.textPrimary(for: colorScheme)
        case .secondary: return CursorTheme.textSecondary(for: colorScheme)
        case .play: return CursorTheme.semanticSuccess
        case .stop: return CursorTheme.semanticError
        case .debug: return CursorTheme.semanticDebug
        case .accent: return CursorTheme.brandPurple
        }
    }

    private var backgroundFill: Color {
        switch style {
        case .primary: return CursorTheme.surfaceMuted(for: colorScheme)
        case .secondary: return CursorTheme.surfaceMuted(for: colorScheme).opacity(0.7)
        case .play: return CursorTheme.semanticSuccess.opacity(0.15)
        case .stop: return CursorTheme.semanticError.opacity(0.15)
        case .debug: return CursorTheme.semanticDebug.opacity(0.15)
        case .accent: return CursorTheme.brandPurple.opacity(0.15)
        }
    }

    private var borderColor: Color {
        switch style {
        case .primary, .secondary: return CursorTheme.border(for: colorScheme)
        case .play: return CursorTheme.semanticSuccess.opacity(0.5)
        case .stop: return CursorTheme.semanticError.opacity(0.5)
        case .debug: return CursorTheme.semanticDebug.opacity(0.5)
        case .accent: return CursorTheme.brandPurple.opacity(0.5)
        }
    }
}

// MARK: - Optional tooltip (apply .help only when non-empty)

private struct OptionalHelpModifier: ViewModifier {
    var help: String?

    func body(content: Content) -> some View {
        if let help, !help.isEmpty {
            content.help(help)
        } else {
            content
        }
    }
}
