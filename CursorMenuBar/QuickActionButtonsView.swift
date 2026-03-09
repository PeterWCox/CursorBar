import SwiftUI

// MARK: - Quick action buttons (Fix Build, Commit & Push)

struct QuickActionButtonsView: View {
    var isDisabled: Bool = false
    var onFixBuild: () -> Void = {}
    var onCommitAndPush: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onFixBuild) {
                HStack(spacing: 6) {
                    Image(systemName: "wrench.and.screwdriver")
                    Text("Fix build")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CursorTheme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(CursorTheme.surfaceMuted, in: Capsule())
                .overlay(Capsule().stroke(CursorTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)

            Button(action: onCommitAndPush) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.circle")
                    Text("Commit & push")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CursorTheme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(CursorTheme.surfaceMuted, in: Capsule())
                .overlay(Capsule().stroke(CursorTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
        }
    }
}
