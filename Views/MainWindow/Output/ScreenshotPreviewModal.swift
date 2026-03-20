import SwiftUI
import AppKit

// MARK: - Full-screen modal to preview screenshot(s) at larger size
// Pair with ScreenshotThumbnailView: parent shows this modal when user taps a thumbnail (same pattern
// in PopoutView, TasksListView for existing tasks and new/edit task draft screenshots).
// Multiple images are shown side by side; optional onDeleteScreenshotAtIndex adds an X on each image to delete.

struct ScreenshotPreviewModal: View {
    /// Multiple saved screenshots (e.g. task with several screenshots). Shown side by side.
    var imageURLs: [URL]? = nil
    /// Multiple in-memory screenshots (e.g. create/edit task drafts before save).
    var images: [NSImage]? = nil
    /// Initial index when showing imageURLs. Ignored when imageURLs is nil or empty.
    var initialIndex: Int = 0
    /// Single saved screenshot (file URL). Used when previewing one image from PopoutView/conversation.
    var imageURL: URL? = nil
    /// In-memory image (e.g. new or edit task draft). When set, shown instead of loading from URL(s).
    var image: NSImage? = nil
    @Binding var isPresented: Bool
    /// When non-nil, an X is shown in the top-right of each image to delete that screenshot (by index).
    var onDeleteScreenshotAtIndex: ((Int) -> Void)? = nil

    @State private var escapeMonitor: Any? = nil
    @State private var currentIndex: Int

    private var urls: [URL] {
        if let imageURLs, !imageURLs.isEmpty { return imageURLs }
        if let url = imageURL { return [url] }
        return []
    }

    private var inMemoryImages: [NSImage] {
        if let images, !images.isEmpty { return images }
        if let image { return [image] }
        return []
    }

    private var displayCount: Int {
        if !inMemoryImages.isEmpty { return inMemoryImages.count }
        return urls.count
    }

    private var hasMultiple: Bool { displayCount > 1 }
    private var selectedIndex: Int {
        guard displayCount > 0 else { return 0 }
        return min(max(currentIndex, 0), displayCount - 1)
    }
    private var selectedURL: URL? {
        guard !urls.isEmpty else { return nil }
        return urls[selectedIndex]
    }

    private var currentDisplayImage: NSImage? {
        if !inMemoryImages.isEmpty {
            return inMemoryImages[selectedIndex]
        }
        guard let url = selectedURL else { return nil }
        return ImageAssetCache.shared.screenshot(for: url)
    }

    init(
        imageURLs: [URL]? = nil,
        images: [NSImage]? = nil,
        initialIndex: Int = 0,
        imageURL: URL? = nil,
        image: NSImage? = nil,
        isPresented: Binding<Bool>,
        onDeleteScreenshotAtIndex: ((Int) -> Void)? = nil
    ) {
        self.imageURLs = imageURLs
        self.images = images
        self.initialIndex = initialIndex
        self.imageURL = imageURL
        self.image = image
        self._isPresented = isPresented
        self.onDeleteScreenshotAtIndex = onDeleteScreenshotAtIndex
        self._currentIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                    .padding(16)
                }

                if let nsImage = currentDisplayImage {
                    screenshotImageCell(nsImage: nsImage, index: selectedIndex)
                        .overlay(alignment: .leading) {
                            if hasMultiple {
                                previewNavButton(systemName: "chevron.left", action: showPreviousScreenshot)
                                    .padding(.leading, CursorTheme.spaceM)
                            }
                        }
                        .overlay(alignment: .trailing) {
                            if hasMultiple {
                                previewNavButton(systemName: "chevron.right", action: showNextScreenshot)
                                    .padding(.trailing, CursorTheme.spaceM)
                            }
                        }
                } else {
                    RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                        .overlay {
                            Text("Unable to load screenshot")
                                .font(.system(size: CursorTheme.fontBody, weight: .medium))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        .frame(maxWidth: 900, maxHeight: 700)
                }

                Spacer(minLength: 0)
            }
        }
        .onAppear {
            currentIndex = initialIndex
            guard escapeMonitor == nil else { return }
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                Task { @MainActor in
                    switch event.keyCode {
                    case 53: // Escape
                        isPresented = false
                    case 123: // Left arrow
                        showPreviousScreenshot()
                    case 124: // Right arrow
                        showNextScreenshot()
                    default:
                        break
                    }
                }
                return [53, 123, 124].contains(event.keyCode) ? nil : event
            }
        }
        .onDisappear {
            if let monitor = escapeMonitor {
                NSEvent.removeMonitor(monitor)
                escapeMonitor = nil
            }
        }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
    }

    private func showPreviousScreenshot() {
        guard hasMultiple else { return }
        currentIndex = selectedIndex == 0 ? displayCount - 1 : selectedIndex - 1
    }

    private func showNextScreenshot() {
        guard hasMultiple else { return }
        currentIndex = selectedIndex == displayCount - 1 ? 0 : selectedIndex + 1
    }

    @ViewBuilder
    private func previewNavButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: CursorTheme.fontTitle, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.08), in: Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func screenshotImageCell(nsImage: NSImage, index: Int) -> some View {
        Image(nsImage: nsImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: 1280, maxHeight: 860)
            .fixedSize(horizontal: true, vertical: true)
            .clipShape(RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous)
                    .stroke(CursorTheme.border, lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                HStack(spacing: CursorTheme.spaceS) {
                    if hasMultiple {
                        Text("\(selectedIndex + 1) / \(displayCount)")
                            .font(.system(size: CursorTheme.fontSecondary, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .padding(.horizontal, CursorTheme.spaceS)
                            .padding(.vertical, CursorTheme.spaceXS)
                            .background(Color.black.opacity(0.45), in: Capsule())
                    }

                    if onDeleteScreenshotAtIndex != nil {
                        Button {
                            onDeleteScreenshotAtIndex?(index)
                            if currentIndex >= urls.count - 1 {
                                currentIndex = max(0, urls.count - 2)
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: CursorTheme.fontIconList))
                                .foregroundStyle(.white.opacity(0.9))
                                .background(Circle().fill(Color.black.opacity(0.4)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(CursorTheme.spaceS)
            }
            .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 8)
    }
}
