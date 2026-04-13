import SwiftUI

// MARK: - Light blue spinner (SwiftUI ProgressView can ignore tint on macOS)

private let spinnerLightBlue = CursorTheme.spinnerBlue

struct LightBlueSpinner: View {
    var size: CGFloat = 14

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: false)) { context in
            let rotation = context.date.timeIntervalSinceReferenceDate.remainder(dividingBy: 0.8) / 0.8 * 360
            Circle()
                .trim(from: 0.15, to: 0.85)
                .stroke(spinnerLightBlue, style: StrokeStyle(lineWidth: max(1.5, size / 8), lineCap: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(rotation))
        }
    }
}

struct StatusDot: View {
    let color: Color
    var size: CGFloat = CursorTheme.sizeStatusDotDefault

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - Tab bar chip (horizontal or vertical with optional subtitle)

struct TabChip: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    var subtitle: String? = nil
    var subtitleColor: Color? = nil
    var workspacePath: String? = nil
    var branchName: String? = nil
    let isSelected: Bool
    let isRunning: Bool
    var latestTurnState: ConversationTurnDisplayState? = nil
    /// True if the user has sent at least one message in this tab (so we can show completion icon).
    var hasPrompted: Bool = true
    let showClose: Bool
    var compact: Bool = false
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        Button(action: onSelect) {
            if compact {
                compactContent
            } else {
                fullContent
            }
        }
        .buttonStyle(.plain)
    }

    private var compactContent: some View {
        Group {
            if isRunning {
                StatusDot(color: CursorTheme.spinnerBlue, size: CursorTheme.sizeStatusDotHeader)
            } else if latestTurnState == .stopped {
                StatusDot(color: CursorTheme.semanticError, size: CursorTheme.sizeStatusDotHeader)
            } else if hasPrompted {
                StatusDot(
                    color: isSelected ? CursorTheme.brandBlue : CursorTheme.semanticReview,
                    size: CursorTheme.sizeStatusDotHeader
                )
            } else {
                StatusDot(color: CursorTheme.textTertiary(for: colorScheme), size: CursorTheme.sizeStatusDotHeader)
            }
        }
        .frame(width: CursorTheme.sizeSidebarCompactChip, height: CursorTheme.sizeSidebarCompactChip)
        .background(
            isSelected
                ? CursorTheme.surfaceRaised(for: colorScheme)
                : CursorTheme.surfaceMuted(for: colorScheme).opacity(0.58),
            in: RoundedRectangle(cornerRadius: CursorTheme.radiusSidebarRow, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CursorTheme.radiusSidebarRow, style: .continuous)
                .stroke(
                    isSelected ? CursorTheme.borderStrong(for: colorScheme) : Color.clear,
                    lineWidth: 1
                )
        )
    }

    /// Fixed width so all tab pills align; status marker is centered within.
    private static let iconContainerWidth: CGFloat = 16

    private var fullContent: some View {
        HStack(spacing: CursorTheme.spaceS) {
            Group {
                if isRunning {
                    StatusDot(color: CursorTheme.spinnerBlue, size: CursorTheme.sizeStatusDotCompact)
                } else if latestTurnState == .stopped {
                    StatusDot(color: CursorTheme.semanticError, size: CursorTheme.sizeStatusDotCompact)
                } else if hasPrompted {
                    StatusDot(color: CursorTheme.semanticReview, size: CursorTheme.sizeStatusDotCompact)
                } else {
                    StatusDot(color: CursorTheme.textTertiary(for: colorScheme), size: CursorTheme.sizeStatusDotCompact)
                }
            }
            .frame(width: Self.iconContainerWidth, height: 16, alignment: .center)

            if let sub = subtitle, !sub.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? CursorTheme.textPrimary(for: colorScheme) : CursorTheme.textSecondary(for: colorScheme))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    HStack(spacing: 4) {
                        if let path = workspacePath, !path.isEmpty {
                            WorkspaceAvatarView(workspacePath: path, displayName: nil, size: 12)
                        }
                        Text(sub)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(subtitleColor ?? CursorTheme.textTertiary(for: colorScheme))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let branch = branchName, !branch.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 9, weight: .medium))
                            Text(branch)
                                .font(.system(size: 10, weight: .regular))
                                .italic()
                        }
                        .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let branch = branchName, !branch.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? CursorTheme.textPrimary(for: colorScheme) : CursorTheme.textSecondary(for: colorScheme))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 9, weight: .medium))
                        Text(branch)
                            .font(.system(size: 10, weight: .regular))
                            .italic()
                    }
                    .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? CursorTheme.textPrimary(for: colorScheme) : CursorTheme.textSecondary(for: colorScheme))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if showClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, CursorTheme.paddingSidebarRowHorizontal)
        .padding(.vertical, CursorTheme.paddingSidebarRowVertical)
        .background(
            isSelected
                ? CursorTheme.surfaceRaised(for: colorScheme)
                : CursorTheme.surfaceMuted(for: colorScheme).opacity(0.58),
            in: RoundedRectangle(cornerRadius: CursorTheme.radiusSidebarRow, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CursorTheme.radiusSidebarRow, style: .continuous)
                .stroke(
                    isSelected ? CursorTheme.borderStrong(for: colorScheme) : Color.clear,
                    lineWidth: 1
                )
        )
    }

}
