import Foundation

/// Effect-independent undo stack. Production must supply an explicit mutation
/// journal, not a before/after desktop diff (which could include user moves).
final class EditorUndo {
    struct WindowState {
        let id: UInt32
        let pid: Int32
        let frame: CGRect
        let displayId: String
    }
    enum Move {
        case frame(before: WindowState, after: WindowState, parked: Bool)
        case hide(pid: Int32, wasHidden: Bool)
    }
    struct Entry {
        let actionId: String
        let label: String
        let at: Date
        let opened: Bool
        let moves: [Move]
        var undone = false
    }
    struct Environment {
        var window: (UInt32) -> WindowState?
        var restore: (WindowState, Bool) -> Bool
        var isHidden: (Int32) -> Bool?
        var unhide: (Int32) -> Bool
    }
    struct Result {
        var restored = 0
        var skipped: [String] = []
        let openedAppsStayOpen: Bool
    }
    private(set) var entries: [Entry] = []
    var newestUndoableActionId: String? { entries.first(where: { !$0.undone })?.actionId }

    func record(_ entry: Entry) {
        entries.insert(entry, at: 0)
        entries = Array(entries.prefix(10))
    }

    /// Consume before executing. Even a partially failed undo cannot be replayed.
    func undo(_ actionId: String, environment: Environment) throws -> Result {
        guard actionId == newestUndoableActionId,
              let index = entries.firstIndex(where: { $0.actionId == actionId }) else {
            throw EditorBridgeError("undo_order", "Undo the newest action first.")
        }
        let entry = entries[index]
        entries[index].undone = true
        var result = Result(openedAppsStayOpen: entry.opened)
        for move in entry.moves.reversed() {
            switch move {
            case let .frame(before, after, parked):
                guard let current = environment.window(after.id), current.pid == after.pid else {
                    result.skipped.append("Window \(after.id) no longer exists.")
                    continue
                }
                guard current.displayId == after.displayId, Self.matches(current.frame, after.frame) else {
                    result.skipped.append("Window \(after.id) moved since this action.")
                    continue
                }
                if environment.restore(before, parked) { result.restored += 1 }
                else { result.skipped.append("Window \(before.id) could not be restored.") }
            case let .hide(pid, wasHidden):
                // Never unhide an app the user had already hidden.
                guard !wasHidden else { continue }
                guard let hidden = environment.isHidden(pid) else {
                    result.skipped.append("App \(pid) no longer exists.")
                    continue
                }
                guard hidden else { continue }
                if environment.unhide(pid) { result.restored += 1 }
                else { result.skipped.append("App \(pid) could not be unhidden.") }
            }
        }
        return result
    }

    private static func matches(_ a: CGRect, _ b: CGRect) -> Bool {
        [a.minX - b.minX, a.minY - b.minY, a.width - b.width, a.height - b.height]
            .allSatisfy { $0.isFinite && abs($0) <= 3 }
    }
}
