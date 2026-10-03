import AppKit

/// Geometry comes from the same projection as the native desk. Never runs actions.
struct EditorGeometry {
    let displays: [OverviewDisplay]
    let mainID: UInt32
    let rows: [UInt32: OverviewRow]
    let visibleFrame: CGRect?
    let standardWindows: Set<UInt32>
    let tucked: [String: Set<UInt32>]

    init(windows: [WindowEntry], displays: [OverviewDisplay], mainID: UInt32,
         homes: [UInt32: CGRect] = [:], visibleFrame: CGRect? = nil,
         standardWindows: Set<UInt32> = [], tucked: [String: Set<UInt32>] = [:]) {
        self.displays = displays
        self.mainID = mainID
        self.visibleFrame = visibleFrame
        self.standardWindows = standardWindows
        self.tucked = tucked
        let main = displays.first { $0.displayId == mainID }?.bounds ?? .zero
        rows = OverviewProjection.make(.init(windows: windows, displays: displays, main: main, homes: homes),
                                       scope: .all, selection: []).all
    }

    static func frame(_ rect: CGRect?) -> Any {
        guard let rect, [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite),
              rect.width > 0, rect.height > 0 else { return NSNull() }
        return ["x": rect.minX, "y": rect.minY, "w": rect.width, "h": rect.height]
    }

    var wireDisplays: [[String: Any]] {
        displays.compactMap { display in
            let id = display.displayId
            guard !(Self.frame(display.bounds) is NSNull) else { return nil }
            return ["id": String(id), "name": display.name, "main": id == mainID, "frame": Self.frame(display.bounds)]
        }
    }

    func window(_ wid: UInt32) -> [String: Any] {
        guard let row = rows[wid] else {
            return ["frame": NSNull(), "displayId": NSNull(), "frameSource": "unavailable"]
        }
        let display = displays.first { $0.index == row.display }
        let source: String
        switch row.position {
        case .live: source = "live"
        case .lastKnown: source = "lastKnown"
        case .savedHome: source = "savedHome"
        case .none: source = "unavailable"
        }
        return ["frame": Self.frame(row.frame),
                "displayId": display.map { String($0.displayId) } as Any? ?? NSNull(), "frameSource": source]
    }

    func preview(_ layer: Layer, members: [LayerMembership.Member]) -> [String: Any]? {
        guard let name = layer.layout, let kind = LayerLayout.Kind(name),
              let main = displays.first(where: { $0.displayId == mainID }),
              main.desktops.contains(main.currentSpaceId), let visibleFrame else { return nil }
        let plan = LayerLayout.plan(kind, members: members, excluding: tucked[layer.id] ?? [],
            main: main.bounds, otherDisplays: displays.filter { $0.displayId != mainID }.map(\.bounds),
            currentSpace: main.currentSpaceId, visibleFrame: visibleFrame, standardWindows: standardWindows)
        guard !plan.isEmpty else { return nil }
        return ["layout": name, "displayId": String(mainID), "frames": plan.map {
            ["windowId": $0.entry.wid, "frame": Self.frame($0.frame)] as [String: Any]
        }]
    }

    static func live(windows: [WindowEntry]) -> Self {
        let displays = OverviewModel.liveDisplays()
        let main = CGMainDisplayID()
        let screen = OverviewModel.screen(forDisplayID: main)
        let visible = screen.map { WindowTiler.tileFrame(fractions: (0, 0, 1, 1), on: $0) }
        // AX reads only: no permission requests, window mutations, or rebinds.
        let standard = AXIsProcessTrusted() ? Set(WorkspaceManager.standardWindows(of: Set(windows.map(\.pid))).keys) : []
        return Self(windows: windows, displays: displays, mainID: main,
                    homes: LayerStage.shared.homes(), visibleFrame: visible,
                    standardWindows: standard, tucked: LayerStage.shared.tuckedByLayer())
    }
}
