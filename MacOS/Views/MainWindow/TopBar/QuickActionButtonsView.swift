import SwiftUI

// MARK: - Quick action buttons (configurable commands + Add)

struct QuickActionButtonsView: View {
    var commands: [QuickActionCommand] = []
    var isDisabled: Bool = false
    var onCommand: (QuickActionCommand) -> Void = { _ in }

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
        }
    }
}
