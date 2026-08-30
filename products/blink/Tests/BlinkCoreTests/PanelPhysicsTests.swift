import CoreGraphics
import Testing
@testable import BlinkCore

@Suite("Panel physics")
struct PanelPhysicsTests {
    private let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let size = CGSize(width: 200, height: 150)

    private func fling(
        origin: CGPoint, velocity: CGPoint,
        friction: Double = 3.2, damping: Double = 0.6, rest: Double = 30,
        bounds: CGRect? = nil
    ) -> FlingIntegrator {
        FlingIntegrator(
            origin: origin, velocity: velocity, size: size,
            bounds: bounds ?? self.bounds,
            friction: friction, bounceDamping: damping, restSpeed: rest
        )
    }

    /// Run a glide to rest (or a generous cap), returning the final integrator
    /// and how many steps it took.
    private func runToRest(_ f: FlingIntegrator, dt: Double = 1.0 / 240) -> (FlingIntegrator, Int) {
        var f = f
        var steps = 0
        while steps < 240 * 10, f.step(dt: dt) { steps += 1 }
        return (f, steps)
    }

    @Test("zero velocity is an immediate no-op")
    func zeroVelocity() {
        var f = fling(origin: CGPoint(x: 100, y: 100), velocity: .zero)
        #expect(f.step(dt: 1.0 / 60) == false)
        #expect(f.origin == CGPoint(x: 100, y: 100))
        #expect(f.velocity == .zero)
    }

    @Test("exponential friction decays a glide to rest")
    func decaysToRest() {
        // Roomy bounds so nothing bounces; travel should approach v0/friction.
        let room = CGRect(x: -10_000, y: -10_000, width: 20_000, height: 20_000)
        let (f, steps) = runToRest(
            fling(origin: .zero, velocity: CGPoint(x: 2000, y: 0), bounds: room)
        )
        #expect(steps > 0)
        #expect(f.velocity == .zero)
        // Integral of 2000·e^(−3.2t) is 625; Euler integration lands within a few %.
        #expect(abs(Double(f.origin.x) - 625) < 40)
        // And rest arrives in a human-scale time, not an asymptotic forever.
        #expect(Double(steps) / 240 < 2.5)
    }

    @Test("edge bounce reflects and damps the normal velocity")
    func bounce() {
        // 100pt from the right edge (maxX = 1000 − 200 = 800), moving right.
        var f = fling(origin: CGPoint(x: 700, y: 400), velocity: CGPoint(x: 1000, y: 0))
        var bounced = false
        var preBounceSpeed = 0.0
        for _ in 0 ..< 240 {
            let before = f.velocity.x
            _ = f.step(dt: 1.0 / 240)
            if f.velocity.x < 0, before > 0 {
                bounced = true
                preBounceSpeed = Double(before)
                break
            }
        }
        #expect(bounced)
        #expect(f.origin.x == 800)  // clamped exactly onto the edge
        // Reflection kept 60% of the speed it carried into the wall.
        #expect(abs(Double(f.velocity.x)) - 0.6 * preBounceSpeed < 1)
        #expect(f.velocity.y == 0)
    }

    @Test("a diagonal fling settles inside the bounds")
    func settlesInside() {
        let (f, _) = runToRest(fling(origin: CGPoint(x: 100, y: 100), velocity: CGPoint(x: 3000, y: 2500)))
        #expect(f.velocity == .zero)
        #expect(f.origin.x >= 0 && f.origin.x <= 800)
        #expect(f.origin.y >= 0 && f.origin.y <= 650)
    }

    @Test("a panel larger than the bounds clamps instead of vibrating")
    func oversized() {
        var f = FlingIntegrator(
            origin: CGPoint(x: 50, y: 50), velocity: CGPoint(x: -500, y: 500),
            size: CGSize(width: 2000, height: 150),
            bounds: bounds, friction: 3.2, bounceDamping: 0.6, restSpeed: 30
        )
        _ = f.step(dt: 1.0 / 60)
        #expect(f.origin.x == 0)
        #expect(f.velocity.x == 0)
    }
}

@Suite("Drag velocity tracker")
struct DragVelocityTrackerTests {
    @Test("no or one sample reads as zero")
    func insufficient() {
        var t = DragVelocityTracker()
        #expect(t.velocity() == .zero)
        t.add(CGPoint(x: 5, y: 5), at: 1.0)
        #expect(t.velocity() == .zero)
    }

    @Test("constant motion estimates exactly")
    func constantVelocity() {
        var t = DragVelocityTracker(window: 0.1)
        t.add(CGPoint(x: 0, y: 0), at: 0.0)
        t.add(CGPoint(x: 100, y: -50), at: 0.05)
        t.add(CGPoint(x: 200, y: -100), at: 0.1)
        #expect(t.velocity() == CGPoint(x: 2000, y: -1000))
    }

    @Test("old samples fall out of the trailing window")
    func pruning() {
        var t = DragVelocityTracker(window: 0.1)
        t.add(CGPoint(x: 0, y: 0), at: 0.0)      // stale by the end
        t.add(CGPoint(x: 10, y: 0), at: 0.09)
        t.add(CGPoint(x: 210, y: 0), at: 0.14)
        t.add(CGPoint(x: 410, y: 0), at: 0.19)
        // Retained window is [0.09, 0.19] — the slow crawl at the start is
        // gone and the flick (200pt per 0.05s) reads at its true 4000pt/s.
        #expect(t.velocity() == CGPoint(x: 4000, y: 0))
    }
}

@Suite("Shake detector")
struct ShakeDetectorTests {
    /// Feed samples of x = amplitude·sin(2π·frequency·t) at 120Hz, returning
    /// whether the detector ever fired.
    private func shakeFires(amplitude: Double, frequency: Double, seconds: Double, y: (Double) -> Double = { _ in 0 }) -> Bool {
        var d = ShakeDetector()
        var t = 0.0
        while t <= seconds {
            if d.add(CGPoint(x: amplitude * sin(2 * .pi * frequency * t), y: y(t)), at: t) { return true }
            t += 1.0 / 120
        }
        return false
    }

    @Test("a real shake fires")
    func shakes() {
        // 100pt swing, 3Hz → 6 reversals/sec: 3 land well inside 0.6s.
        #expect(shakeFires(amplitude: 100, frequency: 3, seconds: 1.0))
    }

    @Test("small wiggles never reach the amplitude floor")
    func tooSmall() {
        // Amplitude counts per reversal LEG (peak-to-trough), so a ±15pt
        // wiggle has 30pt legs — under the 40pt floor.
        #expect(!shakeFires(amplitude: 15, frequency: 3, seconds: 1.5))
    }

    @Test("slow sways fall outside the time window")
    func tooSlow() {
        // 0.8Hz → a reversal every 0.625s: three never fit in 0.6s.
        #expect(!shakeFires(amplitude: 100, frequency: 0.8, seconds: 3.0))
    }

    @Test("a steady drag is not a shake")
    func steadyDrag() {
        var d = ShakeDetector()
        var t = 0.0
        var fired = false
        while t <= 1.0 {
            if d.add(CGPoint(x: 500 * t, y: 0), at: t) { fired = true; break }
            t += 1.0 / 120
        }
        #expect(!fired)
    }

    @Test("vertical shaking does not count")
    func verticalOnly() {
        var d = ShakeDetector()
        var t = 0.0
        var fired = false
        while t <= 1.0 {
            if d.add(CGPoint(x: 0, y: 100 * sin(2 * .pi * 3 * t)), at: t) { fired = true; break }
            t += 1.0 / 120
        }
        #expect(!fired)
    }

    @Test("climbing while shaking suppresses the gesture")
    func verticalDrift() {
        #expect(!shakeFires(amplitude: 100, frequency: 3, seconds: 1.0) { 300 * $0 })
    }
}
