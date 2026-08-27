import Foundation

/// ISO8601 parsing for the two shapes the runtime writes (with and without
/// fractional seconds).
///
/// Built per read rather than held statically: `ISO8601DateFormatter` is not
/// `Sendable`, and these readers run off the main actor. One instance amortised
/// across a whole file scan costs nothing; one per row would not.
struct ActionISO8601Parser {
    private let fractional: ISO8601DateFormatter
    private let plain: ISO8601DateFormatter

    init() {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.fractional = fractional
        self.plain = ISO8601DateFormatter()
    }

    func date(from raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return fractional.date(from: raw) ?? plain.date(from: raw)
    }
}

// MARK: - Live lease

/// The one drive currently holding this Mac, as Home needs to show it.
///
/// Home does not ask the agent over IPC for this. `ActionDriveLeaseStore`
/// already persists each lease as its own small JSON file, and the launcher is
/// on the same machine, so reading the store directly costs a directory listing
/// and keeps the panel honest when the agent process is down — a lease the
/// store still holds is a lease that still owns the pointer.
struct ActionHomeLease: Identifiable, Equatable {
    let id: String
    let agent: String
    let task: String
    let mode: String
    let startedAt: Date?
    let lastActAt: Date?
    let stopFile: String
    let pointerControl: Bool
    let showSupervisionLabel: Bool

    /// Short form for the panel: lease ids are long and only the tail distinguishes them.
    var shortID: String {
        let tail = id.split(separator: "_").last.map(String.init) ?? id
        return String(tail.prefix(8))
    }

    var elapsed: TimeInterval? {
        guard let startedAt else { return nil }
        return Date().timeIntervalSince(startedAt)
    }

    var formattedElapsed: String {
        guard let elapsed, elapsed.isFinite, elapsed >= 0 else {
            return "--:--"
        }
        let total = Int(elapsed.rounded())
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

/// Read-only mirror of `ActionCore`'s `ActionDriveLease`.
///
/// The store's type is internal to `ActionCore`, and widening it to public only
/// so the launcher can read a handful of fields would export a mutable lease
/// model across a module boundary that has no business owning one. Every field
/// here is optional so a lease written by a newer runtime still decodes.
private struct ActionHomeLeaseRecord: Decodable {
    var leaseId: String?
    var agent: String?
    var task: String?
    var mode: String?
    var status: String?
    var startedAt: String?
    var lastActAt: String?
    var releasedAt: String?
    var stopFile: String?
    var pointerControl: Bool?
    var showSupervisionLabel: Bool?
}

/// The store wraps each lease in an owner envelope; older records are bare.
private struct ActionHomeLeaseEnvelope: Decodable {
    var lease: ActionHomeLeaseRecord?
}

enum ActionHomeLeaseReader {
    static var leasesDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Action/runtime/drive/leases", isDirectory: true)
    }

    /// Leases the store still considers live, newest activity first.
    ///
    /// `status` is the store's own word, so Home agrees with the supervisor
    /// rather than forming a second opinion about who is driving. The idle guard
    /// is the belt to that suspenders: a record left behind by a killed process
    /// keeps `driving` forever, and a stale panel claiming the Mac is being
    /// driven is worse than no panel at all.
    static func activeLeases(now: Date = Date()) -> [ActionHomeLease] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: leasesDirectoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        let decoder = JSONDecoder()
        let parser = ActionISO8601Parser()
        var leases: [ActionHomeLease] = []
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url) else {
                continue
            }
            let record = (try? decoder.decode(ActionHomeLeaseEnvelope.self, from: data))?.lease
                ?? (try? decoder.decode(ActionHomeLeaseRecord.self, from: data))
            guard let record,
                  let leaseId = record.leaseId, !leaseId.isEmpty,
                  record.status?.lowercased() == "driving",
                  record.releasedAt == nil else {
                continue
            }

            let lastActAt = parser.date(from: record.lastActAt)
            if let lastActAt, now.timeIntervalSince(lastActAt) >= ActionRunOutcome.idleExpirySeconds {
                continue
            }

            leases.append(
                ActionHomeLease(
                    id: leaseId,
                    agent: record.agent?.nonEmpty ?? "Unidentified agent",
                    task: record.task?.nonEmpty ?? "Driving",
                    mode: record.mode?.nonEmpty ?? "background",
                    startedAt: parser.date(from: record.startedAt),
                    lastActAt: lastActAt,
                    stopFile: record.stopFile ?? "",
                    pointerControl: record.pointerControl ?? false,
                    showSupervisionLabel: record.showSupervisionLabel ?? false
                )
            )
        }

        return leases.sorted {
            ($0.lastActAt ?? .distantPast) > ($1.lastActAt ?? .distantPast)
        }
    }
}

// MARK: - Tool counts

/// One verb an agent can ask this Mac for, and how often it has.
struct ActionToolCount: Identifiable, Equatable {
    let name: String
    let count: Int

    var id: String { name }
}

/// A column of the Actions panel.
struct ActionToolGroup: Identifiable, Equatable {
    let title: String
    let items: [ActionToolCount]

    var id: String { title }
}

struct ActionToolCounts: Equatable {
    var groups: [ActionToolGroup] = []
    /// True once the ledger has at least one call in the window. An empty
    /// ledger has to read as "nothing yet", never as a wall of confident zeros.
    var hasData: Bool = false

    static let empty = ActionToolCounts()
}

/// Tallies the MCP tool ledger the server appends to on every settled call.
///
/// The vocabulary below is deliberately written out rather than derived from
/// whatever happens to be in the file: Home's job is to tell an operator what
/// this Mac *can* do, so a verb nobody has called yet still gets a row, at zero.
enum ActionToolLedger {
    /// "how often it has, this week" — the panel's own claim, so the window has
    /// to match the words.
    static let windowSeconds: TimeInterval = 7 * 24 * 60 * 60

    static var directoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Action/runtime/tools", isDirectory: true)
    }

    private struct Entry: Decodable {
        var at: String?
        var tool: String?
        var verb: String?
        var ok: Bool?
    }

    /// Act kinds the macOS runtime actually has a handler for. `ActionKind`
    /// declares more; the rest are rejected rather than performed, so listing
    /// them here would advertise capability Action does not have.
    private static let actVerbs = [
        "click", "type", "press-key", "focus-window", "open-app", "scroll", "drag",
    ]

    private static let observeTools: [(label: String, tool: String)] = [
        ("snapshot", "action.observe.snapshot"),
        ("resolve.target", "action.resolve.target"),
        ("ax", "action.observe.ax"),
        ("ocr", "action.observe.ocr"),
        ("vision", "action.observe.vision"),
    ]

    private static let driveTools: [(label: String, tool: String)] = [
        ("aim", "action.drive.aim"),
        ("note", "action.drive.note"),
        ("begin", "action.drive.begin"),
        ("release", "action.drive.release"),
        ("play", "action.drive.play"),
    ]

    private static let stageTools: [(label: String, tool: String)] = [
        ("stage.set", "action.stage.set"),
        ("stage.clear", "action.stage.clear"),
        ("record.start", "action.record.start"),
        ("record.stop", "action.record.stop"),
    ]

    static func counts(now: Date = Date()) -> ActionToolCounts {
        var byTool: [String: Int] = [:]
        var byVerb: [String: Int] = [:]
        var total = 0

        let cutoff = now.addingTimeInterval(-windowSeconds)
        let decoder = JSONDecoder()
        let parser = ActionISO8601Parser()
        for url in [directoryURL.appendingPathComponent("log.1.jsonl"),
                    directoryURL.appendingPathComponent("log.jsonl")] {
            guard let raw = try? String(contentsOf: url, encoding: .utf8), !raw.isEmpty else {
                continue
            }
            for row in raw.split(whereSeparator: \.isNewline) {
                guard let data = String(row).data(using: .utf8),
                      let entry = try? decoder.decode(Entry.self, from: data),
                      let tool = entry.tool else {
                    continue
                }
                // A failed call is a call the agent made, but not an action this
                // Mac performed. The panel counts what happened.
                guard entry.ok != false else { continue }
                guard let at = parser.date(from: entry.at), at >= cutoff else { continue }

                total += 1
                byTool[tool, default: 0] += 1
                if let verb = entry.verb, !verb.isEmpty {
                    byVerb[verb, default: 0] += 1
                }
            }
        }

        func group(_ title: String, _ tools: [(label: String, tool: String)]) -> ActionToolGroup {
            ActionToolGroup(
                title: title,
                items: tools.map { ActionToolCount(name: $0.label, count: byTool[$0.tool] ?? 0) }
            )
        }

        return ActionToolCounts(
            groups: [
                ActionToolGroup(
                    title: "Act",
                    items: actVerbs.map { ActionToolCount(name: $0, count: byVerb[$0] ?? 0) }
                ),
                group("Observe", observeTools),
                group("Drive", driveTools),
                group("Stage & record", stageTools),
            ],
            hasData: total > 0
        )
    }
}

// MARK: - Connect an agent

/// The line an operator hands to an agent once.
///
/// It mirrors the form documented in `docs/browser-profiles.md` for the native
/// runtime MCP, whose server name is `action`. `ACTION_ROOT` is resolved from
/// the running app rather than hard-coded, so the snippet is correct on a
/// checkout that does not live at `~/dev/action`.
enum ActionMCPSetup {
    static let serverName = "action"

    static func command(root: URL) -> String {
        let path = abbreviated(root.path)
        return """
        claude mcp add \(serverName) -s user -e ACTION_ROOT=\(path) \\
          -- bun --cwd \(path) packages/mcp/src/index.ts
        """
    }

    /// Two display lines, so the panel can tint the server name on the first.
    static func commandLines(root: URL) -> [String] {
        command(root: root).components(separatedBy: "\n")
    }

    private static func abbreviated(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path == home || path.hasPrefix(home + "/") else {
            return path
        }
        return "~" + String(path.dropFirst(home.count))
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
