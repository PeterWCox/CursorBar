import SwiftUI

// MARK: - Quick action buttons (configurable commands + Add)

struct QuickActionButtonsView: View {
    var commands: [QuickActionCommand] = []
    var isDisabled: Bool = false
    var workspacePath: String = ""
    var onCommand: (QuickActionCommand) -> Void = { _ in }
    var onDebug: (() -> Void)? = nil
    var onAdd: (() -> Void)? = nil
    /// Called after adding a new command so the parent can refresh the list.
    var onCommandsChanged: (() -> Void)? = nil

    @State private var showAddSheet = false

    var body: some View {
        HStack(spacing: CursorTheme.spaceS) {
            ForEach(commands) { cmd in
                ActionButton(
                    title: cmd.title,
                    icon: cmd.icon,
                    action: { onCommand(cmd) },
                    isDisabled: isDisabled,
                    help: cmd.prompt
                )
            }

            // if let onDebug {
            //     Button(action: onDebug) {
            //         HStack(spacing: 6) {
            //             Image(systemName: "ladybug.fill")
            //             Text("Debug")
            //         }
            //         .font(.system(size: 12, weight: .medium))
            //         .foregroundStyle(CursorTheme.textPrimary)
            //         .padding(.horizontal, 12)
            //         .padding(.vertical, 8)
            //         .background(CursorTheme.surfaceMuted, in: Capsule())
            //         .overlay(Capsule().stroke(CursorTheme.border, lineWidth: 1))
            //     }
            //     .buttonStyle(.plain)
            //     .disabled(isDisabled)
            // }

            // Add quick action – commented out
            // if onAdd != nil {
            //     Button(action: { showAddSheet = true }) {
            //         HStack(spacing: 6) {
            //             Image(systemName: "plus")
            //             Text("Add")
            //         }
            //         .font(.system(size: 12, weight: .medium))
            //         .foregroundStyle(CursorTheme.textSecondary)
            //         .padding(.horizontal, 12)
            //         .padding(.vertical, 8)
            //         .background(CursorTheme.surfaceMuted.opacity(0.7), in: Capsule())
            //         .overlay(Capsule().stroke(CursorTheme.border, lineWidth: 1))
            //     }
            //     .buttonStyle(.plain)
            //     .disabled(isDisabled)
            //     .sheet(isPresented: $showAddSheet) {
            //         QuickActionEditSheet(workspacePath: workspacePath, existing: nil) { newCommand in
            //             saveNewCommand(newCommand)
            //             onCommandsChanged?()
            //         }
            //     }
            // }
        }
    }

    private func saveNewCommand(_ cmd: QuickActionCommand) {
        if cmd.scope == .project, !workspacePath.isEmpty {
            var project = QuickActionStorage.loadProjectCommands(workspacePath: workspacePath)
            project.append(cmd)
            QuickActionStorage.saveProjectCommands(workspacePath: workspacePath, project)
        } else {
            var global = QuickActionStorage.loadGlobalCommands()
            global.append(cmd)
            QuickActionStorage.saveGlobalCommands(global)
        }
    }
}
