import AppKit

/// What a switch to a layer would leave on the main screen, worked out
/// without moving anything: where each window would sit, front to back,
/// what would be put away, and the layer's windows a switch leaves where
/// they are (another desktop, another display) or can't show (not running).
/// The layer pad draws it while ⌘⌥ aims (`LayerAim`).
struct LayerForecast: Equatable {
    struct Tile: Equatable {
        let wid: UInt32
        let app: String
        let title: String
        /// Where it would sit, as a share of the main screen, y down.
        let frame: CGRect
        /// The layer's own window, not one it had showing beside them.
        let member: Bool
        /// Not showing now: it comes back with the switch.
        let returning: Bool
    }

    /// One of the layer's apps the switch can't show here, and why.
    struct Away: Equatable {
        let app: String
        let pid: Int32?
        let note: String
    }

    /// Back to front.
    var tiles: [Tile] = []
    /// The main screen's width over its height.
    var aspect: CGFloat = 16 / 10
    var away: [Away] = []
    /// The apps whose showing windows the switch puts away, front first.
    var putAway: [String] = []
    /// How many windows that is.
    var putAwayCount = 0

    /// Where each of `want` would sit: at `planned` when the layout places
    /// it, back home from the park corner when `homes` has it, else where
    /// it is. `members` are the layer's own; the rest are its scene. Back
    /// to front: the scene, then the members, the layout's first window
    /// last, each group in the order they stack now. `showing` is what's
    /// showing on the main screen now; what of it isn't wanted goes away,
    /// except when nothing is wanted, which puts away only `tucked`.
    static func make(
        want: Set<UInt32>,
        members: Set<UInt32>,
        windows: [WindowEntry],
        bounds: CGRect,
        homes: [UInt32: CGRect],
        planned: [(wid: UInt32, frame: CGRect)],
        showing: Set<UInt32>,
        tucked: Set<UInt32>
    ) -> LayerForecast {
        var forecast = LayerForecast()
        guard bounds.width > 0, bounds.height > 0 else { return forecast }
        forecast.aspect = bounds.width / bounds.height
        let placed = Dictionary(planned.map { ($0.wid, $0.frame) }, uniquingKeysWith: { first, _ in first })
        let lead = planned.first?.wid

        let shown = want.isEmpty ? showing.subtracting(tucked) : want
        let ordered = windows
            .filter { shown.contains($0.wid) }
            .sorted { a, b in
                let (am, bm) = (members.contains(a.wid), members.contains(b.wid))
                if am != bm { return !am }
                if (a.wid == lead) != (b.wid == lead) { return b.wid == lead }
                return a.zIndex > b.zIndex
            }
        var seen = Set<UInt32>()
        for entry in ordered where seen.insert(entry.wid).inserted {
            let now = CGRect(x: entry.frame.x, y: entry.frame.y, width: entry.frame.w, height: entry.frame.h)
            let rect = placed[entry.wid] ?? homes[entry.wid] ?? now
            let unit = CGRect(
                x: (rect.minX - bounds.minX) / bounds.width,
                y: (rect.minY - bounds.minY) / bounds.height,
                width: rect.width / bounds.width,
                height: rect.height / bounds.height
            ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            guard !unit.isNull, unit.width > 0.01, unit.height > 0.01 else { continue }
            forecast.tiles.append(Tile(
                wid: entry.wid, app: entry.app, title: entry.title, frame: unit,
                member: members.contains(entry.wid), returning: !showing.contains(entry.wid)
            ))
        }

        let leaving = windows
            .filter { showing.contains($0.wid) && !shown.contains($0.wid) }
            .sorted { $0.zIndex < $1.zIndex }
        forecast.putAwayCount = Set(leaving.map(\.wid)).count
        for entry in leaving where !forecast.putAway.contains(entry.app) {
            forecast.putAway.append(entry.app)
        }
        return forecast
    }

    /// What the pad writes beside an app the switch can't show here.
    static func note(for place: LayerRoster.Place) -> String? {
        switch place {
        case .here: return nil
        case .desktop(let number): return "Stays on Desktop \(number)"
        case .display(let side, _) where side == .other: return "On the other display"
        case .display(let side, _): return "On the \(side.rawValue) display"
        case .fullScreen: return "Full screen"
        case .noWindow: return "No window open"
        case .notOpen: return "Not running"
        }
    }
}

extension WorkspaceManager {
    /// What switching to layer `index` would leave on the main screen; nil
    /// when the main screen isn't showing a desktop.
    func forecast(for index: Int) -> LayerForecast? {
        let layers = self.layers
        guard layers.indices.contains(index), let stage = LayerStage.Stage.current() else { return nil }
        let layer = layers[index]
        let windows = DesktopModel.shared.allWindows()
        let resolution = layerMembership(in: windows)
        var claimed = Set<UInt32>()
        for (id, held) in zip(resolution.ids, resolution.layers) where id != layer.id {
            claimed.formUnion(held.map(\.entry.wid))
        }
        let held = resolution.members(of: layer.id)
        let own = Set(held.map(\.entry.wid))
        let stageState = LayerStage.shared
        let tucked = stageState.tucked(layer.id)
        let want = LayerStage.want(
            own: own,
            scene: stageState.scene(for: layer) + stageState.untucked(layer.id),
            claimed: claimed,
            tucked: tucked,
            windows: windows,
            stage: stage
        )
        let showing = Set(windows.filter { LayerStage.isShowing($0, on: stage) }.map(\.wid))

        var planned: [(wid: UInt32, frame: CGRect)] = []
        if let name = layer.layout, let kind = LayerLayout.Kind(name), let screen = NSScreen.screens.first {
            let candidates = held.filter { !$0.entry.collapsed }
            planned = LayerLayout.plan(
                kind, members: candidates, excluding: tucked,
                main: stage.bounds, otherDisplays: stage.others, currentSpace: stage.spaceId,
                visibleFrame: WindowTiler.tileFrame(fractions: (0, 0, 1, 1), on: screen),
                standardWindows: Set(candidates.map(\.entry.wid))
            ).map { ($0.entry.wid, $0.frame) }
        }

        var forecast = LayerForecast.make(
            want: want, members: own, windows: windows, bounds: stage.bounds,
            homes: stageState.homes(), planned: planned, showing: showing, tucked: tucked
        )
        let onMap = Set(forecast.tiles.map(\.app))
        for app in roster(of: layer, in: windows) where !app.extra && !app.stayed && !onMap.contains(app.name) {
            guard let place = app.place, let note = LayerForecast.note(for: place) else { continue }
            forecast.away.append(LayerForecast.Away(app: app.name, pid: app.pid, note: note))
        }
        return forecast
    }
}
