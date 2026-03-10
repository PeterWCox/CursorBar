import SwiftUI

// MARK: - Composer action buttons (context indicator, Summarize, Send/Stop)

struct ComposerActionButtonsView: View {
    var hasContext: Bool
    var isRunning: Bool
    var canSend: Bool
    /// Context token usage for the small progress indicator; (used, limit). Pass (0, 0) to hide.
    var contextUsed: Int = 0
    var contextLimit: Int = 0
    var onSummarize: () -> Void
    var onSend: () -> Void
    var onStop: () -> Void

    private var contextFraction: Double {
        guard contextLimit > 0 else { return 0 }
        return min(1, Double(contextUsed) / Double(contextLimit))
    }

    var body: some View {
        HStack(spacing: 10) {
            Spacer()

            if contextLimit > 0 {
                contextProgressCircle
            }

            Button(action: onSummarize) {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.compress.vertical")
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

    private var contextProgressCircle: some View {
        let usedK = contextUsed / 1000
        let limitK = contextLimit / 1000
        let pct = contextLimit > 0 ? Int(round(contextFraction * 100)) : 0
        let tooltip = "~\(usedK)k / \(limitK)k tokens (\(pct)% used)"
        return ZStack {
            Circle()
                .stroke(CursorTheme.surfaceMuted, lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: contextFraction)
                .stroke(
                    contextFraction > 0.85 ? CursorTheme.brandAmber : CursorTheme.brandBlue,
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 20, height: 20)
        .help(tooltip)
    }
}
