import SwiftUI
import AppKit

// MARK: - Conversation segment and turn presentation

/// Segments to show in the UI (non-empty text or tool calls with a title).
func visibleSegments(for turn: ConversationTurn) -> [ConversationSegment] {
    turn.segments.compactMap { segment in
        if segment.kind == .toolCall {
            guard let title = segment.toolCall?.title.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else {
                return nil
            }
            return segment
        }
        let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return segment
    }
}

private func inlineAttributedText(_ raw: String) -> AttributedString {
    let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    return (try? AttributedString(markdown: raw, options: opts)) ?? AttributedString(raw)
}

private func toolCallIcon(for status: ToolCallSegmentStatus) -> String {
    switch status {
    case .running: return "hammer"
    case .completed: return "checkmark.circle"
    case .failed: return "exclamationmark.triangle"
    }
}

private func toolCallStatusLabel(for status: ToolCallSegmentStatus) -> String {
    switch status {
    case .running: return "Running"
    case .completed: return "Done"
    case .failed: return "Failed"
    }
}

private func toolCallTint(for status: ToolCallSegmentStatus) -> Color {
    switch status {
    case .running: return CursorTheme.brandBlue
    case .completed: return CursorTheme.textSecondary
    case .failed: return Color(red: 1.0, green: 0.64, blue: 0.67)
    }
}

// MARK: - Segment view

struct ConversationSegmentView: View {
    let segment: ConversationSegment

    var body: some View {
        switch segment.kind {
        case .thinking:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(CursorTheme.textSecondary)
                    Text("Thinking")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CursorTheme.textSecondary)
                }
                Text(segment.text)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(CursorTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(CursorTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(CursorTheme.border, lineWidth: 1)
            )
        case .assistant:
            MarkdownContentView(segment.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        case .toolCall:
            if let toolCall = segment.toolCall {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: toolCallIcon(for: toolCall.status))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(toolCallTint(for: toolCall.status))
                        Text(toolCall.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CursorTheme.textPrimary)
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        Text(toolCallStatusLabel(for: toolCall.status))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(toolCallTint(for: toolCall.status))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(toolCallTint(for: toolCall.status).opacity(0.14), in: Capsule())
                    }
                    if !toolCall.detail.isEmpty {
                        Text(inlineAttributedText(toolCall.detail))
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(CursorTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(CursorTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(toolCallTint(for: toolCall.status).opacity(0.18), lineWidth: 1)
                )
            }
        }
    }
}

// MARK: - Turn view

struct ConversationTurnView: View {
    let turn: ConversationTurn

    private var segments: [ConversationSegment] { visibleSegments(for: turn) }
    private var hasAssistantContent: Bool { segments.contains { $0.kind == .assistant } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Text(turn.userPrompt)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(CursorTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(CursorTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(CursorTheme.border, lineWidth: 1)
                    )
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(turn.userPrompt, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CursorTheme.textSecondary)
                        .contentShape(Rectangle())
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Copy message")
            }

            VStack(alignment: .leading, spacing: 14) {
                ForEach(segments) { segment in
                    ConversationSegmentView(segment: segment)
                }
                if !hasAssistantContent && turn.isStreaming {
                    ProcessingPlaceholderView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Streaming placeholder

struct ProcessingPlaceholderView: View {
    var body: some View {
        HStack(spacing: 8) {
            LightBlueSpinner(size: 16)
            TimelineView(.periodic(from: .now, by: 0.4)) { timeline in
                let dotCount = (Int(timeline.date.timeIntervalSince1970 * 2.5) % 3) + 1
                Text("Processing request" + String(repeating: ".", count: dotCount))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CursorTheme.textSecondary)
                    .animation(.easeInOut(duration: 0.2), value: dotCount)
            }
        }
    }
}
