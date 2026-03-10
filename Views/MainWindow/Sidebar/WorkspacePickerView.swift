import SwiftUI

// MARK: - Workspace folder picker menu

struct WorkspacePickerView: View {
    var displayName: String
    var folders: [URL]
    var selectedPath: String
    var onSelectFolder: (String) -> Void
    var onBrowse: () -> Void
    var onAppear: () -> Void = {}

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
            Divider()
            Button("Browse other folder...", action: onBrowse)
        } label: {
            pickerLabel(icon: "folder", title: displayName)
        }
        .menuStyle(.borderlessButton)
        .foregroundColor(.white)
        .colorScheme(.dark)
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
