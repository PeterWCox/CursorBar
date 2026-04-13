import SwiftUI

// MARK: - Reusable 3-dot (ellipsis) menu button
// Use for "More options" / context menus so appearance is consistent app-wide.

struct ThreeDotMenuButton<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    var size: Size = .medium
    var help: String = "More options"
    @ViewBuilder var content: () -> Content

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

        var iconSize: CGFloat {
            switch self {
            case .small: return 12
            case .medium: return 12
            case .large: return 14
            }
        }
    }

    var body: some View {
        Menu {
            content()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: size.iconSize, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                .frame(width: size.dimension, height: size.dimension)
                .background(CursorTheme.surfaceMuted(for: colorScheme), in: Circle())
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(CursorTheme.textPrimary(for: colorScheme))
        .fixedSize()
        .help(help)
    }
}
