import SwiftUI
import AppKit

// MARK: - Settings modal with sidebar panes

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General"
    case models = "Models"
    case keyboardShortcuts = "Keyboard Shortcuts"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .models: return "cpu"
        case .keyboardShortcuts: return "keyboard"
        case .about: return "info.circle"
        }
    }
}

struct SettingsModalView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
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
            Button("Close", action: { dismiss() })
                .keyboardShortcut(.cancelAction)
                .buttonStyle(DialogSecondaryButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private var sidebar: some View {
        let unselectedForeground = Color.white.opacity(0.82)
        return List(SettingsPane.allCases, selection: $selectedPane) { pane in
            HStack(spacing: 8) {
                Image(systemName: pane.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(selectedPane == pane ? CursorTheme.textPrimary : unselectedForeground)
                    .symbolRenderingMode(.monochrome)
                Text(pane.rawValue)
                    .foregroundStyle(selectedPane == pane ? CursorTheme.textPrimary : unselectedForeground)
            }
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
            case .models:
                ModelsSettingsPaneView()
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
                        Button(action: { selectProjectsRootFolder() }) {
                            HStack(spacing: 12) {
                                Text(resolvedProjectsRootPath)
                                    .font(.system(size: 13))
                                    .foregroundStyle(CursorTheme.textPrimary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(CursorTheme.textSecondary)
                                    .symbolRenderingMode(.hierarchical)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(CursorTheme.editor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(CursorTheme.borderStrong, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)

                        if projectsRootPath != AppPreferences.defaultProjectsRootPath {
                            Button("Reset to default") {
                                projectsRootPath = AppPreferences.defaultProjectsRootPath
                            }
                            .buttonStyle(.bordered)
                        }
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

// MARK: - Models pane

private struct ModelsSettingsPaneView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage(AppPreferences.disabledModelIdsKey) private var disabledModelIdsRaw: String = AppPreferences.defaultDisabledModelIdsRaw

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Model picker")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CursorTheme.textTertiary)
                        .textCase(.uppercase)
                        .tracking(0.6)

                    Text("Choose which models appear in the model picker. Uncheck to hide a model from the list.")
                        .font(.system(size: 14))
                        .foregroundStyle(CursorTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Button("Select all") {
                            disabledModelIdsRaw = AppPreferences.defaultDisabledModelIdsRaw
                        }
                        .buttonStyle(.bordered)
                        Button("Deselect all") {
                            let allIds = Set(appState.availableModels.map(\.id))
                            disabledModelIdsRaw = AppPreferences.rawFrom(disabledIds: allIds)
                        }
                        .buttonStyle(.bordered)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(appState.availableModels, id: \.id) { model in
                            Toggle(isOn: Binding(
                                get: { !AppPreferences.disabledModelIds(from: disabledModelIdsRaw).contains(model.id) },
                                set: { enabled in
                                    var set = AppPreferences.disabledModelIds(from: disabledModelIdsRaw)
                                    if enabled { set.remove(model.id) } else { set.insert(model.id) }
                                    disabledModelIdsRaw = AppPreferences.rawFrom(disabledIds: set)
                                }
                            )) {
                                HStack(spacing: 8) {
                                    Text(model.label)
                                        .font(.system(size: 14))
                                        .foregroundStyle(CursorTheme.textPrimary)
                                    if model.isPremium {
                                        Text("Premium")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(CursorTheme.textTertiary)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(CursorTheme.surfaceMuted, in: Capsule())
                                    }
                                }
                            }
                            .toggleStyle(.checkbox)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)

                            if model.id != appState.availableModels.last?.id {
                                Divider()
                                    .background(CursorTheme.border)
                                    .padding(.leading, 16)
                            }
                        }
                    }
                    .background(CursorTheme.surfaceMuted.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(CursorTheme.border.opacity(0.6), lineWidth: 1)
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
    }
}

// MARK: - About pane (placeholder + GitHub)

private struct AboutPaneView: View {
    private let githubURL = "https://github.com/cursor-macosapp/cursor-macosapp"

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 12) {
                    Image("CursorMetroLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 44)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Cursor+")
                            .font(.system(size: 22, weight: .semibold, design: .monospaced))
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

                Text("Cursor+ is a native macOS menu bar app that works alongside Cursor. It gives you quick access to projects, composer, and Cursor features from the menu bar—open workspaces, jump into chat, or pop out the composer without switching apps.")
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
