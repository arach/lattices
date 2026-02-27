import Foundation

enum ModelEvent {
    case windowsChanged(windows: [WindowEntry], added: [UInt32], removed: [UInt32])
    case tmuxChanged(sessions: [TmuxSession])
    case layerSwitched(index: Int)
}

final class EventBus {
    static let shared = EventBus()
    private var handlers: [(ModelEvent) -> Void] = []
    private let lock = NSLock()

    func subscribe(_ handler: @escaping (ModelEvent) -> Void) {
        lock.lock()
        handlers.append(handler)
        lock.unlock()
    }

    func post(_ event: ModelEvent) {
        lock.lock()
        let copy = handlers
        lock.unlock()
        for handler in copy {
            handler(event)
        }
    }
}
