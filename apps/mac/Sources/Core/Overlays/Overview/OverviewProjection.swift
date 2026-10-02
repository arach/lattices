import CoreGraphics
import Foundation

// Overview's derived state: one pure function from windows, layers, stage
// data, displays, scope and selection to rows, canvas items, counts and
// bulk plans. No AX calls and no window-server reads, so every rule runs
// from fixtures.

/// What Overview browses. Changing it never touches the desktop.
struct OverviewScope: Codable, Equatable {
    /// A display index, nil for every monitor.
    var display: Int?
    /// A Space id, nil for every Space.
    var spaceId: Int?
    /// A ⌘⌥ layer id, nil for all windows.
    var layerId: String?
    var search: String = ""
    /// A `FilterPreset` raw value, nil for all.
    var preset: String?

    static let all = OverviewScope()
    static let defaultsKey = "overview.scope.v1"

    var filterPreset: FilterPreset? { preset.flatMap(FilterPreset.init(rawValue:)) }
    var isLocated: Bool { display != nil || spaceId != nil }

    static func load(from defaults: UserDefaults = .standard) -> OverviewScope {
        guard let data = defaults.data(forKey: defaultsKey),
              let scope = try? JSONDecoder().decode(OverviewScope.self, from: data) else { return .all }
        return scope
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

/// One monitor as Overview sees it, in CG coordinates.
struct OverviewDisplay: Equatable {
    let index: Int
    let name: String
    /// CG (top-left origin) bounds.
    let bounds: CGRect
    /// Its desktops in Mission Control order, numbered from 1.
    let desktops: [Int]
    /// The Space it's showing, which can be a full-screen Space.
    let currentSpaceId: Int
    /// Every Space it owns, full-screen ones included.
    var spaceIds: [Int] = []
    /// CGDirectDisplayID, to find its screen when acting.
    var displayId: UInt32 = 0

    func desktopNumber(of spaceId: Int) -> Int? {
        desktops.firstIndex(of: spaceId).map { $0 + 1 }
    }

    func owns(_ spaceId: Int) -> Bool {
        desktops.contains(spaceId) || spaceIds.contains(spaceId)
    }
}

/// Where a window's outline comes from. A position is never invented.
enum PositionSource: Equatable {
    case live
    case lastKnown
    case savedHome
    case none(String)

    var label: String? {
        switch self {
        case .live: return nil
        case .lastKnown: return "Last known"
        case .savedHome: return "Saved home"
        case .none(let reason): return reason
        }
    }
}

/// What a window is doing, as far as the inputs can confirm.
enum OverviewWindowState: Equatable {
    /// On the Space its monitor is showing.
    case showing
    case otherSpace(desktop: Int?)
    case fullScreen
    case appHidden
    case parked
    /// Minimized or closed: Spaces can't place it.
    case unknown

    var label: String {
        switch self {
        case .showing: return "Showing"
        case .otherSpace(let number?): return "Desktop \(number)"
        case .otherSpace(nil): return "Another Space"
        case .fullScreen: return "Full screen"
        case .appHidden: return "App hidden"
        case .parked: return "Parked"
        case .unknown: return "Minimized or closed"
        }
    }
}

/// Why a window is left out of a scope or an action.
enum Exclusion: Hashable {
    case otherSpace(desktop: Int?)
    case appHidden
    case parked
    case unknown
    case notOpen
    case noWindow
    case fullScreen
    case outsideMonitor
    case outsideSpace
    case outsideLayer
    case search
    case preset
    case tucked
    case gone

    var label: String {
        switch self {
        case .otherSpace(let number?): return "on Desktop \(number)"
        case .otherSpace(nil): return "on another Space"
        case .appHidden: return "app hidden"
        case .parked: return "parked"
        case .unknown: return "minimized or closed"
        case .notOpen: return "not open"
        case .noWindow: return "no window"
        case .fullScreen: return "full screen"
        case .outsideMonitor: return "on another monitor"
        case .outsideSpace: return "on another Space"
        case .outsideLayer: return "outside the layer"
        case .search: return "hidden by search"
        case .preset: return "hidden by filter"
        case .tucked: return "tucked"
        case .gone: return "closed"
        }
    }
}

/// A window's part in the scoped layer.
enum OverviewRole: Equatable {
    case member
    case tucked
    case unclaimed
}

struct OverviewRow: Identifiable, Equatable {
    let wid: UInt32
    let pid: Int32
    let app: String
    let title: String
    let display: Int?
    let spaceId: Int?
    let state: OverviewWindowState
    /// CG frame: live, last known or saved home, per `position`.
    let frame: CGRect?
    let position: PositionSource
    /// The layers whose members include it.
    let layerIds: [String]
    let tier: LayerMembership.Tier?
    let role: OverviewRole?
    /// In the monitor and Space scope.
    let inScope: Bool
    var id: UInt32 { wid }
}

/// A group of rows under one monitor and Space heading.
struct OverviewRowGroup: Identifiable, Equatable {
    let id: String
    let title: String
    let inScope: Bool
    let rows: [OverviewRow]
}

/// One Space on a monitor as Overview's desk lays it out: its map and the
/// rows that live there.
struct OverviewDeskSpace: Identifiable, Equatable {
    let spaceId: Int
    /// Its Mission Control number, nil for a full-screen Space.
    let desktop: Int?
    /// The Space its monitor is showing: the only one with live positions.
    let isCurrent: Bool
    /// In the monitor and Space scope.
    let inScope: Bool
    /// Matched rows on this Space, front to back.
    let rows: [OverviewRow]
    var id: Int { spaceId }

    var title: String { desktop.map { "Desktop \($0)" } ?? "Full screen" }

    /// Only the showing Space has live positions. Elsewhere the map draws
    /// last-known frames or saved homes; this says which. A full-screen
    /// Space has no frames, so it only says it isn't showing.
    var mapNote: String? {
        guard !isCurrent else { return nil }
        guard desktop != nil else { return rows.isEmpty ? nil : "not showing" }
        let sources = rows.filter { $0.frame != nil }.map(\.position)
        if sources.contains(.lastKnown) { return "last known" }
        if sources.contains(.savedHome) { return "saved homes" }
        return nil
    }

    /// Whether the map draws `row` solid: a live frame, or a full-screen
    /// window on the Space its monitor is showing.
    func drawsLive(_ row: OverviewRow) -> Bool {
        desktop == nil ? isCurrent : row.position == .live
    }
}

/// One monitor and every Space it owns, left to right as they're arranged.
struct OverviewDeskMonitor: Identifiable, Equatable {
    let display: OverviewDisplay
    let inScope: Bool
    /// Its desktops in order, all of them, then any full-screen Space
    /// showing or holding a matched window.
    let spaces: [OverviewDeskSpace]
    var id: Int { display.index }
    var rowCount: Int { spaces.reduce(0) { $0 + $1.rows.count } }
}

/// A window drawn on the canvas: a live tile or a labelled outline.
struct OverviewCanvasItem: Identifiable, Equatable {
    let wid: UInt32
    let app: String
    let title: String
    let frame: CGRect
    let position: PositionSource
    let state: OverviewWindowState
    var id: UInt32 { wid }
    var isOutline: Bool { position != .live }
}

struct OverviewCounts: Equatable {
    /// Confirmed windows matching search, preset and layer.
    var matched = 0
    /// Of those, in the monitor and Space scope.
    var inScope = 0
    /// Of those, drawn on the canvas.
    var onCanvas = 0
    /// Matched windows Spaces can't place, kept out of the confirmed totals.
    var unknown = 0
    var located = false

    var elsewhere: Int { matched - inScope }

    var line: String {
        var parts = ["\(matched) matched \(matched == 1 ? "window" : "windows")"]
        if located {
            parts.append("\(inScope) in this scope")
            parts.append("\(elsewhere) elsewhere")
        }
        if unknown > 0 { parts.append("\(unknown) unknown") }
        return parts.joined(separator: " · ")
    }
}

/// What the hosted canvas's keys ask Overview to do.
enum OverviewCommand: Equatable {
    case bulk(OverviewBulkAction)
    /// Step the monitor scope left (-1) or right (1).
    case monitor(Int)
    case search
}

enum OverviewBulkAction: Hashable {
    case tile
    case distribute
    case arrange([Int])

    var verb: String {
        switch self {
        case .tile: return "Tile"
        case .distribute: return "Distribute"
        case .arrange: return "Arrange"
        }
    }
}

/// What a bulk action will act on, per monitor, and what it leaves out.
struct OverviewBulkPlan: Equatable {
    struct Group: Equatable {
        let display: Int
        let displayId: UInt32
        let windows: [OverviewRow]
    }

    let action: OverviewBulkAction
    /// One group per monitor, each acted on in place on that monitor.
    let groups: [Group]
    /// Selected windows left out, with why. They stay selected.
    let excluded: [(wid: UInt32, reason: Exclusion)]

    var eligibleCount: Int { groups.reduce(0) { $0 + $1.windows.count } }
    var isEnabled: Bool { eligibleCount > 0 }

    /// "Tile 2 here · 1 on Desktop 3 excluded".
    var label: String {
        var text = "\(action.verb) \(eligibleCount) here"
        if !excluded.isEmpty { text += " · \(excludedSummary) excluded" }
        return text
    }

    /// "1 on Desktop 3, 1 parked", in first-seen order.
    var excludedSummary: String {
        var order: [Exclusion] = []
        var counts: [Exclusion: Int] = [:]
        for item in excluded {
            if counts[item.reason] == nil { order.append(item.reason) }
            counts[item.reason, default: 0] += 1
        }
        return order.map { "\(counts[$0]!) \($0.label)" }.joined(separator: ", ")
    }

    static func == (a: Self, b: Self) -> Bool {
        a.action == b.action && a.groups == b.groups
            && a.excluded.map(\.wid) == b.excluded.map(\.wid)
            && a.excluded.map(\.reason) == b.excluded.map(\.reason)
    }
}

struct OverviewProjection: Equatable {
    struct Inputs {
        var windows: [WindowEntry]
        var layers: [LayerOverview] = []
        var displays: [OverviewDisplay]
        /// The main display's CG bounds, where the stage parks windows.
        var main: CGRect
        /// Parked windows' saved home frames, from `LayerStage.homes()`.
        var homes: [UInt32: CGRect] = [:]
        var tucked: [String: Set<UInt32>] = [:]
        var extras: [String: Set<UInt32>] = [:]
        /// Full OCR text by window, for search.
        var ocrText: [UInt32: String] = [:]
        var appType: (String) -> AppType = { AppTypeClassifier.classify($0) }
    }

    /// Every matched row, in-scope groups first.
    let groups: [OverviewRowGroup]
    let canvas: [OverviewCanvasItem]
    let counts: OverviewCounts
    /// Selected windows not in the scoped list, with why.
    let outOfScopeSelection: [(wid: UInt32, reason: Exclusion)]
    /// Every known window by id, matched or not, for actions on the selection.
    let all: [UInt32: OverviewRow]
    let displays: [OverviewDisplay]
    /// Every monitor and Space, empty ones too, with the matched rows on
    /// each. Scope marks what's in it; it never hides the structure.
    var desk: [OverviewDeskMonitor] = []
    /// Matched rows no monitor holds: minimized, closed or unplaceable.
    var unplaced: [OverviewRow] = []

    /// Every matched row, in the desk's order: monitor by monitor, Space by
    /// Space, then the unplaced ones.
    var rows: [OverviewRow] {
        desk.flatMap { $0.spaces.flatMap(\.rows) } + unplaced
    }
    var inScopeRows: [OverviewRow] { rows.filter(\.inScope) }

    static func == (a: Self, b: Self) -> Bool {
        // `all` and `displays` too: actions read them for windows the
        // filters hide, whose state can change while the list doesn't.
        a.groups == b.groups && a.desk == b.desk && a.unplaced == b.unplaced
            && a.canvas == b.canvas && a.counts == b.counts
            && a.all == b.all && a.displays == b.displays
            && a.outOfScopeSelection.map(\.wid) == b.outOfScopeSelection.map(\.wid)
            && a.outOfScopeSelection.map(\.reason) == b.outOfScopeSelection.map(\.reason)
    }

    static let empty = OverviewProjection(
        groups: [], canvas: [], counts: OverviewCounts(), outOfScopeSelection: [], all: [:], displays: []
    )
}

extension OverviewProjection {
    static func make(_ inputs: Inputs, scope: OverviewScope, selection: Set<UInt32>) -> OverviewProjection {
        let layerOf = layerIndex(inputs.layers)
        var all: [UInt32: OverviewRow] = [:]
        var hiders: [UInt32: Set<Exclusion>] = [:]
        var order: [UInt32] = []

        for entry in inputs.windows {
            let role = scope.layerId.flatMap { roleIn(layer: $0, wid: entry.wid, inputs: inputs, layerOf: layerOf) }
            let row = makeRow(entry, inputs: inputs, scope: scope, layerOf: layerOf, role: role)
            all[entry.wid] = row
            order.append(entry.wid)
            hiders[entry.wid] = filters(hiding: entry, row: row, scope: scope, inputs: inputs)
        }

        let matched = order.compactMap { all[$0] }.filter { hiders[$0.wid]?.isEmpty ?? true }

        // Rows: in-scope groups first, then elsewhere, then unknown.
        var groupOrder: [String] = []
        var grouped: [String: (title: String, inScope: Bool, rank: Int, rows: [OverviewRow])] = [:]
        for row in matched {
            let (key, title, rank) = groupKey(row, displays: inputs.displays)
            if grouped[key] == nil {
                groupOrder.append(key)
                grouped[key] = (title, row.inScope, rank, [])
            }
            grouped[key]?.rows.append(row)
        }
        let groups = groupOrder
            .map { key in (key, grouped[key]!) }
            .sorted { a, b in
                let ka = (a.1.inScope ? 0 : 1, a.1.rank), kb = (b.1.inScope ? 0 : 1, b.1.rank)
                return ka < kb
            }
            .map { key, value in OverviewRowGroup(id: key, title: value.title, inScope: value.inScope, rows: value.rows) }

        let canvas = matched
            .filter { $0.inScope && $0.state != .unknown }
            .compactMap { row -> OverviewCanvasItem? in
                guard let frame = row.frame else { return nil }
                return OverviewCanvasItem(
                    wid: row.wid, app: row.app, title: row.title,
                    frame: frame, position: row.position, state: row.state
                )
            }

        var counts = OverviewCounts()
        counts.located = scope.isLocated
        counts.matched = matched.filter { $0.state != .unknown }.count
        counts.inScope = matched.filter { $0.state != .unknown && $0.inScope }.count
        counts.onCanvas = canvas.count
        counts.unknown = matched.filter { $0.state == .unknown }.count

        let listed = Set(matched.filter(\.inScope).map(\.wid))
        let outside: [(wid: UInt32, reason: Exclusion)] = selection.sorted().compactMap { wid in
            guard !listed.contains(wid) else { return nil }
            guard let row = all[wid] else { return (wid, .gone) }
            if let hider = hiders[wid].flatMap(firstHider) { return (wid, hider) }
            return (wid, locationExclusion(row, scope: scope))
        }

        let (desk, unplaced) = deskLayout(matched, displays: inputs.displays, scope: scope)

        return OverviewProjection(
            groups: groups, canvas: canvas, counts: counts,
            outOfScopeSelection: outside, all: all, displays: inputs.displays,
            desk: desk, unplaced: unplaced
        )
    }

    /// Lays `rows` out on their monitors and Spaces. Every desktop of every
    /// monitor appears, empty or not; a full-screen Space only when it's
    /// showing or holds a row. A row whose Space its monitor doesn't own
    /// goes with the unplaced ones.
    static func deskLayout(
        _ rows: [OverviewRow], displays: [OverviewDisplay], scope: OverviewScope
    ) -> ([OverviewDeskMonitor], [OverviewRow]) {
        var bySpace: [String: [OverviewRow]] = [:]
        var unplaced: [OverviewRow] = []
        for row in rows {
            guard row.state != .unknown, let index = row.display, let spaceId = row.spaceId,
                  let display = displays.first(where: { $0.index == index }), display.owns(spaceId) else {
                unplaced.append(row)
                continue
            }
            bySpace["\(index)-\(spaceId)", default: []].append(row)
        }
        let ordered = displays.sorted { ($0.bounds.minX, $0.bounds.minY) < ($1.bounds.minX, $1.bounds.minY) }
        let desk = ordered.map { display -> OverviewDeskMonitor in
            let monitorInScope = scope.display == nil || scope.display == display.index
            let fullScreen = display.spaceIds.filter { !display.desktops.contains($0) }
            let spaceIds = display.desktops + fullScreen.filter { id in
                id == display.currentSpaceId || bySpace["\(display.index)-\(id)"] != nil
            }
            let spaces = spaceIds.map { id in
                OverviewDeskSpace(
                    spaceId: id,
                    desktop: display.desktopNumber(of: id),
                    isCurrent: id == display.currentSpaceId,
                    inScope: monitorInScope && (scope.spaceId == nil || scope.spaceId == id),
                    rows: bySpace["\(display.index)-\(id)"] ?? []
                )
            }
            return OverviewDeskMonitor(display: display, inScope: monitorInScope, spaces: spaces)
        }
        return (desk, unplaced)
    }

    /// The scope that shows `wid`: its monitor and Space, with any search,
    /// preset or layer filter that hides it cleared. Filters that already
    /// include it stay. Nil when the window isn't known.
    static func scope(showing wid: UInt32, from scope: OverviewScope, inputs: Inputs) -> OverviewScope? {
        guard let entry = inputs.windows.first(where: { $0.wid == wid }) else { return nil }
        let layerOf = layerIndex(inputs.layers)
        var next = scope
        let role = scope.layerId.flatMap { roleIn(layer: $0, wid: wid, inputs: inputs, layerOf: layerOf) }
        let row = makeRow(entry, inputs: inputs, scope: scope, layerOf: layerOf, role: role)
        let hiding = filters(hiding: entry, row: row, scope: scope, inputs: inputs)
        if hiding.contains(.search) { next.search = "" }
        if hiding.contains(.preset) { next.preset = nil }
        if hiding.contains(.outsideLayer) { next.layerId = nil }
        next.display = row.display
        next.spaceId = row.spaceId
        return next
    }

    /// What `action` does to the selection: per monitor, the windows on the
    /// Space that monitor is showing. Everything else stays selected and is
    /// listed with its reason. It never switches a Space or carries a window.
    func bulk(_ action: OverviewBulkAction, selection: Set<UInt32>) -> OverviewBulkPlan {
        var byDisplay: [Int: [OverviewRow]] = [:]
        var excluded: [(wid: UInt32, reason: Exclusion)] = []
        for wid in orderedSelection(selection) {
            guard let row = all[wid] else { excluded.append((wid, .gone)); continue }
            if let reason = Self.bulkExclusion(row) { excluded.append((wid, reason)); continue }
            guard let display = row.display else { excluded.append((wid, .unknown)); continue }
            byDisplay[display, default: []].append(row)
        }
        let groups = byDisplay.keys.sorted().map { index in
            OverviewBulkPlan.Group(
                display: index,
                displayId: displays.first { $0.index == index }?.displayId ?? 0,
                windows: byDisplay[index]!
            )
        }
        return OverviewBulkPlan(action: action, groups: groups, excluded: excluded)
    }

    /// The selection in row order, then any ids the rows don't hold.
    private func orderedSelection(_ selection: Set<UInt32>) -> [UInt32] {
        let listed = rows.map(\.wid).filter(selection.contains)
        let rest = selection.subtracting(listed).sorted()
        return listed + rest
    }

    static func bulkExclusion(_ row: OverviewRow) -> Exclusion? {
        switch row.state {
        case .showing: return nil
        case .otherSpace(let number): return .otherSpace(desktop: number)
        case .fullScreen: return .fullScreen
        case .appHidden: return .appHidden
        case .parked: return .parked
        case .unknown: return .unknown
        }
    }

    // MARK: Direct actions

    /// Why one window can't be tiled in place: as bulk, only a window on its
    /// monitor's current desktop.
    func placeExclusion(_ wid: UInt32) -> Exclusion? {
        guard let row = all[wid] else { return .gone }
        if let reason = Self.bulkExclusion(row) { return reason }
        return row.display == nil ? .unknown : nil
    }

    /// Why one window can't be carried to another desktop. Showing and
    /// other-desktop windows on a known monitor can; full screen, hidden,
    /// parked and unknown windows can't.
    static func moveExclusion(_ row: OverviewRow) -> Exclusion? {
        switch row.state {
        case .showing, .otherSpace:
            return row.display == nil || row.spaceId == nil ? .unknown : nil
        case .fullScreen: return .fullScreen
        case .appHidden: return .appHidden
        case .parked: return .parked
        case .unknown: return .unknown
        }
    }

    /// The desktops one window can be carried to: the other desktops of its
    /// own monitor. Empty when it can't move.
    func moveTargets(for wid: UInt32) -> [(spaceId: Int, desktop: Int)] {
        guard let row = all[wid], Self.moveExclusion(row) == nil,
              let display = displays.first(where: { $0.index == row.display }) else { return [] }
        return display.desktops.enumerated().compactMap { offset, space in
            space == row.spaceId ? nil : (space, offset + 1)
        }
    }

    /// Where a window is, in a few words: its monitor and Space, and what
    /// keeps it from showing.
    func location(of row: OverviewRow) -> String {
        if row.state == .unknown { return "Minimized or closed" }
        let display = displays.first { $0.index == row.display }
        var parts: [String] = []
        if displays.count > 1, let display { parts.append(display.name) }
        if let display, let spaceId = row.spaceId {
            parts.append(display.desktopNumber(of: spaceId).map { "Desktop \($0)" } ?? "Full screen")
        }
        switch row.state {
        case .parked: parts.append("parked")
        case .appHidden: parts.append("app hidden")
        default: break
        }
        return parts.isEmpty ? row.state.label : parts.joined(separator: " · ")
    }

    func displayId(of row: OverviewRow) -> UInt32? {
        displays.first { $0.index == row.display }.map(\.displayId)
    }
}

// MARK: - Building blocks

private extension OverviewProjection {
    /// Layer id → (member window ids, tier by window).
    static func layerIndex(_ layers: [LayerOverview]) -> [String: Set<UInt32>] {
        var index: [String: Set<UInt32>] = [:]
        for layer in layers {
            var ids = Set(layer.windows.map(\.wid))
            for entry in layer.entries { ids.formUnion(entry.unknown.map(\.wid)) }
            index[layer.id] = ids
        }
        return index
    }

    static func roleIn(layer: String, wid: UInt32, inputs: Inputs, layerOf: [String: Set<UInt32>]) -> OverviewRole? {
        if inputs.tucked[layer]?.contains(wid) == true { return .tucked }
        if layerOf[layer]?.contains(wid) == true { return .member }
        // As `LayerStage.want`: a scene extra counts only while no layer
        // claims it. One another layer took since stays that layer's.
        guard inputs.extras[layer]?.contains(wid) == true else { return nil }
        if layerOf.values.contains(where: { $0.contains(wid) }) { return nil }
        if inputs.tucked.values.contains(where: { $0.contains(wid) }) { return nil }
        return .unclaimed
    }

    static func tier(of wid: UInt32, in layers: [LayerOverview]) -> LayerMembership.Tier? {
        for layer in layers {
            for entry in layer.entries {
                if let window = entry.windows.first(where: { $0.wid == wid }) { return window.tier }
                if let window = entry.unknown.first(where: { $0.wid == wid }) { return window.tier }
            }
        }
        return nil
    }

    static func makeRow(
        _ entry: WindowEntry, inputs: Inputs, scope: OverviewScope,
        layerOf: [String: Set<UInt32>], role: OverviewRole?
    ) -> OverviewRow {
        let frame = CGRect(x: entry.frame.x, y: entry.frame.y, width: entry.frame.w, height: entry.frame.h)
        let usable = frame.width > 1 && frame.height > 1
        let home = inputs.homes[entry.wid].flatMap { $0.width > 1 && $0.height > 1 ? $0 : nil }
        let parked = usable && LayerOverview.isParked(frame, main: inputs.main)
        let (display, spaceId) = locate(entry, frame: parked ? home : (usable ? frame : nil), displays: inputs.displays)

        // Spaces first. A hidden app's windows keep their Space, so a window
        // with none is unconfirmed (minimized or closed) whether or not its
        // app is hidden. This differs on purpose from `LayerOverview.spot`,
        // which counts it as hidden; that baseline, the preview's and
        // `layers.members` counts, is left as it is. A parked window stays
        // parked when its app hides too. A full-screen Space is never
        // "showing", even when its monitor is on it.
        let state: OverviewWindowState
        if entry.spaceIds.isEmpty {
            state = .unknown
        } else if parked {
            state = .parked
        } else if let display, let spaceId, !display.desktops.contains(spaceId), display.owns(spaceId) {
            state = .fullScreen
        } else if entry.appHidden {
            state = .appHidden
        } else if let display, let spaceId, display.currentSpaceId == spaceId {
            state = .showing
        } else {
            state = .otherSpace(desktop: display.flatMap { d in spaceId.flatMap(d.desktopNumber(of:)) })
        }

        let position: PositionSource
        let shown: CGRect?
        switch state {
        case .showing:
            position = usable ? .live : .none("No usable frame")
            shown = usable ? frame : nil
        case .parked:
            if let home {
                position = .savedHome
                shown = home
            } else {
                position = .none("Parked, no saved home")
                shown = nil
            }
        case .unknown:
            position = .none("Minimized or closed")
            shown = nil
        case .fullScreen:
            position = .none("Full screen")
            shown = nil
        case .otherSpace, .appHidden:
            position = usable ? .lastKnown : .none("No known position")
            shown = usable ? frame : nil
        }

        let layerIds = inputs.layers.compactMap { layerOf[$0.id]?.contains(entry.wid) == true ? $0.id : nil }
        var inScope = true
        if let wanted = scope.display, display?.index != wanted { inScope = false }
        if let wanted = scope.spaceId, spaceId != wanted, !entry.spaceIds.contains(wanted) { inScope = false }

        return OverviewRow(
            wid: entry.wid, pid: entry.pid, app: entry.app,
            title: (entry.fullTitle?.isEmpty == false ? entry.fullTitle : nil) ?? entry.title,
            display: display?.index, spaceId: entry.spaceIds.isEmpty ? nil : spaceId, state: state,
            frame: shown, position: position, layerIds: layerIds,
            tier: tier(of: entry.wid, in: inputs.layers), role: role, inScope: inScope
        )
    }

    /// The monitor and Space a window is on. A window on several Spaces
    /// (sticky, or on more than one monitor's) goes to the monitor its
    /// geometry is on, `frame` being its live or saved-home frame, then to
    /// that monitor's current Space when it's one of them.
    static func locate(_ entry: WindowEntry, frame: CGRect?, displays: [OverviewDisplay]) -> (OverviewDisplay?, Int?) {
        guard !entry.spaceIds.isEmpty else { return (nil, nil) }
        let owners = displays.filter { d in entry.spaceIds.contains(where: d.owns) }
        let byGeometry = frame.flatMap { displayContaining($0, in: displays) }
        let display: OverviewDisplay?
        if let byGeometry, owners.isEmpty || owners.contains(byGeometry) {
            display = byGeometry
        } else {
            display = owners.first ?? byGeometry
        }
        guard let display else { return (nil, entry.spaceIds.first) }
        if entry.spaceIds.contains(display.currentSpaceId) { return (display, display.currentSpaceId) }
        return (display, entry.spaceIds.first(where: display.owns) ?? entry.spaceIds.first)
    }

    static func displayContaining(_ frame: CGRect, in displays: [OverviewDisplay]) -> OverviewDisplay? {
        let mid = CGPoint(x: frame.midX, y: frame.midY)
        return displays.first { $0.bounds.contains(mid) }
    }

    /// The search, preset and layer filters that hide `entry`.
    static func filters(hiding entry: WindowEntry, row: OverviewRow, scope: OverviewScope, inputs: Inputs) -> Set<Exclusion> {
        var hiding: Set<Exclusion> = []
        let query = scope.search.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            let hit = entry.app.localizedCaseInsensitiveContains(query)
                || entry.titleContains(query)
                || (entry.latticesSession?.localizedCaseInsensitiveContains(query) ?? false)
                || (inputs.ocrText[entry.wid]?.localizedCaseInsensitiveContains(query) ?? false)
            if !hit { hiding.insert(.search) }
        }
        if let preset = scope.filterPreset, preset != .all {
            let passes: Bool
            switch preset {
            case .lattices: passes = entry.latticesSession != nil
            case .currentSpace: passes = row.state == .showing
            default: passes = preset.appTypes?.contains(inputs.appType(entry.app)) ?? true
            }
            if !passes { hiding.insert(.preset) }
        }
        if scope.layerId != nil, row.role == nil { hiding.insert(.outsideLayer) }
        return hiding
    }

    static func firstHider(_ hiding: Set<Exclusion>) -> Exclusion? {
        [Exclusion.search, .preset, .outsideLayer].first(where: hiding.contains)
    }

    static func locationExclusion(_ row: OverviewRow, scope: OverviewScope) -> Exclusion {
        if row.state == .unknown { return .unknown }
        if let wanted = scope.display, row.display != wanted { return .outsideMonitor }
        return .outsideSpace
    }

    static func groupKey(_ row: OverviewRow, displays: [OverviewDisplay]) -> (String, String, Int) {
        guard row.state != .unknown, let index = row.display else {
            return ("unknown", "Minimized or closed", Int.max)
        }
        let display = displays.first { $0.index == index }
        let monitor = display?.name ?? "Display \(index + 1)"
        guard let spaceId = row.spaceId else { return ("d\(index)", monitor, index * 1000) }
        let number = display?.desktopNumber(of: spaceId)
        let space = number.map { "Desktop \($0)" } ?? "Full screen"
        let showing = display?.currentSpaceId == spaceId ? " · showing" : ""
        return ("d\(index)-s\(spaceId)", "\(monitor) · \(space)\(showing)", index * 1000 + (number ?? 999))
    }
}
