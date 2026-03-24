import AppKit

/// WebSocket JSON-RPC client for the Vox transcription runtime.
///
/// Vox is a local-first transcription daemon (voxd) that runs on a configurable port
/// (default 42137). Service discovery is file-based via ~/.vox/runtime.json.
///
/// Key differences from the old Talkie integration:
///   - Discovery: ~/.vox/runtime.json (not ~/.talkie/services.json)
///   - Port: 42137 (not 19823)
///   - No distributed notifications — poll runtime.json or check on demand
///   - API: transcribe.startSession/stopSession (not startDictation/stopDictation)
///   - No register call — pass clientId per request
///   - All session events flow on the startSession call ID
final class VoxClient: ObservableObject {
    static let shared = VoxClient()

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case unavailable(reason: String)
    }

    @Published var connectionState: ConnectionState = .disconnected

    static let clientId = "lattices"

    private var pendingCalls: [String: PendingCall] = [:]
    private var eventHandler: ((String, [String: Any]) -> Void)?
    private var reconnectDelay: TimeInterval = 0.5
    private var reconnectTimer: DispatchSourceTimer?
    private var heartbeatTimer: DispatchSourceTimer?
    private var intentionalDisconnect = false
    private let queue = DispatchQueue(label: "com.lattices.vox-client")

    private struct PendingCall {
        let completion: (Result<[String: Any], VoxError>) -> Void
        let onProgress: ((String, [String: Any]) -> Void)?
        let timer: DispatchSourceTimer?
    }

    enum VoxError: LocalizedError {
        case notConnected
        case callFailed(String)
        case timeout(String)
        case sessionBusy
        case connectionDropped
        case daemonNotRunning

        var errorDescription: String? {
            switch self {
            case .notConnected: return "Not connected to Vox"
            case .callFailed(let msg): return msg
            case .timeout(let method): return "Call to '\(method)' timed out"
            case .sessionBusy: return "A live session is already active"
            case .connectionDropped: return "Connection to Vox dropped"
            case .daemonNotRunning: return "Vox daemon not running — start with 'vox daemon start'"
            }
        }
    }

    // MARK: - Service Discovery (file-based via ~/.vox/runtime.json)

    private static let defaultPort: UInt16 = 42137
    private static let runtimePath = NSHomeDirectory() + "/.vox/runtime.json"

    struct RuntimeInfo {
        let port: UInt16
        let pid: Int
        let version: String
    }

    /// Read ~/.vox/runtime.json and check if the daemon is alive.
    func discoverDaemon() -> RuntimeInfo? {
        guard let data = FileManager.default.contents(atPath: Self.runtimePath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let port = json["port"] as? Int,
              let pid = json["pid"] as? Int else {
            return nil
        }

        // Verify the PID is still alive
        let alive = kill(Int32(pid), 0) == 0
        guard alive else {
            DiagnosticLog.shared.warn("VoxClient: stale runtime.json — pid \(pid) not running")
            return nil
        }

        let version = json["version"] as? String ?? "unknown"
        return RuntimeInfo(port: UInt16(port), pid: pid, version: version)
    }

    // MARK: - Connection

    func connect() {
        if connectionState == .connected || connectionState == .connecting { return }

        intentionalDisconnect = false

        guard let runtime = discoverDaemon() else {
            DiagnosticLog.shared.warn("VoxClient: daemon not found — check ~/.vox/runtime.json")
            DispatchQueue.main.async {
                self.connectionState = .unavailable(reason: "Vox daemon not running")
            }
            return
        }

        DiagnosticLog.shared.info("VoxClient: discovered daemon v\(runtime.version) on port \(runtime.port) (pid \(runtime.pid))")
        connectToPort(runtime.port)
    }

    func disconnect() {
        intentionalDisconnect = true
        reconnectTimer?.cancel()
        reconnectTimer = nil
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        wsTask?.cancel(with: .goingAway, reason: nil)
        wsTask = nil
        wsSession?.invalidateAndCancel()
        wsSession = nil
        pendingCalls.removeAll()
        DispatchQueue.main.async {
            self.connectionState = .disconnected
        }
    }

    /// Force a full disconnect + reconnect cycle.
    func reconnect() {
        DiagnosticLog.shared.info("VoxClient: forced reconnect requested")
        disconnect()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.connect()
        }
    }

    private var wsTask: URLSessionWebSocketTask?
    private var wsSession: URLSession?

    private func connectToPort(_ port: UInt16) {
        DispatchQueue.main.async {
            self.connectionState = .connecting
        }

        let connectStart = Date()
        DiagnosticLog.shared.info("VoxClient: connecting to ws://127.0.0.1:\(port)")

        let url = URL(string: "ws://127.0.0.1:\(port)")!
        let config = URLSessionConfiguration.default
        config.connectionProxyDictionary = [:]
        let session = URLSession(configuration: config)
        let task = session.webSocketTask(with: url)

        self.wsSession = session
        self.wsTask = task
        task.resume()

        // Verify with a health check instead of raw ping
        task.sendPing { [weak self] error in
            guard let self else { return }
            let ms = Int(Date().timeIntervalSince(connectStart) * 1000)
            if let error {
                DiagnosticLog.shared.warn("VoxClient: WebSocket ping failed (\(ms)ms) — \(error)")
                self.handleDisconnect()
            } else {
                self.reconnectDelay = 0.5
                DiagnosticLog.shared.info("VoxClient: connected on port \(port) (\(ms)ms)")
                self.receiveLoop()
                self.startHeartbeat()
                DispatchQueue.main.async {
                    self.connectionState = .connected
                }
                // Verify with a health RPC
                self.call(method: "health") { result in
                    switch result {
                    case .success(let data):
                        let svc = data["serviceName"] as? String ?? "?"
                        let ver = data["version"] as? String ?? "?"
                        DiagnosticLog.shared.info("VoxClient: health OK — \(svc) v\(ver)")
                    case .failure(let error):
                        DiagnosticLog.shared.warn("VoxClient: health check failed — \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    /// Periodic WebSocket ping every 30s to detect dead connections early.
    private func startHeartbeat() {
        heartbeatTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 30, repeating: 30)
        timer.setEventHandler { [weak self] in
            guard let self, let task = self.wsTask else { return }
            task.sendPing { error in
                if let error {
                    DiagnosticLog.shared.warn("VoxClient: heartbeat failed — \(error)")
                    self.handleDisconnect()
                }
            }
        }
        timer.resume()
        heartbeatTimer = timer
    }

    private func handleDisconnect() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        wsTask?.cancel(with: .goingAway, reason: nil)
        wsTask = nil

        for (_, pending) in pendingCalls {
            pending.timer?.cancel()
            pending.completion(.failure(.connectionDropped))
        }
        pendingCalls.removeAll()

        DispatchQueue.main.async {
            self.connectionState = .disconnected
        }

        guard !intentionalDisconnect else { return }

        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, 10)
        DiagnosticLog.shared.info("VoxClient: reconnecting in \(delay)s")

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + delay)
        timer.setEventHandler { [weak self] in
            self?.connect()
        }
        timer.resume()
        reconnectTimer = timer
    }

    // MARK: - WebSocket I/O

    private func receiveLoop() {
        guard let task = wsTask else { return }

        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text): self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) { self.handleMessage(text) }
                @unknown default: break
                }
                self.receiveLoop()
            case .failure(let error):
                DiagnosticLog.shared.warn("VoxClient: receive error — \(error)")
                self.handleDisconnect()
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // Match by request ID
        if let id = json["id"] as? String, let pending = pendingCalls.removeValue(forKey: id) {
            pending.timer?.cancel()

            // Streaming event — has "event" key alongside "id"
            if let event = json["event"] as? String {
                let eventData = json["data"] as? [String: Any] ?? [:]
                pending.onProgress?(event, eventData)
                // Re-add — still pending until final result/error
                pendingCalls[id] = pending
                return
            }

            // Final result or error
            if let errorStr = json["error"] as? String {
                if errorStr == "live_session_busy" {
                    pending.completion(.failure(.sessionBusy))
                } else {
                    pending.completion(.failure(.callFailed(errorStr)))
                }
            } else {
                let result = json["result"] as? [String: Any] ?? [:]
                pending.completion(.success(result))
            }
            return
        }

        // Push event (no matching ID)
        if let event = json["event"] as? String {
            let eventData = json["data"] as? [String: Any] ?? [:]
            DispatchQueue.main.async {
                self.eventHandler?(event, eventData)
            }
        }
    }

    private func sendJSON(_ dict: [String: Any]) {
        guard let task = wsTask,
              let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else { return }

        task.send(.string(text)) { error in
            if let error {
                DiagnosticLog.shared.warn("VoxClient: send error — \(error)")
            }
        }
    }

    // MARK: - RPC (fire-and-forget and request-response)

    func call(method: String, params: [String: Any]? = nil, timeout: TimeInterval = 30,
              completion: @escaping (Result<[String: Any], VoxError>) -> Void) {
        guard wsTask != nil, connectionState == .connected else {
            completion(.failure(.notConnected))
            return
        }

        let id = UUID().uuidString
        var payload: [String: Any] = ["id": id, "method": method]
        if var p = params {
            // Inject clientId into all calls
            if p["clientId"] == nil { p["clientId"] = Self.clientId }
            payload["params"] = p
        } else {
            payload["params"] = ["clientId": Self.clientId]
        }

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

    /// Streaming RPC — receives progress events before the final result.
    /// Used for transcribe.startSession where events flow on the start call ID.
    func callStreaming(method: String, params: [String: Any]? = nil, timeout: TimeInterval = 120,
                       onProgress: @escaping (String, [String: Any]) -> Void,
                       completion: @escaping (Result<[String: Any], VoxError>) -> Void) {
        guard wsTask != nil, connectionState == .connected else {
            completion(.failure(.notConnected))
            return
        }

        let id = UUID().uuidString
        var payload: [String: Any] = ["id": id, "method": method]
        if var p = params {
            if p["clientId"] == nil { p["clientId"] = Self.clientId }
            payload["params"] = p
        } else {
            payload["params"] = ["clientId": Self.clientId]
        }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler { [weak self] in
            if let pending = self?.pendingCalls.removeValue(forKey: id) {
                pending.completion(.failure(.timeout(method)))
            }
        }
        timer.resume()

        pendingCalls[id] = PendingCall(completion: completion, onProgress: { event, data in
            timer.schedule(deadline: .now() + timeout) // Reset timeout on activity
            onProgress(event, data)
        }, timer: timer)

        sendJSON(payload)
    }

    func onServiceEvent(_ handler: @escaping (String, [String: Any]) -> Void) {
        eventHandler = handler
    }

    // MARK: - High-level session helpers

    /// Current active session ID, if any.
    @Published var activeSessionId: String?

    /// Start a live transcription session. Vox records from the mic and transcribes on stop.
    ///
    /// Events arrive on this call's ID:
    ///   - session.state: {state: "starting"|"recording"|"processing"|"done", sessionId, previous}
    ///   - session.final: {sessionId, text, words[], elapsedMs, metrics}
    func startSession(
        modelId: String = "parakeet:v3",
        onProgress: @escaping (String, [String: Any]) -> Void,
        completion: @escaping (Result<[String: Any], VoxError>) -> Void
    ) {
        callStreaming(
            method: "transcribe.startSession",
            params: ["modelId": modelId],
            onProgress: { [weak self] event, data in
                if event == "session.state", let sid = data["sessionId"] as? String {
                    DispatchQueue.main.async { self?.activeSessionId = sid }
                }
                onProgress(event, data)
            },
            completion: { [weak self] result in
                DispatchQueue.main.async { self?.activeSessionId = nil }
                completion(result)
            }
        )
    }

    /// Stop the current live session. The final transcript arrives via the startSession callback.
    func stopSession(completion: ((Result<[String: Any], VoxError>) -> Void)? = nil) {
        guard let sessionId = activeSessionId else {
            completion?(.failure(.callFailed("No active session")))
            return
        }
        call(method: "transcribe.stopSession", params: ["sessionId": sessionId]) { result in
            completion?(result)
        }
    }

    /// Cancel the current session without waiting for transcription.
    func cancelSession(completion: ((Result<[String: Any], VoxError>) -> Void)? = nil) {
        guard let sessionId = activeSessionId else {
            completion?(.failure(.callFailed("No active session")))
            return
        }
        call(method: "transcribe.cancelSession", params: ["sessionId": sessionId]) { result in
            completion?(result)
        }
    }

    /// Request model warm-up so first transcription is fast.
    func warmup(modelId: String = "parakeet:v3") {
        call(method: "warmup.start", params: ["modelId": modelId]) { result in
            switch result {
            case .success: DiagnosticLog.shared.info("VoxClient: warmup started")
            case .failure(let e): DiagnosticLog.shared.warn("VoxClient: warmup failed — \(e.localizedDescription)")
            }
        }
    }

    // MARK: - Init

    private init() {
        // No distributed notifications for Vox — discovery is file-based.
        // We connect on demand when voice mode activates.
    }
}
