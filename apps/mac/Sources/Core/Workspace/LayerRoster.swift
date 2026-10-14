import AppKit

/// A layer's apps, as the layer bezel lists them under its name: one per app,
/// in entry order, with where its windows are when that isn't the desktop the
/// main display is showing, the one a switch stages and lays out. Placing a
/// window is pure, so it's tested without windows.
enum LayerRoster {
    struct App: Equatable {
        let name: String
        /// A process to take the icon from, when the app is running.
        let pid: Int32?
        /// Where its nearest window is (`LayerOverview.Spot`): on a desktop,
        /// parked in the stage's corner, or its app hidden.
        let spot: LayerOverview.Spot
        /// Kept put away in the layer (`LayerStage.tucked`).
        var tucked = false
        /// Not an entry's: a window the layer had showing when it was last
        /// left (`LayerStage.scene`), which a switch to it shows again.
        var extra = false
        /// Not the layer's: a window the switch parked that its app kept on
        /// screen (`LayerStage.Outcome.stayed`).
        var stayed = false

        init(name: String, pid: Int32?, spot: LayerOverview.Spot, tucked: Bool = false, extra: Bool = false, stayed: Bool = false) {
            self.name = name
            self.pid = pid
            self.spot = spot
            self.tucked = tucked
            self.extra = extra
            self.stayed = stayed
        }

        init(name: String, pid: Int32?, place: Place) {
            self.init(name: name, pid: pid, spot: .at(place))
        }

        /// Its desktop, nil when it's parked or its app is hidden.
        var place: Place? {
            if case .at(let place) = spot { return place }
            return nil
        }

        /// What the bezel writes beside it, nil when it's here.
        var note: String? {
            if stayed { return "Stayed" }
            return tucked && !spot.isShowing ? "Put away" : spot.note
        }
    }

    enum Place: Equatable {
        /// On the desktop the main display is showing.
        case here
        /// On another desktop of the main display, numbered as Mission
        /// Control labels it.
        case desktop(Int)
        /// On another display: on the desktop it's showing when `desktop` is
        /// nil.
        case display(Side, desktop: Int?)
        case fullScreen
        /// The app is running, but no window matches the entry.
        case noWindow
        /// Nothing matches the entry.
        case notOpen

        /// What the bezel writes beside the app, nil when it's here.
        var note: String? {
            switch self {
            case .here: return nil
            case .desktop(let number): return "Desktop \(number)"
            case .display(let side, nil): return "\(side.rawValue.capitalized) display"
            case .display(let side, let number?): return "Desktop \(number), \(side.rawValue)"
            case .fullScreen: return "Full screen"
            case .noWindow: return "No window"
            case .notOpen: return "Not open"
            }
        }

        /// Nearest first. An app with windows in several places lists the
        /// nearest.
        var rank: Int {
            switch self {
            case .here: return 0
            case .display(_, nil): return 1
            case .desktop: return 2
            case .fullScreen: return 3
            case .display: return 4
            case .noWindow, .notOpen: return 5
            }
        }
    }

    enum Side: String {
        case left, right, above, below
        case other
    }

    /// Where a window on `spaceIds` is, with `displays` from
    /// `WindowTiler.getDisplaySpaces()`, `main` the main display's id among
    /// them, and `sides` where the others sit. Nil when Spaces can't say: a
    /// window with no Space is closed but kept, or minimized.
    static func place(of spaceIds: [Int], in displays: [DisplaySpaces], main: String, sides: [String: Side]) -> Place? {
        let ids = Set(spaceIds)
        guard !ids.isEmpty else { return nil }
        // Showing desktops first: a window on every desktop is here.
        if let display = displays.first(where: { $0.displayId == main }), ids.contains(display.currentSpaceId) {
            return .here
        }
        for display in displays where display.displayId != main && ids.contains(display.currentSpaceId) {
            return .display(sides[display.displayId] ?? .other, desktop: nil)
        }
        for display in displays {
            if let space = display.spaces.first(where: { ids.contains($0.id) }) {
                return display.displayId == main
                    ? .desktop(space.index)
                    : .display(sides[display.displayId] ?? .other, desktop: space.index)
            }
            if display.orderedSpaceIds.contains(where: ids.contains) { return .fullScreen }
        }
        return nil
    }

    /// Where `display` sits beside `main`, both CG bounds.
    static func side(of display: CGRect, from main: CGRect) -> Side {
        if display.maxX <= main.minX { return .left }
        if display.minX >= main.maxX { return .right }
        return display.midY < main.midY ? .above : .below
    }

    /// The displays as `place(of:in:main:sides:)` reads them, gathered once
    /// for a batch of windows.
    struct Context {
        let displays: [DisplaySpaces]
        let main: String
        let sides: [String: Side]

        static func current() -> Context {
            let displays = WindowTiler.getDisplaySpaces()
            let mainID = CGMainDisplayID()
            return Context(
                displays: displays,
                main: WindowTiler.displaySpaces(forDisplayID: mainID, in: displays)?.displayId ?? "",
                sides: LayerRoster.sides(of: displays, from: mainID)
            )
        }

        func place(of spaceIds: [Int]) -> Place? {
            LayerRoster.place(of: spaceIds, in: displays, main: main, sides: sides)
        }
    }

    /// Where each display but the main one sits, by its Spaces id.
    private static func sides(of displays: [DisplaySpaces], from main: CGDirectDisplayID) -> [String: Side] {
        var count: UInt32 = 0
        guard displays.count > 1, CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [:] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [:] }
        var sides: [String: Side] = [:]
        for id in ids.prefix(Int(count)) where id != main {
            guard let display = WindowTiler.displaySpaces(forDisplayID: id, in: displays) else { continue }
            sides[display.displayId] = side(of: CGDisplayBounds(id), from: CGDisplayBounds(main))
        }
        return sides
    }

    /// The layer's apps from the windows it holds, `members`: one per app,
    /// in entry order, at the nearest spot any of its windows is, then the
    /// apps of `extras`, the windows it had showing beyond them. `place`
    /// reads a window's Spaces and `spot` where it is from that; a window
    /// with no spot is left out. `tucked` are the members it keeps put away.
    /// `missing` names what an entry holding no window with a spot points at.
    /// Last come the apps of `stayed`, windows of other layers the switch
    /// couldn't put away, one row per app and never merged into the layer's.
    static func apps(
        of layer: Layer,
        members: [LayerMembership.Member],
        place: ([Int]) -> Place?,
        missing: (LayerProject) -> App?,
        spot: (WindowEntry, Place?) -> LayerOverview.Spot? = { _, place in place.map { LayerOverview.Spot.at($0) } },
        tucked: Set<UInt32> = [],
        extras: [WindowEntry] = [],
        stayed: [WindowEntry] = []
    ) -> [App] {
        var apps: [App] = []
        func add(_ app: App) {
            guard let i = apps.firstIndex(where: { $0.name.caseInsensitiveCompare(app.name) == .orderedSame }) else {
                apps.append(app)
                return
            }
            var row = apps[i]
            if rank(of: app.spot) < rank(of: row.spot) {
                row = App(name: row.name, pid: row.pid ?? app.pid, spot: app.spot, tucked: app.tucked, extra: row.extra)
            }
            row.extra = row.extra && app.extra
            apps[i] = row
        }
        for (index, project) in layer.projects.enumerated() {
            var held = false
            for member in members where member.project == index {
                let entry = member.entry
                guard let at = spot(entry, place(entry.spaceIds)) else { continue }
                held = true
                add(App(name: entry.app, pid: entry.pid, spot: at, tucked: tucked.contains(entry.wid)))
            }
            if !held, let app = missing(project) {
                add(app)
            }
        }
        for entry in extras {
            guard let at = spot(entry, place(entry.spaceIds)) else { continue }
            add(App(name: entry.app, pid: entry.pid, spot: at, extra: true))
        }
        var others: [App] = []
        for entry in stayed {
            guard !others.contains(where: { $0.name.caseInsensitiveCompare(entry.app) == .orderedSame }) else { continue }
            others.append(App(name: entry.app, pid: entry.pid, spot: spot(entry, place(entry.spaceIds)) ?? .at(.here), stayed: true))
        }
        return apps + others
    }

    /// Nearest first, in `Place.rank`'s order. A window parked on the
    /// showing desktop, or whose app is hidden, is one step from here: after
    /// the showing desktops, before the other ones.
    static func rank(of spot: LayerOverview.Spot) -> Int {
        switch spot {
        case .at(let place): return place.rank * 2
        case .parked(nil), .hidden: return 3
        case .parked: return 5
        }
    }

    /// Where a window is once `outcome` has landed: what the stage just did
    /// wins over the inventory, which an app's hide reaches only later.
    /// Otherwise as `LayerOverview.spot` reads it, `main` being the main
    /// display's bounds.
    static func spot(
        of entry: WindowEntry,
        place: Place?,
        main: CGRect,
        outcome: LayerStage.Outcome? = nil
    ) -> LayerOverview.Spot? {
        if let outcome {
            if outcome.hidden.contains(entry.wid) { return .hidden }
            if outcome.parked.contains(entry.wid) || outcome.missing.contains(entry.wid) { return .parked(desktop: nil) }
            if outcome.shown.contains(entry.wid) { return .at(.here) }
        }
        let frame = CGRect(x: entry.frame.x, y: entry.frame.y, width: entry.frame.w, height: entry.frame.h)
        return LayerOverview.spot(place: place, frame: frame, appHidden: entry.appHidden, main: main)
    }

    /// The app's icon: its process's, else an app of that name in the usual
    /// folders.
    static func icon(for app: App) -> NSImage? {
        if let pid = app.pid, let icon = NSRunningApplication(processIdentifier: pid)?.icon {
            return icon
        }
        let folders = ["/Applications", "/System/Applications", "/Applications/Utilities", NSHomeDirectory() + "/Applications"]
        for folder in folders {
            let path = "\(folder)/\(app.name).app"
            if FileManager.default.fileExists(atPath: path) { return NSWorkspace.shared.icon(forFile: path) }
        }
        return nil
    }
}

extension WorkspaceManager {
    /// Shows the layer bezel on layer `index` of `layers`, listing its apps
    /// from `windows`, and after a switch from what its stage did (`outcome`).
    /// `edge` is a step off the pad's edge: the lit slot bumps that way and
    /// the bezel goes sooner.
    func showBezel(
        for index: Int,
        in layers: [Layer],
        windows: [WindowEntry]? = nil,
        outcome: LayerStage.Outcome? = nil,
        edge: LayerSlots.Direction? = nil
    ) {
        let layer = layers[index]
        let apps = roster(of: layer, in: windows ?? DesktopModel.shared.allWindows(), outcome: outcome)
        LayerBezel.shared.show(label: layer.label, index: index, total: layers.count, apps: apps, edge: edge)
    }

    /// The layer's apps for the bezel (`LayerRoster`): the windows it holds
    /// in `windows`, then the ones it had showing beyond them when it was
    /// last left (`LayerStage.scene`) that no layer holds, each where it is
    /// once `outcome` has landed, then the windows the stage couldn't put
    /// away (`outcome.stayed`). The members it keeps put away are marked.
    func roster(of layer: Layer, in windows: [WindowEntry], outcome: LayerStage.Outcome? = nil) -> [LayerRoster.App] {
        let context = LayerRoster.Context.current()
        let running = NSWorkspace.shared.runningApplications
        let main = CGDisplayBounds(CGMainDisplayID())
        let resolution = layerMembership(in: windows)
        let members = resolution.ids.contains(layer.id)
            ? resolution.members(of: layer.id)
            : memberWindows(of: layer, in: windows)
        let byWid = Dictionary(windows.map { ($0.wid, $0) }, uniquingKeysWith: { first, _ in first })
        let extras = LayerStage.shared.scene(for: layer).compactMap { wid -> WindowEntry? in
            resolution.owners[wid] == nil ? byWid[wid] : nil
        }
        let listed = Set(members.map { $0.entry.wid }).union(extras.map(\.wid))
        let stayed = (outcome?.stayed ?? []).sorted().compactMap { wid -> WindowEntry? in
            listed.contains(wid) ? nil : byWid[wid]
        }
        return LayerRoster.apps(
            of: layer,
            members: members,
            place: context.place(of:),
            missing: { self.missingApp(for: $0, running: running) },
            spot: { LayerRoster.spot(of: $0, place: $1, main: main, outcome: outcome) },
            tucked: LayerStage.shared.tucked(layer.id),
            extras: extras,
            stayed: stayed
        )
    }

    /// What an entry names when no window matches it: `.noWindow` when that
    /// app is running, `.notOpen` when it isn't. Named as the running app, so
    /// it shares a row with the app's windows from other entries.
    func missingApp(for project: LayerProject, running: [NSRunningApplication]) -> LayerRoster.App? {
        guard let name = project.app ?? project.launch
                ?? project.group.flatMap({ group(byId: $0)?.label })
                ?? project.path.map({ ($0 as NSString).lastPathComponent }) else { return nil }
        let app = project.group == nil && project.path == nil
            ? running.first { $0.localizedName?.localizedCaseInsensitiveContains(name) == true }
            : nil
        return LayerRoster.App(name: app?.localizedName ?? name, pid: app?.processIdentifier, place: app == nil ? .notOpen : .noWindow)
    }

}
