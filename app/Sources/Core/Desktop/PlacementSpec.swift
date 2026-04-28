import CoreGraphics
import Foundation

struct GridPlacement: Equatable {
    let columns: Int
    let rows: Int
    let column: Int
    let row: Int

    init?(columns: Int, rows: Int, column: Int, row: Int) {
        guard columns > 0, rows > 0,
              column >= 0, column < columns,
              row >= 0, row < rows else { return nil }
        self.columns = columns
        self.rows = rows
        self.column = column
        self.row = row
    }

    static func parse(_ str: String) -> GridPlacement? {
        let parts = str.split(separator: ":")
        guard parts.count == 3, parts[0] == "grid" else { return nil }
        let dims = parts[1].split(separator: "x")
        let coords = parts[2].split(separator: ",")
        guard dims.count == 2, coords.count == 2,
              let columns = Int(dims[0]), let rows = Int(dims[1]),
              let column = Int(coords[0]), let row = Int(coords[1]) else {
            return nil
        }
        return GridPlacement(columns: columns, rows: rows, column: column, row: row)
    }

    var fractions: (CGFloat, CGFloat, CGFloat, CGFloat) {
        let w = 1.0 / CGFloat(columns)
        let h = 1.0 / CGFloat(rows)
        return (CGFloat(column) * w, CGFloat(row) * h, w, h)
    }

    var wireValue: String {
        "grid:\(columns)x\(rows):\(column),\(row)"
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
            guard let columns = obj["columns"]?.intValue,
                  let rows = obj["rows"]?.intValue,
                  let column = obj["column"]?.intValue,
                  let row = obj["row"]?.intValue,
                  let grid = GridPlacement(columns: columns, rows: rows, column: column, row: row) else {
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
