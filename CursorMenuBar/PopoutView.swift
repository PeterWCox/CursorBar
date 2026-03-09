import SwiftUI
import AppKit

// MARK: - Main popout panel view

struct PopoutView: View {
    @EnvironmentObject var appState: AppState
    var dismiss: () -> Void = {}
    @AppStorage("workspacePath") private var workspacePath: String = FileManager.default.homeDirectoryForCurrentUser.path
    @AppStorage("selectedModel") private var selectedModel: String = "composer-1.5"
    @AppStorage("messagesSentForUsage") private var messagesSentForUsage: Int = 0
    @StateObject private var tabManager = TabManager()
    @State private var devFolders: [URL] = []
    @State private var gitBranches: [String] = []
    @State private var currentBranch: String = ""

    private var tab: AgentTab { tabManager.activeTab }

    private var apiUsagePercent: Int {
        min(100, (messagesSentForUsage * 100) / AppLimits.includedAPIQuota)
    }

    var body: some View {
        VStack(spacing: 12) {
            topBar
            tabBar

            if let error = tab.errorMessage {
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
                .id(tab.id)

            composerDock
        }
        .padding(16)
        .frame(minWidth: 360, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
        .background(CursorTheme.panelGradient)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(CursorTheme.borderStrong, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.36), radius: 28, y: 16)
        .overlay(
            Group {
                Button("New Tab") {
                    tabManager.addTab()
                }
                .keyboardShortcut("t", modifiers: .command)
                .opacity(0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if tabManager.tabs.count > 1 {
                    Button("Close Tab") {
                        stopStreaming(for: tabManager.activeTab)
                        tabManager.closeTab(tabManager.activeTab.id)
                    }
                    .keyboardShortcut("w", modifiers: .command)
                    .opacity(0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        )
    }

    // MARK: - Top bar & tab bar

    private var topBar: some View {
        HStack(spacing: 10) {
            BrandMark(size: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text("Cursor+")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CursorTheme.textPrimary)

                HStack(spacing: 6) {
                    Circle()
                        .fill(tab.isRunning ? CursorTheme.brandBlue : CursorTheme.textTertiary)
                        .frame(width: 6, height: 6)

                    Text(tab.isRunning ? "Streaming response" : "Ready")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CursorTheme.textSecondary)
                }
            }

            Spacer()

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CursorTheme.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(CursorTheme.surfaceMuted, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }

    private var quickActionButtons: some View {
        HStack(spacing: 8) {
            Button {
                openNewTabAndSend(prompt: QuickActionPrompts.fixBuild)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "wrench.and.screwdriver")
                    Text("Fix build")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CursorTheme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(CursorTheme.surfaceMuted, in: Capsule())
                .overlay(Capsule().stroke(CursorTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(tab.isRunning)

            Button {
                openNewTabAndSend(prompt: QuickActionPrompts.commitAndPush)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.circle")
                    Text("Commit & push")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CursorTheme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(CursorTheme.surfaceMuted, in: Capsule())
                .overlay(Capsule().stroke(CursorTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(tab.isRunning)
        }
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(tabManager.tabs) { t in
                    let isSelected = t.id == tabManager.selectedTabID
                    TabChip(
                        title: t.title,
                        isSelected: isSelected,
                        isRunning: t.isRunning,
                        showClose: tabManager.tabs.count > 1,
                        onSelect: { tabManager.selectedTabID = t.id },
                        onClose: {
                            stopStreaming(for: t)
                            tabManager.closeTab(t.id)
                        }
                    )
                }

                Button(action: { tabManager.addTab() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CursorTheme.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(CursorTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(CursorTheme.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Output card

    private var outputCard: some View {
        OutputScrollView(
            tab: tab,
            scrollToken: tab.scrollToken,
            content: {
                VStack(alignment: .leading, spacing: 18) {
                    if tab.turns.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Responses appear here")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(CursorTheme.textSecondary)

                            Text("Ask a question below and Cursor will stream the answer into this panel.")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(CursorTheme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                    } else {
                        ForEach(tab.turns) { turn in
                            ConversationTurnView(turn: turn)
                                .id(turn.id)
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("outputEnd")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
        )
    }

    // MARK: - Composer dock

    private var composerDock: some View {
        let attachedPaths = screenshotPaths(from: tab.prompt)
        return VStack(alignment: .leading, spacing: 12) {
            quickActionButtons

            ForEach(Array(attachedPaths.enumerated()), id: \.offset) { _, path in
                screenshotCard(path: path)
            }

            ZStack(alignment: .topLeading) {
                SubmittableTextEditor(
                    text: Binding(
                        get: { tab.prompt },
                        set: { newValue in
                            tab.prompt = newValue
                            tab.hasAttachedScreenshot = !screenshotPaths(from: newValue).isEmpty
                        }
                    ),
                    isDisabled: tab.isRunning,
                    onSubmit: sendPrompt,
                    onPasteImage: pasteScreenshot
                )
                .frame(height: 88)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(CursorTheme.editor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(CursorTheme.border, lineWidth: 1)
                )

                if tab.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Send message and/or ⌘V to paste one or more screenshots from clipboard")
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundStyle(CursorTheme.textTertiary)
                        .padding(.leading, 16)
                        .padding(.top, 14)
                        .allowsHitTesting(false)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Menu {
                    ForEach(devFolders, id: \.path) { folder in
                        Button {
                            workspacePath = folder.path
                            appState.workspacePath = folder.path
                        } label: {
                            if folder.path == workspacePath {
                                Label(folder.lastPathComponent, systemImage: "checkmark")
                            } else {
                                Text(folder.lastPathComponent)
                            }
                        }
                    }
                    Divider()
                    Button("Browse other folder...") {
                        appState.changeWorkspace()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                        Text(appState.workspaceDisplayName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CursorTheme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CursorTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(CursorTheme.border, lineWidth: 1)
                    )
                }
                .menuStyle(.borderlessButton)
                .foregroundColor(.white)
                .colorScheme(.dark)
                .onAppear { devFolders = loadDevFolders() }

                Menu {
                    ForEach(AvailableModels.all, id: \.id) { model in
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
                    .foregroundStyle(CursorTheme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CursorTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(CursorTheme.border, lineWidth: 1)
                    )
                }
                .menuStyle(.borderlessButton)
                .foregroundColor(.white)
                .colorScheme(.dark)

                Menu {
                    ForEach(gitBranches, id: \.self) { branch in
                        Button {
                            if branch != currentBranch {
                                if let err = gitCheckout(branch: branch, workspacePath: workspacePath) {
                                    tab.errorMessage = err
                                } else {
                                    let (cur, list) = loadGitBranches(workspacePath: workspacePath)
                                    currentBranch = cur
                                    gitBranches = list
                                    tab.errorMessage = nil
                                }
                            }
                        } label: {
                            if branch == currentBranch {
                                Label(branch, systemImage: "checkmark")
                            } else {
                                Text(branch)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.branch")
                        Text(currentBranch.isEmpty ? "No branch" : currentBranch)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CursorTheme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CursorTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(CursorTheme.border, lineWidth: 1)
                    )
                }
                .menuStyle(.borderlessButton)
                .foregroundColor(.white)
                .colorScheme(.dark)
                .disabled(gitBranches.isEmpty)
                .onAppear {
                    let (cur, list) = loadGitBranches(workspacePath: workspacePath)
                    currentBranch = cur
                    gitBranches = list
                }
                .onChange(of: workspacePath) { _, _ in
                    let (cur, list) = loadGitBranches(workspacePath: workspacePath)
                    currentBranch = cur
                    gitBranches = list
                }
            }

            HStack(spacing: 10) {
                Spacer()

                Button {
                    clearContext()
                } label: {
                    let hasContext = !tab.turns.isEmpty || !tab.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                        Text("Summarize")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(hasContext ? CursorTheme.textPrimary : CursorTheme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        hasContext
                            ? CursorTheme.surfaceRaised
                            : CursorTheme.surfaceMuted,
                        in: Capsule()
                    )
                    .overlay(
                        Capsule()
                            .stroke(CursorTheme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(tab.isRunning)

                Button(action: {
                    if tab.isRunning {
                        stopStreaming()
                    } else {
                        sendPrompt()
                    }
                }) {
                    Group {
                        if tab.isRunning {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 12, weight: .black))
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 15, weight: .bold))
                        }
                    }
                    .foregroundStyle(CursorTheme.textPrimary)
                    .frame(width: 36, height: 36)
                    .background {
                        if tab.isRunning {
                            Circle().fill(CursorTheme.surfaceRaised)
                        } else {
                            Circle().fill(CursorTheme.brandGradient)
                        }
                    }
                    .overlay(
                        Circle()
                            .stroke(
                                tab.isRunning
                                    ? CursorTheme.borderStrong
                                    : Color.white.opacity(0.14),
                                lineWidth: 1
                            )
                    )
                    .opacity(tab.isRunning || canSend ? 1 : 0.45)
                }
                .buttonStyle(.plain)
                .disabled(!tab.isRunning && !canSend)
            }

            contextUsageView
        }
        .padding(14)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
        )
    }

    private var contextUsageView: some View {
        let (used, limit) = estimatedContextTokens(prompt: tab.prompt, turns: tab.turns)
        let fraction = limit > 0 ? Double(used) / Double(limit) : 0
        let usedK = used / 1000
        let limitK = limit / 1000
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Context")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CursorTheme.textTertiary)
                Spacer()
                Text("~\(usedK)k / \(limitK)k tokens")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(CursorTheme.textSecondary)
            }
            ProgressView(value: min(1, fraction))
                .tint(fraction > 0.85 ? CursorTheme.brandAmber : CursorTheme.brandBlue)
                .background(CursorTheme.surfaceMuted)
                .scaleEffect(y: 1.2, anchor: .center)
        }
    }

    private func screenshotCard(path: String) -> some View {
        let imageURL = URL(fileURLWithPath: workspacePath).appendingPathComponent(path)

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
                            .foregroundStyle(CursorTheme.textPrimary)

                        Text(path)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CursorTheme.textSecondary)
                            .lineLimit(1)

                        Text("Included with your next prompt")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CursorTheme.textSecondary)
                    }

                    Spacer()

                    Button(action: { deleteScreenshot(path: path) }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(CursorTheme.textSecondary)
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

    // MARK: - Helpers

    private var selectedModelLabel: String {
        AvailableModels.all.first { $0.id == selectedModel }?.label ?? selectedModel
    }

    private var cardBackground: some ShapeStyle {
        CursorTheme.surface
    }

    private var editorBackground: some ShapeStyle {
        CursorTheme.surfaceMuted
    }

    private var cardBorder: Color {
        CursorTheme.border
    }

    private var canSend: Bool {
        !tab.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !tab.isRunning
    }

    private func clearContext() {
        guard !tab.isRunning else { return }
        tab.turns = []
        tab.prompt = ""
        tab.hasAttachedScreenshot = false
        tab.errorMessage = nil
    }

    private func deleteScreenshot(path: String) {
        let reference = "\n\n[Screenshot attached: \(path)]"
        tab.prompt = tab.prompt.replacingOccurrences(of: reference, with: "")
        if !tab.prompt.contains("[Screenshot attached:") {
            tab.hasAttachedScreenshot = false
        }
        let imageURL = URL(fileURLWithPath: workspacePath).appendingPathComponent(path)
        try? FileManager.default.removeItem(at: imageURL)
    }

    private func pasteScreenshot() {
        let currentPaths = screenshotPaths(from: tab.prompt)
        guard currentPaths.count < AppLimits.maxScreenshots,
              let relPath = nextScreenshotPath(currentPaths: currentPaths) else {
            return
        }

        let pasteboard = NSPasteboard.general
        guard let image = SubmittableTextEditor.imageFromPasteboard(pasteboard) else {
            return
        }

        let destURL = URL(fileURLWithPath: workspacePath).appendingPathComponent(relPath)
        let cursorDir = destURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: cursorDir, withIntermediateDirectories: true)
        } catch {
            return
        }

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return
        }

        do {
            try pngData.write(to: destURL)
            let reference = "\n\n[Screenshot attached: \(relPath)]"
            tab.prompt += reference
            tab.hasAttachedScreenshot = true
        } catch {
            return
        }
    }

    private func openNewTabAndSend(prompt: String) {
        tabManager.addTab(initialPrompt: prompt)
        sendPrompt()
    }

    // MARK: - Streaming

    private func sendPrompt() {
        let currentTab = tab
        let trimmed = currentTab.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if currentTab.turns.isEmpty, let generatedTitle = autoGeneratedTabTitle(from: trimmed) {
            currentTab.title = generatedTitle
        }

        let runID = UUID()
        let turnID = UUID()
        currentTab.streamTask?.cancel()
        currentTab.errorMessage = nil
        currentTab.isRunning = true
        currentTab.activeRunID = runID
        currentTab.activeTurnID = turnID
        currentTab.turns.append(ConversationTurn(id: turnID, userPrompt: trimmed, isStreaming: true))
        currentTab.prompt = ""
        currentTab.hasAttachedScreenshot = false
        currentTab.scrollToken = UUID()
        messagesSentForUsage += 1

        let task = Task {
            do {
                if currentTab.cursorChatId == nil {
                    let chatId = try AgentRunner.createChat()
                    guard currentTab.activeRunID == runID else { return }
                    currentTab.cursorChatId = chatId
                }
                let stream = try AgentRunner.stream(prompt: trimmed, workspacePath: workspacePath, model: selectedModel, conversationId: currentTab.cursorChatId)
                guard currentTab.activeRunID == runID, currentTab.activeTurnID == turnID else { return }
                for try await chunk in stream {
                    guard currentTab.activeRunID == runID, currentTab.activeTurnID == turnID, !Task.isCancelled else { return }
                    switch chunk {
                    case .thinkingDelta(let text):
                        appendThinkingText(text, to: turnID, in: currentTab)
                    case .thinkingCompleted:
                        completeThinking(for: turnID, in: currentTab)
                    case .assistantText(let text):
                        mergeAssistantText(text, into: currentTab, turnID: turnID)
                    case .toolCall(let update):
                        mergeToolCall(update, into: currentTab, turnID: turnID)
                    }
                    currentTab.scrollToken = UUID()
                }
                finishStreaming(for: currentTab, runID: runID, turnID: turnID)
            } catch is CancellationError {
                finishStreaming(for: currentTab, runID: runID, turnID: turnID)
            } catch let error as AgentRunnerError {
                finishStreaming(for: currentTab, runID: runID, turnID: turnID, errorMessage: error.userMessage)
            } catch {
                finishStreaming(for: currentTab, runID: runID, turnID: turnID, errorMessage: error.localizedDescription)
            }
        }

        currentTab.streamTask = task
    }

    private func stopStreaming(for currentTab: AgentTab? = nil) {
        let tabToStop = currentTab ?? tab
        if let turnID = tabToStop.activeTurnID,
           let index = tabToStop.turns.firstIndex(where: { $0.id == turnID }) {
            tabToStop.turns[index].isStreaming = false
            tabToStop.turns[index].lastStreamPhase = nil
        }
        tabToStop.activeRunID = nil
        tabToStop.activeTurnID = nil
        tabToStop.isRunning = false
        tabToStop.streamTask?.cancel()
        tabToStop.streamTask = nil
        tabToStop.scrollToken = UUID()
    }

    private func finishStreaming(for currentTab: AgentTab, runID: UUID, turnID: UUID, errorMessage: String? = nil) {
        guard currentTab.activeRunID == runID else { return }
        if let index = currentTab.turns.firstIndex(where: { $0.id == turnID }) {
            currentTab.turns[index].isStreaming = false
            currentTab.turns[index].lastStreamPhase = nil
        }
        currentTab.errorMessage = errorMessage
        currentTab.isRunning = false
        currentTab.streamTask = nil
        currentTab.activeRunID = nil
        currentTab.activeTurnID = nil
        currentTab.scrollToken = UUID()
    }

    private func appendThinkingText(_ incoming: String, to turnID: UUID, in tab: AgentTab) {
        guard !incoming.isEmpty,
              let index = tab.turns.firstIndex(where: { $0.id == turnID }) else {
            return
        }

        if tab.turns[index].lastStreamPhase != .thinking
            || tab.turns[index].segments.last?.kind != .thinking {
            tab.turns[index].segments.append(ConversationSegment(kind: .thinking, text: incoming))
        } else {
            tab.turns[index].segments[tab.turns[index].segments.count - 1].text += incoming
        }
        tab.turns[index].lastStreamPhase = .thinking
    }

    private func completeThinking(for turnID: UUID, in tab: AgentTab) {
        guard let index = tab.turns.firstIndex(where: { $0.id == turnID }) else { return }
        if tab.turns[index].lastStreamPhase == .thinking {
            tab.turns[index].lastStreamPhase = nil
        }
    }

    private func mergeAssistantText(_ incoming: String, into tab: AgentTab, turnID: UUID) {
        guard !incoming.isEmpty else { return }
        guard let index = tab.turns.firstIndex(where: { $0.id == turnID }) else { return }

        tab.turns[index].lastStreamPhase = .assistant

        if tab.turns[index].segments.last?.kind != .assistant {
            tab.turns[index].segments.append(ConversationSegment(kind: .assistant, text: incoming))
            return
        }

        let lastIndex = tab.turns[index].segments.count - 1
        let existing = tab.turns[index].segments[lastIndex].text

        if existing == incoming {
            return
        }

        if incoming.hasPrefix(existing) {
            tab.turns[index].segments[lastIndex].text = incoming
            return
        }

        tab.turns[index].segments[lastIndex].text += incoming
    }

    private func mergeToolCall(_ update: AgentToolCallUpdate, into tab: AgentTab, turnID: UUID) {
        guard let index = tab.turns.firstIndex(where: { $0.id == turnID }) else { return }

        tab.turns[index].lastStreamPhase = .toolCall

        let mappedStatus: ToolCallSegmentStatus
        switch update.status {
        case .started:
            mappedStatus = .running
        case .completed:
            mappedStatus = .completed
        case .failed:
            mappedStatus = .failed
        }

        if let segmentIndex = tab.turns[index].segments.lastIndex(where: { $0.toolCall?.callID == update.callID }) {
            tab.turns[index].segments[segmentIndex].toolCall?.title = update.title
            if !update.detail.isEmpty {
                tab.turns[index].segments[segmentIndex].toolCall?.detail = update.detail
            }
            tab.turns[index].segments[segmentIndex].toolCall?.status = mappedStatus
            return
        }

        tab.turns[index].segments.append(
            ConversationSegment(
                toolCall: ToolCallSegmentData(
                    callID: update.callID,
                    title: update.title,
                    detail: update.detail,
                    status: mappedStatus
                )
            )
        )
    }
}
