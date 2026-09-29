import CoreGraphics

/// Where a layer's windows go on its display, for the layer's `layout`, as
/// unit rects with y = 0 at the top. Pure, so it's tested without windows.
///
/// `auto` sorts windows into lanes by app type: terminals and chat on the
/// left, editors and design in the middle, browsers and the rest on the
/// right. On an ultrawide each lane gets a column and stacks its windows; on
/// a standard display the main window takes the left half and the rest stack
/// on the right. A lone window sits centred at half width on an ultrawide,
/// and fills a standard display.
enum LayerLayout {
    enum Kind: Equatable {
        case auto
        /// Equal columns in entry order, each stacking its windows.
        case columns
        /// The first window on the left, the rest stacked on the right.
        case masterStack

        init?(_ name: String) {
            switch name.lowercased() {
            case "auto", "smart": self = .auto
            case "columns", "cols": self = .columns
            case "master-stack", "master", "main": self = .masterStack
            default: return nil
            }
        }
    }

    enum Lane: CaseIterable {
        case left, middle, right
    }

    /// 21:9 and wider.
    static let ultrawide: CGFloat = 2.0
    /// The master's share of the width, as in grid.json's master-stack layouts.
    static let masterRatio: CGFloat = 0.62
    /// Lane widths on an ultrawide when all three lanes are used.
    static let laneWidths: [CGFloat] = [0.3, 0.4, 0.3]

    static func lane(for type: AppType) -> Lane {
        switch type {
        case .terminal, .chat: return .left
        case .editor, .design: return .middle
        case .browser, .media, .system, .other: return .right
        }
    }

    /// One unit rect per window, in the order of `types`: the layer's entry
    /// order, its main window first. `aspect` is the display's width over its
    /// height.
    static func frames(_ kind: Kind, types: [AppType], aspect: CGFloat) -> [CGRect] {
        guard !types.isEmpty else { return [] }
        let wide = aspect >= ultrawide
        let whole = CGRect(x: 0, y: 0, width: 1, height: 1)
        if types.count == 1 {
            return [wide ? CGRect(x: 0.25, y: 0, width: 0.5, height: 1) : whole]
        }
        var frames = Array(repeating: whole, count: types.count)
        let all = Array(types.indices)
        switch kind {
        case .auto:
            let lanes = Lane.allCases
                .map { lane in all.filter { self.lane(for: types[$0]) == lane } }
                .filter { !$0.isEmpty }
            if wide {
                switch lanes.count {
                case 1:
                    columns(lanes[0], count: 4, in: whole, into: &frames)
                case 2:
                    stack(lanes[0], in: CGRect(x: 0, y: 0, width: 0.5, height: 1), into: &frames)
                    stack(lanes[1], in: CGRect(x: 0.5, y: 0, width: 0.5, height: 1), into: &frames)
                default:
                    var x: CGFloat = 0
                    for (lane, width) in zip(lanes, laneWidths) {
                        stack(lane, in: CGRect(x: x, y: 0, width: width, height: 1), into: &frames)
                        x += width
                    }
                }
            } else {
                // The editor leads when there is one.
                let main = all.first { lane(for: types[$0]) == .middle } ?? lanes[0][0]
                frames[main] = CGRect(x: 0, y: 0, width: 0.5, height: 1)
                let rest = lanes.joined().filter { $0 != main }
                stack(Array(rest), in: CGRect(x: 0.5, y: 0, width: 0.5, height: 1), into: &frames)
            }
        case .columns:
            columns(all, count: wide ? 4 : 3, in: whole, into: &frames)
        case .masterStack:
            frames[0] = CGRect(x: 0, y: 0, width: masterRatio, height: 1)
            stack(Array(all.dropFirst()), in: CGRect(x: masterRatio, y: 0, width: 1 - masterRatio, height: 1), into: &frames)
        }
        return frames
    }

    /// `members` in up to `count` equal columns of `area`, the leftmost
    /// columns taking any extra, each stacked.
    private static func columns(_ members: [Int], count: Int, in area: CGRect, into frames: inout [CGRect]) {
        let count = max(1, min(count, members.count))
        let width = area.width / CGFloat(count)
        var next = 0
        for column in 0..<count {
            let size = members.count / count + (column < members.count % count ? 1 : 0)
            let rect = CGRect(x: area.minX + CGFloat(column) * width, y: area.minY, width: width, height: area.height)
            stack(Array(members[next..<next + size]), in: rect, into: &frames)
            next += size
        }
    }

    /// `members` stacked in `area`: up to three as rows, more as a grid two
    /// wide, where a last one on its own spans its row.
    private static func stack(_ members: [Int], in area: CGRect, into frames: inout [CGRect]) {
        guard !members.isEmpty else { return }
        if members.count <= 3 {
            let height = area.height / CGFloat(members.count)
            for (row, member) in members.enumerated() {
                frames[member] = CGRect(x: area.minX, y: area.minY + CGFloat(row) * height, width: area.width, height: height)
            }
            return
        }
        let rows = (members.count + 1) / 2
        let height = area.height / CGFloat(rows)
        let width = area.width / 2
        for (position, member) in members.enumerated() {
            let (row, column) = (position / 2, position % 2)
            let alone = column == 0 && position == members.count - 1
            frames[member] = CGRect(
                x: area.minX + CGFloat(column) * width,
                y: area.minY + CGFloat(row) * height,
                width: alone ? area.width : width,
                height: height
            )
        }
    }
}
