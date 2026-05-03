import Foundation

// MARK: - Persistent Claude CLI Agent

/// Manages a persistent Claude conversation via `--session-id` + `--resume`.
/// Each query spawns a `claude -p` process that resumes the same session.
/// Uses `--output-format stream-json` for structured response parsing.
/// The conversation context carries over between calls via session persistence.

final class AgentSession: ObservableObject {
    let model: String
    let label: String
    private(set) var sessionId: UUID

    @Published var isReady = false
    @Published var lastResponse: AgentResponse?
    @Published var sessionStats: SessionStats = .empty

    struct SessionStats {
        let inputTokens: Int
        let outputTokens: Int
        let cacheReadTokens: Int
        let cacheCreationTokens: Int
        let contextWindow: Int
        let costUSD: Double
        let numTurns: Int

        static let empty = SessionStats(inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheCreationTokens: 0, contextWindow: 0, costUSD: 0, numTurns: 0)

        /// How full is the context? 0.0–1.0
        var contextUsage: Double {
            guard contextWindow > 0 else { return 0 }
            let totalInput = inputTokens + cacheReadTokens + cacheCreationTokens
            return Double(totalInput) / Double(contextWindow)
        }
    }

    private var claudePath: String?
    private let queue = DispatchQueue(label: "agent-session", qos: .userInitiated)
    private var callCount = 0
    private var busy = false

    /// Optional override for the system prompt. If set, used instead of the default advisor prompt.
    var customSystemPrompt: (() -> String)?

    init(model: String, label: String) {
        self.model = model
        self.label = label
        self.sessionId = UUID()
    }

    // MARK: - Lifecycle

    func start() {
        guard let resolved = Preferences.resolveClaudePath() else {
            DiagnosticLog.shared.warn("AgentSession[\(label)]: claude CLI not found")
            return
        }
        claudePath = resolved
        DiagnosticLog.shared.info("AgentSession[\(label)]: ready (model=\(model), claude=\(resolved), session=\(sessionId.uuidString.prefix(8)))")
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

        guard let claudePath = claudePath else { return nil }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: claudePath)

        var args = [
            "-p", prompt,
            "--model", model,
            "--output-format", "stream-json",
            "--max-budget-usd", String(format: "%.2f", Preferences.shared.advisorBudgetUSD),
            "--permission-mode", "plan",
            "--no-chrome",
        ]

        if callCount == 0 {
            // First call: create session with system prompt
            args.append(contentsOf: [
                "--session-id", sessionId.uuidString,
                "--system-prompt", customSystemPrompt?() ?? buildSystemPrompt(),
            ])
        } else {
            // Subsequent calls: resume existing session (context carries over)
            args.append(contentsOf: ["--resume", sessionId.uuidString])
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

        // Parse stream-json output — extract text and stats
        let parsed = parseStreamJSON(output)

        // Update session stats
        let stats = parsed.stats
        DispatchQueue.main.async {
            self.sessionStats = stats
        }

        if stats.contextWindow > 0 {
            let pct = Int(stats.contextUsage * 100)
            DiagnosticLog.shared.info("AgentSession[\(label)]: context \(pct)% (\(stats.inputTokens + stats.cacheReadTokens + stats.cacheCreationTokens)/\(stats.contextWindow)) cost=$\(String(format: "%.4f", stats.costUSD))")
        }

        guard let text = parsed.text, !text.isEmpty else {
            DiagnosticLog.shared.info("AgentSession[\(label)]: no text in response")
            return nil
        }

        // Auto-reset session if context usage > 75%
        if stats.contextUsage > 0.75 {
            DiagnosticLog.shared.warn("AgentSession[\(label)]: context at \(Int(stats.contextUsage * 100))%, resetting session")
            sessionId = UUID()  // Fresh session ID
            callCount = 0       // Next call will create a fresh session
        } else {
            callCount += 1
        }

        DiagnosticLog.shared.info("AgentSession[\(label)]: \(text.prefix(120))")
        return AgentResponse.parse(text: text)
    }

    struct ParsedResponse {
        let text: String?
        let stats: SessionStats
    }

    /// Parse stream-json output lines, extract text and session stats from the result line.
    private func parseStreamJSON(_ output: String) -> ParsedResponse {
        let lines = output.components(separatedBy: "\n")
        var resultText: String?
        var stats = SessionStats.empty

        for line in lines {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            let type = json["type"] as? String

            if type == "result" {
                resultText = json["result"] as? String
                let numTurns = json["num_turns"] as? Int ?? 0
                let costUSD = json["total_cost_usd"] as? Double ?? 0

                // Usage stats
                let usage = json["usage"] as? [String: Any] ?? [:]
                let inputTokens = usage["input_tokens"] as? Int ?? 0
                let outputTokens = usage["output_tokens"] as? Int ?? 0
                let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
                let cacheCreation = usage["cache_creation_input_tokens"] as? Int ?? 0

                // Context window from modelUsage
                var contextWindow = 0
                if let modelUsage = json["modelUsage"] as? [String: Any] {
                    for (_, v) in modelUsage {
                        if let m = v as? [String: Any], let cw = m["contextWindow"] as? Int {
                            contextWindow = cw
                        }
                    }
                }

                stats = SessionStats(
                    inputTokens: inputTokens,
                    outputTokens: outputTokens,
                    cacheReadTokens: cacheRead,
                    cacheCreationTokens: cacheCreation,
                    contextWindow: contextWindow,
                    costUSD: costUSD,
                    numTurns: numTurns
                )
            }

            // Fallback: accumulate text from assistant content blocks
            if resultText == nil, type == "assistant",
               let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                var text = ""
                for block in content {
                    if block["type"] as? String == "text",
                       let t = block["text"] as? String {
                        text += t
                    }
                }
                if !text.isEmpty { resultText = text }
            }
        }

        return ParsedResponse(text: resultText, stats: stats)
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
        - Suggestions MUST include all required slots. e.g. search requires {"query": "..."}.
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
