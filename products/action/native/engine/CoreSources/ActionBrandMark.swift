import CoreGraphics
import Foundation

/// Action's mark: a play triangle breaking out of four capture-corner marks.
///
/// The marks are the frame Action puts around a region; the triangle is the
/// take. It crosses the right-hand marks rather than sitting politely inside
/// them, and the marks are cut away where it passes so the crossing reads as
/// deliberate instead of as a collision.
///
/// The geometry lives here, in Core, because three places draw it and they must
/// not drift apart: the menu bar status item, the in-app brand tile, and the
/// `.icns` the build stamps into `Action.app`. Everything is expressed in a
/// 100 x 100 design box with **y pointing down**, then mapped onto whatever
/// rect the caller hands in, so the mark is resolution-independent.
public enum ActionBrandMark {
    /// The design box every coordinate below is expressed in. y points down.
    public static let designBox = CGSize(width: 100, height: 100)

    /// Which way y runs in the space the caller is drawing into.
    ///
    /// CoreGraphics contexts and unflipped `NSImage` drawing put y at the
    /// bottom; SwiftUI and flipped AppKit views put it at the top. The mark is
    /// authored y-down, so getting this wrong renders it upside down rather
    /// than failing loudly — hence an explicit argument instead of a default
    /// that silently suits one caller.
    public enum YAxis: Sendable {
        case up
        case down
    }

    /// Proportions of the frame and the triangle. Tuned by rendering at both
    /// 512 and 18 points, because the knockout gap is the first thing to close
    /// up when the mark is scaled down to the menu bar.
    public struct Metrics: Sendable {
        /// How far the corner marks sit in from the mark's box.
        public var inset = 12.0
        /// Stroke weight of the corner marks. Kept light on purpose: these are
        /// crop marks, not a border, and the triangle is the only solid mass the
        /// mark needs. Thinning the marks alone unbalances it, so the triangle
        /// was pulled in to match.
        public var weight = 3.75
        /// Length of each arm. Long enough that the right-hand marks actually
        /// stand where the triangle wants to go — with short arms the triangle
        /// slips through the gap between the corners and never crosses anything.
        public var arm = 34.0

        /// The triangle. Its tip runs past the marks on the right.
        public var playLeft = 33.0
        public var playTop = 30.0
        public var playBottom = 70.0
        public var playTip = 93.0
        public var playRadius = 3.0

        /// Clearance cut out of the marks where the triangle crosses them.
        /// Below about 4 the gap closes up at menu bar size and the crossing
        /// looks like a mistake; much above the mark's own weight it eats the
        /// right-hand arms.
        public var knockout = 5.0

        public init() {}
    }

    public static let metrics = Metrics()

    /// The whole mark as one path — marks and triangle together. This is the
    /// single-colour form the menu bar uses; the knockout keeps the triangle
    /// legible against the marks even when everything is the same black.
    public static func markPath(
        in rect: CGRect,
        yAxis: YAxis = .up,
        metrics m: Metrics = metrics
    ) -> CGPath {
        let path = CGMutablePath()
        path.addPath(marksPath(in: rect, yAxis: yAxis, metrics: m))
        path.addPath(playPath(in: rect, yAxis: yAxis, metrics: m))
        return path
    }

    /// The four capture-corner marks, already cut away where the triangle
    /// crosses them.
    ///
    /// The cut is a real path subtraction rather than a drawing-time trick, so
    /// the result is one plain path that fills identically in CoreGraphics, in
    /// an `NSImage`, and in a SwiftUI `Shape`. A compositing trick like
    /// `destinationOut` needs a transparency layer and would not survive being
    /// handed to SwiftUI as a shape.
    public static func marksPath(
        in rect: CGRect,
        yAxis: YAxis = .up,
        metrics m: Metrics = metrics
    ) -> CGPath {
        let marks = CGMutablePath()
        let lo = m.inset
        let hi = 100 - m.inset
        let r = m.weight / 2
        for (cx, cy, sx, sy) in [(lo, lo, 1.0, 1.0), (hi, lo, -1.0, 1.0),
                                 (lo, hi, 1.0, -1.0), (hi, hi, -1.0, -1.0)] {
            marks.addPath(bar(cx, cy, sx * m.arm, sy * m.weight, r))
            marks.addPath(bar(cx, cy, sx * m.weight, sy * m.arm, r))
        }

        let play = rawPlay(m)
        let cut: CGPath
        if m.knockout > 0 {
            let halo = play.copy(
                strokingWithWidth: CGFloat(m.knockout * 2),
                lineCap: .round,
                lineJoin: .round,
                miterLimit: 10
            )
            cut = marks.subtracting(halo.union(play))
        } else {
            cut = marks
        }
        return place(cut, in: rect, yAxis: yAxis)
    }

    /// The triangle on its own, so it can carry its own colour.
    public static func playPath(
        in rect: CGRect,
        yAxis: YAxis = .up,
        metrics m: Metrics = metrics
    ) -> CGPath {
        place(rawPlay(m), in: rect, yAxis: yAxis)
    }

    /// A rounded bar reaching out from a corner, in design space. Negative
    /// extents run back toward the origin, which is how the four corners share
    /// one description.
    private static func bar(_ x: Double, _ y: Double, _ dx: Double, _ dy: Double, _ r: Double) -> CGPath {
        let rect = CGRect(x: min(x, x + dx), y: min(y, y + dy), width: abs(dx), height: abs(dy))
        return CGPath(roundedRect: rect, cornerWidth: CGFloat(r), cornerHeight: CGFloat(r), transform: nil)
    }

    private static func rawPlay(_ m: Metrics) -> CGPath {
        roundedPolygon(
            [
                CGPoint(x: m.playLeft, y: m.playTop),
                CGPoint(x: m.playLeft, y: m.playBottom),
                CGPoint(x: m.playTip, y: (m.playTop + m.playBottom) / 2),
            ],
            radius: m.playRadius
        )
    }

    private static func place(_ path: CGPath, in rect: CGRect, yAxis: YAxis) -> CGPath {
        var transform = designTransform(into: rect, yAxis: yAxis)
        return path.copy(using: &transform) ?? path
    }

    /// The rounded tile the mark sits on, as the app icon and the in-app brand
    /// chip both draw it: a rounded rect with macOS "continuous" corners.
    public static func tilePath(in rect: CGRect, cornerRatio: Double = tileCornerRatio) -> CGPath {
        continuousRoundedRect(
            rect,
            radius: Double(min(rect.width, rect.height)) * cornerRatio,
            n: tileCornerExponent
        )
    }

    // MARK: - Tile proportions

    /// How much of each edge the corner eats, as a fraction of the tile's side.
    /// Larger than the circular equivalent because a superellipse corner starts
    /// bending later, so it needs more run to land in the same place.
    public static let tileCornerRatio = 0.28
    /// Squareness of the corner. 2 is a circle; 5 sits where the system mask does.
    public static let tileCornerExponent = 5.0

    /// Apple's icon grid: the tile is 824 of a 1024 canvas, leaving the margin
    /// the system expects for shadow and for optical alignment in the Dock.
    public static let iconBodyInsetRatio = 100.0 / 1024.0
    /// The mark's share of the tile. No optical nudge: unlike a letterform the
    /// frame is symmetric top to bottom, so geometric centring is correct.
    public static let iconMarkScale = 0.74
    public static let iconMarkOffsetY = 0.0

    /// Where the mark sits inside a tile: centred, scaled to `iconMarkScale`,
    /// nudged up because the A is bottom-heavy. Shared by the `.icns` renderer
    /// and the in-app chip so the two compositions cannot drift.
    public static func markRect(inTile tile: CGRect, yAxis: YAxis = .up) -> CGRect {
        let side = tile.width * CGFloat(iconMarkScale)
        // The nudge is authored in design space, where y points down, so it
        // adds in a y-down space and subtracts in a y-up one.
        let dy = tile.height * CGFloat(iconMarkOffsetY) / CGFloat(designBox.height)
        return CGRect(
            x: tile.midX - side / 2,
            y: tile.midY - side / 2 + (yAxis == .down ? dy : -dy),
            width: side,
            height: side
        )
    }

    /// The tile's rect inside a square icon canvas.
    public static func iconBodyRect(inCanvas canvas: CGRect) -> CGRect {
        let inset = Double(canvas.width) * iconBodyInsetRatio
        return canvas.insetBy(dx: CGFloat(inset), dy: CGFloat(inset))
    }

    // MARK: - Brand colours

    /// The `action` built-in theme's HUD coral and ink, baked in.
    ///
    /// Source of truth is `ActionThemeBuiltin.swift`. They are duplicated here
    /// because an `.icns` on disk cannot follow a theme the user switches at
    /// runtime — the app icon has to commit to one palette. Anything drawn
    /// *inside* the app should read `StageHUDTheme` instead of these.
    public static let coral = CGColor(red: 0.937, green: 0.416, blue: 0.278, alpha: 1)
    public static let coralHot = CGColor(red: 1.0, green: 0.49, blue: 0.32, alpha: 1)
    public static let ink = CGColor(red: 0.055, green: 0.071, blue: 0.074, alpha: 1)
    /// The landing system's canvas and its graphite, same values as the theme's
    /// `canvas` and `ink` in light appearance.
    public static let paper = CGColor(red: 0xF3 / 255, green: 0xEB / 255, blue: 0xDD / 255, alpha: 1)
    public static let graphite = CGColor(red: 0x20 / 255, green: 0x28 / 255, blue: 0x2B / 255, alpha: 1)
    /// The landing system's `--action-paper-shadow`, used only to give the tile
    /// a shallow ramp so it does not read as a flat sticker in the Dock.
    public static let paperShadow = CGColor(red: 0xDC / 255, green: 0xCF / 255, blue: 0xB9 / 255, alpha: 1)

    // MARK: - Geometry helpers

    /// Maps the 100 x 100 design box (y down) onto `rect` (y up, as CoreGraphics
    /// and SwiftUI both hand it to us), fitting the shorter side and centring.
    private static func designTransform(into rect: CGRect, yAxis: YAxis) -> CGAffineTransform {
        let scale = min(rect.width, rect.height) / CGFloat(designBox.width)
        let dx = rect.minX + (rect.width - CGFloat(designBox.width) * scale) / 2
        let dy = rect.minY + (rect.height - CGFloat(designBox.height) * scale) / 2
        switch yAxis {
        case .down:
            return CGAffineTransform(translationX: dx, y: dy).scaledBy(x: scale, y: scale)
        case .up:
            return CGAffineTransform(translationX: dx, y: dy + CGFloat(designBox.height) * scale)
                .scaledBy(x: scale, y: -scale)
        }
    }

    /// A closed polygon with every corner rounded to `radius`.
    ///
    /// Starts at the midpoint of the closing edge so that the first vertex gets
    /// an arc too — `addArc(tangent1End:tangent2End:)` rounds the corner it is
    /// aiming at, so beginning on a vertex would leave that one sharp.
    private static func roundedPolygon(_ points: [CGPoint], radius: Double) -> CGPath {
        let path = CGMutablePath()
        guard radius > 0, points.count > 2 else {
            path.addLines(between: points)
            path.closeSubpath()
            return path
        }
        let last = points[points.count - 1]
        path.move(to: CGPoint(x: (last.x + points[0].x) / 2, y: (last.y + points[0].y) / 2))
        for i in points.indices {
            path.addArc(
                tangent1End: points[i],
                tangent2End: points[(i + 1) % points.count],
                radius: CGFloat(radius)
            )
        }
        path.closeSubpath()
        return path
    }

    /// A rounded rect whose corners are superellipse quadrants rather than
    /// circular arcs — the continuous curvature macOS uses, where the corner
    /// eases into the straight edge instead of meeting it at a curvature jump.
    ///
    /// `radius` is how far the corner reaches along each edge, not a circle's
    /// radius; with `n` above 2 the corner is fuller than a circle of the same
    /// reach. Sampled rather than fitted with béziers: at icon sizes the
    /// difference is invisible and the arithmetic stays honest.
    private static func continuousRoundedRect(
        _ rect: CGRect,
        radius: Double,
        n: Double,
        samples: Int = 48
    ) -> CGPath {
        let path = CGMutablePath()
        let x0 = Double(rect.minX), y0 = Double(rect.minY)
        let x1 = Double(rect.maxX), y1 = Double(rect.maxY)
        let r = min(radius, min(x1 - x0, y1 - y0) / 2)
        let exponent = 2 / n

        func corner(_ cx: Double, _ cy: Double, _ sx: Double, _ sy: Double, reversed: Bool) {
            for i in 0...samples {
                let k = reversed ? samples - i : i
                let t = Double.pi / 2 * Double(k) / Double(samples)
                path.addLine(to: CGPoint(
                    x: cx + sx * r * pow(cos(t), exponent),
                    y: cy + sy * r * pow(sin(t), exponent)
                ))
            }
        }

        path.move(to: CGPoint(x: x0 + r, y: y0))
        path.addLine(to: CGPoint(x: x1 - r, y: y0))
        corner(x1 - r, y0 + r, 1, -1, reversed: true)
        path.addLine(to: CGPoint(x: x1, y: y1 - r))
        corner(x1 - r, y1 - r, 1, 1, reversed: false)
        path.addLine(to: CGPoint(x: x0 + r, y: y1))
        corner(x0 + r, y1 - r, -1, 1, reversed: true)
        path.addLine(to: CGPoint(x: x0, y: y0 + r))
        corner(x0 + r, y0 + r, -1, -1, reversed: false)
        path.closeSubpath()
        return path
    }
}
