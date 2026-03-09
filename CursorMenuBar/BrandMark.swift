import SwiftUI
import AppKit

// MARK: - Brand logo / header mark

struct BrandMark: View {
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            if let nsImage = CursorAppIcon.load() {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                            .stroke(CursorTheme.cursorPlusTeal.opacity(0.8), lineWidth: max(1, size * 0.025))
                    )
            } else {
                fallbackIcon
            }
        }
        .frame(width: size, height: size)
        .shadow(color: CursorTheme.cursorPlusTeal.opacity(0.25), radius: 12, y: 6)
    }

    private var fallbackIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(CursorTheme.surfaceMuted)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    CursorTheme.cursorPlusTeal.opacity(0.9),
                                    CursorTheme.brandBlue.opacity(0.8)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: max(1, size * 0.025)
                        )
                )

            Circle()
                .stroke(CursorTheme.textPrimary, lineWidth: size * 0.07)
                .frame(width: size * 0.48, height: size * 0.48)

            Circle()
                .fill(CursorTheme.textPrimary)
                .frame(width: size * 0.11, height: size * 0.11)

            Path { path in
                path.move(to: CGPoint(x: size * 0.18, y: size * 0.6))
                path.addCurve(
                    to: CGPoint(x: size * 0.58, y: size * 0.78),
                    control1: CGPoint(x: size * 0.26, y: size * 0.86),
                    control2: CGPoint(x: size * 0.44, y: size * 0.84)
                )
            }
            .stroke(CursorTheme.textPrimary.opacity(0.75), style: StrokeStyle(lineWidth: size * 0.055, lineCap: .round))

            Image(systemName: "sparkle")
                .font(.system(size: size * 0.18, weight: .bold))
                .foregroundStyle(CursorTheme.textPrimary)
                .offset(x: size * 0.22, y: -size * 0.22)
        }
    }
}
