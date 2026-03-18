import SwiftUI

// MARK: - Reusable panel layout (Projects, Tasks, Preview, Agent)

/// Shared header for panel windows: icon + title + optional subtitle (e.g. project name with color).
struct PanelHeaderView<Subtitle: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    var icon: String
    var title: String
    @ViewBuilder var subtitle: () -> Subtitle

    init(icon: String, title: String, @ViewBuilder subtitle: @escaping () -> Subtitle) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        HStack(alignment: .center, spacing: CursorTheme.spaceM) {
            Image(systemName: icon)
                .font(.system(size: CursorTheme.fontIconList, weight: .medium))
                .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: CursorTheme.fontTitle, weight: .semibold))
                    .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                    .lineLimit(1)
                subtitle()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension PanelHeaderView where Subtitle == EmptyView {
    init(icon: String, title: String) {
        self.icon = icon
        self.title = title
        self.subtitle = { EmptyView() }
    }
}

/// One tab item for the panel tab bar (label with optional count, e.g. "In Progress (2)").
struct PanelTabItem<T: Hashable>: Identifiable {
    let id: T
    let label: String
    let count: Int?

    init(id: T, label: String, count: Int? = nil) {
        self.id = id
        self.label = label
        self.count = count
    }

    var displayLabel: String {
        if let c = count, c > 0 {
            return "\(label) (\(c))"
        }
        return label
    }
}

/// Reusable tab bar for panel windows (Tasks, Projects, Preview). Chrome strip, selected pill with surfaceMuted.
struct PanelTabBarView<T: Hashable>: View {
    @Environment(\.colorScheme) private var colorScheme

    let tabs: [PanelTabItem<T>]
    @Binding var selection: T
    var onSelect: (T) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                Button {
                    selection = tab.id
                    onSelect(tab.id)
                } label: {
                    Text(tab.displayLabel)
                        .font(.system(size: 13, weight: selection == tab.id ? .semibold : .medium))
                        .foregroundStyle(selection == tab.id ? CursorTheme.textPrimary(for: colorScheme) : CursorTheme.textSecondary(for: colorScheme))
                        .padding(.horizontal, CursorTheme.spaceM)
                        .padding(.vertical, CursorTheme.spaceS + CursorTheme.spaceXXS)
                }
                .buttonStyle(.plain)
                .background(selection == tab.id ? CursorTheme.surfaceMuted(for: colorScheme) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: CursorTheme.radiusTabBarPill, style: .continuous))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, CursorTheme.paddingHeaderHorizontal)
        .padding(.vertical, CursorTheme.spaceXS)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CursorTheme.chrome(for: colorScheme))
    }
}

/// Full panel window layout: optional header + optional tab bar + content. Use for consistent Projects, Tasks, Preview panels.
struct PanelWindowView<Header: View, TabBar: View, Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var header: () -> Header
    @ViewBuilder var tabBar: () -> TabBar
    var showTabBar: Bool
    @ViewBuilder var content: () -> Content

    init(
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder tabBar: @escaping () -> TabBar,
        showTabBar: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.header = header
        self.tabBar = tabBar
        self.showTabBar = showTabBar
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            header()
            if showTabBar {
                tabBar()
                Divider()
                    .background(CursorTheme.border(for: colorScheme))
            }
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Convenience when there is no tab bar (e.g. Agent panel).
struct PanelWindowContentOnlyView<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
