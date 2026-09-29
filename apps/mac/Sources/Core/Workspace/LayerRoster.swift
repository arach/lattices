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
        let place: Place
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
    /// Shows the layer bezel on layer `index` of `layers`, listing its apps.
    func showBezel(for index: Int, in layers: [Layer], windows: [WindowEntry]? = nil) {
        let layer = layers[index]
        let apps = roster(of: layer, in: windows ?? DesktopModel.shared.allWindows())
        LayerBezel.shared.show(label: layer.label, index: index, total: layers.count, apps: apps)
    }

    /// The layer's apps for the bezel (`LayerRoster`), placed from `windows`.
    func roster(of layer: Layer, in windows: [WindowEntry]) -> [LayerRoster.App] {
        let displays = WindowTiler.getDisplaySpaces()
        let mainID = CGMainDisplayID()
        let main = WindowTiler.displaySpaces(forDisplayID: mainID, in: displays)?.displayId ?? ""
        let sides = Self.sides(of: displays, from: mainID)
        // Windows as the stage counts them. Apps keep untitled helper
        // surfaces, and those sit on the desktop too.
        let me = getpid()
        let members = memberWindows(of: layer, in: windows).filter {
            $0.entry.axVerified && !$0.entry.title.isEmpty && $0.entry.pid != me
                && $0.entry.frame.w >= 120 && $0.entry.frame.h >= 120
        }

        var apps: [LayerRoster.App] = []
        func add(_ name: String, pid: Int32?, place: LayerRoster.Place) {
            guard let i = apps.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                apps.append(LayerRoster.App(name: name, pid: pid, place: place))
                return
            }
            if place.rank < apps[i].place.rank {
                apps[i] = LayerRoster.App(name: apps[i].name, pid: apps[i].pid ?? pid, place: place)
            }
        }
        for (index, project) in layer.projects.enumerated() {
            let matched = members.compactMap { member -> (entry: WindowEntry, place: LayerRoster.Place)? in
                guard member.project == index,
                      let place = LayerRoster.place(of: member.entry.spaceIds, in: displays, main: main, sides: sides)
                else { return nil }
                return (member.entry, place)
            }
            for member in matched {
                add(member.entry.app, pid: member.entry.pid, place: member.place)
            }
            guard matched.isEmpty, let name = project.app ?? project.launch
                    ?? project.group.flatMap({ group(byId: $0)?.label })
                    ?? project.path.map({ ($0 as NSString).lastPathComponent }) else { continue }
            // Named as the app it matches when that's running, so it shares a
            // row with the app's windows from other entries.
            let running = project.group == nil && project.path == nil
                ? NSWorkspace.shared.runningApplications.first { $0.localizedName?.localizedCaseInsensitiveContains(name) == true }
                : nil
            add(running?.localizedName ?? name, pid: running?.processIdentifier, place: running == nil ? .notOpen : .noWindow)
        }
        return apps
    }

    /// Where each display but the main one sits, by its Spaces id.
    private static func sides(of displays: [DisplaySpaces], from main: CGDirectDisplayID) -> [String: LayerRoster.Side] {
        var count: UInt32 = 0
        guard displays.count > 1, CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [:] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [:] }
        var sides: [String: LayerRoster.Side] = [:]
        for id in ids.prefix(Int(count)) where id != main {
            guard let display = WindowTiler.displaySpaces(forDisplayID: id, in: displays) else { continue }
            sides[display.displayId] = LayerRoster.side(of: CGDisplayBounds(id), from: CGDisplayBounds(main))
        }
        return sides
    }
}
