import AppKit

// MARK: - WindowRef

struct WindowRef: Codable, Identifiable {
    let id: String

    // ── Intent (stable, survives restarts) ──
    var app: String
    var contentHint: String?
    var tile: String?
    var display: Int?

    // ── Runtime (ephemeral, filled when window is live) ──
    var wid: UInt32?
    var pid: Int32?
    var title: String?
    var frame: WindowFrame?

    init(id: String = UUID().uuidString, app: String, contentHint: String? = nil,
         tile: String? = nil, display: Int? = nil,
         wid: UInt32? = nil, pid: Int32? = nil, title: String? = nil, frame: WindowFrame? = nil) {
        self.id = id
        self.app = app
        self.contentHint = contentHint
        self.tile = tile
        self.display = display
        self.wid = wid
        self.pid = pid
        self.title = title
        self.frame = frame
    }
}

// MARK: - SessionLayer

struct SessionLayer: Identifiable, Codable {
    let id: String
    var name: String
    var windows: [WindowRef]

    init(id: String = UUID().uuidString, name: String, windows: [WindowRef] = []) {
        self.id = id
        self.name = name
        self.windows = windows
    }
}

// MARK: - SessionLayerStore

final class SessionLayerStore: ObservableObject {
    static let shared = SessionLayerStore()

    @Published var layers: [SessionLayer] = []
    @Published var activeIndex: Int = -1

    private init() {
        // Listen for window changes to reconcile stale refs
        EventBus.shared.subscribe { [weak self] event in
            if case .windowsChanged = event {
                DispatchQueue.main.async {
                    self?.reconcile()
                }
            }
        }
    }

    // MARK: - CRUD

    @discardableResult
    func create(name: String, windows: [WindowRef] = []) -> SessionLayer {
        let layer = SessionLayer(name: name, windows: windows)
        layers.append(layer)
        DiagnosticLog.shared.info("SessionLayerStore: created '\(name)' with \(windows.count) refs")
        // If this is the first layer, activate it
        if layers.count == 1 { activeIndex = 0 }
        return layer
    }

    func delete(id: String) {
        guard let idx = layers.firstIndex(where: { $0.id == id }) else { return }
        // Clear layer tags for windows in this layer
        for ref in layers[idx].windows {
            if let wid = ref.wid {
                DesktopModel.shared.removeLayerTag(wid: wid)
            }
        }
        layers.remove(at: idx)
        // Adjust activeIndex
        if layers.isEmpty {
            activeIndex = -1
        } else if activeIndex >= layers.count {
            activeIndex = layers.count - 1
        }
    }

    func rename(id: String, name: String) {
        guard let idx = layers.firstIndex(where: { $0.id == id }) else { return }
        layers[idx].name = name
    }

    func clear() {
        DesktopModel.shared.clearLayerTags()
        layers.removeAll()
        activeIndex = -1
        LayerBezel.shared.invalidateCache()
    }

    func layerById(_ id: String) -> SessionLayer? {
        layers.first { $0.id == id }
    }

    func layerByName(_ name: String) -> SessionLayer? {
        layers.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    // MARK: - Window Management

    func assign(ref: WindowRef, toLayerId id: String) {
        guard let idx = layers.firstIndex(where: { $0.id == id }) else { return }
        layers[idx].windows.append(ref)
        if let wid = ref.wid {
            DesktopModel.shared.assignLayer(wid: wid, layerId: layers[idx].name)
        }
    }

    func assignByWid(_ wid: UInt32, toLayerId id: String) {
        guard let idx = layers.firstIndex(where: { $0.id == id }) else { return }
        guard let entry = DesktopModel.shared.windows[wid] else { return }
        // Don't add duplicates
        if layers[idx].windows.contains(where: { $0.wid == wid }) { return }
        let ref = WindowRef(
            app: entry.app,
            contentHint: entry.title,
            wid: entry.wid,
            pid: entry.pid,
            title: entry.title,
            frame: entry.frame
        )
        layers[idx].windows.append(ref)
        DesktopModel.shared.assignLayer(wid: wid, layerId: layers[idx].name)
    }

    func remove(refId: String, fromLayerId id: String) {
        guard let idx = layers.firstIndex(where: { $0.id == id }) else { return }
        if let refIdx = layers[idx].windows.firstIndex(where: { $0.id == refId }) {
            if let wid = layers[idx].windows[refIdx].wid {
                DesktopModel.shared.removeLayerTag(wid: wid)
            }
            layers[idx].windows.remove(at: refIdx)
        }
    }

    func tagFrontmostWindow() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.bundleIdentifier != "com.arach.lattices" else { return }

        let pid = frontApp.processIdentifier
        // Find the frontmost window for this app
        guard let entry = DesktopModel.shared.windows.values
            .first(where: { $0.pid == pid }) else { return }

        // If no layers exist, create one
        if layers.isEmpty {
            create(name: "Layer 1")
        }

        // If no active layer, use first
        let targetIndex = activeIndex >= 0 ? activeIndex : 0
        guard targetIndex < layers.count else { return }

        let layerId = layers[targetIndex].id
        assignByWid(entry.wid, toLayerId: layerId)
        DiagnosticLog.shared.info("SessionLayerStore: tagged \(entry.app) '\(entry.title)' → '\(layers[targetIndex].name)'")

        // Show bezel feedback
        let allNames = layers.map(\.name)
        LayerBezel.shared.show(
            label: layers[targetIndex].name,
            index: targetIndex,
            total: layers.count,
            allLabels: allNames
        )
    }

    // MARK: - Switching

    func switchTo(index: Int) {
        guard index >= 0, index < layers.count else { return }
        activeIndex = index

        DesktopModel.shared.poll()

        var resolved: [(wid: UInt32, pid: Int32)] = []
        for i in layers[index].windows.indices {
            if let r = resolve(&layers[index].windows[i]) {
                resolved.append(r)
            }
        }

        if !resolved.isEmpty {
            WindowTiler.raiseWindowsAndReactivate(windows: resolved)
        }

        let allNames = layers.map(\.name)
        LayerBezel.shared.show(
            label: layers[index].name,
            index: index,
            total: layers.count,
            allLabels: allNames
        )

        DiagnosticLog.shared.info("SessionLayerStore: switched to '\(layers[index].name)' (\(resolved.count)/\(layers[index].windows.count) resolved)")
    }

    func cycleNext() {
        guard !layers.isEmpty else { return }
        let next = (activeIndex + 1) % layers.count
        switchTo(index: next)
    }

    func cyclePrev() {
        guard !layers.isEmpty else { return }
        let prev = activeIndex <= 0 ? layers.count - 1 : activeIndex - 1
        switchTo(index: prev)
    }

    // MARK: - Resolution

    private func resolve(_ ref: inout WindowRef) -> (wid: UInt32, pid: Int32)? {
        // 1. Fast path: wid still valid
        if let wid = ref.wid, let entry = DesktopModel.shared.windows[wid] {
            ref.pid = entry.pid
            ref.title = entry.title
            ref.frame = entry.frame
            return (wid, entry.pid)
        }

        // 2. Re-resolve by app + contentHint
        if let entry = DesktopModel.shared.windowForApp(app: ref.app, title: ref.contentHint) {
            ref.wid = entry.wid
            ref.pid = entry.pid
            ref.title = entry.title
            ref.frame = entry.frame
            DesktopModel.shared.assignLayer(wid: entry.wid, layerId: layerNameForRef(ref))
            return (entry.wid, entry.pid)
        }

        // 3. Window not found — dormant
        ref.wid = nil
        ref.pid = nil
        ref.title = nil
        ref.frame = nil
        return nil
    }

    private func layerNameForRef(_ ref: WindowRef) -> String {
        for layer in layers {
            if layer.windows.contains(where: { $0.id == ref.id }) {
                return layer.name
            }
        }
        return ""
    }

    // MARK: - Reconciliation

    func reconcile() {
        let desktop = DesktopModel.shared
        for layerIdx in layers.indices {
            for refIdx in layers[layerIdx].windows.indices {
                let ref = layers[layerIdx].windows[refIdx]
                guard let wid = ref.wid else { continue }
                if desktop.windows[wid] == nil {
                    // Window gone — clear runtime, keep intent
                    layers[layerIdx].windows[refIdx].wid = nil
                    layers[layerIdx].windows[refIdx].pid = nil
                    layers[layerIdx].windows[refIdx].title = nil
                    layers[layerIdx].windows[refIdx].frame = nil
                    desktop.removeLayerTag(wid: wid)
                }
            }
        }
    }
}
