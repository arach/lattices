import AppKit

/// Writing the ⌘⌥ layers: every surface that saves a set of windows as a
/// layer, or adds one to it, comes through here and lands in
/// `workspace.json`, the one place layers live.
///
/// A window is saved as an entry of its app and its title as it reads now,
/// which is what finds it again after a restart. While it lives, a pin
/// (`pins`) keeps it in even when the title moves on.
extension WorkspaceManager {
    enum LayerEditError: LocalizedError {
        case unknownLayer(String)
        case emptyName
        case write(String)
        case changedOnDisk

        var errorDescription: String? {
            switch self {
            case .unknownLayer(let name): return "No layer named \(name)"
            case .emptyName: return "A layer needs a name"
            case .write(let why): return "Couldn't save workspace.json: \(why)"
            case .changedOnDisk: return "workspace.json changed on disk; reloaded it, try again"
            }
        }
    }

    private static var backedUp = false

    var layers: [Layer] { config?.layers ?? [] }

    // MARK: Windows worth saving

    /// The windows a "save this layout" means: on screen, titled, not ours,
    /// and big enough to be a working window rather than a palette.
    func saveableWindows() -> [WindowEntry] {
        let me = getpid()
        return DesktopModel.shared.allWindows()
            .filter {
                $0.isOnScreen && $0.axVerified && !$0.title.isEmpty && $0.pid != me
                    && $0.frame.w >= 120 && $0.frame.h >= 120
            }
            .sorted { $0.zIndex < $1.zIndex }
    }

    /// The front window of the frontmost app, unless that's Lattices.
    func frontmostWindow() -> WindowEntry? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              !LatticesRuntime.isLatticesBundleIdentifier(app.bundleIdentifier) else { return nil }
        return DesktopModel.shared.allWindows()
            .filter { $0.pid == app.processIdentifier }
            .min { $0.zIndex < $1.zIndex }
    }

    // MARK: Edits

    /// Saves `windows` as a new layer after the others, and returns its index.
    /// `tiles` gives an entry its own tile, which the layer's layout leaves be.
    @discardableResult
    func createLayer(
        label: String, windows: [WindowEntry], tiles: [UInt32: String] = [:], entries: [LayerProject] = []
    ) throws -> Int {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { throw LayerEditError.emptyName }
        var all = layers
        var layer = Layer(id: uniqueLayerID(for: label, in: all), label: label, projects: entries, layout: "auto")
        var pinned: [UInt32: Int] = [:]
        for window in Self.distinct(windows) {
            layer.projects.append(Self.entry(for: window, tile: tiles[window.wid]))
            pinned[window.wid] = layer.projects.count - 1
        }
        all.append(layer)
        try saveLayers(all)
        pins[layer.id] = pinned
        DiagnosticLog.shared.info("Layers: created '\(label)' with \(pinned.count) window(s)")
        return all.count - 1
    }

    /// Adds each window the layer doesn't already hold, and returns how many
    /// it took. One it holds already is pinned to the entry that matched it,
    /// so it stays when its title moves on.
    @discardableResult
    func addWindows(_ windows: [WindowEntry], toLayer index: Int, tiles: [UInt32: String] = [:]) throws -> Int {
        var all = layers
        guard all.indices.contains(index) else { throw LayerEditError.unknownLayer("#\(index)") }
        let id = all[index].id
        var held: [UInt32: Int] = [:]
        for member in memberWindows(of: all[index], in: DesktopModel.shared.allWindows()) {
            held[member.entry.wid] = member.project
        }
        var pinned = pins[id] ?? [:]
        var added = 0
        for window in Self.distinct(windows) {
            if let project = held[window.wid] {
                pinned[window.wid] = project
                continue
            }
            all[index].projects.append(Self.entry(for: window, tile: tiles[window.wid]))
            pinned[window.wid] = all[index].projects.count - 1
            added += 1
        }
        if added > 0 { try saveLayers(all) }
        pins[id] = pinned
        return added
    }

    private static func entry(for window: WindowEntry, tile: String?) -> LayerProject {
        LayerProject(path: nil, group: nil, tile: tile, display: nil, app: window.app, title: window.title, url: nil, launch: nil)
    }

    private static func distinct(_ windows: [WindowEntry]) -> [WindowEntry] {
        var seen = Set<UInt32>()
        return windows.filter { seen.insert($0.wid).inserted }
    }

    /// Takes a window out of a layer by dropping the entries that hold only
    /// it. False when an entry that matches other windows too (a bare app,
    /// a project) still holds it; that's a JSON edit.
    @discardableResult
    func removeWindow(_ wid: UInt32, fromLayer index: Int) throws -> Bool {
        var all = layers
        guard all.indices.contains(index) else { throw LayerEditError.unknownLayer("#\(index)") }
        let windows = DesktopModel.shared.allWindows()
        let layer = all[index]
        // Release its pin first, so no entry holds it by pin alone, then
        // judge each entry by everything its rule matches on its own, not
        // just the windows it's first to claim.
        var pinned = pins[layer.id] ?? [:]
        pinned[wid] = nil
        let released = pinned
        let doomed = layer.projects.indices.filter { entry in
            entryMatches(layer, entry: entry, in: windows, pins: released) == [wid]
        }
        for entry in doomed.reversed() {
            all[index].projects.remove(at: entry)
            pinned = pinned.compactMapValues { $0 == entry ? nil : $0 > entry ? $0 - 1 : $0 }
        }
        let remaining = all[index].projects.indices.contains { entry in
            entryMatches(all[index], entry: entry, in: windows, pins: pinned).contains(wid)
        }
        if !doomed.isEmpty { try saveLayers(all) }
        pins[layer.id] = pinned
        return !remaining
    }

    /// The windows one entry matches by itself, its pins included.
    private func entryMatches(_ layer: Layer, entry: Int, in windows: [WindowEntry], pins given: [UInt32: Int]? = nil) -> Set<UInt32> {
        let single = Layer(id: "\(layer.id)#entry", label: layer.label, projects: [layer.projects[entry]], layout: nil)
        let all = given ?? pins[layer.id] ?? [:]
        let saved = pins[single.id]
        pins[single.id] = all.filter { $0.value == entry }.mapValues { _ in 0 }
        defer { pins[single.id] = saved }
        // A window pinned to another entry is that entry's, as in `memberWindows`.
        let elsewhere = Set(all.filter { $0.value != entry && layer.projects.indices.contains($0.value) }.keys)
        return memberWindowIDs(of: single, in: windows.filter { !elsewhere.contains($0.wid) })
    }

    enum MoveOutcome { case moved, copied, unchanged }

    /// Puts a window in the layer at `target` and takes it out of the one at
    /// `source`. `.copied` when `source` still holds it by a broader entry.
    func moveWindow(_ window: WindowEntry, from source: Int, to target: Int) throws -> MoveOutcome {
        guard source != target else { return .unchanged }
        let added = try addWindows([window], toLayer: target)
        let removed = try removeWindow(window.wid, fromLayer: source)
        DiagnosticLog.shared.info("Layers: \(window.app) '\(window.title)' → '\(layers[target].label)'\(removed ? "" : ", still in '\(layers[source].label)'")")
        if removed { return .moved }
        return added > 0 ? .copied : .unchanged
    }

    /// Replaces the entry at `entry`, or adds one when it's nil.
    func setEntry(_ project: LayerProject, at entry: Int?, inLayer index: Int) throws {
        var all = layers
        guard all.indices.contains(index) else { throw LayerEditError.unknownLayer("#\(index)") }
        if let entry, all[index].projects.indices.contains(entry) {
            all[index].projects[entry] = project
        } else {
            all[index].projects.append(project)
        }
        try saveLayers(all)
    }

    func removeEntry(at entry: Int, fromLayer index: Int) throws {
        var all = layers
        guard all.indices.contains(index), all[index].projects.indices.contains(entry) else {
            throw LayerEditError.unknownLayer("#\(index)")
        }
        all[index].projects.remove(at: entry)
        try saveLayers(all)
        let id = all[index].id
        pins[id] = pins[id]?.compactMapValues { $0 == entry ? nil : $0 > entry ? $0 - 1 : $0 }
    }

    func layerIndex(id: String) -> Int? {
        layers.firstIndex { $0.id == id }
    }

    func renameLayer(_ index: Int, to label: String) throws {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { throw LayerEditError.emptyName }
        var all = layers
        guard all.indices.contains(index) else { throw LayerEditError.unknownLayer("#\(index)") }
        all[index].label = label
        try saveLayers(all)
    }

    /// Deletes the layer. The one you're on moves down with it, so the pad
    /// still lights the same layer.
    func deleteLayer(_ index: Int) throws {
        var all = layers
        guard all.indices.contains(index) else { throw LayerEditError.unknownLayer("#\(index)") }
        let removed = all.remove(at: index)
        try saveLayers(all)
        pins[removed.id] = nil
        if index < activeLayerIndex || activeLayerIndex >= all.count {
            activeLayerIndex = max(0, activeLayerIndex - 1)
            UserDefaults.standard.set(activeLayerIndex, forKey: activeLayerKey)
        }
        DiagnosticLog.shared.info("Layers: deleted '\(removed.label)'")
    }

    /// ⌘⌥T: puts the front window in the layer you're on, making a first
    /// layer when there are none, and shows the pad on it.
    func addFrontmostWindowToActiveLayer() {
        guard let window = frontmostWindow() else { return }
        do {
            if layers.isEmpty {
                activeLayerIndex = try createLayer(label: "Layer 1", windows: [window])
            } else {
                let index = min(max(activeLayerIndex, 0), layers.count - 1)
                let added = try addWindows([window], toLayer: index)
                DiagnosticLog.shared.info("Layers: \(added > 0 ? "added" : "already held") \(window.app) '\(window.title)' → '\(layers[index].label)'")
            }
            showBezel(for: min(max(activeLayerIndex, 0), layers.count - 1), in: layers)
        } catch {
            DiagnosticLog.shared.error("Layers: couldn't add the front window — \(error.localizedDescription)")
        }
    }

    // MARK: Storage

    private func uniqueLayerID(for label: String, in layers: [Layer]) -> String {
        let slug = label.lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
            .split(separator: "-").joined(separator: "-")
        let base = slug.isEmpty ? "layer" : slug
        let taken = Set(layers.map(\.id))
        var id = base
        var n = 2
        while taken.contains(id) {
            id = "\(base)-\(n)"
            n += 1
        }
        return id
    }

    /// Writes `layers` into workspace.json, keeping everything else in the
    /// file as it was. The first write of a launch keeps the previous file
    /// as workspace.json.bak.
    private func saveLayers(_ layers: [Layer]) throws {
        let fm = FileManager.default
        var root: [String: Any] = ["name": config?.name ?? "workspace"]
        if !fm.fileExists(atPath: configPath), !self.layers.isEmpty {
            // Gone since we read it: don't bring it back from memory alone.
            loadConfig()
            throw LayerEditError.changedOnDisk
        }
        if fm.fileExists(atPath: configPath) {
            // Never write over a file we couldn't read: it holds more than layers.
            guard let data = fm.contents(atPath: configPath),
                  let existing = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { throw LayerEditError.write("workspace.json isn't readable JSON; fix it first") }
            root = existing
            // Nor over layers edited since we read them.
            let onDisk: [Layer]
            do {
                onDisk = try root["layers"].map {
                    try JSONDecoder().decode([Layer].self, from: JSONSerialization.data(withJSONObject: $0))
                } ?? []
            } catch {
                throw LayerEditError.write("workspace.json's layers don't read; fix them first")
            }
            guard try Self.same(onDisk, self.layers) else {
                loadConfig()
                throw LayerEditError.changedOnDisk
            }
        }
        do {
            root["layers"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(layers))
            let data = try JSONSerialization.data(
                withJSONObject: root,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
            try fm.createDirectory(
                atPath: (configPath as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
            if !Self.backedUp, fm.fileExists(atPath: configPath) {
                let backup = configPath + ".bak"
                try? fm.removeItem(atPath: backup)
                try fm.copyItem(atPath: configPath, toPath: backup)
                Self.backedUp = true
            }
            try data.write(to: URL(fileURLWithPath: configPath), options: .atomic)
        } catch {
            throw LayerEditError.write(error.localizedDescription)
        }
        if var config {
            config.layers = layers
            self.config = config
        } else {
            config = WorkspaceConfig(name: root["name"] as? String ?? "workspace", groups: nil, layers: layers)
        }
    }
}

extension WorkspaceManager {
    /// Keeps pins only on layers whose entries read as they did: a pin is
    /// an entry's index, which means nothing once the entries change.
    func reconcilePins(from old: [Layer], to new: [Layer]) {
        let before = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let after = Dictionary(new.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for id in Array(pins.keys) where !id.contains("#") {
            guard let was = before[id], let now = after[id],
                  (try? Self.same([Layer(id: "", label: "", projects: was.projects)],
                                  [Layer(id: "", label: "", projects: now.projects)])) == true
            else { pins[id] = nil; continue }
        }
    }

    fileprivate static func same(_ a: [Layer], _ b: [Layer]) throws -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(a) == encoder.encode(b)
    }
}

// MARK: - Entries as Studio rules

extension LayerProject {
    /// An entry from a Studio rule: plain `app` and `title` when that's all
    /// it says, so the file stays readable, the rule itself otherwise.
    init(clause: StudioLayerClause) {
        self.init(path: nil, group: nil, tile: nil, display: nil, app: nil, title: nil, url: nil, launch: nil)
        setClause(clause)
    }

    /// Swaps the entry's rule, keeping its tile, display, launch and the rest.
    mutating func setClause(_ clause: StudioLayerClause) {
        // `app` and `title` both match by substring, as the rule's `app` and
        // `titleContains` do; anything more stays a rule.
        var bare = clause
        bare.app = nil
        bare.titleContains = nil
        let plain = clause.app != nil && bare == StudioLayerClause()
        app = plain ? clause.app : nil
        title = plain ? clause.titleContains : nil
        match = plain ? nil : clause
    }

    /// The entry as a Studio rule, for Hyperspace's rule editor. A project or
    /// tab group has no rule form; nil.
    var clause: StudioLayerClause? {
        if let match { return match }
        guard let app else { return nil }
        return StudioLayerClause(app: app, titleContains: title)
    }
}
