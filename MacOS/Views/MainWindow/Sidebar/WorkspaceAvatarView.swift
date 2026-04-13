import AppKit
import SwiftUI

enum WorkspaceInitials {
    static func string(workspacePath: String, displayName: String?) -> String {
        let trimmedName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: String
        if let trimmedName, !trimmedName.isEmpty {
            base = trimmedName
        } else {
            base = (workspacePath as NSString).lastPathComponent
        }
        return initials(from: base)
    }

    private static func initials(from name: String) -> String {
        let parts = name.split { !$0.isLetter && !$0.isNumber && $0 != "." && $0 != "_" && $0 != "-" }
            .map(String.init)
            .filter { !$0.isEmpty }
        if parts.count >= 2 {
            let a = parts[0].prefix(1)
            let b = parts[1].prefix(1)
            return String(a + b).uppercased()
        }
        if let first = parts.first {
            if first.count >= 2 {
                return String(first.prefix(2)).uppercased()
            }
            if let c = first.first {
                return String(c).uppercased()
            }
        }
        return "?"
    }
}

/// Square avatar: repo logo when present, otherwise initials (or a blank tinted tile) on a tinted background.
struct WorkspaceAvatarView: View {
    @Environment(\.colorScheme) private var colorScheme
    let workspacePath: String
    var displayName: String? = nil
    var size: CGFloat
    /// Corner radius as a fraction of `size` (default ~20% for a soft square).
    var cornerRadiusFraction: CGFloat = 0.22
    /// When false and there is no repo logo, shows only the tinted tile (no letter glyphs).
    var showsInitialsWhenNoLogo: Bool = true

    @State private var repoImage: NSImage?

    private var initialsFull: String {
        WorkspaceInitials.string(workspacePath: workspacePath, displayName: displayName)
    }

    private var initialsShown: String {
        if size <= 14 {
            return String(initialsFull.prefix(1))
        }
        return initialsFull
    }

    private var workspaceTint: Color {
        workspacePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? CursorTheme.textTertiary(for: colorScheme)
            : CursorTheme.colorForWorkspace(path: workspacePath)
    }

    var body: some View {
        Group {
            if let repoImage {
                Image(nsImage: repoImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if showsInitialsWhenNoLogo {
                Text(initialsShown)
                    .font(.system(size: max(6, size * (size <= 14 ? 0.45 : 0.38)), weight: .semibold, design: .rounded))
                    .foregroundStyle(workspaceTint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(workspaceTint.opacity(colorScheme == .dark ? 0.28 : 0.2))
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(workspaceTint.opacity(colorScheme == .dark ? 0.28 : 0.2))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * cornerRadiusFraction, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * cornerRadiusFraction, style: .continuous)
                .stroke(CursorTheme.border(for: colorScheme).opacity(0.55), lineWidth: 1)
        )
        .task(id: "\(workspacePath)|\(displayName ?? "")") {
            let path = workspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else {
                repoImage = nil
                return
            }
            repoImage = await ImageAssetCache.shared.loadRepoAvatarImage(for: path, displayName: displayName)
        }
    }
}
