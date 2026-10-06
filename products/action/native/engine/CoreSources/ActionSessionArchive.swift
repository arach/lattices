import Foundation

struct ActionSessionPruneResult: Codable, Equatable, Sendable {
    var removed: Int
    var freedBytes: Int64
    var remaining: Int
    var remainingBytes: Int64
}

/// The agent's run ledger: one directory per session under
/// `~/Library/Application Support/Action/sessions`, which the app's Runs list
/// always reads.
///
/// The agent writes it for every lease it grants, so a run shows up whether
/// it came through the MCP, the CLI, or a raw connection to the agent port.
/// Callers never have to remember to persist anything. Retention lives here
/// too: old sessions age out and the folder is held under a size cap, so the
/// screenshots and recordings that land beside a run can't grow forever.
struct ActionSessionArchive: Sendable {
    static let maximumAge: TimeInterval = 14 * 24 * 60 * 60
    static let maximumBytes: Int64 = 2 * 1024 * 1024 * 1024
    /// Layer snapshots and recordings are working files, not run evidence.
    static let scratchMaximumAge: TimeInterval = 3 * 24 * 60 * 60
    static let traceLimit = 2_000

    static var defaultRootURL: URL {
        actionSupportURL.appendingPathComponent("sessions", isDirectory: true)
    }

    static var defaultScratchURLs: [URL] {
        let layer = actionSupportURL.appendingPathComponent("agent-layer", isDirectory: true)
        return [
            layer.appendingPathComponent("snapshots", isDirectory: true),
            layer.appendingPathComponent("recordings", isDirectory: true),
        ]
    }

    private static var actionSupportURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Action", isDirectory: true)
    }

    let rootURL: URL
    let scratchURLs: [URL]
    let maximumAge: TimeInterval
    let maximumBytes: Int64
    let scratchMaximumAge: TimeInterval

    init(
        rootURL: URL = ActionSessionArchive.defaultRootURL,
        scratchURLs: [URL] = ActionSessionArchive.defaultScratchURLs,
        maximumAge: TimeInterval = ActionSessionArchive.maximumAge,
        maximumBytes: Int64 = ActionSessionArchive.maximumBytes,
        scratchMaximumAge: TimeInterval = ActionSessionArchive.scratchMaximumAge
    ) {
        self.rootURL = rootURL
        self.scratchURLs = scratchURLs
        self.maximumAge = maximumAge
        self.maximumBytes = maximumBytes
        self.scratchMaximumAge = scratchMaximumAge
    }

    func directoryURL(for sessionID: String) -> URL {
        rootURL.appendingPathComponent(Self.sanitize(sessionID), isDirectory: true)
    }

    /// Writes the lease and appends one trace event. Best effort: a full disk
    /// must never fail the drive call that triggered it.
    func record(_ lease: ActionDriveLease, event: [String: Any]) {
        let directory = directoryURL(for: lease.sessionId)
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let leaseData = try encoder.encode(lease)
            try leaseData.write(to: directory.appendingPathComponent("drive-lease.json"), options: .atomic)

            let traceURL = directory.appendingPathComponent("drive-trace.json")
            var trace = (try? Data(contentsOf: traceURL))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [Any] } ?? []
            trace.append(event)
            if trace.count > Self.traceLimit {
                trace.removeFirst(trace.count - Self.traceLimit)
            }
            try Self.writeJSON(trace, to: traceURL)

            let sessionURL = directory.appendingPathComponent("session.json")
            var session = (try? Data(contentsOf: sessionURL))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            let driving = lease.status == "driving"
            session["id"] = session["id"] ?? lease.sessionId
            session["mode"] = session["mode"] ?? "hybrid"
            session["state"] = driving ? "running" : "completed"
            session["phase"] = driving ? "acting" : "completed"
            session["createdAt"] = session["createdAt"] ?? lease.startedAt
            session["updatedAt"] = lease.releasedAt ?? lease.lastActAt
            session["outputDir"] = directory.path
            session["driveLeaseId"] = lease.leaseId
            session["drive"] = try JSONSerialization.jsonObject(with: leaseData)
            session["recordedBy"] = "action-agent"
            try Self.writeJSON(session, to: sessionURL)
        } catch {
            FileHandle.standardError.write(
                Data("ActionAgent session record failed for \(lease.sessionId): \(error.localizedDescription)\n".utf8)
            )
        }
    }

    /// Ages sessions out, then evicts the oldest until the folder fits the size
    /// cap. Sessions named in `active` are never touched.
    @discardableResult
    func prune(keeping active: Set<String>, now: Date = Date()) -> ActionSessionPruneResult {
        for scratch in scratchURLs {
            Self.pruneFiles(in: scratch, olderThan: now.addingTimeInterval(-scratchMaximumAge))
        }

        var entries = sessionEntries(keeping: active)
        var removed = 0
        var freed: Int64 = 0
        let cutoff = now.addingTimeInterval(-maximumAge)
        entries.removeAll { entry in
            guard entry.modifiedAt < cutoff else { return false }
            if (try? FileManager.default.removeItem(at: entry.url)) != nil {
                removed += 1
                freed += entry.bytes
                return true
            }
            return false
        }

        var total = entries.reduce(Int64(0)) { $0 + $1.bytes } + activeBytes(active)
        entries.sort { $0.modifiedAt < $1.modifiedAt }
        while total > maximumBytes, let oldest = entries.first {
            entries.removeFirst()
            guard (try? FileManager.default.removeItem(at: oldest.url)) != nil else { continue }
            removed += 1
            freed += oldest.bytes
            total -= oldest.bytes
        }
        return ActionSessionPruneResult(
            removed: removed,
            freedBytes: freed,
            remaining: entries.count + active.count,
            remainingBytes: total
        )
    }

    /// Removes every session except the ones still driving.
    @discardableResult
    func clear(keeping active: Set<String>) -> ActionSessionPruneResult {
        var removed = 0
        var freed: Int64 = 0
        for entry in sessionEntries(keeping: active) {
            if (try? FileManager.default.removeItem(at: entry.url)) != nil {
                removed += 1
                freed += entry.bytes
            }
        }
        return ActionSessionPruneResult(
            removed: removed,
            freedBytes: freed,
            remaining: active.count,
            remainingBytes: activeBytes(active)
        )
    }

    func usage() -> (count: Int, bytes: Int64) {
        let entries = sessionEntries(keeping: [])
        return (entries.count, entries.reduce(Int64(0)) { $0 + $1.bytes })
    }

    private struct Entry {
        let url: URL
        let modifiedAt: Date
        let bytes: Int64
    }

    private func sessionEntries(keeping active: Set<String>) -> [Entry] {
        let protected = Set(active.map(Self.sanitize))
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            guard values?.isDirectory == true, !protected.contains(url.lastPathComponent) else {
                return nil
            }
            let (bytes, newest) = Self.measure(url)
            return Entry(url: url, modifiedAt: max(newest, values?.contentModificationDate ?? .distantPast), bytes: bytes)
        }
    }

    private func activeBytes(_ active: Set<String>) -> Int64 {
        active.reduce(Int64(0)) { $0 + Self.measure(directoryURL(for: $1)).bytes }
    }

    private static func measure(_ directory: URL) -> (bytes: Int64, newest: Date) {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys) else {
            return (0, .distantPast)
        }
        var bytes: Int64 = 0
        var newest = Date.distantPast
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else {
                continue
            }
            bytes += Int64(values.totalFileAllocatedSize ?? 0)
            newest = max(newest, values.contentModificationDate ?? .distantPast)
        }
        return (bytes, newest)
    }

    private static func pruneFiles(in directory: URL, olderThan cutoff: Date) {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for url in urls {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private static func writeJSON(_ value: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    static func sanitize(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let cleaned = String(raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        let trimmed = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return trimmed.isEmpty ? "session" : String(trimmed.prefix(160))
    }
}
