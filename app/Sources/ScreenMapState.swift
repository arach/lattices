import AppKit
import Foundation
import SwiftUI

// MARK: - Display Geometry

struct DisplayGeometry {
    let index: Int
    let cgRect: CGRect   // in unified CG coords (top-left origin)
    let label: String    // e.g. "Built-in Retina Display", "LG UltraFine"
}

// MARK: - Screen Map Window Entry

struct ScreenMapWindowEntry: Identifiable {
    let id: UInt32              // CGWindowID
    let pid: Int32              // for AX API
    let app: String
    let title: String
    var originalFrame: CGRect   // frozen at snapshot time
    var editedFrame: CGRect     // mutated during drag
    let zIndex: Int             // 0 = frontmost
    var layer: Int              // assigned by iterative peeling (per-display)
    let displayIndex: Int       // which monitor this window belongs to
    let isOnScreen: Bool        // visible on current Space
    var latticesSession: String? // parsed from [lattices:name] in title
    var tmuxCommand: String?    // running command from tmux pane (e.g. "vim", "node")
    var tmuxPaneTitle: String?  // tmux pane title (often cwd or custom label)
    var hasEdits: Bool { originalFrame != editedFrame }

    /// Rich search key combining all available metadata.
    /// Format: m{spatial}.L{layer}.{layerName}.{app}.{title}.{session}.{command}.{paneTitle}.{state}
    /// Example: m1.L0.primary.terminal.~/dev/lattices.session:myproject.cmd:vim.visible
    func searchKey(spatialNumber: Int, layerName: String?) -> String {
        var parts: [String] = []
        parts.append("m\(spatialNumber)")
        parts.append(layerName.map { "L\(layer).\($0)" } ?? "L\(layer)")
        parts.append(app)
        parts.append(title.isEmpty ? "_" : title)
        if let session = latticesSession {
            parts.append("session:\(session)")
        }
        if let cmd = tmuxCommand, !cmd.isEmpty {
            parts.append("cmd:\(cmd)")
        }
        if let pTitle = tmuxPaneTitle, !pTitle.isEmpty, pTitle != title {
            parts.append(pTitle)
        }
        parts.append(isOnScreen ? "visible" : "hidden")
        return parts.joined(separator: ".").lowercased()
    }
}

// MARK: - Canvas Drag Mode

enum CanvasDragMode {
    case move
    case resizeLeft, resizeRight, resizeTop, resizeBottom
    case resizeTopLeft, resizeTopRight, resizeBottomLeft, resizeBottomRight
}

// MARK: - Screen Map Editor State

final class ScreenMapEditorState: ObservableObject {
    @Published var windows: [ScreenMapWindowEntry]
    @Published var selectedLayers: Set<Int> = [0]  // empty = show all
    @Published var draggingWindowId: UInt32? = nil
    var canvasDragMode: CanvasDragMode = .move
    var currentCursorMode: CanvasDragMode = .move
    @Published var isPreviewing: Bool = false
    @Published var lastActionRef: String? = nil
    @Published var zoomLevel: CGFloat = 1.0   // 1.0 = fit-all
    @Published var panOffset: CGPoint = .zero  // canvas-local pixels
    @Published var focusedDisplayIndex: Int? = nil  // nil = all-displays view
    @Published var windowSearchQuery: String = ""
    @Published var isTilingMode: Bool = false
    var isSearching: Bool { !windowSearchQuery.isEmpty }

    var searchFilteredWindows: [ScreenMapWindowEntry] {
        guard !windowSearchQuery.isEmpty else { return [] }
        let terms = windowSearchQuery.lowercased()
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return [] }

        // Pre-compile glob patterns into matchers
        let matchers: [(String) -> Bool] = terms.map { term in
            if term.hasPrefix("/"), term.count > 1 {
                // Raw regex: /pattern/
                let raw = String(term.dropFirst().hasSuffix("/") ? term.dropFirst().dropLast() : term.dropFirst())
                return Self.regexMatcher(raw)
            } else if term.contains("*") || term.contains("?") {
                return Self.globMatcher(term)
            } else {
                return { key in key.contains(term) }
            }
        }

        return windows
            .filter { win in
                let key = win.searchKey(
                    spatialNumber: spatialNumber(for: win.displayIndex),
                    layerName: layerNames[win.layer]
                )
                return matchers.allSatisfy { $0(key) }
            }
            .sorted { $0.zIndex < $1.zIndex }
    }

    /// Convert a glob pattern (with * and ?) into a substring matcher closure.
    /// `*` matches any sequence of characters, `?` matches exactly one character.
    /// Pattern is matched as a substring unless anchored with `*` on both ends.
    private static func globMatcher(_ pattern: String) -> (String) -> Bool {
        // Convert glob to regex: escape regex-special chars, then * → .* and ? → .
        var regex = ""
        for ch in pattern {
            switch ch {
            case "*": regex += ".*"
            case "?": regex += "."
            case ".", "(", ")", "[", "]", "{", "}", "^", "$", "|", "+", "\\": regex += "\\\(ch)"
            default: regex += String(ch)
            }
        }
        guard let re = try? NSRegularExpression(pattern: regex, options: []) else {
            return { key in key.contains(pattern) }
        }
        return { key in
            re.firstMatch(in: key, range: NSRange(key.startIndex..., in: key)) != nil
        }
    }

    /// Raw regex matcher — term is an unescaped regex pattern.
    /// Case-insensitive. Falls back to literal contains on invalid regex.
    private static func regexMatcher(_ pattern: String) -> (String) -> Bool {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return { key in key.contains(pattern) }
        }
        return { key in
            re.firstMatch(in: key, range: NSRange(key.startIndex..., in: key)) != nil
        }
    }

    var searchTerms: [String] {
        windowSearchQuery.lowercased()
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    var searchHasDirectHit: Bool {
        searchFilteredWindows.count == 1
    }

    var searchResultsByDisplay: [(displayIndex: Int, spatialNumber: Int, label: String, windows: [ScreenMapWindowEntry])] {
        let filtered = searchFilteredWindows
        guard !filtered.isEmpty else { return [] }
        let grouped = Dictionary(grouping: filtered) { $0.displayIndex }
        return grouped.keys.sorted { spatialNumber(for: $0) < spatialNumber(for: $1) }
            .map { idx in
                let label = displays.first(where: { $0.index == idx })?.label ?? "Display \(idx)"
                let wins = grouped[idx]!.sorted { $0.zIndex < $1.zIndex }
                return (idx, spatialNumber(for: idx), label, wins)
            }
    }

    /// Workspace layer names from workspace.json (layer index → label)
    var layerNames: [Int: String] = [:]

    static let minZoom: CGFloat = 0.3
    static let maxZoom: CGFloat = 5.0

    var effectiveScale: CGFloat { scale * zoomLevel }

    func resetZoomPan() {
        zoomLevel = 1.0
        panOffset = .zero
    }

    let actionLog = ScreenMapActionLog()

    /// Backward-compat: single active layer when exactly one is selected
    var activeLayer: Int? {
        selectedLayers.count == 1 ? selectedLayers.first : nil
    }

    func isLayerSelected(_ layer: Int) -> Bool {
        selectedLayers.isEmpty || selectedLayers.contains(layer)
    }

    var isShowingAll: Bool { selectedLayers.isEmpty }
    var dragStartFrame: CGRect? = nil

    // Cached geometry for coordinate conversion (set by the view)
    var fitScale: CGFloat = 1   // base fit-all scale (before zoom)
    var scale: CGFloat = 1      // effective scale (fitScale * zoomLevel)
    var mapOrigin: CGPoint = .zero
    var screenSize: CGSize = .zero
    var bboxOrigin: CGPoint = .zero  // top-left of the bounding box in CG coords

    let displays: [DisplayGeometry]

    init(windows: [ScreenMapWindowEntry], displays: [DisplayGeometry] = []) {
        self.windows = windows
        self.displays = displays
    }

    /// Number of distinct layers (global, all displays)
    var layerCount: Int {
        (windows.map(\.layer).max() ?? 0) + 1
    }

    /// Window count for a specific layer (for sidebar badges)
    func windowCount(for layer: Int) -> Int {
        windows.filter { $0.layer == layer }.count
    }

    // MARK: - Per-Display Layer Scoping

    /// Sorted unique layers present on a given display
    func layersForDisplay(_ displayIndex: Int) -> [Int] {
        let displayWindows = windows.filter { $0.displayIndex == displayIndex }
        return Array(Set(displayWindows.map(\.layer))).sorted()
    }

    /// Layers scoped to the focused display, or all layers when showing all displays
    var effectiveLayers: [Int] {
        guard let dIdx = focusedDisplayIndex else {
            return Array(0..<layerCount)
        }
        return layersForDisplay(dIdx)
    }

    /// Count of layers on the focused display (or global count)
    var effectiveLayerCount: Int {
        effectiveLayers.count
    }

    /// Window count for a layer, scoped to the focused display
    func effectiveWindowCount(for layer: Int) -> Int {
        guard let dIdx = focusedDisplayIndex else {
            return windowCount(for: layer)
        }
        return windows.filter { $0.layer == layer && $0.displayIndex == dIdx }.count
    }

    /// Visible window count per display index
    func visibleWindowCount(for displayIndex: Int) -> Int {
        visibleWindows.filter { $0.displayIndex == displayIndex }.count
    }

    /// Display name for a layer (from workspace config or fallback)
    func layerDisplayName(for layer: Int) -> String {
        if let name = layerNames[layer] {
            return String(name.prefix(8))
        }
        return "L\(layer)"
    }

    /// Windows visible for the active layer filter
    var visibleWindows: [ScreenMapWindowEntry] {
        guard !selectedLayers.isEmpty else { return windows }
        return windows.filter { selectedLayers.contains($0.layer) }
    }

    /// The focused display geometry (nil when showing all)
    var focusedDisplay: DisplayGeometry? {
        guard let idx = focusedDisplayIndex else { return nil }
        return displays.first(where: { $0.index == idx })
    }

    /// Windows filtered by both layer AND focused display
    var focusedVisibleWindows: [ScreenMapWindowEntry] {
        let layerFiltered = visibleWindows
        guard let dIdx = focusedDisplayIndex else { return layerFiltered }
        return layerFiltered.filter { $0.displayIndex == dIdx }
    }

    /// Displays sorted by physical position (left-to-right, then top-to-bottom)
    var spatialDisplayOrder: [DisplayGeometry] {
        displays.sorted { a, b in
            if abs(a.cgRect.origin.x - b.cgRect.origin.x) > 10 {
                return a.cgRect.origin.x < b.cgRect.origin.x
            }
            return a.cgRect.origin.y < b.cgRect.origin.y
        }
    }

    /// 1-based spatial position for a display (left-to-right numbering)
    func spatialNumber(for displayIndex: Int) -> Int {
        let order = spatialDisplayOrder
        if let pos = order.firstIndex(where: { $0.index == displayIndex }) {
            return pos + 1
        }
        return displayIndex + 1
    }

    /// Set focus to a specific display (nil = all-displays view)
    func focusDisplay(_ index: Int?) {
        focusedDisplayIndex = index
        selectedLayers = []  // reset to "All" for the new display scope
        resetZoomPan()
    }

    /// Cycle to the next display in spatial (left-to-right) order
    func cycleNextDisplay() {
        let order = spatialDisplayOrder
        guard order.count > 1 else { return }
        guard let current = focusedDisplayIndex else {
            focusedDisplayIndex = order.first!.index
            selectedLayers = []
            resetZoomPan()
            return
        }
        if let pos = order.firstIndex(where: { $0.index == current }) {
            let next = pos + 1
            if next >= order.count {
                focusedDisplayIndex = nil  // all-displays view
            } else {
                focusedDisplayIndex = order[next].index
            }
        } else {
            focusedDisplayIndex = nil
        }
        selectedLayers = []
        resetZoomPan()
    }

    /// Cycle to the previous display in spatial (right-to-left) order
    func cyclePreviousDisplay() {
        let order = spatialDisplayOrder
        guard order.count > 1 else { return }
        guard let current = focusedDisplayIndex else {
            focusedDisplayIndex = order.last!.index
            selectedLayers = []
            resetZoomPan()
            return
        }
        if let pos = order.firstIndex(where: { $0.index == current }) {
            if pos == 0 {
                focusedDisplayIndex = nil  // all-displays view
            } else {
                focusedDisplayIndex = order[pos - 1].index
            }
        } else {
            focusedDisplayIndex = nil
        }
        selectedLayers = []
        resetZoomPan()
    }

    /// Number of windows with pending edits (position or size)
    var pendingEditCount: Int {
        windows.filter(\.hasEdits).count
    }

    /// Cycle layer: first → … → last → empty(all) → first
    func cycleLayer() {
        let layers = effectiveLayers
        guard !layers.isEmpty else { return }

        if selectedLayers.count > 1 {
            selectedLayers = [layers[0]]
            return
        }
        guard let current = activeLayer else {
            selectedLayers = [layers[0]]
            return
        }
        guard let idx = layers.firstIndex(of: current) else {
            selectedLayers = [layers[0]]
            return
        }
        let nextIdx = idx + 1
        if nextIdx >= layers.count {
            selectedLayers = []  // all
        } else {
            selectedLayers = [layers[nextIdx]]
        }
    }

    /// Cycle layer backward
    func cyclePreviousLayer() {
        let layers = effectiveLayers
        guard !layers.isEmpty else { return }

        if selectedLayers.count > 1 {
            selectedLayers = [layers.last!]
            return
        }
        guard let current = activeLayer else {
            selectedLayers = [layers.last!]
            return
        }
        guard let idx = layers.firstIndex(of: current) else {
            selectedLayers = [layers.last!]
            return
        }
        if idx == 0 {
            selectedLayers = []  // all
        } else {
            selectedLayers = [layers[idx - 1]]
        }
    }

    /// Direct layer selection (from sidebar clicks)
    func selectLayer(_ layer: Int?) {
        DiagnosticLog.shared.info("[ScreenMap] selectLayer: \(layer.map { "\($0)" } ?? "all")")
        if let layer {
            selectedLayers = [layer]
        } else {
            selectedLayers = []
        }
    }

    /// Toggle a layer in multi-select (Cmd+click)
    func toggleLayerSelection(_ layer: Int) {
        if selectedLayers.contains(layer) {
            selectedLayers.remove(layer)
        } else {
            selectedLayers.insert(layer)
        }
        if selectedLayers.count >= effectiveLayerCount {
            selectedLayers = []
        }
        DiagnosticLog.shared.info("[ScreenMap] toggleLayer \(layer) → \(selectedLayers.sorted())")
    }

    /// Move a window to a different layer
    func reassignLayer(windowId: UInt32, toLayer: Int, fitToAvailable: Bool) {
        guard let idx = windows.firstIndex(where: { $0.id == windowId }) else { return }
        let oldFrame = windows[idx].editedFrame
        windows[idx].layer = toLayer
        if fitToAvailable {
            fitWindowIntoLayer(at: idx)
        }
        let newFrame = windows[idx].editedFrame
        if oldFrame != newFrame {
            DiagnosticLog.shared.info("[ScreenMap] reassign wid=\(windowId): fitted \(Int(oldFrame.origin.x)),\(Int(oldFrame.origin.y)) → \(Int(newFrame.origin.x)),\(Int(newFrame.origin.y))")
        }
    }

    /// Auto-resize a window to fit among siblings in its layer
    func fitWindowIntoLayer(at idx: Int) {
        let win = windows[idx]
        let siblings = windows.enumerated().filter { $0.offset != idx && $0.element.layer == win.layer }
        let siblingFrames = siblings.map(\.element.editedFrame)
        let screenRect = CGRect(origin: .zero, size: screenSize)
        if let fitted = fitRect(win.editedFrame, avoiding: siblingFrames, within: screenRect) {
            windows[idx].editedFrame = fitted
        }
    }

    /// Try to fit a rect avoiding collisions
    func fitRect(_ rect: CGRect, avoiding others: [CGRect], within bounds: CGRect) -> CGRect? {
        let collisions = others.filter { $0.intersects(rect) }
        if collisions.isEmpty { return nil }

        let minW: CGFloat = 100, minH: CGFloat = 50
        var candidates: [CGRect] = []

        for blocker in collisions {
            let rightClip = CGRect(x: rect.minX, y: rect.minY,
                                   width: blocker.minX - rect.minX, height: rect.height)
            if rightClip.width >= minW && rightClip.height >= minH { candidates.append(rightClip) }

            let bottomClip = CGRect(x: rect.minX, y: rect.minY,
                                    width: rect.width, height: blocker.minY - rect.minY)
            if bottomClip.width >= minW && bottomClip.height >= minH { candidates.append(bottomClip) }

            let pushRight = CGRect(x: blocker.maxX, y: rect.minY,
                                   width: rect.width, height: rect.height)
            if pushRight.maxX <= bounds.maxX { candidates.append(pushRight) }

            let pushDown = CGRect(x: rect.minX, y: blocker.maxY,
                                  width: rect.width, height: rect.height)
            if pushDown.maxY <= bounds.maxY { candidates.append(pushDown) }
        }

        let valid = candidates.filter { cand in
            cand.width >= minW && cand.height >= minH &&
            bounds.contains(cand) &&
            !others.contains(where: { $0.intersects(cand) })
        }
        return valid.max(by: { $0.width * $0.height < $1.width * $1.height })
    }

    /// Auto-tile the active layer's windows into a grid
    func autoTileLayer() -> Int {
        guard let layer = activeLayer else { return 0 }

        let screens = NSScreen.screens
        let primaryHeight = screens.first?.frame.height ?? 0
        var totalTiled = 0
        let diag = DiagnosticLog.shared

        diag.info("[Tile] autoTileLayer layer=\(layer) screens=\(screens.count)")
        var displayIndices = Set(windows.filter { $0.layer == layer }.map(\.displayIndex))
        if let focused = focusedDisplayIndex { displayIndices = displayIndices.intersection([focused]) }
        for dIdx in displayIndices.sorted() {
            var indices = windows.indices.filter { windows[$0].layer == layer && windows[$0].displayIndex == dIdx }
            guard indices.count >= 1 else { continue }
            indices.sort { windows[$0].zIndex < windows[$1].zIndex }

            let screen = dIdx < screens.count ? screens[dIdx] : screens.first!
            let visible = screen.visibleFrame
            let axTop = primaryHeight - visible.maxY

            if indices.count == 1 {
                let frame = CGRect(x: visible.origin.x, y: axTop, width: visible.width, height: visible.height)
                windows[indices[0]].editedFrame = frame
                totalTiled += 1
                continue
            }

            let shape = WindowTiler.gridShape(for: indices.count)
            let rowCount = shape.count
            let totalW = Int(visible.width)
            let totalH = Int(visible.height)
            let baseX = Int(visible.origin.x)
            let baseY = Int(axTop)

            var slotIdx = 0
            for (row, cols) in shape.enumerated() {
                let y0 = baseY + (row * totalH) / rowCount
                let y1 = baseY + ((row + 1) * totalH) / rowCount
                for col in 0..<cols {
                    guard slotIdx < indices.count else { break }
                    let x0 = baseX + (col * totalW) / cols
                    let x1 = baseX + ((col + 1) * totalW) / cols
                    let frame = CGRect(x: CGFloat(x0), y: CGFloat(y0), width: CGFloat(x1 - x0), height: CGFloat(y1 - y0))
                    windows[indices[slotIdx]].editedFrame = frame
                    slotIdx += 1
                }
            }
            totalTiled += indices.count
        }
        return totalTiled
    }

    /// Expose the active layer's windows with gaps
    func exposeLayer() -> Int {
        guard let layer = activeLayer else { return 0 }

        let screens = NSScreen.screens
        let primaryHeight = screens.first?.frame.height ?? 0
        var totalExposed = 0

        var displayIndices = Set(windows.filter { $0.layer == layer }.map(\.displayIndex))
        if let focused = focusedDisplayIndex { displayIndices = displayIndices.intersection([focused]) }
        for dIdx in displayIndices {
            var indices = windows.indices.filter { windows[$0].layer == layer && windows[$0].displayIndex == dIdx }
            guard indices.count >= 2 else { totalExposed += indices.count; continue }
            indices.sort { windows[$0].zIndex < windows[$1].zIndex }

            let screen = dIdx < screens.count ? screens[dIdx] : screens.first!
            let visible = screen.visibleFrame
            let axTop = primaryHeight - visible.maxY
            let padding: CGFloat = 20
            let shape = WindowTiler.gridShape(for: indices.count)
            let rowCount = shape.count
            let rowH = visible.height / CGFloat(rowCount)

            var slotIdx = 0
            for (row, cols) in shape.enumerated() {
                let colW = visible.width / CGFloat(cols)
                let axY = axTop + CGFloat(row) * rowH
                for col in 0..<cols {
                    guard slotIdx < indices.count else { break }
                    let idx = indices[slotIdx]
                    let orig = windows[idx].originalFrame

                    let cellX = visible.origin.x + CGFloat(col) * colW + padding
                    let cellY = axY + padding
                    let cellW = colW - padding * 2
                    let cellH = rowH - padding * 2

                    let aspect = orig.width / max(orig.height, 1)
                    var fitW = cellW
                    var fitH = fitW / aspect
                    if fitH > cellH {
                        fitH = cellH
                        fitW = fitH * aspect
                    }

                    let x = cellX + (cellW - fitW) / 2
                    let y = cellY + (cellH - fitH) / 2

                    windows[idx].editedFrame = CGRect(x: x, y: y, width: fitW, height: fitH)
                    slotIdx += 1
                }
            }
            totalExposed += indices.count
        }
        return totalExposed
    }

    /// Push overlapping windows apart with minimal movement
    func smartSpreadLayer() -> Int {
        guard let layer = activeLayer else { return 0 }

        let screens = NSScreen.screens
        let primaryHeight = screens.first?.frame.height ?? 0
        var totalAffected = 0

        var displayIndices = Set(windows.filter { $0.layer == layer }.map(\.displayIndex))
        if let focused = focusedDisplayIndex { displayIndices = displayIndices.intersection([focused]) }
        for dIdx in displayIndices {
            let indices = windows.indices.filter { windows[$0].layer == layer && windows[$0].displayIndex == dIdx }
            guard indices.count >= 2 else { continue }

            let screen = dIdx < screens.count ? screens[dIdx] : screens.first!
            let axTop = primaryHeight - screen.frame.maxY
            let screenRect = CGRect(x: screen.frame.origin.x, y: axTop,
                                    width: screen.frame.width, height: screen.frame.height)
            var affected: Set<Int> = []

            for _ in 0..<15 {
                var hadOverlap = false
                for i in 0..<indices.count {
                    for j in (i + 1)..<indices.count {
                        let idxA = indices[i]
                        let idxB = indices[j]
                        let a = windows[idxA].editedFrame
                        let b = windows[idxB].editedFrame
                        guard a.intersects(b) else { continue }
                        hadOverlap = true

                        let overlapW = min(a.maxX, b.maxX) - max(a.minX, b.minX)
                        let overlapH = min(a.maxY, b.maxY) - max(a.minY, b.minY)

                        if overlapW < overlapH {
                            let push = (overlapW / 2).rounded(.up) + 1
                            if a.midX <= b.midX {
                                windows[idxA].editedFrame.origin.x -= push
                                windows[idxB].editedFrame.origin.x += push
                            } else {
                                windows[idxA].editedFrame.origin.x += push
                                windows[idxB].editedFrame.origin.x -= push
                            }
                        } else {
                            let push = (overlapH / 2).rounded(.up) + 1
                            if a.midY <= b.midY {
                                windows[idxA].editedFrame.origin.y -= push
                                windows[idxB].editedFrame.origin.y += push
                            } else {
                                windows[idxA].editedFrame.origin.y += push
                                windows[idxB].editedFrame.origin.y -= push
                            }
                        }
                        affected.insert(idxA)
                        affected.insert(idxB)
                    }
                }
                for idx in indices { clampToScreen(at: idx, bounds: screenRect) }
                if !hadOverlap { break }
            }
            totalAffected += affected.count
        }
        return totalAffected
    }

    private func clampToScreen(at idx: Int, bounds: CGRect) {
        var f = windows[idx].editedFrame
        if f.minX < bounds.minX { f.origin.x = bounds.minX }
        if f.minY < bounds.minY { f.origin.y = bounds.minY }
        if f.maxX > bounds.maxX { f.origin.x = bounds.maxX - f.width }
        if f.maxY > bounds.maxY { f.origin.y = bounds.maxY - f.height }
        windows[idx].editedFrame = f
    }

    /// Grow each window outward until it hits a neighbor or screen edge
    func fitAvailableSpace() -> Int {
        guard let layer = activeLayer else { return 0 }

        let screens = NSScreen.screens
        let primaryHeight = screens.first?.frame.height ?? 0
        var totalAffected = 0

        var displayIndices = Set(windows.filter { $0.layer == layer }.map(\.displayIndex))
        if let focused = focusedDisplayIndex { displayIndices = displayIndices.intersection([focused]) }

        for dIdx in displayIndices {
            var indices = windows.indices.filter { windows[$0].layer == layer && windows[$0].displayIndex == dIdx }
            guard !indices.isEmpty else { continue }
            indices.sort { windows[$0].zIndex < windows[$1].zIndex }

            let screen = dIdx < screens.count ? screens[dIdx] : screens.first!
            let axTop = primaryHeight - screen.frame.maxY
            let bounds = CGRect(x: screen.frame.origin.x, y: axTop,
                                width: screen.frame.width, height: screen.frame.height)

            // Snapshot original positions for neighbor detection
            let origFrames = indices.map { windows[$0].editedFrame }

            for (i, idx) in indices.enumerated() {
                let me = origFrames[i]

                // Find nearest obstacle in each direction (only neighbors that overlap on the perpendicular axis)
                var left = bounds.minX
                var right = bounds.maxX
                var top = bounds.minY
                var bottom = bounds.maxY

                for (j, otherFrame) in origFrames.enumerated() where j != i {
                    // Left: other window whose right edge is to my left, overlapping vertically
                    if otherFrame.maxX <= me.minX + 1 &&
                       otherFrame.maxY > me.minY && otherFrame.minY < me.maxY {
                        left = max(left, otherFrame.maxX)
                    }
                    // Right: other window whose left edge is to my right, overlapping vertically
                    if otherFrame.minX >= me.maxX - 1 &&
                       otherFrame.maxY > me.minY && otherFrame.minY < me.maxY {
                        right = min(right, otherFrame.minX)
                    }
                    // Top: other window whose bottom edge is above me, overlapping horizontally
                    if otherFrame.maxY <= me.minY + 1 &&
                       otherFrame.maxX > me.minX && otherFrame.minX < me.maxX {
                        top = max(top, otherFrame.maxY)
                    }
                    // Bottom: other window whose top edge is below me, overlapping horizontally
                    if otherFrame.minY >= me.maxY - 1 &&
                       otherFrame.maxX > me.minX && otherFrame.minX < me.maxX {
                        bottom = min(bottom, otherFrame.minY)
                    }
                }

                let newFrame = CGRect(x: left, y: top, width: right - left, height: bottom - top)
                if newFrame != windows[idx].editedFrame {
                    windows[idx].editedFrame = newFrame
                    totalAffected += 1
                }
            }
        }
        return totalAffected
    }

    /// Distribute visible windows into a grid (staged — edits frames only)
    func distributeLayer() -> Int {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return 0 }
        var totalDistributed = 0

        // Group by display
        var displayIndices: Set<Int>
        if let focused = focusedDisplayIndex {
            displayIndices = [focused]
        } else {
            displayIndices = Set(focusedVisibleWindows.map(\.displayIndex))
            if displayIndices.isEmpty {
                displayIndices = Set(visibleWindows.map(\.displayIndex))
            }
        }

        for dIdx in displayIndices.sorted() {
            // Get windows to distribute on this display
            var indices = windows.indices.filter { idx in
                let win = windows[idx]
                let layerMatch = selectedLayers.isEmpty || selectedLayers.contains(win.layer)
                return win.displayIndex == dIdx && layerMatch
            }
            guard !indices.isEmpty else { continue }
            indices.sort { windows[$0].zIndex < windows[$1].zIndex }

            let screen = dIdx < screens.count ? screens[dIdx] : screens.first!
            let slots = WindowTiler.computeGridSlots(count: indices.count, screen: screen)
            guard slots.count == indices.count else { continue }

            for (i, idx) in indices.enumerated() {
                windows[idx].editedFrame = slots[i]
            }
            totalDistributed += indices.count
        }
        return totalDistributed
    }

    /// Reset all edited frames back to original
    func discardEdits() {
        for i in windows.indices {
            windows[i].editedFrame = windows[i].originalFrame
        }
    }

    /// Remap sparse layer numbers to contiguous
    func renumberLayersContiguous() {
        let usedLayers = Set(windows.map(\.layer)).sorted()
        guard usedLayers != Array(0..<usedLayers.count) else { return }
        let mapping = Dictionary(uniqueKeysWithValues: usedLayers.enumerated().map { ($1, $0) })
        for i in windows.indices {
            windows[i].layer = mapping[windows[i].layer] ?? windows[i].layer
        }
        selectedLayers = Set(selectedLayers.compactMap { mapping[$0] })
    }

    /// Consolidate windows into fewer layers
    func consolidateLayers() -> (old: Int, new: Int) {
        let oldCount = effectiveLayerCount
        let scopedLayers = effectiveLayers
        guard let maxLayer = scopedLayers.last, maxLayer >= 1 else { return (oldCount, oldCount) }

        let screenRect = CGRect(origin: .zero, size: screenSize)
        let dIdx = focusedDisplayIndex

        for sourceLayer in stride(from: maxLayer, through: 1, by: -1) {
            guard scopedLayers.contains(sourceLayer) else { continue }
            let windowIndices = windows.indices.filter {
                windows[$0].layer == sourceLayer &&
                (dIdx == nil || windows[$0].displayIndex == dIdx!)
            }
            for idx in windowIndices {
                let win = windows[idx]
                for targetLayer in scopedLayers where targetLayer < sourceLayer {
                    let siblings = windows.enumerated().filter {
                        $0.offset != idx && $0.element.layer == targetLayer &&
                        (dIdx == nil || $0.element.displayIndex == dIdx!)
                    }.map(\.element.editedFrame)

                    let collisions = siblings.filter { $0.intersects(win.editedFrame) }
                    if collisions.isEmpty {
                        windows[idx].layer = targetLayer
                        break
                    }
                    if let fitted = fitRect(win.editedFrame, avoiding: siblings, within: screenRect) {
                        windows[idx].editedFrame = fitted
                        windows[idx].layer = targetLayer
                        break
                    }
                }
            }
        }

        renumberLayersContiguous()
        let newLayers = effectiveLayers
        selectedLayers = newLayers.isEmpty ? [] : [newLayers[0]]
        return (old: oldCount, new: effectiveLayerCount)
    }

    var layerLabel: String {
        if selectedLayers.isEmpty { return "ALL" }
        if selectedLayers.count == 1 { return "LAYER \(selectedLayers.first!)" }
        return selectedLayers.sorted().map { "L\($0)" }.joined(separator: "+")
    }

    /// Merge all windows from selected layers into the lowest one
    func flattenSelectedLayers() -> (count: Int, target: Int)? {
        guard selectedLayers.count >= 2 else { return nil }
        let sorted = selectedLayers.sorted()
        let target = sorted[0]
        let higherLayers = Set(sorted.dropFirst())
        let dIdx = focusedDisplayIndex

        var moveCount = 0
        for idx in windows.indices where higherLayers.contains(windows[idx].layer) {
            if let dIdx, windows[idx].displayIndex != dIdx { continue }
            windows[idx].layer = target
            fitWindowIntoLayer(at: idx)
            moveCount += 1
        }

        renumberLayersContiguous()
        selectedLayers = target < layerCount ? [target] : []
        return (count: moveCount, target: target)
    }
}

// MARK: - Screen Map Action Log

final class ScreenMapActionLog {
    struct WindowSnapshot: Codable {
        let wid: UInt32
        let app: String
        let title: String
        let frame: FrameSnapshot
        let layer: Int

        struct FrameSnapshot: Codable {
            let x: Int
            let y: Int
            let w: Int
            let h: Int
        }
    }

    struct MovedWindow: Codable {
        let wid: UInt32
        let app: String
        let title: String
        let fromFrame: WindowSnapshot.FrameSnapshot
        let toFrame: WindowSnapshot.FrameSnapshot
        let fromLayer: Int
        let toLayer: Int
    }

    struct Entry: Codable {
        let ref: String
        let action: String
        let timestamp: String
        let summary: String
        let before: [WindowSnapshot]
        let after: [WindowSnapshot]
        let moved: [MovedWindow]
    }

    private(set) var lastEntry: Entry? = nil

    private static var logFileURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".lattices", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("actions.jsonl")
    }()

    private static func shortUUID() -> String {
        let uuid = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return String(uuid.suffix(8))
    }

    func snapshot(_ windows: [ScreenMapWindowEntry]) -> [WindowSnapshot] {
        windows.map { win in
            WindowSnapshot(
                wid: win.id, app: win.app, title: win.title,
                frame: .init(
                    x: Int(win.editedFrame.origin.x), y: Int(win.editedFrame.origin.y),
                    w: Int(win.editedFrame.width), h: Int(win.editedFrame.height)
                ),
                layer: win.layer
            )
        }
    }

    func record(action: String, summary: String,
                before: [WindowSnapshot], after: [WindowSnapshot]) -> Entry {
        let ref = Self.shortUUID()

        var afterByWid: [UInt32: WindowSnapshot] = [:]
        for snap in after { afterByWid[snap.wid] = snap }

        var moved: [MovedWindow] = []
        for b in before {
            guard let a = afterByWid[b.wid] else { continue }
            let frameChanged = b.frame.x != a.frame.x || b.frame.y != a.frame.y
                || b.frame.w != a.frame.w || b.frame.h != a.frame.h
            let layerChanged = b.layer != a.layer
            if frameChanged || layerChanged {
                moved.append(MovedWindow(
                    wid: b.wid, app: b.app, title: b.title,
                    fromFrame: b.frame, toFrame: a.frame,
                    fromLayer: b.layer, toLayer: a.layer
                ))
            }
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let entry = Entry(
            ref: ref, action: action,
            timestamp: iso.string(from: Date()),
            summary: summary,
            before: before, after: after, moved: moved
        )

        let compactEncoder = JSONEncoder()
        compactEncoder.outputFormatting = [.sortedKeys]
        if let data = try? compactEncoder.encode(entry),
           var line = String(data: data, encoding: .utf8) {
            line += "\n"
            if let lineData = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: Self.logFileURL.path) {
                    if let fh = try? FileHandle(forWritingTo: Self.logFileURL) {
                        fh.seekToEndOfFile()
                        fh.write(lineData)
                        fh.closeFile()
                    }
                } else {
                    try? lineData.write(to: Self.logFileURL)
                }
            }
        }

        DiagnosticLog.shared.info("[ScreenMapAction] \(ref) \(action): \(summary) (\(moved.count) moved)")
        lastEntry = entry
        return entry
    }

    func lastEntryJSON() -> String? {
        guard let entry = lastEntry else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entry) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func verify() {
        guard let last = lastEntry else { return }
        let intendedByWid: [UInt32: WindowSnapshot] = Dictionary(
            last.after.map { ($0.wid, $0) }, uniquingKeysWith: { _, b in b }
        )
        guard !intendedByWid.isEmpty else { return }

        guard let rawList = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return }

        var actual: [WindowSnapshot] = []
        var drifted: [MovedWindow] = []

        for info in rawList {
            guard let wid = info[kCGWindowNumber as String] as? UInt32,
                  let intended = intendedByWid[wid],
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let cgX = bounds["X"] as? CGFloat,
                  let cgY = bounds["Y"] as? CGFloat,
                  let cgW = bounds["Width"] as? CGFloat,
                  let cgH = bounds["Height"] as? CGFloat else { continue }

            let snap = WindowSnapshot(
                wid: wid, app: intended.app, title: intended.title,
                frame: .init(x: Int(cgX), y: Int(cgY), w: Int(cgW), h: Int(cgH)),
                layer: intended.layer
            )
            actual.append(snap)

            let i = intended.frame
            let a = snap.frame
            if i.x != a.x || i.y != a.y || i.w != a.w || i.h != a.h {
                drifted.append(MovedWindow(
                    wid: wid, app: intended.app, title: intended.title,
                    fromFrame: intended.frame, toFrame: a,
                    fromLayer: intended.layer, toLayer: intended.layer
                ))
            }
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let summary = drifted.isEmpty
            ? "Verified \(actual.count) windows — all match"
            : "Verified \(actual.count) windows — \(drifted.count) drifted"

        let entry = Entry(
            ref: last.ref, action: "verify",
            timestamp: iso.string(from: Date()),
            summary: summary,
            before: last.after, after: actual, moved: drifted
        )

        let compactEncoder = JSONEncoder()
        compactEncoder.outputFormatting = [.sortedKeys]
        if let data = try? compactEncoder.encode(entry),
           var line = String(data: data, encoding: .utf8) {
            line += "\n"
            if let lineData = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: Self.logFileURL.path) {
                    if let fh = try? FileHandle(forWritingTo: Self.logFileURL) {
                        fh.seekToEndOfFile()
                        fh.write(lineData)
                        fh.closeFile()
                    }
                } else {
                    try? lineData.write(to: Self.logFileURL)
                }
            }
        }

        DiagnosticLog.shared.info("[ScreenMapAction] verify \(last.ref): \(summary)")
    }
}

// MARK: - Screen Map Controller

final class ScreenMapController: ObservableObject {
    @Published var editor: ScreenMapEditorState?
    @Published var selectedWindowIds: Set<UInt32> = []
    @Published var flashMessage: String? = nil
    @Published var previewCaptures: [UInt32: NSImage] = [:]
    @Published var savedPositions: [UInt32: (pid: Int32, frame: WindowFrame)]? = nil
    @Published var isSearchActive: Bool = false
    @Published var searchHighlightIndex: Int = 0

    enum DisplayTransitionDirection {
        case left, right, none
    }
    @Published var displayTransition: DisplayTransitionDirection = .none

    var previewWindow: NSWindow? = nil
    private var previewGlobalMonitor: Any? = nil
    private var previewLocalMonitor: Any? = nil

    var onDismiss: (() -> Void)?

    // MARK: - Selection

    func isSelected(_ id: UInt32) -> Bool { selectedWindowIds.contains(id) }

    func selectSingle(_ id: UInt32) {
        navigateToWindowDisplay(id)
        selectedWindowIds = [id]
    }

    func toggleSelection(_ id: UInt32) {
        if selectedWindowIds.contains(id) {
            selectedWindowIds.remove(id)
        } else {
            selectedWindowIds.insert(id)
        }
    }

    func clearSelection() {
        selectedWindowIds = []
    }

    func selectNextWindow() {
        guard let ed = editor else { return }
        let wins = ed.focusedVisibleWindows.sorted(by: { $0.zIndex < $1.zIndex })
        guard !wins.isEmpty else { return }
        if selectedWindowIds.count == 1, let current = selectedWindowIds.first,
           let idx = wins.firstIndex(where: { $0.id == current }) {
            let next = wins[(idx + 1) % wins.count]
            selectedWindowIds = [next.id]
        } else {
            selectedWindowIds = [wins[0].id]
        }
        objectWillChange.send()
    }

    func selectPreviousWindow() {
        guard let ed = editor else { return }
        let wins = ed.focusedVisibleWindows.sorted(by: { $0.zIndex < $1.zIndex })
        guard !wins.isEmpty else { return }
        if selectedWindowIds.count == 1, let current = selectedWindowIds.first,
           let idx = wins.firstIndex(where: { $0.id == current }) {
            let prev = wins[(idx - 1 + wins.count) % wins.count]
            selectedWindowIds = [prev.id]
        } else {
            selectedWindowIds = [wins[wins.count - 1].id]
        }
        objectWillChange.send()
    }

    func selectAll() {
        guard let ed = editor else { return }
        let allIds = Set(ed.focusedVisibleWindows.map(\.id))
        selectedWindowIds = allIds
        flash("Selected \(allIds.count) windows")
        objectWillChange.send()
    }

    // MARK: - Search

    var searchHighlightedWindowId: UInt32? {
        guard isSearchActive, let ed = editor else { return nil }
        let results = ed.searchFilteredWindows
        guard !results.isEmpty else { return nil }
        let idx = max(0, min(searchHighlightIndex, results.count - 1))
        return results[idx].id
    }

    func openSearch() {
        isSearchActive = true
        searchHighlightIndex = 0
    }

    func closeSearch() {
        isSearchActive = false
        searchHighlightIndex = 0
        editor?.windowSearchQuery = ""
    }

    func searchSelectHighlighted() {
        guard let wid = searchHighlightedWindowId else { return }
        selectSingle(wid)
        // Direct hit (single result) → close search immediately
        if editor?.searchHasDirectHit == true {
            closeSearch()
        }
        // Multiple results → stay open, just select
    }

    /// Switch display focus to match a window's display, with directional animation
    func navigateToWindowDisplay(_ windowId: UInt32) {
        guard let ed = editor,
              let win = ed.windows.first(where: { $0.id == windowId }) else { return }
        let targetDisplay = win.displayIndex
        guard ed.focusedDisplayIndex != nil,
              ed.focusedDisplayIndex != targetDisplay else { return }

        let fromSpatial = ed.spatialNumber(for: ed.focusedDisplayIndex!)
        let toSpatial = ed.spatialNumber(for: targetDisplay)
        displayTransition = toSpatial > fromSpatial ? .right : .left

        ed.focusDisplay(targetDisplay)
        objectWillChange.send()

        // Clear transition after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.displayTransition = .none
        }
    }

    func focusWindowOnScreen(_ windowId: UInt32) {
        guard let ed = editor,
              let win = ed.windows.first(where: { $0.id == windowId }) else { return }
        if isSearchActive { closeSearch() }
        selectSingle(windowId)
        // Raise the target window and let it stay on top (don't re-activate Lattices)
        WindowTiler.focusWindow(wid: win.id, pid: win.pid)
        WindowTiler.highlightWindowById(wid: win.id)
    }

    func focusSelectedWindowOnScreen() {
        if isSearchActive, let wid = searchHighlightedWindowId {
            focusWindowOnScreen(wid)
        } else if selectedWindowIds.count == 1, let wid = selectedWindowIds.first {
            focusWindowOnScreen(wid)
        }
    }

    func searchNavigate(delta: Int) {
        guard let ed = editor else { return }
        let count = ed.searchFilteredWindows.count
        guard count > 0 else { return }
        searchHighlightIndex = (searchHighlightIndex + delta + count) % count
        objectWillChange.send()
    }

    // MARK: - Enter

    func enter() {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return }

        struct CGWin {
            let wid: UInt32; let pid: Int32; let app: String; let title: String
            let frame: CGRect; let layer: Int; let displayIndex: Int
            let isOnScreen: Bool
        }

        let screens = NSScreen.screens
        let primaryHeight = screens.first?.frame.height ?? 0

        func displayIndex(for frame: CGRect) -> Int {
            let centerX = frame.midX
            let centerY = frame.midY
            for (i, screen) in screens.enumerated() {
                let cgOriginY = primaryHeight - screen.frame.maxY
                let cgRect = CGRect(x: screen.frame.origin.x, y: cgOriginY,
                                    width: screen.frame.width, height: screen.frame.height)
                if cgRect.contains(CGPoint(x: centerX, y: centerY)) {
                    return i
                }
            }
            var bestIdx = 0
            var bestDist = CGFloat.infinity
            for (i, screen) in screens.enumerated() {
                let cgOriginY = primaryHeight - screen.frame.maxY
                let cgRect = CGRect(x: screen.frame.origin.x, y: cgOriginY,
                                    width: screen.frame.width, height: screen.frame.height)
                let dx = centerX - cgRect.midX
                let dy = centerY - cgRect.midY
                let dist = dx * dx + dy * dy
                if dist < bestDist { bestDist = dist; bestIdx = i }
            }
            return bestIdx
        }

        var ordered: [CGWin] = []
        for info in windowList {
            guard let wid = info[kCGWindowNumber as String] as? UInt32,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary else { continue }
            var rect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict, &rect) else { continue }
            guard rect.width >= 100 && rect.height >= 50 else { continue }
            let app = info[kCGWindowOwnerName as String] as? String ?? ""
            if app == "Lattices" || app == "lattices" || app == "Lattices" { continue }
            let pid = info[kCGWindowOwnerPID as String] as? Int32 ?? 0
            let title = info[kCGWindowName as String] as? String ?? ""
            let dIdx = displayIndex(for: rect)
            let onScreen = (info[kCGWindowIsOnscreen as String] as? Bool) ?? false
            ordered.append(CGWin(wid: wid, pid: pid, app: app, title: title, frame: rect, layer: layer, displayIndex: dIdx, isOnScreen: onScreen))
        }

        NSLog("[ScreenMap] enter: %d windows after filtering", ordered.count)

        // Iterative peeling PER DISPLAY
        func significantOverlap(_ a: CGRect, _ b: CGRect) -> Bool {
            let inter = a.intersection(b)
            guard !inter.isNull && inter.width > 0 && inter.height > 0 else { return false }
            let interArea = inter.width * inter.height
            let smallerArea = min(a.width * a.height, b.width * b.height)
            guard smallerArea > 0 else { return false }
            return interArea / smallerArea >= 0.15
        }

        var byDisplay: [Int: [Int]] = [:]
        for i in ordered.indices {
            byDisplay[ordered[i].displayIndex, default: []].append(i)
        }

        var layerAssignment = [Int: Int]()
        for (_, displayIndices) in byDisplay {
            var remaining = Set(displayIndices)
            var layer = 0
            while !remaining.isEmpty {
                var unoccluded: [Int] = []
                for i in remaining {
                    let frame = ordered[i].frame
                    let isOccluded = remaining.contains(where: { j in
                        j < i && significantOverlap(ordered[j].frame, frame)
                    })
                    if !isOccluded { unoccluded.append(i) }
                }
                if unoccluded.isEmpty {
                    for i in remaining { layerAssignment[i] = layer }
                    remaining.removeAll()
                    break
                }
                for i in unoccluded {
                    layerAssignment[i] = layer
                    remaining.remove(i)
                }
                layer += 1
            }
        }

        // Build tmux PID → context lookup from TmuxModel
        let latticesSessionRegex = try? NSRegularExpression(pattern: "\\[lattices:([^\\]]+)\\]")
        var tmuxPidLookup: [Int32: (command: String, paneTitle: String, session: String)] = [:]
        for session in TmuxModel.shared.sessions {
            for pane in session.panes {
                // Map pane PID and all child PIDs to this context
                tmuxPidLookup[Int32(pane.pid)] = (pane.currentCommand, pane.title, session.name)
            }
        }

        var mapWindows: [ScreenMapWindowEntry] = []
        for (i, win) in ordered.enumerated() {
            let assignedLayer = layerAssignment[i] ?? 0

            // Parse [lattices:session] from title
            var latticesSession: String?
            if let regex = latticesSessionRegex,
               let match = regex.firstMatch(in: win.title, range: NSRange(win.title.startIndex..., in: win.title)),
               let range = Range(match.range(at: 1), in: win.title) {
                latticesSession = String(win.title[range])
            }

            // Cross-reference with tmux — match by PID (window owner PID or child)
            let tmuxCtx = tmuxPidLookup[win.pid]
            // If no direct PID match, try looking up by lattices session name
            let tmuxBySession: (command: String, paneTitle: String, session: String)? = {
                guard let session = latticesSession else { return nil }
                guard tmuxCtx == nil else { return nil }
                for s in TmuxModel.shared.sessions where s.name == session {
                    if let active = s.panes.first(where: { $0.isActive }) {
                        return (active.currentCommand, active.title, s.name)
                    }
                }
                return nil
            }()
            let ctx = tmuxCtx ?? tmuxBySession

            mapWindows.append(ScreenMapWindowEntry(
                id: win.wid, pid: win.pid, app: win.app, title: win.title,
                originalFrame: win.frame, editedFrame: win.frame,
                zIndex: i, layer: assignedLayer, displayIndex: win.displayIndex,
                isOnScreen: win.isOnScreen,
                latticesSession: latticesSession ?? ctx?.session,
                tmuxCommand: ctx?.command,
                tmuxPaneTitle: ctx?.paneTitle
            ))
        }

        let totalLayers = (mapWindows.map(\.layer).max() ?? 0) + 1
        NSLog("[ScreenMap] Peeling complete: %d layers from %d windows across %d displays (tmux panes indexed: %d)", totalLayers, mapWindows.count, byDisplay.count, tmuxPidLookup.count)

        // Build display geometries
        var displayGeometries: [DisplayGeometry] = []
        for (i, screen) in screens.enumerated() {
            let cgOriginY = primaryHeight - screen.frame.maxY
            let cgRect = CGRect(x: screen.frame.origin.x, y: cgOriginY,
                                width: screen.frame.width, height: screen.frame.height)
            displayGeometries.append(DisplayGeometry(index: i, cgRect: cgRect, label: screen.localizedName))
        }

        let newEditor = ScreenMapEditorState(windows: mapWindows, displays: displayGeometries)

        // Populate layer names from workspace config
        if let layers = WorkspaceManager.shared.config?.layers {
            for (i, layer) in layers.enumerated() {
                newEditor.layerNames[i] = layer.label
            }
        }

        // Auto-focus the display where the mouse cursor is
        if screens.count > 1 {
            let mouseLocation = NSEvent.mouseLocation
            let mouseCG = CGPoint(x: mouseLocation.x, y: primaryHeight - mouseLocation.y)
            for disp in displayGeometries {
                if disp.cgRect.contains(mouseCG) {
                    newEditor.focusedDisplayIndex = disp.index
                    break
                }
            }
        }

        editor = newEditor
        selectedWindowIds = []
    }

    /// Re-snapshot, preserving display/layer context
    func refresh() {
        let savedDisplay = editor?.focusedDisplayIndex
        let savedLayers = editor?.selectedLayers ?? []
        enter()
        if let ed = editor {
            ed.focusedDisplayIndex = savedDisplay
            ed.selectedLayers = savedLayers
        }
    }

    // MARK: - Key Handler

    func handleKey(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) -> Bool {
        let diag = DiagnosticLog.shared
        diag.info("[ScreenMap] key: \(keyCode)")

        // Tiling mode intercepts keys before anything else
        if editor?.isTilingMode == true {
            switch keyCode {
            case 53: // Escape — always dismiss
                onDismiss?()
                return true
            case 123: // ← → left
                tileSelectedWindowInEditor(to: .left)
                return true
            case 124: // → → right
                tileSelectedWindowInEditor(to: .right)
                return true
            case 126: // ↑ → top (Shift = maximize)
                if modifiers.contains(.shift) {
                    tileSelectedWindowInEditor(to: .maximize)
                } else {
                    tileSelectedWindowInEditor(to: .top)
                }
                return true
            case 125: // ↓ → bottom
                tileSelectedWindowInEditor(to: .bottom)
                return true
            case 8: // c → center
                tileSelectedWindowInEditor(to: .center)
                return true
            case 18: // 1 → topLeft
                tileSelectedWindowInEditor(to: .topLeft)
                return true
            case 19: // 2 → topRight
                tileSelectedWindowInEditor(to: .topRight)
                return true
            case 20: // 3 → bottomLeft
                tileSelectedWindowInEditor(to: .bottomLeft)
                return true
            case 21: // 4 → bottomRight
                tileSelectedWindowInEditor(to: .bottomRight)
                return true
            case 23: // 5 → leftThird
                tileSelectedWindowInEditor(to: .leftThird)
                return true
            case 22: // 6 → centerThird
                tileSelectedWindowInEditor(to: .centerThird)
                return true
            case 26: // 7 → rightThird
                tileSelectedWindowInEditor(to: .rightThird)
                return true
            default:
                exitTilingMode()
                flash("Tiling cancelled")
                return true
            }
        }

        // Ctrl+Option direct tiling shortcuts (always active, single selection)
        if modifiers.contains([.control, .option]) && selectedWindowIds.count == 1 {
            switch keyCode {
            case 123: // Ctrl+Opt+← → left
                tileSelectedWindowInEditor(to: .left)
                return true
            case 124: // Ctrl+Opt+→ → right
                tileSelectedWindowInEditor(to: .right)
                return true
            case 126: // Ctrl+Opt+↑ → top (+ Shift = maximize)
                if modifiers.contains(.shift) {
                    tileSelectedWindowInEditor(to: .maximize)
                } else {
                    tileSelectedWindowInEditor(to: .top)
                }
                return true
            case 125: // Ctrl+Opt+↓ → bottom
                tileSelectedWindowInEditor(to: .bottom)
                return true
            default:
                break
            }
        }

        // Search mode intercepts keys before normal handling
        if isSearchActive {
            switch keyCode {
            case 53: // Escape — always dismiss
                onDismiss?()
                return true
            case 36: // Enter → select or focus
                if modifiers.contains(.command) {
                    focusSelectedWindowOnScreen()
                } else {
                    searchSelectHighlighted()
                }
                return true
            case 125: // ↓ → next result
                searchNavigate(delta: 1)
                return true
            case 126: // ↑ → previous result
                searchNavigate(delta: -1)
                return true
            default:
                // Let other keys pass through to the text field
                return false
            }
        }

        switch keyCode {
        case 53: // Escape — always dismiss
            diag.info("[ScreenMap] exit")
            onDismiss?()
            return true

        case 36: // Enter
            if modifiers.contains(.command) {
                // ⌘↩ → focus selected window on screen
                focusSelectedWindowOnScreen()
            } else {
                // ↩ → apply edits
                if editor?.isPreviewing == true { endPreview() }
                diag.info("[ScreenMap] apply edits")
                applyEdits()
            }
            return true

        // MARK: Right hand — Navigation

        case 4: // h → previous display
            if let ed = editor, ed.displays.count > 1 {
                ed.cyclePreviousDisplay()
                let label = ed.focusedDisplay?.label ?? "All displays"
                flash(label)
                objectWillChange.send()
            }
            return true

        case 37: // l → next display
            if let ed = editor, ed.displays.count > 1 {
                ed.cycleNextDisplay()
                let label = ed.focusedDisplay?.label ?? "All displays"
                flash(label)
                objectWillChange.send()
            }
            return true

        case 38: // j → next layer
            editor?.cycleLayer()
            diag.info("[ScreenMap] layer → \(editor?.layerLabel ?? "nil")")
            objectWillChange.send()
            return true

        case 40: // k → previous layer
            editor?.cyclePreviousLayer()
            diag.info("[ScreenMap] layer → \(editor?.layerLabel ?? "nil")")
            objectWillChange.send()
            return true

        case 45: // n → next window
            selectNextWindow()
            return true

        case 35: // p → previous window
            selectPreviousWindow()
            return true

        case 48: // Tab → cycle windows
            if modifiers.contains(.shift) {
                selectPreviousWindow()
            } else {
                selectNextWindow()
            }
            return true

        case 33: // [ → move to previous layer
            if let ed = editor {
                for wid in selectedWindowIds {
                    if let idx = ed.windows.firstIndex(where: { $0.id == wid }) {
                        let oldLayer = ed.windows[idx].layer
                        let newLayer = max(0, oldLayer - 1)
                        ed.reassignLayer(windowId: wid, toLayer: newLayer, fitToAvailable: true)
                    }
                }
                objectWillChange.send()
            }
            return true

        case 30: // ] → move to next layer
            if let ed = editor {
                for wid in selectedWindowIds {
                    if let idx = ed.windows.firstIndex(where: { $0.id == wid }) {
                        let oldLayer = ed.windows[idx].layer
                        ed.reassignLayer(windowId: wid, toLayer: oldLayer + 1, fitToAvailable: true)
                    }
                }
                objectWillChange.send()
            }
            return true

        // MARK: Left hand — Actions

        case 1: // s → spread
            smartSpreadLayer()
            return true

        case 14: // e → expose
            exposeLayer()
            return true

        case 17: // t → tile (1 window = tiling mode, otherwise bulk tile)
            if selectedWindowIds.count == 1 {
                enterTilingMode()
            } else {
                tileLayer()
            }
            return true

        case 2: // d → distribute
            distributeVisible()
            return true

        case 15: // r → reset zoom/pan
            editor?.resetZoomPan()
            flash("Fit all")
            return true

        case 5: // g → grow to fill
            fitAvailableSpace()
            return true

        case 3: // f → flatten
            flattenLayers()
            return true

        case 8: // c → consolidate
            consolidateLayers()
            return true

        case 9: // v → toggle preview
            previewLayer()
            return true

        case 0: // a → select all
            selectAll()
            return true

        case 7: // x → deselect all
            clearSelection()
            flash("Deselected")
            return true

        case 6: // z → discard edits
            if let ed = editor, ed.pendingEditCount > 0 {
                ed.discardEdits()
                flash("Edits discarded")
            } else {
                flash("No edits to discard")
            }
            return true

        case 29: // 0 → fit all (secondary)
            editor?.resetZoomPan()
            flash("Fit all")
            return true

        case 123: // ← previous display (secondary)
            if let ed = editor, ed.displays.count > 1 {
                ed.cyclePreviousDisplay()
                let label = ed.focusedDisplay?.label ?? "All displays"
                flash(label)
                objectWillChange.send()
            }
            return true

        case 124: // → next display (secondary)
            if let ed = editor, ed.displays.count > 1 {
                ed.cycleNextDisplay()
                let label = ed.focusedDisplay?.label ?? "All displays"
                flash(label)
                objectWillChange.send()
            }
            return true

        case 44: // / → open window search
            openSearch()
            return true

        case 12: // q → dismiss screen map
            if editor?.isPreviewing == true { endPreview() }
            WindowBezel.shared.dismiss()
            onDismiss?()
            return true

        default:
            return true
        }
    }

    // MARK: - Actions

    func applyEdits() {
        guard let ed = editor else { return }
        let pendingEdits = ed.windows.filter(\.hasEdits)
        guard !pendingEdits.isEmpty else {
            flash("No changes to apply")
            return
        }

        var positions: [UInt32: (pid: Int32, frame: WindowFrame)] = [:]
        for win in pendingEdits {
            positions[win.id] = (pid: win.pid, frame: WindowFrame(
                x: Double(win.originalFrame.origin.x), y: Double(win.originalFrame.origin.y),
                w: Double(win.originalFrame.width), h: Double(win.originalFrame.height)
            ))
        }
        savedPositions = positions

        let sorted = pendingEdits.sorted(by: { $0.layer > $1.layer })
        let allMoves = sorted.map { (wid: $0.id, pid: $0.pid, frame: $0.editedFrame) }
        NSLog("[ScreenMap] Applying %d edits", allMoves.count)

        let actionLog = ed.actionLog

        // Apply AX changes (no hide/show — Screen Map stays visible)
        WindowTiler.batchMoveWindows(allMoves)

        // Commit edited frames as new originals so the map doesn't reload
        for i in ed.windows.indices {
            ed.windows[i].originalFrame = ed.windows[i].editedFrame
        }
        ed.objectWillChange.send()
        objectWillChange.send()

        // Verify in background — if anything drifted, retry once then refresh
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let drifted = WindowTiler.verifyMoves(allMoves)
            if !drifted.isEmpty {
                NSLog("[ScreenMap] %d/%d windows drifted, retrying", drifted.count, allMoves.count)
                WindowTiler.batchMoveWindows(drifted)
            }
            actionLog.verify()
        }

        let noun = pendingEdits.count == 1 ? "edit" : "edits"
        flash("Applied \(pendingEdits.count) \(noun)")
    }

    func applyEditsFromButton() {
        if editor?.isPreviewing == true { endPreview() }
        applyEdits()
    }

    func exitScreenMap() {
        if editor?.isPreviewing == true { endPreview() }
        WindowBezel.shared.dismiss()
        if let ed = editor, ed.pendingEditCount > 0 {
            ed.discardEdits()
            flash("Edits discarded")
        } else {
            onDismiss?()
        }
    }

    func tileLayer() {
        guard let ed = editor else { return }
        let before = ed.actionLog.snapshot(ed.windows)
        let count = ed.autoTileLayer()
        let after = ed.actionLog.snapshot(ed.windows)
        let summary: String
        if count >= 2 { summary = "Tiled \(count) windows" }
        else if count == 1 { summary = "Only 1 window in layer" }
        else { summary = "Select a single layer first" }
        let entry = ed.actionLog.record(action: "tile", summary: summary, before: before, after: after)
        ed.lastActionRef = entry.ref
        flash("\(summary)  [\(entry.ref)]")
        objectWillChange.send()
    }

    func exposeLayer() {
        guard let ed = editor else { return }
        let before = ed.actionLog.snapshot(ed.windows)
        let count = ed.exposeLayer()
        let after = ed.actionLog.snapshot(ed.windows)
        let summary: String
        if count >= 2 { summary = "Exposed \(count) windows" }
        else if count == 1 { summary = "Only 1 window in layer" }
        else { summary = "Select a single layer first" }
        let entry = ed.actionLog.record(action: "expose", summary: summary, before: before, after: after)
        ed.lastActionRef = entry.ref
        flash("\(summary)  [\(entry.ref)]")
        objectWillChange.send()
    }

    func smartSpreadLayer() {
        guard let ed = editor else { return }
        let before = ed.actionLog.snapshot(ed.windows)
        let count = ed.smartSpreadLayer()
        let after = ed.actionLog.snapshot(ed.windows)
        let summary: String
        if count >= 2 { summary = "Spread \(count) windows" }
        else if count == 1 { summary = "Only 1 window in layer" }
        else { summary = "Select a single layer first" }
        let entry = ed.actionLog.record(action: "spread", summary: summary, before: before, after: after)
        ed.lastActionRef = entry.ref
        flash("\(summary)  [\(entry.ref)]")
        objectWillChange.send()
    }

    func distributeVisible() {
        guard let ed = editor else { return }
        let before = ed.actionLog.snapshot(ed.windows)
        let count = ed.distributeLayer()
        let after = ed.actionLog.snapshot(ed.windows)
        let summary: String
        if count >= 2 { summary = "Distributed \(count) windows" }
        else if count == 1 { summary = "Only 1 window to distribute" }
        else { summary = "No visible windows to distribute" }
        let entry = ed.actionLog.record(action: "distribute", summary: summary, before: before, after: after)
        ed.lastActionRef = entry.ref
        flash("\(summary)  [\(entry.ref)]")
        objectWillChange.send()
    }

    func fitAvailableSpace() {
        guard let ed = editor else { return }
        let before = ed.actionLog.snapshot(ed.windows)
        let count = ed.fitAvailableSpace()
        let after = ed.actionLog.snapshot(ed.windows)
        let summary: String
        if count >= 2 { summary = "Grew \(count) windows to fill" }
        else if count == 1 { summary = "Grew 1 window to fill" }
        else { summary = "No windows to grow" }
        let entry = ed.actionLog.record(action: "fit", summary: summary, before: before, after: after)
        ed.lastActionRef = entry.ref
        flash("\(summary)  [\(entry.ref)]")
        objectWillChange.send()
    }

    func consolidateLayers() {
        guard let ed = editor else { return }
        let before = ed.actionLog.snapshot(ed.windows)
        let result = ed.consolidateLayers()
        let after = ed.actionLog.snapshot(ed.windows)
        let summary = result.old == result.new
            ? "Already optimal"
            : "Consolidated \(result.old) → \(result.new) layers"
        let entry = ed.actionLog.record(action: "merge", summary: summary, before: before, after: after)
        ed.lastActionRef = entry.ref
        flash("\(summary)  [\(entry.ref)]")
        objectWillChange.send()
    }

    func flattenLayers() {
        guard let ed = editor else { return }
        let before = ed.actionLog.snapshot(ed.windows)
        let result = ed.flattenSelectedLayers()
        let after = ed.actionLog.snapshot(ed.windows)
        let summary: String
        if let result = result {
            summary = "Merged \(result.count) windows into L\(result.target)"
        } else {
            summary = "Select 2+ layers to flatten"
        }
        let entry = ed.actionLog.record(action: "flatten", summary: summary, before: before, after: after)
        ed.lastActionRef = entry.ref
        flash("\(summary)  [\(entry.ref)]")
        objectWillChange.send()
    }

    // MARK: - Per-Window Tiling

    func tileSelectedWindowInEditor(to position: TilePosition) {
        guard let ed = editor, selectedWindowIds.count == 1,
              let winId = selectedWindowIds.first,
              let idx = ed.windows.firstIndex(where: { $0.id == winId }),
              let display = ed.displays.first(where: { $0.index == ed.windows[idx].displayIndex })
        else { return }
        ed.windows[idx].editedFrame = WindowTiler.tileFrame(for: position, inDisplay: display.cgRect)
        ed.isTilingMode = false
        ed.objectWillChange.send(); objectWillChange.send()
        flash(position.label)
    }

    func tileSelectedWindowInEditor(fractions: (CGFloat, CGFloat, CGFloat, CGFloat), label: String) {
        guard let ed = editor, selectedWindowIds.count == 1,
              let winId = selectedWindowIds.first,
              let idx = ed.windows.firstIndex(where: { $0.id == winId }),
              let display = ed.displays.first(where: { $0.index == ed.windows[idx].displayIndex })
        else { return }
        ed.windows[idx].editedFrame = WindowTiler.tileFrame(fractions: fractions, inDisplay: display.cgRect)
        ed.isTilingMode = false
        ed.objectWillChange.send(); objectWillChange.send()
        flash(label)
    }

    func applyLayout(name: String) {
        guard let ed = editor else { return }
        let wm = WorkspaceManager.shared
        guard let layout = wm.gridLayouts[name] else {
            flash("Layout '\(name)' not found")
            return
        }

        var matched = 0
        for spec in layout.windows {
            // Find matching window(s) by app name (case-insensitive substring)
            let appLower = spec.app.lowercased()
            let candidates = ed.windows.indices.filter { idx in
                let win = ed.windows[idx]
                let nameMatch = win.app.lowercased().contains(appLower)
                if let titleFilter = spec.title {
                    return nameMatch && win.title.lowercased().contains(titleFilter.lowercased())
                }
                return nameMatch
            }
            guard let idx = candidates.first else { continue }

            // Resolve tile position (check presets first, then built-in)
            guard let fractions = wm.resolveTileFractions(spec.tile) else { continue }

            // Resolve display (spatial number → displayIndex)
            let display: DisplayGeometry
            if let spatialNum = spec.display {
                let order = ed.spatialDisplayOrder
                if spatialNum >= 1 && spatialNum <= order.count {
                    display = order[spatialNum - 1]
                } else {
                    display = ed.displays.first(where: { $0.index == ed.windows[idx].displayIndex }) ?? ed.displays[0]
                }
            } else {
                display = ed.displays.first(where: { $0.index == ed.windows[idx].displayIndex }) ?? ed.displays[0]
            }

            ed.windows[idx].editedFrame = WindowTiler.tileFrame(fractions: fractions, inDisplay: display.cgRect)
            // Update display index if layout spec moves to a different display
            if let spatialNum = spec.display {
                let order = ed.spatialDisplayOrder
                if spatialNum >= 1 && spatialNum <= order.count {
                    let moved = ed.windows[idx]
                    ed.windows[idx] = ScreenMapWindowEntry(
                        id: moved.id, pid: moved.pid,
                        app: moved.app, title: moved.title,
                        originalFrame: moved.originalFrame,
                        editedFrame: moved.editedFrame,
                        zIndex: moved.zIndex, layer: moved.layer,
                        displayIndex: order[spatialNum - 1].index,
                        isOnScreen: moved.isOnScreen,
                        latticesSession: moved.latticesSession,
                        tmuxCommand: moved.tmuxCommand,
                        tmuxPaneTitle: moved.tmuxPaneTitle
                    )
                }
            }
            matched += 1
        }

        ed.objectWillChange.send(); objectWillChange.send()
        flash("Layout '\(name)': \(matched)/\(layout.windows.count) matched")
    }

    func enterTilingMode() {
        guard let ed = editor, selectedWindowIds.count == 1 else { return }
        ed.isTilingMode = true
        ed.objectWillChange.send(); objectWillChange.send()
    }

    func exitTilingMode() {
        guard let ed = editor else { return }
        ed.isTilingMode = false
        ed.objectWillChange.send(); objectWillChange.send()
    }

    // MARK: - Preview

    func previewLayer() {
        guard let ed = editor else { return }
        if ed.isPreviewing { endPreview(); return }

        let visible = ed.focusedVisibleWindows
        guard !visible.isEmpty else { flash("No windows to preview"); return }

        var captures: [UInt32: NSImage] = [:]
        for win in visible {
            if let cgImage = CGWindowListCreateImage(
                .null, .optionIncludingWindow, CGWindowID(win.id),
                [.boundsIgnoreFraming, .bestResolution]
            ) {
                captures[win.id] = NSImage(cgImage: cgImage,
                    size: NSSize(width: win.editedFrame.width, height: win.editedFrame.height))
            }
        }
        previewCaptures = captures
        ed.isPreviewing = true
        objectWillChange.send()
    }

    func showPreviewWindow(contentView: NSView, frame: NSRect) {
        let window = NSWindow(
            contentRect: frame, styleMask: .borderless,
            backing: .buffered, defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        window.hasShadow = false
        window.contentView = contentView
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
        previewWindow = window

        previewGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.endPreview()
        }
        previewLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.endPreview()
            return nil
        }
    }

    func endPreview() {
        guard editor?.isPreviewing == true else { return }
        previewWindow?.orderOut(nil)
        previewWindow = nil
        if let m = previewGlobalMonitor { NSEvent.removeMonitor(m) }
        if let m = previewLocalMonitor { NSEvent.removeMonitor(m) }
        previewGlobalMonitor = nil
        previewLocalMonitor = nil
        previewCaptures = [:]
        editor?.isPreviewing = false
        objectWillChange.send()
    }

    // MARK: - Flash

    func flash(_ message: String) {
        flashMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            if self?.flashMessage == message { self?.flashMessage = nil }
        }
    }
}

// MARK: - Bezel Panel (custom NSPanel)

/// Panel that stays behind its target window and supports dragging both together.
private class BezelPanel: NSPanel {
    var targetWid: UInt32 = 0
    var targetPid: Int32 = 0
    private var dragOrigin: NSPoint?
    private var panelOriginAtDrag: NSPoint?
    private var targetOriginAtDrag: CGPoint?

    // Never come to front on click — stay behind target
    override func mouseDown(with event: NSEvent) {
        let loc = event.locationInWindow
        dragOrigin = NSEvent.mouseLocation
        panelOriginAtDrag = frame.origin

        // Read current target window position (CG coords, top-left origin)
        if let axWin = WindowTiler.findAXWindowByFrame(wid: targetWid, pid: targetPid) {
            var posRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWin, kAXPositionAttribute as CFString, &posRef)
            var pos = CGPoint.zero
            if let pv = posRef { AXValueGetValue(pv as! AXValue, .cgPoint, &pos) }
            targetOriginAtDrag = pos
        }

        // Keep behind target — don't call super which would order front
        _ = loc  // suppress unused warning
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart = dragOrigin,
              let panelStart = panelOriginAtDrag else { return }

        let current = NSEvent.mouseLocation
        let dx = current.x - dragStart.x
        let dy = current.y - dragStart.y

        // Move the bezel panel
        setFrameOrigin(NSPoint(x: panelStart.x + dx, y: panelStart.y + dy))

        // Move the target window via AX (CG coords: top-left origin, so dy is inverted)
        if let targetStart = targetOriginAtDrag,
           let axWin = WindowTiler.findAXWindowByFrame(wid: targetWid, pid: targetPid) {
            var newPos = CGPoint(x: targetStart.x + dx, y: targetStart.y - dy)
            let posVal: AXValue? = AXValueCreate(.cgPoint, &newPos)
            if let pv = posVal {
                AXUIElementSetAttributeValue(axWin, kAXPositionAttribute as CFString, pv)
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        dragOrigin = nil
        panelOriginAtDrag = nil
        targetOriginAtDrag = nil
    }
}

// MARK: - Window Bezel (standalone companion window)

/// Persistent chromeless companion window that frames a target window with info.
/// Singleton — reuses a single NSPanel, repositions/updates content for each target.
final class WindowBezel {
    static let shared = WindowBezel()

    private var panel: BezelPanel?
    private var currentTargetWid: UInt32?

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Show or update bezel for a known ScreenMapWindowEntry.
    func show(for win: ScreenMapWindowEntry, editor: ScreenMapEditorState) {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let primaryHeight = screens.first!.frame.height
        let targetScreen: NSScreen
        if win.displayIndex < screens.count {
            targetScreen = screens[win.displayIndex]
        } else {
            targetScreen = screens.first!
        }

        let targetWindowNumber = Self.findNSWindowNumber(forCGWindowID: win.id)

        let displayName = editor.displays.first(where: { $0.index == win.displayIndex })?.label ?? "Display \(win.displayIndex)"
        let displayNumber = editor.spatialNumber(for: win.displayIndex)
        let layerName = editor.layerDisplayName(for: win.layer)
        let windowsOnDisplay = editor.windows.filter { $0.displayIndex == win.displayIndex }.count
        let layersOnDisplay = editor.layersForDisplay(win.displayIndex).count

        let cgFrame = win.editedFrame
        let screenNS = targetScreen.frame

        let winLocalX = cgFrame.origin.x - screenNS.origin.x
        let winLocalY = (primaryHeight - cgFrame.origin.y - cgFrame.height) - screenNS.origin.y

        // Detect flush edges
        let tolerance: CGFloat = 10
        let flush = ShowOnScreenBezelView.FlushEdges(
            top: (screenNS.height - (winLocalY + cgFrame.height)) < tolerance,
            bottom: winLocalY < tolerance,
            left: winLocalX < tolerance,
            right: (screenNS.width - (winLocalX + cgFrame.width)) < tolerance
        )

        // Shelf placement: prefer non-flush edges
        let bezelH: CGFloat = 48
        let spaceBelow = winLocalY - bezelH
        let spaceAbove = screenNS.height - (winLocalY + cgFrame.height) - bezelH
        let spaceLeft = winLocalX
        let spaceRight = screenNS.width - (winLocalX + cgFrame.width)

        let placement: ShowOnScreenBezelView.LabelPlacement
        if !flush.bottom && spaceBelow >= 0 {
            placement = .below
        } else if !flush.top && spaceAbove >= 0 {
            placement = .above
        } else if !flush.right && spaceRight >= 200 {
            placement = .right
        } else if !flush.left && spaceLeft >= 200 {
            placement = .left
        } else if spaceBelow >= 0 {
            placement = .below
        } else if spaceAbove >= 0 {
            placement = .above
        } else {
            placement = .right
        }

        // Compute tight frame
        let edgePx: CGFloat = 5
        let shelfPx: CGFloat = 40
        let inL: CGFloat = flush.left ? 0 : edgePx
        let inR: CGFloat = flush.right ? 0 : edgePx
        let inT: CGFloat = flush.top ? 0 : edgePx
        let inB: CGFloat = flush.bottom ? 0 : edgePx

        var fX = winLocalX - inL
        var fY = winLocalY - inB
        var fW = cgFrame.width + inL + inR
        var fH = cgFrame.height + inT + inB

        switch placement {
        case .below:  fY -= shelfPx; fH += shelfPx
        case .above:  fH += shelfPx
        case .right:  fW += 200
        case .left:   fX -= 200; fW += 200
        }

        let tightFrame = NSRect(
            x: screenNS.origin.x + fX,
            y: screenNS.origin.y + fY,
            width: fW,
            height: fH
        )

        let localWinFrame = CGRect(
            x: winLocalX - fX,
            y: winLocalY - fY,
            width: cgFrame.width,
            height: cgFrame.height
        )
        let tightSize = CGSize(width: tightFrame.width, height: tightFrame.height)

        // Capture window content for screenshot tool compositing
        let windowSnapshot: NSImage? = {
            guard let cgImage = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                win.id,
                [.bestResolution, .boundsIgnoreFraming]
            ) else { return nil }
            return NSImage(cgImage: cgImage, size: NSSize(width: cgFrame.width, height: cgFrame.height))
        }()

        let bezelView = ShowOnScreenBezelView(
            appName: win.app,
            windowTitle: win.title,
            displayName: displayName,
            displayNumber: displayNumber,
            layerName: layerName,
            windowSize: "\(Int(cgFrame.width))×\(Int(cgFrame.height))",
            windowsOnDisplay: windowsOnDisplay,
            layersOnDisplay: layersOnDisplay,
            windowLocalFrame: localWinFrame,
            screenSize: tightSize,
            labelPlacement: placement,
            flush: flush,
            windowSnapshot: windowSnapshot
        )

        let hostingView = NSHostingView(rootView: bezelView)
        let isNewWindow = (panel == nil)

        if panel == nil {
            let p = BezelPanel(
                contentRect: tightFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.isOpaque = false
            p.backgroundColor = .clear
            p.level = .normal
            p.hasShadow = true
            p.hidesOnDeactivate = false
            p.isReleasedWhenClosed = false
            p.isMovable = false  // we handle dragging ourselves
            p.appearance = nil
            panel = p
        }

        guard let p = panel else { return }

        p.contentView = hostingView
        p.targetWid = win.id
        p.targetPid = win.pid
        currentTargetWid = win.id

        if isNewWindow {
            // First show: position and fade in
            p.setFrame(tightFrame, display: false)
            p.alphaValue = 0

            if let targetWinNum = targetWindowNumber {
                p.orderFrontRegardless()
                p.order(.below, relativeTo: targetWinNum)
            } else {
                p.orderFrontRegardless()
            }

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                p.animator().alphaValue = 1.0
            }
        } else {
            // Reuse: animate to new position/size
            if let targetWinNum = targetWindowNumber {
                p.order(.below, relativeTo: targetWinNum)
            }

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                p.animator().setFrame(tightFrame, display: true)
                p.animator().alphaValue = 1.0
            }
        }
    }

    /// Toggle bezel for the frontmost window (global hotkey).
    static func showBezelForFrontmostWindow() {
        if shared.isVisible {
            shared.dismiss()
            return
        }

        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.bundleIdentifier != "com.arach.lattices" else { return }

        let pid = frontApp.processIdentifier

        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return }

        var targetInfo: [String: Any]?
        for info in infoList {
            guard let wPid = info[kCGWindowOwnerPID as String] as? Int32,
                  wPid == pid,
                  let wLayer = info[kCGWindowLayer as String] as? Int,
                  wLayer == 0 else { continue }
            if let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
               let w = bounds["Width"], let h = bounds["Height"],
               w > 50, h > 50 {
                targetInfo = info
                break
            }
        }
        guard let info = targetInfo,
              let wid = info[kCGWindowNumber as String] as? UInt32 else { return }

        let ctrl = ScreenMapController()
        ctrl.enter()
        guard let ed = ctrl.editor,
              let win = ed.windows.first(where: { $0.id == wid }) else { return }

        shared.show(for: win, editor: ed)
    }

    func dismiss() {
        guard let p = panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            p.animator().alphaValue = 0
        }) { [weak self] in
            p.orderOut(nil)
            self?.panel = nil
            self?.currentTargetWid = nil
        }
    }

    private static func findNSWindowNumber(forCGWindowID cgWid: UInt32) -> Int? {
        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }
        for info in infoList {
            guard let wid = info[kCGWindowNumber as String] as? UInt32,
                  wid == cgWid else { continue }
            return Int(wid)
        }
        return nil
    }
}
