import SwiftUI
import AppKit

// MARK: - Create debug script sheet

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
                    .foregroundStyle(CursorTheme.semanticError)
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
