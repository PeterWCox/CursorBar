import SwiftUI
import AppKit

// MARK: - Attached screenshot card with delete
// Uses shared ScreenshotThumbnailView (corner-frame overlay, tap → full preview) for consistency with tasks and draft screenshots.

struct ScreenshotCardView: View {
    var path: String
    var workspacePath: String
    var onDelete: () -> Void
    var onTapPreview: () -> Void

    private var imageURL: URL {
        screenshotFileURL(path: path, workspacePath: workspacePath)
    }

    private var cardBackground: some ShapeStyle {
        CursorTheme.surfaceMuted
    }

    var body: some View {
        HStack(spacing: CursorTheme.spaceM) {
            ScreenshotThumbnailView(
                imageURL: imageURL,
                size: CGSize(width: 84, height: 84),
                cornerRadius: CursorTheme.radiusCard,
                onTapPreview: onTapPreview,
                onDelete: nil
            )

            VStack(alignment: .leading, spacing: CursorTheme.spaceXS) {
                Text("Attached screenshot")
                    .font(.system(size: CursorTheme.fontSecondary, weight: .semibold))
                    .foregroundStyle(CursorTheme.textPrimary)

                Text(path)
                    .font(.system(size: CursorTheme.fontSmall, weight: .medium))
                    .foregroundStyle(CursorTheme.textSecondary)
                    .lineLimit(1)

                Text("Included with your next prompt")
                    .font(.system(size: CursorTheme.fontSmall, weight: .medium))
                    .foregroundStyle(CursorTheme.textSecondary)
            }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: CursorTheme.fontIconList))
                    .foregroundStyle(CursorTheme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(CursorTheme.paddingCard)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: CursorTheme.radiusCard + 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CursorTheme.radiusCard + 4, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
