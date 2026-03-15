import SwiftUI

// MARK: - Model selection menu
// Styled like ActionButton.primary (surfaceMuted, textPrimary, border) for consistency.

/// Red "!" in white circle — premium/alert indicator badge.
fileprivate struct PremiumBadge: View {
    var body: some View {
        Text("!")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.red)
            .frame(width: 18, height: 18)
            .background(Circle().strokeBorder(Color.white, lineWidth: 1.5))
    }
}

struct ModelPickerView: View {
    @Environment(\.colorScheme) private var colorScheme

    var selectedModelId: String
    var models: [ModelOption]
    var onSelect: (String) -> Void

    private var selectedModel: ModelOption {
        models.first { $0.id == selectedModelId } ?? ModelOption(id: AvailableModels.autoID, label: "Auto", isPremium: false)
    }

    var body: some View {
        HStack(spacing: 8) {
            if selectedModel.isPremium {
                PremiumBadge()
            }
            Menu {
                ForEach(models, id: \.id) { model in
                    Button {
                        onSelect(model.id)
                    } label: {
                        HStack(spacing: 8) {
                            if model.id == selectedModelId {
                                Image(systemName: "checkmark")
                            } else {
                                Image(systemName: model.isPremium ? "sparkles" : "circle")
                                    .opacity(model.isPremium ? 0.9 : 0.2)
                            }

                            Text(model.label)

                            if model.isPremium {
                                Spacer(minLength: 12)
                                PremiumBadge()
                            }
                        }
                    }
                }
            } label: {
                pickerLabel(for: selectedModel)
            }
            .menuStyle(.borderlessButton)
            .fixedSize(horizontal: true, vertical: false)
        }
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
            if model.isPremium {
                PremiumBadge()
            }
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, CursorTheme.paddingCard)
        .padding(.vertical, CursorTheme.spaceS)
        .background(CursorTheme.surfaceMuted(for: colorScheme), in: Capsule())
        .overlay(Capsule().stroke(CursorTheme.border(for: colorScheme), lineWidth: 1))
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
            if model.isPremium {
                PremiumBadge()
            }
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, CursorTheme.paddingCard)
        .padding(.vertical, CursorTheme.spaceS)
        .background(CursorTheme.surfaceMuted(for: colorScheme), in: Capsule())
        .overlay(Capsule().stroke(CursorTheme.border(for: colorScheme), lineWidth: 1))
        .fixedSize(horizontal: true, vertical: false)
    }
}
