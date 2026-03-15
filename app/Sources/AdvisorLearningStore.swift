import Foundation

/// Captures moments where the Claude advisor resolved something the local matcher couldn't.
/// Each entry records the transcript, what the local system matched (or missed), and what
/// the advisor suggested that the user accepted.
///
/// For now this is append-only — just growing the dataset. Future work can use it to
/// improve local matching without needing the advisor.

final class AdvisorLearningStore {
    static let shared = AdvisorLearningStore()

    struct Entry: Codable {
        let timestamp: String
        let transcript: String
        let localIntent: String?
        let localSlots: [String: String]
        let localResultCount: Int
        let advisorIntent: String
        let advisorSlots: [String: String]
        let advisorLabel: String
    }

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.lattices.advisor-learning")
    private static let isoFmt: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".lattices")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("advisor-learning.jsonl")
    }

    /// Record that the user engaged with an advisor suggestion.
    func record(
        transcript: String,
        localIntent: String?,
        localSlots: [String: String],
        localResultCount: Int,
        advisorIntent: String,
        advisorSlots: [String: String],
        advisorLabel: String
    ) {
        let entry = Entry(
            timestamp: Self.isoFmt.string(from: Date()),
            transcript: transcript,
            localIntent: localIntent,
            localSlots: localSlots,
            localResultCount: localResultCount,
            advisorIntent: advisorIntent,
            advisorSlots: advisorSlots,
            advisorLabel: advisorLabel
        )

        queue.async {
            guard let data = try? JSONEncoder().encode(entry),
                  var line = String(data: data, encoding: .utf8) else { return }
            line += "\n"

            if let handle = try? FileHandle(forWritingTo: self.fileURL) {
                handle.seekToEndOfFile()
                handle.write(line.data(using: .utf8)!)
                handle.closeFile()
            } else {
                try? line.data(using: .utf8)?.write(to: self.fileURL)
            }

            DiagnosticLog.shared.info("AdvisorLearning: captured [\(transcript)] → \(advisorIntent)(\(advisorSlots))")
        }
    }

    /// Read all entries (for analysis).
    func allEntries() -> [Entry] {
        guard let data = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return data.components(separatedBy: "\n").compactMap { line in
            guard !line.isEmpty, let d = line.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(Entry.self, from: d)
        }
    }

    var entryCount: Int {
        guard let data = try? String(contentsOf: fileURL, encoding: .utf8) else { return 0 }
        return data.components(separatedBy: "\n").filter { !$0.isEmpty }.count
    }
}
