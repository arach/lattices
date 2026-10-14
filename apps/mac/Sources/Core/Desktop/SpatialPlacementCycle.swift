import CoreGraphics

struct SpatialPlacementCycleResult: Equatable {
    let direction: SpatialDirection
    let placement: PlacementSpec
    /// Zero-based step in half → third → two-thirds.
    let cycleIndex: Int
    let label: String
}

/// Resolves repeated directional input from live geometry, never session
/// memory. If a window already matches a cycle step, the next invocation
/// advances; any other geometry starts at the familiar half placement.
enum SpatialPlacementCycle {
    static let tolerance: CGFloat = 8

    static func resolve(
        direction: SpatialDirection,
        currentFrame: CGRect,
        sourceVisibleFrame: CGRect,
        tolerance: CGFloat = tolerance
    ) -> SpatialPlacementCycleResult {
        let options = steps(for: direction)
        let currentIndex = options.firstIndex { option in
            framesClose(
                currentFrame,
                WindowTiler.tileFrame(fractions: option.placement.fractions, inDisplay: sourceVisibleFrame),
                tolerance: tolerance
            )
        }
        let nextIndex = currentIndex.map { ($0 + 1) % options.count } ?? 0
        return options[nextIndex]
    }

    static func steps(for direction: SpatialDirection) -> [SpatialPlacementCycleResult] {
        let placements: [PlacementSpec]
        switch direction {
        case .left:
            placements = [
                .tile(.left),
                .tile(.leftThird),
                fractional(x: 0, y: 0, w: 2.0 / 3.0, h: 1),
            ]
        case .right:
            placements = [
                .tile(.right),
                .tile(.rightThird),
                fractional(x: 1.0 / 3.0, y: 0, w: 2.0 / 3.0, h: 1),
            ]
        case .up:
            placements = [
                .tile(.top),
                .tile(.topThird),
                fractional(x: 0, y: 0, w: 1, h: 2.0 / 3.0),
            ]
        case .down:
            placements = [
                .tile(.bottom),
                .tile(.bottomThird),
                fractional(x: 0, y: 1.0 / 3.0, w: 1, h: 2.0 / 3.0),
            ]
        }

        let sizes = ["½", "⅓", "⅔"]
        return placements.enumerated().map { index, placement in
            SpatialPlacementCycleResult(
                direction: direction,
                placement: placement,
                cycleIndex: index,
                label: "\(direction.placementLabel) \(sizes[index])"
            )
        }
    }

    private static func fractional(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> PlacementSpec {
        // All built-in cycle constants are inside the unit square.
        .fractions(FractionalPlacement(x: x, y: y, w: w, h: h)!)
    }

    private static func framesClose(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance &&
            abs(lhs.minY - rhs.minY) <= tolerance &&
            abs(lhs.width - rhs.width) <= tolerance &&
            abs(lhs.height - rhs.height) <= tolerance
    }
}

/// The first Spatial Lens action set: cardinal directions keep Lattices'
/// geometry-derived 1/2 -> 1/3 -> 2/3 cycle, while diagonals are quarters.
enum SpatialLensTarget: String, CaseIterable, Equatable, Hashable {
    case topLeft
    case top
    case topRight
    case left
    case right
    case bottomLeft
    case bottom
    case bottomRight

    var label: String {
        switch self {
        case .topLeft: return "Top Left"
        case .top: return "Top"
        case .topRight: return "Top Right"
        case .left: return "Left"
        case .right: return "Right"
        case .bottomLeft: return "Bottom Left"
        case .bottom: return "Bottom"
        case .bottomRight: return "Bottom Right"
        }
    }

    var cardinalDirection: SpatialDirection? {
        switch self {
        case .top: return .up
        case .left: return .left
        case .right: return .right
        case .bottom: return .down
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return nil
        }
    }

    var cornerPlacement: PlacementSpec? {
        switch self {
        case .topLeft: return .tile(.topLeft)
        case .topRight: return .tile(.topRight)
        case .bottomLeft: return .tile(.bottomLeft)
        case .bottomRight: return .tile(.bottomRight)
        case .top, .left, .right, .bottom: return nil
        }
    }

    fileprivate var gridOffset: CGVector {
        switch self {
        case .topLeft: return CGVector(dx: -100, dy: 56)
        case .top: return CGVector(dx: 0, dy: 56)
        case .topRight: return CGVector(dx: 100, dy: 56)
        case .left: return CGVector(dx: -100, dy: 0)
        case .right: return CGVector(dx: 100, dy: 0)
        case .bottomLeft: return CGVector(dx: -100, dy: -56)
        case .bottom: return CGVector(dx: 0, dy: -56)
        case .bottomRight: return CGVector(dx: 100, dy: -56)
        }
    }
}

struct SpatialLensTargetRegion: Equatable {
    let target: SpatialLensTarget
    let rect: CGRect
}

enum SpatialLensSelectionSource: String, Equatable {
    case paintedTarget
    case outerFlick
}

struct SpatialLensTargetSelection: Equatable {
    let target: SpatialLensTarget
    let source: SpatialLensSelectionSource
}

/// Shared geometry for drawing and hit-testing. A single region list is used
/// for both so the painted targets never lie about what the pointer will pick.
enum SpatialLensTargetLayout {
    static let targetSize = CGSize(width: 92, height: 48)
    static let horizontalExtent: CGFloat = 146
    static let verticalExtent: CGFloat = 80
    static let edgeInset: CGFloat = 12
    static let activationMovement: CGFloat = 16
    static let flickDistance: CGFloat = 168

    static func regions(center requestedCenter: CGPoint, within bounds: CGRect) -> [SpatialLensTargetRegion] {
        let center = CGPoint(
            x: clamped(
                requestedCenter.x,
                lower: bounds.minX + horizontalExtent + edgeInset,
                upper: bounds.maxX - horizontalExtent - edgeInset
            ),
            y: clamped(
                requestedCenter.y,
                lower: bounds.minY + verticalExtent + edgeInset,
                upper: bounds.maxY - verticalExtent - edgeInset
            )
        )
        return SpatialLensTarget.allCases.map { target in
            let offset = target.gridOffset
            return SpatialLensTargetRegion(
                target: target,
                rect: CGRect(
                    x: center.x + offset.dx - targetSize.width / 2,
                    y: center.y + offset.dy - targetSize.height / 2,
                    width: targetSize.width,
                    height: targetSize.height
                )
            )
        }
    }

    static func target(
        at pointer: CGPoint,
        anchor: CGPoint,
        regions: [SpatialLensTargetRegion]
    ) -> SpatialLensTarget? {
        selection(at: pointer, anchor: anchor, regions: regions)?.target
    }

    static func selection(
        at pointer: CGPoint,
        anchor: CGPoint,
        regions: [SpatialLensTargetRegion]
    ) -> SpatialLensTargetSelection? {
        let delta = CGVector(dx: pointer.x - anchor.x, dy: pointer.y - anchor.y)
        let distance = hypot(delta.dx, delta.dy)
        guard distance >= activationMovement else { return nil }
        if let hit = regions.first(where: { $0.rect.contains(pointer) }) {
            return SpatialLensTargetSelection(target: hit.target, source: .paintedTarget)
        }
        guard distance >= flickDistance else { return nil }
        guard let target = nearestTarget(to: delta) else { return nil }
        return SpatialLensTargetSelection(target: target, source: .outerFlick)
    }

    static func center(of regions: [SpatialLensTargetRegion]) -> CGPoint? {
        guard let top = regions.first(where: { $0.target == .top }),
              let left = regions.first(where: { $0.target == .left }) else { return nil }
        return CGPoint(x: top.rect.midX, y: left.rect.midY)
    }

    static func nearestTarget(to delta: CGVector) -> SpatialLensTarget? {
        guard delta.dx != 0 || delta.dy != 0 else { return nil }
        let angle = atan2(delta.dy, delta.dx)
        let step = Int((angle / (.pi / 4)).rounded())
        switch step {
        case 0: return .right
        case 1: return .topRight
        case 2: return .top
        case 3: return .topLeft
        case 4, -4: return .left
        case -3: return .bottomLeft
        case -2: return .bottom
        case -1: return .bottomRight
        default: return nil
        }
    }

    private static func clamped(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard lower <= upper else { return (lower + upper) / 2 }
        return min(max(value, lower), upper)
    }
}

enum SpatialLensGesture {
    static func displayPushThresholds(minDimension: CGFloat) -> (enter: CGFloat, exit: CGFloat) {
        let enter = min(max(minDimension * 0.30, 360), 480)
        return (enter, enter * 0.78)
    }

    static func displayPushRequested(
        selectionSource: SpatialLensSelectionSource,
        wasPushed: Bool,
        distance: CGFloat,
        minDimension: CGFloat
    ) -> Bool {
        // A painted target always means the placement shown on the current
        // display. Cross-display movement is a separate, deliberate outer
        // flick so a small overshoot can never change the destination.
        guard selectionSource == .outerFlick else { return false }
        let thresholds = displayPushThresholds(minDimension: minDimension)
        return pushed(
            wasPushed: wasPushed,
            distance: distance,
            enterThreshold: thresholds.enter,
            exitThreshold: thresholds.exit
        )
    }

    static func direction(
        delta: CGVector,
        minimumDistance: CGFloat = 28,
        axisBias: CGFloat = 1.08
    ) -> SpatialDirection? {
        let x = abs(delta.dx)
        let y = abs(delta.dy)
        guard hypot(x, y) >= minimumDistance else { return nil }

        if x >= y * axisBias {
            return delta.dx < 0 ? .left : .right
        }
        if y >= x * axisBias {
            // AppKit global points grow upward.
            return delta.dy < 0 ? .down : .up
        }

        // In the narrow diagonal deadband, retain a deterministic dominant
        // axis instead of flickering between two proposals.
        if x >= y {
            return delta.dx < 0 ? .left : .right
        }
        return delta.dy < 0 ? .down : .up
    }

    static func pushed(
        wasPushed: Bool,
        distance: CGFloat,
        enterThreshold: CGFloat,
        exitThreshold: CGFloat
    ) -> Bool {
        if wasPushed {
            return distance >= exitThreshold
        }
        return distance >= enterThreshold
    }
}
