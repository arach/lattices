import AppKit

/// Lattices' pointer, the mark's centre, as an outline to fill: Action's
/// cursor on any heading, or the knob it becomes when a grid's own centre is
/// the target.
enum LatticesPointer {
    /// Which way the pointer points, and how far it has become the knob.
    struct Pose {
        /// Radians, counterclockwise from +x.
        var heading: CGFloat
        /// 0 is the pointer, 1 the knob.
        var knob: CGFloat

        /// The mark's own pose: pointing into the crook of the L, bottom left.
        static let rest = Pose(heading: .pi * 5 / 4, knob: 0)

        func mixed(with other: Pose, by t: CGFloat) -> Pose {
            Pose(heading: heading + (other.heading - heading) * t, knob: knob + (other.knob - knob) * t)
        }
    }

    /// #ef6a47, the family coral: the mark's accent.
    static let coral = NSColor(srgbRed: 239 / 255, green: 106 / 255, blue: 71 / 255, alpha: 1)

    /// The pose that aims from the middle of a 3×3 at the cell at `col`, `row`,
    /// counted from the top left, turning from `heading` the shorter way round.
    /// The middle cell itself gets the knob.
    static func aim(col: Int, row: Int, turningFrom heading: CGFloat) -> Pose {
        if col == 1 && row == 1 { return Pose(heading: heading, knob: 1) }
        return turn(from: heading, to: atan2(CGFloat(1 - row), CGFloat(col - 1)))
    }

    /// The rest pose, turning from `heading` the shorter way round, for when
    /// no cell is the target.
    static func rest(turningFrom heading: CGFloat) -> Pose {
        turn(from: heading, to: Pose.rest.heading)
    }

    /// `pose` as a closed outline in a `side` square about `centre`: the
    /// pointer, drawn `pose.knob` of the way into the knob. Both outlines
    /// have one point per step, tip first, so each point slides straight to
    /// its partner.
    static func path(_ pose: Pose, side: CGFloat, centre: CGPoint) -> NSBezierPath {
        let pointer = pointer(heading: pose.heading, side: side, centre: centre)
        let knob = knob(radius: side * 0.29, centre: centre, from: pose.heading, count: pointer.count)
        let path = NSBezierPath()
        for (index, (a, b)) in zip(pointer, knob).enumerated() {
            let point = CGPoint(x: a.x + (b.x - a.x) * pose.knob, y: a.y + (b.y - a.y) * pose.knob)
            if index == 0 { path.move(to: point) } else { path.line(to: point) }
        }
        path.close()
        return path
    }

    private static func turn(from heading: CGFloat, to bearing: CGFloat) -> Pose {
        Pose(heading: heading + (bearing - heading).remainder(dividingBy: 2 * .pi), knob: 0)
    }

    /// The cursor in a `side` square about `centre`, pointing along `heading`.
    /// Its tip sits where the heading leaves the square: a corner on a
    /// diagonal, an edge's midpoint straight on. In the mark's pose, tip in
    /// the bottom-left corner, the tail reaches the top and right edges.
    private static func pointer(heading: CGFloat, side: CGFloat, centre: CGPoint) -> [CGPoint] {
        let (dx, dy) = (cos(heading), sin(heading))
        let reach = side / 2 / max(abs(dx), abs(dy))
        let tip = CGPoint(x: centre.x + dx * reach, y: centre.y + dy * reach)
        let scale = side / cursorSpan
        return cursor.map { p in
            CGPoint(x: tip.x + scale * (p.y * dy - p.x * dx), y: tip.y - scale * (p.x * dy + p.y * dx))
        }
    }

    /// `count` points round a circle, counterclockwise from `angle`.
    private static func knob(radius: CGFloat, centre: CGPoint, from angle: CGFloat, count: Int) -> [CGPoint] {
        (0..<count).map { index in
            let a = angle + 2 * .pi * CGFloat(index) / CGFloat(count)
            return CGPoint(x: centre.x + radius * cos(a), y: centre.y + radius * sin(a))
        }
    }

    /// Action's cursor, the site's `actionCursor`, as points spaced evenly
    /// round its outline, counterclockwise from the tip. The tip sits at the
    /// origin and the tail runs along +x.
    private static let cursor: [CGPoint] = {
        let path = NSBezierPath()
        path.move(to: .zero)
        path.curve(to: NSPoint(x: 8, y: -3.730461265239989), controlPoint1: NSPoint(x: 0, y: -2), controlPoint2: NSPoint(x: 3, y: -3))
        path.line(to: NSPoint(x: 170, y: -79.27230188634977))
        path.curve(to: NSPoint(x: 175, y: -73.93537846789975), controlPoint: NSPoint(x: 180, y: -83.93537846789975))
        path.line(to: NSPoint(x: 140, y: -26))
        path.curve(to: NSPoint(x: 140, y: 26), controlPoint: NSPoint(x: 124, y: 0))
        path.line(to: NSPoint(x: 175, y: 73.93537846789975))
        path.curve(to: NSPoint(x: 170, y: 79.27230188634977), controlPoint: NSPoint(x: 180, y: 83.93537846789975))
        path.line(to: NSPoint(x: 8, y: 3.730461265239989))
        path.curve(to: .zero, controlPoint1: NSPoint(x: 3, y: 3), controlPoint2: NSPoint(x: 0, y: 2))
        path.close()
        return resample(path, count: 160)
    }()

    /// How far the cursor reaches turned 45°, where it spans a square.
    private static let cursorSpan: CGFloat = 530 - 348.61256823541

    /// `count` points spaced evenly round a closed path, from its first point.
    private static func resample(_ path: NSBezierPath, count: Int) -> [CGPoint] {
        path.flatness = 0.05
        let flat = path.flattened
        var ring: [CGPoint] = []
        var points = [NSPoint](repeating: .zero, count: 3)
        for index in 0..<flat.elementCount {
            let kind = flat.element(at: index, associatedPoints: &points)
            if kind == .moveTo || kind == .lineTo { ring.append(points[0]) }
        }
        ring.append(ring[0])
        var lengths: [CGFloat] = [0]
        for (a, b) in zip(ring, ring.dropFirst()) {
            lengths.append(lengths[lengths.count - 1] + hypot(b.x - a.x, b.y - a.y))
        }
        var segment = 0
        return (0..<count).map { index in
            let at = lengths[lengths.count - 1] * CGFloat(index) / CGFloat(count)
            while lengths[segment + 1] < at { segment += 1 }
            let (a, b) = (ring[segment], ring[segment + 1])
            let t = (at - lengths[segment]) / max(lengths[segment + 1] - lengths[segment], .ulpOfOne)
            return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
    }
}
