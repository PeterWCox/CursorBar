import Foundation

enum AgentProviderID: String, Codable, CaseIterable, Identifiable {
    case cursor
    case claudeCode

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cursor:
            return "Cursor"
        case .claudeCode:
            return "Claude Code"
        }
    }

    /// In-app product name shown beside the selected agent backend (e.g. sidebar, welcome header).
    var metroAppMarketingName: String {
        switch self {
        case .cursor:
            return "Cursor Metro"
        case .claudeCode:
            return "Claude Metro"
        }
    }

    /// Wordmark / logo asset in `Assets.xcassets` for the active backend.
    var metroLogoAssetName: String {
        switch self {
        case .cursor:
            return "CursorMetroLogo"
        case .claudeCode:
            return "ClaudeMetroLogo"
        }
    }

    /// Resolves the saved backend from shared `UserDefaults` (same key as Settings → Agent).
    static func resolvedFromStorage(_ defaults: UserDefaults = .standard) -> AgentProviderID {
        let raw = defaults.string(forKey: AppPreferences.selectedAgentProviderIDKey) ?? Self.claudeCode.rawValue
        return AgentProviderID(rawValue: raw) ?? .claudeCode
    }
}

struct AgentProviderDescriptor {
    let id: AgentProviderID
    let displayName: String
    let defaultModelID: String
    let fallbackModels: [ModelOption]
    let defaultEnabledModelIds: Set<String>
    let defaultShownModelIds: Set<String>
}

struct AgentStreamRequest {
    let prompt: String
    let workspacePath: String
    let modelID: String?
    let conversationID: String?
}

protocol AgentProvider {
    var descriptor: AgentProviderDescriptor { get }
    func listModels() async throws -> [ModelOption]
    func stream(request: AgentStreamRequest) throws -> AsyncThrowingStream<AgentStreamChunk, Error>
}

enum AgentProviders {
    static let defaultProviderID: AgentProviderID = .claudeCode

    static func provider(for id: AgentProviderID) -> any AgentProvider {
        switch id {
        case .cursor:
            return CursorAgentProvider.shared
        case .claudeCode:
            return ClaudeCodeAgentProvider.shared
        }
    }

    static func resolvedProviderID(_ rawValue: String) -> AgentProviderID {
        AgentProviderID(rawValue: rawValue) ?? defaultProviderID
    }

    static func descriptor(for id: AgentProviderID) -> AgentProviderDescriptor {
        provider(for: id).descriptor
    }

    static func defaultModelID(for id: AgentProviderID) -> String {
        descriptor(for: id).defaultModelID
    }

    static func fallbackModels(for id: AgentProviderID) -> [ModelOption] {
        descriptor(for: id).fallbackModels
    }

    static func defaultEnabledModelIds(for id: AgentProviderID) -> Set<String> {
        descriptor(for: id).defaultEnabledModelIds
    }

    static func defaultShownModelIds(for id: AgentProviderID) -> Set<String> {
        descriptor(for: id).defaultShownModelIds
    }
}

// MARK: - Cursor stream-json payloads

private struct StreamEvent: Decodable {
    let type: String?
    let subtype: String?
    let text: String?
    let message: StreamMessage?
    let callID: String?
    let toolCall: StreamToolCallPayload?
    let title: String?
    let id: String?
    let input: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case type
        case subtype
        case text
        case message
        case callID = "call_id"
        case toolCall = "tool_call"
        case title
        case id
        case input
    }
}

private struct StreamMessage: Decodable {
    let content: [StreamContent]?
}

private struct StreamContent: Decodable {
    let type: String?
    let text: String?
}

private struct StreamToolCallPayload: Decodable {
    let toolName: String
    let description: String?
    let args: StreamToolCallArgs?
    let result: StreamToolCallResult?
    let name: String?
    let input: JSONValue?
    let id: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)

        name = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey(stringValue: "name"))
        id = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey(stringValue: "id"))
        input = try container.decodeIfPresent(JSONValue.self, forKey: DynamicCodingKey(stringValue: "input"))

        guard let key = container.allKeys.first(where: { $0.stringValue != "name" && $0.stringValue != "id" && $0.stringValue != "input" }),
              let invocation = try container.decodeIfPresent(StreamToolInvocation.self, forKey: key) else {
            toolName = "Tool"
            description = nil
            args = nil
            result = nil
            return
        }

        toolName = Self.displayName(for: key.stringValue)
        description = invocation.description
        args = invocation.args
        result = invocation.result
    }

    private static func displayName(for rawName: String) -> String {
        let trimmed = rawName.replacingOccurrences(of: "ToolCall", with: "")
        let separated = trimmed.replacingOccurrences(
            of: "([a-z0-9])([A-Z])",
            with: "$1 $2",
            options: .regularExpression
        )
        return separated
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

private struct StreamToolInvocation: Decodable {
    let description: String?
    let args: StreamToolCallArgs?
    let result: StreamToolCallResult?
}

private struct StreamToolCallArgs: Decodable {
    let command: String?
    let path: String?
    let globPattern: String?
    let pattern: String?
    let query: String?
    let url: String?
    let workingDirectory: String?
    let description: String?
}

private struct StreamToolCallResult: Decodable {
    let success: StreamToolCallSuccess?
    let failure: StreamToolCallFailure?
    let error: StreamToolCallFailure?
}

private struct StreamToolCallSuccess: Decodable {
    let exitCode: Int?
    let executionTime: Int?
    let localExecutionTimeMs: Int?
    let durationMs: Int?
}

private struct StreamToolCallFailure: Decodable {
    let exitCode: Int?
    let stderr: String?
    let message: String?
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }
}

// MARK: - Claude Code stream-json payloads

private struct ClaudeStreamEnvelope: Decodable {
    let type: String?
    let subtype: String?
    let sessionID: String?
    let message: ClaudeMessage?
    let event: ClaudeStreamEvent?
    let toolUseResult: ClaudeToolUseResultPayload?

    private enum CodingKeys: String, CodingKey {
        case type
        case subtype
        case sessionID = "session_id"
        case message
        case event
        case toolUseResult = "tool_use_result"
    }
}

private struct ClaudeMessage: Decodable {
    let role: String?
    let content: [ClaudeContentBlock]?
}

private struct ClaudeContentBlock: Decodable {
    let type: String?
    let id: String?
    let name: String?
    let text: String?
    let input: JSONValue?
    let toolUseID: String?
    let content: JSONValue?
    let isError: Bool?

    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case name
        case text
        case input
        case toolUseID = "tool_use_id"
        case content
        case isError = "is_error"
    }
}

private struct ClaudeStreamEvent: Decodable {
    let type: String?
    let index: Int?
    let contentBlock: ClaudeStreamContentBlock?
    let delta: ClaudeStreamDelta?

    private enum CodingKeys: String, CodingKey {
        case type
        case index
        case contentBlock = "content_block"
        case delta
    }
}

private struct ClaudeStreamContentBlock: Decodable {
    let type: String?
    let id: String?
    let name: String?
}

private struct ClaudeStreamDelta: Decodable {
    let type: String?
    let text: String?
    let partialJSON: String?
    let thinking: String?

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case partialJSON = "partial_json"
        case thinking
    }
}

private struct ClaudeToolUseResultPayload: Decodable {
    let stdout: String?
    let stderr: String?
    let interrupted: Bool?
    let noOutputExpected: Bool?
}

private enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    var renderedInline: String {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            if value.rounded(.towardZero) == value {
                return String(Int(value))
            }
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .null:
            return "null"
        case .object, .array:
            return prettyPrintedJSON ?? ""
        }
    }

    var prettyPrintedJSON: String? {
        guard let object = foundationObject else { return nil }
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    private var foundationObject: Any? {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return value
        case .bool(let value):
            return value
        case .null:
            return NSNull()
        case .object(let value):
            return value.mapValues(\.foundationObject)
        case .array(let value):
            return value.map(\.foundationObject)
        }
    }
}

private struct PartialToolUseState {
    let callID: String
    let title: String
    var partialInputJSON: String = ""
    var resolvedDetail: String = ""
}

enum AgentStreamChunk {
    case sessionInitialized(String)
    case thinkingDelta(String)
    case thinkingCompleted
    case assistantText(String)
    case toolCall(AgentToolCallUpdate)
}

enum AgentToolCallStatus {
    case started
    case completed
    case failed
}

struct AgentToolCallUpdate {
    let callID: String
    let title: String
    let detail: String
    let status: AgentToolCallStatus
}

enum AgentProviderError: Error {
    case agentNotFound
    case processFailed(exitCode: Int32, stderr: String)

    var userMessage: String {
        switch self {
        case .agentNotFound:
            return "Claude Code CLI not found. Install the `claude` CLI and ensure it is available on your PATH."
        case .processFailed(let code, let stderr):
            var msg = "Agent exited with code \(code)."
            if !stderr.isEmpty {
                msg += "\n\n\(stderr)"
            }
            if stderr.localizedCaseInsensitiveContains("login")
                || stderr.localizedCaseInsensitiveContains("auth")
                || stderr.localizedCaseInsensitiveContains("authenticate") {
                msg += "\n\nTry signing in to Claude Code in Terminal and then run the request again."
            }
            return msg
        }
    }
}

final class CursorAgentProvider: AgentProvider {
    static let shared = CursorAgentProvider()

    let descriptor = AgentProviderDescriptor(
        id: .cursor,
        displayName: AgentProviderID.cursor.displayName,
        defaultModelID: AvailableModels.autoID,
        fallbackModels: AvailableModels.fallback,
        defaultEnabledModelIds: AvailableModels.defaultEnabledModelIds,
        defaultShownModelIds: AvailableModels.defaultShownModelIds
    )

    private init() {}

    /// Creates a new Cursor CLI chat and returns its ID. Use this before the first message in a tab so follow-ups can use `--resume`.
    func createConversation() throws -> String {
        guard let agentPath = Self.findAgentPath() else {
            throw AgentProviderError.agentNotFound
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: agentPath)
        process.arguments = ["create-chat"]
        let env = ProcessInfo.processInfo.environment
        var fullEnv = env
        if let path = env["PATH"], !path.contains(".local/bin") {
            let home = env["HOME"] ?? NSHomeDirectory()
            fullEnv["PATH"] = "\(home)/.local/bin:\(path)"
        }
        process.environment = fullEnv
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw AgentProviderError.processFailed(exitCode: process.terminationStatus, stderr: "")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let id = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .newlines)
        guard let id = id, !id.isEmpty else {
            throw AgentProviderError.processFailed(exitCode: -1, stderr: "create-chat did not return a chat ID")
        }
        return id
    }

    /// Fetches available models from the Cursor Agent CLI (`agent models`). Call from a background context.
    func listModels() async throws -> [ModelOption] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try Self.runListModelsSync()
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    nonisolated private static func runListModelsSync() throws -> [ModelOption] {
        guard let agentPath = findAgentPath() else {
            throw AgentProviderError.agentNotFound
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: agentPath)
        process.arguments = ["models"]
        let env = ProcessInfo.processInfo.environment
        var fullEnv = env
        if let path = env["PATH"], !path.contains(".local/bin") {
            let home = env["HOME"] ?? NSHomeDirectory()
            fullEnv["PATH"] = "\(home)/.local/bin:\(path)"
        }
        process.environment = fullEnv
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw AgentProviderError.processFailed(exitCode: process.terminationStatus, stderr: "")
        }
        guard let output = String(data: data, encoding: .utf8) else {
            throw AgentProviderError.processFailed(exitCode: -1, stderr: "Could not decode agent models output")
        }
        return Self.parseModelsOutput(output)
    }

    /// Parses `agent models` stdout: lines like "id - Label" or "id - Label  (current)".
    nonisolated private static func parseModelsOutput(_ output: String) -> [ModelOption] {
        let knownPremiumIds: Set<String> = [
            "gpt-5.4-medium", "gpt-5.4-high", "gpt-5.4-xhigh", "gpt-5.4-medium-fast", "gpt-5.4-high-fast", "gpt-5.4-xhigh-fast",
            "composer-1.5", "composer-1",
            "opus-4.6", "opus-4.6-thinking", "opus-4.5", "opus-4.5-thinking",
            "sonnet-4.6", "sonnet-4.6-thinking", "sonnet-4.5", "sonnet-4.5-thinking",
        ]
        func stripANSI(_ s: String) -> String {
            let pattern = "\\x1B\\[[0-9;]*[a-zA-Z]"
            return s.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        var result: [ModelOption] = []
        for line in output.components(separatedBy: .newlines) {
            let cleaned = stripANSI(line).trimmingCharacters(in: .whitespaces)
            guard cleaned.contains(" - ") else { continue }
            if cleaned.hasPrefix("Available models") || cleaned.hasPrefix("Loading") || cleaned.hasPrefix("Tip:") {
                continue
            }
            guard let dashRange = cleaned.range(of: " - ") else { continue }
            let id = String(cleaned[..<dashRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let label = String(cleaned[dashRange.upperBound...])
                .replacingOccurrences(of: "  (current)", with: "")
                .replacingOccurrences(of: "  (default)", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard !id.isEmpty, !label.isEmpty else { continue }
            result.append(ModelOption(
                id: id,
                label: label,
                isPremium: knownPremiumIds.contains(id)
            ))
        }
        return result
    }

    func stream(request: AgentStreamRequest) throws -> AsyncThrowingStream<AgentStreamChunk, Error> {
        guard let agentPath = Self.findAgentPath() else {
            throw AgentProviderError.agentNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: agentPath)
        var args = [
            "-f",
            "-p", request.prompt,
            "--workspace", request.workspacePath,
            "--output-format", "stream-json",
            "--stream-partial-output"
        ]
        if let conversationId = request.conversationID, !conversationId.isEmpty {
            args += ["--resume", conversationId]
        }
        if let model = request.modelID, !model.isEmpty {
            args += ["--model", model]
        }
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: projectRootForTerminal(workspacePath: request.workspacePath))

        let env = ProcessInfo.processInfo.environment
        var fullEnv = env
        if let path = env["PATH"], !path.contains(".local/bin") {
            let home = env["HOME"] ?? NSHomeDirectory()
            fullEnv["PATH"] = "\(home)/.local/bin:\(path)"
        }
        process.environment = fullEnv

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        return AsyncThrowingStream { continuation in
            continuation.onTermination = { @Sendable _ in
                if process.isRunning {
                    process.terminate()
                }
            }

            Task.detached {
                let stderrTask = Task.detached { () -> String in
                    let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    return String(data: data, encoding: .utf8) ?? ""
                }

                let handle = stdoutPipe.fileHandleForReading
                let decoder = JSONDecoder()
                var lineBuffer = ""
                var streamComplete = false

                while true {
                    let data = handle.availableData
                    if data.isEmpty { break }

                    guard let chunk = String(data: data, encoding: .utf8) else { continue }
                    lineBuffer += chunk

                    while let newlineIndex = lineBuffer.firstIndex(of: "\n") {
                        let line = String(lineBuffer[..<newlineIndex])
                        lineBuffer = String(lineBuffer[lineBuffer.index(after: newlineIndex)...])

                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { continue }

                        do {
                            let event = try decoder.decode(StreamEvent.self, from: Data(trimmed.utf8))

                            if event.type == "result" {
                                streamComplete = true
                                break
                            }

                            if event.type == "thinking" {
                                if event.subtype == "delta", let text = event.text, !text.isEmpty {
                                    continuation.yield(.thinkingDelta(text))
                                } else if event.subtype == "completed" {
                                    continuation.yield(.thinkingCompleted)
                                }
                                continue
                            }

                            if let toolCallUpdate = Self.toolCallUpdate(from: event) {
                                continuation.yield(.toolCall(toolCallUpdate))
                                continue
                            }

                            if event.type == "assistant", let message = event.message, let content = message.content {
                                for item in content {
                                    if item.type == "text", let text = item.text, !text.isEmpty {
                                        continuation.yield(.assistantText(text))
                                    }
                                }
                            }
                        } catch {
                            continue
                        }
                    }

                    if streamComplete { break }
                }

                process.waitUntilExit()
                let stderrStr = await stderrTask.value

                if process.terminationStatus != 0 {
                    continuation.finish(throwing: AgentProviderError.processFailed(
                        exitCode: process.terminationStatus, stderr: stderrStr))
                } else {
                    continuation.finish()
                }
            }
        }
    }

    nonisolated private static func findAgentPath() -> String? {
        let pathsToCheck = [
            "\(NSHomeDirectory())/.local/bin/agent",
            "/usr/local/bin/agent",
            "/opt/homebrew/bin/agent"
        ]

        for path in pathsToCheck {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for component in path.split(separator: ":") {
                let candidate = "\(component)/agent"
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }

        return nil
    }

    nonisolated private static func toolCallUpdate(from event: StreamEvent) -> AgentToolCallUpdate? {
        guard event.type == "tool_call" else { return nil }
        guard let callID = event.toolCall?.id ?? event.id else { return nil }
        let title = event.toolCall?.name ?? event.title ?? "Tool"

        let status: AgentToolCallStatus
        if event.subtype == "started" {
            status = .started
        } else if event.subtype == "completed" {
            status = .completed
        } else if event.subtype == "failed" {
            status = .failed
        } else {
            return nil
        }

        let detail = event.toolCall?.input.map { $0.renderedInline } ?? ""
        return AgentToolCallUpdate(callID: callID, title: title, detail: detail, status: status)
    }
}

final class ClaudeCodeAgentProvider: AgentProvider {
    static let shared = ClaudeCodeAgentProvider()

    let descriptor = AgentProviderDescriptor(
        id: .claudeCode,
        displayName: AgentProviderID.claudeCode.displayName,
        defaultModelID: AvailableModels.autoID,
        fallbackModels: AvailableModels.fallback,
        defaultEnabledModelIds: AvailableModels.defaultEnabledModelIds,
        defaultShownModelIds: AvailableModels.defaultShownModelIds
    )

    private init() {}

    func listModels() async throws -> [ModelOption] {
        AvailableModels.fallback
    }

    func stream(request: AgentStreamRequest) throws -> AsyncThrowingStream<AgentStreamChunk, Error> {
        guard let claudePath = Self.findClaudePath() else {
            throw AgentProviderError.agentNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)

        var args = [
            "-p", request.prompt,
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            "--permission-mode", "bypassPermissions"
        ]
        if let conversationID = request.conversationID, !conversationID.isEmpty {
            args += ["--resume", conversationID]
        }
        if let model = request.modelID, !model.isEmpty, model != AvailableModels.autoID {
            args += ["--model", model]
        }
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: projectRootForTerminal(workspacePath: request.workspacePath))

        let env = ProcessInfo.processInfo.environment
        var fullEnv = env
        if let path = env["PATH"], !path.contains(".local/bin") {
            let home = env["HOME"] ?? NSHomeDirectory()
            fullEnv["PATH"] = "\(home)/.local/bin:\(path)"
        }
        process.environment = fullEnv

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        try process.run()

        return AsyncThrowingStream { continuation in
            continuation.onTermination = { @Sendable _ in
                if process.isRunning {
                    process.terminate()
                }
            }

            Task.detached {
                let stderrTask = Task.detached { () -> String in
                    let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    return String(data: data, encoding: .utf8) ?? ""
                }

                let handle = stdoutPipe.fileHandleForReading
                let decoder = JSONDecoder()
                var lineBuffer = ""
                var activeToolUses: [Int: PartialToolUseState] = [:]

                while true {
                    let data = handle.availableData
                    if data.isEmpty { break }

                    guard let chunk = String(data: data, encoding: .utf8) else { continue }
                    lineBuffer += chunk

                    while let newlineIndex = lineBuffer.firstIndex(of: "\n") {
                        let line = String(lineBuffer[..<newlineIndex])
                        lineBuffer = String(lineBuffer[lineBuffer.index(after: newlineIndex)...])

                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { continue }

                        guard let envelope = try? decoder.decode(ClaudeStreamEnvelope.self, from: Data(trimmed.utf8)) else {
                            continue
                        }

                        if let sessionID = envelope.sessionID, !sessionID.isEmpty {
                            continuation.yield(.sessionInitialized(sessionID))
                        }

                        switch envelope.type {
                        case "stream_event":
                            Self.handleStreamEvent(
                                envelope.event,
                                activeToolUses: &activeToolUses,
                                continuation: continuation
                            )
                        case "user":
                            Self.handleToolResultMessage(
                                envelope,
                                activeToolUses: &activeToolUses,
                                continuation: continuation
                            )
                        default:
                            break
                        }
                    }
                }

                process.waitUntilExit()
                let stderrStr = await stderrTask.value

                if process.terminationStatus != 0 {
                    continuation.finish(throwing: AgentProviderError.processFailed(
                        exitCode: process.terminationStatus,
                        stderr: stderrStr
                    ))
                } else {
                    continuation.finish()
                }
            }
        }
    }

    nonisolated private static func handleStreamEvent(
        _ event: ClaudeStreamEvent?,
        activeToolUses: inout [Int: PartialToolUseState],
        continuation: AsyncThrowingStream<AgentStreamChunk, Error>.Continuation
    ) {
        guard let event else { return }

        switch event.type {
        case "content_block_start":
            guard let index = event.index,
                  event.contentBlock?.type == "tool_use" else { return }

            let callID = event.contentBlock?.id ?? UUID().uuidString
            let title = displayName(forTool: event.contentBlock?.name)
            let state = PartialToolUseState(callID: callID, title: title)
            activeToolUses[index] = state
            continuation.yield(.toolCall(AgentToolCallUpdate(
                callID: callID,
                title: title,
                detail: "",
                status: .started
            )))

        case "content_block_delta":
            guard let delta = event.delta else { return }
            switch delta.type {
            case "text_delta":
                if let text = delta.text, !text.isEmpty {
                    continuation.yield(.assistantText(text))
                }
            case "thinking_delta":
                if let thinking = delta.thinking, !thinking.isEmpty {
                    continuation.yield(.thinkingDelta(thinking))
                }
            case "input_json_delta":
                guard let index = event.index,
                      var state = activeToolUses[index] else { return }
                state.partialInputJSON += delta.partialJSON ?? ""
                state.resolvedDetail = toolInputDetail(fromPartialJSON: state.partialInputJSON)
                activeToolUses[index] = state
                continuation.yield(.toolCall(AgentToolCallUpdate(
                    callID: state.callID,
                    title: state.title,
                    detail: state.resolvedDetail,
                    status: .started
                )))
            default:
                break
            }

        case "content_block_stop":
            if let index = event.index, activeToolUses[index] != nil {
                return
            }
            continuation.yield(.thinkingCompleted)

        default:
            break
        }
    }

    nonisolated private static func handleToolResultMessage(
        _ envelope: ClaudeStreamEnvelope,
        activeToolUses: inout [Int: PartialToolUseState],
        continuation: AsyncThrowingStream<AgentStreamChunk, Error>.Continuation
    ) {
        guard let content = envelope.message?.content else { return }

        for block in content where block.type == "tool_result" {
            guard let callID = nonEmpty(block.toolUseID) else { continue }

            let stateMatch = activeToolUses.first { $0.value.callID == callID }
            let state = stateMatch?.value
            if let index = stateMatch?.key {
                activeToolUses.removeValue(forKey: index)
            }

            let baseDetail = nonEmpty(state?.resolvedDetail)
            let resultDetail = nonEmpty(toolResultDetail(block: block, payload: envelope.toolUseResult))
            let detail = [baseDetail, resultDetail].compactMap { $0 }.joined(separator: " | ")

            continuation.yield(.toolCall(AgentToolCallUpdate(
                callID: callID,
                title: state?.title ?? "Tool",
                detail: detail,
                status: block.isError == true ? .failed : .completed
            )))
        }
    }

    nonisolated private static func toolInputDetail(fromPartialJSON partialJSON: String) -> String {
        let trimmed = partialJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if let data = trimmed.data(using: .utf8),
           let jsonObject = try? JSONSerialization.jsonObject(with: data),
           let jsonData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.sortedKeys]),
           let jsonString = String(data: jsonData, encoding: .utf8),
           let resolved = toolInputDetail(fromJSONString: jsonString) {
            return resolved
        }

        return singleLine(trimmed) ?? ""
    }

    nonisolated private static func toolInputDetail(fromJSONString jsonString: String) -> String? {
        guard let data = jsonString.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let preferredKeys = [
            "command",
            "description",
            "path",
            "file_path",
            "glob",
            "pattern",
            "query",
            "url",
            "prompt"
        ]

        for key in preferredKeys {
            if let value = jsonObject[key] as? String, let resolved = nonEmpty(singleLine(value)) {
                return resolved
            }
        }

        if let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            return prettyString
        }
        return nil
    }

    nonisolated private static func toolResultDetail(
        block: ClaudeContentBlock,
        payload: ClaudeToolUseResultPayload?
    ) -> String {
        var parts: [String] = []

        if let stdout = nonEmpty(singleLine(payload?.stdout)), !(payload?.noOutputExpected ?? false) {
            parts.append(stdout)
        }
        if let stderr = nonEmpty(singleLine(payload?.stderr)) {
            parts.append(stderr)
        }
        if payload?.interrupted == true {
            parts.append("interrupted")
        }
        if let content = nonEmpty(singleLine(block.content?.renderedInline)), !parts.contains(content) {
            parts.append(content)
        }

        return parts.joined(separator: " | ")
    }

    nonisolated private static func findClaudePath() -> String? {
        let pathsToCheck = [
            "\(NSHomeDirectory())/.local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude"
        ]

        for path in pathsToCheck {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for component in path.split(separator: ":") {
                let candidate = "\(component)/claude"
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }

        return nil
    }

    nonisolated private static func displayName(forTool rawName: String?) -> String {
        guard let rawName = nonEmpty(rawName) else { return "Tool" }
        let separated = rawName.replacingOccurrences(
            of: "([a-z0-9])([A-Z])",
            with: "$1 $2",
            options: .regularExpression
        )
        return separated
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    nonisolated private static func singleLine(_ text: String?) -> String? {
        text?
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func nonEmpty(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return text
    }
}
