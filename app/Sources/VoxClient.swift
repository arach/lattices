import AppKit

/// WebSocket JSON-RPC client for connecting to TalkieAgent.
/// Handles service discovery, persistent connection, auto-reconnect,
/// and streaming dictation sessions.
final class TalkieClient: ObservableObject {
    static let shared = TalkieClient()

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case unavailable(reason: String)
    }

    @Published var connectionState: ConnectionState = .disconnected

    private var pendingCalls: [String: PendingCall] = [:]
    private var eventHandler: ((String, [String: Any]) -> Void)?
    private var reconnectDelay: TimeInterval = 0.5
    private var reconnectTimer: DispatchSourceTimer?
    private var intentionalDisconnect = false
    private let queue = DispatchQueue(label: "com.lattices.talkie-client")

    private struct PendingCall {
        let completion: (Result<[String: Any], TalkieError>) -> Void
        let onProgress: ((String, [String: Any]) -> Void)?
        let timer: DispatchSourceTimer?
    }

    enum TalkieError: LocalizedError {
        case notConnected
        case callFailed(String)
        case timeout(String)
        case micBusy(owner: String)
        case connectionDropped

        var errorDescription: String? {
            switch self {
            case .notConnected: return "Not connected to TalkieAgent"
            case .callFailed(let msg): return msg
            case .timeout(let method): return "Call to '\(method)' timed out"
            case .micBusy(let owner): return "Mic in use by \(owner)"
            case .connectionDropped: return "Connection to TalkieAgent dropped"
            }
        }
    }

    // MARK: - Service Discovery

    private static let defaultAgentPort: UInt16 = 19823
    private static let servicesPath = NSHomeDirectory() + "/.talkie/services.json"
    private static let talkieAppPath = "/Applications/Talkie.app"

    enum TalkieAvailability {
        case notInstalled
        case installedNotRunning
        case running(port: UInt16)
    }

    func discoverAgent() -> TalkieAvailability {
        // Try services.json first
        if let data = FileManager.default.contents(atPath: Self.servicesPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Support both flat and versioned format
            let services = (json["services"] as? [String: Any]) ?? json
            if let agent = services["agent"] as? [String: Any],
               let port = agent["port"] as? Int {
                return .running(port: UInt16(port))
            }
        }

        // Check if Talkie is installed — fall back to default port
        if FileManager.default.fileExists(atPath: Self.talkieAppPath) ||
           FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.talkie") {
            // services.json may not exist yet — try the default port
            return .running(port: Self.defaultAgentPort)
        }

        return .notInstalled
    }

    // MARK: - Connection

    func connect() {
        // Don't replace an active or in-progress connection
        if connectionState == .connected || connectionState == .connecting { return }

        intentionalDisconnect = false

        let availability = discoverAgent()
        DiagnosticLog.shared.info("TalkieClient: discovery result — \(availability)")
        switch availability {
        case .notInstalled:
            DispatchQueue.main.async {
                self.connectionState = .unavailable(reason: "Talkie not installed")
            }
            return

        case .installedNotRunning:
            DispatchQueue.main.async {
                self.connectionState = .unavailable(reason: "Talkie not running")
            }
            // Try launching
            launchTalkie()
            return

        case .running(let port):
            connectToPort(port)
        }
    }

    func disconnect() {
        intentionalDisconnect = true
        reconnectTimer?.cancel()
        reconnectTimer = nil
        wsTask?.cancel(with: .goingAway, reason: nil)
        wsTask = nil
        wsSession?.invalidateAndCancel()
        wsSession = nil
        pendingCalls.removeAll()
        DispatchQueue.main.async {
            self.connectionState = .disconnected
        }
    }

    private var wsTask: URLSessionWebSocketTask?
    private var wsSession: URLSession?

    private func connectToPort(_ port: UInt16) {
        DispatchQueue.main.async {
            self.connectionState = .connecting
        }

        let connectStart = Date()
        DiagnosticLog.shared.info("TalkieClient: connecting to ws://127.0.0.1:\(port)")

        let url = URL(string: "ws://127.0.0.1:\(port)")!
        // Skip proxy/DNS lookup for localhost — shaves ~100ms
        let config = URLSessionConfiguration.default
        config.connectionProxyDictionary = [:]
        let session = URLSession(configuration: config)
        let task = session.webSocketTask(with: url)

        self.wsSession = session
        self.wsTask = task

        task.resume()

        // Verify connection with a single WebSocket ping
        task.sendPing { [weak self] error in
            guard let self else { return }
            let ms = Int(Date().timeIntervalSince(connectStart) * 1000)
            if let error {
                DiagnosticLog.shared.warn("TalkieClient: WebSocket ping failed (\(ms)ms) — \(error)")
                self.handleDisconnect()
            } else {
                self.reconnectDelay = 0.5
                DispatchQueue.main.async {
                    self.connectionState = .connected
                }
                DiagnosticLog.shared.info("TalkieClient: connected to TalkieAgent on port \(port) (\(ms)ms)")
                self.receiveLoop()
            }
        }
    }

    private func handleDisconnect() {
        wsTask?.cancel(with: .goingAway, reason: nil)
        wsTask = nil

        // Cancel all pending calls
        for (_, pending) in pendingCalls {
            pending.timer?.cancel()
            pending.completion(.failure(.connectionDropped))
        }
        pendingCalls.removeAll()

        DispatchQueue.main.async {
            self.connectionState = .disconnected
        }

        guard !intentionalDisconnect else { return }

        // Auto-reconnect with exponential backoff
        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, 10)

        DiagnosticLog.shared.info("TalkieClient: reconnecting in \(delay)s")

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + delay)
        timer.setEventHandler { [weak self] in
            self?.connect()
        }
        timer.resume()
        reconnectTimer = timer
    }

    private func launchTalkie() {
        guard FileManager.default.fileExists(atPath: Self.talkieAppPath) else { return }

        DiagnosticLog.shared.info("TalkieClient: launching Talkie.app")
        NSWorkspace.shared.open(URL(fileURLWithPath: Self.talkieAppPath))

        // Listen for live.ready notification
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.jdi.talkie.agent.live.ready"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            var port = Self.defaultAgentPort

            if let info = notification.userInfo,
               let agentPort = info["agentPort"] as? Int {
                port = UInt16(agentPort)
            }

            DiagnosticLog.shared.info("TalkieClient: Talkie came online on port \(port)")
            self.connectToPort(port)
        }

        // Timeout after 10s
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self else { return }
            if case .unavailable = self.connectionState {
                // Still not connected — give up on auto-launch
                DiagnosticLog.shared.warn("TalkieClient: Talkie launch timed out")
            }
        }
    }

    // MARK: - WebSocket I/O

    private func receiveLoop() {
        guard let task = wsTask else { return }

        task.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                // Continue receiving
                self.receiveLoop()

            case .failure(let error):
                DiagnosticLog.shared.warn("TalkieClient: receive error — \(error)")
                self.handleDisconnect()
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // Response to a pending call (has "id")
        if let id = json["id"] as? String, let pending = pendingCalls.removeValue(forKey: id) {
            pending.timer?.cancel()

            // Check for progress event (has both "id" and "event")
            if let event = json["event"] as? String {
                let eventData = json["data"] as? [String: Any] ?? [:]
                pending.onProgress?(event, eventData)
                // Re-add — still pending until we get result/error
                pendingCalls[id] = pending
                return
            }

            if let errorStr = json["error"] as? String {
                // Parse mic_busy error
                if errorStr.hasPrefix("mic_busy") {
                    let owner = errorStr.contains(":") ? String(errorStr.split(separator: ":").last ?? "unknown") : "unknown"
                    pending.completion(.failure(.micBusy(owner: owner)))
                } else {
                    pending.completion(.failure(.callFailed(errorStr)))
                }
            } else {
                let result = json["result"] as? [String: Any] ?? [:]
                pending.completion(.success(result))
            }
            return
        }

        // Push event (has "event" but no "id")
        if let event = json["event"] as? String {
            let eventData = json["data"] as? [String: Any] ?? [:]
            DispatchQueue.main.async {
                self.eventHandler?(event, eventData)
            }
        }
    }

    private func sendJSON(_ dict: [String: Any]) {
        guard let task = wsTask else { return }

        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else { return }

        task.send(.string(text)) { error in
            if let error {
                DiagnosticLog.shared.warn("TalkieClient: send error — \(error)")
            }
        }
    }

    // MARK: - RPC

    func ping(completion: @escaping (Bool) -> Void) {
        call(method: "ping") { result in
            switch result {
            case .success: completion(true)
            case .failure: completion(false)
            }
        }
    }

    func call(method: String, params: [String: Any]? = nil, timeout: TimeInterval = 30, completion: @escaping (Result<[String: Any], TalkieError>) -> Void) {
        guard wsTask != nil, connectionState == .connected else {
            completion(.failure(.notConnected))
            return
        }

        let id = UUID().uuidString
        var payload: [String: Any] = ["id": id, "method": method]
        if let params { payload["params"] = params }

        // Timeout timer
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler { [weak self] in
            if let pending = self?.pendingCalls.removeValue(forKey: id) {
                pending.completion(.failure(.timeout(method)))
            }
        }
        timer.resume()

        pendingCalls[id] = PendingCall(completion: completion, onProgress: nil, timer: timer)
        sendJSON(payload)
    }

    func callStreaming(method: String, params: [String: Any]? = nil, timeout: TimeInterval = 120, onProgress: @escaping (String, [String: Any]) -> Void, completion: @escaping (Result<[String: Any], TalkieError>) -> Void) {
        guard wsTask != nil, connectionState == .connected else {
            completion(.failure(.notConnected))
            return
        }

        let id = UUID().uuidString
        var payload: [String: Any] = ["id": id, "method": method]
        if let params { payload["params"] = params }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler { [weak self] in
            if let pending = self?.pendingCalls.removeValue(forKey: id) {
                pending.completion(.failure(.timeout(method)))
            }
        }
        timer.resume()

        pendingCalls[id] = PendingCall(completion: completion, onProgress: { event, data in
            // Reset timeout on progress
            timer.schedule(deadline: .now() + timeout)
            onProgress(event, data)
        }, timer: timer)

        sendJSON(payload)
    }

    func onServiceEvent(_ handler: @escaping (String, [String: Any]) -> Void) {
        eventHandler = handler
    }

    // MARK: - Init

    private init() {
        // Listen for Talkie coming online
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.jdi.talkie.agent.live.ready"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard case .disconnected = self.connectionState else { return }
            guard case .unavailable = self.connectionState else { return }

            var port = Self.defaultAgentPort
            if let info = notification.userInfo,
               let agentPort = info["agentPort"] as? Int {
                port = UInt16(agentPort)
            }
            self.connectToPort(port)
        }
    }
}
