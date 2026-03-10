import SwiftUI

// MARK: - Pinned questions stack (top-left overlay)

private let maxPinnedQuestions = 8

struct PinnedQuestionsStackView: View {
    let tab: AgentTab
    let onDismiss: (UUID) -> Void

    /// Turns to show: not dismissed, first-at-top order (chronological), last N capped.
    private var visibleTurns: [ConversationTurn] {
        let undismissed = tab.turns.filter { !tab.dismissedPinnedTurnIDs.contains($0.id) }
        return Array(undismissed.suffix(maxPinnedQuestions))
    }

    var body: some View {
        Group {
            if !visibleTurns.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(visibleTurns) { turn in
                        PinnedQuestionChip(
                            question: turn.userPrompt,
                            isProcessing: turn.isStreaming,
                            onDismiss: { onDismiss(turn.id) }
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
    let isProcessing: Bool
    let onDismiss: () -> Void

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
            if isProcessing {
                LightBlueSpinner(size: 14)
                    .padding(.top, 2)
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

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(CursorTheme.textTertiary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Dismiss")
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
