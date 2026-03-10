import SwiftUI
import AppKit

// MARK: - Settings modal with sidebar panes

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General"
    case keyboardShortcuts = "Keyboard Shortcuts"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .keyboardShortcuts: return "keyboard"
        case .about: return "info.circle"
        }
    }
}

struct SettingsModalView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPane: SettingsPane = .general

    private let sidebarWidth: CGFloat = 200

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .background(CursorTheme.border)

            HStack(spacing: 0) {
                sidebar
                Divider()
                    .background(CursorTheme.border)
                    .frame(width: 1)
                contentArea
            }
        }
        .frame(width: 680, height: 520)
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
            Text("Settings")
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

    private var sidebar: some View {
        List(SettingsPane.allCases, selection: $selectedPane) { pane in
            Label(pane.rawValue, systemImage: pane.icon)
                .foregroundStyle(selectedPane == pane ? CursorTheme.textPrimary : CursorTheme.textSecondary)
                .tag(pane)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(CursorTheme.surfaceMuted.opacity(0.5))
        .frame(width: sidebarWidth)
    }

    @ViewBuilder
    private var contentArea: some View {
        Group {
            switch selectedPane {
            case .general:
                GeneralSettingsPaneView()
            case .keyboardShortcuts:
                KeyboardShortcutsContentView()
            case .about:
                AboutPaneView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - General pane

private struct GeneralSettingsPaneView: View {
    @AppStorage(AppPreferences.projectsRootPathKey) private var projectsRootPath: String = AppPreferences.defaultProjectsRootPath

    private var resolvedProjectsRootPath: String {
        AppPreferences.resolvedProjectsRootPath(projectsRootPath)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Project picker root")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CursorTheme.textTertiary)
                        .textCase(.uppercase)
                        .tracking(0.6)

                    Text("Direct subfolders from this directory appear in the workspace picker.")
                        .font(.system(size: 14))
                        .foregroundStyle(CursorTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 10) {
                        TextField("~/dev", text: $projectsRootPath)
                            .textFieldStyle(.roundedBorder)

                        HStack(spacing: 10) {
                            Button("Browse...") {
                                selectProjectsRootFolder()
                            }

                            if projectsRootPath != AppPreferences.defaultProjectsRootPath {
                                Button("Reset") {
                                    projectsRootPath = AppPreferences.defaultProjectsRootPath
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(16)
                    .background(CursorTheme.surfaceMuted.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(CursorTheme.border.opacity(0.6), lineWidth: 1)
                    )

                    Text("Current root: \(resolvedProjectsRootPath)")
                        .font(.system(size: 12))
                        .foregroundStyle(CursorTheme.textTertiary)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
    }

    private func selectProjectsRootFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = "Select Projects Root"
        panel.message = "Choose the directory whose subfolders should be shown in the workspace picker."
        panel.directoryURL = URL(fileURLWithPath: resolvedProjectsRootPath)

        if panel.runModal() == .OK, let url = panel.url {
            projectsRootPath = url.path
        }
    }
}

// MARK: - About pane (placeholder + GitHub)

private struct AboutPaneView: View {
    private let githubURL = "https://github.com"

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: 12) {
                    BrandAppIconView(size: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cursor+")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(CursorTheme.textPrimary)
                        Text("A menu bar companion for Cursor.")
                            .font(.system(size: 14))
                            .foregroundStyle(CursorTheme.textSecondary)
                    }
                }

                Text("About this app")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CursorTheme.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.6)

                Text("Placeholder content. You can add a short description, version info, credits, or links here.")
                    .font(.system(size: 14))
                    .foregroundStyle(CursorTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("GitHub")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CursorTheme.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.6)

                Link(destination: URL(string: githubURL)!) {
                    HStack(spacing: 8) {
                        Image(systemName: "link")
                            .font(.system(size: 14))
                        Text(githubURL)
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(CursorTheme.brandBlue)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
    }
}

#Preview {
    SettingsModalView()
        .padding(40)
        .background(CursorTheme.panel)
}
