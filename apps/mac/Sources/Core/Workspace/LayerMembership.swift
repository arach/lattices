import Foundation

/// Which ⌘⌥ layer holds each window. A window belongs to one entry of one
/// layer at most: the entry with the strongest claim on it. From strongest:
/// a pin (the window's own wid, saved when it was added by hand), a `match`
/// rule, a tab group's tab, a project's session or companion windows, then
/// an app and title, a longer title before a shorter one and a bare app
/// last. A rule, tab or companion that names only an app claims as a bare
/// app. Ties go to the earlier layer, then the earlier entry. An entry saved
/// from a window (`LayerProject.isSaved`) claims by its pins alone. Only
/// content windows (`DesktopModel.isContent`) are held.
enum LayerMembership {
    typealias Member = (entry: WindowEntry, placed: Bool, project: Int)

    /// What entries point at outside the layers: tab groups by id, and a
    /// project's companion windows by path.
    struct Sources {
        var group: (String) -> TabGroup? = { _ in nil }
        var projectWindows: (String) -> [LayerProject] = { _ in [] }
        var isContent: (WindowEntry) -> Bool = DesktopModel.isContent
        /// Whether a process runs on.
        var isRunning: (Int32) -> Bool = { pid in pid > 0 && (kill(pid, 0) == 0 || errno == EPERM) }
    }

    /// The layer and entry that hold a window.
    struct Owner: Equatable {
        let layerId: String
        let project: Int
    }

    /// A pin whose window is gone, bound to a live window of the same app
    /// and title: pin `pin` of entry `project` in layer `layer`, now `wid`
    /// of process `pid`.
    struct Rebind: Equatable {
        let layer: Int
        let project: Int
        let pin: Int
        let wid: UInt32
        let pid: Int32
    }

    /// A pin whose window closed while its app ran on: pin `pin` of entry
    /// `project` in layer `layer`. It holds nothing again.
    struct Closed: Equatable {
        let layer: Int
        let project: Int
        let pin: Int
    }

    struct Resolution {
        let ids: [String]
        /// Each layer's windows, in the order the layers came: entry order,
        /// front to back within an entry. `placed` marks the ones whose
        /// entry sets its own `tile` or `display`, which a layout leaves be.
        var layers: [[Member]] = []
        var owners: [UInt32: Owner] = [:]
        /// The windows held by a pin.
        var pinned: Set<UInt32> = []
        var rebound: [Rebind] = []
        var closed: [Closed] = []

        func members(of layerId: String) -> [Member] {
            ids.firstIndex(of: layerId).map { layers[$0] } ?? []
        }

        /// How many of each layer's entries hold a window, of how many it
        /// has. `layers` are the ones resolved, in the same order.
        func counts(of layers: [Layer]) -> [(running: Int, total: Int)] {
            layers.enumerated().map { index, layer in
                let held = self.layers.indices.contains(index) ? self.layers[index] : []
                let running = Set(held.map(\.project)).filter { layer.projects.indices.contains($0) }.count
                return (running, layer.projects.count)
            }
        }
    }

    /// A window of `app` whose title contains `title`, as an app entry, a
    /// tab or a companion reads it.
    static func reads(app: String, title: String?, _ window: WindowEntry) -> Bool {
        window.app.localizedCaseInsensitiveContains(app) && (title.map { window.titleContains($0) } ?? true)
    }

    /// A window showing tmux session `name` (`WorkspaceManager.sessionName`).
    static func shows(session name: String, _ window: WindowEntry) -> Bool {
        SessionWindowLocator.matches(session: name, title: window.title, extractedSessionName: window.latticesSession)
    }

    /// A window a tab of a group reads: its project's session, or its app and title.
    static func reads(_ tab: TabGroupTab, _ window: WindowEntry) -> Bool {
        if let path = tab.path { return shows(session: WorkspaceManager.sessionName(for: path), window) }
        guard let app = tab.app else { return false }
        return reads(app: app, title: tab.title, window)
    }

    /// How strongly an entry claims a window; the lower rank wins.
    private struct Rank: Comparable {
        enum Tier: Int { case pin, match, group, path, app }
        let tier: Tier
        /// Needle lengths: a longer needle is the more specific claim.
        let title: Int
        let app: Int
        let layer: Int
        let project: Int

        static func < (a: Rank, b: Rank) -> Bool {
            (a.tier.rawValue, b.title, b.app, a.layer, a.project)
                < (b.tier.rawValue, a.title, a.app, b.layer, b.project)
        }
    }

    /// Resolves every layer at once, so each window lands in one of them.
    static func resolve(_ layers: [Layer], windows: [WindowEntry], sources: Sources = Sources()) -> Resolution {
        var seen = Set<UInt32>()
        let front = windows.enumerated()
            .sorted { ($0.element.zIndex, $0.offset) < ($1.element.zIndex, $1.offset) }
            .map(\.element)
            .filter { seen.insert($0.wid).inserted }
        let content = front.filter(sources.isContent)
        let byWid = Dictionary(front.map { ($0.wid, $0) }, uniquingKeysWith: { first, _ in first })

        var best: [UInt32: (rank: Rank, placed: Bool)] = [:]
        // The strongest rule on each window, and the layers whose rules read it.
        var ruled: [UInt32: Rank] = [:]
        var readers: [UInt32: Set<Int>] = [:]
        func claim(_ window: WindowEntry, _ rank: Rank, placed: Bool) {
            if rank.tier != .pin {
                readers[window.wid, default: []].insert(rank.layer)
                if ruled[window.wid].map({ rank < $0 }) ?? true { ruled[window.wid] = rank }
            }
            if let held = best[window.wid], held.rank <= rank { return }
            best[window.wid] = (rank, placed)
        }
        var resolution = Resolution(ids: layers.map(\.id))

        // Pins. A live wid of the pin's app holds its window.
        var pinned = Set<UInt32>()
        var dead: [(layer: Int, project: Int, index: Int, pin: LayerPin)] = []
        for (l, layer) in layers.enumerated() {
            for (p, lp) in layer.projects.enumerated() {
                for (i, pin) in (lp.pins ?? []).enumerated() {
                    guard let window = byWid[pin.wid], window.app == pin.app else {
                        dead.append((l, p, i, pin))
                        continue
                    }
                    pinned.insert(pin.wid)
                    if sources.isContent(window) {
                        claim(window, Rank(tier: .pin, title: 0, app: 0, layer: l, project: p), placed: lp.isPlaced)
                    }
                }
            }
        }

        // Rules. An entry that only launches something matches nothing, and
        // one saved from a window matches by its pins alone.
        var companions: [String: [LayerProject]] = [:]
        for (l, layer) in layers.enumerated() {
            for (p, lp) in layer.projects.enumerated() {
                func ranked(_ tier: Rank.Tier, title: Int = 0, app: Int = 0) -> Rank {
                    Rank(tier: tier, title: title, app: app, layer: l, project: p)
                }
                func contains(_ app: String, title: String?, _ tier: Rank.Tier, placed: Bool) {
                    let rank = ranked(title == nil ? .app : tier, title: title?.count ?? 0, app: app.count)
                    for window in content where reads(app: app, title: title, window) {
                        claim(window, rank, placed: placed)
                    }
                }
                func session(of path: String, _ tier: Rank.Tier) {
                    let name = WorkspaceManager.sessionName(for: path)
                    // A session names one window: as specific as a claim gets.
                    let rank = ranked(tier, title: .max)
                    for window in content where shows(session: name, window) {
                        claim(window, rank, placed: lp.isPlaced)
                    }
                }

                if let clause = lp.match {
                    let rank = clause.appOnly.map { ranked(.app, app: $0) } ?? ranked(.match)
                    for window in content where clause.matches(window) {
                        claim(window, rank, placed: lp.isPlaced)
                    }
                } else if let groupId = lp.group, let group = sources.group(groupId) {
                    for tab in group.tabs {
                        if let path = tab.path {
                            session(of: path, .group)
                        } else if let app = tab.app {
                            contains(app, title: tab.title, .group, placed: lp.isPlaced)
                        }
                    }
                } else if let app = lp.app, !lp.isSaved {
                    contains(app, title: lp.title, .app, placed: lp.isPlaced)
                } else if let path = lp.path {
                    session(of: path, .path)
                    if companions[path] == nil { companions[path] = sources.projectWindows(path) }
                    for cw in companions[path] ?? [] {
                        guard let app = cw.app else { continue }
                        contains(app, title: cw.title, .path, placed: cw.tile != nil || (cw.display ?? lp.display) != nil)
                    }
                }
            }
        }

        // Dead pins. One whose window closed while its app ran on is gone
        // for good: closed. Once its app has quit, it takes the front window
        // no pin holds with the same app and exact title, and no other
        // layer's rule holds. A pin from before pins kept their process
        // takes only a window no other layer's entry reads.
        for gone in dead {
            // A pid another app's windows have now is no longer the pin's app.
            if let pid = gone.pin.pid, sources.isRunning(pid),
               !front.contains(where: { $0.pid == pid && $0.app != gone.pin.app }) {
                // A hidden app's window can drop out of the inventory.
                if !front.contains(where: { $0.pid == pid && $0.appHidden }) {
                    resolution.closed.append(Closed(layer: gone.layer, project: gone.project, pin: gone.index))
                }
                continue
            }
            guard !gone.pin.title.isEmpty, let window = content.first(where: { window in
                guard !pinned.contains(window.wid), window.app == gone.pin.app,
                      window.title == gone.pin.title || window.fullTitle == gone.pin.title else { return false }
                if gone.pin.pid == nil { return (readers[window.wid] ?? []).subtracting([gone.layer]).isEmpty }
                return (ruled[window.wid]?.layer ?? gone.layer) == gone.layer
            }) else { continue }
            pinned.insert(window.wid)
            resolution.rebound.append(Rebind(
                layer: gone.layer, project: gone.project, pin: gone.index, wid: window.wid, pid: window.pid
            ))
            let lp = layers[gone.layer].projects[gone.project]
            claim(window, Rank(tier: .pin, title: 0, app: 0, layer: gone.layer, project: gone.project), placed: lp.isPlaced)
        }

        var members = Array(repeating: [(order: Int, member: Member)](), count: layers.count)
        for (order, window) in content.enumerated() {
            guard let held = best[window.wid] else { continue }
            members[held.rank.layer].append((order, (window, held.placed, held.rank.project)))
            resolution.owners[window.wid] = Owner(layerId: layers[held.rank.layer].id, project: held.rank.project)
            if held.rank.tier == .pin { resolution.pinned.insert(window.wid) }
        }
        resolution.layers = members.map { list in
            list.sorted { ($0.member.project, $0.order) < ($1.member.project, $1.order) }.map(\.member)
        }
        return resolution
    }
}

extension LayerProject {
    /// Saved from a window (⌘⌥T, the layer bezel, a move): it holds windows
    /// by its pins alone; its app and title find a pin's window again and
    /// launch one. An entry written by hand matches by its app and title,
    /// pins or not.
    var isSaved: Bool { saved == true }
}

private extension LayerProject {
    /// The entry sets its own place, which a layout leaves be.
    var isPlaced: Bool { tile != nil || display != nil }
}
