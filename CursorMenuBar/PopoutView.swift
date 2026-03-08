import SwiftUI
import AppKit

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

struct SubmittableTextEditor: NSViewRepresentable {
    @Binding var text: String
    var isDisabled: Bool
    var onSubmit: () -> Void
    var onPasteImage: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = PasteAwareTextView()
        textView.delegate = context.coordinator
        textView.onPasteImage = onPasteImage
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.backgroundColor = .clear
        textView.textColor = NSColor.white.withAlphaComponent(0.92)
        textView.insertionPointColor = NSColor.white.withAlphaComponent(0.9)
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.isEditable = !isDisabled
        (textView as? PasteAwareTextView)?.onPasteImage = onPasteImage
    }

    /// Extracts an image from the pasteboard using multiple methods (NSImage, file URL, raw PNG/TIFF).
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
        let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]
        for type in imageTypes {
            if let data = pasteboard.data(forType: type), let image = NSImage(data: data) {
                return image
            }
        }
        return nil
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SubmittableTextEditor
        weak var textView: NSTextView?

        init(_ parent: SubmittableTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.text = tv.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if NSEvent.modifierFlags.contains(.shift) {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                } else {
                    parent.onSubmit()
                }
                return true
            }
            return false
        }
    }
}

private let availableModels: [(id: String, label: String)] = [
    ("composer-1.5", "Composer 1.5"),
    ("composer-1", "Composer 1"),
    ("auto", "Auto"),
    ("opus-4.6-thinking", "Claude 4.6 Opus (Thinking)"),
    ("sonnet-4.6-thinking", "Claude 4.6 Sonnet (Thinking)"),
    ("sonnet-4.6", "Claude 4.6 Sonnet"),
    ("gpt-5.4-high", "GPT-5.4 High"),
    ("gpt-5.4-medium", "GPT-5.4"),
    ("gemini-3.1-pro", "Gemini 3.1 Pro"),
]

struct BrandMark: View {
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.29, green: 0.52, blue: 1.0),
                            Color(red: 0.47, green: 0.27, blue: 0.98),
                            Color(red: 0.08, green: 0.13, blue: 0.28)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .stroke(Color.white.opacity(0.9), lineWidth: size * 0.07)
                .frame(width: size * 0.48, height: size * 0.48)

            Circle()
                .fill(Color.white)
                .frame(width: size * 0.11, height: size * 0.11)

            Path { path in
                path.move(to: CGPoint(x: size * 0.18, y: size * 0.6))
                path.addCurve(
                    to: CGPoint(x: size * 0.58, y: size * 0.78),
                    control1: CGPoint(x: size * 0.26, y: size * 0.86),
                    control2: CGPoint(x: size * 0.44, y: size * 0.84)
                )
            }
            .stroke(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: size * 0.055, lineCap: .round))

            Image(systemName: "sparkle")
                .font(.system(size: size * 0.18, weight: .bold))
                .foregroundStyle(.white)
                .offset(x: size * 0.22, y: -size * 0.22)
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(0.25), radius: 18, y: 12)
    }
}

struct PopoutView: View {
    @EnvironmentObject var appState: AppState
    var dismiss: () -> Void = {}
    @AppStorage("workspacePath") private var workspacePath: String = FileManager.default.homeDirectoryForCurrentUser.path
    @AppStorage("selectedModel") private var selectedModel: String = "composer-1.5"
    @State private var prompt = ""
    @State private var output = ""
    @State private var isRunning = false
    @State private var errorMessage: String?
    @State private var hasAttachedScreenshot = false
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.08, blue: 0.11),
                    Color(red: 0.10, green: 0.11, blue: 0.15),
                    Color(red: 0.06, green: 0.07, blue: 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                topBar

                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(red: 1.0, green: 0.64, blue: 0.67))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(cardBackground.opacity(0.96), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.red.opacity(0.25), lineWidth: 1)
                        )
                }

                outputCard
                    .frame(maxHeight: .infinity)

                composerDock
            }
            .padding(14)
        }
        .frame(width: 460, height: 780)
        .onChange(of: prompt) { _, newValue in
            hasAttachedScreenshot = newValue.contains("[Screenshot attached:")
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            BrandMark(size: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text("CursorBar")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                Text(isRunning ? "Streaming response" : "Ready")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            Button {
                (NSApp.delegate as? AppDelegate)?.showSettingsWindow(nil)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.05), in: Circle())
            }
            .buttonStyle(.plain)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.05), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }

    private var composerDock: some View {
        VStack(alignment: .leading, spacing: 12) {
            if hasAttachedScreenshot {
                screenshotCard
            }

            HStack(spacing: 10) {
                Button(action: { appState.changeWorkspace() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                        Text(appState.workspaceDisplayName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.06), in: Capsule())
                }
                .buttonStyle(.plain)

                Menu {
                    ForEach(availableModels, id: \.id) { model in
                        Button {
                            selectedModel = model.id
                        } label: {
                            if model.id == selectedModel {
                                Label(model.label, systemImage: "checkmark")
                            } else {
                                Text(model.label)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "cpu")
                        Text(selectedModelLabel)
                            .lineLimit(1)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.86))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.06), in: Capsule())
                }
                .menuStyle(.borderlessButton)
                .foregroundColor(.white)
                .colorScheme(.dark)

                Spacer()

                Button {
                    pasteScreenshot()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: hasAttachedScreenshot ? "photo.fill" : "paperclip")
                        Text(hasAttachedScreenshot ? "Attached" : "Attach")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.06), in: Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("v", modifiers: [.command, .shift])
            }

            HStack(alignment: .bottom, spacing: 10) {
                SubmittableTextEditor(text: $prompt, isDisabled: isRunning, onSubmit: sendPrompt, onPasteImage: pasteScreenshot)
                    .frame(height: 82)
                    .padding(12)
                    .background(editorBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                Button(action: sendPrompt) {
                    Group {
                        if isRunning {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.35, green: 0.56, blue: 1.0), Color(red: 0.50, green: 0.32, blue: 1.0)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Circle()
                    )
                    .opacity(canSend ? 1 : 0.45)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }

            Text("You've used 1% of your included API usage")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))
        }
        .padding(14)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
        )
    }

    private var screenshotCard: some View {
        let imageURL = URL(fileURLWithPath: workspacePath)
            .appendingPathComponent(".cursor", isDirectory: true)
            .appendingPathComponent("pasted-screenshot.png")

        return Group {
            if let nsImage = NSImage(contentsOf: imageURL) {
                HStack(spacing: 12) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Attached screenshot")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))

                        Text(".cursor/pasted-screenshot.png")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.46))
                            .lineLimit(1)

                        Text("Included with your next prompt")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.56))
                    }

                    Spacer()

                    Button(action: deleteScreenshot) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(editorBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
        }
    }

    private var outputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Agent")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))

                Spacer()

                Text(isRunning ? "Streaming" : "Idle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isRunning ? Color(red: 0.59, green: 0.83, blue: 1.0) : .white.opacity(0.4))
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Group {
                        if output.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Response will appear here...")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.58))

                                Text("Ask a question below and CursorBar will stream the answer into this panel.")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.38))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                        } else {
                            Text(output)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.88))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .textSelection(.enabled)
                        }
                    }
                    .id("outputEnd")
                }
                .frame(maxHeight: .infinity)
                .background(editorBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .onChange(of: output) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("outputEnd", anchor: .bottom)
                    }
                }
            }
        }
        .padding(14)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
        )
    }

    private var selectedModelLabel: String {
        availableModels.first { $0.id == selectedModel }?.label ?? selectedModel
    }

    private var cardBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                Color.white.opacity(0.12),
                Color.white.opacity(0.06)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var editorBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                Color.black.opacity(0.22),
                Color.black.opacity(0.34)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardBorder: Color {
        Color.white.opacity(0.11)
    }

    private var canSend: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isRunning
    }
    
    private func deleteScreenshot() {
        let reference = "\n\n[Screenshot attached: .cursor/pasted-screenshot.png]"
        prompt = prompt.replacingOccurrences(of: reference, with: "")
        hasAttachedScreenshot = false
        let imageURL = URL(fileURLWithPath: workspacePath).appendingPathComponent(".cursor", isDirectory: true).appendingPathComponent("pasted-screenshot.png")
        try? FileManager.default.removeItem(at: imageURL)
    }
    
    private func pasteScreenshot() {
        let pasteboard = NSPasteboard.general
        guard let image = SubmittableTextEditor.imageFromPasteboard(pasteboard) else {
            return
        }
        
        let cursorDir = URL(fileURLWithPath: workspacePath).appendingPathComponent(".cursor", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: cursorDir, withIntermediateDirectories: true)
        } catch {
            return
        }
        
        let destURL = cursorDir.appendingPathComponent("pasted-screenshot.png")
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return
        }
        
        do {
            try pngData.write(to: destURL)
            let reference = "\n\n[Screenshot attached: .cursor/pasted-screenshot.png]"
            if !prompt.contains(reference) {
                prompt += reference
            }
            hasAttachedScreenshot = true
        } catch {
            return
        }
    }
    
    private func sendPrompt() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        errorMessage = nil
        output = ""
        isRunning = true
        
        Task {
            do {
                let stream = try AgentRunner.stream(prompt: trimmed, workspacePath: workspacePath, model: selectedModel)
                prompt = ""
                hasAttachedScreenshot = false
                for try await chunk in stream {
                    output += chunk
                }
                isRunning = false
            } catch let error as AgentRunnerError {
                errorMessage = error.userMessage
                isRunning = false
            } catch {
                errorMessage = error.localizedDescription
                isRunning = false
            }
        }
    }
}

