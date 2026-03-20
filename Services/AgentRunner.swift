import Foundation

enum AgentProviderID: String, Codable, CaseIterable, Identifiable {
    case cursor

    var id: String { rawValue }

    var displayName: String { "Cursor" }
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
    func createConversation() throws -> String
    func listModels() async throws -> [ModelOption]
    func stream(request: AgentStreamRequest) throws -> AsyncThrowingStream<AgentStreamChunk, Error>
}

enum AgentProviders {
    static let defaultProviderID: AgentProviderID = .cursor

    static func provider(for id: AgentProviderID) -> any AgentProvider {
        CursorAgentProvider.shared
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

// MARK: - Stream JSON event types (Cursor CLI stream-json format)
private struct StreamEvent: Decodable {
    let type: String?
    let subtype: String?
    let text: String?
    let message: StreamMessage?
    let callID: String?
    let toolCall: StreamToolCallPayload?

    private enum CodingKeys: String, CodingKey {
        case type
        case subtype
        case text
        case message
        case callID = "call_id"
        case toolCall = "tool_call"
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        guard let key = container.allKeys.first,
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
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

enum AgentStreamChunk {
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
    case notAuthenticated
    case processFailed(exitCode: Int32, stderr: String)
    
    var userMessage: String {
        switch self {
        case .agentNotFound:
            return "Cursor CLI not found. Install with: curl https://cursor.com/install -fsSL | bash\n\nEnsure ~/.local/bin is in your PATH."
        case .notAuthenticated:
            return "Not authenticated. Run 'agent login' in Terminal first."
        case .processFailed(let code, let stderr):
            var msg = "Agent exited with code \(code)."
            if !stderr.isEmpty {
                msg += "\n\n\(stderr)"
            }
            if stderr.contains("login") || stderr.contains("auth") || stderr.contains("authenticate") {
                msg += "\n\nTry signing in to Cursor CLI and then run the request again."
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
            var label = String(cleaned[dashRange.upperBound...])
                .replacingOccurrences(of: "  (current)", with: "")
                .replacingOccurrences(of: "  (default)", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard !id.isEmpty, !label.isEmpty else { continue }
            result.append(ModelOption(
                id: id,
                label: label,
                isPremium: AvailableModels.isPremiumModel(id: id)
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
        // Recent headless Cursor CLI builds reject `--model auto` even though
        // Auto still exists as a user-facing concept in Cursor's UI/docs.
        // Treat Auto as "use the CLI's current/default model" by omitting
        // the flag entirely.
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
                            // Skip malformed JSON lines
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
        guard event.type == "tool_call",
              let subtype = event.subtype,
              let callID = event.callID,
              let toolCall = event.toolCall else {
            return nil
        }

        let title = nonEmpty(toolCall.description) ?? toolCall.toolName
        let baseDetail = toolCallBaseDetail(for: toolCall)

        switch subtype {
        case "started":
            return AgentToolCallUpdate(
                callID: callID,
                title: title,
                detail: baseDetail,
                status: .started
            )
        case "completed":
            return AgentToolCallUpdate(
                callID: callID,
                title: title,
                detail: toolCallCompletionDetail(base: baseDetail, result: toolCall.result),
                status: toolCallStatus(for: toolCall.result)
            )
        default:
            return nil
        }
    }

    nonisolated private static func toolCallBaseDetail(for toolCall: StreamToolCallPayload) -> String {
        guard let args = toolCall.args else { return "" }

        let candidates = [
            nonEmpty(singleLine(args.command)),
            nonEmpty(args.path),
            nonEmpty(args.globPattern),
            nonEmpty(singleLine(args.pattern)),
            nonEmpty(singleLine(args.query)),
            nonEmpty(singleLine(args.url)),
            nonEmpty(args.workingDirectory),
            nonEmpty(singleLine(args.description))
        ]

        return candidates.compactMap { $0 }.first ?? ""
    }

    nonisolated private static func toolCallCompletionDetail(base: String, result: StreamToolCallResult?) -> String {
        var parts: [String] = []
        if let detail = nonEmpty(base) {
            parts.append(detail)
        }

        if let failure = result?.failure ?? result?.error {
            if let exitCode = failure.exitCode {
                parts.append("exit \(exitCode)")
            }
            if let message = nonEmpty(singleLine(failure.message ?? failure.stderr)) {
                parts.append(message)
            }
            return parts.joined(separator: " | ")
        }

        if let success = result?.success {
            if let exitCode = success.exitCode, exitCode != 0 {
                parts.append("exit \(exitCode)")
            }
            if let duration = toolCallDuration(from: success) {
                parts.append(duration)
            }
        }

        return parts.joined(separator: " | ")
    }

    nonisolated private static func toolCallStatus(for result: StreamToolCallResult?) -> AgentToolCallStatus {
        if result?.failure != nil || result?.error != nil {
            return .failed
        }

        if let exitCode = result?.success?.exitCode, exitCode != 0 {
            return .failed
        }

        return .completed
    }

    nonisolated private static func toolCallDuration(from success: StreamToolCallSuccess) -> String? {
        let durationMs = success.localExecutionTimeMs ?? success.executionTime ?? success.durationMs
        guard let durationMs else { return nil }

        if durationMs >= 1000 {
            return String(format: "%.1fs", Double(durationMs) / 1000)
        }

        return "\(durationMs)ms"
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
