import ArgumentParser
import BlinkCore
import Darwin
import Foundation

enum BlinkSocketClient {
    static func call(method: String, params: [String: Any]) throws -> Any {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ValidationError("could not create Blink socket client") }
        defer { Darwin.close(fd) }
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        let path = BlinkPaths.socket().path
        guard path.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw ValidationError("Blink socket path is too long")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { bytes in
            bytes.baseAddress?.initializeMemory(as: UInt8.self, repeating: 0, count: bytes.count)
            path.utf8CString.withUnsafeBytes { source in bytes.copyBytes(from: source) }
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            throw ValidationError("Blink is not running with the same BLINK_HOME (missing blink.sock)")
        }
        let request: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": method, "params": params]
        var outgoing = try JSONSerialization.data(withJSONObject: request); outgoing.append(0x0a)
        _ = outgoing.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
        var bytes = [UInt8](repeating: 0, count: 65_536)
        let count = Darwin.read(fd, &bytes, bytes.count)
        guard count > 0,
              let object = try JSONSerialization.jsonObject(with: Data(bytes.prefix(count))) as? [String: Any]
        else { throw ValidationError("Blink closed the socket without a response") }
        if let error = object["error"] as? [String: Any] {
            throw ValidationError(error["message"] as? String ?? "Blink RPC failed")
        }
        return object["result"] ?? NSNull()
    }
}
