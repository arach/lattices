import Foundation
import CommonCrypto

// MARK: - POSIX WebSocket Server
// NWListener is broken on macOS 26 (Tahoe) — EINVAL on any listener creation.
// This is a minimal POSIX-socket WebSocket server on 127.0.0.1:9399.

final class DaemonServer: ObservableObject {
    static let shared = DaemonServer()

    @Published var clientCount: Int = 0
    @Published var isListening: Bool = false

    private var serverFd: Int32 = -1
    private var clients: [UUID: WebSocketClient] = [:]
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "lattices.daemon", qos: .userInitiated)
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var acceptSource: DispatchSourceRead?

    func start() {
        let diag = DiagnosticLog.shared

        // 1. Create TCP socket
        serverFd = socket(AF_INET, SOCK_STREAM, 0)
        guard serverFd >= 0 else {
            diag.error("DaemonServer: socket() failed — errno \(errno)")
            return
        }

        // SO_REUSEADDR so we can restart quickly
        var yes: Int32 = 1
        setsockopt(serverFd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        // 2. Bind to 127.0.0.1:9399
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(9399).bigEndian
        addr.sin_addr.s_addr = UInt32(0x7f000001).bigEndian // 127.0.0.1

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverFd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            diag.error("DaemonServer: bind() failed — errno \(errno)")
            close(serverFd)
            serverFd = -1
            return
        }

        // 3. Listen
        guard listen(serverFd, 8) == 0 else {
            diag.error("DaemonServer: listen() failed — errno \(errno)")
            close(serverFd)
            serverFd = -1
            return
        }

        // Non-blocking
        let flags = fcntl(serverFd, F_GETFL)
        _ = fcntl(serverFd, F_SETFL, flags | O_NONBLOCK)

        // 4. GCD dispatch source for accepting connections
        let source = DispatchSource.makeReadSource(fileDescriptor: serverFd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptConnection() }
        source.setCancelHandler { [weak self] in
            if let fd = self?.serverFd, fd >= 0 { close(fd) }
            self?.serverFd = -1
        }
        source.resume()
        acceptSource = source

        DispatchQueue.main.async { self.isListening = true }
        diag.success("DaemonServer: listening on ws://127.0.0.1:9399")

        // Subscribe to EventBus for broadcasting
        EventBus.shared.subscribe { [weak self] event in
            self?.broadcastEvent(event)
        }
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        lock.lock()
        for (_, client) in clients {
            close(client.fd)
        }
        clients.removeAll()
        lock.unlock()
        DispatchQueue.main.async {
            self.clientCount = 0
            self.isListening = false
        }
    }

    func broadcast(_ event: DaemonEvent) {
        guard let data = try? encoder.encode(event),
              let text = String(data: data, encoding: .utf8) else { return }
        lock.lock()
        let snapshot = clients
        lock.unlock()
        for (_, client) in snapshot {
            sendWebSocketText(text, to: client)
        }
    }

    // MARK: - Accept

    private func acceptConnection() {
        var clientAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let clientFd = withUnsafeMutablePointer(to: &clientAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                accept(serverFd, $0, &addrLen)
            }
        }
        guard clientFd >= 0 else { return }

        // A client can disconnect immediately after a large response. On Darwin,
        // writing to that socket can otherwise raise SIGPIPE and terminate the app.
        var noSigPipe: Int32 = 1
        setsockopt(clientFd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        let id = UUID()
        let client = WebSocketClient(id: id, fd: clientFd)

        // Read the HTTP upgrade request
        queue.async { [weak self] in
            self?.performHandshake(client: client)
        }
    }

    // MARK: - WebSocket Handshake

    private func performHandshake(client: WebSocketClient) {
        let diag = DiagnosticLog.shared

        // Ensure blocking mode for handshake read
        let curFlags = fcntl(client.fd, F_GETFL)
        if curFlags & O_NONBLOCK != 0 {
            _ = fcntl(client.fd, F_SETFL, curFlags & ~O_NONBLOCK)
        }

        // Read HTTP request (up to 4KB)
        var buf = [UInt8](repeating: 0, count: 4096)
        let n = read(client.fd, &buf, buf.count)
        guard n > 0 else {
            close(client.fd)
            return
        }

        let request = String(bytes: buf[..<n], encoding: .utf8) ?? ""

        // Extract Sec-WebSocket-Key
        guard let keyLine = request.split(separator: "\r\n").first(where: {
            $0.lowercased().hasPrefix("sec-websocket-key:")
        }) else {
            close(client.fd)
            return
        }
        let key = keyLine.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)

        // Compute accept key: Base64(SHA1(key + magic))
        let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let combined = key + magic
        let acceptKey = sha1Base64(combined)

        // Send HTTP 101 response
        let response = "HTTP/1.1 101 Switching Protocols\r\n" +
            "Upgrade: websocket\r\n" +
            "Connection: Upgrade\r\n" +
            "Sec-WebSocket-Accept: \(acceptKey)\r\n\r\n"
        let responseBytes = Array(response.utf8)
        responseBytes.withUnsafeBufferPointer { ptr in
            _ = write(client.fd, ptr.baseAddress!, ptr.count)
        }

        // Register client
        lock.lock()
        clients[client.id] = client
        let count = clients.count
        lock.unlock()
        DispatchQueue.main.async { self.clientCount = count }
        diag.info("DaemonServer: client connected (\(count) total)")

        // Start read loop
        readLoop(client: client)
    }

    // MARK: - WebSocket Frame I/O

    private func readLoop(client: WebSocketClient) {
        // Make non-blocking and use a dispatch source
        let flags = fcntl(client.fd, F_GETFL)
        _ = fcntl(client.fd, F_SETFL, flags | O_NONBLOCK)

        let source = DispatchSource.makeReadSource(fileDescriptor: client.fd, queue: queue)
        client.readSource = source
        source.setEventHandler { [weak self] in
            self?.readFrame(client: client)
        }
        source.setCancelHandler { [weak self] in
            self?.removeClient(client)
        }
        source.resume()
    }

    private func readFrame(client: WebSocketClient) {
        // Read available data into client buffer
        var buf = [UInt8](repeating: 0, count: 65536)
        let n = read(client.fd, &buf, buf.count)
        if n <= 0 {
            client.readSource?.cancel()
            return
        }
        client.buffer.append(contentsOf: buf[..<n])

        // Process complete frames
        while let frame = parseFrame(&client.buffer) {
            switch frame.opcode {
            case 0x1: // Text
                if let text = String(bytes: frame.payload, encoding: .utf8),
                   let data = text.data(using: .utf8) {
                    handleMessage(data, client: client)
                }
            case 0x8: // Close
                // Send close frame back
                sendFrame(opcode: 0x8, payload: [], to: client)
                client.readSource?.cancel()
                return
            case 0x9: // Ping → Pong
                sendFrame(opcode: 0xA, payload: frame.payload, to: client)
            case 0xA: // Pong — ignore
                break
            default:
                break
            }
        }
    }

    private struct WSFrame {
        let opcode: UInt8
        let payload: [UInt8]
    }

    private func parseFrame(_ buffer: inout [UInt8]) -> WSFrame? {
        guard buffer.count >= 2 else { return nil }

        let byte0 = buffer[0]
        let byte1 = buffer[1]
        let opcode = byte0 & 0x0F
        let masked = (byte1 & 0x80) != 0
        var payloadLen = UInt64(byte1 & 0x7F)
        var offset = 2

        if payloadLen == 126 {
            guard buffer.count >= 4 else { return nil }
            payloadLen = UInt64(buffer[2]) << 8 | UInt64(buffer[3])
            offset = 4
        } else if payloadLen == 127 {
            guard buffer.count >= 10 else { return nil }
            payloadLen = 0
            for i in 0..<8 { payloadLen = payloadLen << 8 | UInt64(buffer[2 + i]) }
            offset = 10
        }

        let maskSize = masked ? 4 : 0
        let totalNeeded = offset + maskSize + Int(payloadLen)
        guard buffer.count >= totalNeeded else { return nil }

        var payload: [UInt8]
        if masked {
            let mask = Array(buffer[offset..<(offset + 4)])
            let dataStart = offset + 4
            payload = Array(buffer[dataStart..<(dataStart + Int(payloadLen))])
            for i in 0..<payload.count {
                payload[i] ^= mask[i % 4]
            }
        } else {
            payload = Array(buffer[offset..<(offset + Int(payloadLen))])
        }

        buffer.removeFirst(totalNeeded)
        return WSFrame(opcode: opcode, payload: payload)
    }

    private func sendFrame(opcode: UInt8, payload: [UInt8], to client: WebSocketClient) {
        var frame: [UInt8] = [0x80 | opcode] // FIN + opcode

        if payload.count < 126 {
            frame.append(UInt8(payload.count))
        } else if payload.count < 65536 {
            frame.append(126)
            frame.append(UInt8((payload.count >> 8) & 0xFF))
            frame.append(UInt8(payload.count & 0xFF))
        } else {
            frame.append(127)
            for i in (0..<8).reversed() {
                frame.append(UInt8((payload.count >> (i * 8)) & 0xFF))
            }
        }
        frame.append(contentsOf: payload)

        frame.withUnsafeBufferPointer { ptr in
            _ = write(client.fd, ptr.baseAddress!, ptr.count)
        }
    }

    private func sendWebSocketText(_ text: String, to client: WebSocketClient) {
        let payload = Array(text.utf8)
        sendFrame(opcode: 0x1, payload: payload, to: client)
    }

    // MARK: - Message Handling

    private func handleMessage(_ data: Data, client: WebSocketClient) {
        guard let request = try? decoder.decode(DaemonRequest.self, from: data) else {
            let errResponse = DaemonResponse(id: "?", result: nil, error: "Invalid request JSON")
            sendResponse(errResponse, to: client)
            return
        }

        let response = LatticesApi.shared.handle(request)
        sendResponse(response, to: client)
    }

    private func sendResponse(_ response: DaemonResponse, to client: WebSocketClient) {
        guard let data = try? encoder.encode(response),
              let text = String(data: data, encoding: .utf8) else { return }
        sendWebSocketText(text, to: client)
    }

    // MARK: - Client Management

    private func removeClient(_ client: WebSocketClient) {
        close(client.fd)
        lock.lock()
        clients.removeValue(forKey: client.id)
        let count = clients.count
        lock.unlock()
        DispatchQueue.main.async { self.clientCount = count }
        DiagnosticLog.shared.info("DaemonServer: client disconnected (\(count) total)")
    }

    // MARK: - Crypto Helper

    private func sha1Base64(_ string: String) -> String {
        let data = Array(string.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        CC_SHA1(data, CC_LONG(data.count), &hash)
        return Data(hash).base64EncodedString()
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
        case .processesChanged(let interesting):
            daemonEvent = DaemonEvent(
                event: "processes.changed",
                data: .object([
                    "interestingCount": .int(interesting.count),
                    "pids": .array(interesting.map { .int($0) })
                ])
            )
        case .ocrScanComplete(let windowCount, let totalBlocks):
            daemonEvent = DaemonEvent(
                event: "ocr.scanComplete",
                data: .object([
                    "windowCount": .int(windowCount),
                    "totalBlocks": .int(totalBlocks)
                ])
            )
        case .voiceCommand(let text, let confidence):
            daemonEvent = DaemonEvent(
                event: "voice.command",
                data: .object([
                    "text": .string(text),
                    "confidence": .double(confidence)
                ])
            )
        }
        broadcast(daemonEvent)
    }
}

// MARK: - Client State

final class WebSocketClient {
    let id: UUID
    let fd: Int32
    var buffer: [UInt8] = []
    var readSource: DispatchSourceRead?

    init(id: UUID, fd: Int32) {
        self.id = id
        self.fd = fd
    }
}
