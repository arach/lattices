import Foundation
import Darwin

struct ActionSupervisionRegistration: Codable {
    let id: String
    let title: String
    let detail: String?
    let controlFile: String?
    let stopFile: String?
    let ownsVisibleControls: Bool?
    let avoidedDisplayID: UInt32?
    let expiresAt: String?
    let updatedAt: String
}

private struct ActionSupervisionNote: Codable {
    let at: String
    let line: String
    /// Which drive wrote it. Absent on notes from before leases were tagged.
    let leaseId: String?
}

enum ActionSupervisionRegistry {
    private static let driveIdleExpirySeconds: TimeInterval = 90
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let iso8601Format = Date.ISO8601FormatStyle()
    private static let fractionalISO8601Format = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    static var baseDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Action/runtime/supervision", isDirectory: true)
    }

    static var registrationsDirectoryURL: URL {
        baseDirectoryURL.appendingPathComponent("registrations", isDirectory: true)
    }

    static var overlayPIDURL: URL {
        baseDirectoryURL.appendingPathComponent("overlay.pid")
    }

    static var overlayStopSignalURL: URL {
        baseDirectoryURL.appendingPathComponent("overlay.stop")
    }

    static var notesURL: URL {
        baseDirectoryURL.appendingPathComponent("notes.jsonl")
    }

    private struct PlayHudFilter: Codable {
        var show: Bool?
        var events: [String]?
    }

    private struct PlayLogEvent: Codable {
        var event: String
        var play: String?
        var index: Int?
        var of: Int?
        var `do`: String?
        var detail: String?
        var ms: Int?
        var error: String?
    }

    private static let defaultPlayHudEvents: Set<String> = [
        "play-start",
        "step-start",
        "step-fail",
        "play-fail",
        "play-ok",
    ]

    private static var playsDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Action/runtime/plays", isDirectory: true)
    }

    /// Filtered play-log lines for the HUD. The files always record every event;
    /// `hud-filter.json` chooses what Action shows.
    static func recentHudLines(limit: Int = 4) -> [String] {
        let filter = loadPlayHudFilter()
        if filter.show {
            let playLines = recentPlayLines(limit: limit, allowed: filter.events)
            if !playLines.isEmpty {
                return playLines
            }
        }
        return recentNotes(limit: limit)
    }

    private static func loadPlayHudFilter() -> (show: Bool, events: Set<String>) {
        let url = playsDirectoryURL.appendingPathComponent("hud-filter.json")
        guard let data = try? Data(contentsOf: url),
              let parsed = try? JSONDecoder().decode(PlayHudFilter.self, from: data) else {
            return (true, defaultPlayHudEvents)
        }
        let show = parsed.show ?? true
        let events = Set((parsed.events?.isEmpty == false ? parsed.events : nil) ?? Array(defaultPlayHudEvents))
        return (show, events)
    }

    private static func recentPlayLines(limit: Int, allowed: Set<String>) -> [String] {
        let url = playsDirectoryURL.appendingPathComponent("current.jsonl")
        guard let raw = try? String(contentsOf: url, encoding: .utf8), !raw.isEmpty else {
            return []
        }
        let decoder = JSONDecoder()
        var lines: [String] = []
        for row in raw.split(whereSeparator: \.isNewline) {
            guard let data = String(row).data(using: .utf8),
                  let event = try? decoder.decode(PlayLogEvent.self, from: data),
                  allowed.contains(event.event) else {
                continue
            }
            let line = displayLine(for: event)
            if !line.isEmpty {
                lines.append(line)
            }
        }
        if lines.count > limit {
            return Array(lines.suffix(limit))
        }
        return lines
    }

    private static func displayLine(for event: PlayLogEvent) -> String {
        switch event.event {
        case "play-start":
            let count = event.of.map(String.init) ?? "0"
            return "\(event.play ?? "play") · \(count) steps"
        case "play-ok":
            return "\(event.play ?? "play") · done"
        case "play-fail":
            if let error = event.error, !error.isEmpty {
                return "\(event.play ?? "play") · failed: \(error)"
            }
            return "\(event.play ?? "play") · failed"
        case "step-fail":
            let n = stepIndex(event)
            let verb = event.do ?? "step"
            if let error = event.error, !error.isEmpty {
                return "\(n) fail \(verb): \(error)"
            }
            return "\(n) fail \(verb)"
        case "step-ok":
            let n = stepIndex(event)
            let verb = event.do ?? "step"
            if let ms = event.ms {
                return "\(n) \(verb) \(ms)ms"
            }
            return "\(n) \(verb)"
        default:
            let n = stepIndex(event)
            return "\(n) \(event.do ?? "step")"
        }
    }

    private static func stepIndex(_ event: PlayLogEvent) -> String {
        guard let index = event.index, let of = event.of else {
            return "?"
        }
        return "\(index + 1)/\(of)"
    }

    /// The newest beat a specific drive wrote, if it is recent enough to still
    /// describe what that drive is doing.
    ///
    /// The unfiltered `recentHudLines` is wrong for a live panel: it returns the
    /// last line anyone wrote, so a finished play from hours ago gets printed
    /// under a running drive as if it were its current step. A beat has to be
    /// attributable to *this* lease and still warm, or it is not shown at all.
    static func latestNote(forLease leaseID: String, maxAge: TimeInterval = 90, now: Date = Date()) -> String? {
        guard let raw = try? String(contentsOf: notesURL, encoding: .utf8), !raw.isEmpty else {
            return nil
        }

        let decoder = JSONDecoder()
        for row in raw.split(whereSeparator: \.isNewline).reversed() {
            guard let data = String(row).data(using: .utf8),
                  let note = try? decoder.decode(ActionSupervisionNote.self, from: data) else {
                continue
            }
            guard note.leaseId == leaseID else { continue }
            guard let at = parseISO8601Date(note.at), now.timeIntervalSince(at) < maxAge else {
                // Older entries only get older; nothing further back can qualify.
                return nil
            }
            let line = note.line.trimmingCharacters(in: .whitespacesAndNewlines)
            return line.isEmpty ? nil : line
        }
        return nil
    }

    static func recentNotes(limit: Int = 4) -> [String] {
        guard let raw = try? String(contentsOf: notesURL, encoding: .utf8), !raw.isEmpty else {
            return []
        }

        let decoder = JSONDecoder()
        var lines: [String] = []
        for row in raw.split(whereSeparator: \.isNewline) {
            guard let data = String(row).data(using: .utf8),
                  let note = try? decoder.decode(ActionSupervisionNote.self, from: data) else {
                continue
            }
            let line = note.line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty {
                lines.append(line)
            }
        }
        if lines.count > limit {
            return Array(lines.suffix(limit))
        }
        return lines
    }

    static func register(
        id: String,
        title: String,
        detail: String?,
        controlFile: String?,
        stopFile: String?,
        ownsVisibleControls: Bool = false,
        avoidedDisplayID: UInt32? = nil,
        expiresAt: String? = nil
    ) throws {
        let registration = ActionSupervisionRegistration(
            id: id,
            title: title,
            detail: detail,
            controlFile: controlFile,
            stopFile: stopFile,
            ownsVisibleControls: ownsVisibleControls,
            avoidedDisplayID: avoidedDisplayID,
            expiresAt: expiresAt,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        try FileManager.default.createDirectory(at: registrationsDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.removeItemIfExists(at: overlayStopSignalURL)
        let url = registrationURL(for: id)
        try encoder.encode(registration).write(to: url)
        try ActionSupervisionOverlayLauncher.ensureRunning()
    }

    static func unregister(id: String) {
        try? FileManager.default.removeItem(at: registrationURL(for: id))
        let remaining = activeRegistrations().count
        if remaining == 0 {
            stopOverlay()
        }
    }

    static func activeRegistrations() -> [ActionSupervisionRegistration] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: registrationsDirectoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        let decoder = JSONDecoder()
        let now = Date()
        var registrations: [ActionSupervisionRegistration] = []
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let registration = try? decoder.decode(ActionSupervisionRegistration.self, from: data) else {
                continue
            }
            if registrationIsExpired(registration, now: now) {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            registrations.append(registration)
        }
        return registrations.sorted { $0.updatedAt < $1.updatedAt }
    }

    @discardableResult
    static func triggerStopAll() -> Int {
        let registrations = activeRegistrations()
        for registration in registrations {
            if let controlFile = registration.controlFile, !controlFile.isEmpty {
                appendControlCommands(to: controlFile)
            }
            if let stopFile = registration.stopFile, !stopFile.isEmpty {
                writeMarker(path: stopFile, contents: "stop\n")
            }
        }
        return registrations.count
    }

    static func recordOverlayPID(_ pid: pid_t) {
        do {
            try FileManager.default.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
            try Data(String(pid).utf8).write(to: overlayPIDURL)
        } catch {}
    }

    static func clearOverlayPID(ifOwnedBy ownerPID: pid_t) {
        let existing = (try? String(contentsOf: overlayPIDURL, encoding: .utf8)) ?? "missing"
        let normalized = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized == String(ownerPID) else {
            return
        }
        try? FileManager.default.removeItem(at: overlayPIDURL)
    }

    static func overlayIsRunning() -> Bool {
        guard let pid = overlayPID() else {
            return false
        }

        if kill(pid, 0) == 0 {
            return true
        }

        return errno != ESRCH
    }

    static func overlayPID() -> pid_t? {
        guard let raw = try? String(contentsOf: overlayPIDURL, encoding: .utf8),
              let pid = Int32(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return pid
    }

    static func stopOverlay() {
        writeMarker(path: overlayStopSignalURL.path, contents: "stop\n")
    }

    private static func registrationURL(for id: String) -> URL {
        registrationsDirectoryURL.appendingPathComponent("\(sanitizedID(id)).json")
    }

    private static func registrationIsExpired(_ registration: ActionSupervisionRegistration, now: Date) -> Bool {
        if let expiresAt = registration.expiresAt,
           let expiration = parseISO8601Date(expiresAt) {
            return expiration <= now
        }

        // Registrations written before `expiresAt` existed can survive when
        // their MCP owner exits. Apply the same drive deadlines during this
        // one-time migration; non-drive Swift registrations remain durable
        // until their owner unregisters them.
        guard registration.id.hasPrefix("drive_"),
              let updatedAt = parseISO8601Date(registration.updatedAt) else {
            return false
        }
        let isTerminal = registration.detail.map { detail in
            let normalized = detail.uppercased()
            return ["DONE", "FAILED", "CANCELLED", "EXPIRED", "DENIED"]
                .contains(where: normalized.hasPrefix)
        } ?? false
        let expiry = isTerminal ? 8 : driveIdleExpirySeconds
        return now.timeIntervalSince(updatedAt) >= expiry
    }

    private static func parseISO8601Date(_ raw: String) -> Date? {
        (try? Date(raw, strategy: fractionalISO8601Format))
            ?? (try? Date(raw, strategy: iso8601Format))
    }

    private static func sanitizedID(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"[^A-Za-z0-9._-]+"#, with: "_", options: .regularExpression)
    }

    private static func appendControlCommands(to path: String) {
        let line = "stop\nquit\n"
        do {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: path) {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
                try handle.close()
            } else {
                try Data(line.utf8).write(to: url)
            }
        } catch {}
    }

    private static func writeMarker(path: String, contents: String) {
        let url = URL(fileURLWithPath: path)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: url)
        } catch {}
    }
}

enum ActionSupervisionOverlayLauncher {
    static func ensureRunning() throws {
        if ActionSupervisionRegistry.overlayIsRunning() {
            return
        }

        try FileManager.default.removeItemIfExists(at: ActionSupervisionRegistry.overlayStopSignalURL)
        let bundleURL = try resolveAppBundleURL()
        let replyFile = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("action-supervision-overlay-\(UUID().uuidString).json")

        defer {
            try? FileManager.default.removeItem(at: replyFile)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", bundleURL.path, "--args", "supervision-overlay", "--reply-file", replyFile.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
        try waitForOverlayReply(at: replyFile)
    }

    private static func resolveAppBundleURL() throws -> URL {
        let bundleURL = Bundle.main.bundleURL
        var fallbackAppBundleURL: URL?

        func inspect(candidate: URL) -> URL? {
            guard candidate.pathExtension == "app" else {
                return nil
            }
            if fallbackAppBundleURL == nil {
                fallbackAppBundleURL = candidate
            }
            if candidate.lastPathComponent == "Action.app" {
                return candidate
            }
            return nil
        }

        if let resolved = inspect(candidate: bundleURL) {
            return resolved
        }

        if let executableURL = Bundle.main.executableURL {
            var candidate = executableURL.deletingLastPathComponent()
            while candidate.path != "/" {
                if let resolved = inspect(candidate: candidate) {
                    return resolved
                }
                candidate.deleteLastPathComponent()
            }
        }

        if let fallbackAppBundleURL {
            return fallbackAppBundleURL
        }

        throw NSError(
            domain: "ActionSupervisionOverlayLauncher",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to resolve Action.app bundle URL for supervision overlay"]
        )
    }

    private static func waitForOverlayReply(at replyFile: URL) throws {
        for _ in 0..<50 {
            if let data = try? Data(contentsOf: replyFile),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let status = object["status"] as? String,
               status == "supervision-overlay-running" {
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        throw NSError(
            domain: "ActionSupervisionOverlayLauncher",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Supervision overlay did not acknowledge launch"]
        )
    }
}

private extension FileManager {
    func removeItemIfExists(at url: URL) throws {
        guard fileExists(atPath: url.path) else {
            return
        }
        try removeItem(at: url)
    }
}
