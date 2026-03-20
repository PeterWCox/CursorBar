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
                LightBlueSpinner(size: 15)
            } else if latestTurnState == .stopped {
                Image(systemName: "square.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CursorTheme.semanticError)
            } else if hasPrompted {
                Image(systemName: "clock.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(isSelected ? CursorTheme.brandBlue : CursorTheme.semanticReview)
            } else {
                Image(systemName: "bubble.left")
                    .font(.system(size: 15))
                    .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
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

    /// Fixed width so all tab pills align; icon (spinner/symbol) is centered within.
    private static let iconContainerWidth: CGFloat = 16

    private var fullContent: some View {
        HStack(spacing: CursorTheme.spaceS) {
            Group {
                if isRunning {
                    LightBlueSpinner(size: 10)
                } else if latestTurnState == .stopped {
                    Image(systemName: "square.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CursorTheme.semanticError)
                } else if hasPrompted {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(CursorTheme.semanticReview)
                } else {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 12))
                        .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
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
