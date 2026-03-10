import SwiftUI

// MARK: - Git branch picker menu

struct GitBranchPickerView: View {
    var branches: [String]
    var currentBranch: String
    var onSelectBranch: (String) -> Void
    var onAppear: () -> Void = {}

    var body: some View {
        Menu {
            ForEach(branches, id: \.self) { branch in
                Button {
                    onSelectBranch(branch)
                } label: {
                    if branch == currentBranch {
                        Label(branch, systemImage: "checkmark")
                    } else {
                        Text(branch)
                    }
                }
            }
        } label: {
            pickerLabel(
                icon: "arrow.triangle.branch",
                title: currentBranch.isEmpty ? "No branch" : currentBranch
            )
        }
        .menuStyle(.borderlessButton)
        .foregroundColor(.white)
        .colorScheme(.dark)
        .disabled(branches.isEmpty)
        .onAppear(perform: onAppear)
    }

    private func pickerLabel(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(title)
                .lineLimit(1)
                .truncationMode(.middle)
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
