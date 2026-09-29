import Foundation

/// Where layers sit on the ⌘⌥1–9 pad: the eight slots round the middle, in
/// reading order. The middle slot holds the bezel's pointer, not a layer, so
/// the fifth layer sits in slot 6 and a ninth layer has no slot. The arrows
/// move across the pad the way they point.
enum LayerSlots {
    /// ⌘⌥5 shows where you are rather than switching.
    static let centre = 5
    /// The slots layers fill, in order.
    static let ordered = [1, 2, 3, 4, 6, 7, 8, 9]

    enum Direction {
        case left, right, up, down
    }

    /// The slot layer `index` sits in, if it has one.
    static func slot(forIndex index: Int) -> Int? {
        ordered.indices.contains(index) ? ordered[index] : nil
    }

    /// The layer that slot `slot` holds, when that many layers exist.
    static func index(forSlot slot: Int) -> Int? {
        ordered.firstIndex(of: slot)
    }

    /// The layer a step from layer `index` lands on among `count`: the
    /// nearest slot that way holding a layer, hopping the middle. Nil at the
    /// pad's edge, so steps don't wrap.
    static func neighbour(of index: Int, _ direction: Direction, count: Int) -> Int? {
        guard let start = slot(forIndex: index) else { return nil }
        let (dc, dr): (Int, Int)
        switch direction {
        case .left: (dc, dr) = (-1, 0)
        case .right: (dc, dr) = (1, 0)
        case .up: (dc, dr) = (0, -1)
        case .down: (dc, dr) = (0, 1)
        }
        var col = (start - 1) % 3
        var row = (start - 1) / 3
        while true {
            col += dc
            row += dr
            guard (0..<3).contains(col), (0..<3).contains(row) else { return nil }
            if let next = self.index(forSlot: row * 3 + col + 1), next < count {
                return next
            }
        }
    }
}
