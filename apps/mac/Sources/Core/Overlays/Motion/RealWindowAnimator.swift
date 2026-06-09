import AppKit
import ApplicationServices
import QuartzCore

// MARK: - RealWindowAnimator
//
// Animates a *real* desktop window (a resolved AX element) from its current
// frame to a target by interpolating AX position+size each tick. The motion
// has a little "actor" physics: a tiny wind-up (anticipation), an accelerating
// drift along a gentle arc, then it sticks the landing — no springy bounce.
//
// Frames are AX coordinates (top-left origin), matching WindowTiler.tileFrame.

final class RealWindowAnimator {
    private let axWin: AXUIElement
    private var timer: Timer?
    private var startTime: CFTimeInterval = 0
    private var fromFrame: CGRect = .zero
    private var toFrame: CGRect = .zero
    private var duration: CFTimeInterval = 0.28
    private var delay: CFTimeInterval = 0
    private var bow: CGFloat = 0
    private var snap = false
    private var onDone: (() -> Void)?

    init(axWin: AXUIElement) {
        self.axWin = axWin
    }

    /// `snap` = crisp, no arc (for small nudge/resize increments).
    func animate(to target: CGRect,
                 duration: CFTimeInterval = 0.28,
                 delay: CFTimeInterval = 0,
                 snap: Bool = false,
                 completion: (() -> Void)? = nil) {
        cancel()
        guard let current = RealWindowAnimator.axFrame(axWin) else {
            RealWindowAnimator.setFrame(axWin, target)
            completion?()
            return
        }
        fromFrame = current
        toFrame = target
        self.duration = max(duration, 0.01)
        self.delay = delay
        self.snap = snap
        onDone = completion
        // A faint directionality arc on glides only; none for snaps.
        bow = snap ? 0 : min(hypot(target.midX - current.midX, target.midY - current.midY) * 0.06, 28)

        startTime = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let elapsed = CACurrentMediaTime() - startTime - delay
        if elapsed < 0 { return }  // still in stagger delay → hold at start
        let raw = min(max(elapsed / duration, 0), 1)

        // Clean ease-out (no wind-up). Snaps decelerate a touch faster.
        let p = snap ? RealWindowAnimator.easeOut(raw) : RealWindowAnimator.easeOutCubic(raw)
        let e = RealWindowAnimator.easeOut(raw)

        let w = lerp(fromFrame.width, toFrame.width, e)
        let h = lerp(fromFrame.height, toFrame.height, e)

        let fc = CGPoint(x: fromFrame.midX, y: fromFrame.midY)
        let tc = CGPoint(x: toFrame.midX, y: toFrame.midY)
        var cx = lerp(fc.x, tc.x, p)
        var cy = lerp(fc.y, tc.y, p)

        if bow != 0 {
            let dx = tc.x - fc.x, dy = tc.y - fc.y
            let dist = max(hypot(dx, dy), 1)
            let peak = sin(CGFloat(raw) * .pi) * bow      // lateral drift, 0 at ends
            cx += (-dy / dist) * peak
            cy += (dx / dist) * peak
        }

        RealWindowAnimator.setFrame(axWin, CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h))

        if raw >= 1 {
            RealWindowAnimator.setFrame(axWin, toFrame)  // land exactly on target
            cancel()
            onDone?()
            onDone = nil
        }
    }

    // MARK: - Easing

    static func easeOutCubic(_ t: Double) -> Double {
        let x = max(0, min(1, t))
        return 1 - pow(1 - x, 3)
    }

    static func easeOut(_ t: Double) -> Double {
        let x = max(0, min(1, t))
        return 1 - pow(1 - x, 2.2)
    }

    // MARK: - AX resolution

    /// Resolve the AX element for a window. Tries exact CGWindowID match, then
    /// (crucially, for apps like Chrome whose CG numbers don't map to AX) the
    /// window whose frame matches `expectedFrame`, then single-window / main.
    static func resolve(wid: UInt32, pid: Int32, expectedFrame: CGRect?) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref) == .success,
           let windows = ref as? [AXUIElement] {
            // 1. Exact CGWindowID match.
            for w in windows {
                var id: CGWindowID = 0
                if _AXUIElementGetWindow(w, &id) == .success, id == wid { return w }
            }
            // 2. Best frame match — picks the *right* window among several.
            if let expected = expectedFrame {
                var best: AXUIElement?
                var bestDelta = CGFloat.greatestFiniteMagnitude
                for w in windows {
                    guard let f = axFrame(w) else { continue }
                    let delta = abs(f.minX - expected.minX) + abs(f.minY - expected.minY)
                        + abs(f.width - expected.width) + abs(f.height - expected.height)
                    if delta < bestDelta { bestDelta = delta; best = w }
                }
                if let best, bestDelta < 40 { return best }
            }
            // 3. Single-window app.
            if windows.count == 1 { return windows.first }
        }
        // 4. Last resort: the app's main / focused window.
        for attr in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
            var wref: CFTypeRef?
            if AXUIElementCopyAttributeValue(app, attr as CFString, &wref) == .success,
               let value = wref, CFGetTypeID(value) == AXUIElementGetTypeID() {
                return (value as! AXUIElement)
            }
        }
        return nil
    }

    static func axFrame(_ el: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef else { return nil }
        var p = CGPoint.zero
        var s = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &p)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &s)
        return CGRect(origin: p, size: s)
    }

    static func setFrame(_ el: AXUIElement, _ f: CGRect) {
        var size = CGSize(width: f.width, height: f.height)
        if let sv = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, sv)
        }
        var pos = CGPoint(x: f.minX, y: f.minY)
        if let pv = AXValueCreate(.cgPoint, &pos) {
            AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, pv)
        }
    }

    /// Move a window *robustly*. Apps that participate in macOS window tiling —
    /// or otherwise turn on "enhanced UI" — lock their AX size/position so a
    /// plain set silently fails (iTerm2 is the classic case). Disabling
    /// AXEnhancedUserInterface around a size→position→size set breaks that lock,
    /// then we restore the app's prior setting. Same recipe as WindowTiler.
    static func setFrameRobust(_ el: AXUIElement, _ f: CGRect, pid: Int32, raise shouldRaise: Bool = false) {
        let app = AXUIElementCreateApplication(pid)
        var priorRef: CFTypeRef?
        let prior = AXUIElementCopyAttributeValue(app, "AXEnhancedUserInterface" as CFString, &priorRef) == .success
            ? (priorRef as? Bool ?? false) : false
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, false as CFTypeRef)

        var size = CGSize(width: f.width, height: f.height)
        var pos = CGPoint(x: f.minX, y: f.minY)
        if let sv = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, sv) }
        if let pv = AXValueCreate(.cgPoint, &pos) { AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, pv) }
        if let sv = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, sv) }

        if shouldRaise { raise(el) }

        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, prior as CFTypeRef)
    }

    /// Bring a window to the front of the global window order *without* activating
    /// its app — so an overlay that's driving the motion keeps key focus/input.
    static func raise(_ el: AXUIElement) {
        AXUIElementPerformAction(el, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(el, kAXMainAttribute as CFString, kCFBooleanTrue)
    }
}

private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }
