import Foundation
import Network

final class DaemonServer: ObservableObject {
    static let shared = DaemonServer()

    @Published var clientCount: Int = 0

    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    private let queue = DispatchQueue(label: "lattice.daemon", qos: .userInitiated)
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func start() {
        let diag = DiagnosticLog.shared

        // WebSocket options
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true

        // Build TCP params with WebSocket protocol
        let params = NWParameters(tls: nil)
        let tcpOptions = NWProtocolTCP.Options()
        params.defaultProtocolStack.transportProtocol = tcpOptions
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        // Bind to localhost only
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: 9399)

        do {
            listener = try NWListener(using: params)
        } catch {
            diag.error("DaemonServer: failed to create listener — \(error.localizedDescription)")
            return
        }

        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                diag.success("DaemonServer: listening on ws://127.0.0.1:9399")
            case .failed(let err):
                diag.error("DaemonServer: listener failed — \(err.localizedDescription)")
            case .cancelled:
                diag.info("DaemonServer: listener cancelled")
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }

        listener?.start(queue: queue)

        // Subscribe to EventBus for broadcasting
        EventBus.shared.subscribe { [weak self] event in
            self?.broadcastEvent(event)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for (_, conn) in connections {
            conn.cancel()
        }
        connections.removeAll()
        DispatchQueue.main.async { self.clientCount = 0 }
    }

    func broadcast(_ event: DaemonEvent) {
        guard let data = try? encoder.encode(event) else { return }
        let meta = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "event", metadata: [meta])
        for (_, conn) in connections {
            conn.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
        }
    }

    // MARK: - Connection Handling

    private func handleNewConnection(_ connection: NWConnection) {
        let id = UUID()
        let diag = DiagnosticLog.shared

        connections[id] = connection
        DispatchQueue.main.async { self.clientCount = self.connections.count }
        diag.info("DaemonServer: client connected (\(connections.count) total)")

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receiveLoop(id: id, connection: connection)
            case .failed, .cancelled:
                self?.removeConnection(id)
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func removeConnection(_ id: UUID) {
        connections.removeValue(forKey: id)
        DispatchQueue.main.async { self.clientCount = self.connections.count }
        DiagnosticLog.shared.info("DaemonServer: client disconnected (\(connections.count) total)")
    }

    private func receiveLoop(id: UUID, connection: NWConnection) {
        connection.receiveMessage { [weak self] data, context, _, error in
            guard let self else { return }

            if let error {
                DiagnosticLog.shared.warn("DaemonServer: receive error — \(error.localizedDescription)")
                self.removeConnection(id)
                return
            }

            if let data, !data.isEmpty {
                self.handleMessage(data, connection: connection)
            }

            // Continue receiving
            if self.connections[id] != nil {
                self.receiveLoop(id: id, connection: connection)
            }
        }
    }

    private func handleMessage(_ data: Data, connection: NWConnection) {
        guard let request = try? decoder.decode(DaemonRequest.self, from: data) else {
            let errResponse = DaemonResponse(id: "?", result: nil, error: "Invalid request JSON")
            sendResponse(errResponse, on: connection)
            return
        }

        let response = MessageRouter.handle(request)
        sendResponse(response, on: connection)
    }

    private func sendResponse(_ response: DaemonResponse, on connection: NWConnection) {
        guard let data = try? encoder.encode(response) else { return }
        let meta = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "response", metadata: [meta])
        connection.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
    }

    // MARK: - Event Broadcasting

    private func broadcastEvent(_ event: ModelEvent) {
        let daemonEvent: DaemonEvent
        switch event {
        case .windowsChanged(let windows, let added, let removed):
            daemonEvent = DaemonEvent(
                event: "windows.changed",
                data: .object([
                    "windowCount": .int(windows.count),
                    "added": .array(added.map { .int(Int($0)) }),
                    "removed": .array(removed.map { .int(Int($0)) })
                ])
            )
        case .tmuxChanged(let sessions):
            daemonEvent = DaemonEvent(
                event: "tmux.changed",
                data: .object([
                    "sessionCount": .int(sessions.count),
                    "sessions": .array(sessions.map { .string($0.name) })
                ])
            )
        case .layerSwitched(let index):
            daemonEvent = DaemonEvent(
                event: "layer.switched",
                data: .object(["index": .int(index)])
            )
        }
        broadcast(daemonEvent)
    }
}
