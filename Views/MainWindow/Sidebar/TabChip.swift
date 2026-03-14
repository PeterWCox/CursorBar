import SwiftUI
import AppKit

// MARK: - Light blue spinner (SwiftUI ProgressView can ignore tint on macOS)

private let spinnerLightBlue = CursorTheme.spinnerBlue

struct LightBlueSpinner: View {
    var size: CGFloat = 14
    @State private var rotation: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0.15, to: 0.85)
            .stroke(spinnerLightBlue, style: StrokeStyle(lineWidth: max(1.5, size / 8), lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) { rotation = 360 }
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
                LightBlueSpinner(size: 14)
            } else if latestTurnState == .stopped {
                Image(systemName: "clock.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CursorTheme.semanticReview)
            } else if hasPrompted {
                Image(systemName: "clock.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? CursorTheme.brandBlue : CursorTheme.semanticReview)
            } else {
                Image(systemName: "bubble.left")
                    .font(.system(size: 14))
                    .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
            }
        }
        .frame(width: 28, height: 28)
        .background(
            isSelected
                ? CursorTheme.surfaceRaised(for: colorScheme)
                : CursorTheme.surfaceMuted(for: colorScheme),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? CursorTheme.borderStrong(for: colorScheme) : CursorTheme.border(for: colorScheme).opacity(0.6), lineWidth: 1)
        )
    }

    private var fullContent: some View {
        HStack(spacing: 6) {
            if isRunning {
                LightBlueSpinner(size: 10)
            } else if latestTurnState == .stopped {
                Image(systemName: "clock.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CursorTheme.semanticReview)
            } else if hasPrompted {
                Image(systemName: "clock.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(CursorTheme.semanticReview)
            } else {
                Image(systemName: "bubble.left")
                    .font(.system(size: 12))
                    .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
            }

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
                            ProjectIconView(path: path)
                                .frame(width: 12, height: 12)
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
                .frame(maxWidth: 160, alignment: .leading)
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
        .padding(.horizontal, CursorTheme.paddingCard)
        .padding(.vertical, CursorTheme.spaceS)
        .background(
            isSelected
                ? CursorTheme.surfaceRaised(for: colorScheme)
                : CursorTheme.surfaceMuted(for: colorScheme),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? CursorTheme.borderStrong(for: colorScheme) : CursorTheme.border(for: colorScheme).opacity(0.6), lineWidth: 1)
        )
    }

}

// MARK: - Project / folder icon from path (uses system icon, including custom folder icons)

struct ProjectIconView: View {
    let path: String

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .aspectRatio(contentMode: .fit)
    }
}
