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
        AppDialogSheet(
            icon: "globe",
            title: "View in Browser",
            onCancel: { dismiss() },
            primaryTitle: "Save",
            primaryAction: saveAndOpenIfNeeded,
            minWidth: 420
        ) {
            Text("Set the URL that opens when you use \"View in Browser\". Handy for local dev servers.")
                .font(.system(size: 13))
                .foregroundStyle(CursorTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)

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

            Toggle("Open in browser after saving", isOn: $openAfterSave)
                .toggleStyle(.checkbox)
                .font(.system(size: 13))
                .foregroundStyle(CursorTheme.textPrimary)
        }
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

struct CreateDebugScriptSheet: View {
    var workspacePath: String
    var onSave: (() -> Void)? = nil
    var onRunAfterSave: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var scriptContents: String = """
#!/bin/bash

"""
    @State private var errorMessage: String?

    var body: some View {
        AppDialogSheet(
            icon: "ladybug.fill",
            title: "Create debug.sh",
            onCancel: { dismiss() },
            primaryTitle: "Create & Run",
            primaryAction: { saveAndMaybeRun(true) },
            secondaryPrimaryTitle: "Create",
            secondaryPrimaryAction: { saveAndMaybeRun(false) },
            minWidth: 560,
            minHeight: 420
        ) {
            Text("`debug.sh` was not found in the project root. Paste the script below and it will be saved to `\(workspacePath)/debug.sh`.")
                .font(.system(size: 13))
                .foregroundStyle(CursorTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)

            TextEditor(text: $scriptContents)
                .font(.system(.body, design: .monospaced))
                .padding(10)
                .frame(minHeight: 260)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.red)
                    .padding(.top, 12)
            }
        }
    }

    private func saveAndMaybeRun(_ shouldRun: Bool) {
        let trimmed = scriptContents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Paste a script before creating `debug.sh`."
            return
        }

        do {
            try createDebugScript(workspacePath: workspacePath, contents: scriptContents)
            onSave?()
            dismiss()
            if shouldRun {
                onRunAfterSave?()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
