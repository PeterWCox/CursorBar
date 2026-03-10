import SwiftUI

// MARK: - Composer action buttons (context indicator) — same row as pickers
// Processing blue matches Agent tab spinner for consistency.
private let contextWheelBlue = Color(red: 0.45, green: 0.68, blue: 1.0)

struct ComposerActionButtonsView: View {
    var hasContext: Bool
    var isRunning: Bool
    /// Context token usage for the small progress indicator; (used, limit). Pass (0, 0) to hide.
    var contextUsed: Int = 0
    var contextLimit: Int = 0

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
        }
    }

    private var contextProgressCircle: some View {
        let usedK = contextUsed / 1000
        let limitK = contextLimit / 1000
        let pct = contextLimit > 0 ? Int(round(contextFraction * 100)) : 0
        let tooltip = "~\(usedK)k / \(limitK)k tokens (\(pct)% used)"
        return ZStack {
            // Track: obvious outline
            Circle()
                .stroke(CursorTheme.borderStrong, lineWidth: 3)
            // Filled arc: same blue as Agent tab processing
            Circle()
                .trim(from: 0, to: contextFraction)
                .stroke(
                    contextWheelBlue,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 20, height: 20)
        .help(tooltip)
    }
}
