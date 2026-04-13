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
    case .failed: return CursorTheme.semanticErrorTint
    case .stopped: return CursorTheme.semanticError
    }
}

/// Fixed size for segment status icons so checkmark, thinking dots, and tool icons align.
private let kSegmentStatusIconWidth: CGFloat = 24
private let kSegmentStatusIconHeight: CGFloat = 12

// MARK: - Shared segment block container

/// Reusable card for conversation segment blocks (thinking, tool calls). Provides consistent
/// layout, padding, background, and border; callers supply header row and optional body content.
private struct SegmentBlockContainer<Header: View, Content: View>: View {
    /// When non-nil, border uses this tint at 0.18 opacity (e.g. tool call status). When nil, uses `CursorTheme.border`.
    var borderTint: Color? = nil
    @ViewBuilder let header: () -> Header
    @ViewBuilder let content: () -> Content

    private var strokeStyle: (color: Color, lineWidth: CGFloat) {
        if let tint = borderTint {
            return (tint.opacity(0.18), 1)
        }
        return (CursorTheme.border, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header()
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CursorTheme.paddingCard)
        .background(CursorTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(strokeStyle.color, lineWidth: strokeStyle.lineWidth)
        )
    }
}

/// Standard header row for segment blocks: fixed-size icon + title + spacer + trailing (e.g. chevron or status badge).
private func segmentBlockHeaderRow<Icon: View, Trailing: View>(
    @ViewBuilder icon: () -> Icon,
    title: String,
    titleColor: Color,
    @ViewBuilder trailing: () -> Trailing
) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
        icon()
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(titleColor)
            .lineLimit(2)
        Spacer(minLength: 8)
        trailing()
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
            }
        }
        .animation(.easeInOut(duration: 0.25), value: phase)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 450_000_000)
                phase = (phase + 1) % 3
            }
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
        SegmentBlockContainer(borderTint: nil) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                segmentBlockHeaderRow(
                    icon: {
                        Group {
                            if isStreaming {
                                ThinkingDotsView()
                            } else {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(CursorTheme.textSecondary)
                            }
                        }
                        .frame(width: kSegmentStatusIconWidth, height: kSegmentStatusIconHeight)
                    },
                    title: "Thinking",
                    titleColor: CursorTheme.textSecondary,
                    trailing: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(CursorTheme.textSecondary)
                    }
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered in
                if isHovered { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        } content: {
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
                    }
                }
            }
        }
    }
}

// MARK: - Tool call block (collapsed by default, expanded while running)

private struct ToolCallBlockView: View {
    let toolCall: ToolCallSegmentData
    @State private var isExpanded: Bool

    init(toolCall: ToolCallSegmentData) {
        self.toolCall = toolCall
        self._isExpanded = State(initialValue: toolCall.status == .running)
    }

    private var hasDetail: Bool { !toolCall.detail.isEmpty }

    var body: some View {
        let tint = toolCallTint(for: toolCall.status)
        SegmentBlockContainer(borderTint: tint) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                segmentBlockHeaderRow(
                    icon: {
                        Image(systemName: toolCallIcon(for: toolCall.status))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(tint)
                            .frame(width: kSegmentStatusIconWidth, height: kSegmentStatusIconHeight)
                    },
                    title: toolCall.title,
                    titleColor: CursorTheme.textPrimary,
                    trailing: {
                        HStack(spacing: 6) {
                            Text(toolCallStatusLabel(for: toolCall.status))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(tint)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(tint.opacity(0.14), in: Capsule())
                            if hasDetail {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(CursorTheme.textSecondary)
                                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            }
                        }
                    }
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!hasDetail)
            .onHover { isHovered in
                guard hasDetail else { return }
                if isHovered { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        } content: {
            if isExpanded && hasDetail {
                InlineText(markdown: toolCall.detail)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(CursorTheme.textSecondary)
                    .textual.inlineStyle(.gitHub)
                    .fixedSize(horizontal: false, vertical: true)
                    .textual.textSelection(.enabled)
            }
        }
        .onChange(of: toolCall.status) { newStatus in
            if newStatus != .running {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded = false }
            }
        }
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .toolCall:
            if let toolCall = segment.toolCall {
                ToolCallBlockView(toolCall: toolCall)
            }
        }
    }
}

// MARK: - User message content (text + inline screenshots, no "[Screenshot attached: ...]" text)

private struct UserMessageContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    let prompt: String
    let workspacePath: String
    let onPreviewScreenshots: ([String], String) -> Void
    private let displayText: String
    private let paths: [String]

    init(prompt: String, workspacePath: String, onPreviewScreenshots: @escaping ([String], String) -> Void) {
        self.prompt = prompt
        self.workspacePath = workspacePath
        self.onPreviewScreenshots = onPreviewScreenshots
        displayText = userPromptDisplayText(from: prompt)
        paths = screenshotPaths(from: prompt)
    }

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
            if let firstPath = paths.first {
                UserMessageScreenshotSummaryView(
                    path: firstPath,
                    workspacePath: workspacePath,
                    screenshotCount: paths.count,
                    onOpenPreview: { onPreviewScreenshots(paths, firstPath) }
                )
            }
        }
    }
}

private struct UserMessageScreenshotSummaryView: View {
    @Environment(\.colorScheme) private var colorScheme
    let path: String
    let workspacePath: String
    let screenshotCount: Int
    let onOpenPreview: () -> Void
    @State private var loadedImage: NSImage?

    private var imageURL: URL {
        screenshotFileURL(path: path, workspacePath: workspacePath)
    }

    private var badgeText: String {
        screenshotCount > 99 ? "99+" : "\(screenshotCount)"
    }

    var body: some View {
        Group {
            if let nsImage = loadedImage {
                ScreenshotThumbnailView(
                    image: nsImage,
                    size: CGSize(width: 42, height: 42),
                    cornerRadius: CursorTheme.spaceS,
                    onTapPreview: onOpenPreview
                )
            } else {
                RoundedRectangle(cornerRadius: CursorTheme.spaceS, style: .continuous)
                    .fill(CursorTheme.surfaceMuted(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: CursorTheme.spaceS, style: .continuous)
                            .stroke(CursorTheme.border(for: colorScheme), lineWidth: 1)
                    )
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                    }
                    .frame(width: 42, height: 42)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onOpenPreview)
            }
        }
        .overlay(alignment: .topTrailing) {
            Text(badgeText)
                .font(.system(size: CursorTheme.fontCaption, weight: .semibold))
                .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                .padding(.horizontal, CursorTheme.paddingBadgeHorizontal)
                .padding(.vertical, CursorTheme.paddingBadgeVertical)
                .background(CursorTheme.surface(for: colorScheme), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(CursorTheme.borderStrong(for: colorScheme), lineWidth: 1)
                )
                .padding(CursorTheme.spaceXS)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(screenshotCount) screenshots attached")
        .task(id: imageURL.path) {
            if let cached = ImageAssetCache.shared.cachedScreenshot(for: imageURL) {
                loadedImage = cached
                return
            }

            let image = await ImageAssetCache.shared.loadScreenshot(for: imageURL)
            guard !Task.isCancelled else { return }
            loadedImage = image
        }
    }
}

// MARK: - Turn view

struct ConversationTurnView: View, Equatable {
    let turn: ConversationTurn
    var workspacePath: String = ""
    var onPreviewScreenshots: ([String], String) -> Void = { _, _ in }

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
                    UserMessageContentView(
                        prompt: turn.userPrompt,
                        workspacePath: workspacePath,
                        onPreviewScreenshots: onPreviewScreenshots
                    )
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
    @State private var dotCount = 1

    var body: some View {
        HStack(spacing: 8) {
            LightBlueSpinner(size: 16)
            Text("Processing request" + String(repeating: ".", count: dotCount))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(CursorTheme.textSecondary)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 400_000_000)
                dotCount = dotCount == 3 ? 1 : dotCount + 1
            }
        }
    }
}

struct StoppedPlaceholderView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CursorTheme.semanticReview)
            Text("Review")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(CursorTheme.textSecondary)
        }
    }
}
