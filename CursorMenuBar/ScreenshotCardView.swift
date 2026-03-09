import SwiftUI
import AppKit

// MARK: - Attached screenshot card with delete

struct ScreenshotCardView: View {
    var path: String
    var workspacePath: String
    var onDelete: () -> Void

    private var imageURL: URL {
        URL(fileURLWithPath: workspacePath).appendingPathComponent(path)
    }

    private var cardBackground: some ShapeStyle {
        CursorTheme.surfaceMuted
    }

    var body: some View {
        Group {
            if let nsImage = NSImage(contentsOf: imageURL) {
                HStack(spacing: 12) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Attached screenshot")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CursorTheme.textPrimary)

                        Text(path)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CursorTheme.textSecondary)
                            .lineLimit(1)

                        Text("Included with your next prompt")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CursorTheme.textSecondary)
                    }

                    Spacer()

                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(CursorTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
        }
    }
}
