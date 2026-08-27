import CryptoKit
import Foundation

struct ActionSessionLinkTarget: Codable, Sendable {
    let canonicalPath: String
    let artifactDirectoryPath: String
    let sessionId: String
    let feedbackItemId: String?
    let createdAt: String
}

@MainActor
final class ActionSessionLinkStore {
    static let shared = ActionSessionLinkStore()

    private struct LinkIndex: Codable {
        var records: [String: ActionSessionLinkTarget]
    }

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private let decoder = JSONDecoder()

    func register(session: ActionSessionSummary, feedbackItemId: String? = nil) throws -> String {
        var index = try loadIndex()
        let canonicalPath = feedbackItemId.map {
            "sessions/\(session.sessionId)/feedbacks/\($0)"
        } ?? "sessions/\(session.sessionId)/feedback"
        let token = token(for: canonicalPath, existing: index.records)
        index.records[token] = ActionSessionLinkTarget(
            canonicalPath: canonicalPath,
            artifactDirectoryPath: session.artifactDirectoryURL.path,
            sessionId: session.sessionId,
            feedbackItemId: feedbackItemId,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        try saveIndex(index)
        return token
    }

    func resolve(token: String) throws -> ActionSessionLinkTarget? {
        let index = try loadIndex()
        return index.records[token]
    }

    private func loadIndex() throws -> LinkIndex {
        let url = indexURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            return LinkIndex(records: [:])
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(LinkIndex.self, from: data)
    }

    private func saveIndex(_ index: LinkIndex) throws {
        let url = indexURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(index)
        try data.write(to: url, options: .atomic)
    }

    private func indexURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Action/link-index.json")
    }

    private func token(for canonicalPath: String, existing: [String: ActionSessionLinkTarget]) -> String {
        let digest = SHA256.hash(data: Data(canonicalPath.utf8))
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567")
        var bits = 0
        var value = 0
        var encoded = ""

        for byte in digest {
            value = (value << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                let index = (value >> (bits - 5)) & 0x1F
                encoded.append(alphabet[index])
                bits -= 5
            }
        }

        if bits > 0 {
            let index = (value << (5 - bits)) & 0x1F
            encoded.append(alphabet[index])
        }

        for length in 10...min(16, encoded.count) {
            let candidate = String(encoded.prefix(length))
            if let existingTarget = existing[candidate], existingTarget.canonicalPath != canonicalPath {
                continue
            }
            return candidate
        }

        return String(encoded.prefix(16))
    }
}
