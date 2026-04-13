import Foundation
import Combine

@MainActor
final class AgentSessionStore: ObservableObject {
    private let flushIntervalNs: UInt64 = 100_000_000
    private let completionNotifier: AskCompletionNotifying

    init(completionNotifier: AskCompletionNotifying = AskCompletionNotificationService.shared) {
        self.completionNotifier = completionNotifier
    }

    func submitOrQueuePrompt(
        tab: AgentTab,
        selectedModel: String,
        incrementUsage: @escaping () -> Void,
        recordHangEvent: @escaping (String, [String: String]) -> Void,
        updateTabTitle: @escaping (String, AgentTab) -> Void,
        requestAutoScroll: @escaping (AgentTab, Bool) -> Void
    ) {
        let trimmed = tab.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if tab.isRunning {
            queueFollowUp(tab: tab)
            return
        }
        sendPrompt(
            tab: tab,
            selectedModel: selectedModel,
            incrementUsage: incrementUsage,
            recordHangEvent: recordHangEvent,
            updateTabTitle: updateTabTitle,
            requestAutoScroll: requestAutoScroll
        )
    }

    func sendInCurrentTab(
        prompt: String,
        tab: AgentTab,
        selectedModel: String,
        incrementUsage: @escaping () -> Void,
        recordHangEvent: @escaping (String, [String: String]) -> Void,
        updateTabTitle: @escaping (String, AgentTab) -> Void,
        requestAutoScroll: @escaping (AgentTab, Bool) -> Void
    ) {
        guard !tab.isRunning else { return }
        tab.prompt = prompt
        sendPrompt(
            tab: tab,
            selectedModel: selectedModel,
            incrementUsage: incrementUsage,
            recordHangEvent: recordHangEvent,
            updateTabTitle: updateTabTitle,
            requestAutoScroll: requestAutoScroll
        )
    }

    func compressContext(
        tab: AgentTab,
        selectedModel: String,
        incrementUsage: @escaping () -> Void,
        recordHangEvent: @escaping (String, [String: String]) -> Void,
        updateTabTitle: @escaping (String, AgentTab) -> Void,
        requestAutoScroll: @escaping (AgentTab, Bool) -> Void
    ) {
        guard !tab.isRunning else { return }
        let hasContext = !tab.turns.isEmpty || !tab.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !hasContext {
            clearContext(tab: tab)
            return
        }
        tab.prompt = Self.compressPrompt
        tab.isCompressRequest = true
        sendPrompt(
            tab: tab,
            selectedModel: selectedModel,
            incrementUsage: incrementUsage,
            recordHangEvent: recordHangEvent,
            updateTabTitle: updateTabTitle,
            requestAutoScroll: requestAutoScroll
        )
    }

    func clearContext(tab: AgentTab) {
        guard !tab.isRunning else { return }
        tab.turns = []
        tab.cachedConversationCharacterCount = 0
        tab.prompt = ""
        tab.hasAttachedScreenshot = false
        tab.errorMessage = nil
    }

    func stopStreaming(
        for tab: AgentTab,
        recordHangEvent: @escaping (String, [String: String]) -> Void,
        requestAutoScroll: @escaping (AgentTab, Bool) -> Void
    ) {
        recordHangEvent("stop-streaming", [
            "tabID": tab.id.uuidString,
            "workspacePath": tab.workspacePath,
            "linkedTaskID": tab.linkedTaskID?.uuidString ?? "nil"
        ])

        let turnIndex: Int? = {
            if let turnID = tab.activeTurnID,
               let idx = tab.turns.firstIndex(where: { $0.id == turnID }) {
                return idx
            }
            return tab.turns.indices.last
        }()

        if let index = turnIndex {
            tab.turns[index].isStreaming = false
            tab.turns[index].lastStreamPhase = nil
            tab.turns[index].wasStopped = true
            for segmentIndex in tab.turns[index].segments.indices {
                if tab.turns[index].segments[segmentIndex].toolCall?.status == .running {
                    tab.turns[index].segments[segmentIndex].toolCall?.status = .stopped
                }
            }
            notifyTurnsChanged(tab)
        }

        tab.activeRunID = nil
        tab.activeTurnID = nil
        tab.isRunning = false
        tab.streamTask?.cancel()
        tab.streamTask = nil
        requestAutoScroll(tab, true)
    }

    func sendPrompt(
        tab currentTab: AgentTab,
        selectedModel: String,
        incrementUsage: @escaping () -> Void,
        recordHangEvent: @escaping (String, [String: String]) -> Void,
        updateTabTitle: @escaping (String, AgentTab) -> Void,
        requestAutoScroll: @escaping (AgentTab, Bool) -> Void
    ) {
        let trimmed = currentTab.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        recordHangEvent("send-prompt", [
            "tabID": currentTab.id.uuidString,
            "workspacePath": currentTab.workspacePath,
            "linkedTaskID": currentTab.linkedTaskID?.uuidString ?? "nil",
            "promptLength": "\(trimmed.count)"
        ])

        updateTabTitle(trimmed, currentTab)

        let runID = UUID()
        let turnID = UUID()
        if currentTab.isCompressRequest {
            currentTab.pendingCompressRunID = runID
            currentTab.isCompressRequest = false
        }

        currentTab.streamTask?.cancel()
        currentTab.errorMessage = nil
        currentTab.isRunning = true
        currentTab.activeRunID = runID
        currentTab.activeTurnID = turnID
        currentTab.turns.append(ConversationTurn(id: turnID, userPrompt: trimmed, isStreaming: true, wasStopped: false))
        currentTab.cachedConversationCharacterCount += trimmed.count
        currentTab.prompt = ""
        currentTab.hasAttachedScreenshot = false
        requestAutoScroll(currentTab, true)
        incrementUsage()

        let task = Task {
            do {
                let providerID = currentTab.providerID
                let modelToUse = currentTab.modelId ?? selectedModel
                let streamRequest = AgentStreamRequest(
                    prompt: trimmed,
                    workspacePath: currentTab.workspacePath,
                    modelID: modelToUse,
                    conversationID: currentTab.conversationID
                )
                let stream = try await Task.detached(priority: .userInitiated) {
                    let p = AgentProviders.provider(for: providerID)
                    return try p.stream(request: streamRequest)
                }.value

                guard currentTab.activeRunID == runID, currentTab.activeTurnID == turnID else { return }

                var thinkingBuffer = ""
                var assistantBuffer = ""
                var flushTask: Task<Void, Never>?

                func flushBatched() {
                    let thinking = thinkingBuffer
                    let assistant = assistantBuffer
                    thinkingBuffer = ""
                    assistantBuffer = ""

                    Task { @MainActor in
                        if !thinking.isEmpty {
                            self.appendThinkingText(thinking, to: turnID, in: currentTab)
                        }
                        if !assistant.isEmpty {
                            self.mergeAssistantText(assistant, into: currentTab, turnID: turnID)
                        }
                        requestAutoScroll(currentTab, false)
                    }
                }

                func scheduleFlush() {
                    flushTask?.cancel()
                    flushTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: self.flushIntervalNs)
                        guard currentTab.activeRunID == runID, currentTab.activeTurnID == turnID else { return }
                        flushBatched()
                        flushTask = nil
                    }
                }

                for try await chunk in stream {
                    guard currentTab.activeRunID == runID, currentTab.activeTurnID == turnID, !Task.isCancelled else { return }
                    switch chunk {
                    case .sessionInitialized(let sessionID):
                        currentTab.conversationID = sessionID
                    case .thinkingDelta(let text):
                        thinkingBuffer += text
                        scheduleFlush()
                    case .thinkingCompleted:
                        flushBatched()
                        completeThinking(for: turnID, in: currentTab)
                        requestAutoScroll(currentTab, false)
                    case .assistantText(let text):
                        assistantBuffer += text
                        scheduleFlush()
                    case .toolCall(let update):
                        flushBatched()
                        mergeToolCall(update, into: currentTab, turnID: turnID)
                        requestAutoScroll(currentTab, false)
                    }
                }

                flushTask?.cancel()
                flushBatched()
                finishStreaming(
                    for: currentTab,
                    runID: runID,
                    turnID: turnID,
                    errorMessage: nil,
                    selectedModel: selectedModel,
                    incrementUsage: incrementUsage,
                    recordHangEvent: recordHangEvent,
                    updateTabTitle: updateTabTitle,
                    requestAutoScroll: requestAutoScroll
                )
            } catch is CancellationError {
                finishStreaming(
                    for: currentTab,
                    runID: runID,
                    turnID: turnID,
                    errorMessage: nil,
                    selectedModel: selectedModel,
                    incrementUsage: incrementUsage,
                    recordHangEvent: recordHangEvent,
                    updateTabTitle: updateTabTitle,
                    requestAutoScroll: requestAutoScroll
                )
            } catch let error as AgentProviderError {
                finishStreaming(
                    for: currentTab,
                    runID: runID,
                    turnID: turnID,
                    errorMessage: error.userMessage,
                    selectedModel: selectedModel,
                    incrementUsage: incrementUsage,
                    recordHangEvent: recordHangEvent,
                    updateTabTitle: updateTabTitle,
                    requestAutoScroll: requestAutoScroll
                )
            } catch {
                finishStreaming(
                    for: currentTab,
                    runID: runID,
                    turnID: turnID,
                    errorMessage: error.localizedDescription,
                    selectedModel: selectedModel,
                    incrementUsage: incrementUsage,
                    recordHangEvent: recordHangEvent,
                    updateTabTitle: updateTabTitle,
                    requestAutoScroll: requestAutoScroll
                )
            }

            if currentTab.pendingCompressRunID == runID {
                Task { @MainActor in
                    let summary: String
                    if let idx = currentTab.turns.firstIndex(where: { $0.id == turnID }) {
                        summary = Self.fullAssistantText(for: currentTab.turns[idx])
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        summary = ""
                    }

                    currentTab.pendingCompressRunID = nil

                    currentTab.conversationID = nil
                    currentTab.turns = []
                    currentTab.cachedConversationCharacterCount = 0
                    currentTab.prompt = summary
                    currentTab.hasAttachedScreenshot = false
                    currentTab.errorMessage = nil
                }
            }
        }

        currentTab.streamTask = task
    }

    private func finishStreaming(
        for currentTab: AgentTab,
        runID: UUID,
        turnID: UUID,
        errorMessage: String?,
        selectedModel: String,
        incrementUsage: @escaping () -> Void,
        recordHangEvent: @escaping (String, [String: String]) -> Void,
        updateTabTitle: @escaping (String, AgentTab) -> Void,
        requestAutoScroll: @escaping (AgentTab, Bool) -> Void
    ) {
        guard currentTab.activeRunID == runID else { return }

        recordHangEvent("finish-streaming", [
            "tabID": currentTab.id.uuidString,
            "workspacePath": currentTab.workspacePath,
            "linkedTaskID": currentTab.linkedTaskID?.uuidString ?? "nil",
            "hadError": errorMessage == nil ? "false" : "true"
        ])

        if let index = currentTab.turns.firstIndex(where: { $0.id == turnID }) {
            currentTab.turns[index].isStreaming = false
            currentTab.turns[index].lastStreamPhase = nil
            currentTab.turns[index].wasStopped = false
            notifyTurnsChanged(currentTab)
        }

        currentTab.errorMessage = errorMessage
        currentTab.isRunning = false
        currentTab.streamTask = nil
        currentTab.activeRunID = nil
        currentTab.activeTurnID = nil
        requestAutoScroll(currentTab, true)

        let shouldNotifyCompletion = currentTab.followUpQueue.isEmpty
            && currentTab.pendingCompressRunID != runID
        if shouldNotifyCompletion {
            completionNotifier.notifyAskFinished(
                taskTitle: currentTab.title,
                workspacePath: currentTab.workspacePath,
                hadError: errorMessage != nil
            )
        }

        if !currentTab.followUpQueue.isEmpty {
            processNextQueuedFollowUp(
                tab: currentTab,
                selectedModel: selectedModel,
                incrementUsage: incrementUsage,
                recordHangEvent: recordHangEvent,
                updateTabTitle: updateTabTitle,
                requestAutoScroll: requestAutoScroll
            )
        }
    }

    private func queueFollowUp(tab: AgentTab) {
        let trimmed = tab.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tab.followUpQueue.append(QueuedFollowUp(text: tab.prompt))
        tab.prompt = ""
        tab.hasAttachedScreenshot = false
    }

    private func processNextQueuedFollowUp(
        tab: AgentTab,
        selectedModel: String,
        incrementUsage: @escaping () -> Void,
        recordHangEvent: @escaping (String, [String: String]) -> Void,
        updateTabTitle: @escaping (String, AgentTab) -> Void,
        requestAutoScroll: @escaping (AgentTab, Bool) -> Void
    ) {
        guard let first = tab.followUpQueue.first else { return }
        tab.followUpQueue.removeFirst()
        tab.prompt = first.text
        tab.hasAttachedScreenshot = !screenshotPaths(from: first.text).isEmpty
        sendPrompt(
            tab: tab,
            selectedModel: selectedModel,
            incrementUsage: incrementUsage,
            recordHangEvent: recordHangEvent,
            updateTabTitle: updateTabTitle,
            requestAutoScroll: requestAutoScroll
        )
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
        tab.cachedConversationCharacterCount += incoming.count
        tab.turns[index].lastStreamPhase = .thinking
        notifyTurnsChangedIfThrottled(tab)
    }

    private func completeThinking(for turnID: UUID, in tab: AgentTab) {
        guard let index = tab.turns.firstIndex(where: { $0.id == turnID }) else { return }
        if tab.turns[index].lastStreamPhase == .thinking {
            tab.turns[index].lastStreamPhase = nil
            notifyTurnsChanged(tab)
        }
    }

    private func mergeAssistantText(_ incoming: String, into tab: AgentTab, turnID: UUID) {
        guard !incoming.isEmpty else { return }
        guard let index = tab.turns.firstIndex(where: { $0.id == turnID }) else { return }

        tab.turns[index].lastStreamPhase = .assistant

        if tab.turns[index].segments.last?.kind != .assistant {
            tab.turns[index].segments.append(ConversationSegment(kind: .assistant, text: incoming))
            tab.cachedConversationCharacterCount += incoming.count
            notifyTurnsChangedIfThrottled(tab)
            return
        }

        let lastIndex = tab.turns[index].segments.count - 1
        let existing = tab.turns[index].segments[lastIndex].text

        if existing == incoming {
            return
        }

        if incoming.hasPrefix(existing) {
            tab.turns[index].segments[lastIndex].text = incoming
            tab.cachedConversationCharacterCount += incoming.count - existing.count
        } else {
            tab.turns[index].segments[lastIndex].text += incoming
            tab.cachedConversationCharacterCount += incoming.count
        }
        notifyTurnsChangedIfThrottled(tab)
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
            notifyTurnsChanged(tab)
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
        notifyTurnsChanged(tab)
    }

    private func notifyTurnsChanged(_ tab: AgentTab) {
        if Thread.isMainThread {
            tab.objectWillChange.send()
        } else {
            DispatchQueue.main.async {
                tab.objectWillChange.send()
            }
        }
    }

    private func notifyTurnsChangedIfThrottled(_ tab: AgentTab) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - tab.lastStreamUIUpdateAt >= 0.1 else { return }
        tab.lastStreamUIUpdateAt = now
        notifyTurnsChanged(tab)
    }

    private static func fullAssistantText(for turn: ConversationTurn) -> String {
        turn.segments
            .filter { $0.kind == .assistant }
            .map(\.text)
            .joined()
    }

    private static let compressPrompt = "Summarize our entire conversation so far into a single concise summary that preserves key context, decisions, and next steps. Reply with only that summary, no other text."
}
