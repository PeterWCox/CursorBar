import SwiftUI

// MARK: - Keyboard shortcut row model

private struct ShortcutRow: Identifiable {
    let id = UUID()
    let keys: [String]  // multiple shortcuts per action
    let action: String
}

// MARK: - Keyboard shortcuts content (embeddable, no header/frame)

struct KeyboardShortcutsContentView: View {
    private static let sections: [(title: String, rows: [ShortcutRow])] = [
        ("Tabs", [
            ShortcutRow(keys: ["⌘T", "⌘N"], action: "New tab"),
            ShortcutRow(keys: ["⌘W"], action: "Close tab"),
            ShortcutRow(keys: ["⌘⇧T"], action: "Reopen closed tab"),
        ]),
        ("Navigation", [
            ShortcutRow(keys: ["⇥ Tab"], action: "Focus prompt input"),
        ]),
        ("Composer", [
            ShortcutRow(keys: ["↵ Return"], action: "Send message"),
            ShortcutRow(keys: ["⇧↵ Shift + Return"], action: "New line in message"),
            ShortcutRow(keys: ["⌘V"], action: "Paste (including screenshots)"),
        ]),
        ("Agent", [
            ShortcutRow(keys: ["⌃C"], action: "Stop agent"),
        ]),
        ("Window", [
            ShortcutRow(keys: ["⌘B", "⌘S"], action: "Show/hide panel"),
        ]),
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 24) {
                comingSoonBanner
                ForEach(Self.sections, id: \.title) { section in
                    KeyboardShortcutsContentView.sectionView(title: section.title, rows: section.rows)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
    }

    private var comingSoonBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(CursorTheme.brandBlue)
            Text("Ability to customise these shortcuts is coming soon.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(CursorTheme.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CursorTheme.brandBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    fileprivate static func sectionView(title: String, rows: [ShortcutRow]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CursorTheme.textTertiary)
                .textCase(.uppercase)
                .tracking(0.6)

            VStack(spacing: 0) {
                ForEach(rows) { row in
                    HStack {
                        Text(row.action)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(CursorTheme.textPrimary)
                        Spacer(minLength: 16)
                        HStack(spacing: 6) {
                            ForEach(row.keys, id: \.self) { key in
                                keyCaps(key)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(CursorTheme.surfaceMuted.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(CursorTheme.border.opacity(0.6), lineWidth: 1)
                    )

                    if row.id != rows.last?.id {
                        Spacer().frame(height: 8)
                    }
                }
            }
        }
    }

    fileprivate static func keyCaps(_ keys: String) -> some View {
        Text(keys)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(CursorTheme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(CursorTheme.editor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(CursorTheme.borderStrong, lineWidth: 1)
            )
    }
}

// MARK: - Keyboard shortcuts modal (read-only, standalone)

struct KeyboardShortcutsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .background(CursorTheme.border)
                .padding(.horizontal, 24)
            KeyboardShortcutsContentView()
        }
        .frame(width: 420, height: 440)
        .background(CursorTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(CursorTheme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
    }

    private var header: some View {
        HStack {
            Image(systemName: "keyboard")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(CursorTheme.brandBlue)
            Text("Keyboard Shortcuts")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(CursorTheme.textPrimary)
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(CursorTheme.textTertiary)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }
}

#Preview {
    KeyboardShortcutsView()
        .padding(40)
        .background(CursorTheme.panel)
}
