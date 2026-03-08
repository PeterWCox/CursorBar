import Foundation

// MARK: - Stream JSON event types (Cursor CLI stream-json format)
private struct StreamEvent: Decodable {
    let type: String?
    let subtype: String?
    let message: StreamMessage?
}

private struct StreamMessage: Decodable {
    let content: [StreamContent]?
}

private struct StreamContent: Decodable {
    let type: String?
    let text: String?
}

enum AgentRunnerError: Error {
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
                msg += "\n\nTry running 'agent login' in Terminal."
            }
            return msg
        }
    }
}

@MainActor
final class AgentRunner {
    static func stream(prompt: String, workspacePath: String, model: String? = nil) throws -> AsyncThrowingStream<String, Error> {
        guard let agentPath = findAgentPath() else {
            throw AgentRunnerError.agentNotFound
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: agentPath)
        var args = [
            "-f",
            "-p", prompt,
            "--workspace", workspacePath,
            "--output-format", "stream-json",
            "--stream-partial-output"
        ]
        if let model, !model.isEmpty {
            args += ["--model", model]
        }
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: workspacePath)
        
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
                            
                            if event.type == "assistant", let message = event.message, let content = message.content {
                                for item in content {
                                    if item.type == "text", let text = item.text, !text.isEmpty {
                                        continuation.yield(text)
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
                    continuation.finish(throwing: AgentRunnerError.processFailed(
                        exitCode: process.terminationStatus, stderr: stderrStr))
                } else {
                    continuation.finish()
                }
            }
        }
    }
    
    private static func findAgentPath() -> String? {
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
}
