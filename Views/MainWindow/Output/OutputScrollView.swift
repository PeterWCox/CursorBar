import SwiftUI

// MARK: - Scrollable output area with scroll-to-bottom button (ChatGPT-style)

struct OutputScrollView<Content: View>: View {
    let tab: AgentTab
    let scrollToken: UUID
    @ViewBuilder let content: () -> Content

    @State private var bottomVisibleID: AnyHashable?

    private var showScrollButton: Bool {
        guard !tab.turns.isEmpty else { return false }
        return bottomVisibleID != nil && bottomVisibleID != AnyHashable("outputEnd")
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content()
            }
            .scrollPosition(id: $bottomVisibleID, anchor: .bottom)
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 2)
            .overlay(alignment: .bottom) {
                if showScrollButton {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("outputEnd", anchor: .bottom)
                        }
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CursorTheme.textPrimary)
                            .frame(width: 32, height: 32)
                            .background(CursorTheme.surfaceRaised, in: Circle())
                            .overlay(
                                Circle()
                                    .stroke(CursorTheme.borderStrong, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 12)
                }
            }
            .onChange(of: scrollToken) { _, _ in
                proxy.scrollTo("outputEnd", anchor: .bottom)
            }
        }
    }
}
