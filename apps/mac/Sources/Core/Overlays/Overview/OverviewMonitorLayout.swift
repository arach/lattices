import Foundation
import CoreGraphics

/// A pure fit calculation: no measuring pass, persisted geometry, or screen reads.
/// The stage gets only the room above the reserved toolbar/tray.
enum OverviewMonitorLayout {
    enum Arrangement: String { case empty, single, sideBySide, stacked, focusColumn, focusRow }
    struct Placement: Equatable {
        let id: Int
        let frame: CGRect
        let map: CGSize
        let thumb: CGSize
        let compact: Bool
    }
    struct Plan: Equatable {
        let arrangement: Arrangement
        let placements: [Placement]
        var mapArea: CGFloat { placements.reduce(0) { $0 + $1.map.width * $1.map.height } }
    }
    static let gap: CGFloat = 16

    static func plan(_ monitors: [OverviewDeskMonitor], in room: CGSize, preferred: UInt32?) -> Plan {
        guard !monitors.isEmpty, room.width > 0, room.height > 0 else { return Plan(arrangement: .empty, placements: []) }
        let lead = monitors.first { $0.display.displayId == preferred } ?? monitors.first { $0.display.isMain } ?? monitors[0]
        let ordered = [lead] + monitors.filter { $0.id != lead.id }
        let bounds = CGRect(origin: .zero, size: room)
        if ordered.count == 1 { return Plan(arrangement: .single, placements: [fit(lead, in: bounds, compact: false)]) }
        if ordered.count == 2 {
            let horizontal = room.width >= room.height
            let cells = divide(bounds, count: 2, horizontal: horizontal)
            return packed(Plan(arrangement: horizontal ? .sideBySide : .stacked,
                        placements: zip(ordered, cells).map { fit($0.0, in: $0.1, compact: false) }), in: room)
        }
        // Evaluate both thumbnail orientations and the split together. Select
        // the greatest drawn map area, not the largest enclosing empty boxes.
        var candidates: [Plan] = []
        for column in [true, false] {
            for fraction in stride(from: 0.56, through: 0.82, by: 0.02) {
                let available = max(0, (column ? room.width : room.height) - gap)
                let extent = floor(available * fraction)
                let primary = column ? CGRect(x: 0, y: 0, width: extent, height: room.height)
                    : CGRect(x: 0, y: 0, width: room.width, height: extent)
                let rest = column ? CGRect(x: extent + gap, y: 0, width: available - extent, height: room.height)
                    : CGRect(x: 0, y: extent + gap, width: room.width, height: available - extent)
                let cells = divide(rest, count: ordered.count - 1, horizontal: !column)
                let placements = [fit(lead, in: primary, compact: false)] + zip(ordered.dropFirst(), cells).map { fit($0.0, in: $0.1, compact: true) }
                let leadArea = placements[0].map.width * placements[0].map.height
                guard placements.dropFirst().allSatisfy({ $0.map.width * $0.map.height <= leadArea }) else { continue }
                candidates.append(Plan(arrangement: column ? .focusColumn : .focusRow, placements: placements))
            }
        }
        let best = candidates.max { $0.mapArea < $1.mapArea } ?? Plan(arrangement: .stacked,
            placements: zip(ordered, divide(bounds, count: ordered.count, horizontal: false)).map { fit($0.0, in: $0.1, compact: true) })
        return packed(best, in: room)
    }

    /// Pack actual aspect-fitted bounds, not their allocation cells. This keeps
    /// unlike monitor ratios aligned and removes internal letterbox gutters.
    private static func packed(_ plan: Plan, in room: CGSize) -> Plan {
        let p = plan.placements
        guard let lead = p.first else { return plan }
        func moved(_ value: Placement, x: CGFloat, y: CGFloat) -> Placement {
            Placement(id: value.id, frame: CGRect(x: floor(x), y: floor(y), width: value.frame.width, height: value.frame.height),
                map: value.map, thumb: value.thumb, compact: value.compact)
        }
        var result: [Placement] = []
        switch plan.arrangement {
        case .sideBySide, .stacked:
            let horizontal = plan.arrangement == .sideBySide
            let extent = p.reduce(CGFloat(0)) { $0 + (horizontal ? $1.frame.width : $1.frame.height) } + gap * CGFloat(p.count - 1)
            let maxHeight = p.map(\.frame.height).max() ?? 0
            var cursor = ((horizontal ? room.width : room.height) - extent) / 2
            for item in p {
                result.append(moved(item, x: horizontal ? cursor : (room.width - item.frame.width) / 2,
                    y: horizontal ? (room.height - maxHeight) / 2 : cursor))
                cursor += (horizontal ? item.frame.width : item.frame.height) + gap
            }
        case .focusColumn:
            let others = Array(p.dropFirst())
            let otherWidth = others.map(\.frame.width).max() ?? 0
            let otherHeight = others.reduce(CGFloat(0)) { $0 + $1.frame.height } + gap * CGFloat(max(0, others.count - 1))
            let x = (room.width - lead.frame.width - gap - otherWidth) / 2
            var y = (room.height - max(lead.frame.height, otherHeight)) / 2
            result.append(moved(lead, x: x, y: y))
            for item in others {
                result.append(moved(item, x: x + lead.frame.width + gap, y: y))
                y += item.frame.height + gap
            }
        case .focusRow:
            let others = Array(p.dropFirst())
            let otherHeight = others.map(\.frame.height).max() ?? 0
            let otherWidth = others.reduce(CGFloat(0)) { $0 + $1.frame.width } + gap * CGFloat(max(0, others.count - 1))
            let y = (room.height - lead.frame.height - gap - otherHeight) / 2
            result.append(moved(lead, x: (room.width - lead.frame.width) / 2, y: y))
            var x = (room.width - otherWidth) / 2
            for item in others {
                result.append(moved(item, x: x, y: y + lead.frame.height + gap))
                x += item.frame.width + gap
            }
        default: return plan
        }
        return Plan(arrangement: plan.arrangement, placements: result)
    }

    private static func divide(_ rect: CGRect, count: Int, horizontal: Bool) -> [CGRect] {
        let dimension = horizontal ? rect.width : rect.height
        let spacing = min(gap, dimension / CGFloat(max(1, count * 2)))
        let extent = max(0, (dimension - spacing * CGFloat(count - 1)) / CGFloat(count))
        return (0..<count).map { i in
            horizontal ? CGRect(x: rect.minX + CGFloat(i) * (extent + spacing), y: rect.minY, width: extent, height: rect.height)
                : CGRect(x: rect.minX, y: rect.minY + CGFloat(i) * (extent + spacing), width: rect.width, height: extent)
        }
    }

    private static func fit(_ monitor: OverviewDeskMonitor, in cell: CGRect, compact: Bool) -> Placement {
        let size = monitor.display.bounds.size
        let aspect = size.width > 0 && size.height > 0 ? size.width / size.height : 1.6
        let count = CGFloat(max(1, monitor.spaces.count))
        func thumbnail(_ width: CGFloat) -> CGFloat { compact ? 0 : min(84, max(24, (width - 6 * (count - 1)) / count)) }
        let chrome: CGFloat = compact ? 34 : 58
        // Width influences both the map's and its Desktop strip's height.
        var low: CGFloat = 0, high = max(0, cell.width)
        for _ in 0..<24 {
            let mid = (low + high) / 2
            if mid / aspect + chrome + thumbnail(mid) / aspect <= cell.height { low = mid } else { high = mid }
        }
        let width = floor(low), height = floor(width / aspect)
        let thumbWidth = floor(thumbnail(width)), thumbHeight = floor(thumbWidth / aspect)
        let total = min(cell.height, height + chrome + thumbHeight)
        return Placement(id: monitor.id,
            frame: CGRect(x: floor(cell.midX - width / 2), y: floor(cell.midY - total / 2), width: width, height: total),
            map: CGSize(width: width, height: height), thumb: CGSize(width: thumbWidth, height: thumbHeight), compact: compact)
    }
}
