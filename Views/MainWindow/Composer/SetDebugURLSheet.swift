import SwiftUI
import AppKit

// MARK: - Sheet to set or edit the project debug URL (for "View in Browser")

struct SetDebugURLSheet: View {
    var workspacePath: String
    var initialURL: String
    var onSave: (String?) -> Void
    var onOpenAfterSave: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var urlString: String = ""
    @State private var openAfterSave: Bool = true

    private let fieldBorder = Color(NSColor.separatorColor)
    private static let quickURLs = [
        "http://localhost:3000",
        "http://localhost:8080",
        "http://127.0.0.1:3000",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(CursorTheme.brandBlue)
                Text("View in Browser")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CursorTheme.textPrimary)
                Spacer()
                HStack(spacing: 8) {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(.bordered)
                    Button("Save") { saveAndOpenIfNeeded() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.bottom, 14)

            Divider()
                .opacity(0.5)
                .padding(.bottom, 16)

            // Description
            Text("Set the URL that opens when you use \"View in Browser\". Handy for local dev servers.")
                .font(.system(size: 13))
                .foregroundStyle(CursorTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)

            // URL field with label
            VStack(alignment: .leading, spacing: 6) {
                Text("URL")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CursorTheme.textSecondary)
                TextField("http://localhost:3000", text: $urlString)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(fieldBorder, lineWidth: 1))
            }
            .padding(.bottom, 12)

            // Quick-fill suggestions
            HStack(spacing: 6) {
                Text("Quick fill:")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CursorTheme.textTertiary)
                ForEach(Self.quickURLs, id: \.self) { preset in
                    Button(preset) {
                        urlString = preset
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(CursorTheme.brandBlue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(CursorTheme.surfaceMuted.opacity(0.8), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .padding(.bottom, 16)

            // Open after save
            Toggle("Open in browser after saving", isOn: $openAfterSave)
                .toggleStyle(.checkbox)
                .font(.system(size: 13))
                .foregroundStyle(CursorTheme.textPrimary)
        }
        .padding(24)
        .frame(minWidth: 420)
        .background(CursorTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(CursorTheme.border, lineWidth: 1))
        .onAppear {
            urlString = initialURL
        }
    }

    private func saveAndOpenIfNeeded() {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let toSave = trimmed.isEmpty ? nil : trimmed
        ProjectSettingsStorage.setDebugURL(workspacePath: workspacePath, toSave)
        onSave(toSave)
        dismiss()
        if openAfterSave, let value = toSave, let url = URL(string: value) {
            NSWorkspace.shared.open(url)
        }
        onOpenAfterSave?()
    }
}
