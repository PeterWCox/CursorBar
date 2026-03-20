import SwiftUI

// MARK: - Model selection menu
// Native `Menu` = standard macOS dropdown (rectangular); avoids custom popover chrome.

struct ModelPickerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appState: AppState

    var selectedModelId: String
    var models: [ModelOption]
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

    var body: some View {
        HStack(spacing: CursorTheme.spaceS) {
            Menu {
                Button {
                    onSelect(autoModel.id)
                } label: {
                    menuRowLabel(for: autoModel)
                }

                Divider()

                ForEach(concreteModels, id: \.id) { model in
                    Button {
                        onSelect(model.id)
                    } label: {
                        menuRowLabel(for: model)
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
