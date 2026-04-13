import SwiftUI
import AppKit

// MARK: - Popout header icon (top-left of panel): Cursor Metro mark with teal accent

struct BrandMark: View {
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(CursorTheme.surfaceMuted)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
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

            // Cursor mark: ring
            Circle()
                .stroke(CursorTheme.textPrimary, lineWidth: size * 0.07)
                .frame(width: size * 0.48, height: size * 0.48)

            Circle()
                .fill(CursorTheme.textPrimary)
                .frame(width: size * 0.11, height: size * 0.11)

            // Orbit
            Path { path in
                path.move(to: CGPoint(x: size * 0.18, y: size * 0.6))
                path.addCurve(
                    to: CGPoint(x: size * 0.58, y: size * 0.78),
                    control1: CGPoint(x: size * 0.26, y: size * 0.86),
                    control2: CGPoint(x: size * 0.44, y: size * 0.84)
                )
            }
            .stroke(CursorTheme.textPrimary.opacity(0.75), style: StrokeStyle(lineWidth: size * 0.055, lineCap: .round))

            // Spark
            Image(systemName: "sparkle")
                .font(.system(size: size * 0.18, weight: .bold))
                .foregroundStyle(CursorTheme.textPrimary)
                .offset(x: size * 0.22, y: -size * 0.22)

            // Teal plus (Cursor Metro)
            RoundedRectangle(cornerRadius: size * 0.02, style: .continuous)
                .fill(CursorTheme.cursorPlusTeal)
                .frame(width: size * 0.24, height: max(2, size * 0.06))
                .offset(x: size * 0.28, y: size * 0.26)
            RoundedRectangle(cornerRadius: size * 0.02, style: .continuous)
                .fill(CursorTheme.cursorPlusTeal)
                .frame(width: max(2, size * 0.06), height: size * 0.24)
                .offset(x: size * 0.28, y: size * 0.26)
        }
        .frame(width: size, height: size)
        .shadow(color: CursorTheme.cursorPlusTeal.opacity(size > 30 ? 0.25 : 0.15), radius: size > 30 ? 12 : 4, y: size > 30 ? 6 : 2)
    }
}
