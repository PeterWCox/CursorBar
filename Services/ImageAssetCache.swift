import Foundation
import AppKit

final class ImageAssetCache {
    static let shared = ImageAssetCache()

    private let screenshotCache = NSCache<NSString, NSImage>()
    private let projectIconCache = NSCache<NSString, NSImage>()

    private init() {}

    func screenshot(for url: URL) -> NSImage? {
        let key = url.path as NSString
        if let cached = screenshotCache.object(forKey: key) {
            return cached
        }
        guard let image = NSImage(contentsOf: url) else { return nil }
        screenshotCache.setObject(image, forKey: key)
        return image
    }

    func removeScreenshot(for url: URL) {
        screenshotCache.removeObject(forKey: url.path as NSString)
    }

    func removeScreenshots(for urls: [URL]) {
        for url in urls {
            removeScreenshot(for: url)
        }
    }

    func projectIcon(for path: String) -> NSImage {
        let key = path as NSString
        if let cached = projectIconCache.object(forKey: key) {
            return cached
        }
        let icon = NSWorkspace.shared.icon(forFile: path)
        projectIconCache.setObject(icon, forKey: key)
        return icon
    }
}
