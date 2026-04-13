import SwiftUI

// MARK: - Add/Edit quick action sheet (title, prompt, scope chips; icon derived from scope)

struct QuickActionEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    var workspacePath: String = ""
    var existing: QuickActionCommand?
    var onSave: (QuickActionCommand) -> Void

    @State private var title: String = ""
    @State private var prompt: String = ""
    @State private var scope: QuickActionCommand.Scope = .global

    private var isEditing: Bool { existing != nil }

    /// Icon derived from scope: globe = global, folder = this project only.
    private static func icon(for scope: QuickActionCommand.Scope) -> String {
        switch scope {
        case .global: return "globe"
        case .project: return "folder"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Text(isEditing ? "Edit quick action" : "Add quick action")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                HStack(spacing: 8) {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(.bordered)
                    Button("Save") { saveAndDismiss() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.bottom, 2)

            Divider()
                .opacity(0.5)

            // Outline visible on both light and dark sheet background
            let fieldBorder = Color(NSColor.separatorColor)

            // Title
            VStack(alignment: .leading, spacing: 4) {
                Text("Title")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CursorTheme.textSecondary)
                TextField("e.g. Fix build", text: $title)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(fieldBorder, lineWidth: 1))
            }

            // Prompt
            VStack(alignment: .leading, spacing: 4) {
                Text("Prompt")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CursorTheme.textSecondary)
                TextEditor(text: $prompt)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 52, maxHeight: 88)
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(fieldBorder, lineWidth: 1))
            }

            // Scope chips: Global / Local (this project only)
            VStack(alignment: .leading, spacing: 4) {
                Text("Scope")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CursorTheme.textSecondary)
                HStack(spacing: 8) {
                    ScopeChip(
                        title: "Global",
                        systemImage: "globe",
                        isSelected: scope == .global
                    ) { scope = .global }
                    ScopeChip(
                        title: "Local",
                        systemImage: "folder",
                        isSelected: scope == .project
                    ) { scope = .project }
                }
                Text(scope == .global ? "Available in all workspaces." : "Only shown in the active project.")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(CursorTheme.textTertiary)
            }
        }
        .padding(18)
        .frame(width: 360)
        .onAppear {
            if let e = existing {
                title = e.title
                prompt = e.prompt
                scope = e.scope
            } else {
                title = ""
                prompt = ""
                scope = .global
            }
        }
    }

    private func saveAndDismiss() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedPrompt.isEmpty else { return }

        let cmd = QuickActionCommand(
            id: existing?.id ?? UUID(),
            title: trimmedTitle,
            prompt: trimmedPrompt,
            icon: Self.icon(for: scope),
            scope: scope
        )
        onSave(cmd)
        dismiss()
    }
}

// MARK: - Scope chip (selectable Global / Local)

private struct ScopeChip: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(isSelected ? Color.white : CursorTheme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? CursorTheme.brandBlue : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                if !isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color(NSColor.separatorColor), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
