import SwiftUI
import AppKit

// MARK: - Shared screenshot thumbnail + full preview
// Use ScreenshotThumbnailView for any screenshot (saved or draft) that should show a corner-frame "zoom"
// affordance and open in ScreenshotPreviewModal on tap. Parent holds preview state (URL? and/or NSImage?)
// and presents ScreenshotPreviewModal in an overlay when non-nil. Used by: conversation attachments
// (ScreenshotCardView), existing task screenshots, and new/edit task draft screenshots.

// MARK: - Corner-frame "expand preview" overlay (square with corners only)

/// Reusable shape: rectangle with only the four corners drawn (common "view larger" affordance).
struct CornerFrameShape: Shape {
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

/// Dark scrim + corner-frame icon overlay for screenshot thumbnails. Tap to open full preview.
struct ScreenshotExpandPreviewOverlay: View {
    var cornerRadius: CGFloat = 6
    var cornerFrameSize: CGFloat = 20

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            CornerFrameShape(cornerLength: 4, strokeWidth: 2)
                .stroke(Color.white.opacity(0.9), lineWidth: 2)
                .frame(width: cornerFrameSize, height: cornerFrameSize)
        }
    }
}

// MARK: - Reusable screenshot thumbnail (URL or NSImage) with preview affordance

/// Single screenshot thumbnail with corner-frame "expand" overlay; tap opens full preview. Use for tasks (saved or draft) and conversation attachments.
struct ScreenshotThumbnailView: View {
    @Environment(\.colorScheme) private var colorScheme

    /// Image from file (saved task screenshots, conversation attachments).
    var imageURL: URL?
    /// In-memory image (new/edit task draft screenshots).
    var image: NSImage?

    var size: CGSize = CGSize(width: 56, height: 56)
    var cornerRadius: CGFloat = 6
    var onTapPreview: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var displayImage: NSImage?

    private var resolvedImage: NSImage? {
        image ?? displayImage
    }

    private var showsPreviewAffordance: Bool {
        onTapPreview != nil
    }

    var body: some View {
        Group {
            if let nsImage = resolvedImage {
                thumbnailContent(nsImage: nsImage)
            } else if imageURL != nil {
                // Placeholder while loading from URL (e.g. pasted screenshot in agent composer)
                thumbnailPlaceholder
            }
        }
        .task(id: imageURL?.path ?? image?.hash.description ?? "") {
            if let imageURL {
                if let cached = ImageAssetCache.shared.cachedScreenshot(for: imageURL) {
                    displayImage = cached
                    return
                }

                let loadedImage = await ImageAssetCache.shared.loadScreenshot(for: imageURL)
                guard !Task.isCancelled else { return }
                displayImage = loadedImage
            } else {
                displayImage = nil
            }
        }
    }

    @ViewBuilder
    private func thumbnailContent(nsImage: NSImage) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(CursorTheme.border(for: colorScheme), lineWidth: 1)
                )
                .overlay {
                    if showsPreviewAffordance {
                        ScreenshotExpandPreviewOverlay(
                            cornerRadius: cornerRadius,
                            cornerFrameSize: min(size.width, size.height) * 0.36
                        )
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard let onTapPreview else { return }
                    onTapPreview()
                }

            if onDelete != nil {
                Button(action: { onDelete?() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var thumbnailPlaceholder: some View {
        HStack(alignment: .center, spacing: 6) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(CursorTheme.surfaceMuted(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(CursorTheme.border(for: colorScheme), lineWidth: 1)
                )
                .overlay {
                    Image(systemName: "photo")
                        .font(.system(size: min(size.width, size.height) * 0.4))
                        .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                }
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard let onTapPreview else { return }
                    onTapPreview()
                }

            if onDelete != nil {
                Button(action: { onDelete?() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
