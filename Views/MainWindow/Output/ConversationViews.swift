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

// MARK: - Animated thinking dots

private struct ThinkingDotsView: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0 ..< 3, id: \.self) { index in
                Circle()
                    .fill(CursorTheme.textSecondary)
                    .frame(width: 4, height: 4)
                    .scaleEffect(phase == index ? 1.2 : 0.85)
                    .opacity(phase == index ? 1 : 0.5)
                    .animation(.easeInOut(duration: 0.25), value: phase)
            }
        }
        .onReceive(Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()) { _ in
            phase = (phase + 1) % 3
        }
    }
}

// MARK: - Thinking block (collapsed by default for performance)

private struct ThinkingBlockView: View {
    let segment: ConversationSegment
    var renderAsPlainText: Bool = false
    /// When false, thinking has finished and we show a checkmark like other tools.
    var isStreaming: Bool = false
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    if isStreaming {
                        ThinkingDotsView()
                    } else {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(CursorTheme.textSecondary)
                    }
                    Text("Thinking")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CursorTheme.textSecondary)
                    Spacer(minLength: 8)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CursorTheme.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered in
                if isHovered { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }

            if isExpanded {
                Group {
                    if renderAsPlainText {
                        Text(segment.text)
                            .font(.system(size: 12))
                            .foregroundStyle(CursorTheme.textSecondary)
                            .textSelection(.enabled)
                    } else {
                        StructuredText(markdown: segment.text)
                            .font(.system(size: 12))
                            .foregroundStyle(CursorTheme.textSecondary)
                            .textual.textSelection(.enabled)
                            .colorScheme(.dark)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(CursorTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CursorTheme.border, lineWidth: 1)
        )
    }
}

// MARK: - Segment view

struct ConversationSegmentView: View, Equatable {
    let segment: ConversationSegment
    /// When true, render as plain text (no markdown parsing). Use during streaming to reduce CPU.
    var renderAsPlainText: Bool = false
    /// When true for a thinking segment, show animated dots; when false, show checkmark (finished).
    var isStreaming: Bool = false

    static func == (lhs: ConversationSegmentView, rhs: ConversationSegmentView) -> Bool {
        lhs.segment == rhs.segment && lhs.renderAsPlainText == rhs.renderAsPlainText && lhs.isStreaming == rhs.isStreaming
    }

    var body: some View {
        switch segment.kind {
        case .thinking:
            ThinkingBlockView(segment: segment, renderAsPlainText: renderAsPlainText, isStreaming: isStreaming)
        case .assistant:
            Group {
                if renderAsPlainText {
                    Text(segment.text)
                        .foregroundStyle(CursorTheme.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    StructuredText(markdown: segment.text)
                        .textual.structuredTextStyle(.gitHub)
                        .foregroundStyle(CursorTheme.textPrimary)
                        .textual.textSelection(.enabled)
                        .colorScheme(.dark)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
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

// MARK: - User message content (text + inline screenshots, no "[Screenshot attached: ...]" text)

private struct UserMessageContentView: View {
    let prompt: String
    let workspacePath: String
    @Binding var screenshotPreviewURL: URL?

    private var displayText: String { userPromptDisplayText(from: prompt) }
    private var paths: [String] { screenshotPaths(from: prompt) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !displayText.isEmpty {
                Text(displayText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(CursorTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            ForEach(Array(paths.enumerated()), id: \.offset) { _, path in
                UserMessageScreenshotView(path: path, workspacePath: workspacePath, screenshotPreviewURL: $screenshotPreviewURL)
            }
        }
    }
}

private struct UserMessageScreenshotView: View {
    let path: String
    let workspacePath: String
    @Binding var screenshotPreviewURL: URL?

    private var imageURL: URL {
        URL(fileURLWithPath: workspacePath).appendingPathComponent(path)
    }

    var body: some View {
        if let nsImage = NSImage(contentsOf: imageURL) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 200, maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(CursorTheme.border, lineWidth: 1)
                )
                .onTapGesture { screenshotPreviewURL = imageURL }
                .contentShape(Rectangle())
        }
    }
}

// MARK: - Turn view

struct ConversationTurnView: View, Equatable {
    let turn: ConversationTurn
    var workspacePath: String = ""
    @Binding var screenshotPreviewURL: URL?

    @State private var showCopiedFeedback = false

    private var segments: [ConversationSegment] { visibleSegments(for: turn) }
    private var hasAssistantContent: Bool { segments.contains { $0.kind == .assistant } }

    static func == (lhs: ConversationTurnView, rhs: ConversationTurnView) -> Bool {
        lhs.turn == rhs.turn && lhs.workspacePath == rhs.workspacePath
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if !workspacePath.isEmpty {
                    UserMessageContentView(prompt: turn.userPrompt, workspacePath: workspacePath, screenshotPreviewURL: $screenshotPreviewURL)
                } else {
                    Text(turn.userPrompt)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(CursorTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .padding(.trailing, 36)
            .background(CursorTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(CursorTheme.border, lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 6) {
                    if showCopiedFeedback {
                        Text("Copied!")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(CursorTheme.textPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(CursorTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(CursorTheme.border, lineWidth: 1)
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    }
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(turn.userPrompt, forType: .string)
                        withAnimation(.easeOut(duration: 0.2)) { showCopiedFeedback = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(.easeIn(duration: 0.2)) { showCopiedFeedback = false }
                        }
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(CursorTheme.textSecondary)
                            .contentShape(Rectangle())
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help("Copy message")
                    .onHover { isHovered in
                        if isHovered {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                }
                .padding(6)
            }

            VStack(alignment: .leading, spacing: 14) {
                ForEach(segments) { segment in
                    let isStreamingSegment = turn.isStreaming && segment.id == segments.last?.id && (segment.kind == .assistant || segment.kind == .thinking)
                    ConversationSegmentView(segment: segment, renderAsPlainText: isStreamingSegment, isStreaming: isStreamingSegment)
                        .equatable()
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
