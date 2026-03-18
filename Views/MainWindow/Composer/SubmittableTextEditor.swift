import SwiftUI
import AppKit

// MARK: - Paste-aware text editor for composer

final class PasteAwareTextView: NSTextView {
    var onPasteImage: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCommandV = modifiers.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "v"

        if isCommandV {
            let pasteboard = NSPasteboard.general
            if onPasteImage != nil, SubmittableTextEditor.imageFromPasteboard(pasteboard) != nil {
                onPasteImage?()
                return true
            }
            if let string = pasteboard.string(forType: .string), !string.isEmpty {
                insertText(string, replacementRange: selectedRange())
                return true
            }
        }

        return super.performKeyEquivalent(with: event)
    }

    override func paste(_ sender: Any?) {
        if onPasteImage != nil, SubmittableTextEditor.imageFromPasteboard(.general) != nil {
            onPasteImage?()
            return
        }
        super.paste(sender)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        if onPasteImage != nil, SubmittableTextEditor.imageFromPasteboard(.general) != nil {
            onPasteImage?()
            return
        }
        super.pasteAsPlainText(sender)
    }

    override func pasteAsRichText(_ sender: Any?) {
        if onPasteImage != nil, SubmittableTextEditor.imageFromPasteboard(.general) != nil {
            onPasteImage?()
            return
        }
        super.pasteAsRichText(sender)
    }
}

// MARK: - Single-line paste-aware field (e.g. new task row)

/// Single-line NSTextView-based field so Cmd+V and Edit > Paste are handled by our PasteAwareTextView (field editor would steal paste on NSTextField).
struct SingleLinePasteAwareField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var onSubmit: () -> Void
    var onCancel: () -> Void
    var onPasteImage: (() -> Void)?
    var colorScheme: ColorScheme = .dark
    var onFocusRequested: ((@escaping () -> Void) -> Void)?

    func makeCoordinator() -> SingleLinePasteAwareField.Coordinator { Coordinator(self) }

    private static func textColor(for colorScheme: ColorScheme) -> NSColor {
        colorScheme == .dark
            ? NSColor.white.withAlphaComponent(0.92)
            : NSColor.black.withAlphaComponent(0.88)
    }

    private static func typingAttributes(for colorScheme: ColorScheme) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: textColor(for: colorScheme)
        ]
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = PasteAwareTextView()
        textView.delegate = context.coordinator
        textView.onPasteImage = onPasteImage
        textView.isRichText = false
        textView.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        textView.typingAttributes = Self.typingAttributes(for: colorScheme)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textColor = Self.textColor(for: colorScheme)
        textView.insertionPointColor = Self.textColor(for: colorScheme)
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineFragmentPadding = 0
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: 24)
        textView.minSize = NSSize(width: 0, height: 24)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autoresizingMask = [.width]
        context.coordinator.textView = textView

        if let callback = onFocusRequested {
            let focusClosure: () -> Void = { [weak scrollView] in
                guard let sv = scrollView, let tv = sv.documentView as? NSTextView else { return }
                sv.window?.makeFirstResponder(tv)
            }
            callback(focusClosure)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        textView.textColor = Self.textColor(for: colorScheme)
        textView.insertionPointColor = Self.textColor(for: colorScheme)
        textView.typingAttributes = Self.typingAttributes(for: colorScheme)
        (textView as? PasteAwareTextView)?.onPasteImage = onPasteImage
        if textView.string != text {
            textView.string = text
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SingleLinePasteAwareField
        weak var textView: NSTextView?

        init(_ parent: SingleLinePasteAwareField) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.text = tv.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            return false
        }
    }
}

struct SubmittableTextEditor: NSViewRepresentable {
    @Binding var text: String
    var isDisabled: Bool
    var onSubmit: () -> Void
    var onPasteImage: (() -> Void)?
    var onHeightChange: ((CGFloat) -> Void)? = nil
    /// Called once with (focusClosure, isFirstResponderClosure) so the host can focus this field (e.g. on Tab) and check if it already has focus.
    var onFocusRequested: (((@escaping () -> Void), (@escaping () -> Bool)) -> Void)? = nil
    /// Pass from environment so editor text respects light/dark.
    var colorScheme: ColorScheme = .dark
    /// Override for places that use body text instead of a monospaced composer font.
    var font: NSFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    /// Override for layouts that need tighter or looser text padding.
    var textContainerInset: NSSize = NSSize(width: 4, height: 6)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    private static func textColor(for colorScheme: ColorScheme) -> NSColor {
        colorScheme == .dark
            ? NSColor.white.withAlphaComponent(0.92)
            : NSColor.black.withAlphaComponent(0.88)
    }

    private static func typingAttributes(for colorScheme: ColorScheme, font: NSFont) -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: textColor(for: colorScheme)
        ]
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = PasteAwareTextView()
        textView.delegate = context.coordinator
        textView.onPasteImage = onPasteImage
        textView.isRichText = false
        textView.font = font
        textView.typingAttributes = Self.typingAttributes(for: colorScheme, font: font)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textColor = Self.textColor(for: colorScheme)
        textView.insertionPointColor = Self.textColor(for: colorScheme)
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.textContainerInset = textContainerInset
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineFragmentPadding = 0

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        context.coordinator.textView = textView
        context.coordinator.updateHeightIfNeeded(for: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        textView.textColor = Self.textColor(for: colorScheme)
        textView.insertionPointColor = Self.textColor(for: colorScheme)
        textView.font = font
        textView.typingAttributes = Self.typingAttributes(for: colorScheme, font: font)
        textView.textContainerInset = textContainerInset
        if textView.string != text {
            textView.string = text
        }
        textView.isEditable = true
        (textView as? PasteAwareTextView)?.onPasteImage = onPasteImage
        context.coordinator.updateHeightIfNeeded(for: textView)

        if let callback = onFocusRequested, !context.coordinator.didSendFocusCallbacks {
            context.coordinator.didSendFocusCallbacks = true
            let focusClosure: () -> Void = { [weak scrollView] in
                guard let sv = scrollView, let tv = sv.documentView as? NSTextView, let window = sv.window else { return }
                window.makeKey()
                window.makeFirstResponder(tv)
            }
            let isFirstResponderClosure: () -> Bool = { [weak scrollView] in
                guard let sv = scrollView, let tv = sv.documentView as? NSTextView else { return false }
                return sv.window?.firstResponder === tv
            }
            callback(focusClosure, isFirstResponderClosure)
        }
    }

    /// Extracts an image from the pasteboard using multiple methods (NSImage, file URL, raw PNG/TIFF/JPEG).
    /// macOS screenshots often put a file URL (public.file-url) on the pasteboard; we read that explicitly.
    static func imageFromPasteboard(_ pasteboard: NSPasteboard) -> NSImage? {
        if pasteboard.canReadObject(forClasses: [NSImage.self], options: nil),
           let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first {
            return image
        }
        if pasteboard.canReadObject(forClasses: [NSURL.self], options: nil),
           let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let url = urls.first,
           let image = NSImage(contentsOf: url) {
            return image
        }
        // macOS screenshot (and Finder "Copy") often puts file URL as data with type .fileURL; readObjects may not return it.
        let fileURLType = NSPasteboard.PasteboardType.fileURL
        if pasteboard.types?.contains(fileURLType) == true,
           let data = pasteboard.data(forType: fileURLType),
           let str = String(data: data, encoding: .utf8),
           let url = URL(string: str.trimmingCharacters(in: .whitespacesAndNewlines)),
           url.isFileURL,
           let image = NSImage(contentsOf: url) {
            return image
        }
        let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]
        for type in imageTypes {
            if let data = pasteboard.data(forType: type), let image = NSImage(data: data) {
                return image
            }
        }
        // JPEG (e.g. some screenshots or copied images)
        let jpegType = NSPasteboard.PasteboardType("public.jpeg")
        if pasteboard.types?.contains(jpegType) == true,
           let data = pasteboard.data(forType: jpegType),
           let image = NSImage(data: data) {
            return image
        }
        return nil
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SubmittableTextEditor
        weak var textView: NSTextView?
        private var lastReportedHeight: CGFloat = 0
        var didSendFocusCallbacks: Bool = false

        init(_ parent: SubmittableTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.text = tv.string
            updateHeightIfNeeded(for: tv)
        }

        func textDidBeginEditing(_ notification: Notification) {
            guard let tv = textView else { return }
            updateHeightIfNeeded(for: tv)
        }

        func textDidEndEditing(_ notification: Notification) {
            guard let tv = textView else { return }
            updateHeightIfNeeded(for: tv)
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if NSEvent.modifierFlags.contains(.shift) {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                } else if !parent.isDisabled {
                    parent.onSubmit()
                }
                return true
            }
            return false
        }

        func updateHeightIfNeeded(for textView: NSTextView) {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                return
            }

            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let contentHeight = ceil(usedRect.height + (textView.textContainerInset.height * 2))
            let targetHeight = max(24, contentHeight)

            guard abs(targetHeight - lastReportedHeight) > 0.5 else { return }
            lastReportedHeight = targetHeight
            DispatchQueue.main.async {
                self.parent.onHeightChange?(targetHeight)
            }
        }
    }
}
