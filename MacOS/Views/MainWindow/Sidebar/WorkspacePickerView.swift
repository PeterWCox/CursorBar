import SwiftUI

// MARK: - Button style that runs when the user presses (e.g. to open a Menu)

private struct RefreshOnOpenMenuButtonStyle: ButtonStyle {
    var onPress: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    onPress()
                }
            }
    }
}

// MARK: - Workspace folder picker menu

struct WorkspacePickerView: View {
    var displayName: String
    var folders: [URL]
    var selectedPath: String
    var onSelectFolder: (String) -> Void
    /// Called when the user opens the dropdown so the parent can reload the folder list.
    var onOpenMenu: () -> Void = {}

    var body: some View {
        Menu {
            ForEach(folders, id: \.path) { folder in
                Button {
                    onSelectFolder(folder.path)
                } label: {
                    if folder.path == selectedPath {
                        Label(folder.lastPathComponent, systemImage: "checkmark")
                    } else {
                        Text(folder.lastPathComponent)
                    }
                }
            }
        } label: {
            pickerLabel(icon: "folder", title: displayName)
        }
        .buttonStyle(RefreshOnOpenMenuButtonStyle(onPress: onOpenMenu))
        .menuStyle(.borderlessButton)
        .foregroundColor(.white)
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
