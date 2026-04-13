import SwiftUI

// MARK: - Reusable circular icon-only button
// Use for toolbar actions (settings, collapse, minimise, etc.) so size and style are consistent.

struct IconButton: View {
    @Environment(\.colorScheme) private var colorScheme

    var icon: String  // SF Symbol name
    var action: () -> Void
    var help: String? = nil
    var size: Size = .medium
    var style: Style = .secondary

    enum Size {
        case small   // 24×24
        case medium  // 30×30
        case large   // 36×36

        var dimension: CGFloat {
            switch self {
            case .small: return 24
            case .medium: return 30
            case .large: return 36
            }
        }

        var iconFontSize: CGFloat {
            switch self {
            case .small: return 11
            case .medium: return 12
            case .large: return 14
            }
        }
    }

    enum Style {
        case primary   // textPrimary
        case secondary // textSecondary
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size.iconFontSize, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(style == .primary ? CursorTheme.textPrimary(for: colorScheme) : CursorTheme.textSecondary(for: colorScheme))
                .frame(width: size.dimension, height: size.dimension)
                .background(CursorTheme.surfaceMuted(for: colorScheme), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .modifier(IconButtonHelpModifier(help: help))
    }
}

private struct IconButtonHelpModifier: ViewModifier {
    var help: String?

    func body(content: Content) -> some View {
        if let help, !help.isEmpty {
            content.help(help)
        } else {
            content
        }
    }
}
