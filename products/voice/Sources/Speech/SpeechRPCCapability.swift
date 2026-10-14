import Foundation
import Security

/// A local, per-daemon capability. Never included in RPC parameters or events.
final class SpeechRPCCapability {
    static let header = "x-lattices-speech-token"
    static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Speech/RPC/capability")
    }
    private let token: String
    private let url: URL

    init(url: URL = SpeechRPCCapability.fileURL) throws {
        self.url = url
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw CocoaError(.fileWriteUnknown)
        }
        token = Data(bytes).base64EncodedString()
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let temporary = directory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard FileManager.default.createFile(atPath: temporary.path, contents: Data(token.utf8),
                                             attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard rename(temporary.path, url.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }

    func authorizes(handshake: String) -> Bool {
        let lines = handshake.components(separatedBy: "\r\n")
        var tokens: [String] = []
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            let pair = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { return false }
            let name = pair[0].trimmingCharacters(in: .whitespaces).lowercased()
            if name == "origin" { return false }
            if name == Self.header { tokens.append(pair[1].trimmingCharacters(in: .whitespaces)) }
        }
        guard tokens.count == 1 else { return false }
        let supplied = Array(tokens[0].utf8), expected = Array(token.utf8)
        guard supplied.count == expected.count else { return false }
        var difference: UInt8 = 0
        for index in expected.indices { difference |= supplied[index] ^ expected[index] }
        return difference == 0
    }

    func remove() {
        guard (try? String(contentsOf: url, encoding: .utf8)) == token else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
