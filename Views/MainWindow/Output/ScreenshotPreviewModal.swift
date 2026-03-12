import SwiftUI
import AppKit

// MARK: - Full-screen modal to preview a screenshot at larger size

struct ScreenshotPreviewModal: View {
    var imageURL: URL
    @Binding var isPresented: Bool

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

                if let nsImage = NSImage(contentsOf: imageURL) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 900, maxHeight: 700)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(CursorTheme.border, lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 8)
                }

                Spacer(minLength: 0)
            }
        }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
    }
}
