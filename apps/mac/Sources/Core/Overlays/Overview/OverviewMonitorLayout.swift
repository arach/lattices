import Foundation
import CoreGraphics

/// A pure fit calculation: no measuring pass, persisted geometry, or screen reads.
/// The stage gets only the room above the reserved toolbar/tray.
enum OverviewMonitorLayout {
    enum Arrangement: String { case empty, single, spatial, sideBySide, stacked, focusColumn, focusRow }
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

    /// Every monitor is drawn at one scale, so a 4K panel reads larger than a
    /// laptop beside it, and where it sits on the desk: left of, above or
    /// below its neighbours, gaps closed. When that wastes the room (a tall
    /// window over a row of monitors) a tidier row, column or focus layout
    /// takes over at the same one-scale rule.
    static func plan(_ monitors: [OverviewDeskMonitor], in room: CGSize, preferred: UInt32?) -> Plan {
        guard !monitors.isEmpty, room.width > 0, room.height > 0 else { return Plan(arrangement: .empty, placements: []) }
        let lead = monitors.first { $0.display.displayId == preferred } ?? monitors.first { $0.display.isMain } ?? monitors[0]
        let ordered = [lead] + monitors.filter { $0.id != lead.id }
        if ordered.count == 1 {
            let scale = largestScale(ordered, in: room) { extent(placements(ordered, arrangement: .single, scale: $0), .single) }
            return packed(Plan(arrangement: .single, placements: placements(ordered, arrangement: .single, scale: scale)), in: room)
        }
        let spatialScale = largestScale(ordered, in: room) { bbox(spatial(ordered, scale: $0)).size }
        let tidy: [Arrangement] = ordered.count == 2 ? [.sideBySide, .stacked] : [.sideBySide, .stacked, .focusColumn, .focusRow]
        let sized = tidy.map { arrangement in
            (arrangement, scale: largestScale(ordered, in: room) { extent(placements(ordered, arrangement: arrangement, scale: $0), arrangement) })
        }
        let full = sized.filter { $0.0 == .sideBySide || $0.0 == .stacked }.max { $0.scale < $1.scale }!
        let focus = sized.filter { $0.0 == .focusColumn || $0.0 == .focusRow }.max { $0.scale < $1.scale }
        let best = focus.map { $0.scale > full.scale * 1.1 ? $0 : full } ?? full
        if spatialScale >= best.scale * 0.8 {
            let frames = spatial(ordered, scale: spatialScale)
            let box = bbox(frames)
            let dx = floor((room.width - box.width) / 2 - box.minX), dy = floor((room.height - box.height) / 2 - box.minY)
            return Plan(arrangement: .spatial, placements: frames.map {
                Placement(id: $0.id, frame: $0.frame.offsetBy(dx: dx, dy: dy), map: $0.map, thumb: $0.thumb, compact: false)
            })
        }
        return packed(Plan(arrangement: best.0, placements: placements(ordered, arrangement: best.0, scale: best.scale)), in: room)
    }

    /// The desk as arranged in Displays settings, scaled, with each monitor's
    /// head and Desktops below its map and a gap where frames would touch.
    private static func spatial(_ ordered: [OverviewDeskMonitor], scale: CGFloat) -> [Placement] {
        let origin = CGPoint(x: ordered.map { $0.display.bounds.minX }.min() ?? 0, y: ordered.map { $0.display.bounds.minY }.min() ?? 0)
        var frames = ordered.map { monitor -> Placement in
            let p = sized(monitor, scale: scale, compact: false)
            let b = monitor.display.bounds
            return Placement(id: p.id, frame: CGRect(x: floor((b.minX - origin.x) * scale), y: floor((b.minY - origin.y) * scale),
                width: p.frame.width, height: p.frame.height), map: p.map, thumb: p.thumb, compact: false)
        }
        func overlaps(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> Bool { a < d - 0.5 && c < b - 0.5 }
        // Left to right: a frame sharing rows with one before it starts past it.
        for i in frames.indices.sorted(by: { frames[$0].frame.minX < frames[$1].frame.minX }) {
            var x = frames[i].frame.minX
            for j in frames.indices where j != i && frames[j].frame.minX < frames[i].frame.minX
                && overlaps(frames[i].frame.minY, frames[i].frame.maxY, frames[j].frame.minY, frames[j].frame.maxY) {
                x = max(x, frames[j].frame.maxX + gap)
            }
            frames[i] = moved(frames[i], to: CGPoint(x: x, y: frames[i].frame.minY))
        }
        // Top to bottom: one under another clears its Desktops.
        for i in frames.indices.sorted(by: { frames[$0].frame.minY < frames[$1].frame.minY }) {
            var y = frames[i].frame.minY
            for j in frames.indices where j != i && frames[j].frame.minY < frames[i].frame.minY
                && overlaps(frames[i].frame.minX, frames[i].frame.maxX, frames[j].frame.minX, frames[j].frame.maxX) {
                y = max(y, frames[j].frame.maxY + gap)
            }
            frames[i] = moved(frames[i], to: CGPoint(x: frames[i].frame.minX, y: y))
        }
        return frames
    }

    private static func moved(_ p: Placement, to point: CGPoint) -> Placement {
        Placement(id: p.id, frame: CGRect(origin: point, size: p.frame.size), map: p.map, thumb: p.thumb, compact: p.compact)
    }

    private static func bbox(_ p: [Placement]) -> CGRect {
        p.dropFirst().reduce(p.first?.frame ?? .zero) { $0.union($1.frame) }
    }

    private static func isCompact(_ index: Int, _ arrangement: Arrangement) -> Bool {
        index > 0 && (arrangement == .focusColumn || arrangement == .focusRow)
    }

    private static func placements(_ ordered: [OverviewDeskMonitor], arrangement: Arrangement, scale: CGFloat) -> [Placement] {
        ordered.enumerated().map { index, monitor in
            sized(monitor, scale: scale, compact: isCompact(index, arrangement))
        }
    }

    /// The outer size an arrangement of these placements needs.
    private static func extent(_ p: [Placement], _ arrangement: Arrangement) -> CGSize {
        func row(_ items: ArraySlice<Placement>) -> CGSize {
            CGSize(width: items.reduce(0) { $0 + $1.frame.width } + gap * CGFloat(max(0, items.count - 1)),
                   height: items.map(\.frame.height).max() ?? 0)
        }
        func column(_ items: ArraySlice<Placement>) -> CGSize {
            CGSize(width: items.map(\.frame.width).max() ?? 0,
                   height: items.reduce(0) { $0 + $1.frame.height } + gap * CGFloat(max(0, items.count - 1)))
        }
        guard let lead = p.first?.frame.size else { return .zero }
        switch arrangement {
        case .sideBySide, .single, .spatial: return row(p[...])
        case .stacked: return column(p[...])
        case .focusColumn:
            let rest = column(p.dropFirst())
            return CGSize(width: lead.width + gap + rest.width, height: max(lead.height, rest.height))
        case .focusRow:
            let rest = row(p.dropFirst())
            return CGSize(width: max(lead.width, rest.width), height: lead.height + gap + rest.height)
        case .empty: return .zero
        }
    }

    private static func largestScale(_ ordered: [OverviewDeskMonitor], in room: CGSize, extent: (CGFloat) -> CGSize) -> CGFloat {
        let widest = ordered.map { physical($0).width }.max() ?? 1
        var low: CGFloat = 0, high = room.width / widest
        for _ in 0..<28 {
            let mid = (low + high) / 2
            let size = extent(mid)
            if size.width <= room.width && size.height <= room.height { low = mid } else { high = mid }
        }
        return low
    }

    private static func physical(_ monitor: OverviewDeskMonitor) -> CGSize {
        let size = monitor.display.bounds.size
        return size.width > 0 && size.height > 0 ? size : CGSize(width: 1600, height: 1000)
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
        case .single:
            result.append(moved(lead, x: (room.width - lead.frame.width) / 2, y: (room.height - lead.frame.height) / 2))
        case .empty, .spatial: return plan
        }
        return Plan(arrangement: plan.arrangement, placements: result)
    }

    /// One monitor at `scale` points per display point: its map, its Desktop
    /// strip unless compact, and the head above them.
    private static func sized(_ monitor: OverviewDeskMonitor, scale: CGFloat, compact: Bool) -> Placement {
        let size = physical(monitor)
        let aspect = size.width / size.height
        let count = CGFloat(max(1, monitor.spaces.count))
        let width = floor(size.width * scale), height = floor(width / aspect)
        let thumbWidth = compact ? 0 : floor(min(84, max(24, (width - 6 * (count - 1)) / count)))
        let thumbHeight = floor(thumbWidth / aspect)
        let chrome: CGFloat = compact ? 34 : 58
        return Placement(id: monitor.id,
            frame: CGRect(x: 0, y: 0, width: width, height: height + chrome + thumbHeight),
            map: CGSize(width: width, height: height), thumb: CGSize(width: thumbWidth, height: thumbHeight), compact: compact)
    }
}
