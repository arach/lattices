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
    private static let installCommand = "npm install -g @mariozechner/pi-coding-agent@latest"

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
    @Published var authProviderID: String = "openai-codex" {
        didSet {
            guard oldValue != authProviderID else { return }
            if isAuthenticating {
                cancelAuthFlow(silently: true)
            }
            UserDefaults.standard.set(authProviderID, forKey: Self.selectedProviderDefaultsKey)
            authToken = ""
            authPromptInput = ""
            pendingAuthPrompt = nil
            authNoticeText = nil
            authErrorText = nil
            latestAuthURL = nil
            latestAuthInstructions = nil
            authVerificationCodeCopied = false
            lastCopiedAuthVerificationCode = nil
            prepareForDisplay()
        }
    }
    @Published var authToken: String = ""
    @Published var authPromptInput: String = ""
    @Published private(set) var isAuthenticating: Bool = false
    @Published private(set) var authenticatingProviderID: String?
    @Published private(set) var pendingAuthPrompt: PiAuthPrompt?
    @Published private(set) var authNoticeText: String?
    @Published private(set) var authErrorText: String?
    @Published private(set) var storedCredentialKinds: [String: String] = [:]
    @Published private(set) var piBinaryPath: String?
    @Published private(set) var latestAuthURL: URL?
    @Published private(set) var latestAuthInstructions: String?
    @Published private(set) var authVerificationCodeCopied: Bool = false

    private let queue = DispatchQueue(label: "pi-chat-session", qos: .userInitiated)
    private let sessionFileURL: URL
    private let authFileURL: URL
    private var authProcess: Process?
    private var authProcessIdentifier: Int32?
    private var authInputHandle: FileHandle?
    private var authStdoutPipe: Pipe?
    private var authStderrPipe: Pipe?
    private var authStdoutBuffer: String = ""
    private var authStderrBuffer: String = ""
    private var nodeBinaryPath: String?
    private var lastCopiedAuthVerificationCode: String?

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
        refreshBinaryAvailability()
        cleanupLingeringAuthHelpers()
    }

    var hasPiBinary: Bool {
        piBinaryPath != nil
    }

    var piInstallCommand: String {
        Self.installCommand
    }

    var providerOptions: [PiProvider] {
        PiProvider.supported
    }

    var currentProvider: PiProvider {
        PiProvider.provider(id: authProviderID)
    }

    var authenticatingProvider: PiProvider? {
        guard let authenticatingProviderID else { return nil }
        return PiProvider.provider(id: authenticatingProviderID)
    }

    var needsProviderSetup: Bool {
        hasPiBinary && !hasSelectedCredential
    }

    var hasConversationHistory: Bool {
        messages.contains { $0.role != .system }
    }

    var selectedCredentialSummary: String {
        guard let kind = storedCredentialKinds[authProviderID] else { return "not authenticated" }
        return kind == "oauth" ? "oauth saved" : "token saved"
    }

    var hasSelectedCredential: Bool {
        storedCredentialKinds[authProviderID] != nil
    }

    var authVerificationCode: String? {
        guard let latestAuthInstructions else { return nil }
        let prefix = "Enter code:"
        guard let range = latestAuthInstructions.range(of: prefix, options: [.caseInsensitive]) else { return nil }
        let value = latestAuthInstructions[range.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var authStepLabel: String {
        if pendingAuthPrompt != nil || latestAuthURL == nil {
            return "STEP 1"
        }
        return "STEP 2"
    }

    var authStepTitle: String {
        if pendingAuthPrompt != nil {
            return "Answer one quick question"
        }
        if latestAuthURL == nil {
            return "Opening your sign-in page"
        }
        if authVerificationCode != nil {
            return authVerificationCodeCopied
                ? "Paste the copied code in your browser"
                : "Copy the code, then paste it in your browser"
        }
        return "Finish sign-in in your browser"
    }

    var authStepDescription: String {
        if let prompt = pendingAuthPrompt {
            return prompt.message
        }
        if latestAuthURL == nil {
            return "Stay here for a second while Pi prepares the browser step."
        }
        if authVerificationCode != nil {
            return authVerificationCodeCopied
                ? "The code is already on your clipboard. Switch to the browser page and paste it."
                : "Use the code below on the browser page, or copy it here first."
        }
        return "Your browser sign-in page is ready. Finish the provider flow there."
    }

    var authStepShortText: String {
        if pendingAuthPrompt != nil {
            return "Answer one quick question"
        }
        if latestAuthURL == nil {
            return "Opening browser sign-in"
        }
        if authVerificationCode != nil {
            return authVerificationCodeCopied ? "Paste the copied code" : "Copy the code and paste it"
        }
        return "Finish sign-in in browser"
    }

    var setupStatusSummary: String {
        if !hasPiBinary {
            return "Install Pi to enable the assistant"
        }
        if isAuthenticating {
            return authStepShortText
        }
        if needsProviderSetup {
            return "Next: connect \(currentProvider.name)"
        }
        return currentProvider.name
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
        if needsProviderSetup || isAuthenticating {
            isAuthPanelVisible = true
            dockHeight = max(dockHeight, 300)
            return
        }
        isAuthPanelVisible.toggle()
        if isAuthPanelVisible {
            dockHeight = max(dockHeight, 300)
        }
    }

    func clearConversation() {
        try? FileManager.default.removeItem(at: sessionFileURL)
        messages = []
        prepareForDisplay()
    }

    func prepareForDisplay() {
        reconcileAuthState()
        refreshBinaryAvailability()

        if isAuthenticating {
            isAuthPanelVisible = true
            statusText = "connecting..."
        } else if needsProviderSetup {
            isAuthPanelVisible = true
            statusText = "setup ai"
        } else if hasPiBinary && (statusText == "setup ai" || statusText == "missing pi") {
            statusText = "idle"
        }

        syncStructuredWelcomeMessage()
    }

    func refreshBinaryAvailability() {
        piBinaryPath = resolvePiPath()
        nodeBinaryPath = resolveNodePath()

        if piBinaryPath == nil {
            if statusText == "idle" || statusText == "missing pi" {
                statusText = "missing pi"
            }
        } else if !hasSelectedCredential {
            if statusText == "idle" || statusText == "setup ai" {
                statusText = "setup ai"
            }
        } else if statusText == "missing pi" {
            statusText = "idle"
        }
    }

    func copyPiInstallCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(piInstallCommand, forType: .string)
        appendSystemMessage("Copied the Pi install command to the clipboard.")
    }

    func installPiInTerminal() {
        Preferences.shared.terminal.launch(command: piInstallCommand, in: NSHomeDirectory())
        appendSystemMessage("Opened \(Preferences.shared.terminal.rawValue) and started the Pi install.")
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

        refreshBinaryAvailability()

        guard let piPath = piBinaryPath else {
            prepareForDisplay()
            statusText = "missing pi"
            return
        }

        guard !needsProviderSetup else {
            prepareForDisplay()
            return
        }

        messages.append(PiChatMessage(role: .user, text: trimmed, timestamp: Date()))

        let provider = currentProvider
        isSending = true
        statusText = "thinking..."

        queue.async { [weak self] in
            guard let self else { return }

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: piPath)
            proc.arguments = [
                "--provider", provider.id,
                "-p",
                "--session", self.sessionFileURL.path,
                trimmed,
            ]

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
                if let friendly = self.friendlyAuthFailureMessage(for: message) {
                    self.statusText = "setup ai"
                    self.authErrorText = friendly
                    self.isAuthPanelVisible = true
                    self.syncStructuredWelcomeMessage()
                    return
                }
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
            isAuthPanelVisible = false
            prepareForDisplay()
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
            prepareForDisplay()
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
        submitAuthPromptValue(value)
    }

    private func submitAuthPromptValue(_ value: String) {
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

    func reopenLatestAuthURL() {
        guard let latestAuthURL else {
            authNoticeText = "Still preparing the browser sign-in link..."
            return
        }

        autoCopyAuthVerificationCodeIfNeeded()
        NSWorkspace.shared.open(latestAuthURL)
        authNoticeText = authVerificationCode != nil
            ? "Reopened the sign-in page. Paste the copied code there."
            : "Reopened \(authenticatingProvider?.name ?? currentProvider.name) sign-in in your browser."
    }

    func copyAuthVerificationCode() {
        copyAuthVerificationCode(silently: false)
    }

    private func copyAuthVerificationCode(silently: Bool) {
        guard let authVerificationCode else {
            authNoticeText = "No sign-in code is ready yet."
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(authVerificationCode, forType: .string)
        authVerificationCodeCopied = true
        lastCopiedAuthVerificationCode = authVerificationCode
        if !silently {
            authNoticeText = "Copied the sign-in code. Paste it into the browser page."
        }
    }

    private func autoCopyAuthVerificationCodeIfNeeded() {
        guard let authVerificationCode else { return }
        guard !authVerificationCodeCopied || lastCopiedAuthVerificationCode != authVerificationCode else { return }
        copyAuthVerificationCode(silently: true)
    }

    func cancelAuthFlow(silently: Bool = false) {
        let process = authProcess
        cleanupAuthProcess()
        terminateProcess(process, escalateAfter: 0.8)
        isAuthenticating = false
        statusText = hasPiBinary && !hasSelectedCredential ? "setup ai" : "idle"
        if !silently {
            authNoticeText = "Cancelled auth flow."
        }
    }

    private func startOAuthLogin(for provider: PiProvider) {
        reconcileAuthState()
        cleanupLingeringAuthHelpers()

        if isAuthenticating {
            cancelAuthFlow(silently: true)
        }

        refreshBinaryAvailability()

        guard hasPiBinary else {
            authErrorText = "Install Pi before starting auth."
            return
        }

        guard let nodePath = nodeBinaryPath else {
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
        latestAuthURL = nil
        latestAuthInstructions = nil
        authVerificationCodeCopied = false
        lastCopiedAuthVerificationCode = nil
        authNoticeText = "Preparing \(provider.name) sign-in..."
        authErrorText = nil
        isAuthenticating = true
        authenticatingProviderID = provider.id
        statusText = "connecting..."

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
                self?.handleAuthProcessExit(processID: process.processIdentifier, status: process.terminationStatus)
            }
        }

        do {
            try proc.run()
            authProcess = proc
            authProcessIdentifier = proc.processIdentifier
            authInputHandle = stdinPipe.fileHandleForWriting
            authStdoutPipe = stdoutPipe
            authStderrPipe = stderrPipe
            recordAuthHelperProcess(proc.processIdentifier)
            appendSystemMessage("Started \(provider.name) auth flow.")
        } catch {
            cleanupAuthProcess()
            isAuthenticating = false
            statusText = hasPiBinary && !hasSelectedCredential ? "setup ai" : "idle"
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
            let prompt = PiAuthPrompt(
                message: json["message"] as? String ?? "Continue",
                placeholder: json["placeholder"] as? String,
                allowEmpty: json["allowEmpty"] as? Bool ?? false
            )
            pendingAuthPrompt = prompt
            authNoticeText = prompt.message
            if shouldAutoSubmitPrompt(prompt) {
                authNoticeText = "Using github.com. If you need GitHub Enterprise, cancel and enter your domain instead."
                submitAuthPromptValue("")
            }

        case "auth":
            let urlString = json["url"] as? String ?? ""
            let instructions = json["instructions"] as? String
            latestAuthURL = URL(string: urlString)
            latestAuthInstructions = instructions
            if authVerificationCode != lastCopiedAuthVerificationCode {
                authVerificationCodeCopied = false
            }
            autoCopyAuthVerificationCodeIfNeeded()
            authNoticeText = authVerificationCode != nil
                ? "The sign-in code is copied. Paste it into the browser page."
                : "Your browser sign-in page is ready."
            if let url = latestAuthURL {
                NSWorkspace.shared.open(url)
            }
            if authVerificationCode != nil {
                appendSystemMessage("Pi auth is ready. The sign-in code is copied, and you can reopen the browser page here if needed.")
            } else if let instructions, !instructions.isEmpty {
                appendSystemMessage("Pi auth: \(instructions) If nothing opened, use OPEN AGAIN.")
            } else {
                appendSystemMessage("Pi auth is ready in your browser. If nothing opened, use OPEN AGAIN.")
            }

        case "progress":
            authNoticeText = json["message"] as? String ?? "Working..."

        case "success":
            guard var credentials = json["credentials"] as? [String: Any] else {
                authErrorText = "Pi auth completed but returned no credentials."
                return
            }
            let providerID = authenticatingProviderID ?? authProviderID
            let provider = PiProvider.provider(id: providerID)
            credentials["type"] = "oauth"
            do {
                try mutateAuthFile { auth in
                    auth[providerID] = credentials
                }
                reloadAuthState()
                authNoticeText = "Saved OAuth credentials for \(provider.name)."
                authErrorText = nil
                appendSystemMessage("Saved \(provider.name) OAuth credentials to Pi auth storage.")
                isAuthPanelVisible = false
                prepareForDisplay()
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

    private func handleAuthProcessExit(processID: Int32, status: Int32) {
        guard authProcessIdentifier == processID else { return }

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

        if status == 0, hasSelectedCredential {
            statusText = "idle"
        } else if hasPiBinary && !hasSelectedCredential {
            statusText = "setup ai"
        }
    }

    private func cleanupAuthProcess() {
        authProcess?.terminationHandler = nil
        authStdoutPipe?.fileHandleForReading.readabilityHandler = nil
        authStderrPipe?.fileHandleForReading.readabilityHandler = nil
        try? authInputHandle?.close()
        authInputHandle = nil
        authStdoutPipe = nil
        authStderrPipe = nil
        authStdoutBuffer = ""
        authStderrBuffer = ""
        latestAuthURL = nil
        latestAuthInstructions = nil
        authVerificationCodeCopied = false
        lastCopiedAuthVerificationCode = nil
        authProcess = nil
        authProcessIdentifier = nil
        authenticatingProviderID = nil
        clearRecordedAuthHelperProcess()
    }

    private func appendSystemMessage(_ text: String) {
        messages.append(PiChatMessage(role: .system, text: text, timestamp: Date()))
    }

    private func syncStructuredWelcomeMessage() {
        guard !hasConversationHistory else { return }
        messages = [
            PiChatMessage(
                role: .system,
                text: structuredWelcomeMessage(),
                timestamp: Date()
            )
        ]
    }

    private func structuredWelcomeMessage() -> String {
        if !hasPiBinary {
            return """
            Welcome to Pi Workspace.

            Pi powers the in-app assistant. Install it first, then come back here and refresh.

            Install command:
            \(piInstallCommand)
            """
        }

        if isAuthenticating {
            return """
            Welcome to Pi Workspace.

            \(authStepTitle)

            \(authStepDescription)
            """
        }

        if needsProviderSetup {
            return """
            Welcome to Pi Workspace.

            Next step: connect \(currentProvider.name).

            The setup panel above is open. Once you finish that one step, the chat box unlocks automatically.
            """
        }

        return """
        Welcome to Pi Workspace.

        You're connected with \(currentProvider.name). Ask for code help, planning, debugging, or a second opinion.
        """
    }

    private func friendlyAuthFailureMessage(for message: String) -> String? {
        let lowercased = message.lowercased()
        let authHints = [
            "use /login",
            "set an api key environment variable",
            "authentication",
            "unauthorized",
            "api key",
            "oauth",
            "token",
        ]

        guard authHints.contains(where: lowercased.contains) else { return nil }

        if currentProvider.authMode == .oauth {
            return "This provider is not connected yet. Use the setup panel to sign in with \(currentProvider.name), then come back and send your first prompt."
        }

        return "This provider still needs an API key. Paste your \(currentProvider.tokenLabel.lowercased()) into the setup panel above, save it, and then try again."
    }

    private func shouldAutoSubmitPrompt(_ prompt: PiAuthPrompt) -> Bool {
        guard authenticatingProviderID == "github-copilot" else { return false }
        guard prompt.allowEmpty else { return false }

        let message = prompt.message.lowercased()
        return message.contains("github enterprise url")
            || message.contains("github enterprise")
            || message.contains("blank for github.com")
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

    private func reconcileAuthState() {
        guard isAuthenticating else { return }

        if let authProcess, authProcess.isRunning {
            return
        }

        cleanupAuthProcess()
        isAuthenticating = false
        pendingAuthPrompt = nil
        if hasPiBinary && !hasSelectedCredential {
            statusText = "setup ai"
        }
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
                NSHomeDirectory() + "/.bun/bin/pi",
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
                NSHomeDirectory() + "/.local/bin/node",
            ]
        )
    }

    private func resolveCommandPath(named command: String, candidates: [String]) -> String? {
        var orderedCandidates: [String] = []
        var seen: Set<String> = []

        for rawPath in candidates + managedInstallCandidates(for: command) {
            let path = (rawPath as NSString).expandingTildeInPath
            guard !path.isEmpty else { continue }
            guard seen.insert(path).inserted else { continue }
            orderedCandidates.append(path)
        }

        for path in orderedCandidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        let lookups = [
            ProcessQuery.shell(["/usr/bin/which", command]),
            ProcessQuery.shell(["/bin/sh", "-lc", "command -v \(command) 2>/dev/null"]),
            ProcessQuery.shell(["/bin/zsh", "-lc", "command -v \(command) 2>/dev/null"]),
        ]

        for output in lookups {
            let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
    }

    private func managedInstallCandidates(for command: String) -> [String] {
        let home = NSHomeDirectory()
        var candidates = [
            "\(home)/.bun/bin/\(command)",
            "\(home)/.npm-global/bin/\(command)",
            "\(home)/Library/pnpm/\(command)",
            "\(home)/.local/share/mise/shims/\(command)",
        ]

        let fnmRoot = URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("share", isDirectory: true)
            .appendingPathComponent("fnm", isDirectory: true)
            .appendingPathComponent("node-versions", isDirectory: true)

        if let installs = try? FileManager.default.contentsOfDirectory(
            at: fnmRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            let sortedInstalls = installs.sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending
            }

            for install in sortedInstalls {
                candidates.append(
                    install
                        .appendingPathComponent("installation", isDirectory: true)
                        .appendingPathComponent("bin", isDirectory: true)
                        .appendingPathComponent(command)
                        .path
                )
            }
        }

        return candidates
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

    private func recordAuthHelperProcess(_ pid: Int32) {
        let payload: [String: Any] = [
            "pid": Int(pid),
            "recordedAt": Date().timeIntervalSince1970,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        try? data.write(to: authRuntimeURL, options: .atomic)
    }

    private func clearRecordedAuthHelperProcess() {
        try? FileManager.default.removeItem(at: authRuntimeURL)
    }

    private func cleanupLingeringAuthHelpers() {
        let fm = FileManager.default

        if let data = try? Data(contentsOf: authRuntimeURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let pid = json["pid"] as? Int {
            terminateRecordedAuthHelper(pid)
            try? fm.removeItem(at: authRuntimeURL)
        }

        let currentPID = Int(ProcessInfo.processInfo.processIdentifier)
        for entry in ProcessQuery.snapshot().values where Self.looksLikePiOAuthHelper(entry.args) {
            guard entry.pid != currentPID else { continue }
            guard authProcess?.processIdentifier != Int32(entry.pid) else { continue }
            terminateRecordedAuthHelper(entry.pid)
        }
    }

    private func terminateRecordedAuthHelper(_ pid: Int) {
        guard pid > 1 else { return }
        guard kill(Int32(pid), 0) == 0 else { return }

        let args = ProcessQuery.shell(["/bin/ps", "-p", "\(pid)", "-o", "args="])
        guard Self.looksLikePiOAuthHelper(args) else { return }

        _ = kill(Int32(pid), SIGTERM)
        let deadline = Date().addingTimeInterval(1.0)
        while Date() < deadline {
            if kill(Int32(pid), 0) != 0 {
                return
            }
            usleep(100_000)
        }

        _ = kill(Int32(pid), SIGKILL)
    }

    private func terminateProcess(_ process: Process?, escalateAfter delay: TimeInterval) {
        guard let process else { return }
        let pid = process.processIdentifier
        process.terminate()

        let deadline = Date().addingTimeInterval(delay)
        while Date() < deadline {
            if kill(pid, 0) != 0 {
                return
            }
            usleep(100_000)
        }

        _ = kill(pid, SIGKILL)
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

    private static func looksLikePiOAuthHelper(_ args: String) -> Bool {
        args.contains("node:readline")
            && args.contains("getOAuthProvider")
            && args.contains("oauthModuleUrl")
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

    private var authRuntimeURL: URL {
        sessionFileURL.deletingLastPathComponent().appendingPathComponent("oauth-runtime.json")
    }
}
