import AppKit
import ApplicationServices

/// Scoped to explicit native action execution. Hooks run at the mutation sites;
/// never infer ownership from a whole-desktop before/after difference.
final class EditorMutationJournal {
    static var current: EditorMutationJournal?
    private(set) var moves: [EditorUndo.Move] = []
    private(set) var sealed = false
    private var initialParked: [UInt32: LayerStage.ParkedWindow] = [:]

    init(parked: [LayerStage.ParkedWindow]? = nil) {
        initialParked = Dictionary((parked ?? LayerStage.shared.status().parked).map { ($0.wid, $0) },
                                  uniquingKeysWith: { first, _ in first })
    }

    func run<T>(_ body: () throws -> T) rethrows -> T {
        let previous = Self.current
        Self.current = self
        defer { Self.current = previous }
        return try body()
    }
    func seal() { sealed = true }

    struct Capture {
        let journal: EditorMutationJournal
        let before: EditorUndo.WindowState
        let ax: AXUIElement
        let parked: Bool
    }
    static func begin(wid: UInt32, ax: AXUIElement, parked: Bool = false) -> Capture? {
        guard let journal = current, !journal.sealed, let before = read(wid: wid, ax: ax) else { return nil }
        // Retain the before record before invoking AX. End fills actual readback.
        journal.moves.append(.frame(before: before, after: before, parked: parked))
        return Capture(journal: journal, before: before, ax: ax, parked: parked)
    }
    static func end(_ capture: Capture?) {
        guard let capture, !capture.journal.sealed else { return }
        let after = read(wid: capture.before.id, ax: capture.ax) ?? capture.before
        let journal = capture.journal
        // Fold repeated writes to this window into one reversible net move.
        var first = capture.before
        var parked = capture.parked
        journal.moves.removeAll { move in
            if case let .frame(before, _, wasParked) = move, before.id == capture.before.id {
                if first.frame == capture.before.frame { first = before }
                parked = parked || wasParked
                return true
            }
            return false
        }
        journal.moves.append(.frame(before: first, after: after, parked: parked))
    }
    static func hiding(_ app: NSRunningApplication) {
        guard let journal = current, !journal.sealed else { return }
        journal.moves.append(.hide(pid: app.processIdentifier, wasHidden: app.isHidden))
    }

    static func read(wid: UInt32, ax: AXUIElement) -> EditorUndo.WindowState? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(ax, &pid) == .success else { return nil }
        var p: CFTypeRef?, s: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ax, kAXPositionAttribute as CFString, &p) == .success,
              AXUIElementCopyAttributeValue(ax, kAXSizeAttribute as CFString, &s) == .success,
              let p, let s, CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(p, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeBitCast(s, to: AXValue.self), .cgSize, &size) else { return nil }
        let frame = CGRect(origin: point, size: size)
        let display = NSScreen.screens.max {
            let a = CGDisplayBounds(($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0).intersection(frame)
            let b = CGDisplayBounds(($1.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0).intersection(frame)
            return a.width * a.height < b.width * b.height
        }
        let id = (display?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? "unknown"
        return .init(id: wid, pid: pid, frame: frame, displayId: id)
    }
    static func axWindow(_ wid: UInt32, pid: Int32) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        return windows.first { ax in
            var id: CGWindowID = 0
            return _AXUIElementGetWindow(ax, &id) == .success && id == wid
        }
    }
    func environment() -> EditorUndo.Environment {
        let identities = Dictionary(moves.compactMap { move -> (UInt32, Int32)? in
            if case let .frame(before, _, _) = move { return (before.id, before.pid) }
            return nil
        }, uniquingKeysWith: { first, _ in first })
        return .init(window: { wid in
            guard let pid = identities[wid], let ax = Self.axWindow(wid, pid: pid) else { return nil }
            return Self.read(wid: wid, ax: ax)
        }, restore: { [self] before, _ in
            guard let ax = Self.axWindow(before.id, pid: before.pid) else { return false }
            WindowTiler.batchMoveWindows([(before.id, before.pid, before.frame)])
            guard let actual = Self.read(wid: before.id, ax: ax),
                  abs(actual.frame.minX - before.frame.minX) <= 3,
                  abs(actual.frame.minY - before.frame.minY) <= 3,
                  abs(actual.frame.width - before.frame.width) <= 3,
                  abs(actual.frame.height - before.frame.height) <= 3 else { return false }
            LayerStage.shared.editorRestored(window: before.id, parkedBefore: initialParked[before.id])
            return true
        }, isHidden: { NSRunningApplication(processIdentifier: $0)?.isHidden },
        unhide: { pid in
            guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
            app.unhide()
            LayerStage.shared.editorUnhid(pid)
            return true
        })
    }
}
