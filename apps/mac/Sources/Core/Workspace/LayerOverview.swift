import AppKit
import Combine

/// A ⌘⌥ layer as Studio lists it: each of its entries with the windows it
/// matched, and where each window is. That's its desktop (`LayerRoster`),
/// unless the layer stage parked it in the main display's corner or hid its
/// app. Telling those apart is pure, so it's tested without windows.
struct LayerOverview: Identifiable, Equatable {
    enum Spot: Equatable {
        case at(LayerRoster.Place)
        /// Hanging off the main display's bottom-right corner, where a switch
        /// parks it; on a desktop that isn't showing when `desktop` is set.
        case parked(desktop: Int?)
        /// Its app is hidden.
        case hidden

        /// What Studio writes beside the window, nil when it's here.
        var note: String? {
            switch self {
            case .at(let place): return place.note
            case .parked(nil): return "Parked"
            case .parked(let desktop?): return "Parked, Desktop \(desktop)"
            case .hidden: return "Hidden"
            }
        }

        /// On a desktop a display is showing, where it can be seen.
        var isShowing: Bool {
            switch self {
            case .at(.here), .at(.display(_, nil)): return true
            default: return false
            }
        }
    }

    struct Window: Identifiable, Equatable {
        let wid: UInt32
        let app: String
        let title: String
        let spot: Spot
        var id: UInt32 { wid }
    }

    struct Entry: Identifiable, Equatable {
        /// Its index in the layer's `projects`.
        let index: Int
        /// The app, tab group or project it matches.
        let name: String
        /// The title it looks for, if it looks for one.
        let pattern: String?
        let windows: [Window]
        /// Why nothing matched (`.noWindow`, `.notOpen`), nil when something did.
        let missing: LayerRoster.Place?
        var id: Int { index }
    }

    /// The layer's index in the config's layers, which `focusLayer` takes.
    let index: Int
    let id: String
    let label: String
    let layout: String?
    /// The layer ⌘⌥ last switched to.
    let isActive: Bool
    let entries: [Entry]

    /// Where the layer sits on the ⌘⌥ pad.
    var slot: Int? { LayerSlots.slot(forIndex: index) }
    var windows: [Window] { entries.flatMap(\.windows) }
    var showingIds: Set<UInt32> { Set(windows.filter(\.spot.isShowing).map(\.wid)) }

    /// How Studio's layer scope names a ⌘⌥ layer, beside its saved layers.
    static func scopeId(for layerId: String) -> String { "workspace-layer:\(layerId)" }

    static func layerId(fromScope scopeId: String) -> String? {
        let prefix = "workspace-layer:"
        return scopeId.hasPrefix(prefix) ? String(scopeId.dropFirst(prefix.count)) : nil
    }

    /// Where a window is: `place` from its Spaces, `frame` in CG coordinates,
    /// and `main` the main display's bounds, where the stage parks windows.
    static func spot(place: LayerRoster.Place, frame: CGRect, appHidden: Bool, main: CGRect) -> Spot {
        if appHidden { return .hidden }
        guard isParked(frame, main: main) else { return .at(place) }
        switch place {
        case .here: return .parked(desktop: nil)
        case .desktop(let number): return .parked(desktop: number)
        default: return .at(place)
        }
    }

    /// In the corner the stage parks windows in. The stage moves them to one
    /// point in from it and macOS clamps them back a little, so it allows
    /// the same 40 points `LayerStage` does.
    static func isParked(_ frame: CGRect, main: CGRect) -> Bool {
        frame.minX >= main.maxX - 40 && frame.minX < main.maxX
            && frame.minY >= main.minY && frame.minY < main.maxY
    }
}

extension WorkspaceManager {
    /// Every ⌘⌥ layer's overview, from `windows`.
    func overviews(in windows: [WindowEntry]) -> [LayerOverview] {
        guard let layers = config?.layers, !layers.isEmpty else { return [] }
        let context = LayerRoster.Context.current()
        let main = CGDisplayBounds(CGMainDisplayID())
        let running = NSWorkspace.shared.runningApplications
        var hidden: [Int32: Bool] = [:]
        func isHidden(_ pid: Int32) -> Bool {
            if let known = hidden[pid] { return known }
            let answer = NSRunningApplication(processIdentifier: pid)?.isHidden == true
            hidden[pid] = answer
            return answer
        }

        return layers.enumerated().map { index, layer in
            let members = listedMembers(of: layer, in: windows)
            let entries = layer.projects.enumerated().map { projectIndex, project -> LayerOverview.Entry in
                let matched = members.compactMap { member -> LayerOverview.Window? in
                    guard member.project == projectIndex, let place = context.place(of: member.entry.spaceIds) else { return nil }
                    let frame = member.entry.frame
                    return LayerOverview.Window(
                        wid: member.entry.wid,
                        app: member.entry.app,
                        title: member.entry.title,
                        spot: LayerOverview.spot(
                            place: place,
                            frame: CGRect(x: frame.x, y: frame.y, width: frame.w, height: frame.h),
                            appHidden: isHidden(member.entry.pid),
                            main: main
                        )
                    )
                }
                let name = project.app ?? project.launch
                    ?? project.group.map { group(byId: $0)?.label ?? $0 }
                    ?? project.path.map { ($0 as NSString).lastPathComponent }
                    ?? "Entry \(projectIndex + 1)"
                return LayerOverview.Entry(
                    index: projectIndex,
                    name: name,
                    pattern: project.app == nil ? nil : project.title,
                    windows: matched,
                    missing: matched.isEmpty ? missingApp(for: project, running: running)?.place : nil
                )
            }
            return LayerOverview(
                index: index, id: layer.id, label: layer.label, layout: layer.layout,
                isActive: index == activeLayerIndex, entries: entries
            )
        }
    }
}

/// Studio's ⌘⌥ layers, rebuilt as windows move while Studio is open.
final class LayerOverviewStore: ObservableObject {
    @Published private(set) var layers: [LayerOverview] = []
    private var watch: AnyCancellable?

    /// Rebuilds on each window poll, config reload and layer switch, until
    /// `stop()`.
    func start() {
        guard watch == nil else { return }
        let workspace = WorkspaceManager.shared
        // The publishers fire before the change lands; rebuild after it has.
        watch = DesktopModel.shared.$windows.map { _ in () }
            .merge(with: workspace.$config.map { _ in () }, workspace.$activeLayerIndex.map { _ in () })
            .debounce(for: .milliseconds(120), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.rebuild() }
        rebuild()
    }

    func stop() {
        watch = nil
    }

    func rebuild() {
        let fresh = WorkspaceManager.shared.overviews(in: DesktopModel.shared.allWindows())
        if fresh != layers { layers = fresh }
    }
}
