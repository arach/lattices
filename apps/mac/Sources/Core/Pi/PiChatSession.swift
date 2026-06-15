import AppKit
import Combine
import Foundation
#if canImport(HudsonAI)
import HudsonAI
#endif

struct PiChatMessage: Identifiable, Equatable {
    enum Role {
        case system
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    var text: String
    let timestamp: Date

    init(id: UUID = UUID(), role: Role, text: String, timestamp: Date) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
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
    let modelID: String
    let authMode: AuthMode
    let tokenLabel: String
    let tokenPlaceholder: String
    let helpText: String

    static let supported: [PiProvider] = [
        PiProvider(
            id: "github-copilot",
            name: "GitHub Copilot",
            modelID: "gpt-5.4",
            authMode: .oauth,
            tokenLabel: "OAuth",
            tokenPlaceholder: "",
            helpText: "Uses device-code login. Personal access tokens are not accepted on this path."
        ),
        PiProvider(
            id: "openai-codex",
            name: "OpenAI Codex",
            modelID: "gpt-5.5",
            authMode: .oauth,
            tokenLabel: "OAuth",
            tokenPlaceholder: "",
            helpText: "Uses browser login for ChatGPT Plus/Pro Codex access."
        ),
        PiProvider(
            id: "openai",
            name: "OpenAI",
            modelID: "gpt-5.4",
            authMode: .apiKey,
            tokenLabel: "API key",
            tokenPlaceholder: "sk-...",
            helpText: "Stores an OpenAI API key for this app and the provider runtime to reuse."
        ),
        PiProvider(
            id: "anthropic",
            name: "Anthropic",
            modelID: "claude-opus-4-7",
            authMode: .apiKey,
            tokenLabel: "API key",
            tokenPlaceholder: "sk-ant-...",
            helpText: "Stores an Anthropic API key for provider-backed chat."
        ),
        PiProvider(
            id: "google",
            name: "Google Gemini",
            modelID: "gemini-3.1-pro-preview",
            authMode: .apiKey,
            tokenLabel: "API key",
            tokenPlaceholder: "AIza...",
            helpText: "Stores a Gemini API key for provider-backed chat."
        ),
        PiProvider(
            id: "openrouter",
            name: "OpenRouter",
            modelID: "moonshotai/kimi-k2.6",
            authMode: .apiKey,
            tokenLabel: "API key",
            tokenPlaceholder: "sk-or-...",
            helpText: "Stores an OpenRouter API key for provider-backed chat."
        ),
        PiProvider(
            id: "groq",
            name: "Groq",
            modelID: "openai/gpt-oss-120b",
            authMode: .apiKey,
            tokenLabel: "API key",
            tokenPlaceholder: "gsk_...",
            helpText: "Stores a Groq API key for provider-backed chat."
        ),
        PiProvider(
            id: "xai",
            name: "xAI",
            modelID: "grok-4.20-0309-reasoning",
            authMode: .apiKey,
            tokenLabel: "API key",
            tokenPlaceholder: "xai-...",
            helpText: "Stores an xAI API key for provider-backed chat."
        ),
        PiProvider(
            id: "mistral",
            name: "Mistral",
            modelID: "devstral-medium-latest",
            authMode: .apiKey,
            tokenLabel: "API key",
            tokenPlaceholder: "",
            helpText: "Stores a Mistral API key for provider-backed chat."
        ),
        PiProvider(
            id: "minimax",
            name: "MiniMax",
            modelID: "MiniMax-M2.7",
            authMode: .apiKey,
            tokenLabel: "API key",
            tokenPlaceholder: "",
            helpText: "Stores a MiniMax API key for provider-backed chat."
        ),
    ]

    static func provider(id: String) -> PiProvider {
        supported.first(where: { $0.id == id }) ?? supported[0]
    }
}

final class PiChatSession: ObservableObject {
    static let shared = PiChatSession()
    private static let installCommand = "npm install -g --ignore-scripts @earendil-works/pi-coding-agent@latest"

    @Published private(set) var messages: [PiChatMessage] = [
        PiChatMessage(
            role: .system,
            text: "Assistant ready. Uses a persistent Pi session — clear chat to start fresh.",
            timestamp: Date()
        )
    ]
    @Published var draft: String = ""
    @Published var isVisible: Bool = false
    @Published private(set) var isSending: Bool = false
    @Published private(set) var statusText: String = "idle"
    /// Prompts submitted while a turn was streaming. They render as pending chips
    /// and fire FIFO once the current turn finishes (the "queue" primitive).
    @Published private(set) var queuedPrompts: [String] = []
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
            isEditingStoredCredential = false
            authPromptInput = ""
            pendingAuthPrompt = nil
            authNoticeText = nil
            authErrorText = nil
            latestAuthURL = nil
            latestAuthInstructions = nil
            authVerificationCodeCopied = false
            lastCopiedAuthVerificationCode = nil
            invalidateChatRuntime()
            prepareForDisplay()
        }
    }
    @Published var authToken: String = ""
    @Published var isEditingStoredCredential: Bool = false
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
    private let chatSessionDirURL: URL
    private let voiceAdvisorSessionDirURL: URL
    private let voiceResolverSessionDirURL: URL
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
    private var chatRuntime: PiRpcRuntime?
    private var chatRuntimeProviderID: String?
    private var voiceAdvisorRuntime: PiRpcRuntime?
    private var voiceResolverRuntime: PiRpcRuntime?
    private var voiceRuntimeProviderID: String?

    private var streamingMessageID: UUID?
    /// The in-flight HudAIClient streaming task. Cancelling it (paired with
    /// HudAIClient's onTermination wiring) actually halts generation — that's the
    /// "stop" primitive. nil on the native PiRpcRuntime path.
    private var streamingTask: Task<Void, Never>?
    /// Monotonic turn id. Every provider callback captures the id it was started
    /// under and bails if it no longer matches, so a stopped or superseded turn
    /// can never write into a newer one (covers the non-cancellable native path).
    private var turnGeneration = 0
    // Display drain — decouples on-screen reveal from network arrival cadence so
    // chunky provider bursts flow in smoothly (and a wait-then-dump final still
    // animates in). `targetText` is everything received so far; `displayedCount`
    // is how many characters have been revealed; a 60Hz timer eases the gap shut.
    private var streamingTargetText: String = ""
    private var streamingDisplayedCount: Int = 0
    private var streamingClosing: Bool = false
    private var streamingDrainTimer: Timer?
    // Ticks to idle before revealing more — used to add a natural reading beat
    // after sentence/clause punctuation so the stream doesn't read robotically.
    private var streamingHoldTicks: Int = 0
    private static let streamingDrainInterval: TimeInterval = 1.0 / 60.0

    private static let selectedProviderDefaultsKey = "PiChatSelectedProvider"
    private static let voiceInferenceTimeout: TimeInterval = 45
    private static let chatAppendSystemPrompt = """
        You are the Workspace Assistant, the in-app assistant for Lattices.
        Use structured context from the host as ground truth. Answer naturally and concretely.
        For informational questions, explain what is configured and what the available choices mean.
        For setting changes, inspect or update the relevant local config with tools when available and safe.
        If you cannot apply a requested change, say so plainly and give the exact next step.
        Never claim a setting or file changed unless it actually changed.
        """
    private static let voiceAppendSystemPrompt = """
        You are the Workspace Assistant for Lattices voice surfaces.
        Respond concisely. Follow the response format requested in each prompt exactly.
        """

    /// Product-knowledge brief (how Lattices works, with doc references) injected
    /// into chat/voice prompts so the assistant can explain features — not just the
    /// current settings. Loaded once from `docs/assistant-knowledge.md`; empty if
    /// the file can't be found (the prompt then omits the block).
    static let capabilitiesGuide: String = loadCapabilitiesGuide()

    private static func loadCapabilitiesGuide() -> String {
        let file = "assistant-knowledge.md"
        let appDir = (Bundle.main.bundlePath as NSString).deletingLastPathComponent
        let candidates: [String] = [
            // Bundled into the app (shipped builds).
            Bundle.main.resourcePath.map { ($0 as NSString).appendingPathComponent("docs/\(file)") },
            // Beside the .app.
            ((appDir as NSString).appendingPathComponent("../docs/\(file)") as NSString).standardizingPath,
            // Repo root (dev builds: apps/mac/Lattices.app -> repo/docs).
            ((appDir as NSString).appendingPathComponent("../../docs/\(file)") as NSString).standardizingPath,
        ].compactMap { $0 }
        for path in candidates {
            if let text = try? String(contentsOfFile: path, encoding: .utf8),
               text.isEmpty == false {
                return text
            }
        }
        return ""
    }

    private static let dockHeightDefaultsKey = "PiChatDockHeight"

    #if canImport(HudsonVoice)
    /// Drains finalized voice transcripts from the Hudson-powered mic into the composer draft.
    private var voiceInputCancellable: AnyCancellable?
    #endif

    private init() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("Lattices/pi-chat", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        chatSessionDirURL = dir.appendingPathComponent("sessions", isDirectory: true)
        try? fm.createDirectory(at: chatSessionDirURL, withIntermediateDirectories: true)
        voiceAdvisorSessionDirURL = dir.appendingPathComponent("voice-advisor-sessions", isDirectory: true)
        try? fm.createDirectory(at: voiceAdvisorSessionDirURL, withIntermediateDirectories: true)
        voiceResolverSessionDirURL = dir.appendingPathComponent("voice-resolver-sessions", isDirectory: true)
        try? fm.createDirectory(at: voiceResolverSessionDirURL, withIntermediateDirectories: true)
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

        #if canImport(HudsonVoice)
        // Splice finalized voice transcripts into the draft (one-shot, then drain),
        // mirroring OpenScout's HUDDockState lastFinalText subscription.
        voiceInputCancellable = WorkspaceVoiceInput.shared.$lastFinalText
            .receive(on: RunLoop.main)
            .sink { [weak self] text in
                guard let self else { return }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                self.draft = WorkspaceDictationBuffer.appending(trimmed, to: self.draft)
                Task { @MainActor in
                    WorkspaceVoiceInput.shared.consumeFinalText()
                }
            }
        #endif
    }

    var hasPiBinary: Bool {
        piBinaryPath != nil
    }

    var isProviderInferenceReady: Bool {
        hasPiBinary && !needsProviderSetup
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

    var copyableConversationText: String {
        messages
            .filter { $0.role != .system }
            .compactMap { message -> String? in
                let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return "\(Self.copyLabel(for: message.role)):\n\(text)"
            }
            .joined(separator: "\n\n")
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
            return "Stay here for a second while the sign-in page is prepared."
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
            return "Install the provider runtime to enable provider chat"
        }
        if isAuthenticating {
            return authStepShortText
        }
        if needsProviderSetup {
            return "Next: connect \(currentProvider.name)"
        }
        return currentProvider.name
    }

    /// Active tool name when the runtime is mid-tool-call, else nil. Drives
    /// the in-message tool chip on the streaming assistant row.
    var activeToolName: String? {
        let prefix = "tool: "
        guard statusText.hasPrefix(prefix) else { return nil }
        let raw = String(statusText.dropFirst(prefix.count))
        return raw.isEmpty ? nil : raw
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
        messages = []
        prepareForDisplay()
        queue.async { [weak self] in
            guard let self else { return }
            if let runtime = self.chatRuntime {
                runtime.newSession { result in
                    if case .failure(let error) = result {
                        DispatchQueue.main.async {
                            self.appendSystemMessage("Could not start a new assistant session: \(error.localizedDescription)")
                        }
                    }
                }
                return
            }
            try? FileManager.default.removeItem(at: self.chatSessionDirURL)
            try? FileManager.default.createDirectory(at: self.chatSessionDirURL, withIntermediateDirectories: true)
        }
    }

    func shutdown() {
        invalidateChatRuntime()
    }

    func prepareForDisplay() {
        reconcileAuthState()
        refreshBinaryAvailability()

        if isAuthenticating {
            isAuthPanelVisible = true
            statusText = "connecting..."
        } else if needsProviderSetup {
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
        appendSystemMessage("Copied the provider runtime install command to the clipboard.")
    }

    func copyConversationToClipboard() {
        let text = copyableConversationText
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        DiagnosticLog.shared.success("PiChat: copied conversation to clipboard (\(text.count) chars)")
    }

    func installPiInTerminal() {
        Preferences.shared.terminal.launch(command: piInstallCommand, in: NSHomeDirectory())
        appendSystemMessage("Opened \(Preferences.shared.terminal.rawValue) and started the provider runtime install.")
    }

    func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        if isSending {
            queuedPrompts.append(text)   // queue while a turn is in flight
            return
        }
        send(text)
    }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isSending else { return }

        messages.append(PiChatMessage(role: .user, text: trimmed, timestamp: Date()))

        if let localResponse = handleImmediateLocalCommand(trimmed) {
            appendLocalAssistantResponse(localResponse)
            return
        }

        refreshBinaryAvailability()

        if !isProviderInferenceReady,
           let localResponse = handleLocalSettingsCommand(trimmed) {
            appendLocalAssistantResponse(localResponse)
            return
        }

        guard let piPath = piBinaryPath else {
            DiagnosticLog.shared.info("Chat: provider runtime not installed — cannot send")
            prepareForDisplay()
            statusText = "missing pi"
            return
        }

        guard !needsProviderSetup else {
            DiagnosticLog.shared.info("Chat: \(currentProvider.name) needs credentials — showing auth panel instead of sending")
            prepareForDisplay()
            isAuthPanelVisible = true
            dockHeight = max(dockHeight, 300)
            return
        }

        let provider = currentProvider
        isSending = true
        statusText = "thinking..."
        settleActiveStreamingMessage(interrupted: false)   // snap any prior reveal to full before a new turn
        turnGeneration &+= 1
        let turnGen = turnGeneration
        let prompt = providerPrompt(for: trimmed)
        let runtime = chatRuntime(piPath: piPath, provider: provider)
        let inferenceTimer = DiagnosticLog.shared.startTimed("Chat inference via \(provider.name) RPC")
        let messageID = UUID()
        messages.append(PiChatMessage(
            id: messageID,
            role: .assistant,
            text: "",
            timestamp: Date()
        ))

        streamingMessageID = messageID
        resetStreamingDrain()

        #if canImport(HudsonAI)
        if HudsonKitSwitch.useHudAIChat {
            sendViaHudAIClient(
                prompt: prompt,
                runtime: runtime,
                providerName: provider.name,
                modelID: provider.modelID,
                messageID: messageID,
                generation: turnGen,
                inferenceTimer: inferenceTimer
            )
            return
        }
        #endif

        var streamedText = ""
        runtime.promptAndFetchAssistantText(
            prompt,
            onEvent: { [weak self] event in
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard self.turnGeneration == turnGen else { return }  // stale (stopped/superseded) turn
                    if let delta = PiRpcRuntime.streamingDelta(from: event) {
                        streamedText += delta
                        if self.statusText == "thinking..." {
                            self.statusText = "streaming..."
                        }
                        self.commitStreamingText(streamedText)
                    } else if let snapshot = PiRpcRuntime.streamingSnapshot(from: event) {
                        streamedText = snapshot
                        if self.statusText == "thinking..." {
                            self.statusText = "streaming..."
                        }
                        self.commitStreamingText(streamedText)
                    } else if event["type"] as? String == "tool_execution_start",
                              let toolName = event["toolName"] as? String {
                        self.statusText = "tool: \(toolName)"
                    }
                }
            }
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.turnGeneration == turnGen else { return }  // stopped/superseded before completion
                self.isSending = false

                switch result {
                case .success(let text):
                    DiagnosticLog.shared.finish(inferenceTimer)
                    self.statusText = "idle"
                    self.finalizeStreaming(finalText: text)
                case .failure(let error):
                    DiagnosticLog.shared.error("Chat inference failed: \(error.localizedDescription)")
                    self.cancelPendingStreamingFlush()
                    self.removeMessageIfEmpty(id: messageID)
                    self.streamingMessageID = nil
                    self.handleInferenceFailure(error.localizedDescription)
                }
                self.drainQueuedPrompt()
            }
        }
    }

    #if canImport(HudsonAI)
    /// Drive a chat turn through HudsonKit's `HudAIClient` with pi as the
    /// provider adapter, instead of calling `PiRpcRuntime` directly. Gated on
    /// `HudsonKitSwitch.useHudAIChat`. Feeds the same 30fps-coalesced streaming
    /// commit path as the native pi route, so the rendered result is identical —
    /// this is the seam where pi becomes "one of the providers HudAIClient
    /// supports", alongside the HTTP adapters.
    private func sendViaHudAIClient(
        prompt: String,
        runtime: PiRpcRuntime,
        providerName: String,
        modelID: String,
        messageID: UUID,
        generation: Int,
        inferenceTimer: DiagnosticLog.TimedAction
    ) {
        let adapter = PiHudAIAdapter(
            displayName: providerName,
            defaultModel: modelID,
            runtimeProvider: { runtime }
        )
        let client = HudAIClient(
            provider: adapter,
            vault: NullHudAICredentialSource(),
            defaults: HudAIDefaults(timeout: 120),
            routeDefault: .local
        )
        let request = HudAIRequest(messages: [.user(prompt)])

        // Held so a Stop can cancel it. HudAIClient.stream() ties its producer to
        // the stream's termination, so cancelling this task actually halts pi.
        streamingTask = Task {
            var streamed = ""
            do {
                for try await event in client.stream(request) {
                    switch event {
                    case .textDelta(_, let text):
                        streamed += text
                        let snapshot = streamed
                        DispatchQueue.main.async { [weak self] in
                            guard let self, self.turnGeneration == generation else { return }
                            if self.statusText == "thinking..." { self.statusText = "streaming..." }
                            self.commitStreamingText(snapshot)
                        }
                    case .toolCallStarted(_, let name):
                        DispatchQueue.main.async { [weak self] in
                            guard let self, self.turnGeneration == generation else { return }
                            self.statusText = "tool: \(name)"
                        }
                    case .completed(let response):
                        let final = response.text.isEmpty ? streamed : response.text
                        DispatchQueue.main.async { [weak self] in
                            guard let self, self.turnGeneration == generation else { return }
                            self.streamingTask = nil
                            self.isSending = false
                            self.statusText = "idle"
                            DiagnosticLog.shared.finish(inferenceTimer)
                            self.finalizeStreaming(finalText: final)
                            self.drainQueuedPrompt()
                        }
                    case .failed:
                        // HudAIClient always finishes(throwing:) right after .failed,
                        // so the catch below owns failure handling (avoids double-fire).
                        break
                    default:
                        break
                    }
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.turnGeneration == generation else { return }  // cancelled/stopped
                    self.streamingTask = nil
                    self.isSending = false
                    DiagnosticLog.shared.error("Chat inference (HudAIClient) failed: \(error.localizedDescription)")
                    self.cancelPendingStreamingFlush()
                    self.removeMessageIfEmpty(id: messageID)
                    self.streamingMessageID = nil
                    self.handleInferenceFailure(error.localizedDescription)
                    self.drainQueuedPrompt()
                }
            }
        }
    }
    #endif

    func askVoiceAdvisor(transcript: String, matched: String, callback: @escaping (AgentResponse?) -> Void) {
        runVoiceInference(
            prompt: voiceAdvisorPrompt(transcript: transcript, matched: matched),
            sessionDir: voiceAdvisorSessionDirURL,
            label: "voice advisor"
        ) { output in
            guard let output, !output.isEmpty else {
                callback(nil)
                return
            }
            callback(AgentResponse.parse(text: output))
        }
    }

    func answerVoiceQuestion(_ transcript: String, callback: @escaping (AgentResponse?) -> Void) {
        runVoiceInference(
            prompt: voiceQuestionPrompt(transcript: transcript),
            sessionDir: voiceAdvisorSessionDirURL,
            label: "voice question"
        ) { output in
            guard let output, !output.isEmpty else {
                callback(nil)
                return
            }
            callback(AgentResponse(commentary: output, suggestion: nil, raw: output))
        }
    }

    func resolveVoiceIntent(transcript: String, callback: @escaping (ResolvedIntent?) -> Void) {
        runVoiceInference(
            prompt: voiceResolverPrompt(transcript: transcript),
            sessionDir: voiceResolverSessionDirURL,
            label: "voice resolver"
        ) { output in
            callback(Self.parseResolvedIntent(from: output))
        }
    }

    /// Second-chance AI pass: an intent the model produced failed validation/execution.
    /// Hand the model the exact failure plus the full catalog vocabulary and ask it to
    /// return a corrected intent constrained to valid values. Best-effort — calls back nil
    /// if the model can't fix it, so the caller can surface the original error.
    func repairVoiceIntent(
        transcript: String,
        failedIntent: String,
        failedSlots: [String: JSON],
        error: String,
        callback: @escaping (ResolvedIntent?) -> Void
    ) {
        runVoiceInference(
            prompt: voiceRepairPrompt(transcript: transcript, failedIntent: failedIntent, failedSlots: failedSlots, error: error),
            sessionDir: voiceResolverSessionDirURL,
            label: "voice repair"
        ) { output in
            callback(Self.parseResolvedIntent(from: output))
        }
    }

    /// Parse a resolver/repair model response into a ResolvedIntent. Returns nil for
    /// missing/`unknown` intents so the caller treats it as "couldn't resolve".
    private static func parseResolvedIntent(from output: String?) -> ResolvedIntent? {
        guard let output,
              let jsonStr = Self.extractJSON(from: output),
              let data = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let intent = json["intent"] as? String,
              intent != "unknown" else {
            return nil
        }

        var slots: [String: JSON] = [:]
        if let rawSlots = json["slots"] as? [String: Any] {
            for (key, value) in rawSlots {
                if let value = value as? String {
                    slots[key] = .string(value)
                } else if let value = value as? Int {
                    slots[key] = .int(value)
                } else if let value = value as? Bool {
                    slots[key] = .bool(value)
                }
            }
        }
        return ResolvedIntent(intent: intent, slots: slots)
    }

    private func runVoiceInference(
        prompt: String,
        sessionDir: URL,
        label: String,
        callback: @escaping (String?) -> Void
    ) {
        refreshBinaryAvailability()

        guard let piPath = piBinaryPath else {
            DiagnosticLog.shared.info("Assistant inference[\(label)]: provider runtime not installed")
            callback(nil)
            return
        }
        guard !needsProviderSetup else {
            DiagnosticLog.shared.info("Assistant inference[\(label)]: selected provider needs credentials")
            callback(nil)
            return
        }

        let provider = currentProvider
        let runtime = voiceRuntime(piPath: piPath, provider: provider, sessionDir: sessionDir)
        let timer = DiagnosticLog.shared.startTimed("Assistant inference[\(label)] via \(provider.name) RPC")

        runtime.promptAndFetchAssistantText(prompt, timeout: Self.voiceInferenceTimeout) { result in
            DiagnosticLog.shared.finish(timer)
            switch result {
            case .success(let text):
                callback(text)
            case .failure(let error):
                DiagnosticLog.shared.info("Assistant inference[\(label)]: \(error.localizedDescription)")
                callback(nil)
            }
        }
    }

    private func updateAssistantMessage(id: UUID, text: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].text = text
    }

    /// Record the latest accumulated snapshot as the drain target. The reveal
    /// itself happens on the drain timer, not here — so a chunky burst doesn't
    /// snap onto the screen all at once.
    private func commitStreamingText(_ text: String) {
        streamingTargetText = text
        startStreamingDrainIfNeeded()
    }

    private func resetStreamingDrain() {
        streamingDrainTimer?.invalidate()
        streamingDrainTimer = nil
        streamingTargetText = ""
        streamingDisplayedCount = 0
        streamingClosing = false
        streamingHoldTicks = 0
    }

    private func startStreamingDrainIfNeeded() {
        guard streamingDrainTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: Self.streamingDrainInterval, repeats: true) { [weak self] _ in
            self?.tickStreamingDrain()
        }
        // .common so the drain keeps ticking during scroll/tracking runloops.
        RunLoop.main.add(timer, forMode: .common)
        streamingDrainTimer = timer
    }

    /// One reveal step: ease the displayed length toward the target, snapping to
    /// a word boundary so words land whole. Faster while closing so the message
    /// settles promptly once the network is done.
    private func tickStreamingDrain() {
        guard let id = streamingMessageID else {
            streamingDrainTimer?.invalidate()
            streamingDrainTimer = nil
            return
        }

        // Honor a pending reading beat (skip this tick) before revealing more.
        if streamingHoldTicks > 0 {
            streamingHoldTicks -= 1
            return
        }

        let target = streamingTargetText
        let targetCount = target.count

        if streamingDisplayedCount >= targetCount {
            if streamingClosing {
                updateAssistantMessage(id: id, text: target)
                streamingDrainTimer?.invalidate()
                streamingDrainTimer = nil
                streamingMessageID = nil
            }
            return
        }

        let gap = targetCount - streamingDisplayedCount
        let fraction = streamingClosing ? 0.45 : 0.22
        let minStep = streamingClosing ? 6 : 2
        var step = max(minStep, Int((Double(gap) * fraction).rounded()))
        step = min(step, gap)
        let proposed = streamingDisplayedCount + step
        streamingDisplayedCount = snapToWordBoundary(in: target, proposed: proposed)
        updateAssistantMessage(id: id, text: String(target.prefix(streamingDisplayedCount)))

        // After landing on a word boundary, add a reading beat if we just
        // finished a sentence or clause — but never while racing to settle, and
        // never if there's a huge backlog to catch up on.
        if !streamingClosing, gap < 240 {
            streamingHoldTicks = readingBeat(in: target, revealedCount: streamingDisplayedCount)
        }
    }

    /// Pause length (in 60Hz ticks) after the most recently revealed token:
    /// a longer beat after sentence enders, a shorter one after clause marks.
    private func readingBeat(in text: String, revealedCount: Int) -> Int {
        let chars = Array(text)
        // The boundary lands just past a space, so the sentence punctuation is a
        // couple of characters back. Scan the last few non-space chars.
        var idx = revealedCount - 1
        var skippedSpace = false
        while idx >= 0, idx >= revealedCount - 3 {
            let c = chars[idx]
            if c == " " || c == "\n" { skippedSpace = true; idx -= 1; continue }
            guard skippedSpace || idx == revealedCount - 1 else { break }
            switch c {
            case ".", "!", "?":  return 10   // ~165ms — end of sentence
            case ",", ";", ":":  return 5    // ~80ms  — clause break
            default:             return 0
            }
        }
        return 0
    }

    /// Extend `proposed` forward to just past the next space/newline (within a
    /// small window) so the reveal doesn't stop mid-token.
    private func snapToWordBoundary(in text: String, proposed: Int) -> Int {
        let chars = Array(text)
        guard proposed < chars.count else { return chars.count }
        var i = proposed
        let limit = min(chars.count, proposed + 16)
        while i < limit {
            if chars[i] == " " || chars[i] == "\n" { return i + 1 }
            i += 1
        }
        return proposed
    }

    private func cancelPendingStreamingFlush() {
        resetStreamingDrain()
    }

    /// Hand the drain the final text and let it finish revealing. The drain
    /// settles the message exactly and clears `streamingMessageID` once caught up.
    private func finalizeStreaming(finalText: String) {
        streamingTargetText = finalText
        streamingClosing = true
        startStreamingDrainIfNeeded()
    }

    /// Snap the active streaming message to everything received so far and stop the
    /// drain — used before a new turn starts and when a turn is stopped. When
    /// `interrupted`, tag the partial so it reads as deliberately cut off.
    private func settleActiveStreamingMessage(interrupted: Bool) {
        guard let id = streamingMessageID else { return }
        let full = streamingTargetText
        resetStreamingDrain()
        streamingMessageID = nil
        if full.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            removeMessageIfEmpty(id: id)
        } else if interrupted {
            updateAssistantMessage(id: id, text: full + "\n\n— stopped —")
        } else {
            updateAssistantMessage(id: id, text: full)
        }
    }

    /// Fire the next queued prompt once the turn is idle (FIFO drain).
    private func drainQueuedPrompt() {
        guard !isSending, !queuedPrompts.isEmpty else { return }
        let next = queuedPrompts.removeFirst()
        send(next)
    }

    /// Stop button. Halts the in-flight turn (cancelling generation on the
    /// HudAIClient path; the generation guard neutralizes the native path's stale
    /// callbacks), settles the partial answer, then — if the composer has text —
    /// sends it immediately as a redirect (steer). Empty draft = plain stop, and
    /// any queued prompts still continue.
    func interruptAndSteer() {
        guard isSending else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        turnGeneration &+= 1
        streamingTask?.cancel()
        streamingTask = nil
        isSending = false
        statusText = "idle"
        settleActiveStreamingMessage(interrupted: true)
        if text.isEmpty {
            drainQueuedPrompt()
        } else {
            draft = ""
            send(text)
        }
    }

    /// Remove a still-pending queued prompt (tapping its chip before it fires).
    func removeQueuedPrompt(at index: Int) {
        guard queuedPrompts.indices.contains(index) else { return }
        queuedPrompts.remove(at: index)
    }

    private func removeMessageIfEmpty(id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        if messages[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.remove(at: index)
        }
    }

    private func handleInferenceFailure(_ message: String) {
        if let friendly = friendlyAuthFailureMessage(for: message) {
            statusText = "setup ai"
            authErrorText = friendly
            isAuthPanelVisible = true
            syncStructuredWelcomeMessage()
            invalidateChatRuntime()
            return
        }
        statusText = "error"
        appendSystemMessage(message)
        if Self.looksLikeAuthError(message) {
            isAuthPanelVisible = true
            invalidateChatRuntime()
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
            isEditingStoredCredential = false
            authNoticeText = "Saved \(currentProvider.tokenLabel.lowercased()) for \(currentProvider.name)."
            authErrorText = nil
            reloadAuthState()
            invalidateChatRuntime()
            appendSystemMessage("Saved \(currentProvider.name) credentials.")
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
            isEditingStoredCredential = true
            reloadAuthState()
            invalidateChatRuntime()
            appendSystemMessage("Removed saved \(currentProvider.name) credentials.")
            prepareForDisplay()
        } catch {
            authErrorText = "Failed to remove credentials: \(error.localizedDescription)"
        }
    }

    private func chatRuntime(piPath: String, provider: PiProvider) -> PiRpcRuntime {
        if let chatRuntime,
           chatRuntimeProviderID == provider.id,
           chatRuntime.isRunning {
            return chatRuntime
        }

        chatRuntime?.stop()
        let runtime = PiRpcRuntime(
            piPath: piPath,
            sessionDir: chatSessionDirURL,
            providerID: provider.id,
            modelID: provider.modelID,
            environment: buildProcessEnvironment(for: provider),
            appendSystemPrompt: Self.chatAppendSystemPrompt
        )
        chatRuntime = runtime
        chatRuntimeProviderID = provider.id
        return runtime
    }

    private func voiceRuntime(piPath: String, provider: PiProvider, sessionDir: URL) -> PiRpcRuntime {
        if voiceRuntimeProviderID != provider.id {
            voiceAdvisorRuntime?.stop()
            voiceResolverRuntime?.stop()
            voiceAdvisorRuntime = nil
            voiceResolverRuntime = nil
            voiceRuntimeProviderID = provider.id
        }

        if sessionDir == voiceAdvisorSessionDirURL,
           let voiceAdvisorRuntime,
           voiceAdvisorRuntime.isRunning {
            return voiceAdvisorRuntime
        }
        if sessionDir == voiceResolverSessionDirURL,
           let voiceResolverRuntime,
           voiceResolverRuntime.isRunning {
            return voiceResolverRuntime
        }

        let runtime = PiRpcRuntime(
            piPath: piPath,
            sessionDir: sessionDir,
            providerID: provider.id,
            modelID: provider.modelID,
            environment: buildProcessEnvironment(for: provider),
            appendSystemPrompt: Self.voiceAppendSystemPrompt,
            disableBuiltInTools: true,
            defaultTimeout: Self.voiceInferenceTimeout
        )

        if sessionDir == voiceAdvisorSessionDirURL {
            voiceAdvisorRuntime = runtime
        } else {
            voiceResolverRuntime = runtime
        }
        return runtime
    }

    private func invalidateChatRuntime() {
        chatRuntime?.stop()
        chatRuntime = nil
        chatRuntimeProviderID = nil
        voiceAdvisorRuntime?.stop()
        voiceAdvisorRuntime = nil
        voiceResolverRuntime?.stop()
        voiceResolverRuntime = nil
        voiceRuntimeProviderID = nil
    }

    private func buildProcessEnvironment(for provider: PiProvider) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")
        if provider.id == "github-copilot", storedCredentialKinds[provider.id] == nil {
            env.removeValue(forKey: "COPILOT_GITHUB_TOKEN")
        }
        Self.sanitizeEnvironment(&env, for: provider.id, hasStoredCredential: storedCredentialKinds[provider.id] != nil)
        return env
    }

    func startSelectedAuthFlow() {
        if currentProvider.authMode == .apiKey {
            saveSelectedToken()
            return
        }

        startOAuthLogin(for: currentProvider)
    }

    func beginReplacingSelectedCredential() {
        authToken = ""
        authErrorText = nil
        authNoticeText = nil
        isEditingStoredCredential = true
    }

    func cancelReplacingSelectedCredential() {
        authToken = ""
        authErrorText = nil
        isEditingStoredCredential = false
    }

    func submitAuthPrompt() {
        guard let prompt = pendingAuthPrompt else { return }
        let value = authPromptInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard prompt.allowEmpty || !value.isEmpty else { return }
        submitAuthPromptValue(value)
    }

    private func submitAuthPromptValue(_ value: String) {
        guard let handle = authInputHandle else {
            authErrorText = "The auth input pipe is no longer available."
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
            authErrorText = "Install the provider runtime before starting auth."
            return
        }

        guard let nodePath = nodeBinaryPath else {
            authErrorText = "Node.js is required for OAuth login."
            return
        }

        guard let oauthModuleURL = resolveOAuthModuleURL() else {
            authErrorText = "Couldn't locate the OAuth module next to the installed provider runtime."
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
                appendSystemMessage("Auth is ready. The sign-in code is copied, and you can reopen the browser page here if needed.")
            } else if let instructions, !instructions.isEmpty {
                appendSystemMessage("Auth: \(instructions) If nothing opened, use OPEN AGAIN.")
            } else {
                appendSystemMessage("Auth is ready in your browser. If nothing opened, use OPEN AGAIN.")
            }

        case "progress":
            authNoticeText = json["message"] as? String ?? "Working..."

        case "success":
            guard var credentials = json["credentials"] as? [String: Any] else {
                authErrorText = "Auth completed but returned no credentials."
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
                appendSystemMessage("Saved \(provider.name) OAuth credentials.")
                isAuthPanelVisible = false
                prepareForDisplay()
            } catch {
                authErrorText = "Failed to save OAuth credentials: \(error.localizedDescription)"
            }

        case "error":
            let message = json["message"] as? String ?? "Unknown auth error."
            authErrorText = message
            appendSystemMessage("Auth failed: \(message)")

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

    private static func copyLabel(for role: PiChatMessage.Role) -> String {
        switch role {
        case .system:
            return "System"
        case .user:
            return "You"
        case .assistant:
            return "Assistant"
        }
    }

    private func appendSystemMessage(_ text: String) {
        messages.append(PiChatMessage(role: .system, text: text, timestamp: Date()))
    }

    private func appendLocalAssistantResponse(_ text: String) {
        messages.append(PiChatMessage(role: .assistant, text: text, timestamp: Date()))
        refreshBinaryAvailability()
        statusText = hasPiBinary ? (needsProviderSetup ? "setup ai" : "idle") : "missing pi"
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
            Welcome to the Workspace Assistant.

            Install the provider runtime to use regular assistant turns. Until then, only a few deterministic app commands work here.

            Install command:
            \(piInstallCommand)
            """
        }

        if isAuthenticating {
            return """
            Welcome to the Workspace Assistant.

            \(authStepTitle)

            \(authStepDescription)
            """
        }

        if needsProviderSetup {
            return """
            Welcome to the Workspace Assistant.

            Next step: connect \(currentProvider.name).

            Open Settings with the gear icon, choose a provider, and save its API key to unlock provider-backed chat.
            """
        }

        return """
        Welcome to the Workspace Assistant.

        You're connected with \(currentProvider.name). Regular turns go through the provider for code help, planning, debugging, settings changes, and second opinions.
        """
    }

    private func handleLocalSettingsCommand(_ text: String) -> String? {
        let lower = text.lowercased()
        let prefs = Preferences.shared

        if let immediate = handleImmediateLocalCommand(text) {
            return immediate
        }

        if lower.contains("help") && lower.contains("settings") {
            return settingsHelpText()
        }

        if lower.contains("settings") && isInformationalSettingsQuery(lower) {
            return settingsSummary()
        }

        if lower.contains("status") || lower.contains("current settings") {
            return settingsSummary()
        }

        if lower.contains("advisor") || lower.contains("voice advisor") {
            return nil
        }

        if lower.contains("scan root") || lower.contains("project root") || lower.contains("project scan") {
            if let root = extractPathValue(from: text) {
                prefs.scanRoot = root
                ProjectScanner.shared.updateRoot(root)
                ProjectScanner.shared.scan()
                return "Set project scan root to \(root) and started a rescan."
            }
            return nil
        }

        if lower.contains("terminal"), isSettingsMutationIntent(lower) {
            if let terminal = parseTerminal(from: lower) {
                guard terminal.isInstalled else {
                    return "\(terminal.rawValue) is not installed, so I left the terminal set to \(prefs.terminal.rawValue)."
                }
                prefs.terminal = terminal
                return "Set terminal to \(terminal.rawValue)."
            }
            return nil
        }

        if isSettingsMutationIntent(lower),
           lower.contains("detach mode") || lower.contains("interaction mode") || lower.contains("learning mode") || lower.contains("auto mode") {
            if lower.contains("auto") {
                prefs.mode = .auto
                return "Set detach mode to Auto."
            }
            if lower.contains("learning") {
                prefs.mode = .learning
                return "Set detach mode to Learning."
            }
            return nil
        }

        if lower.contains("drag") && lower.contains("snap"), isSettingsMutationIntent(lower) {
            if let enabled = parseBooleanMutation(from: lower) {
                prefs.dragSnapEnabled = enabled
                return "\(enabled ? "Enabled" : "Disabled") drag-to-snap."
            }
            return nil
        }

        if lower.contains("mouse") && (lower.contains("gesture") || lower.contains("shortcut")), isSettingsMutationIntent(lower) {
            if isMouseShortcutRuleRequest(lower) {
                return nil
            }
            if let enabled = parseBooleanMutation(from: lower) {
                prefs.mouseGesturesEnabled = enabled
                return "\(enabled ? "Enabled" : "Disabled") mouse gestures."
            }
            return nil
        }

        if lower.contains("companion") && lower.contains("bridge"), isSettingsMutationIntent(lower) {
            if let enabled = parseBooleanMutation(from: lower) {
                prefs.companionBridgeEnabled = enabled
                return "\(enabled ? "Enabled" : "Disabled") the companion bridge."
            }
            return nil
        }

        if lower.contains("companion") && lower.contains("trackpad"), isSettingsMutationIntent(lower) {
            if let enabled = parseBooleanMutation(from: lower) {
                prefs.companionTrackpadEnabled = enabled
                return "\(enabled ? "Enabled" : "Disabled") companion trackpad."
            }
            return nil
        }

        if lower.contains("ocr") || lower.contains("screen text") || lower.contains("text recognition") {
            if lower.contains("accuracy") {
                if lower.contains("fast") {
                    prefs.ocrAccuracy = "fast"
                    return "Set OCR accuracy to Fast."
                }
                if lower.contains("accurate") {
                    prefs.ocrAccuracy = "accurate"
                    return "Set OCR accuracy to Accurate."
                }
                return nil
            }

            if isSettingsMutationIntent(lower), let enabled = parseBooleanMutation(from: lower) {
                OcrModel.shared.setEnabled(enabled)
                return "\(enabled ? "Enabled" : "Disabled") screen text recognition."
            }
            return nil
        }

        return nil
    }

    private func handleImmediateLocalCommand(_ text: String) -> String? {
        let lower = text.lowercased()

        if lower.contains("open assistant settings") || lower.contains("show assistant settings") {
            SettingsWindowController.shared.showAssistant()
            return "Opened Assistant settings."
        }

        if lower.contains("open settings") || lower.contains("show settings") {
            SettingsWindowController.shared.show()
            return "Opened Settings."
        }

        return nil
    }

    private func providerPrompt(for userText: String) -> String {
        let knowledge = Self.capabilitiesGuide
        let knowledgeBlock = knowledge.isEmpty ? "" : """

            Lattices product knowledge (how the app works; cite the linked docs when a question goes deeper):
            \(knowledge)
            """
        return """
        You are the Workspace Assistant, the in-app assistant for Lattices.

        Use the structured context as ground truth for this user's current configuration, and the product knowledge to explain how Lattices works and point to the right feature or doc. Answer naturally and concretely. For informational questions, explain what is currently configured and what the available choices mean.

        For setting changes, inspect or update the relevant local config with tools when available and safe. If you cannot apply the change, say so plainly and give the exact next step. Never claim a setting or file changed unless it actually changed.
        \(knowledgeBlock)

        Structured context:
        \(assistantKnowledgeBrief())

        User request:
        \(userText)
        """
    }

    private func voiceAdvisorPrompt(transcript: String, matched: String) -> String {
        """
        You are the same Workspace Assistant used by Lattices chat, responding through the voice command surface.

        Use the shared structured context below as ground truth. The voice surface needs terse commentary and optional next actions, not a chatty answer.

        Structured context:
        \(assistantKnowledgeBrief())

        Voice transcript:
        "\(transcript)"

        Local match already handled:
        \(matched)

        Available intents (use ONLY these names and slot values):
        \(voiceIntentCatalogText())

        Respond with ONLY a JSON object:
        {"commentary": "short observation or null", "suggestion": {"label": "button text", "intent": "intent_name", "slots": {"key": "value"}} or null}

        Rules:
        - commentary: 1 sentence max. null if the matched command fully covers the request.
        - suggestion: a follow-up action. null if none needed.
        - suggestion.intent MUST be one of the intent names listed above. Never invent an intent.
        - For slots marked with {a|b|c}, the value MUST be exactly one of those tokens.
        - Never suggest what was already executed.
        - Suggestions MUST include all required slots (marked with *).
        - Be terse and useful.
        """
    }

    private func voiceQuestionPrompt(transcript: String) -> String {
        let knowledge = Self.capabilitiesGuide
        let knowledgeBlock = knowledge.isEmpty ? "" : """

            Lattices product knowledge (how the app works):
            \(knowledge)
            """
        return """
        You are the same Workspace Assistant used by Lattices chat, responding through the voice surface.

        This is an informational question, not necessarily a command. Use the shared structured context and product knowledge below, answer naturally, and include concrete current settings when relevant. Keep it short enough for voice, but do not give a clipped yes/no answer.
        \(knowledgeBlock)

        Structured context:
        \(assistantKnowledgeBrief())

        User said:
        "\(transcript)"
        """
    }

    /// Renders the full intent catalog as a vocabulary block for the voice prompts.
    /// Each line lists the intent name, description, and its slots with required
    /// markers (`*`) and the exact set of allowed enum values (`{a|b|c}`). The model
    /// only ever sees valid intent names and valid slot values from here, which keeps
    /// it from inventing things the executor rejects (e.g. position "tl", "grid-2x2").
    private func voiceIntentCatalogText() -> String {
        guard case .array(let intents) = PhraseMatcher.shared.catalog() else { return "" }
        return intents.compactMap { intent -> String? in
            guard let name = intent["intent"]?.stringValue else { return nil }
            let desc = intent["description"]?.stringValue ?? ""
            var line = desc.isEmpty ? "- \(name)" : "- \(name) — \(desc)"
            if case .array(let slots) = intent["slots"], !slots.isEmpty {
                let slotDescs = slots.compactMap { slot -> String? in
                    guard let slotName = slot["name"]?.stringValue else { return nil }
                    var s = slotName
                    if slot["required"]?.boolValue == true { s += "*" }
                    if case .array(let vals) = slot["values"] {
                        let values = vals.compactMap { $0.stringValue }
                        if !values.isEmpty { s += " {\(values.joined(separator: "|"))}" }
                    }
                    return s
                }
                if !slotDescs.isEmpty {
                    line += "\n    slots: \(slotDescs.joined(separator: ", "))"
                }
            }
            return line
        }.joined(separator: "\n")
    }

    private func voiceResolverPrompt(transcript: String) -> String {
        let windowList = DesktopModel.shared.windows.values
            .prefix(20)
            .map { "\($0.app): \($0.title)" }
            .joined(separator: "\n")

        let intentList = voiceIntentCatalogText()

        return """
        You are the same Workspace Assistant used by Lattices chat, resolving a spoken command into one executable Lattices intent.

        Structured context:
        \(assistantKnowledgeBrief())

        Voice transcript, possibly with transcription errors:
        "\(transcript)"

        Available intents:
        \(intentList)

        Current windows:
        \(windowList)

        Return ONLY a JSON object like:
        {"intent":"search","slots":{"query":"dewey"},"reasoning":"user wants to find dewey windows"}

        Rules:
        - Use ONLY intent names and slot values listed above. Never invent a slot value.
        - For slots marked with {a|b|c}, the value MUST be exactly one of those tokens.
        - Use intent "unknown" if the request cannot be mapped confidently.
        - Include all required slots (marked with *).
        - For search, extract the key term.
        - Use app/window names from the current windows list when targeting windows.
        - tile_window moves ONE window to a position. To arrange MULTIPLE windows into a grid (e.g. "tile my four iTerms two by two"), use distribute, not tile_window.
        """
    }

    private func voiceRepairPrompt(transcript: String, failedIntent: String, failedSlots: [String: JSON], error: String) -> String {
        let slotsDesc = failedSlots
            .map { "\($0.key)=\($0.value.stringValue ?? "\($0.value)")" }
            .sorted()
            .joined(separator: ", ")
        let attempt = slotsDesc.isEmpty ? failedIntent : "\(failedIntent)(\(slotsDesc))"

        return """
        You are correcting a Lattices voice command that failed to execute. A previous pass
        produced an intent the executor rejected. Fix it using ONLY the vocabulary below.

        Original voice transcript:
        "\(transcript)"

        Previous attempt that FAILED:
        \(attempt)

        Executor error:
        \(error)

        Available intents (use ONLY these names and slot values):
        \(voiceIntentCatalogText())

        Return ONLY a corrected JSON object like:
        {"intent":"distribute","slots":{"app":"iTerm2"},"reasoning":"four terminals into a grid"}

        Rules:
        - Use ONLY intent names and slot values listed above. Never repeat the rejected value.
        - For slots marked with {a|b|c}, the value MUST be exactly one of those tokens.
        - Include all required slots (marked with *).
        - If the request truly cannot be mapped, return {"intent":"unknown"}.
        """
    }

    private func assistantKnowledgeBrief() -> String {
        assistantContextJSON()
    }

    private func assistantContextJSON() -> String {
        let payload = assistantContextPayload()
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return #"{"error":"context unavailable"}"#
        }
        return text
    }

    private func assistantContextPayload() -> [String: Any] {
        let prefs = Preferences.shared
        MouseShortcutStore.shared.reloadIfNeeded()

        return [
            "assistant": [
                "name": "Workspace Assistant",
                "selectedProvider": [
                    "id": authProviderID,
                    "name": currentProvider.name,
                    "credential": selectedCredentialSummary,
                ],
                "providerRuntime": [
                    "binary": (piBinaryPath as Any?) ?? NSNull(),
                    "node": (nodeBinaryPath as Any?) ?? NSNull(),
                    "authFile": authFileURL.path,
                    "chatSession": chatSessionDirURL.path,
                ],
            ],
            "currentSettings": [
                "terminal": prefs.terminal.rawValue,
                "detachMode": prefs.mode.rawValue,
                "scanRoot": prefs.scanRoot.isEmpty ? NSNull() : prefs.scanRoot,
                "dragToSnap": prefs.dragSnapEnabled,
                "companionBridge": prefs.companionBridgeEnabled,
                "companionTrackpad": prefs.companionTrackpadEnabled,
                "ocr": [
                    "enabled": prefs.ocrEnabled,
                    "accuracy": prefs.ocrAccuracy,
                    "quickIntervalSeconds": prefs.ocrQuickInterval,
                    "deepIntervalSeconds": prefs.ocrDeepInterval,
                    "quickWindowLimit": prefs.ocrQuickLimit,
                    "deepWindowLimit": prefs.ocrDeepLimit,
                    "deepScanBudget": prefs.ocrDeepBudget,
                ],
                "mouseShortcuts": mouseShortcutContextPayload(),
            ],
            "settingsCatalog": [
                [
                    "id": "terminal",
                    "type": "enum",
                    "choices": Terminal.allCases.map(\.rawValue),
                    "installedChoices": Terminal.installed.map(\.rawValue),
                    "description": "Terminal app used when Lattices launches workspaces.",
                ],
                [
                    "id": "detachMode",
                    "type": "enum",
                    "choices": ["learning", "auto"],
                    "description": "Learning mode shows tmux hints; auto mode stays quieter.",
                ],
                [
                    "id": "scanRoot",
                    "type": "path",
                    "description": "Root directory scanned for projects containing .lattices.json.",
                ],
                [
                    "id": "dragToSnap",
                    "type": "boolean",
                    "description": "Enables drag-to-snap window zones.",
                ],
                [
                    "id": "mouseShortcuts",
                    "type": "boolean-plus-json-rules",
                    "description": "Middle-click and drag gesture shortcuts controlled by mouseGestures.enabled plus ~/.lattices/mouse-shortcuts.json.",
                ],
                [
                    "id": "ocr",
                    "type": "object",
                    "description": "Screen text recognition settings, including enablement, cadence, and accuracy.",
                ],
                [
                    "id": "assistantProvider",
                    "type": "enum-plus-api-key",
                    "choices": ["openai", "groq", "openrouter", "minimax"],
                    "description": "Provider-backed inference for chat and voice.",
                ],
            ],
            "settingsFiles": [
                "workspace": "\(NSHomeDirectory())/.lattices/workspace.json",
                "mouseShortcuts": MouseShortcutStore.shared.configURL.path,
                "mouseShortcutsHistory": MouseShortcutStore.shared.historyDirectoryURL.path,
                "snapZones": "\(NSHomeDirectory())/.lattices/snap-zones.json",
                "ocrDatabase": "\(NSHomeDirectory())/.lattices/ocr.db",
                "diagnostics": "\(NSHomeDirectory())/.lattices/lattices.log",
            ],
            "cliCommands": [
                "lattices",
                "lattices init",
                "lattices sync",
                "lattices restart [pane]",
                "lattices tile <position>",
                "lattices group [id]",
                "lattices layer [name|index]",
                "lattices windows --json",
                "lattices search <query>",
                "lattices app restart",
            ],
            "runtimeSnapshot": [
                "installedTerminals": Terminal.installed.map(\.rawValue),
                "discoveredProjectCount": ProjectScanner.shared.projects.count,
            ],
        ]
    }

    private func mouseShortcutContextPayload() -> [String: Any] {
        let prefs = Preferences.shared
        let store = MouseShortcutStore.shared
        store.reloadIfNeeded()

        return [
            "enabled": prefs.mouseGesturesEnabled,
            "configFile": store.configURL.path,
            "historyDirectory": store.historyDirectoryURL.path,
            "recentHistory": store.historySummaryLines,
            "tuning": [
                "dragThresholdPx": Double(store.tuning.dragThreshold),
                "holdTolerancePx": Double(store.tuning.holdTolerance),
                "axisBias": Double(store.tuning.axisBias),
            ],
            "activeMappings": store.enabledRules.map { rule in
                [
                    "id": rule.id,
                    "trigger": rule.trigger.displayLabel,
                    "action": rule.action.label,
                    "summary": rule.summary,
                ]
            },
        ]
    }

    private func settingsSummary() -> String {
        let prefs = Preferences.shared
        return """
        Current settings:
        Terminal: \(prefs.terminal.rawValue)
        Detach mode: \(prefs.mode.rawValue)
        Scan root: \(prefs.scanRoot.isEmpty ? "not set" : prefs.scanRoot)
        Drag-to-snap: \(prefs.dragSnapEnabled ? "on" : "off")
        Mouse gestures: \(prefs.mouseGesturesEnabled ? "on" : "off")
        Companion bridge: \(prefs.companionBridgeEnabled ? "on" : "off")
        Companion trackpad: \(prefs.companionTrackpadEnabled ? "on" : "off")
        OCR: \(prefs.ocrEnabled ? "on" : "off"), \(prefs.ocrAccuracy)
        Voice assistant: same provider as chat, \(currentProvider.name)

        \(mouseShortcutSummary())
        """
    }

    private func mouseShortcutSummary() -> String {
        let prefs = Preferences.shared
        let store = MouseShortcutStore.shared
        store.reloadIfNeeded()
        let mappings = store.summaryLines
        let mappingText = mappings.isEmpty
            ? "- No active mouse shortcut mappings."
            : mappings.map { "- \($0)" }.joined(separator: "\n")

        return """
        Mouse shortcuts:
        - Middle-click shortcuts are \(prefs.mouseGesturesEnabled ? "enabled" : "disabled").
        - Config file: \(store.configURL.path)
        - History: \(store.historyDirectoryURL.path)
        - Drag threshold: \(Int(store.tuning.dragThreshold)) px; hold tolerance: \(Int(store.tuning.holdTolerance)) px; axis bias: \(String(format: "%.1f", Double(store.tuning.axisBias))).
        Active mappings:
        \(mappingText)
        """
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

    private func settingsHelpText() -> String {
        """
        I can manage Lattices settings from chat. Try:
        - set terminal to Ghostty
        - set scan root to ~/dev
        - turn OCR off
        - set OCR accuracy to fast
        - enable drag snap
        - disable mouse gestures
        - set detach mode to auto
        - open assistant settings
        - open settings
        """
    }

    private func parseTerminal(from lower: String) -> Terminal? {
        let aliases: [(Terminal, [String])] = [
            (.iterm2, ["iterm2", "iterm"]),
            (.warp, ["warp"]),
            (.ghostty, ["ghostty"]),
            (.kitty, ["kitty"]),
            (.alacritty, ["alacritty"]),
            (.terminal, ["terminal.app", "apple terminal", "terminal"]),
        ]

        return aliases.first { _, names in
            names.contains { lower.contains($0) }
        }?.0
    }

    /// Questions and status checks should reach the provider with structured context.
    private func isInformationalSettingsQuery(_ lower: String) -> Bool {
        if lower.contains("?") {
            return true
        }

        let markers = [
            "can you take a look",
            "can you look",
            "could you look",
            "take a look",
            "look at ",
            "what are ",
            "what is ",
            "what's ",
            "which ",
            "how do ",
            "how are ",
            "tell me ",
            "show me ",
            "list ",
            "describe ",
            "explain ",
            "currently ",
            "right now",
            "at the moment",
            "do i have ",
            "are there ",
            "is there ",
            "am i using ",
        ]
        return markers.contains { lower.contains($0) }
    }

    private func isSettingsMutationIntent(_ lower: String) -> Bool {
        !isInformationalSettingsQuery(lower)
            && (
                lower.contains("set ")
                || lower.contains("update ")
                || lower.contains("configure ")
                || lower.contains("switch to ")
                || lower.contains("change ")
                || lower.contains("use ")
                || lower.hasPrefix("enable ")
                || lower.hasPrefix("disable ")
                || lower.contains(" turn on ")
                || lower.contains(" turn off ")
                || lower.contains("turn on ")
                || lower.contains("turn off ")
            )
    }

    private func parseBooleanMutation(from lower: String) -> Bool? {
        guard isSettingsMutationIntent(lower) else { return nil }

        let offTokens = ["turn off", "disable", "switch off"]
        if offTokens.contains(where: lower.contains) {
            return false
        }

        let onTokens = ["turn on", "enable", "switch on"]
        if onTokens.contains(where: lower.contains) {
            return true
        }

        return nil
    }

    private func isMouseShortcutRuleRequest(_ lower: String) -> Bool {
        let ruleMarkers = [
            " back button",
            " forward button",
            " middle button",
            "button.",
            "button ",
            "swipe",
            "slide",
            "drag up",
            "drag down",
            "drag left",
            "drag right",
            "map ",
            "mapping",
            "bind ",
            "assign ",
            "rule",
            "dictation",
            "transcription",
            "enter",
            "shortcut.send",
            "dictation.start",
        ]
        return ruleMarkers.contains { lower.contains($0) }
    }

    private func extractPathValue(from text: String) -> String? {
        let markers = [" to ", " at ", " root "]
        let lower = text.lowercased()

        for marker in markers {
            guard let range = lower.range(of: marker) else { continue }
            let raw = text[range.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
            guard !raw.isEmpty else { continue }
            return (raw as NSString).expandingTildeInPath
        }

        return nil
    }

    private func extractFirstNumber(from text: String) -> Double? {
        let pattern = #"(?<![A-Za-z0-9_])\$?([0-9]+(?:\.[0-9]+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Double(text[range])
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
            return "This provider is not connected yet. Open Settings with the gear icon, connect \(currentProvider.name), then come back and send your first prompt."
        }

        return "This provider still needs an API key. Open Settings with the gear icon, save your \(currentProvider.tokenLabel.lowercased()), and then try again."
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
        let scopedPackageRoot = packageRoot.deletingLastPathComponent()
        let nodeModulesRoot = scopedPackageRoot.lastPathComponent.hasPrefix("@")
            ? scopedPackageRoot.deletingLastPathComponent()
            : scopedPackageRoot
        let packageNames = resolvePiAiPackageNames(from: packageRoot)

        var piAiRoots: [URL] = []
        var seenRoots: Set<String> = []
        for nodeModulesURL in [
            packageRoot.appendingPathComponent("node_modules"),
            nodeModulesRoot,
        ] {
            for packageName in packageNames {
                let root = nodePackageURL(named: packageName, in: nodeModulesURL)
                guard seenRoots.insert(root.path).inserted else { continue }
                piAiRoots.append(root)
            }
        }

        for piAiRoot in piAiRoots {
            let moduleURL = piAiRoot.appendingPathComponent("dist/oauth.js")
            if FileManager.default.fileExists(atPath: moduleURL.path) {
                return moduleURL
            }
        }

        return nil
    }

    private func resolvePiAiPackageNames(from packageRoot: URL) -> [String] {
        var names: [String] = []
        var seen: Set<String> = []

        func appendName(_ name: String) {
            guard !name.isEmpty, seen.insert(name).inserted else { return }
            names.append(name)
        }

        let packageJSON = packageRoot.appendingPathComponent("package.json")
        if let data = try? Data(contentsOf: packageJSON),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["dependencies", "optionalDependencies", "peerDependencies", "devDependencies"] {
                guard let dependencies = json[key] as? [String: Any] else { continue }
                for packageName in dependencies.keys.sorted() {
                    if packageName == "pi-ai" || packageName.hasSuffix("/pi-ai") {
                        appendName(packageName)
                    }
                }
            }
        }

        return names
    }

    private func nodePackageURL(named packageName: String, in nodeModulesURL: URL) -> URL {
        packageName
            .split(separator: "/")
            .reduce(nodeModulesURL) { url, component in
                url.appendingPathComponent(String(component))
            }
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
        chatSessionDirURL.deletingLastPathComponent().appendingPathComponent("oauth-runtime.json")
    }
}
