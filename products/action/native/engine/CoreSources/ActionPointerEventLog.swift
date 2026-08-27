import CoreGraphics
import Foundation

/// The single source of truth for Action-driven pointer button events.
///
/// Every synthetic primary-button press this project posts goes through `ActionPointerChannel`.
/// The channel posts the CGEvent and, when a recording has published a pointer event log,
/// appends the same record to that log. The visible click pulse is rendered by tailing the very
/// same log, so the recorded metadata and the recorded pixels are derived from one event and
/// cannot drift apart.
///
/// The log is JSON Lines because clicks are posted from short-lived per-action host processes
/// while the pulse overlay is a separate long-lived process. Append-only lines under the atomic
/// write size let both sides share the file without a lock or a second channel.
public enum ActionPointerEventLogFormat {
    /// Bump when a field changes meaning. Readers should refuse a version they do not know.
    public static let version = 1
    /// Environment variable that publishes the active log to every host subprocess.
    public static let environmentKey = "ACTION_POINTER_EVENT_LOG"
}

public struct ActionPointerFeedbackSettings: Codable, Equatable, Sendable {
    /// Whether the operator opted in to visible click feedback. Metadata is recorded either way.
    public let enabled: Bool
    /// Only `pulse` exists today; the field keeps the artifact readable if another style lands.
    public let style: String
    /// Lifetime of one pulse in milliseconds.
    public let durationMs: Double
    /// Outer radius the pulse expands to, in points.
    public let radius: Double

    public init(
        enabled: Bool,
        style: String = "pulse",
        durationMs: Double = 320,
        radius: Double = 34
    ) {
        self.enabled = enabled
        self.style = style
        self.durationMs = durationMs
        self.radius = radius
    }
}

/// First line of the log. Carries the clock reference every later line is relative to.
public struct ActionPointerEventLogHeader: Codable, Equatable, Sendable {
    public let kind: String
    public let version: Int
    public let recordingId: String
    public let sessionId: String?
    /// Wall-clock time the recording log was opened.
    public let startedAt: String
    /// `ProcessInfo.systemUptime` at the same instant. System uptime is a machine-wide monotonic
    /// clock, so a different process can subtract against it later and get a real elapsed time.
    public let startedAtUptime: Double
    public let feedback: ActionPointerFeedbackSettings

    public init(
        recordingId: String,
        sessionId: String?,
        startedAt: String,
        startedAtUptime: Double,
        feedback: ActionPointerFeedbackSettings
    ) {
        self.kind = "header"
        self.version = ActionPointerEventLogFormat.version
        self.recordingId = recordingId
        self.sessionId = sessionId
        self.startedAt = startedAt
        self.startedAtUptime = startedAtUptime
        self.feedback = feedback
    }
}

public enum ActionPointerPhase: String, Codable, Sendable {
    case down
    case up
}

public enum ActionPointerButton: String, Codable, Sendable {
    case left
    case right
}

/// What kind of gesture the press belongs to. Both phases of one gesture share a correlation id.
public enum ActionPointerGestureKind: String, Codable, Sendable {
    case click
    case drag
}

/// One button transition. This is the record that is written to the artifact and the record the
/// pulse renderer consumes — the same value, not two parallel descriptions of it.
public struct ActionPointerEvent: Codable, Equatable, Sendable {
    public let kind: String
    public let recordingId: String
    public let sessionId: String?
    /// Shared by the `down` and `up` of a single gesture, so the pair can be rejoined.
    public let correlationId: String
    public let gesture: ActionPointerGestureKind
    public let phase: ActionPointerPhase
    public let button: ActionPointerButton
    /// Screen coordinates in CoreGraphics global space (origin top-left), the same space the
    /// CGEvent was posted in.
    public let x: Double
    public let y: Double
    /// Monotonic milliseconds since the recording log was opened.
    public let recordingElapsedMs: Double
    /// Wall-clock time of the post, with fractional seconds.
    public let at: String
    /// Raw `ProcessInfo.systemUptime` at the post, so a reader can re-derive elapsed time.
    public let uptime: Double
    /// Measured press duration, present on `up` only.
    public let holdMs: Double?
    /// Which Action surface posted the event, e.g. `click-point` or `drag`.
    public let source: String

    public init(
        recordingId: String,
        sessionId: String?,
        correlationId: String,
        gesture: ActionPointerGestureKind,
        phase: ActionPointerPhase,
        button: ActionPointerButton,
        point: CGPoint,
        recordingElapsedMs: Double,
        at: String,
        uptime: Double,
        holdMs: Double?,
        source: String
    ) {
        self.kind = "pointer"
        self.recordingId = recordingId
        self.sessionId = sessionId
        self.correlationId = correlationId
        self.gesture = gesture
        self.phase = phase
        self.button = button
        self.x = Double(point.x)
        self.y = Double(point.y)
        self.recordingElapsedMs = recordingElapsedMs
        self.at = at
        self.uptime = uptime
        self.holdMs = holdMs
        self.source = source
    }

    public var point: CGPoint {
        CGPoint(x: x, y: y)
    }
}

public enum ActionPointerEventLogError: LocalizedError {
    case unwritable(String)
    case malformedHeader(String)
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .unwritable(let path):
            return "Unable to append to pointer event log at \(path)"
        case .malformedHeader(let path):
            return "Pointer event log at \(path) has no readable header line"
        case .unsupportedVersion(let version):
            return "Pointer event log version \(version) is newer than this build understands"
        }
    }
}

/// Reads and writes one pointer event log. Values are cheap: a host process constructs one per
/// gesture rather than holding shared mutable state.
public struct ActionPointerEventLog: Sendable {
    public let path: String
    public let header: ActionPointerEventLogHeader

    /// A value-type format style rather than `ISO8601DateFormatter`, so the shared instance is
    /// concurrency-safe without a lock.
    private static let isoFormat = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    private static func isoString(from date: Date) -> String {
        date.formatted(isoFormat)
    }

    public init(path: String, header: ActionPointerEventLogHeader) {
        self.path = path
        self.header = header
    }

    /// Creates the log and writes its header line. Called once when a recording starts.
    @discardableResult
    public static func create(
        at path: String,
        recordingId: String,
        sessionId: String?,
        feedback: ActionPointerFeedbackSettings,
        now: Date = Date(),
        uptime: Double = ProcessInfo.processInfo.systemUptime
    ) throws -> ActionPointerEventLog {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let header = ActionPointerEventLogHeader(
            recordingId: recordingId,
            sessionId: sessionId,
            startedAt: isoString(from: now),
            startedAtUptime: uptime,
            feedback: feedback
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var line = try encoder.encode(header)
        line.append(0x0a)
        try line.write(to: url, options: .atomic)

        return ActionPointerEventLog(path: path, header: header)
    }

    /// Opens an existing log by reading its header line. Returns nil when the path is absent,
    /// which is the normal "no recording is running" case rather than an error.
    public static func open(path: String) throws -> ActionPointerEventLog? {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            return nil
        }
        defer { try? handle.close() }

        // The header is the first line; reading a bounded prefix avoids pulling a long session
        // of events into memory just to learn the clock reference.
        let prefix = (try? handle.read(upToCount: 8192)) ?? Data()
        guard let newline = prefix.firstIndex(of: 0x0a) else {
            throw ActionPointerEventLogError.malformedHeader(path)
        }
        let headerData = prefix[prefix.startIndex..<newline]
        guard let header = try? JSONDecoder().decode(
            ActionPointerEventLogHeader.self,
            from: Data(headerData)
        ) else {
            throw ActionPointerEventLogError.malformedHeader(path)
        }
        guard header.version <= ActionPointerEventLogFormat.version else {
            throw ActionPointerEventLogError.unsupportedVersion(header.version)
        }

        return ActionPointerEventLog(path: path, header: header)
    }

    /// Well-known marker naming the log of the recording that is currently running.
    ///
    /// A marker file rather than only an environment variable because the host is usually started
    /// through `open -n`, which launches a fresh app via LaunchServices and does not reliably
    /// carry the caller's environment across. Every click process can read this path no matter how
    /// it was launched.
    public static func activeMarkerPath(
        home: URL = URL(fileURLWithPath: NSHomeDirectory())
    ) -> String {
        home
            .appendingPathComponent("Library/Application Support/Action/runtime/pointer-events")
            .appendingPathComponent("active.json")
            .path
    }

    private struct ActiveMarker: Codable {
        let path: String
    }

    /// Publishes (or clears) the marker so host processes record into this log.
    public static func publishActive(path: String?, markerPath: String? = nil) throws {
        let marker = markerPath ?? activeMarkerPath()
        let url = URL(fileURLWithPath: marker)
        guard let path, !path.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(ActiveMarker(path: path)).write(to: url, options: .atomic)
    }

    private static func markerLogPath(_ markerPath: String) -> String? {
        guard let data = FileManager.default.contents(atPath: markerPath),
              let marker = try? JSONDecoder().decode(ActiveMarker.self, from: data),
              !marker.path.isEmpty else {
            return nil
        }
        return marker.path
    }

    /// Resolves the active log, most specific source first: an explicit path, then the
    /// environment, then the marker written when a recording started.
    /// Returns nil when nothing is recording — callers then post events without metadata.
    public static func active(
        explicitPath: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        markerPath: String? = nil
    ) -> ActionPointerEventLog? {
        let candidate = [
            explicitPath,
            environment[ActionPointerEventLogFormat.environmentKey],
            markerLogPath(markerPath ?? activeMarkerPath()),
        ]
            .compactMap { $0 }
            .first(where: { !$0.isEmpty })
        guard let candidate else {
            return nil
        }
        // A missing or unreadable log must never block an action from being performed.
        return try? open(path: candidate)
    }

    /// Milliseconds between the log's start reference and a given system uptime reading.
    public func elapsedMs(atUptime uptime: Double) -> Double {
        (uptime - header.startedAtUptime) * 1000.0
    }

    public func makeEvent(
        correlationId: String,
        gesture: ActionPointerGestureKind,
        phase: ActionPointerPhase,
        button: ActionPointerButton,
        point: CGPoint,
        source: String,
        holdMs: Double? = nil,
        now: Date = Date(),
        uptime: Double = ProcessInfo.processInfo.systemUptime
    ) -> ActionPointerEvent {
        ActionPointerEvent(
            recordingId: header.recordingId,
            sessionId: header.sessionId,
            correlationId: correlationId,
            gesture: gesture,
            phase: phase,
            button: button,
            point: point,
            recordingElapsedMs: elapsedMs(atUptime: uptime),
            at: Self.isoString(from: now),
            uptime: uptime,
            holdMs: holdMs,
            source: source
        )
    }

    /// Appends one event as a single line. `O_APPEND` plus a one-shot `write` keeps concurrent
    /// host processes from interleaving partial lines.
    public func append(_ event: ActionPointerEvent) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var line = try encoder.encode(event)
        line.append(0x0a)

        // `Darwin.open` is qualified because this type also declares a static `open(path:)`.
        let descriptor = Darwin.open(path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard descriptor >= 0 else {
            throw ActionPointerEventLogError.unwritable(path)
        }
        defer { Darwin.close(descriptor) }

        try line.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else {
                return
            }
            var written = 0
            while written < buffer.count {
                let result = Darwin.write(descriptor, base.advanced(by: written), buffer.count - written)
                guard result > 0 else {
                    throw ActionPointerEventLogError.unwritable(path)
                }
                written += result
            }
        }
    }

    /// Decodes the pointer events in a chunk of log text, ignoring the header and any line a
    /// newer writer added that this reader does not understand.
    public static func decodeEvents(from text: String) -> [ActionPointerEvent] {
        let decoder = JSONDecoder()
        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                guard let data = line.data(using: .utf8) else {
                    return nil
                }
                return try? decoder.decode(ActionPointerEvent.self, from: data)
            }
    }
}
