import SwiftUI
import AppKit
import Textual

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

private func toolCallIcon(for status: ToolCallSegmentStatus) -> String {
    switch status {
    case .running: return "hammer"
    case .completed: return "checkmark.circle"
    case .failed: return "exclamationmark.triangle"
    case .stopped: return "square.fill"
    }
}

private func toolCallStatusLabel(for status: ToolCallSegmentStatus) -> String {
    switch status {
    case .running: return "Running"
    case .completed: return "Done"
    case .failed: return "Failed"
    case .stopped: return "Stopped"
    }
}

private func toolCallTint(for status: ToolCallSegmentStatus) -> Color {
    switch status {
    case .running: return CursorTheme.brandBlue
    case .completed: return CursorTheme.textSecondary
    case .failed: return Color(red: 1.0, green: 0.64, blue: 0.67)
    case .stopped: return Color.red
    }
}

// MARK: - Segment view

struct ConversationSegmentView: View, Equatable {
    let segment: ConversationSegment

    static func == (lhs: ConversationSegmentView, rhs: ConversationSegmentView) -> Bool {
        lhs.segment == rhs.segment
    }

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
                StructuredText(markdown: segment.text)
                    .font(.system(size: 12))
                    .foregroundStyle(CursorTheme.textSecondary)
                    .textual.textSelection(.enabled)
                    .colorScheme(.dark)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(CursorTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(CursorTheme.border, lineWidth: 1)
            )
        case .assistant:
            StructuredText(markdown: segment.text)
                .textual.structuredTextStyle(.gitHub)
                .foregroundStyle(CursorTheme.textPrimary)
                .textual.textSelection(.enabled)
                .colorScheme(.dark)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                        InlineText(markdown: toolCall.detail)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(CursorTheme.textSecondary)
                            .textual.inlineStyle(.gitHub)
                            .fixedSize(horizontal: false, vertical: true)
                            .textual.textSelection(.enabled)
                            .colorScheme(.dark)
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

struct ConversationTurnView: View, Equatable {
    let turn: ConversationTurn

    private var segments: [ConversationSegment] { visibleSegments(for: turn) }
    private var hasAssistantContent: Bool { segments.contains { $0.kind == .assistant } }

    static func == (lhs: ConversationTurnView, rhs: ConversationTurnView) -> Bool {
        lhs.turn == rhs.turn
    }

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
                } else if !hasAssistantContent && turn.displayState == .stopped {
                    StoppedPlaceholderView()
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

struct StoppedPlaceholderView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.red)
            Text("Stopped")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(CursorTheme.textSecondary)
        }
    }
}
