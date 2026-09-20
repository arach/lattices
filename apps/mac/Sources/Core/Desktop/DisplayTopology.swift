import AppKit
import CoreGraphics

enum SpatialDirection: String, CaseIterable, Equatable {
    case left
    case right
    case up
    case down

    var placementLabel: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        case .up: return "Top"
        case .down: return "Bottom"
        }
    }
}

/// Canonical physical display geometry for directional movement.
///
/// `apiIndex` remains the SkyLight/API identity accepted by ActionRuntime;
/// `frame` and neighbor selection describe the user's physical arrangement.
/// This keeps API ordering and spatial direction from being conflated.
struct DisplayTopology: Equatable {
    struct Display: Equatable {
        let id: String
        let apiIndex: Int
        let name: String
        /// Full display frame in CG/AX top-left global coordinates.
        let frame: CGRect
        /// Usable display frame in the same coordinate space.
        let visibleFrame: CGRect
    }

    let displays: [Display]

    var spatialOrder: [Display] {
        displays.sorted { lhs, rhs in
            if abs(lhs.frame.minX - rhs.frame.minX) > 10 {
                return lhs.frame.minX < rhs.frame.minX
            }
            if abs(lhs.frame.minY - rhs.frame.minY) > 10 {
                return lhs.frame.minY < rhs.frame.minY
            }
            return lhs.id < rhs.id
        }
    }

    func display(id: String) -> Display? {
        displays.first(where: { $0.id == id })
    }

    func display(containing point: CGPoint) -> Display? {
        if let containing = displays.first(where: { $0.frame.contains(point) }) {
            return containing
        }
        return displays.min { lhs, rhs in
            Self.squaredDistance(from: point, to: lhs.frame) < Self.squaredDistance(from: point, to: rhs.frame)
        }
    }

    func adjacent(to sourceID: String, direction: SpatialDirection) -> Display? {
        guard let source = display(id: sourceID) else { return nil }
        return displays
            .filter { $0.id != source.id && Self.isCandidate($0.frame, in: direction, from: source.frame) }
            .min { lhs, rhs in
                let leftScore = Self.neighborScore(lhs.frame, from: source.frame, direction: direction)
                let rightScore = Self.neighborScore(rhs.frame, from: source.frame, direction: direction)
                if abs(leftScore - rightScore) > 0.001 {
                    return leftScore < rightScore
                }
                return lhs.id < rhs.id
            }
    }

    /// Main-thread snapshot that joins AppKit screens to the stable SkyLight
    /// API index through UUID matching. Falls back to AppKit indices only when
    /// SkyLight cannot provide a display list.
    static func live() -> DisplayTopology {
        let screens = NSScreen.screens
        let primaryHeight = screens.first?.frame.height ?? 0
        let spaces = WindowTiler.getDisplaySpaces()

        let displays = screens.enumerated().map { appKitIndex, screen in
            let apiIndex = spaces.first(where: {
                DisplayGeometryMapper.screen(for: $0, in: screens) === screen
            })?.displayIndex ?? appKitIndex
            return Display(
                id: ScreenOverlayCanvasController.screenID(for: screen),
                apiIndex: apiIndex,
                name: screen.localizedName,
                frame: DisplayGeometryMapper.topLeftFrame(screen.frame, primaryHeight: primaryHeight),
                visibleFrame: DisplayGeometryMapper.topLeftFrame(screen.visibleFrame, primaryHeight: primaryHeight)
            )
        }
        return DisplayTopology(displays: displays)
    }

    private static func isCandidate(_ candidate: CGRect, in direction: SpatialDirection, from source: CGRect) -> Bool {
        let epsilon: CGFloat = 1
        switch direction {
        case .left: return candidate.midX < source.midX - epsilon
        case .right: return candidate.midX > source.midX + epsilon
        case .up: return candidate.midY < source.midY - epsilon
        case .down: return candidate.midY > source.midY + epsilon
        }
    }

    /// Prefer a display that overlaps the source on the perpendicular axis,
    /// then the closest forward display. This handles staggered and differently
    /// sized monitors without treating array order as physical direction.
    private static func neighborScore(
        _ candidate: CGRect,
        from source: CGRect,
        direction: SpatialDirection
    ) -> CGFloat {
        let horizontal = direction == .left || direction == .right
        let forward: CGFloat
        let perpendicularGap: CGFloat
        let perpendicularCenter: CGFloat

        if horizontal {
            forward = abs(candidate.midX - source.midX)
            perpendicularGap = intervalGap(
                candidate.minY, candidate.maxY,
                source.minY, source.maxY
            )
            perpendicularCenter = abs(candidate.midY - source.midY)
        } else {
            forward = abs(candidate.midY - source.midY)
            perpendicularGap = intervalGap(
                candidate.minX, candidate.maxX,
                source.minX, source.maxX
            )
            perpendicularCenter = abs(candidate.midX - source.midX)
        }

        return forward + perpendicularGap * 4 + perpendicularCenter * 0.15
    }

    private static func intervalGap(_ a0: CGFloat, _ a1: CGFloat, _ b0: CGFloat, _ b1: CGFloat) -> CGFloat {
        if a1 < b0 { return b0 - a1 }
        if b1 < a0 { return a0 - b1 }
        return 0
    }

    private static func squaredDistance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(max(rect.minX - point.x, 0), point.x - rect.maxX)
        let dy = max(max(rect.minY - point.y, 0), point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}
