import SwiftUI

// MARK: - Composer action buttons (Summarize, Send/Stop)

struct ComposerActionButtonsView: View {
    var hasContext: Bool
    var isRunning: Bool
    var canSend: Bool
    var onSummarize: () -> Void
    var onSend: () -> Void
    var onStop: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Spacer()

            Button(action: onSummarize) {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                    Text("Summarize")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hasContext ? CursorTheme.textPrimary : CursorTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    hasContext
                        ? CursorTheme.surfaceRaised
                        : CursorTheme.surfaceMuted,
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .stroke(CursorTheme.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(isRunning)

            Button(action: {
                if isRunning {
                    onStop()
                } else {
                    onSend()
                }
            }) {
                Group {
                    if isRunning {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 12, weight: .black))
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                    }
                }
                .foregroundStyle(CursorTheme.textPrimary)
                .frame(width: 36, height: 36)
                .background {
                    if isRunning {
                        Circle().fill(CursorTheme.surfaceRaised)
                    } else {
                        Circle().fill(CursorTheme.brandGradient)
                    }
                }
                .overlay(
                    Circle()
                        .stroke(
                            isRunning
                                ? CursorTheme.borderStrong
                                : Color.white.opacity(0.14),
                            lineWidth: 1
                        )
                )
                .opacity(isRunning || canSend ? 1 : 0.45)
            }
            .buttonStyle(.plain)
            .disabled(!isRunning && !canSend)
        }
    }
}
