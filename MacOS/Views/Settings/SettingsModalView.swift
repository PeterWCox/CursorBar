import SwiftUI
import AppKit
#if DEBUG
import Inject
#endif

// MARK: - Settings modal with sidebar panes

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General"
    case models = "Models"
    case keyboardShortcuts = "Shortcuts"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .models: return "cpu"
        case .keyboardShortcuts: return "command"
        case .about: return "info.circle"
        }
    }
}

struct SettingsModalView: View {
    #if DEBUG
    @ObserveInjection var inject
    #endif
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
        .frame(width: 680, height: 580)
        .background(CursorTheme.surface(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(CursorTheme.border(for: colorScheme), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
        #if DEBUG
        .enableInjection()
        #endif
    }

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
            Spacer()
            Button("Close", action: { dismiss() })
                .keyboardShortcut(.cancelAction)
                .buttonStyle(DialogSecondaryButtonStyle())
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
                SettingsPaneContainer {
                    GeneralSettingsPaneContent()
                }
            case .models:
                SettingsPaneContainer {
                    ModelsSettingsPaneContent()
                }
            case .keyboardShortcuts:
                SettingsPaneContainer {
                    KeyboardShortcutsContentView()
                }
            case .about:
                SettingsPaneContainer {
                    AboutPaneContent()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Settings pane container (scroll + padding)

private struct SettingsPaneContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
        }
    }
}

// MARK: - Models pane (Cursor-like: default model, toggles, View All)

private struct ModelsSettingsPaneContent: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var appState: AppState
    @AppStorage(AppPreferences.disabledModelIdsKey) private var disabledModelIdsRaw: String = AppPreferences.defaultDisabledModelIdsRaw
    @AppStorage(AppPreferences.defaultModelIdKey) private var defaultModelId: String = AppPreferences.defaultDefaultModelId
    @AppStorage(AppPreferences.quickModelIdKey) private var quickModelId: String = AppPreferences.defaultQuickModelId
    @AppStorage(AppPreferences.thinkingModelIdKey) private var thinkingModelId: String = AppPreferences.defaultThinkingModelId
    @State private var modelSearchText: String = ""
    @State private var showAllModels: Bool = false

    private var allModelIds: Set<String> {
        Set(appState.availableModels.map(\.id))
    }

    private func effectiveDisabled() -> Set<String> {
        AppPreferences.effectiveDisabledModelIds(
            allIds: allModelIds,
            raw: disabledModelIdsRaw,
            defaultEnabledModelIds: AgentProviders.defaultEnabledModelIds(for: .cursor),
            defaultModelID: AgentProviders.defaultModelID(for: .cursor)
        )
    }

    /// Options for the default model picker: Auto plus all visible (enabled) models, without duplicating Auto.
    private var defaultModelOptions: [ModelOption] {
        let disabled = effectiveDisabled()
        let visible = appState.visibleModels(for: .cursor, disabledIds: disabled)
            .filter { $0.id != AvailableModels.autoID }
        let auto = ModelOption(id: AvailableModels.autoID, label: "Auto", isPremium: false)
        return [auto] + visible
    }

    /// Non-Auto models enabled for the picker; used for Quick / Thinking assignment.
    private var shortcutPickerBaseOptions: [ModelOption] {
        let disabled = effectiveDisabled()
        return appState.visibleModels(for: .cursor, disabledIds: disabled)
            .filter { $0.id != AvailableModels.autoID }
    }

    private func shortcutPickerOptions(storedId: String) -> [ModelOption] {
        var list = shortcutPickerBaseOptions
        if !storedId.isEmpty, !list.contains(where: { $0.id == storedId }),
           let orphan = appState.model(for: storedId, providerID: .cursor) {
            list.append(orphan)
        }
        return list
    }

    private var displayedModels: [ModelOption] {
        var list = showAllModels
            ? appState.availableModels
            : appState.availableModels.filter { appState.isDefaultShown(modelId: $0.id, for: .cursor) }
        let search = modelSearchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !search.isEmpty {
            list = list.filter {
                $0.label.lowercased().contains(search) || $0.id.lowercased().contains(search)
            }
        }
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Default model: label above dropdown (no badge)
            ModelsSettingsPaneContent.defaultModelSectionView(
                colorScheme: colorScheme,
                defaultModelId: $defaultModelId,
                options: defaultModelOptions
            )

            ModelsSettingsPaneContent.shortcutModelSectionView(
                colorScheme: colorScheme,
                title: "Quick Model",
                footer: "Shortcut row in the model picker below Auto. Right-click a model in the picker to assign quickly.",
                modelId: $quickModelId,
                options: shortcutPickerOptions(storedId: quickModelId)
            )

            ModelsSettingsPaneContent.shortcutModelSectionView(
                colorScheme: colorScheme,
                title: "Thinking Model",
                footer: "Shortcut row in the model picker below Quick. Right-click a model in the picker to assign quickly.",
                modelId: $thinkingModelId,
                options: shortcutPickerOptions(storedId: thinkingModelId)
            )

            // Available Models section
            Text("AVAILABLE MODELS")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                .textCase(.uppercase)
                .tracking(0.6)

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
                    modelSettingsRow(model: model)
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
        .onAppear {
            appState.loadModelsFromCLI()
        }
        .onChange(of: defaultModelOptions.count) { _, _ in
            if !defaultModelOptions.isEmpty && !defaultModelOptions.contains(where: { $0.id == defaultModelId }) {
                defaultModelId = AppPreferences.defaultDefaultModelId
            }
        }
    }

    @ViewBuilder
    private func modelSettingsRow(model: ModelOption) -> some View {
        Group {
            if model.id != AvailableModels.autoID {
                modelRowChrome(model: model)
                    .contextMenu {
                        Button("Set as Quick model") {
                            quickModelId = model.id
                        }
                        Button("Set as Thinking model") {
                            thinkingModelId = model.id
                        }
                    }
            } else {
                modelRowChrome(model: model)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func modelRowChrome(model: ModelOption) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 14))
                .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                .symbolRenderingMode(.hierarchical)
            Text(model.label)
                .font(.system(size: CursorTheme.fontBody, weight: .regular))
                .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
            Spacer(minLength: 8)
            if model.id != AvailableModels.autoID {
                Menu {
                    Button("Set as Quick model") {
                        quickModelId = model.id
                    }
                    Button("Set as Thinking model") {
                        thinkingModelId = model.id
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: CursorTheme.fontIconList, weight: .medium))
                        .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.plain)
                .help("Model shortcuts")
            }
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
    }

    /// Default model: "Default Model" label above a plain dropdown (no badge).
    fileprivate static func defaultModelSectionView(
        colorScheme: ColorScheme,
        defaultModelId: Binding<String>,
        options: [ModelOption]
    ) -> some View {
        let resolvedId = options.contains(where: { $0.id == defaultModelId.wrappedValue })
            ? defaultModelId.wrappedValue
            : AvailableModels.autoID
        return VStack(alignment: .leading, spacing: 8) {
            Text("Default Model")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                .textCase(.uppercase)
                .tracking(0.6)

            Menu {
                ForEach(options, id: \.id) { model in
                    Button {
                        defaultModelId.wrappedValue = model.id
                    } label: {
                        HStack(spacing: 8) {
                            if model.id == resolvedId {
                                Image(systemName: "checkmark")
                            }
                            Text(model.label)
                        }
                    }
                }
            } label: {
                let selected = options.first { $0.id == resolvedId } ?? ModelOption(id: AvailableModels.autoID, label: "Auto", isPremium: false)
                Text(selected.label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
            }
            .menuStyle(.borderlessButton)
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    /// Quick / Thinking: label above dropdown; empty string = None.
    fileprivate static func shortcutModelSectionView(
        colorScheme: ColorScheme,
        title: String,
        footer: String,
        modelId: Binding<String>,
        options: [ModelOption]
    ) -> some View {
        let resolvedId = modelId.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayLabel: String = {
            if resolvedId.isEmpty { return "None" }
            return options.first { $0.id == resolvedId }?.label ?? resolvedId
        }()
        return VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                .textCase(.uppercase)
                .tracking(0.6)

            Menu {
                Button {
                    modelId.wrappedValue = ""
                } label: {
                    HStack(spacing: 8) {
                        if resolvedId.isEmpty {
                            Image(systemName: "checkmark")
                        }
                        Text("None")
                    }
                }
                if !options.isEmpty {
                    Divider()
                }
                ForEach(options, id: \.id) { model in
                    Button {
                        modelId.wrappedValue = model.id
                    } label: {
                        HStack(spacing: 8) {
                            if model.id == resolvedId {
                                Image(systemName: "checkmark")
                            }
                            Text(model.label)
                        }
                    }
                }
            } label: {
                Text(displayLabel)
                    .font(.system(size: CursorTheme.fontBody, weight: .medium))
                    .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
            }
            .menuStyle(.borderlessButton)
            .fixedSize(horizontal: true, vertical: false)

            Text(footer)
                .font(.system(size: CursorTheme.fontSecondary, weight: .regular))
                .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - About pane

private struct AboutPaneContent: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppPreferences.selectedAgentProviderIDKey) private var selectedAgentProviderIDRawValue: String = AgentProviderID.claudeCode.rawValue
    private let githubURL = "https://github.com/cursor-macosapp/cursor-macosapp"

    private var providerId: AgentProviderID {
        AgentProviderID(rawValue: selectedAgentProviderIDRawValue) ?? .claudeCode
    }

    private var logoImageName: String {
        switch providerId {
        case .cursor:
            return "CursorMetroLogo"
        case .claudeCode:
            return "ClaudeMetroLogo"
        }
    }

    private var providerName: String {
        providerId.displayName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(logoImageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 44)

            Text("Cursor Metro is a native macOS menu bar app for \(providerName). It gives you quick access to projects, asks, and streaming output from the menu bar so you can keep an eye on agent work without living in a terminal.")
                .font(.system(size: 14))
                .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)

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
