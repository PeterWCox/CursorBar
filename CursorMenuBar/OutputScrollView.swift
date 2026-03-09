import SwiftUI

// MARK: - Scrollable output area with scroll-to-bottom pill

struct OutputScrollView<Content: View>: View {
    let tab: AgentTab
    let scrollToken: UUID
    @ViewBuilder let content: () -> Content

    @State private var bottomVisibleID: AnyHashable?

    private var showScrollPill: Bool {
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
            .overlay(alignment: .bottomTrailing) {
                if showScrollPill {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("outputEnd", anchor: .bottom)
                        }
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(CursorTheme.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(CursorTheme.surfaceMuted, in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(CursorTheme.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                }
            }
            .onChange(of: scrollToken) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("outputEnd", anchor: .bottom)
                }
            }
        }
    }
}
