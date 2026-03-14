import SwiftUI
import AppKit

// MARK: - Settings modal with sidebar panes

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General"
    case preview = "Preview"
    case models = "Models"
    case keyboardShortcuts = "Shortcuts"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .preview: return "globe"
        case .models: return "cpu"
        case .keyboardShortcuts: return "command"
        case .about: return "info.circle"
        }
    }
}

struct SettingsModalView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var appState: AppState
    @State private var selectedPane: SettingsPane = .general

    private let sidebarWidth: CGFloat = 200

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .background(CursorTheme.border(for: colorScheme))

            HStack(spacing: 0) {
                sidebar
                Divider()
                    .background(CursorTheme.border(for: colorScheme))
                    .frame(width: 1)
                contentArea
            }
        }
        .frame(width: 680, height: 520)
        .background(CursorTheme.surface(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(CursorTheme.border(for: colorScheme), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Settings")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                Spacer()
                Button("Close", action: { dismiss() })
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(DialogSecondaryButtonStyle())
            }
            Text("Changes apply automatically.")
                .font(.system(size: 12))
                .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private var sidebar: some View {
        let unselectedForeground = colorScheme == .dark ? Color.white.opacity(0.82) : Color.black.opacity(0.6)
        return List(SettingsPane.allCases, selection: $selectedPane) { pane in
            HStack(spacing: 8) {
                Image(systemName: pane.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(selectedPane == pane ? CursorTheme.textPrimary(for: colorScheme) : unselectedForeground)
                    .symbolRenderingMode(.monochrome)
                Text(pane.rawValue)
                    .foregroundStyle(selectedPane == pane ? CursorTheme.textPrimary(for: colorScheme) : unselectedForeground)
            }
            .tag(pane)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(CursorTheme.surfaceMuted(for: colorScheme).opacity(0.5))
        .frame(width: sidebarWidth)
    }

    @ViewBuilder
    private var contentArea: some View {
        Group {
            switch selectedPane {
            case .general:
                SettingsPaneContainer(title: SettingsPane.general.rawValue) {
                    GeneralSettingsPaneContent()
                }
            case .preview:
                SettingsPaneContainer(title: SettingsPane.preview.rawValue) {
                    PreviewSettingsPaneContent()
                }
            case .models:
                SettingsPaneContainer(title: SettingsPane.models.rawValue) {
                    ModelsSettingsPaneContent()
                }
            case .keyboardShortcuts:
                SettingsPaneContainer(title: SettingsPane.keyboardShortcuts.rawValue) {
                    KeyboardShortcutsContentView()
                }
            case .about:
                SettingsPaneContainer(title: SettingsPane.about.rawValue) {
                    AboutPaneContent()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Settings pane container (title + scroll + padding)

private struct SettingsPaneContainer<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 24) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
    }
}

// MARK: - General pane

private struct GeneralSettingsPaneContent: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppPreferences.projectsRootPathKey) private var projectsRootPath: String = AppPreferences.defaultProjectsRootPath

    private var resolvedProjectsRootPath: String {
        AppPreferences.resolvedProjectsRootPath(projectsRootPath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Project picker root")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                        .textCase(.uppercase)
                        .tracking(0.6)

                    Text("Direct subfolders from this directory appear in the workspace picker.")
                        .font(.system(size: 14))
                        .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 10) {
                        Button(action: { selectProjectsRootFolder() }) {
                            HStack(spacing: 12) {
                                Text(resolvedProjectsRootPath)
                                    .font(.system(size: 13))
                                    .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                                    .symbolRenderingMode(.hierarchical)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(CursorTheme.editor(for: colorScheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(CursorTheme.borderStrong(for: colorScheme), lineWidth: 1)
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
                    .background(CursorTheme.surfaceMuted(for: colorScheme).opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(CursorTheme.border(for: colorScheme).opacity(0.6), lineWidth: 1)
                    )

                    Text("Current root: \(resolvedProjectsRootPath)")
                        .font(.system(size: 12))
                        .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                        .textSelection(.enabled)
                }
            }
        .frame(maxWidth: .infinity, alignment: .leading)
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

// MARK: - Preview pane (View in Browser URL, startup script)

private struct PreviewSettingsPaneContent: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var appState: AppState
    @State private var debugURL: String = ""
    @State private var startupScriptContents: String = ""

    private var workspacePath: String {
        appState.tabManager.activeProjectPath ?? appState.workspacePath
    }

    private var activeProjectPath: String? {
        appState.tabManager.activeProjectPath
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("These settings apply to the currently selected project. View in Browser opens the URL in Chrome; the startup script runs when you use \"Run startup script\" from the composer menu.")
                .font(.system(size: 14))
                .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                Text("View in Browser URL")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                    .textCase(.uppercase)
                    .tracking(0.6)
                TextField("", text: $debugURL)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Startup script (startup.sh)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                    .textCase(.uppercase)
                    .tracking(0.6)
                Text("Stored in `.metro/startup.sh`, run with bash.")
                    .font(.system(size: 12))
                    .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                TextEditor(text: $startupScriptContents)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 80, maxHeight: 120)
                    .background(CursorTheme.editor(for: colorScheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(CursorTheme.border(for: colorScheme), lineWidth: 1)
                    )
            }

            if let path = activeProjectPath {
                Text("Project: \((path as NSString).lastPathComponent)")
                    .font(.system(size: 12))
                    .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            loadFromProject()
        }
        .onChange(of: appState.tabManager.selectedProjectPath) { _, _ in
            loadFromProject()
        }
        .onDisappear {
            let trimmedUrl = debugURL.trimmingCharacters(in: .whitespacesAndNewlines)
            ProjectSettingsStorage.setDebugURL(workspacePath: workspacePath, trimmedUrl.isEmpty ? nil : trimmedUrl)
            ProjectSettingsStorage.setStartupScriptContents(workspacePath: workspacePath, startupScriptContents.isEmpty ? nil : startupScriptContents)
        }
    }

    private func loadFromProject() {
        debugURL = ProjectSettingsStorage.getDebugURL(workspacePath: workspacePath) ?? ""
        startupScriptContents = ProjectSettingsStorage.getStartupScriptContents(workspacePath: workspacePath) ?? ""
    }
}

// MARK: - Models pane (Cursor-like: toggles, default set, View All)

private struct ModelsSettingsPaneContent: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var appState: AppState
    @AppStorage(AppPreferences.disabledModelIdsKey) private var disabledModelIdsRaw: String = AppPreferences.defaultDisabledModelIdsRaw
    @AppStorage(AppPreferences.modelsSortOrderKey) private var modelsSortOrderRaw: String = AppPreferences.defaultModelsSortOrderRaw
    @State private var modelSearchText: String = ""
    @State private var showAllModels: Bool = false

    private var modelsSortOrder: ModelsSortOrder {
        ModelsSortOrder(rawValue: modelsSortOrderRaw) ?? .defaultOrder
    }

    private var allModelIds: Set<String> {
        Set(appState.availableModels.map(\.id))
    }

    private func effectiveDisabled() -> Set<String> {
        AppPreferences.effectiveDisabledModelIds(allIds: allModelIds, raw: disabledModelIdsRaw)
    }

    private var displayedModels: [ModelOption] {
        var list = showAllModels
            ? appState.availableModels
            : appState.availableModels.filter { AvailableModels.isDefaultShown(modelId: $0.id) }
        let search = modelSearchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !search.isEmpty {
            list = list.filter {
                $0.label.lowercased().contains(search) || $0.id.lowercased().contains(search)
            }
        }
        if modelsSortOrder == .alphabetical {
            list = list.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        }
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Order: A–Z (toggled) first, then Default (untoggled)
            VStack(alignment: .leading, spacing: 8) {
                Text("Order")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                    .textCase(.uppercase)
                    .tracking(0.6)
                Picker("Order", selection: $modelsSortOrderRaw) {
                    ForEach(ModelsSortOrder.allCases, id: \.rawValue) { order in
                        Text(order.displayName).tag(order.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Search and refresh
            HStack(spacing: 8) {
                TextField("Search models...", text: $modelSearchText)
                    .textFieldStyle(.roundedBorder)
                Button {
                    appState.loadModelsFromCLI()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("Refresh model list")
            }

            // Model list with native macOS toggles
            VStack(alignment: .leading, spacing: 0) {
                ForEach(displayedModels, id: \.id) { model in
                    HStack(spacing: 12) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 14))
                            .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                            .symbolRenderingMode(.hierarchical)
                        Text(model.label)
                            .font(.system(size: 14))
                            .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                        Spacer(minLength: 8)
                        Toggle("", isOn: Binding(
                            get: { !effectiveDisabled().contains(model.id) },
                            set: { enabled in
                                var disabled = effectiveDisabled()
                                if enabled { disabled.remove(model.id) } else { disabled.insert(model.id) }
                                disabledModelIdsRaw = AppPreferences.rawFrom(disabledIds: disabled)
                            }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                    if model.id != displayedModels.last?.id {
                        Divider()
                            .background(CursorTheme.border(for: colorScheme))
                            .padding(.leading, 12)
                    }
                }
            }
            .background(CursorTheme.surfaceMuted(for: colorScheme).opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(CursorTheme.border(for: colorScheme).opacity(0.6), lineWidth: 1)
            )

            if !showAllModels {
                Button("View All Models") {
                    showAllModels = true
                }
                .buttonStyle(.plain)
                .foregroundStyle(CursorTheme.brandBlue)
                .font(.system(size: 14))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - About pane

private struct AboutPaneContent: View {
    @Environment(\.colorScheme) private var colorScheme
    private let githubURL = "https://github.com/cursor-macosapp/cursor-macosapp"

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Cursor+ is a native macOS menu bar app that works alongside Cursor. It gives you quick access to projects, composer, and Cursor features from the menu bar—open workspaces, jump into chat, or pop out the composer without switching apps.")
                .font(.system(size: 14))
                .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            Image("CursorMetroLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 44)

            Text("GitHub")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
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
    }
}

#Preview {
    SettingsModalView()
        .padding(40)
        .background(CursorTheme.panel(for: .dark))
}
