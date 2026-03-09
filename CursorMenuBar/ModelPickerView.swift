import SwiftUI

// MARK: - Model selection menu

struct ModelPickerView: View {
    var selectedModelId: String
    var models: [(id: String, label: String)]
    var onSelect: (String) -> Void

    private var selectedLabel: String {
        models.first { $0.id == selectedModelId }?.label ?? selectedModelId
    }

    var body: some View {
        Menu {
            ForEach(models, id: \.id) { model in
                Button {
                    onSelect(model.id)
                } label: {
                    if model.id == selectedModelId {
                        Label(model.label, systemImage: "checkmark")
                    } else {
                        Text(model.label)
                    }
                }
            }
        } label: {
            pickerLabel(icon: "cpu", title: selectedLabel)
        }
        .menuStyle(.borderlessButton)
        .foregroundColor(.white)
        .colorScheme(.dark)
    }

    private func pickerLabel(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(title)
                .lineLimit(1)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(CursorTheme.textPrimary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CursorTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(CursorTheme.border, lineWidth: 1)
        )
    }
}
