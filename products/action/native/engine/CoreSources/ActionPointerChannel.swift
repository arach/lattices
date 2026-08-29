import CoreGraphics
import Foundation

/// Outcome of one Action-driven pointer gesture, returned so callers can report the correlation
/// id that ties the gesture to its rows in the pointer event log.
public struct ActionPointerGesture: Equatable, Sendable {
    public let correlationId: String
    /// Nil when no recording was active, which is the default, opt-out-free case.
    public let recordingId: String?
    public let recorded: Bool
    /// Measured press duration in milliseconds.
    public let holdMs: Double
}

/// A press that is open. The caller may post its own intermediate motion before releasing.
/// Not `Sendable`: a press is held open across a single synchronous call stack, and the
/// `CGEventSource` it carries is not safe to move between isolation domains.
public struct ActionPointerPress {
    public let correlationId: String
    public let startPoint: CGPoint
    fileprivate let log: ActionPointerEventLog?
    fileprivate let source: String
    fileprivate let button: ActionPointerButton
    fileprivate let gesture: ActionPointerGestureKind
    fileprivate let eventSource: CGEventSource?
    fileprivate let pressedAtUptime: Double
}

public enum ActionPointerChannelError: LocalizedError {
    case eventCreationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .eventCreationFailed(let detail):
            return detail
        }
    }
}

/// The one place Action synthesizes primary-button events.
///
/// Both the coordinate click path and the drag path post through here, so a single definition of
/// "an Action click happened" produces the recorded metadata and, when the operator opted in, the
/// pulse the viewer sees. Nothing in this file touches `NSCursor` or draws anything: the real
/// macOS pointer stays exactly as the system renders it.
public enum ActionPointerChannel {
    /// Matches the historical inline behaviour: settle time after warping the pointer.
    private static let warpSettleMicroseconds: useconds_t = 10_000

    /// Warps to `point`, posts a primary down/up pair holding for `holdMs`, and records both
    /// phases. A `holdMs` above a plain click is how press-and-hold affordances are triggered.
    @discardableResult
    public static func primaryClick(
        at point: CGPoint,
        holdMs: Int,
        source: String,
        eventSource: CGEventSource? = nil,
        log: ActionPointerEventLog? = ActionPointerEventLog.active()
    ) throws -> ActionPointerGesture {
        let press = try beginPrimaryPress(
            at: point,
            gesture: .click,
            source: source,
            eventSource: eventSource,
            log: log
        )
        usleep(useconds_t(max(1, holdMs) * 1000))
        return try endPrimaryPress(press, at: point)
    }

    /// Warps to `point` and posts a primary button down. The caller owns any motion that follows
    /// and must finish with `endPrimaryPress`.
    public static func beginPrimaryPress(
        at point: CGPoint,
        gesture: ActionPointerGestureKind,
        source: String,
        eventSource: CGEventSource? = nil,
        log: ActionPointerEventLog? = ActionPointerEventLog.active()
    ) throws -> ActionPointerPress {
        CGWarpMouseCursorPosition(point)
        usleep(warpSettleMicroseconds)

        guard let down = CGEvent(
            mouseEventSource: eventSource,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            throw ActionPointerChannelError.eventCreationFailed("Unable to create mouse events")
        }

        let correlationId = makeCorrelationID()
        down.post(tap: .cghidEventTap)
        // Stamped immediately after the post so the recorded time is the time the system saw the
        // press, not the time bookkeeping finished.
        let pressedAtUptime = ProcessInfo.processInfo.systemUptime

        record(
            log: log,
            correlationId: correlationId,
            gesture: gesture,
            phase: .down,
            button: .left,
            point: point,
            source: source,
            holdMs: nil,
            uptime: pressedAtUptime
        )

        return ActionPointerPress(
            correlationId: correlationId,
            startPoint: point,
            log: log,
            source: source,
            button: .left,
            gesture: gesture,
            eventSource: eventSource,
            pressedAtUptime: pressedAtUptime
        )
    }

    /// Posts the matching button up and records the measured hold duration.
    @discardableResult
    public static func endPrimaryPress(
        _ press: ActionPointerPress,
        at point: CGPoint
    ) throws -> ActionPointerGesture {
        guard let up = CGEvent(
            mouseEventSource: press.eventSource,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            throw ActionPointerChannelError.eventCreationFailed("Unable to create mouse events")
        }

        up.post(tap: .cghidEventTap)
        let releasedAtUptime = ProcessInfo.processInfo.systemUptime
        let holdMs = (releasedAtUptime - press.pressedAtUptime) * 1000.0

        record(
            log: press.log,
            correlationId: press.correlationId,
            gesture: press.gesture,
            phase: .up,
            button: press.button,
            point: point,
            source: press.source,
            holdMs: holdMs,
            uptime: releasedAtUptime
        )

        return ActionPointerGesture(
            correlationId: press.correlationId,
            recordingId: press.log?.header.recordingId,
            recorded: press.log != nil,
            holdMs: holdMs
        )
    }

    /// Appending is presentation and provenance, never a reason to fail an action the system has
    /// already carried out — the button events are posted before this runs.
    private static func record(
        log: ActionPointerEventLog?,
        correlationId: String,
        gesture: ActionPointerGestureKind,
        phase: ActionPointerPhase,
        button: ActionPointerButton,
        point: CGPoint,
        source: String,
        holdMs: Double?,
        uptime: Double
    ) {
        guard let log else {
            return
        }
        let event = log.makeEvent(
            correlationId: correlationId,
            gesture: gesture,
            phase: phase,
            button: button,
            point: point,
            source: source,
            holdMs: holdMs,
            uptime: uptime
        )
        try? log.append(event)
    }

    private static func makeCorrelationID() -> String {
        "pe_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))"
    }
}
