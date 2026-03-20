import Foundation
import AppKit

// MARK: - Repo avatar discovery (recursive, name-aware)

extension ImageAssetCache {
    /// Tokens derived from the folder name and optional display name (for fuzzy filename matching).
    fileprivate static func repoAvatarNameTokens(workspacePath: String, displayName: String?) -> [String] {
        var set = Set<String>()
        func absorb(_ raw: String) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let lower = trimmed.lowercased()
            if lower.count >= 2 { set.insert(lower) }
            let runs = lower.split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 2 }
            for r in runs { set.insert(r) }
            let folded = lower.filter { $0.isLetter || $0.isNumber }
            if folded.count >= 3 { set.insert(folded) }
        }
        absorb((workspacePath as NSString).lastPathComponent)
        if let displayName { absorb(displayName) }
        return set.sorted { $0.count > $1.count }
    }

    /// True if `file` is contained in `root` (avoids `/foo` matching `/foobar/...`).
    fileprivate static func fileURL(_ file: URL, isUnderRoot root: URL) -> Bool {
        let fp = file.standardizedFileURL.path
        let rp = root.standardizedFileURL.path
        guard !rp.isEmpty, !fp.isEmpty else { return false }
        if fp == rp { return false }
        let prefix = rp.hasSuffix("/") ? rp : rp + "/"
        return fp.hasPrefix(prefix)
    }
}

final class ImageAssetCache {
    static let shared = ImageAssetCache()

    private let screenshotCache = NSCache<NSString, NSImage>()
    private let projectIconCache = NSCache<NSString, NSImage>()
    private let repoAvatarCache = NSCache<NSString, NSImage>()

    /// Relative paths checked in order before a deeper tree walk (cheap hits at known locations).
    private static let repoAvatarCandidatePaths: [String] = [
        "logo.png", "logo.jpg", "logo.jpeg", "logo.webp",
        "icon.png", "icon.jpg", "icon.jpeg", "icon.webp",
        "app-icon.png", "app_icon.png",
        "favicon.ico",
        ".github/logo.png", ".github/logo.jpg", ".github/logo.jpeg",
        "assets/logo.png", "docs/logo.png",
    ]

    /// Subdirectories we never descend into (dependency / build trees).
    private static let repoAvatarSkippedDirs: Set<String> = [
        ".git", "node_modules", "pods", "carthage", "deriveddata", "build", ".build",
        "dist", "target", "vendor", "__pycache__", ".gradle", "venv", ".venv",
        ".next", ".nuxt", "coverage", "htmlcov", "tmp", "temp", "bower_components",
        ".turbo", ".cache", "site-packages", ".metro", "pods-headers", "intermediates",
    ]

    private static let repoAvatarMaxDepth = 10
    private static let repoAvatarMaxDirectoriesVisited = 1_200
    private static let repoAvatarMaxImageBytes: Int64 = 12 * 1_024 * 1_024

    private init() {}

    func cachedScreenshot(for url: URL) -> NSImage? {
        screenshotCache.object(forKey: url.path as NSString)
    }

    func screenshot(for url: URL) -> NSImage? {
        let key = url.path as NSString
        if let cached = screenshotCache.object(forKey: key) {
            return cached
        }
        guard let image = NSImage(contentsOf: url) else { return nil }
        screenshotCache.setObject(image, forKey: key)
        return image
    }

    func loadScreenshot(for url: URL) async -> NSImage? {
        let key = url.path as NSString
        if let cached = screenshotCache.object(forKey: key) {
            return cached
        }

        let loadedImage = await Task.detached(priority: .utility) {
            NSImage(contentsOf: url)
        }.value

        if let loadedImage {
            screenshotCache.setObject(loadedImage, forKey: key)
        }

        return loadedImage
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

    /// Raster image under the workspace, or nil. Pass `displayName` so names like `MyApp-1024.png` match.
    func loadRepoAvatarImage(for workspacePath: String, displayName: String? = nil) async -> NSImage? {
        let trimmed = workspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let nameKey = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cacheKey = "\(trimmed)\n\(nameKey)" as NSString
        if let cached = repoAvatarCache.object(forKey: cacheKey) {
            return cached
        }

        let url = await Task.detached(priority: .utility) {
            Self.firstRepoImageURL(workspacePath: trimmed, displayName: displayName)
        }.value

        guard let url else { return nil }

        let image = await Task.detached(priority: .utility) {
            guard let img = NSImage(contentsOf: url), img.size.width > 0.5, img.size.height > 0.5 else { return nil as NSImage? }
            return img
        }.value

        if let image {
            repoAvatarCache.setObject(image, forKey: cacheKey)
        }
        return image
    }

    /// When the workspace is a `.metro` config folder, also search the parent repo for icons.
    private static func repoAvatarSearchRoots(workspacePath: String) -> [URL] {
        let primary = URL(fileURLWithPath: workspacePath, isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        var roots = [primary]
        if primary.lastPathComponent.lowercased() == ".metro" {
            let parent = primary.deletingLastPathComponent().standardizedFileURL
            let fm = FileManager.default
            if fm.fileExists(atPath: parent.path), parent.path != primary.path {
                roots.append(parent)
            }
        }
        return roots
    }

    private static func firstRepoImageURL(workspacePath: String, displayName: String?) -> URL? {
        let fm = FileManager.default
        let tokens = repoAvatarNameTokens(workspacePath: workspacePath, displayName: displayName)
        let roots = repoAvatarSearchRoots(workspacePath: workspacePath)

        for root in roots {
            guard fm.fileExists(atPath: root.path) else { continue }
            for rel in repoAvatarCandidatePaths {
                let url = root.appendingPathComponent(rel, isDirectory: false)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }
                return url
            }
        }

        var bestURL: URL?
        var bestScore = Int.min
        var bestDepth = Int.max
        var bestPath: String?

        for root in roots {
            guard fm.fileExists(atPath: root.path) else { continue }
            guard let candidate = bestRepoImageByRecursiveScan(root: root, fm: fm, nameTokens: tokens) else { continue }
            guard let score = repoImageFileScore(file: candidate, root: root, nameTokens: tokens) else { continue }
            let d = repoRelativeDepth(file: candidate, root: root)
            let path = candidate.path
            if isBetterRepoImageCandidate(path: path, score: score, depth: d, currentBestPath: bestPath, bestScore: bestScore, bestDepth: bestDepth) {
                bestURL = candidate
                bestScore = score
                bestDepth = d
                bestPath = path
            }
        }

        return bestURL
    }

    /// Depth of `file` under `root` (file directly in root → 0).
    private static func repoRelativeDepth(file: URL, root: URL) -> Int {
        guard fileURL(file, isUnderRoot: root) else { return Int.max }
        let rootPath = root.standardizedFileURL.path
        let filePath = file.standardizedFileURL.path
        let rootWithSlash = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard filePath != rootPath else { return 0 }
        guard filePath.hasPrefix(rootWithSlash) else { return Int.max }
        let suffix = filePath.dropFirst(rootWithSlash.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !suffix.isEmpty else { return 0 }
        return suffix.split(separator: "/").count - 1
    }

    private static func shouldSkipAvatarSubdirectory(name: String) -> Bool {
        let lower = name.lowercased()
        if repoAvatarSkippedDirs.contains(lower) { return true }
        if lower == ".git" { return true }
        // Skip most dot-folders (noise, VCS); still allow `.github` for profile/readme assets.
        if name.hasPrefix("."), lower != ".github" { return true }
        return false
    }

    private static func repoImageFileScore(file: URL, root: URL, nameTokens: [String]) -> Int? {
        let ext = file.pathExtension.lowercased()
        guard ["png", "jpg", "jpeg", "webp", "ico", "icns"].contains(ext) else { return nil }

        let path = file.standardizedFileURL.path
        guard fileURL(file, isUnderRoot: root) else { return nil }
        let rootPath = root.standardizedFileURL.path
        let rootWithSlash = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        let relative: String
        if path.hasPrefix(rootWithSlash) {
            relative = String(path.dropFirst(rootWithSlash.count))
        } else {
            relative = ""
        }
        let relLower = relative.lowercased()
        let name = file.lastPathComponent.lowercased()
        let stem = (file.deletingPathExtension().lastPathComponent).lowercased()

        var score = 0
        if name == "favicon.ico" { score = 200 }
        else if name.contains("logo") { score = 190 }
        else if relLower.contains("appicon.appiconset"), ext == "png" { score = 186 }
        else if name.contains("app-icon") || stem == "appicon" || name.contains("appicon") { score = 180 }
        else if name == "icon.png" || name == "icon.jpg" || name == "icon.jpeg" || name == "icon.webp" { score = 175 }
        else if name.hasPrefix("icon."), ["png", "jpg", "jpeg", "webp", "icns"].contains(ext) { score = 168 }
        else if name.contains("apple-touch-icon") || name.contains("apple_touch") { score = 162 }
        else if name.contains("favicon") { score = 155 }
        else if name.contains("mstile") || name.contains("tileicon") { score = 145 }
        else if name.contains("brand") || name.contains("mark") || name == "mark.png" { score = 135 }
        else if name.contains("hero") || name.contains("splash") || name.contains("banner") { score = 70 }
        else if name.contains("icon") { score = 55 }
        else if relLower.contains("/images/") || relLower.contains("/img/") || relLower.contains("/assets/") { score = 35 }
        else { score = 22 }

        if stem.contains("screenshot") || stem.hasPrefix("img_") || stem.contains("simulator") || stem.contains("wireframe") {
            score -= 45
        }

        for token in nameTokens {
            guard token.count >= 2 else { continue }
            if stem == token { score += 130; break }
            if stem.hasPrefix(token + "-") || stem.hasPrefix(token + "_") { score += 110; break }
            if stem.hasSuffix("-" + token) || stem.hasSuffix("_" + token) { score += 110; break }
            if stem.contains(token) {
                score += token.count >= 4 ? 75 : 50
                break
            }
        }

        let depth = repoRelativeDepth(file: file, root: root)
        if score < 100 {
            score -= min(depth, 10) * 2
        } else if depth > 6 {
            score -= (depth - 6) * 2
        }
        return score
    }

    private static func isBetterRepoImageCandidate(
        path: String,
        score: Int,
        depth: Int,
        currentBestPath: String?,
        bestScore: Int,
        bestDepth: Int
    ) -> Bool {
        if score != bestScore { return score > bestScore }
        if depth != bestDepth { return depth < bestDepth }
        guard let currentBestPath else { return true }
        return path < currentBestPath
    }

    /// Walks the repo up to depth / directory limits and picks the strongest-scoring image file.
    private static func bestRepoImageByRecursiveScan(root: URL, fm: FileManager, nameTokens: [String]) -> URL? {
        var bestURL: URL?
        var bestScore = Int.min
        var bestDepth = Int.max
        var bestPath: String?

        var stack: [(URL, Int)] = [(root, 0)]
        var dirsVisited = 0

        while let (dir, depth) = stack.popLast() {
            guard dirsVisited < repoAvatarMaxDirectoriesVisited, depth <= repoAvatarMaxDepth else { continue }
            dirsVisited += 1

            let children: [URL]
            do {
                // Do not use `.skipsHiddenFiles` — we need `.github` and similar.
                children = try fm.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                    options: [.skipsPackageDescendants]
                )
            } catch {
                continue
            }

            let sorted = children.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            var subdirs: [URL] = []

            for url in sorted {
                let name = url.lastPathComponent
                if name == ".DS_Store" { continue }

                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }

                if isDir.boolValue {
                    if shouldSkipAvatarSubdirectory(name: name) { continue }
                    subdirs.append(url)
                    continue
                }

                guard let score = repoImageFileScore(file: url, root: root, nameTokens: nameTokens), score >= 8 else { continue }

                let size: Int64 = {
                    guard let n = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return 0 }
                    return Int64(n)
                }()
                if size > repoAvatarMaxImageBytes || size < 32 { continue }

                let d = repoRelativeDepth(file: url, root: root)
                let path = url.path
                if isBetterRepoImageCandidate(path: path, score: score, depth: d, currentBestPath: bestPath, bestScore: bestScore, bestDepth: bestDepth) {
                    bestURL = url
                    bestScore = score
                    bestDepth = d
                    bestPath = path
                }
            }

            for sd in subdirs.reversed() {
                stack.append((sd, depth + 1))
            }
        }

        return bestURL
    }
}
