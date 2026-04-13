import SwiftUI

// MARK: - Composer action buttons (Show history, etc.)
struct ComposerActionButtonsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var showPinnedQuestionsPanel: Bool
    var hasContext: Bool
    var isRunning: Bool

    var body: some View {
        HStack(spacing: 10) {
            Spacer()

            // Only show the "show questions" control when panel is hidden; when shown, close is on the floating container.
            if !showPinnedQuestionsPanel {
                questionsPanelToggle
            }
        }
    }

    private var questionsPanelToggle: some View {
        Button(action: { showPinnedQuestionsPanel = true }) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.on.rectangle")
                Text("Show history")
                    .lineLimit(1)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(CursorTheme.surfaceMuted(for: colorScheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(CursorTheme.border(for: colorScheme), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .help("Show questions you asked in this conversation")
    }
}

// MARK: - Context usage (used on picker row in PopoutView)
private let contextWheelBlue = CursorTheme.spinnerBlue

struct ContextUsageView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var showDetails = false
    var contextUsed: Int
    var contextLimit: Int

    private var contextFraction: Double {
        guard contextLimit > 0 else { return 0 }
        return min(1, Double(contextUsed) / Double(contextLimit))
    }

    var body: some View {
        if contextLimit > 0 {
            let usedK = contextUsed / 1000
            let limitK = contextLimit / 1000
            let pct = Int(round(contextFraction * 100))
            let tooltip = "~\(usedK)k / \(limitK)k tokens (\(pct)% used)"
            Button {
                showDetails.toggle()
            } label: {
                ZStack {
                    Circle()
                        .stroke(CursorTheme.borderStrong(for: colorScheme), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: contextFraction)
                        .stroke(
                            contextWheelBlue,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 20, height: 20)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(tooltip)
            .appKitToolTip(tooltip)
            .popover(isPresented: $showDetails, arrowEdge: .bottom) {
                Text(tooltip)
                    .font(.system(size: CursorTheme.fontSecondary, weight: .regular))
                    .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                    .padding(CursorTheme.paddingCard)
                    .frame(width: 220, alignment: .leading)
                    .background(CursorTheme.surface(for: colorScheme))
                    .presentationBackground(CursorTheme.surface(for: colorScheme))
            }
            .accessibilityLabel("Context usage")
            .accessibilityValue(tooltip)
        }
    }
}

// MARK: - Usage (API/billing placeholder; CLI does not expose usage)
struct UsageView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var showDetails = false
    var isRunning: Bool = false
    private let tooltip = "Claude Code does not currently expose usage details here."

    var body: some View {
        Button {
            showDetails.toggle()
        } label: {
            HStack(spacing: CursorTheme.spaceXS) {
                if isRunning {
                    LightBlueSpinner(size: 12)
                }

                Text("$???")
                    .font(.system(size: CursorTheme.fontSmall, weight: .medium))
                    .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
            }
        }
        .buttonStyle(.plain)
        .help(tooltip)
            .appKitToolTip(tooltip)
            .popover(isPresented: $showDetails, arrowEdge: .bottom) {
                Text(tooltip)
                    .font(.system(size: CursorTheme.fontSecondary, weight: .regular))
                    .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                    .padding(CursorTheme.paddingCard)
                    .frame(width: 240, alignment: .leading)
                    .background(CursorTheme.surface(for: colorScheme))
                    .presentationBackground(CursorTheme.surface(for: colorScheme))
            }
            .accessibilityLabel(isRunning ? "Usage, processing" : "Usage")
            .accessibilityValue(tooltip)
    }
}
