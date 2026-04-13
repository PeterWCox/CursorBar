import SwiftUI
import AppKit

// MARK: - Pass-through view for tooltip (does not steal clicks)

private final class TooltipPassThroughView: NSView {
    var tooltipText: String = "" {
        didSet { toolTip = tooltipText }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = ""
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        toolTip = ""
    }

    /// Return nil so clicks pass through to the SwiftUI view underneath; tooltip still shows on hover.
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}

// MARK: - AppKit tooltip overlay (reliable in NSPanel / NSHostingView)

private struct TooltipOverlayView: NSViewRepresentable {
    let tooltip: String

    func makeNSView(context: Context) -> TooltipPassThroughView {
        let v = TooltipPassThroughView()
        v.tooltipText = tooltip
        return v
    }

    func updateNSView(_ nsView: TooltipPassThroughView, context: Context) {
        nsView.tooltipText = tooltip
    }
}

extension View {
    /// AppKit-based tooltip that shows reliably in NSPanel and other hosting contexts where SwiftUI `.help()` may not.
    func appKitToolTip(_ text: String) -> some View {
        overlay(TooltipOverlayView(tooltip: text))
    }
}
