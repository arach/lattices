import Darwin
import Foundation
import BlinkCore

final class BlinkSocketServer: @unchecked Sendable {
    final class Client: @unchecked Sendable {
        let fd: Int32
        var buffer = Data()
        var subscribed = false
        var source: DispatchSourceRead?
        init(_ fd: Int32) { self.fd = fd }
    }

    private let path: URL
    private let queue = DispatchQueue(label: "dev.arach.blink.socket")
    private var listener: DispatchSourceRead?
    private var clients: [Int32: Client] = [:]
    private let handler: @MainActor (Data, Client) async -> Void

    init(path: URL = BlinkPaths.socket(), handler: @escaping @MainActor (Data, Client) async -> Void) {
        self.path = path; self.handler = handler
    }

    func start() throws {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        unlink(path.path)
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        guard path.path.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else { close(fd); throw POSIXError(.ENAMETOOLONG) }
        withUnsafeMutableBytes(of: &address.sun_path) { bytes in
            bytes.baseAddress?.initializeMemory(as: UInt8.self, repeating: 0, count: bytes.count)
            path.path.utf8CString.withUnsafeBytes { bytes.copyBytes(from: $0) }
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0, listen(fd, 16) == 0 else { close(fd); throw POSIXError(.EADDRINUSE) }
        chmod(path.path, mode_t(S_IRUSR | S_IWUSR))
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.accept(fd) }
        source.setCancelHandler { close(fd) }
        listener = source; source.resume()
    }

    func stop() {
        queue.sync {
            for client in clients.values {
                client.source?.cancel()
                close(client.fd)
            }
            clients.removeAll()
        }
        listener?.cancel(); listener = nil; unlink(path.path)
    }

    private func accept(_ listenerFD: Int32) {
        let fd = Darwin.accept(listenerFD, nil, nil); guard fd >= 0 else { return }
        let client = Client(fd)
        clients[fd] = client
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        client.source = source
        source.setEventHandler { [weak self, weak client] in
            guard let self, let client else { return }
            self.read(client)
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
    }

    private func read(_ client: Client) {
        var bytes = [UInt8](repeating: 0, count: 8192)
        let count = Darwin.read(client.fd, &bytes, bytes.count)
        guard count > 0 else {
            client.source?.cancel()
            clients[client.fd] = nil
            return
        }
        client.buffer.append(contentsOf: bytes.prefix(count))
        while let newline = client.buffer.firstIndex(of: 0x0a) {
            let line = client.buffer.prefix(upTo: newline)
            client.buffer.removeSubrange(...newline)
            let data = Data(line)
            Task { @MainActor [handler] in await handler(data, client) }
        }
    }

    func send(_ object: [String: Any], to client: Client) {
        guard JSONSerialization.isValidJSONObject(object), var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0a)
        queue.async { _ = data.withUnsafeBytes { Darwin.write(client.fd, $0.baseAddress, $0.count) } }
    }

    func publish(method: String, params: [String: Any]) {
        queue.async { [weak self] in
            guard let self else { return }
            for client in clients.values where client.subscribed { send(["jsonrpc": "2.0", "method": method, "params": params], to: client) }
        }
    }
}
