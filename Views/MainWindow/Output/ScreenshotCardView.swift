import SwiftUI
import AppKit

// MARK: - Four-corner "expand preview" icon overlay

private struct ExpandPreviewIcon: View {
    var body: some View {
        let cornerLen: CGFloat = 8
        let stroke: CGFloat = 2
        ZStack(alignment: .center) {
            Color.black.opacity(0.25)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            // Box with only corners (common "view larger" affordance)
            CornerFrameShape(cornerLength: cornerLen, strokeWidth: stroke)
                .stroke(Color.white.opacity(0.9), lineWidth: stroke)
                .frame(width: 32, height: 32)
        }
    }
}

private struct CornerFrameShape: Shape {
    var cornerLength: CGFloat
    var strokeWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = cornerLength
        var path = Path()
        // Top-left
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + c))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + c, y: rect.minY))
        // Top-right
        path.move(to: CGPoint(x: rect.maxX - c, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + c))
        // Bottom-right
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - c))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - c, y: rect.maxY))
        // Bottom-left
        path.move(to: CGPoint(x: rect.minX + c, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - c))
        return path
    }
}

// MARK: - Attached screenshot card with delete

struct ScreenshotCardView: View {
    var path: String
    var workspacePath: String
    var onDelete: () -> Void
    var onTapPreview: () -> Void

    private var imageURL: URL {
        URL(fileURLWithPath: workspacePath).appendingPathComponent(path)
    }

    private var expandPreviewIcon: some View {
        ExpandPreviewIcon()
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
                        .overlay(expandPreviewIcon)
                        .onTapGesture { onTapPreview() }
                        .contentShape(Rectangle())

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
