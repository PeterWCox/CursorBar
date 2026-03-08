import SwiftUI
import AppKit

struct SubmittableTextEditor: NSViewRepresentable {
    @Binding var text: String
    var isDisabled: Bool
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.backgroundColor = .clear
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

struct PopoutView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("workspacePath") private var workspacePath: String = FileManager.default.homeDirectoryForCurrentUser.path
    @State private var prompt = ""
    @State private var output = ""
    @State private var isRunning = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                SubmittableTextEditor(text: $prompt, isDisabled: isRunning, onSubmit: sendPrompt)
                    .frame(height: 72)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )
                
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                
                HStack(spacing: 6) {
                    Button(action: { appState.changeWorkspace() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                            Text(appState.workspaceDisplayName)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.accessoryBar)
                    
                    Spacer()
                    
                    Button(action: sendPrompt) {
                        if isRunning {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 50)
                        } else {
                            Label("Send", systemImage: "paperplane.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRunning)
                }
            }
            .padding(12)
            
            Divider()
            
            ScrollViewReader { proxy in
                ScrollView {
                    Text(output.isEmpty ? "Response will appear here..." : output)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(output.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .textSelection(.enabled)
                        .id("outputEnd")
                }
                .frame(maxHeight: .infinity)
                .onChange(of: output) { _, _ in
                    withAnimation {
                        proxy.scrollTo("outputEnd", anchor: .bottom)
                    }
                }
            }
            
            Divider()
            
            HStack(spacing: 12) {
                Button {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    Image(systemName: "gear")
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 380, height: 360)
    }
    
    private func sendPrompt() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        errorMessage = nil
        output = ""
        isRunning = true
        
        Task {
            do {
                let stream = try AgentRunner.stream(prompt: trimmed, workspacePath: workspacePath)
                prompt = ""
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

