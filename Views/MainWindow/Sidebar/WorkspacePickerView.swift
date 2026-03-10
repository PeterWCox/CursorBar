import SwiftUI

// MARK: - Workspace folder picker menu

struct WorkspacePickerView: View {
    var displayName: String
    var folders: [URL]
    var selectedPath: String
    var onSelectFolder: (String) -> Void
    var onBrowse: () -> Void
    /// Called when the user opens the dropdown so the parent can reload the folder list.
    var onOpenMenu: () -> Void = {}

    @State private var isPopoverPresented = false

    var body: some View {
        Button {
            onOpenMenu()
            isPopoverPresented = true
        } label: {
            pickerLabel(icon: "folder", title: displayName)
        }
        .buttonStyle(.plain)
        .foregroundColor(.white)
        .colorScheme(.dark)
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(folders, id: \.path) { folder in
                    Button {
                        onSelectFolder(folder.path)
                        isPopoverPresented = false
                    } label: {
                        if folder.path == selectedPath {
                            Label(folder.lastPathComponent, systemImage: "checkmark")
                        } else {
                            Text(folder.lastPathComponent)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                Button("Browse other folder...") {
                    isPopoverPresented = false
                    onBrowse()
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .frame(minWidth: 220)
            .background(CursorTheme.surfaceMuted)
        }
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
