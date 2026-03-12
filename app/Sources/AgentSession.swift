import Foundation

// MARK: - Persistent Claude CLI Agent

/// Manages a persistent Claude conversation via `--session-id` + `--resume`.
/// Each query spawns a `claude -p` process that resumes the same session.
/// Uses `--output-format stream-json` for structured response parsing.
/// The conversation context carries over between calls via session persistence.

final class AgentSession: ObservableObject {
    let model: String
    let label: String
    let sessionId: UUID

    @Published var isReady = false
    @Published var lastResponse: AgentResponse?

    private let claudePath = "/Users/arach/.local/bin/claude"
    private let queue = DispatchQueue(label: "agent-session", qos: .userInitiated)
    private var callCount = 0
    private var busy = false

    init(model: String, label: String) {
        self.model = model
        self.label = label
        self.sessionId = UUID()
    }

    // MARK: - Lifecycle

    func start() {
        guard FileManager.default.isExecutableFile(atPath: claudePath) else {
            DiagnosticLog.shared.warn("AgentSession[\(label)]: claude CLI not found")
            return
        }
        DiagnosticLog.shared.info("AgentSession[\(label)]: ready (model=\(model), session=\(sessionId.uuidString.prefix(8)))")
        DispatchQueue.main.async { self.isReady = true }
    }

    func stop() {
        DispatchQueue.main.async {
            self.isReady = false
            self.callCount = 0
        }
    }

    // MARK: - Communication

    /// Send a message and get a response via callback (main thread).
    func send(message: String, callback: @escaping (AgentResponse?) -> Void) {
        guard isReady else {
            callback(nil)
            return
        }
        guard !busy else {
            DiagnosticLog.shared.info("AgentSession[\(label)]: busy, skipping")
            callback(nil)
            return
        }

        queue.async { [weak self] in
            guard let self = self else { return }
            self.busy = true
            let response = self.call(prompt: message)
            self.busy = false

            DispatchQueue.main.async {
                self.lastResponse = response
                callback(response)
            }
        }
    }

    // MARK: - Claude CLI call

    private func call(prompt: String) -> AgentResponse? {
        let timer = DiagnosticLog.shared.startTimed("AgentSession[\(label)] call")

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: claudePath)

        var args = [
            "-p", prompt,
            "--model", model,
            "--output-format", "stream-json",
            "--session-id", sessionId.uuidString,
            "--max-budget-usd", "0.50",
            "--permission-mode", "plan",
            "--no-chrome",
        ]

        if callCount == 0 {
            // First call: include system prompt
            args.append(contentsOf: ["--system-prompt", buildSystemPrompt()])
        } else {
            // Subsequent calls: continue the existing session
            args.append(contentsOf: ["--continue", sessionId.uuidString])
        }

        proc.arguments = args

        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")
        proc.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        do {
            try proc.run()
        } catch {
            DiagnosticLog.shared.warn("AgentSession[\(label)]: launch failed — \(error)")
            DiagnosticLog.shared.finish(timer)
            return nil
        }

        proc.waitUntilExit()
        DiagnosticLog.shared.finish(timer)

        let output = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !stderr.isEmpty {
            DiagnosticLog.shared.info("AgentSession[\(label)] stderr: \(stderr.prefix(200))")
        }

        guard !output.isEmpty else {
            DiagnosticLog.shared.info("AgentSession[\(label)]: empty response")
            return nil
        }

        // Parse stream-json output — extract text from result line
        let text = parseStreamJSON(output)
        guard let text, !text.isEmpty else {
            DiagnosticLog.shared.info("AgentSession[\(label)]: no text in response")
            return nil
        }

        callCount += 1
        DiagnosticLog.shared.info("AgentSession[\(label)]: \(text.prefix(120))")
        return AgentResponse.parse(text: text)
    }

    /// Parse stream-json output lines, extract the final result text.
    private func parseStreamJSON(_ output: String) -> String? {
        let lines = output.components(separatedBy: "\n")

        // Look for the "result" line which has the complete text
        for line in lines.reversed() {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            let type = json["type"] as? String
            if type == "result", let result = json["result"] as? String {
                return result
            }
        }

        // Fallback: accumulate text from content blocks
        var text = ""
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            let type = json["type"] as? String
            if type == "assistant",
               let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                for block in content {
                    if block["type"] as? String == "text",
                       let t = block["text"] as? String {
                        text += t
                    }
                }
            }
        }

        return text.isEmpty ? nil : text
    }

    // MARK: - System prompt

    private func buildSystemPrompt() -> String {
        let windowSummary = DesktopModel.shared.windows.values
            .prefix(20)
            .map { "\($0.app): \($0.title)" }
            .joined(separator: "\n")

        let intentList = PhraseMatcher.shared.catalog()
        var intentSummary = ""
        if case .array(let intents) = intentList {
            intentSummary = intents.compactMap { intent -> String? in
                guard let name = intent["intent"]?.stringValue else { return nil }
                var slotNames: [String] = []
                if case .array(let slots) = intent["slots"] {
                    slotNames = slots.compactMap { $0["name"]?.stringValue }
                }
                let s = slotNames.isEmpty ? "" : "(\(slotNames.joined(separator: ", ")))"
                return "\(name)\(s)"
            }.joined(separator: ", ")
        }

        return """
        You are an advisor for Lattices, a macOS workspace manager. You run alongside voice commands, providing commentary and follow-up suggestions.

        Available commands: \(intentSummary)

        Current windows:
        \(windowSummary)

        For each user message, you receive a voice transcript and what command was matched.

        Respond with ONLY a JSON object:
        {"commentary": "short observation or null", "suggestion": {"label": "button text", "intent": "intent_name", "slots": {"key": "value"}} or null}

        Rules:
        - commentary: 1 sentence max. null if the matched command fully covers the request.
        - suggestion: a follow-up action. null if none needed.
        - Never suggest what was already executed.
        - Be terse and useful, not chatty.
        """
    }
}

// MARK: - Response types

struct AgentResponse {
    let commentary: String?
    let suggestion: AgentSuggestion?
    let raw: String

    struct AgentSuggestion {
        let label: String
        let intent: String
        let slots: [String: String]
    }

    static func parse(text: String) -> AgentResponse {
        guard let jsonStr = extractJSON(from: text),
              let data = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return AgentResponse(commentary: text, suggestion: nil, raw: text)
        }

        let commentary = json["commentary"] as? String

        var suggestion: AgentSuggestion?
        if let s = json["suggestion"] as? [String: Any],
           let label = s["label"] as? String,
           let intent = s["intent"] as? String {
            let slots = (s["slots"] as? [String: String]) ?? [:]
            suggestion = AgentSuggestion(label: label, intent: intent, slots: slots)
        }

        return AgentResponse(commentary: commentary, suggestion: suggestion, raw: text)
    }

    private static func extractJSON(from text: String) -> String? {
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = cleaned.firstIndex(of: "{"),
              let end = cleaned.lastIndex(of: "}") else { return nil }
        return String(cleaned[start...end])
    }
}

// MARK: - Agent Pool

/// Manages the Haiku (fast advisor) and Sonnet (deep thinker) agent sessions.
final class AgentPool {
    static let shared = AgentPool()

    let haiku = AgentSession(model: "haiku", label: "haiku")
    let sonnet = AgentSession(model: "sonnet", label: "sonnet")

    private init() {}

    func start() {
        DiagnosticLog.shared.info("AgentPool: starting haiku + sonnet sessions")
        haiku.start()
        // Stagger sonnet start
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            self.sonnet.start()
        }
    }

    func stop() {
        haiku.stop()
        sonnet.stop()
    }
}
