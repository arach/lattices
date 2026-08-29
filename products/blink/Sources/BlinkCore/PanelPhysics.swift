import CoreGraphics
import Foundation

/// Pure panel-physics primitives — the math behind Blink's "panel physics":
/// momentum fling (velocity decay, edge reflection, rest detection),
/// release-velocity estimation, and shake recognition. No AppKit: the window
/// glue (display link, event tracking, frame autosave) lives in BlinkApp and
/// drives these value types.

/// A flung panel's momentum integrator: one `step(dt:)` per display frame.
///
/// Velocity decays exponentially (`v *= exp(-friction * dt)`), the origin
/// integrates along it, and hitting an edge of `bounds` reflects that velocity
/// component scaled by `bounceDamping`. Below `restSpeed` the panel is at rest
/// and `step` returns false — the caller stops ticking and persists the frame.
/// Total glide distance is ~`speed / friction`, so friction is the one knob
/// that reads as "heft".
public struct FlingIntegrator: Equatable, Sendable {
    /// Window origin (AppKit bottom-left; the math is axis-symmetric so the
    /// coordinate handedness doesn't matter as long as `bounds` matches it).
    public var origin: CGPoint
    /// pt/s, per axis.
    public var velocity: CGPoint
    /// Panel size — fixed for the glide's lifetime.
    public var size: CGSize
    /// The rectangle the panel bounces within (a screen's `visibleFrame`).
    public var bounds: CGRect
    /// Exponential friction, 1/s. Higher = heavier, stops sooner.
    public var friction: Double
    /// Fraction of the normal velocity component kept after an edge bounce (0…1).
    public var bounceDamping: Double
    /// Speed (pt/s) below which the panel is declared at rest.
    public var restSpeed: Double

    public init(
        origin: CGPoint,
        velocity: CGPoint,
        size: CGSize,
        bounds: CGRect,
        friction: Double,
        bounceDamping: Double,
        restSpeed: Double
    ) {
        self.origin = origin
        self.velocity = velocity
        self.size = size
        self.bounds = bounds
        self.friction = friction
        self.bounceDamping = bounceDamping
        self.restSpeed = restSpeed
    }

    public var speed: Double {
        hypot(Double(velocity.x), Double(velocity.y))
    }

    /// Advance the glide by `dt` seconds. Returns false once at rest (velocity
    /// zeroed); a zero-velocity integrator is immediately at rest.
    @discardableResult
    public mutating func step(dt: Double) -> Bool {
        guard speed >= restSpeed else {
            velocity = .zero
            return false
        }
        guard dt > 0 else { return true }

        let decay = exp(-friction * dt)
        velocity = CGPoint(x: velocity.x * decay, y: velocity.y * decay)
        origin.x += velocity.x * CGFloat(dt)
        origin.y += velocity.y * CGFloat(dt)

        bounce(axis: \.x, length: \.width)
        bounce(axis: \.y, length: \.height)

        guard speed >= restSpeed else {
            velocity = .zero
            return false
        }
        return true
    }

    /// Reflect one axis at its bound, keeping `bounceDamping` of the speed.
    /// A panel larger than the bound clamps to the near edge and stops on
    /// that axis — there is no room to bounce in.
    private mutating func bounce(axis: WritableKeyPath<CGPoint, CGFloat>, length: KeyPath<CGSize, CGFloat>) {
        let lo = bounds.origin[keyPath: axis]
        let hi = lo + bounds.size[keyPath: length] - size[keyPath: length]
        if hi <= lo {
            origin[keyPath: axis] = lo
            velocity[keyPath: axis] = 0
        } else if origin[keyPath: axis] < lo {
            origin[keyPath: axis] = lo
            velocity[keyPath: axis] = abs(velocity[keyPath: axis]) * bounceDamping
        } else if origin[keyPath: axis] > hi {
            origin[keyPath: axis] = hi
            velocity[keyPath: axis] = -abs(velocity[keyPath: axis]) * bounceDamping
        }
    }
}

/// Release-velocity estimate for a drag: a trailing window of recent samples,
/// so a flick registers fast even if the gesture as a whole started slow.
/// Feed window positions from `mouseDragged` (+ one final sample at `mouseUp`),
/// then read `velocity()` at release.
public struct DragVelocityTracker: Sendable {
    /// How far back (seconds) samples count toward the estimate.
    public var window: Double
    private var samples: [(time: Double, point: CGPoint)] = []

    public init(window: Double = 0.1) {
        self.window = window
    }

    public mutating func reset() {
        samples.removeAll(keepingCapacity: true)
    }

    public mutating func add(_ point: CGPoint, at time: Double) {
        samples.append((time, point))
        let cutoff = time - window
        while samples.count > 1, samples[0].time < cutoff {
            samples.removeFirst()
        }
    }

    /// pt/s across the retained window; zero with fewer than two usable samples.
    public func velocity() -> CGPoint {
        guard let first = samples.first, let last = samples.last, last.time > first.time else {
            return .zero
        }
        let dt = last.time - first.time
        return CGPoint(
            x: (last.point.x - first.point.x) / dt,
            y: (last.point.y - first.point.y) / dt
        )
    }
}

/// Recognizes a horizontal shake during a drag: `requiredReversals` direction
/// flips within `window` seconds, each spanning at least `minAmplitude` points,
/// with little net vertical travel. Feed drag samples; it returns true the
/// moment a shake is recognized, then re-arms so a continued shake can fire
/// again after another full set of reversals.
public struct ShakeDetector: Sendable {
    /// All reversals must land inside this window (seconds).
    public var window: Double
    /// Minimum horizontal span (pt) of one back-or-forth leg for it to count.
    public var minAmplitude: CGFloat
    /// Direction flips needed to fire.
    public var requiredReversals: Int
    /// Net vertical travel tolerated across the window (pt) — a shake is sideways.
    public var maxVerticalDrift: CGFloat

    public init(
        window: Double = 0.6,
        minAmplitude: CGFloat = 40,
        requiredReversals: Int = 3,
        maxVerticalDrift: CGFloat = 60
    ) {
        self.window = window
        self.minAmplitude = minAmplitude
        self.requiredReversals = requiredReversals
        self.maxVerticalDrift = maxVerticalDrift
    }

    private var lastPoint: CGPoint?
    private var lastDirection: Int = 0  // -1 | 0 | +1, the current horizontal run
    private var runStart: CGPoint = .zero  // where the current run began
    private var extreme: CGPoint = .zero   // furthest point of the current run
    private var reversals: [(time: Double, point: CGPoint)] = []

    public mutating func reset() {
        lastPoint = nil
        lastDirection = 0
        runStart = .zero
        extreme = .zero
        reversals.removeAll(keepingCapacity: true)
    }

    public mutating func add(_ point: CGPoint, at time: Double) -> Bool {
        reversals.removeAll { time - $0.time > window }
        guard let last = lastPoint else {
            lastPoint = point
            runStart = point
            extreme = point
            return false
        }
        lastPoint = point
        let dx = point.x - last.x
        let direction = dx > 0 ? 1 : (dx < 0 ? -1 : 0)
        guard direction != 0 else { return false }

        if lastDirection == 0 {
            // First real movement: the run starts where sampling started.
            lastDirection = direction
            extreme = point
            return false
        }
        if direction == lastDirection {
            // Same run — keep the extreme current.
            if direction > 0, point.x > extreme.x { extreme = point }
            if direction < 0, point.x < extreme.x { extreme = point }
            return false
        }

        // Direction flipped: the completed run is a candidate reversal.
        lastDirection = direction
        let amplitude = abs(extreme.x - runStart.x)
        defer {
            runStart = extreme
            extreme = point
        }
        guard amplitude >= minAmplitude else { return false }
        reversals.append((time, extreme))
        guard reversals.count >= requiredReversals,
              abs(point.y - reversals[0].point.y) <= maxVerticalDrift
        else { return false }

        // Recognized — re-arm so a sustained shake toggles again.
        reversals.removeAll(keepingCapacity: true)
        return true
    }
}
