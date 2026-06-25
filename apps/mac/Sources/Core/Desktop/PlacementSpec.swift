import CoreGraphics
import Foundation

struct GridPlacement: Equatable {
    let columns: Int
    let rows: Int
    let column: Int
    let row: Int
    /// How many cells this placement spans. 1×1 is a single cell; larger values
    /// tile the window across a rectangular block of cells (e.g. a 2×2 quadrant
    /// of a 4×4 grid). `column + columnSpan <= columns` always holds.
    let columnSpan: Int
    let rowSpan: Int

    init?(columns: Int, rows: Int, column: Int, row: Int, columnSpan: Int = 1, rowSpan: Int = 1) {
        guard columns > 0, rows > 0,
              column >= 0, row >= 0,
              columnSpan >= 1, rowSpan >= 1,
              column + columnSpan <= columns,
              row + rowSpan <= rows else { return nil }
        self.columns = columns
        self.rows = rows
        self.column = column
        self.row = row
        self.columnSpan = columnSpan
        self.rowSpan = rowSpan
    }

    /// Build from two (possibly unordered) cell corners, both inclusive.
    init?(columns: Int, rows: Int, from: (col: Int, row: Int), to: (col: Int, row: Int)) {
        let c0 = min(from.col, to.col), c1 = max(from.col, to.col)
        let r0 = min(from.row, to.row), r1 = max(from.row, to.row)
        self.init(columns: columns, rows: rows, column: c0, row: r0,
                  columnSpan: c1 - c0 + 1, rowSpan: r1 - r0 + 1)
    }

    static func parse(_ str: String) -> GridPlacement? {
        let parts = str.split(separator: ":")
        let dimsPart: Substring
        let cellsPart: Substring
        let oneBasedCoordinates: Bool
        if parts.count == 3, parts[0] == "grid" {
            dimsPart = parts[1]
            cellsPart = parts[2]
            oneBasedCoordinates = false
        } else if parts.count == 2 {
            dimsPart = parts[0]
            cellsPart = parts[1]
            oneBasedCoordinates = true
        } else {
            return nil
        }

        let dims = dimsPart.split(separator: "x")
        guard dims.count == 2, let columns = Int(dims[0]), let rows = Int(dims[1]) else { return nil }

        // Coordinates are either a single cell ("c,r") or an inclusive span
        // between two corners ("c0,r0-c1,r1", e.g. "grid:4x4:0,0-1,1").
        // The explicit `grid:` wire form is 0-based for API compatibility.
        // The compact command form ("4x4:1,1") is 1-based for humans.
        func cell(_ s: Substring) -> (col: Int, row: Int)? {
            let xy = s.split(separator: ",")
            guard xy.count == 2, let c = Int(xy[0]), let r = Int(xy[1]) else { return nil }
            return oneBasedCoordinates ? (c - 1, r - 1) : (c, r)
        }
        let corners = cellsPart.split(separator: "-", maxSplits: 1)
        guard let start = cell(corners[0]) else { return nil }
        if corners.count == 2 {
            guard let end = cell(corners[1]) else { return nil }
            return GridPlacement(columns: columns, rows: rows, from: start, to: end)
        }
        return GridPlacement(columns: columns, rows: rows, column: start.col, row: start.row)
    }

    /// Shorthand: `grid:N.K` → an N×N grid, K-th cell in row-major order
    /// (1-indexed). Useful for the command bar and voice, where typing the full
    /// `grid:4x4:0,0` is heavy. K must lie in `[1, N*N]`.
    /// Examples: `grid:4.1` → top-left, `grid:4.5` → row 2 col 1, `grid:4.16` → bottom-right.
    static func parseShorthand(_ str: String) -> GridPlacement? {
        let parts = str.split(separator: ":")
        guard parts.count == 2, parts[0] == "grid" else { return nil }
        let pair = parts[1].split(separator: ".")
        guard pair.count == 2,
              let n = Int(pair[0]), n > 0,
              let k = Int(pair[1]), k >= 1, k <= n * n else { return nil }
        let k0 = k - 1
        let column = k0 % n
        let row = k0 / n
        return GridPlacement(columns: n, rows: n, column: column, row: row)
    }

    var fractions: (CGFloat, CGFloat, CGFloat, CGFloat) {
        let w = 1.0 / CGFloat(columns)
        let h = 1.0 / CGFloat(rows)
        return (CGFloat(column) * w, CGFloat(row) * h, CGFloat(columnSpan) * w, CGFloat(rowSpan) * h)
    }

    /// True when this placement covers exactly one cell.
    var isSingleCell: Bool { columnSpan == 1 && rowSpan == 1 }

    var wireValue: String {
        if isSingleCell { return "grid:\(columns)x\(rows):\(column),\(row)" }
        return "grid:\(columns)x\(rows):\(column),\(row)-\(column + columnSpan - 1),\(row + rowSpan - 1)"
    }

    var compactValue: String {
        let start = "\(column + 1),\(row + 1)"
        if isSingleCell { return "\(columns)x\(rows):\(start)" }
        return "\(columns)x\(rows):\(start)-\(column + columnSpan),\(row + rowSpan)"
    }
}

struct FractionalPlacement: Equatable {
    let x: CGFloat
    let y: CGFloat
    let w: CGFloat
    let h: CGFloat

    init?(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
        guard x >= 0, y >= 0, w > 0, h > 0,
              x + w <= 1.0001, y + h <= 1.0001 else { return nil }
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    var fractions: (CGFloat, CGFloat, CGFloat, CGFloat) {
        (x, y, w, h)
    }
}

enum PlacementSpec: Equatable {
    case tile(TilePosition)
    case grid(GridPlacement)
    case fractions(FractionalPlacement)

    init?(string: String) {
        let normalized = PlacementSpec.normalize(string)
        if let position = TilePosition(rawValue: normalized) {
            self = .tile(position)
            return
        }
        if let alias = PlacementSpec.aliases[normalized], let position = TilePosition(rawValue: alias) {
            self = .tile(position)
            return
        }
        if let grid = GridPlacement.parse(normalized) {
            self = .grid(grid)
            return
        }
        if let grid = GridPlacement.parseShorthand(normalized) {
            self = .grid(grid)
            return
        }
        return nil
    }

    init?(json: JSON?) {
        guard let json else { return nil }

        if let string = json.stringValue {
            self.init(string: string)
            return
        }

        guard case .object(let obj) = json,
              let kind = obj["kind"]?.stringValue?.lowercased() else {
            return nil
        }

        switch kind {
        case "tile", "named", "position":
            guard let value = obj["value"]?.stringValue else { return nil }
            self.init(string: value)
        case "grid":
            let columnSpan = obj["columnSpan"]?.intValue ?? 1
            let rowSpan = obj["rowSpan"]?.intValue ?? 1
            guard let columns = obj["columns"]?.intValue,
                  let rows = obj["rows"]?.intValue,
                  let column = obj["column"]?.intValue,
                  let row = obj["row"]?.intValue,
                  let grid = GridPlacement(columns: columns, rows: rows, column: column, row: row,
                                           columnSpan: columnSpan, rowSpan: rowSpan) else {
                return nil
            }
            self = .grid(grid)
        case "fractions":
            guard let x = obj["x"]?.numericDouble,
                  let y = obj["y"]?.numericDouble,
                  let w = obj["w"]?.numericDouble,
                  let h = obj["h"]?.numericDouble,
                  let placement = FractionalPlacement(
                    x: CGFloat(x),
                    y: CGFloat(y),
                    w: CGFloat(w),
                    h: CGFloat(h)
                  ) else {
                return nil
            }
            self = .fractions(placement)
        default:
            return nil
        }
    }

    var fractions: (CGFloat, CGFloat, CGFloat, CGFloat) {
        switch self {
        case .tile(let position):
            return position.rect
        case .grid(let grid):
            return grid.fractions
        case .fractions(let placement):
            return placement.fractions
        }
    }

    var wireValue: String {
        switch self {
        case .tile(let position):
            return position.rawValue
        case .grid(let grid):
            return grid.wireValue
        case .fractions(let placement):
            return "fractions:\(placement.x),\(placement.y),\(placement.w),\(placement.h)"
        }
    }

    var compactValue: String {
        switch self {
        case .tile(let position):
            return position.rawValue
        case .grid(let grid):
            return grid.compactValue
        case .fractions:
            return wireValue
        }
    }

    var jsonValue: JSON {
        switch self {
        case .tile(let position):
            return .object([
                "kind": .string("tile"),
                "value": .string(position.rawValue),
            ])
        case .grid(let grid):
            return .object([
                "kind": .string("grid"),
                "columns": .int(grid.columns),
                "rows": .int(grid.rows),
                "column": .int(grid.column),
                "row": .int(grid.row),
                "columnSpan": .int(grid.columnSpan),
                "rowSpan": .int(grid.rowSpan),
            ])
        case .fractions(let placement):
            return .object([
                "kind": .string("fractions"),
                "x": .double(Double(placement.x)),
                "y": .double(Double(placement.y)),
                "w": .double(Double(placement.w)),
                "h": .double(Double(placement.h)),
            ])
        }
    }

    private static func normalize(_ string: String) -> String {
        string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }

    private static let aliases: [String: String] = [
        "upper-third": "top-third",
        "lower-third": "bottom-third",
        "left-quarter": "left-quarter",
        "right-quarter": "right-quarter",
        "top-quarter": "top-quarter",
        "bottom-quarter": "bottom-quarter",
    ]
}
