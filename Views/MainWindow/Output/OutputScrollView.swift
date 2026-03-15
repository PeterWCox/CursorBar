import SwiftUI

// MARK: - Scrollable output area with scroll-to-bottom button (ChatGPT-style)

struct OutputScrollView<Content: View>: View {
    let tab: AgentTab
    let scrollToken: UUID
    @ViewBuilder let content: () -> Content

    @State private var bottomVisibleID: AnyHashable?
    /// When true, we just programmatically scrolled (auto-scroll); hide the button briefly so it doesn’t flash.
    @State private var isAutoScrolling = false

    /// Show the scroll-to-bottom button when there is content, user is not at bottom, and we’re not in the middle of auto-scrolling.
    private var showScrollButton: Bool {
        guard !tab.turns.isEmpty else { return false }
        guard !isAutoScrolling else { return false }
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
                            .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .help("Scroll to bottom")
                    .padding(.bottom, 12)
                }
            }
            .onChange(of: scrollToken) { _, _ in
                isAutoScrolling = true
                proxy.scrollTo("outputEnd", anchor: .bottom)
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    isAutoScrolling = false
                }
            }
            .onAppear {
                // When we focus this agent (tab selected), start at bottom; if work is ongoing, existing requestAutoScroll will keep autoscroll.
                isAutoScrolling = true
                proxy.scrollTo("outputEnd", anchor: .bottom)
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    isAutoScrolling = false
                }
            }
        }
    }
}
