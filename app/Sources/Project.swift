import CryptoKit
import Foundation

struct Project: Identifiable {
    let id: String
    let path: String
    let name: String
    let devCommand: String?
    let packageManager: String?
    let hasConfig: Bool
    let paneCount: Int
    let paneNames: [String]
    let paneSummary: String
    var isRunning: Bool

    /// Unique session name: basename-{6-char SHA256 hash of full path}
    /// Must match the JS `toSessionName()` in lattices.js exactly
    var sessionName: String {
        let base = name.replacingOccurrences(
            of: "[^a-zA-Z0-9_-]",
            with: "-",
            options: .regularExpression
        )
        let hash = SHA256.hash(data: Data(path.utf8))
        let short = hash.prefix(3).map { String(format: "%02x", $0) }.joined()
        return "\(base)-\(short)"
    }
}
