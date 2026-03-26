import SwiftUI

// MARK: - Model selection menu
// Native `Menu` = standard macOS dropdown (rectangular); avoids custom popover chrome.

struct ModelPickerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appState: AppState
    @AppStorage(AppPreferences.quickModelIdKey) private var quickModelId: String = AppPreferences.defaultQuickModelId
    @AppStorage(AppPreferences.thinkingModelIdKey) private var thinkingModelId: String = AppPreferences.defaultThinkingModelId

    var selectedModelId: String
    var models: [ModelOption]
    /// Used to resolve shortcut labels when a model is hidden from the picker but still assigned.
    var providerID: AgentProviderID = .cursor
    var onSelect: (String) -> Void

    private var selectedModel: ModelOption {
        models.first { $0.id == selectedModelId } ?? AvailableModels.autoOption
    }

    private var autoModel: ModelOption {
        models.first { $0.id == AvailableModels.autoID } ?? AvailableModels.autoOption
    }

    private var concreteModels: [ModelOption] {
        models.filter { $0.id != AvailableModels.autoID }
    }

    private func resolvedModel(forStoredId id: String) -> ModelOption? {
        guard !id.isEmpty else { return nil }
        if let m = models.first(where: { $0.id == id }) { return m }
        return appState.model(for: id, providerID: providerID)
    }

    var body: some View {
        HStack(spacing: CursorTheme.spaceS) {
            Menu {
                Button {
                    onSelect(autoModel.id)
                } label: {
                    menuRowLabel(for: autoModel)
                }

                shortcutMenuButton(
                    title: "Quick",
                    systemImage: "bolt.fill",
                    storedId: quickModelId,
                    isSelected: !quickModelId.isEmpty && selectedModelId == quickModelId
                )
                shortcutMenuButton(
                    title: "Thinking",
                    systemImage: "brain.head.profile",
                    storedId: thinkingModelId,
                    isSelected: !thinkingModelId.isEmpty && selectedModelId == thinkingModelId
                )

                Divider()

                ForEach(concreteModels, id: \.id) { model in
                    Button {
                        onSelect(model.id)
                    } label: {
                        menuRowLabel(for: model)
                    }
                    .contextMenu {
                        shortcutAssignmentMenuContent(for: model)
                    }
                }

                Divider()

                Button("Add Models") {
                    appState.showSettingsSheet = true
                }
            } label: {
                pickerLabel(for: selectedModel)
            }
            .menuStyle(.borderlessButton)
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    @ViewBuilder
    private func shortcutMenuButton(title: String, systemImage: String, storedId: String, isSelected: Bool) -> some View {
        if let target = resolvedModel(forStoredId: storedId) {
            Button {
                onSelect(target.id)
            } label: {
                shortcutMenuRowLabel(title: title, systemImage: systemImage, subtitle: target.label, showCheckmark: isSelected)
            }
        } else {
            Button {
                appState.showSettingsSheet = true
            } label: {
                shortcutMenuRowLabel(
                    title: title,
                    systemImage: systemImage,
                    subtitle: "Not set — choose in Settings",
                    showCheckmark: false,
                    subtitleIsPlaceholder: true
                )
            }
        }
    }

    @ViewBuilder
    private func shortcutMenuRowLabel(
        title: String,
        systemImage: String,
        subtitle: String,
        showCheckmark: Bool,
        subtitleIsPlaceholder: Bool = false
    ) -> some View {
        HStack(alignment: .center, spacing: CursorTheme.spaceXS) {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: CursorTheme.fontSecondary, weight: .regular))
                    .foregroundStyle(subtitleIsPlaceholder ? CursorTheme.textTertiary(for: colorScheme) : CursorTheme.textSecondary(for: colorScheme))
                    .lineLimit(1)
            }
            Spacer(minLength: CursorTheme.spaceM)
            if showCheckmark {
                Image(systemName: "checkmark")
            }
        }
    }

    @ViewBuilder
    private func shortcutAssignmentMenuContent(for model: ModelOption) -> some View {
        if model.id != AvailableModels.autoID {
            Button("Set as Quick model") {
                quickModelId = model.id
            }
            Button("Set as Thinking model") {
                thinkingModelId = model.id
            }
        }
    }

    @ViewBuilder
    private func menuRowLabel(for model: ModelOption) -> some View {
        HStack(spacing: CursorTheme.spaceXS) {
            modelMenuIcon(for: model)
            Text(model.label)
                .lineLimit(1)
            Spacer(minLength: CursorTheme.spaceM)
            if let speed = modelSpeedTag(for: model) {
                Text(speed)
                    .foregroundStyle(.secondary)
            }
            if model.id == selectedModelId {
                Image(systemName: "checkmark")
            }
        }
    }

    @ViewBuilder
    private func modelMenuIcon(for model: ModelOption) -> some View {
        if model.id == AvailableModels.autoID {
            Image(systemName: "sparkles")
        } else {
            Image(systemName: model.isPremium ? "brain.head.profile" : "bolt.fill")
        }
    }

    private func modelSpeedTag(for model: ModelOption) -> String? {
        let id = model.id
        if id == AvailableModels.autoID { return nil }
        if id.contains("fast") { return "Fast" }
        if id.contains("thinking") || id.contains("xhigh") || id.contains("max") || id.contains("opus-high") {
            return "High"
        }
        if id.contains("medium") || id.contains("high") || id == "composer-2" {
            return "Medium"
        }
        return nil
    }

    private func pickerLabel(for model: ModelOption) -> some View {
        HStack(spacing: 6) {
            Image(systemName: model.isPremium ? "sparkles" : "cpu")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
            Text(model.label)
                .lineLimit(1)
                .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                .fontWeight(.medium)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, CursorTheme.paddingCard)
        .padding(.vertical, CursorTheme.spaceS)
        .background(CursorTheme.modelChipBackground(for: colorScheme, isAuto: model.id == AvailableModels.autoID), in: Capsule())
        .overlay(Capsule().stroke(CursorTheme.modelChipBorder(for: colorScheme, isAuto: model.id == AvailableModels.autoID), lineWidth: 1))
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Read-only model chip (no dropdown)

/// Displays the selected model as a chip when the agent cannot be changed (e.g. processing).
/// Styled like ActionButton.primary for consistency.
struct ModelChipView: View {
    @Environment(\.colorScheme) private var colorScheme

    let model: ModelOption

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: model.isPremium ? "sparkles" : "cpu")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
            Text(model.label)
                .lineLimit(1)
                .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                .fontWeight(.medium)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, CursorTheme.paddingCard)
        .padding(.vertical, CursorTheme.spaceS)
        .background(CursorTheme.modelChipBackground(for: colorScheme, isAuto: model.id == AvailableModels.autoID), in: Capsule())
        .overlay(Capsule().stroke(CursorTheme.modelChipBorder(for: colorScheme, isAuto: model.id == AvailableModels.autoID), lineWidth: 1))
        .fixedSize(horizontal: true, vertical: false)
    }
}
