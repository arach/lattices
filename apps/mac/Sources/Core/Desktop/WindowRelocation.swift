import Foundation
import CoreGraphics

/// A relocation is a window mutation, not a change to the desktop being viewed.
/// Keep the ordering and verification independent of AX/Mission Control so a
/// refused operation cannot become a successful receipt in either the UI or API.
enum WindowRelocation {
    struct Display: Equatable {
        let id: String
        let index: Int
        let currentSpaceId: Int
        let spaceIds: [Int]
    }

    struct Snapshot: Equatable {
        let frame: CGRect?
        let displayId: String?
        let spaceIds: [Int]
    }

    struct Destination {
        let displayId: String
        let spaceId: Int
        let frame: CGRect
    }

    struct Environment {
        var displays: () -> [Display]
        var snapshot: () -> Snapshot
        /// Returns an error on refusal; a nil error is still independently verified.
        var moveSpace: (Int) -> String?
        var moveFrame: (CGRect) -> Void
        var wait: (@escaping (Snapshot) -> Bool) -> Snapshot
    }

    struct Result {
        let verified: Bool
        let after: Snapshot
        let failure: String?
        let trace: [String]
        let rollbackAttempted: Bool
        let rollbackVerified: Bool

        /// The UI must report partial failure, not just the original AX error.
        var recoveryMessage: String? {
            guard !verified else { return nil }
            if rollbackVerified {
                return rollbackAttempted
                    ? "The original display, desktop, and frame were restored."
                    : "The original display, desktop, and frame are unchanged."
            }
            return "The original position could not be restored. Locate the window in Overview and retry with an available display and desktop."
        }
    }

    static func matches(_ snapshot: Snapshot, destination: Destination, tolerance: CGFloat) -> Bool {
        snapshot.displayId == destination.displayId &&
            snapshot.spaceIds == [destination.spaceId] &&
            snapshot.frame.map { framesClose($0, destination.frame, tolerance: tolerance) } == true
    }

    static func framesClose(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance && abs(lhs.minY - rhs.minY) <= tolerance &&
            abs(lhs.width - rhs.width) <= tolerance && abs(lhs.height - rhs.height) <= tolerance
    }

    /// Shared guard for undo receipts, including legacy frame-only receipts.
    static func undoConflict(frame: CGRect?, expectedFrame: CGRect?,
                             spaceIds: [Int], expectedSpaceIds: [Int]?,
                             tolerance: CGFloat) -> String? {
        if let expectedSpaceIds, spaceIds.sorted() != expectedSpaceIds.sorted() {
            return "current-space-mismatch"
        }
        guard let frame else { return "window-frame-unavailable" }
        if let expectedFrame, !framesClose(frame, expectedFrame, tolerance: tolerance) {
            return "current-frame-mismatch"
        }
        return nil
    }

    static func execute(
        from before: Snapshot,
        to destination: Destination,
        tolerance: CGFloat,
        environment: Environment
    ) -> Result {
        var trace: [String] = []
        // Reject a stale plan without restoring it over a newer user move.
        let observed = environment.snapshot()
        guard observed == before else {
            return Result(verified: false, after: observed,
                          failure: "Window changed before relocation; refresh and retry",
                          trace: ["rejected stale source snapshot; no mutation attempted"],
                          rollbackAttempted: false, rollbackVerified: false)
        }
        let failure = transfer(from: before, to: destination, tolerance: tolerance, environment: environment, trace: &trace)
        let after = environment.snapshot()
        if failure == nil, matches(after, destination: destination, tolerance: tolerance) {
            return Result(verified: true, after: after, failure: nil, trace: trace,
                          rollbackAttempted: false, rollbackVerified: false)
        }

        let reason = failure ?? "Final display, desktop, and geometry could not be verified"
        trace.append("failed: \(reason)")
        // A failed AX call often changes nothing. Do not open Mission Control
        // needlessly, and never discard evidence of a partial move.
        guard let frame = before.frame, let displayId = before.displayId,
              before.spaceIds.count == 1, let spaceId = before.spaceIds.first else {
            return Result(verified: false, after: after, failure: reason, trace: trace,
                          rollbackAttempted: false, rollbackVerified: false)
        }
        let original = Destination(displayId: displayId, spaceId: spaceId, frame: frame)
        if matches(after, destination: original, tolerance: tolerance) {
            trace.append("original display, desktop, and frame are unchanged")
            return Result(verified: false, after: after, failure: reason, trace: trace,
                          rollbackAttempted: false, rollbackVerified: true)
        }
        trace.append("rollback: restoring original display, desktop, and frame")
        let rollbackFailure = transfer(from: after, to: original, tolerance: tolerance, environment: environment, trace: &trace)
        let restored = environment.snapshot()
        let rollbackVerified = rollbackFailure == nil && matches(restored, destination: original, tolerance: tolerance)
        trace.append(rollbackVerified ? "rollback verified" : "rollback failed: \(rollbackFailure ?? "final state did not match")")
        return Result(verified: false, after: restored, failure: reason, trace: trace,
                      rollbackAttempted: true, rollbackVerified: rollbackVerified)
    }

    private static func transfer(
        from before: Snapshot,
        to destination: Destination,
        tolerance: CGFloat,
        environment: Environment,
        trace: inout [String]
    ) -> String? {
        guard tolerance.isFinite, tolerance >= 0,
              validFrame(destination.frame), let sourceFrame = before.frame,
              validFrame(sourceFrame) else {
            return "Window relocation requires finite, positive source and destination frames"
        }
        let displays = environment.displays()
        guard before.spaceIds.count == 1, let sourceSpace = before.spaceIds.first,
              let source = displays.first(where: { $0.spaceIds.contains(sourceSpace) }),
              source.id == before.displayId else {
            return "Source window must belong to one ordinary desktop on its observed display"
        }
        guard let target = displays.first(where: { $0.id == destination.displayId }),
              target.spaceIds.contains(destination.spaceId) else {
            return "Destination desktop does not belong to the selected display"
        }
        if matches(before, destination: destination, tolerance: tolerance) {
            trace.append("already at verified destination")
            return nil
        }
        let needsFrame = source.id != target.id ||
            before.frame.map { !framesClose($0, destination.frame, tolerance: tolerance) } != false
        var current = before

        if needsFrame {
            guard source.spaceIds.contains(source.currentSpaceId), target.spaceIds.contains(target.currentSpaceId) else {
                return "A display is showing a full-screen Space; select an ordinary desktop before moving geometry"
            }
            // AX can report success while ignoring geometry writes to a window
            // on an inactive desktop. Materialize it on its source display's
            // current desktop first; activating its app is insufficient.
            if sourceSpace != source.currentSpaceId {
                trace.append("stage source desktop \(sourceSpace) → \(source.currentSpaceId)")
                if let error = environment.moveSpace(source.currentSpaceId) { return "Source staging failed: \(error)" }
                let staged = Destination(displayId: source.id, spaceId: source.currentSpaceId, frame: before.frame ?? destination.frame)
                // Membership may update before Mission Control's thumbnail
                // animation ends. AX must see the actual window again.
                current = environment.wait { matches($0, destination: staged, tolerance: tolerance) }
                guard matches(current, destination: staged, tolerance: tolerance) else {
                    return "Source desktop staging was not verified"
                }
            }
            // Staging may take seconds. Never use an earlier display snapshot
            // to write geometry after a display disconnect or desktop switch.
            guard environment.displays() == displays else {
                return "Display topology or current desktop changed during source staging; retry"
            }
            trace.append("apply frame on display \(target.index), desktop \(target.currentSpaceId)")
            environment.moveFrame(destination.frame)
            let activeDestination = Destination(displayId: target.id, spaceId: target.currentSpaceId, frame: destination.frame)
            current = environment.wait { matches($0, destination: activeDestination, tolerance: tolerance) }
            guard matches(current, destination: activeDestination, tolerance: tolerance) else {
                return "Display transfer did not reach the target display, active desktop, and frame"
            }
        }

        if current.spaceIds != [destination.spaceId] {
            guard environment.displays().contains(where: {
                $0.id == destination.displayId && $0.spaceIds.contains(destination.spaceId)
            }) else {
                return "Destination desktop is no longer on the selected display"
            }
            trace.append("move desktop \(current.spaceIds) → \(destination.spaceId) on display \(target.index)")
            if let error = environment.moveSpace(destination.spaceId) { return "Destination desktop move failed: \(error)" }
        }
        let final = environment.wait { matches($0, destination: destination, tolerance: tolerance) }
        guard matches(final, destination: destination, tolerance: tolerance) else {
            return "Final display, desktop, and geometry did not match the destination"
        }
        trace.append("verified display \(target.index), desktop \(destination.spaceId), and frame")
        return nil
    }

    private static func validFrame(_ frame: CGRect) -> Bool {
        frame.origin.x.isFinite && frame.origin.y.isFinite &&
            frame.width.isFinite && frame.height.isFinite &&
            frame.width > 0 && frame.height > 0
    }
}

/// Mission Control has one global drag session. Runtime relocation, rollback,
/// undo and direct carry callers all use this gate. Recursive for carry within
/// a transaction; try-lock callers fail promptly rather than queue stale moves.
enum WindowRelocationGate {
    static let lock = NSRecursiveLock()
}
