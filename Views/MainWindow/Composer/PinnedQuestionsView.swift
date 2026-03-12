import SwiftUI

// MARK: - Pinned questions stack (top-left overlay)

private let maxPinnedQuestions = 8

struct PinnedQuestionsStackView: View {
    let tab: AgentTab
    /// Called when the user taps the close (X) button on the floating container.
    var onClose: (() -> Void)? = nil

    /// Turns to show: chronological order, capped to the latest N.
    private var visibleTurns: [ConversationTurn] {
        Array(tab.turns.suffix(maxPinnedQuestions))
    }

    var body: some View {
        Group {
            if !visibleTurns.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Previous requests")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CursorTheme.textSecondary)
                        Spacer(minLength: 8)
                        if let onClose {
                            Button(action: onClose) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(CursorTheme.textSecondary)
                                    .frame(width: 24, height: 24)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Hide questions")
                        }
                    }
                    ForEach(visibleTurns) { turn in
                        PinnedQuestionChip(
                            question: turn.userPrompt,
                            state: turn.displayState
                        )
                    }
                }
                .padding(12)
                .background(
                    CursorTheme.surfaceRaised.opacity(0.96),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(CursorTheme.border, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
                .frame(maxWidth: 320, alignment: .topLeading)
            }
        }
    }
}

// MARK: - Single pinned question chip

struct PinnedQuestionChip: View {
    let question: String
    let state: ConversationTurnDisplayState

    private var displayText: String {
        var text = question
        if let regex = try? NSRegularExpression(pattern: "\\[Screenshot attached:[^\\]]*\\]") {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Message" : trimmed
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if state == .processing {
                LightBlueSpinner(size: 14)
                    .padding(.top, 2)
            } else if state == .stopped {
                Image(systemName: "square.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.red)
                    .padding(.top, 3)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.green)
                    .padding(.top, 2)
            }

            Text(displayText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(CursorTheme.textPrimary)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(CursorTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(CursorTheme.border.opacity(0.8), lineWidth: 1)
        )
    }
}
