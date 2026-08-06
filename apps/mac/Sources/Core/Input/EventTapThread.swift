import Foundation
import CoreFoundation

/// Hosts a long-lived thread + CFRunLoop dedicated to CGEventTap callbacks.
///
/// **Important:** keyboard and mouse must *not* share a run loop. Both taps
/// used `EventTapThread.shared` for months of fine Hyper/gestures — then under
/// load a 40ms+ mouse callback serialized *keyboard* delivery on the same
/// thread and macOS delayed typing system-wide. That is a regression, not an
/// inherent limit of event taps.
///
/// Callbacks fire on this thread — hop AppKit/UI work to main yourself.
final class EventTapThread {
    /// Keyboard remap / Hyper only.
    static let keyboard = EventTapThread(name: "dev.lattices.app.EventTap.keyboard")
    /// Mouse gestures only.
    static let mouse = EventTapThread(name: "dev.lattices.app.EventTap.mouse")
    /// Escape / focus / chord taps that must not contend with keyboard Hyper.
    static let overlay = EventTapThread(name: "dev.lattices.app.EventTap.overlay")

    /// Legacy alias — prefer `.keyboard` / `.mouse` / `.overlay`.
    static var shared: EventTapThread { keyboard }

    private let lock = NSLock()
    private var runLoop: CFRunLoop?
    private let threadName: String

    init(name: String) {
        self.threadName = name
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
        thread.name = name
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
