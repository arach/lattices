import Foundation
import CoreFoundation

/// Hosts a long-lived thread + CFRunLoop dedicated to CGEventTap callbacks,
/// so taps installed at `.headInsertEventTap` don't add main-thread latency
/// to every keyboard/mouse event in the user's session.
///
/// Callbacks fire on this thread — callers must hop AppKit/UI work back to
/// main themselves (DispatchQueue.main.async).
final class EventTapThread {
    static let shared = EventTapThread()

    private let lock = NSLock()
    private var runLoop: CFRunLoop?

    private init() {
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [unowned self] in
            let loop = CFRunLoopGetCurrent()
            // Keep the run loop alive across add/remove cycles by anchoring a
            // no-op port; otherwise CFRunLoopRun() returns when the last
            // source is removed.
            let keepalive = NSMachPort()
            RunLoop.current.add(keepalive, forMode: .common)
            self.lock.lock()
            self.runLoop = loop
            self.lock.unlock()
            ready.signal()
            CFRunLoopRun()
        }
        thread.qualityOfService = .userInteractive
        thread.name = "com.arach.lattices.EventTapThread"
        thread.start()
        ready.wait()
    }

    func add(source: CFRunLoopSource) {
        lock.lock()
        let loop = runLoop
        lock.unlock()
        guard let loop else { return }
        CFRunLoopAddSource(loop, source, .commonModes)
        CFRunLoopWakeUp(loop)
    }

    func remove(source: CFRunLoopSource) {
        lock.lock()
        let loop = runLoop
        lock.unlock()
        guard let loop else { return }
        CFRunLoopRemoveSource(loop, source, .commonModes)
        CFRunLoopWakeUp(loop)
    }
}
