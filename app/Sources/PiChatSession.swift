import AppKit
import Foundation

struct PiChatMessage: Identifiable, Equatable {
    enum Role {
        case system
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let text: String
    let timestamp: Date
}

struct PiAuthPrompt: Equatable {
    let message: String
    let placeholder: String?
    let allowEmpty: Bool
}

struct PiProvider: Identifiable, Equatable {
    enum AuthMode {
        case apiKey
        case oauth
    }

    let id: String
    let name: String
    let authMode: AuthMode
    let tokenLabel: String
    let tokenPlaceholder: String
    let helpText: String

    static let supported: [PiProvider] = [
        PiProvider(
            id: "github-copilot",
            name: "GitHub Copilot",
            authMode: .oauth,
            tokenLabel: "OAuth",
            tokenPlaceholder: "",
            helpText: "Uses Pi's device-code login. Personal access tokens are not accepted on this path."
        ),
        PiProvider(
            id: "openai-codex",
            name: "OpenAI Codex",
            authMode: .oauth,
            tokenLabel: "OAuth",
            tokenPlaceholder: "",
            helpText: "Uses Pi's browser login for ChatGPT Plus/Pro Codex access."
        ),
        PiProvider(
            id: "openai",
            name: "OpenAI",
            authMode: .apiKey,
            tokenLabel: "API key",
            tokenPlaceholder: "sk-...",
            helpText: "Stores an OpenAI API key in Pi's auth.json for this app and Pi CLI to reuse."
        ),
        PiProvider(
            id: "anthropic",
            name: "Anthropic",
            authMode: .apiKey,
            tokenLabel: "API key",
            tokenPlaceholder: "sk-ant-...",
            helpText: "Stores an Anthropic API key for Pi. OAuth-capable Anthropic flows can be added later."
        ),
        PiProvider(
            id: "google",
            name: "Google Gemini",
            authMode: .apiKey,
            tokenLabel: "API key",
            tokenPlaceholder: "AIza...",
            helpText: "Stores a Gemini API key for Pi's Google provider."
        ),
        PiProvider(
            id: "openrouter",
            name: "OpenRouter",
            authMode: .apiKey,
            tokenLabel: "API key",
            tokenPlaceholder: "sk-or-...",
            helpText: "Stores an OpenRouter API key for Pi."
        ),
        PiProvider(
            id: "groq",
            name: "Groq",
            authMode: .apiKey,
            tokenLabel: "API key",
            tokenPlaceholder: "gsk_...",
            helpText: "Stores a Groq API key for Pi."
        ),
        PiProvider(
            id: "xai",
            name: "xAI",
            authMode: .apiKey,
            tokenLabel: "API key",
            tokenPlaceholder: "xai-...",
            helpText: "Stores an xAI API key for Pi."
        ),
        PiProvider(
            id: "mistral",
            name: "Mistral",
            authMode: .apiKey,
            tokenLabel: "API key",
            tokenPlaceholder: "",
            helpText: "Stores a Mistral API key for Pi."
        ),
        PiProvider(
            id: "minimax",
            name: "MiniMax",
            authMode: .apiKey,
            tokenLabel: "API key",
            tokenPlaceholder: "",
            helpText: "Stores a MiniMax API key for Pi."
        ),
    ]

    static func provider(id: String) -> PiProvider {
        supported.first(where: { $0.id == id }) ?? supported[0]
    }
}

final class PiChatSession: ObservableObject {
    static let shared = PiChatSession()

    @Published private(set) var messages: [PiChatMessage] = [
        PiChatMessage(
            role: .system,
            text: "Pi dock ready. This is a lightweight in-app conversation surface, not a full terminal.",
            timestamp: Date()
        )
    ]
    @Published var draft: String = ""
    @Published var isVisible: Bool = false
    @Published private(set) var isSending: Bool = false
    @Published private(set) var statusText: String = "idle"
    @Published var dockHeight: CGFloat = 230 {
        didSet {
            dockHeight = Self.clampDockHeight(dockHeight)
            UserDefaults.standard.set(dockHeight, forKey: Self.dockHeightDefaultsKey)
        }
    }
    @Published var isAuthPanelVisible: Bool = false
    @Published var authProviderID: String = "minimax" {
        didSet {
            guard oldValue != authProviderID else { return }
            UserDefaults.standard.set(authProviderID, forKey: Self.selectedProviderDefaultsKey)
            authToken = ""
            authPromptInput = ""
            pendingAuthPrompt = nil
            authNoticeText = nil
            authErrorText = nil
        }
    }
    @Published var authToken: String = ""
    @Published var authPromptInput: String = ""
    @Published private(set) var isAuthenticating: Bool = false
    @Published private(set) var pendingAuthPrompt: PiAuthPrompt?
    @Published private(set) var authNoticeText: String?
    @Published private(set) var authErrorText: String?
    @Published private(set) var storedCredentialKinds: [String: String] = [:]

    private let queue = DispatchQueue(label: "pi-chat-session", qos: .userInitiated)
    private let sessionFileURL: URL
    private let authFileURL: URL
    private var authProcess: Process?
    private var authInputHandle: FileHandle?
    private var authStdoutBuffer: String = ""
    private var authStderrBuffer: String = ""

    private static let selectedProviderDefaultsKey = "PiChatSelectedProvider"
    private static let dockHeightDefaultsKey = "PiChatDockHeight"

    private init() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("Lattices/pi-chat", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        sessionFileURL = dir.appendingPathComponent("session.jsonl")
        authFileURL = Self.piAgentDirURL().appendingPathComponent("auth.json")

        if let savedProvider = UserDefaults.standard.string(forKey: Self.selectedProviderDefaultsKey),
           PiProvider.supported.contains(where: { $0.id == savedProvider }) {
            authProviderID = savedProvider
        }
        let savedDockHeight = UserDefaults.standard.double(forKey: Self.dockHeightDefaultsKey)
        if savedDockHeight > 0 {
            dockHeight = Self.clampDockHeight(savedDockHeight)
        }

        reloadAuthState()
    }

    var hasPiBinary: Bool {
        resolvePiPath() != nil
    }

    var providerOptions: [PiProvider] {
        PiProvider.supported
    }

    var currentProvider: PiProvider {
        PiProvider.provider(id: authProviderID)
    }

    var selectedCredentialSummary: String {
        guard let kind = storedCredentialKinds[authProviderID] else { return "not authenticated" }
        return kind == "oauth" ? "oauth saved" : "token saved"
    }

    var hasSelectedCredential: Bool {
        storedCredentialKinds[authProviderID] != nil
    }

    var canSubmitAuthPrompt: Bool {
        guard let prompt = pendingAuthPrompt else { return false }
        let value = authPromptInput.trimmingCharacters(in: .whitespacesAndNewlines)
        return prompt.allowEmpty || !value.isEmpty
    }

    func toggleVisibility() {
        isVisible.toggle()
    }

    func toggleAuthPanel() {
        isAuthPanelVisible.toggle()
        if isAuthPanelVisible {
            dockHeight = max(dockHeight, 300)
        }
    }

    func clearConversation() {
        try? FileManager.default.removeItem(at: sessionFileURL)
        messages = [
            PiChatMessage(
                role: .system,
                text: "Started a fresh Pi conversation.",
                timestamp: Date()
            )
        ]
        statusText = "idle"
    }

    func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        send(text)
    }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isSending else { return }

        messages.append(PiChatMessage(role: .user, text: trimmed, timestamp: Date()))

        guard let piPath = resolvePiPath() else {
            appendSystemMessage("Pi CLI not found. Install `pi` or add it to PATH.")
            statusText = "missing pi"
            return
        }

        let provider = currentProvider
        isSending = true
        statusText = "thinking..."

        queue.async { [weak self] in
            guard let self else { return }

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: piPath)
            var args = [
                "--provider", provider.id,
                "-p",
                "--session", self.sessionFileURL.path,
            ]

            if let extPath = Self.resolveExtensionPath() {
                args += ["-e", extPath]
            }

            args.append(trimmed)
            proc.arguments = args

            var env = ProcessInfo.processInfo.environment
            env.removeValue(forKey: "CLAUDECODE")
            if provider.id == "github-copilot", self.storedCredentialKinds[provider.id] == nil {
                env.removeValue(forKey: "COPILOT_GITHUB_TOKEN")
            }
            Self.sanitizeEnvironment(&env, for: provider.id, hasStoredCredential: self.storedCredentialKinds[provider.id] != nil)
            proc.environment = env

            let outPipe = Pipe()
            let errPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = errPipe

            let stdout: String
            let stderr: String
            let exitCode: Int32

            do {
                try proc.run()
                proc.waitUntilExit()
                stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                exitCode = proc.terminationStatus
            } catch {
                DispatchQueue.main.async {
                    self.isSending = false
                    self.statusText = "launch failed"
                    self.appendSystemMessage("Failed to launch Pi: \(error.localizedDescription)")
                }
                return
            }

            DispatchQueue.main.async {
                self.isSending = false

                if exitCode == 0, !stdout.isEmpty {
                    self.statusText = "idle"
                    self.messages.append(PiChatMessage(
                        role: .assistant,
                        text: stdout,
                        timestamp: Date()
                    ))
                    return
                }

                let message = !stderr.isEmpty ? stderr : (stdout.isEmpty ? "Pi returned no output." : stdout)
                self.statusText = "error"
                self.appendSystemMessage(message)
                if Self.looksLikeAuthError(message) {
                    self.isAuthPanelVisible = true
                }
            }
        }
    }

    func saveSelectedToken() {
        let token = authToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            authErrorText = "Enter a token before saving."
            return
        }

        do {
            try mutateAuthFile { auth in
                auth[authProviderID] = [
                    "type": "api_key",
                    "key": token,
                ]
            }
            authToken = ""
            authNoticeText = "Saved \(currentProvider.tokenLabel.lowercased()) for \(currentProvider.name)."
            authErrorText = nil
            reloadAuthState()
            appendSystemMessage("Saved \(currentProvider.name) credentials to Pi auth storage.")
        } catch {
            authErrorText = "Failed to save token: \(error.localizedDescription)"
        }
    }

    func removeSelectedCredential() {
        do {
            try mutateAuthFile { auth in
                auth.removeValue(forKey: authProviderID)
            }
            authNoticeText = "Removed saved credentials for \(currentProvider.name)."
            authErrorText = nil
            reloadAuthState()
            appendSystemMessage("Removed saved \(currentProvider.name) credentials from Pi auth storage.")
        } catch {
            authErrorText = "Failed to remove credentials: \(error.localizedDescription)"
        }
    }

    func startSelectedAuthFlow() {
        if currentProvider.authMode == .apiKey {
            saveSelectedToken()
            return
        }

        startOAuthLogin(for: currentProvider)
    }

    func submitAuthPrompt() {
        guard let prompt = pendingAuthPrompt else { return }
        let value = authPromptInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard prompt.allowEmpty || !value.isEmpty else { return }

        guard let handle = authInputHandle else {
            authErrorText = "Pi auth input pipe is no longer available."
            return
        }

        let line = value + "\n"
        if let data = line.data(using: .utf8) {
            do {
                try handle.write(contentsOf: data)
                authPromptInput = ""
                pendingAuthPrompt = nil
            } catch {
                authErrorText = "Failed to send auth input: \(error.localizedDescription)"
            }
        }
    }

    func cancelAuthFlow() {
        authProcess?.terminate()
        cleanupAuthProcess()
        isAuthenticating = false
        authNoticeText = "Cancelled auth flow."
    }

    private func startOAuthLogin(for provider: PiProvider) {
        guard !isAuthenticating else {
            authErrorText = "An auth flow is already running."
            return
        }

        guard let nodePath = resolveNodePath() else {
            authErrorText = "Node.js is required for Pi OAuth login."
            return
        }

        guard let oauthModuleURL = resolveOAuthModuleURL() else {
            authErrorText = "Couldn't locate Pi's OAuth module next to the installed `pi` CLI."
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: nodePath)
        proc.arguments = [
            "--input-type=module",
            "--eval",
            Self.oauthDriverScript,
            provider.id,
            oauthModuleURL.absoluteString,
        ]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        authStdoutBuffer = ""
        authStderrBuffer = ""
        authPromptInput = ""
        pendingAuthPrompt = nil
        authNoticeText = "Starting \(provider.name) login..."
        authErrorText = nil
        isAuthenticating = true

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.handleAuthStdout(text)
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.handleAuthStderr(text)
        }

        proc.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                self?.handleAuthProcessExit(status: process.terminationStatus)
            }
        }

        do {
            try proc.run()
            authProcess = proc
            authInputHandle = stdinPipe.fileHandleForWriting
            appendSystemMessage("Started \(provider.name) auth flow.")
        } catch {
            cleanupAuthProcess()
            isAuthenticating = false
            authErrorText = "Failed to launch auth flow: \(error.localizedDescription)"
        }
    }

    private func handleAuthStdout(_ text: String) {
        DispatchQueue.main.async {
            self.authStdoutBuffer.append(text)
            self.consumeBufferedAuthLines(buffer: &self.authStdoutBuffer, handler: self.handleAuthEventLine(_:))
        }
    }

    private func handleAuthStderr(_ text: String) {
        DispatchQueue.main.async {
            self.authStderrBuffer.append(text)
            self.consumeBufferedAuthLines(buffer: &self.authStderrBuffer) { line in
                guard !line.isEmpty else { return }
                self.authNoticeText = line
            }
        }
    }

    private func consumeBufferedAuthLines(buffer: inout String, handler: (String) -> Void) {
        while let range = buffer.range(of: "\n") {
            let line = String(buffer[..<range.lowerBound])
            buffer.removeSubrange(buffer.startIndex...range.lowerBound)
            handler(line.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func handleAuthEventLine(_ line: String) {
        guard !line.isEmpty else { return }
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            authNoticeText = line
            return
        }

        switch type {
        case "prompt":
            pendingAuthPrompt = PiAuthPrompt(
                message: json["message"] as? String ?? "Continue",
                placeholder: json["placeholder"] as? String,
                allowEmpty: json["allowEmpty"] as? Bool ?? false
            )
            authNoticeText = pendingAuthPrompt?.message

        case "auth":
            let urlString = json["url"] as? String ?? ""
            let instructions = json["instructions"] as? String
            authNoticeText = instructions ?? "Continue in your browser."
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
            if let instructions, !instructions.isEmpty {
                appendSystemMessage("Pi auth: \(instructions)")
            }

        case "progress":
            authNoticeText = json["message"] as? String ?? "Working..."

        case "success":
            guard var credentials = json["credentials"] as? [String: Any] else {
                authErrorText = "Pi auth completed but returned no credentials."
                return
            }
            credentials["type"] = "oauth"
            do {
                try mutateAuthFile { auth in
                    auth[authProviderID] = credentials
                }
                reloadAuthState()
                authNoticeText = "Saved OAuth credentials for \(currentProvider.name)."
                authErrorText = nil
                appendSystemMessage("Saved \(currentProvider.name) OAuth credentials to Pi auth storage.")
            } catch {
                authErrorText = "Failed to save OAuth credentials: \(error.localizedDescription)"
            }

        case "error":
            let message = json["message"] as? String ?? "Unknown Pi auth error."
            authErrorText = message
            appendSystemMessage("Pi auth failed: \(message)")

        default:
            authNoticeText = line
        }
    }

    private func handleAuthProcessExit(status: Int32) {
        let hadExplicitError = authErrorText != nil
        cleanupAuthProcess()
        isAuthenticating = false
        pendingAuthPrompt = nil

        if status == 0 {
            if !hadExplicitError {
                authNoticeText = authNoticeText ?? "Auth flow finished."
            }
        } else if !hadExplicitError {
            authErrorText = "Auth flow exited with status \(status)."
        }
    }

    private func cleanupAuthProcess() {
        authProcess?.standardInput = nil
        if let output = authProcess?.standardOutput as? Pipe {
            output.fileHandleForReading.readabilityHandler = nil
        }
        if let error = authProcess?.standardError as? Pipe {
            error.fileHandleForReading.readabilityHandler = nil
        }
        authInputHandle = nil
        authProcess = nil
    }

    private func appendSystemMessage(_ text: String) {
        messages.append(PiChatMessage(role: .system, text: text, timestamp: Date()))
    }

    private func reloadAuthState() {
        let auth = loadAuthFile()
        var kinds: [String: String] = [:]

        for (providerID, rawValue) in auth {
            guard let record = rawValue as? [String: Any],
                  let type = record["type"] as? String else { continue }
            kinds[providerID] = type
        }

        storedCredentialKinds = kinds
    }

    private func loadAuthFile() -> [String: Any] {
        guard let data = try? Data(contentsOf: authFileURL), !data.isEmpty else { return [:] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json
    }

    private func mutateAuthFile(_ mutate: (inout [String: Any]) -> Void) throws {
        let fm = FileManager.default
        let dir = authFileURL.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        var auth = loadAuthFile()
        mutate(&auth)

        let data = try JSONSerialization.data(withJSONObject: auth, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: authFileURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: authFileURL.path)
    }

    private func resolvePiPath() -> String? {
        resolveCommandPath(
            named: "pi",
            candidates: [
                "/opt/homebrew/bin/pi",
                "/usr/local/bin/pi",
                NSHomeDirectory() + "/.local/bin/pi",
            ]
        )
    }

    private func resolveNodePath() -> String? {
        resolveCommandPath(
            named: "node",
            candidates: [
                "/opt/homebrew/bin/node",
                "/usr/local/bin/node",
                "/usr/bin/node",
            ]
        )
    }

    private func resolveCommandPath(named command: String, candidates: [String]) -> String? {
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", "which \(command) 2>/dev/null"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return output.isEmpty ? nil : output
    }

    static func resolveExtensionPath() -> String? {
        let fm = FileManager.default
        let candidates = [
            NSHomeDirectory() + "/.lattices/pi-extension/lattices.ts",
            Bundle.main.bundlePath + "/../pi-extension/lattices.ts",
        ]
        for path in candidates where fm.fileExists(atPath: path) {
            return path
        }
        return nil
    }

    private func resolveOAuthModuleURL() -> URL? {
        guard let packageRoot = resolvePiPackageRoot() else { return nil }
        let moduleURL = packageRoot
            .appendingPathComponent("node_modules")
            .appendingPathComponent("@mariozechner")
            .appendingPathComponent("pi-ai")
            .appendingPathComponent("dist")
            .appendingPathComponent("utils")
            .appendingPathComponent("oauth")
            .appendingPathComponent("index.js")
        return FileManager.default.fileExists(atPath: moduleURL.path) ? moduleURL : nil
    }

    private func resolvePiPackageRoot() -> URL? {
        guard let piPath = resolvePiPath() else { return nil }
        let resolved = URL(fileURLWithPath: piPath).resolvingSymlinksInPath()
        guard resolved.lastPathComponent == "cli.js",
              resolved.deletingLastPathComponent().lastPathComponent == "dist" else { return nil }
        return resolved.deletingLastPathComponent().deletingLastPathComponent()
    }

    private static func piAgentDirURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["PI_CODING_AGENT_DIR"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".pi", isDirectory: true)
            .appendingPathComponent("agent", isDirectory: true)
    }

    private static func looksLikeAuthError(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        return lowercased.contains("api key")
            || lowercased.contains("oauth")
            || lowercased.contains("token")
            || lowercased.contains("authentication")
            || lowercased.contains("unauthorized")
            || lowercased.contains("bad request")
    }

    private static func clampDockHeight(_ height: CGFloat) -> CGFloat {
        min(max(height, 170), 520)
    }

    private static func sanitizeEnvironment(_ env: inout [String: String], for providerID: String, hasStoredCredential: Bool) {
        let providerEnvVars: [String: [String]] = [
            "github-copilot": ["COPILOT_GITHUB_TOKEN", "GH_TOKEN", "GITHUB_TOKEN"],
            "anthropic": ["ANTHROPIC_API_KEY", "ANTHROPIC_OAUTH_TOKEN"],
            "openai": ["OPENAI_API_KEY"],
            "google": ["GEMINI_API_KEY"],
            "groq": ["GROQ_API_KEY"],
            "xai": ["XAI_API_KEY"],
            "openrouter": ["OPENROUTER_API_KEY"],
            "mistral": ["MISTRAL_API_KEY"],
            "minimax": ["MINIMAX_API_KEY"],
            "openai-codex": [],
        ]

        for (id, keys) in providerEnvVars where id != providerID {
            for key in keys {
                env.removeValue(forKey: key)
            }
        }

        if providerID == "github-copilot", !hasStoredCredential {
            env.removeValue(forKey: "COPILOT_GITHUB_TOKEN")
            env.removeValue(forKey: "GH_TOKEN")
            env.removeValue(forKey: "GITHUB_TOKEN")
        }
    }

    private static let oauthDriverScript = #"""
import readline from 'node:readline';

const providerId = process.argv[1];
const oauthModuleUrl = process.argv[2];
const { getOAuthProvider } = await import(oauthModuleUrl);

const provider = getOAuthProvider(providerId);
if (!provider) {
  process.stdout.write(JSON.stringify({ type: 'error', message: `Unknown OAuth provider: ${providerId}` }) + '\n');
  process.exit(1);
}

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stderr,
  terminal: false,
});

function emit(event) {
  process.stdout.write(JSON.stringify(event) + '\n');
}

function readLine() {
  return new Promise((resolve) => {
    rl.once('line', (line) => resolve(line));
  });
}

try {
  const credentials = await provider.login({
    onAuth: (info) => emit({
      type: 'auth',
      url: info.url,
      instructions: info.instructions ?? null,
    }),
    onPrompt: async (prompt) => {
      emit({
        type: 'prompt',
        message: prompt.message,
        placeholder: prompt.placeholder ?? null,
        allowEmpty: Boolean(prompt.allowEmpty),
      });
      const input = await readLine();
      return typeof input === 'string' ? input : '';
    },
    onProgress: (message) => emit({
      type: 'progress',
      message,
    }),
  });

  emit({
    type: 'success',
    credentials,
  });
  rl.close();
  process.exit(0);
} catch (error) {
  emit({
    type: 'error',
    message: error instanceof Error ? error.message : String(error),
  });
  rl.close();
  process.exit(1);
}
"""#
}
