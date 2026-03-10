import SwiftUI

// MARK: - Model selection menu

private let premiumSelectionTextColor = Color(red: 0.99, green: 0.91, blue: 0.62)
private let premiumSelectionAccentColor = Color(red: 1.00, green: 0.83, blue: 0.33)
private let premiumSelectionBadgeTextColor = Color(red: 1.00, green: 0.88, blue: 0.45)
private let premiumSelectionBackgroundColor = Color(red: 0.19, green: 0.14, blue: 0.07)
private let premiumSelectionBadgeBackgroundColor = Color(red: 0.38, green: 0.27, blue: 0.08)
private let premiumSelectionBorderColor = Color(red: 0.93, green: 0.72, blue: 0.30)
private let premiumSelectionShadowColor = Color(red: 0.93, green: 0.72, blue: 0.30)

struct ModelPickerView: View {
    var selectedModelId: String
    var models: [ModelOption]
    var onSelect: (String) -> Void

    private var selectedModel: ModelOption {
        models.first { $0.id == selectedModelId } ?? ModelOption(id: AvailableModels.autoID, label: "Auto", isPremium: false)
    }

    private func labelForeground(for model: ModelOption) -> Color {
        if model.isPremium {
            return premiumSelectionTextColor
        }
        return CursorTheme.textPrimary
    }

    private func labelBackground(for model: ModelOption) -> Color {
        if model.isPremium {
            return premiumSelectionBackgroundColor
        }
        return CursorTheme.surfaceMuted
    }

    private func labelBorderColor(for model: ModelOption) -> Color {
        model.isPremium ? premiumSelectionBorderColor : CursorTheme.border
    }

    private func labelShadowColor(for model: ModelOption) -> Color {
        model.isPremium ? premiumSelectionShadowColor.opacity(0.35) : .clear
    }

    var body: some View {
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
                            Text("Premium")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(premiumSelectionBadgeTextColor)
                        }
                    }
                }
            }
        } label: {
            pickerLabel(for: selectedModel)
        }
        .menuStyle(.borderlessButton)
        .colorScheme(.dark)
    }

    private func pickerLabel(for model: ModelOption) -> some View {
        HStack(spacing: 8) {
            Image(systemName: model.isPremium ? "sparkles" : "cpu")
                .font(.system(size: model.isPremium ? 14 : 12, weight: .semibold))
                .foregroundStyle(model.isPremium ? premiumSelectionAccentColor : labelForeground(for: model))
                .symbolRenderingMode(model.isPremium ? .hierarchical : .monochrome)
            Text(model.label)
                .lineLimit(1)
                .foregroundStyle(labelForeground(for: model))
                .fontWeight(model.isPremium ? .semibold : .medium)
            if model.isPremium {
                Text("Premium")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(premiumSelectionBadgeTextColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        premiumSelectionBadgeBackgroundColor.opacity(0.9),
                        in: Capsule()
                    )
            }
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(labelBackground(for: model), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(labelBorderColor(for: model), lineWidth: model.isPremium ? 1.5 : 1)
        )
        .shadow(color: labelShadowColor(for: model), radius: 12, y: 4)
    }
}
