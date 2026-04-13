import SwiftUI

// MARK: - Metro speech bubble (Tesco blue, tail under Cursor text)

struct MetroSpeechBubble: View {
    /// Scale for font/padding (e.g. 1.2 for larger use in About).
    var scale: CGFloat = 1.0

    var body: some View {
        Text("Metro")
            .font(.system(size: 13 * scale, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10 * scale)
            .padding(.vertical, 5 * scale)
            .background(SpeechBubbleShape().fill(CursorTheme.tescoBlue))
            .fixedSize()
    }
}

private struct SpeechBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cr: CGFloat = 6
        let tailW: CGFloat = 10
        let tailH: CGFloat = 6
        let body = CGRect(x: 0, y: 0, width: rect.width, height: rect.height - tailH)
        var path = Path(roundedRect: body, cornerSize: CGSize(width: cr, height: cr))
        path.addPath(Path { p in
            p.move(to: CGPoint(x: rect.midX - tailW/2, y: body.maxY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.midX + tailW/2, y: body.maxY))
            p.closeSubpath()
        })
        return path
    }
}
