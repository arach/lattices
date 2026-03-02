import Foundation

struct WindowEntry: Codable, Identifiable {
    let wid: UInt32
    let app: String
    let pid: Int32
    let title: String
    let frame: WindowFrame
    let spaceIds: [Int]
    let isOnScreen: Bool
    let latticesSession: String?

    var id: UInt32 { wid }
}

struct WindowFrame: Codable, Equatable {
    let x: Double
    let y: Double
    let w: Double
    let h: Double
}

// MARK: - Desktop Inventory Snapshot

struct DesktopInventorySnapshot {
    let displays: [DisplayInfo]
    let timestamp: Date

    struct DisplayInfo: Identifiable {
        let id: String           // display UUID or index
        let name: String         // e.g. "Built-in Retina", "LG UltraFine"
        let resolution: (w: Int, h: Int)
        let visibleFrame: (w: Int, h: Int)
        let isMain: Bool
        let spaceCount: Int
        let currentSpaceIndex: Int
        let spaces: [SpaceGroup]
    }

    struct SpaceGroup: Identifiable {
        let id: Int              // CGS space ID
        let index: Int           // 1-based index within display
        let isCurrent: Bool
        let apps: [AppGroup]
    }

    struct AppGroup: Identifiable {
        let id: String           // unique key (spaceId-appName)
        let appName: String
        let windows: [InventoryWindowInfo]
    }

    struct InventoryWindowInfo: Identifiable {
        let id: UInt32           // CGWindowID
        let pid: Int32           // owner PID for AX operations
        let title: String
        let frame: WindowFrame
        let tilePosition: TilePosition?
        let isLattices: Bool
        let latticesSession: String?
        let spaceIndex: Int?     // 1-based space index within display
        let isOnScreen: Bool     // on current space
        var inventoryPath: InventoryPath?
        var appName: String?     // owner app name for filtering
    }

    /// Flat list of all windows across all displays/spaces/apps
    var allWindows: [InventoryWindowInfo] {
        displays.flatMap { $0.spaces.flatMap { $0.apps.flatMap { $0.windows } } }
    }
}
