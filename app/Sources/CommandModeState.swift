import AppKit
import Foundation

// MARK: - Phase

enum CommandModePhase: Equatable {
    case idle
    case inventory
    case desktopInventory
    case executing(String)
}

// MARK: - Inventory Snapshot

struct CommandModeInventory {
    struct Item {
        let name: String
        let group: String       // "Layer: X", "Group: Y", "Orphan"
        let status: Status
        let paneCount: Int
        let tileHint: String?   // "left", "right", etc.
    }
    enum Status { case running, attached, stopped }

    let activeLayer: String?
    let layerCount: Int
    let items: [Item]
}

// MARK: - Chord

struct Chord {
    let key: String         // display label e.g. "a", "1"
    let keyCode: UInt16
    let label: String       // e.g. "tile all"
    let action: () -> Void
}

// MARK: - Desktop Inventory Mode

enum DesktopInventoryMode: Equatable {
    case browsing
    case tiling       // t → tile picker
    case gridPreview  // s → preview grid layout before applying
    case screenMap    // m → interactive screen map editor
}

// MARK: - Display Geometry

struct DisplayGeometry {
    let index: Int
    let cgRect: CGRect   // in unified CG coords (top-left origin)
    let label: String    // "Display 0", "Display 1"
}

// MARK: - Screen Map Editor

struct ScreenMapWindow: Identifiable {
    let id: UInt32              // CGWindowID
    let pid: Int32              // for AX API
    let app: String
    let title: String
    let originalFrame: CGRect   // frozen at snapshot time
    var editedFrame: CGRect     // mutated during drag
    let zIndex: Int             // 0 = frontmost
    var layer: Int              // assigned by iterative peeling (per-display)
    let displayIndex: Int       // which monitor this window belongs to
    var hasEdits: Bool { originalFrame != editedFrame }
}

final class ScreenMapEditorState: ObservableObject {
    @Published var windows: [ScreenMapWindow]
    @Published var selectedLayers: Set<Int> = [0]  // empty = show all
    @Published var draggingWindowId: UInt32? = nil
    @Published var isPreviewing: Bool = false
    @Published var lastActionRef: String? = nil
    @Published var zoomLevel: CGFloat = 1.0   // 1.0 = fit-all
    @Published var panOffset: CGPoint = .zero  // canvas-local pixels

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

    init(windows: [ScreenMapWindow], displays: [DisplayGeometry] = []) {
        self.windows = windows
        self.displays = displays
    }

    /// Number of distinct layers
    var layerCount: Int {
        (windows.map(\.layer).max() ?? 0) + 1
    }

    /// Window count for a specific layer (for sidebar badges)
    func windowCount(for layer: Int) -> Int {
        windows.filter { $0.layer == layer }.count
    }

    /// Windows visible for the active layer filter
    var visibleWindows: [ScreenMapWindow] {
        guard !selectedLayers.isEmpty else { return windows }
        return windows.filter { selectedLayers.contains($0.layer) }
    }

    /// Number of windows with pending edits (position or size)
    var pendingEditCount: Int {
        windows.filter(\.hasEdits).count
    }

    /// Cycle layer: 0 → 1 → … → N-1 → empty(all) → 0
    /// From multi-select → collapse to [0] and resume cycling
    func cycleLayer() {
        if selectedLayers.count > 1 {
            // Multi-select → collapse to single
            selectedLayers = [0]
            return
        }
        guard let current = activeLayer else {
            // Showing all → go to 0
            selectedLayers = [0]
            return
        }
        let next = current + 1
        if next >= layerCount {
            selectedLayers = []  // all
        } else {
            selectedLayers = [next]
        }
    }

    /// Cycle layer backward: N-1 → … → 0 → empty(all) → N-1
    /// From multi-select → collapse to last layer and resume cycling
    func cyclePreviousLayer() {
        if selectedLayers.count > 1 {
            selectedLayers = [layerCount - 1]
            return
        }
        guard let current = activeLayer else {
            // Showing all → go to last layer
            selectedLayers = [layerCount - 1]
            return
        }
        if current == 0 {
            selectedLayers = []  // all
        } else {
            selectedLayers = [current - 1]
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

    /// Toggle a layer in multi-select (Cmd+click).
    /// If all layers end up selected, collapse to empty (show all).
    func toggleLayerSelection(_ layer: Int) {
        if selectedLayers.contains(layer) {
            selectedLayers.remove(layer)
        } else {
            selectedLayers.insert(layer)
        }
        // If all layers are now selected, collapse to "All"
        if selectedLayers.count >= layerCount {
            selectedLayers = []
        }
        DiagnosticLog.shared.info("[ScreenMap] toggleLayer \(layer) → \(selectedLayers.sorted())")
    }

    /// Move a window to a different layer, optionally auto-fitting to avoid collisions
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

    /// Try to fit a rect avoiding collisions; returns nil if no adjustment needed or no fit found
    func fitRect(_ rect: CGRect, avoiding others: [CGRect], within bounds: CGRect) -> CGRect? {
        // No collisions → keep as-is
        let collisions = others.filter { $0.intersects(rect) }
        if collisions.isEmpty { return nil }

        let minW: CGFloat = 100, minH: CGFloat = 50
        var candidates: [CGRect] = []

        for blocker in collisions {
            // Shrink from right (keep left edge, reduce width)
            let rightClip = CGRect(x: rect.minX, y: rect.minY,
                                   width: blocker.minX - rect.minX, height: rect.height)
            if rightClip.width >= minW && rightClip.height >= minH { candidates.append(rightClip) }

            // Shrink from bottom (keep top edge, reduce height)
            let bottomClip = CGRect(x: rect.minX, y: rect.minY,
                                    width: rect.width, height: blocker.minY - rect.minY)
            if bottomClip.width >= minW && bottomClip.height >= minH { candidates.append(bottomClip) }

            // Push right (shift origin past blocker)
            let pushRight = CGRect(x: blocker.maxX, y: rect.minY,
                                   width: rect.width, height: rect.height)
            if pushRight.maxX <= bounds.maxX { candidates.append(pushRight) }

            // Push down (shift origin below blocker)
            let pushDown = CGRect(x: rect.minX, y: blocker.maxY,
                                  width: rect.width, height: rect.height)
            if pushDown.maxY <= bounds.maxY { candidates.append(pushDown) }
        }

        // Pick largest candidate that avoids all siblings
        let valid = candidates.filter { cand in
            cand.width >= minW && cand.height >= minH &&
            bounds.contains(cand) &&
            !others.contains(where: { $0.intersects(cand) })
        }
        return valid.max(by: { $0.width * $0.height < $1.width * $1.height })
    }

    /// Auto-tile the active layer's windows into a grid (edits editedFrame only)
    func autoTileLayer() -> Int {
        guard let layer = activeLayer else { return 0 }

        let screens = NSScreen.screens
        let primaryHeight = screens.first?.frame.height ?? 0
        var totalTiled = 0
        let diag = DiagnosticLog.shared

        diag.info("[Tile] autoTileLayer layer=\(layer) screens=\(screens.count) primaryH=\(Int(primaryHeight))")
        for (i, screen) in screens.enumerated() {
            let cgY = primaryHeight - screen.frame.maxY
            diag.info("[Tile] NSScreen[\(i)] frame=\(Int(screen.frame.origin.x)),\(Int(screen.frame.origin.y)) \(Int(screen.frame.width))×\(Int(screen.frame.height)) cgY=\(Int(cgY)) visible=\(Int(screen.visibleFrame.origin.x)),\(Int(screen.visibleFrame.origin.y)) \(Int(screen.visibleFrame.width))×\(Int(screen.visibleFrame.height))")
        }

        // Tile per display: each monitor tiles its own windows independently
        let displayIndices = Set(windows.filter { $0.layer == layer }.map(\.displayIndex))
        for dIdx in displayIndices.sorted() {
            var indices = windows.indices.filter { windows[$0].layer == layer && windows[$0].displayIndex == dIdx }
            guard indices.count >= 1 else { continue }

            indices.sort { windows[$0].zIndex < windows[$1].zIndex }

            let screen = dIdx < screens.count ? screens[dIdx] : screens.first!
            let visible = screen.visibleFrame
            let axTop = primaryHeight - visible.maxY

            diag.info("[Tile] display=\(dIdx) \(indices.count) windows, visible=\(Int(visible.origin.x)),\(Int(visible.origin.y)) \(Int(visible.width))×\(Int(visible.height)) axTop=\(Int(axTop))")

            if indices.count == 1 {
                let frame = CGRect(x: visible.origin.x, y: axTop, width: visible.width, height: visible.height)
                windows[indices[0]].editedFrame = frame
                diag.info("[Tile]   \(windows[indices[0]].app) → \(Int(frame.origin.x)),\(Int(frame.origin.y)) \(Int(frame.width))×\(Int(frame.height))")
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
                    diag.info("[Tile]   \(windows[indices[slotIdx]].app) → \(Int(frame.origin.x)),\(Int(frame.origin.y)) \(Int(frame.width))×\(Int(frame.height))")
                    slotIdx += 1
                }
            }
            totalTiled += indices.count
        }
        return totalTiled
    }

    /// Expose the active layer's windows: spread into a padded grid with gaps.
    /// Unlike autoTileLayer() which tiles edge-to-edge, this preserves aspect ratios
    /// and adds padding so windows are visually separated. Operates per display.
    func exposeLayer() -> Int {
        guard let layer = activeLayer else { return 0 }

        let screens = NSScreen.screens
        let primaryHeight = screens.first?.frame.height ?? 0
        var totalExposed = 0

        let displayIndices = Set(windows.filter { $0.layer == layer }.map(\.displayIndex))
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

    /// Push overlapping windows apart with minimal movement. Operates per display.
    /// Unlike expose (which rearranges into a grid), this preserves approximate positions
    /// and only separates overlapping pairs along the shortest axis.
    func smartSpreadLayer() -> Int {
        guard let layer = activeLayer else { return 0 }

        let screens = NSScreen.screens
        let primaryHeight = screens.first?.frame.height ?? 0
        var totalAffected = 0

        let displayIndices = Set(windows.filter { $0.layer == layer }.map(\.displayIndex))
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

                for idx in indices {
                    clampToScreen(at: idx, bounds: screenRect)
                }

                if !hadOverlap { break }
            }
            totalAffected += affected.count
        }

        return totalAffected
    }

    /// Clamp a window's editedFrame to stay within screen bounds
    private func clampToScreen(at idx: Int, bounds: CGRect) {
        var f = windows[idx].editedFrame
        if f.minX < bounds.minX { f.origin.x = bounds.minX }
        if f.minY < bounds.minY { f.origin.y = bounds.minY }
        if f.maxX > bounds.maxX { f.origin.x = bounds.maxX - f.width }
        if f.maxY > bounds.maxY { f.origin.y = bounds.maxY - f.height }
        windows[idx].editedFrame = f
    }

    /// Reset all edited frames back to original
    func discardEdits() {
        for i in windows.indices {
            windows[i].editedFrame = windows[i].originalFrame
        }
    }

    /// Remap sparse layer numbers (e.g. 0, 3, 5) to contiguous (0, 1, 2)
    func renumberLayersContiguous() {
        let usedLayers = Set(windows.map(\.layer)).sorted()
        guard usedLayers != Array(0..<usedLayers.count) else { return }
        let mapping = Dictionary(uniqueKeysWithValues: usedLayers.enumerated().map { ($1, $0) })
        for i in windows.indices {
            windows[i].layer = mapping[windows[i].layer] ?? windows[i].layer
        }
        selectedLayers = Set(selectedLayers.compactMap { mapping[$0] })
    }

    /// Consolidate windows into fewer layers (defragmentation).
    /// Returns (oldLayerCount, newLayerCount) for display.
    func consolidateLayers() -> (old: Int, new: Int) {
        let oldCount = layerCount
        let maxLayer = (windows.map(\.layer).max() ?? 0)
        guard maxLayer >= 1 else { return (oldCount, oldCount) }

        let screenRect = CGRect(origin: .zero, size: screenSize)

        // Process from deepest layer up to layer 1
        for sourceLayer in stride(from: maxLayer, through: 1, by: -1) {
            let windowIndices = windows.indices.filter { windows[$0].layer == sourceLayer }
            for idx in windowIndices {
                let win = windows[idx]
                var placed = false

                // Try each shallower target layer
                for targetLayer in 0..<sourceLayer {
                    let siblings = windows.enumerated().filter {
                        $0.offset != idx && $0.element.layer == targetLayer
                    }.map(\.element.editedFrame)

                    // Prefer keeping current position if no collision
                    let collisions = siblings.filter { $0.intersects(win.editedFrame) }
                    if collisions.isEmpty {
                        windows[idx].layer = targetLayer
                        placed = true
                        break
                    }

                    // Fall back to fitRect for an adjusted position
                    if let fitted = fitRect(win.editedFrame, avoiding: siblings, within: screenRect) {
                        windows[idx].editedFrame = fitted
                        windows[idx].layer = targetLayer
                        placed = true
                        break
                    }
                }
                // If nothing works, leave it on its current layer
                _ = placed
            }
        }

        renumberLayersContiguous()

        // Land on layer 0 — consolidation pushes windows toward it
        selectedLayers = [0]

        return (old: oldCount, new: layerCount)
    }

    var layerLabel: String {
        if selectedLayers.isEmpty { return "ALL" }
        if selectedLayers.count == 1 { return "LAYER \(selectedLayers.first!)" }
        return selectedLayers.sorted().map { "L\($0)" }.joined(separator: "+")
    }

    /// Merge all windows from selected layers into the lowest one.
    /// Returns (count of moved windows, target layer) or nil if not enough layers selected.
    func flattenSelectedLayers() -> (count: Int, target: Int)? {
        guard selectedLayers.count >= 2 else { return nil }
        let sorted = selectedLayers.sorted()
        let target = sorted[0]
        let higherLayers = Set(sorted.dropFirst())

        var moveCount = 0
        for idx in windows.indices where higherLayers.contains(windows[idx].layer) {
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
        let before: [WindowSnapshot]   // pre-action state (from screen on first action)
        let after: [WindowSnapshot]    // post-action planned state (calculated)
        let moved: [MovedWindow]       // diff: what changed
        // verify entries reuse this struct: before=intended, after=actual, moved=drifted
    }

    private(set) var lastEntry: Entry? = nil

    private static var logFileURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".lattice", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("actions.jsonl")
    }()

    private static func shortUUID() -> String {
        let uuid = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return String(uuid.suffix(8))
    }

    func snapshot(_ windows: [ScreenMapWindow]) -> [WindowSnapshot] {
        windows.map { win in
            WindowSnapshot(
                wid: win.id,
                app: win.app,
                title: win.title,
                frame: .init(
                    x: Int(win.editedFrame.origin.x),
                    y: Int(win.editedFrame.origin.y),
                    w: Int(win.editedFrame.width),
                    h: Int(win.editedFrame.height)
                ),
                layer: win.layer
            )
        }
    }

    func record(action: String, summary: String,
                before: [WindowSnapshot], after: [WindowSnapshot]) -> Entry {
        let ref = Self.shortUUID()

        // Build moved array by diffing before/after
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

        // Write compact JSON line to ~/.lattice/logs/actions.jsonl
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

    /// Get the last entry as pretty-printed JSON string
    func lastEntryJSON() -> String? {
        guard let entry = lastEntry else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entry) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Scan real window positions via CGWindowList and log a "verify" entry
    /// comparing intended positions (from lastEntry) against actual positions.
    func verify() {
        guard let last = lastEntry else { return }
        let intendedByWid: [UInt32: WindowSnapshot] = Dictionary(
            last.after.map { ($0.wid, $0) }, uniquingKeysWith: { _, b in b }
        )
        guard !intendedByWid.isEmpty else { return }

        // CGWindowList scan
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

            // Check if actual differs from intended
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
            ref: last.ref,
            action: "verify",
            timestamp: iso.string(from: Date()),
            summary: summary,
            before: last.after,  // intended positions
            after: actual,       // actual positions
            moved: drifted       // windows that didn't land where intended
        )

        // Write to log file
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

// MARK: - Filter Presets

enum FilterPreset: String, CaseIterable {
    case all = "All"
    case terminals = "Terminals"
    case editors = "Editors"
    case browsers = "Browsers"
    case lattice = "Lattice"
    case currentSpace = "Current Space"

    var appTypes: Set<AppType>? {
        switch self {
        case .all: return nil
        case .terminals: return [.terminal]
        case .editors: return [.editor]
        case .browsers: return [.browser]
        case .lattice: return nil  // special case
        case .currentSpace: return nil  // special case
        }
    }

    var keyIndex: Int? {
        switch self {
        case .all: return 1
        case .terminals: return 2
        case .editors: return 3
        case .browsers: return 4
        case .lattice: return 5
        case .currentSpace: return 6
        }
    }

    static func from(keyIndex: Int) -> FilterPreset? {
        allCases.first { $0.keyIndex == keyIndex }
    }
}

// MARK: - State Machine

final class CommandModeState: ObservableObject {
    @Published var phase: CommandModePhase = .idle
    @Published var inventory = CommandModeInventory(activeLayer: nil, layerCount: 0, items: [])
    @Published var chords: [Chord] = []
    @Published var desktopSnapshot: DesktopInventorySnapshot?
    @Published var selectedWindowIds: Set<UInt32> = []
    @Published var desktopMode: DesktopInventoryMode = .browsing
    @Published var activePreset: FilterPreset? = nil
    @Published var searchQuery: String = ""
    @Published var isSearching: Bool = false

    // MARK: - Screen Map Editor
    @Published var screenMapEditor: ScreenMapEditorState? = nil

    // MARK: - Marquee Drag State
    @Published var isDragging: Bool = false
    @Published var marqueeOrigin: CGPoint = .zero
    @Published var marqueeCurrentPoint: CGPoint = .zero

    /// Computed normalized rect from origin → current drag point
    var marqueeRect: CGRect {
        let x = min(marqueeOrigin.x, marqueeCurrentPoint.x)
        let y = min(marqueeOrigin.y, marqueeCurrentPoint.y)
        let w = abs(marqueeCurrentPoint.x - marqueeOrigin.x)
        let h = abs(marqueeCurrentPoint.y - marqueeOrigin.y)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Row frames in inventoryPanel coordinate space (updated by PreferenceKey)
    var rowFrames: [UInt32: CGRect] = [:]

    /// Raw mouse-down point for drag threshold detection (screen coordinates)
    var dragStartPoint: NSPoint?

    /// Selection state before drag started (for Cmd+drag additive mode)
    private var preDragSelection: Set<UInt32> = []

    // MARK: - Saved Positions (for restore after show & distribute)
    /// Saved window frames before a show/distribute action — allows undo
    @Published var savedPositions: [UInt32: (pid: Int32, frame: WindowFrame)]? = nil

    /// Brief flash message shown after an action (auto-dismisses)
    @Published var flashMessage: String? = nil

    var onDismiss: (() -> Void)?
    var onPanelResize: ((_ width: CGFloat, _ height: CGFloat) -> Void)?

    /// Tracks the last item navigated to, for consistent Shift+arrow multi-select
    private var cursorWindowId: UInt32?

    // MARK: - Selection Helpers

    /// Backwards-compat: returns single selected ID (first element)
    var selectedWindowId: UInt32? {
        selectedWindowIds.first
    }

    func isSelected(_ id: UInt32) -> Bool {
        selectedWindowIds.contains(id)
    }

    func selectSingle(_ id: UInt32) {
        selectedWindowIds = [id]
        cursorWindowId = id
    }

    func toggleSelection(_ id: UInt32) {
        if selectedWindowIds.contains(id) {
            selectedWindowIds.remove(id)
        } else {
            selectedWindowIds.insert(id)
        }
        cursorWindowId = id
    }

    func clearSelection() {
        selectedWindowIds = []
        cursorWindowId = nil
        isDragging = false
        dragStartPoint = nil
    }

    /// Select contiguous range from cursor anchor to target (Shift+click)
    func selectRange(to targetId: UInt32) {
        guard let anchorId = cursorWindowId else { selectSingle(targetId); return }
        let list = flatWindowList
        guard let anchorIdx = list.firstIndex(where: { $0.id == anchorId }),
              let targetIdx = list.firstIndex(where: { $0.id == targetId }) else {
            selectSingle(targetId)
            return
        }
        let lo = min(anchorIdx, targetIdx)
        let hi = max(anchorIdx, targetIdx)
        selectedWindowIds = Set(list[lo...hi].map(\.id))
        // cursorWindowId stays as anchor for subsequent Shift+clicks
    }

    // MARK: - Marquee Drag

    func beginDrag(at point: CGPoint, additive: Bool) {
        preDragSelection = additive ? selectedWindowIds : []
        marqueeOrigin = point
        marqueeCurrentPoint = point
        isDragging = true
    }

    func updateDrag(to point: CGPoint) {
        marqueeCurrentPoint = point
        updateMarqueeSelection()
    }

    func endDrag() {
        isDragging = false
        dragStartPoint = nil
        preDragSelection = []
    }

    /// Select all rows whose frames intersect the current marquee rect
    private func updateMarqueeSelection() {
        let rect = marqueeRect
        var hits = preDragSelection
        for (wid, frame) in rowFrames {
            if rect.intersects(frame) {
                hits.insert(wid)
            }
        }
        selectedWindowIds = hits
        if let first = hits.first { cursorWindowId = first }
    }

    func activateSearch() {
        isSearching = true
        searchQuery = ""
        clearSelection()
    }

    func deactivateSearch() {
        isSearching = false
        searchQuery = ""
    }

    /// Filtered desktop snapshot based on active preset and search query
    var filteredSnapshot: DesktopInventorySnapshot? {
        guard let snapshot = desktopSnapshot else { return nil }

        let needsPresetFilter = activePreset != nil && activePreset != .all
        let needsSearchFilter = isSearching && !searchQuery.isEmpty
        guard needsPresetFilter || needsSearchFilter else { return snapshot }

        let query = searchQuery.lowercased()

        let filteredDisplays = snapshot.displays.compactMap { display -> DesktopInventorySnapshot.DisplayInfo? in
            let filteredSpaces = display.spaces.compactMap { space -> DesktopInventorySnapshot.SpaceGroup? in
                if let preset = activePreset, preset == .currentSpace && !space.isCurrent { return nil }

                let filteredApps = space.apps.compactMap { appGroup -> DesktopInventorySnapshot.AppGroup? in
                    let filteredWindows = appGroup.windows.filter { win in
                        // Preset filter
                        if let preset = activePreset, preset != .all {
                            let passesPreset: Bool
                            switch preset {
                            case .lattice: passesPreset = win.isLattice
                            case .currentSpace: passesPreset = true
                            default:
                                if let types = preset.appTypes, let name = win.appName {
                                    passesPreset = types.contains(AppTypeClassifier.classify(name))
                                } else {
                                    passesPreset = false
                                }
                            }
                            if !passesPreset { return false }
                        }

                        // Search filter
                        if needsSearchFilter {
                            let matchesApp = win.appName?.lowercased().contains(query) ?? false
                            let matchesTitle = win.title.lowercased().contains(query)
                            let matchesLattice = win.latticeSession?.lowercased().contains(query) ?? false
                            if !matchesApp && !matchesTitle && !matchesLattice { return false }
                        }

                        return true
                    }
                    guard !filteredWindows.isEmpty else { return nil }
                    return DesktopInventorySnapshot.AppGroup(
                        id: appGroup.id, appName: appGroup.appName, windows: filteredWindows
                    )
                }
                guard !filteredApps.isEmpty else { return nil }
                return DesktopInventorySnapshot.SpaceGroup(
                    id: space.id, index: space.index, isCurrent: space.isCurrent, apps: filteredApps
                )
            }
            guard !filteredSpaces.isEmpty else { return nil }
            return DesktopInventorySnapshot.DisplayInfo(
                id: display.id, name: display.name, resolution: display.resolution,
                visibleFrame: display.visibleFrame, isMain: display.isMain,
                spaceCount: display.spaceCount, currentSpaceIndex: display.currentSpaceIndex,
                spaces: filteredSpaces
            )
        }
        return DesktopInventorySnapshot(displays: filteredDisplays, timestamp: snapshot.timestamp)
    }

    /// Compact panel size for chord view
    private let chordPanelSize: (CGFloat, CGFloat) = (580, 360)

    /// Compute desktop inventory panel size based on display count, clamped to screen
    private var desktopPanelSize: (CGFloat, CGFloat) {
        let displayCount = max(1, desktopSnapshot?.displays.count ?? 1)
        let ideal = CGFloat(displayCount) * 480 + CGFloat(displayCount - 1) + 32
        let screenWidth = NSScreen.main?.visibleFrame.width ?? 1920
        let width = min(ideal, screenWidth * 0.92)
        let height: CGFloat = 640
        return (width, height)
    }

    /// Flat window list for keyboard navigation (respects active filter)
    var flatWindowList: [DesktopInventorySnapshot.InventoryWindowInfo] {
        filteredSnapshot?.allWindows ?? []
    }

    func enter() {
        inventory = buildInventory()
        chords = buildChords()
        desktopSnapshot = buildDesktopInventory()
        clearSelection()
        desktopMode = .browsing
        phase = .desktopInventory
        // Go directly to screen map editor
        enterScreenMapEditor()
        // Don't call onPanelResize here — caller handles initial sizing
    }

    /// Returns true if the key was consumed
    func handleKey(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) -> Bool {
        // Backtick (keyCode 50) toggles desktop inventory from either phase
        if keyCode == 50 {
            if isSearching {
                deactivateSearch()
                return true
            }
            if phase == .desktopInventory {
                // Back to chord view
                clearSelection()
                desktopMode = .browsing
                activePreset = nil
                phase = .inventory
                onPanelResize?(chordPanelSize.0, chordPanelSize.1)
                return true
            } else if phase == .inventory {
                // Enter desktop inventory
                let diag = DiagnosticLog.shared
                desktopSnapshot = buildDesktopInventory()
                clearSelection()
                desktopMode = .browsing
                phase = .desktopInventory
                let size = desktopPanelSize
                onPanelResize?(size.0, size.1)
                if let snap = desktopSnapshot {
                    let totalWindows = snap.allWindows.count
                    let totalSpaces = snap.displays.reduce(0) { $0 + $1.spaces.count }
                    diag.info("Desktop inventory: \(snap.displays.count) display(s), \(totalSpaces) space(s), \(totalWindows) window(s)")
                }
                return true
            }
        }

        // Route desktop inventory keys
        if phase == .desktopInventory {
            return handleDesktopInventoryKey(keyCode, modifiers: modifiers)
        }

        // Escape from chord view → dismiss
        if keyCode == 53 {
            dismiss()
            return true
        }

        guard phase == .inventory else { return false }

        // Check chord map
        if let chord = chords.first(where: { $0.keyCode == keyCode }) {
            phase = .executing(chord.label)
            let action = chord.action
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                action()
                self?.dismiss()
            }
            return true
        }

        // Unknown key — ignore
        return true
    }

    // MARK: - Desktop Inventory Key Handling

    private func handleDesktopInventoryKey(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) -> Bool {
        switch desktopMode {
        case .browsing:     return handleBrowsingKey(keyCode, modifiers: modifiers)
        case .tiling:       return handleTilingKey(keyCode)
        case .gridPreview:  return handleGridPreviewKey(keyCode)
        case .screenMap:    return handleScreenMapKey(keyCode, modifiers: modifiers)
        }
    }

    // MARK: Browsing — ↑↓ within column, ←→ between displays, Enter → actions

    private func handleBrowsingKey(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) -> Bool {
        // Cmd+A → select all visible windows (works during search too — selects filtered results)
        if keyCode == 0 && modifiers.contains(.command) {
            let allIds = Set(flatWindowList.map(\.id))
            if selectedWindowIds == allIds {
                clearSelection()  // toggle off
            } else {
                selectedWindowIds = allIds
            }
            if isSearching { deactivateSearch() }
            return true
        }

        switch keyCode {
        case 53: // Escape
            if isSearching {
                deactivateSearch()
                return true
            }
            if !selectedWindowIds.isEmpty {
                clearSelection()
                return true
            }
            // No selection — back to chord view
            desktopMode = .browsing
            activePreset = nil
            phase = .inventory
            onPanelResize?(chordPanelSize.0, chordPanelSize.1)
            return true

        case 126: // ↑
            if modifiers.contains(.shift) {
                extendSelectionVertical(-1)
            } else {
                moveSelectionVertical(-1)
            }
            return true

        case 125: // ↓
            if modifiers.contains(.shift) {
                extendSelectionVertical(1)
            } else {
                moveSelectionVertical(1)
            }
            return true

        case 38: // j
            if isSearching { return false }
            if modifiers.contains(.shift) {
                extendSelectionVertical(1)
            } else {
                moveSelectionVertical(1)
            }
            return true

        case 40: // k
            if isSearching { return false }
            if modifiers.contains(.shift) {
                extendSelectionVertical(-1)
            } else {
                moveSelectionVertical(-1)
            }
            return true

        case 123: // ← → jump to previous display
            moveSelectionToDisplay(delta: -1)
            return true

        case 124: // → → jump to next display
            moveSelectionToDisplay(delta: 1)
            return true

        case 36: // Enter
            if isSearching {
                // Select first match and bring to front
                if let first = flatWindowList.first {
                    selectSingle(first.id)
                    bringSelectedToFront()
                }
                deactivateSearch()
                return true
            }
            if !selectedWindowIds.isEmpty {
                if selectedWindowIds.count > 1 {
                    bringAllSelectedToFront()
                } else {
                    bringSelectedToFront()
                }
            } else {
                moveSelectionVertical(1) // select first window
            }
            return true

        case 44: // / → activate search
            if !isSearching {
                activateSearch()
                return true
            }
            return false

        case 3: // f → focus window directly
            if isSearching && selectedWindowIds.isEmpty { return false }
            if isSearching { deactivateSearch() }
            if !selectedWindowIds.isEmpty {
                if selectedWindowIds.count > 1 {
                    focusAllSelected()
                } else {
                    focusSelectedWindow()
                }
            }
            return true

        case 17: // t → enter tiling mode directly
            if isSearching && selectedWindowIds.isEmpty { return false }
            if isSearching { deactivateSearch() }
            if !selectedWindowIds.isEmpty {
                desktopMode = .tiling
            }
            return true

        case 1: // s → grid preview (or show & distribute if single)
            if isSearching && selectedWindowIds.isEmpty { return false }
            if isSearching { deactivateSearch() }
            if !selectedWindowIds.isEmpty {
                desktopMode = .gridPreview
            }
            return true

        case 4: // h → highlight window directly
            if isSearching && selectedWindowIds.isEmpty { return false }
            if isSearching { deactivateSearch() }
            if !selectedWindowIds.isEmpty {
                if selectedWindowIds.count > 1 {
                    highlightAllSelected()
                } else {
                    highlightSelectedWindow()
                }
            }
            return true

        case 46: // m → screen map editor
            if isSearching { deactivateSearch() }
            enterScreenMapEditor()
            return true

        case 18, 19, 20, 21, 23, 22: // 1-6 → filter presets (only when no selection and not searching)
            if isSearching { return false }
            if selectedWindowIds.isEmpty {
                let keyToIndex: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6]
                if let idx = keyToIndex[keyCode], let preset = FilterPreset.from(keyIndex: idx) {
                    if activePreset == preset {
                        activePreset = nil  // toggle off
                    } else {
                        activePreset = preset
                    }
                    clearSelection()
                }
            }
            return true

        default:
            if isSearching { return false }
            return true
        }
    }

    // MARK: Tiling — position keys

    private func handleTilingKey(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 53: // Escape → back to browsing
            desktopMode = .browsing
            return true

        case 123: tileSelectedWindow(to: .left); return true       // ←
        case 124: tileSelectedWindow(to: .right); return true      // →
        case 126: tileSelectedWindow(to: .maximize); return true   // ↑
        case 18:  tileSelectedWindow(to: .topLeft); return true    // 1
        case 19:  tileSelectedWindow(to: .topRight); return true   // 2
        case 20:  tileSelectedWindow(to: .bottomLeft); return true // 3
        case 21:  tileSelectedWindow(to: .bottomRight); return true// 4
        case 8:   tileSelectedWindow(to: .center); return true     // c
        case 2:   distributeSelectedHorizontally(); return true    // d → distribute

        default:
            return true
        }
    }

    // MARK: Grid Preview — Enter/s to apply, Esc to cancel

    private func handleGridPreviewKey(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 53: // Escape → back to browsing
            desktopMode = .browsing
            return true

        case 36, 1: // Enter or s → apply the layout
            showAndDistributeSelected()
            desktopMode = .browsing
            return true

        default:
            return true
        }
    }

    /// Windows arranged in grid order for preview
    var gridPreviewWindows: [DesktopInventorySnapshot.InventoryWindowInfo] {
        flatWindowList.filter { selectedWindowIds.contains($0.id) }
    }

    /// Grid shape for current selection
    var gridPreviewShape: [Int] {
        WindowTiler.gridShape(for: selectedWindowIds.count)
    }

    // MARK: Screen Map Editor

    private func handleScreenMapKey(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) -> Bool {
        let diag = DiagnosticLog.shared
        diag.info("[ScreenMap] key: \(keyCode)")
        switch keyCode {
        case 53: // Escape → discard edits or exit
            if screenMapEditor?.isPreviewing == true {
                endScreenMapPreview()
            }
            if let editor = screenMapEditor, editor.pendingEditCount > 0 {
                editor.discardEdits()
                diag.info("[ScreenMap] discarded \(editor.pendingEditCount) edits")
                flash("Edits discarded")
            } else {
                diag.info("[ScreenMap] exit")
                screenMapEditor = nil
                desktopMode = .browsing
            }
            return true

        case 36: // Enter → apply pending edits
            if screenMapEditor?.isPreviewing == true {
                endScreenMapPreview()
            }
            diag.info("[ScreenMap] apply edits")
            applyScreenMapEdits()
            return true

        case 47: // . → cycle layer, shift+. → cycle reverse
            if modifiers.contains(.shift) {
                screenMapEditor?.cyclePreviousLayer()
            } else {
                screenMapEditor?.cycleLayer()
            }
            diag.info("[ScreenMap] cycle → \(screenMapEditor?.layerLabel ?? "nil")")
            objectWillChange.send()
            return true

        case 33: // [ → move selected windows to previous layer
            if let editor = screenMapEditor {
                for wid in selectedWindowIds {
                    if let idx = editor.windows.firstIndex(where: { $0.id == wid }) {
                        let oldLayer = editor.windows[idx].layer
                        let newLayer = max(0, oldLayer - 1)
                        diag.info("[ScreenMap] [: \(editor.windows[idx].app) L\(oldLayer)→L\(newLayer)")
                        editor.reassignLayer(windowId: wid, toLayer: newLayer, fitToAvailable: true)
                    }
                }
                objectWillChange.send()
            }
            return true

        case 30: // ] → move selected windows to next layer
            if let editor = screenMapEditor {
                for wid in selectedWindowIds {
                    if let idx = editor.windows.firstIndex(where: { $0.id == wid }) {
                        let oldLayer = editor.windows[idx].layer
                        let newLayer = oldLayer + 1
                        diag.info("[ScreenMap] ]: \(editor.windows[idx].app) L\(oldLayer)→L\(newLayer)")
                        editor.reassignLayer(windowId: wid, toLayer: newLayer, fitToAvailable: true)
                    }
                }
                objectWillChange.send()
            }
            return true

        case 1: // s → show & distribute selected (if any)
            if !selectedWindowIds.isEmpty {
                diag.info("[ScreenMap] s: grid preview with \(selectedWindowIds.count) selected")
                screenMapEditor = nil
                desktopMode = .gridPreview
            }
            return true

        case 8: // c → consolidate (defrag) layers
            diag.info("[ScreenMap] c: consolidate layers")
            consolidateScreenMapLayers()
            return true

        case 3: // f → flatten selected layers
            diag.info("[ScreenMap] f: flatten selected layers")
            flattenScreenMapLayers()
            return true

        case 9: // v → toggle layer preview
            diag.info("[ScreenMap] v: toggle preview")
            previewScreenMapLayer()
            return true

        case 17: // t → auto-tile active layer
            diag.info("[ScreenMap] t: tile layer")
            tileScreenMapLayer()
            return true

        case 14: // e → expose (spread windows with gaps)
            diag.info("[ScreenMap] e: expose layer")
            exposeScreenMapLayer()
            return true

        case 2: // d → smart spread (push overlaps apart)
            diag.info("[ScreenMap] d: smart spread")
            smartSpreadScreenMapLayer()
            return true

        case 29: // 0 → fit all (reset zoom + pan)
            diag.info("[ScreenMap] 0: fit all")
            screenMapEditor?.resetZoomPan()
            flash("Fit all")
            return true

        default:
            return true
        }
    }

    /// Snapshot on-screen windows into the screen map editor
    func enterScreenMapEditor() {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return }

        struct CGWin {
            let wid: UInt32; let pid: Int32; let app: String; let title: String
            let frame: CGRect; let layer: Int; let displayIndex: Int
        }

        // Build display rects for assigning windows to monitors
        let screens = NSScreen.screens
        let primaryHeight = screens.first?.frame.height ?? 0

        /// Determine which display a window center belongs to (in CG/AX coordinates)
        func displayIndex(for frame: CGRect) -> Int {
            let centerX = frame.midX
            let centerY = frame.midY
            for (i, screen) in screens.enumerated() {
                // Convert NSScreen frame (bottom-left origin) to CG coords (top-left origin)
                let cgOriginY = primaryHeight - screen.frame.maxY
                let cgRect = CGRect(x: screen.frame.origin.x, y: cgOriginY,
                                    width: screen.frame.width, height: screen.frame.height)
                if cgRect.contains(CGPoint(x: centerX, y: centerY)) {
                    return i
                }
            }
            // Fallback: closest screen by center distance
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
            if app == "LatticeApp" || app == "lattice" { continue }
            let pid = info[kCGWindowOwnerPID as String] as? Int32 ?? 0
            let title = info[kCGWindowName as String] as? String ?? ""
            let dIdx = displayIndex(for: rect)
            ordered.append(CGWin(wid: wid, pid: pid, app: app, title: title, frame: rect, layer: layer, displayIndex: dIdx))
        }

        NSLog("[ScreenMap] enterScreenMapEditor: %d windows after filtering", ordered.count)

        // Iterative peeling PER DISPLAY: windows only occlude each other within the same monitor.
        func significantOverlap(_ a: CGRect, _ b: CGRect) -> Bool {
            let inter = a.intersection(b)
            guard !inter.isNull && inter.width > 0 && inter.height > 0 else { return false }
            let interArea = inter.width * inter.height
            let smallerArea = min(a.width * a.height, b.width * b.height)
            guard smallerArea > 0 else { return false }
            return interArea / smallerArea >= 0.15
        }

        // Group indices by display
        var byDisplay: [Int: [Int]] = [:]
        for i in ordered.indices {
            byDisplay[ordered[i].displayIndex, default: []].append(i)
        }

        var layerAssignment = [Int: Int]()  // index → layer

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
                    if !isOccluded {
                        unoccluded.append(i)
                    }
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

        var mapWindows: [ScreenMapWindow] = []
        for (i, win) in ordered.enumerated() {
            let assignedLayer = layerAssignment[i] ?? 0
            mapWindows.append(ScreenMapWindow(
                id: win.wid, pid: win.pid, app: win.app, title: win.title,
                originalFrame: win.frame, editedFrame: win.frame,
                zIndex: i, layer: assignedLayer, displayIndex: win.displayIndex
            ))
        }

        let totalLayers = (mapWindows.map(\.layer).max() ?? 0) + 1
        NSLog("[ScreenMap] Peeling complete: %d layers from %d windows across %d displays", totalLayers, mapWindows.count, byDisplay.count)
        for l in 0..<totalLayers {
            let count = mapWindows.filter { $0.layer == l }.count
            let names = mapWindows.filter { $0.layer == l }.map { "\($0.app)[\($0.displayIndex)]" }.joined(separator: ", ")
            NSLog("[ScreenMap]   Layer %d: %d windows [%@]", l, count, names)
        }

        // Build display geometries in CG coordinates
        var displayGeometries: [DisplayGeometry] = []
        for (i, screen) in screens.enumerated() {
            let cgOriginY = primaryHeight - screen.frame.maxY
            let cgRect = CGRect(x: screen.frame.origin.x, y: cgOriginY,
                                width: screen.frame.width, height: screen.frame.height)
            displayGeometries.append(DisplayGeometry(
                index: i, cgRect: cgRect, label: "Display \(i)"
            ))
        }

        screenMapEditor = ScreenMapEditorState(windows: mapWindows, displays: displayGeometries)
        desktopMode = .screenMap
    }

    /// Apply all pending screen map edits (moves + resizes)
    private func applyScreenMapEdits() {
        guard let editor = screenMapEditor else { return }
        let pendingEdits = editor.windows.filter(\.hasEdits)
        guard !pendingEdits.isEmpty else {
            screenMapEditor = nil
            desktopMode = .browsing
            return
        }

        // Save original positions for undo (restore/keep banner)
        var positions: [UInt32: (pid: Int32, frame: WindowFrame)] = [:]
        for win in pendingEdits {
            positions[win.id] = (pid: win.pid, frame: WindowFrame(
                x: Double(win.originalFrame.origin.x), y: Double(win.originalFrame.origin.y),
                w: Double(win.originalFrame.width), h: Double(win.originalFrame.height)
            ))
        }
        savedPositions = positions

        // Sort by layer descending (deepest layers first → front layers last so they end up on top)
        let sorted = pendingEdits.sorted(by: { $0.layer > $1.layer })
        let allMoves = sorted.map { (wid: $0.id, pid: $0.pid, frame: $0.editedFrame) }
        NSLog("[ScreenMap] Applying %d edits (sorted by layer desc)", allMoves.count)
        for m in allMoves {
            NSLog("[ScreenMap]   wid=%u → %.0f,%.0f %.0fx%.0f", m.wid, m.frame.origin.x, m.frame.origin.y, m.frame.width, m.frame.height)
        }
        // Keep a reference to the action log before clearing the editor
        let actionLog = editor.actionLog

        // First pass: move all windows
        WindowTiler.batchMoveWindows(allMoves)

        // Second pass after a tick: re-apply to override apps that snap back
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            WindowTiler.batchMoveWindows(allMoves)
        }

        let noun = pendingEdits.count == 1 ? "edit" : "edits"
        flash("Applied \(pendingEdits.count) \(noun)")
        screenMapEditor = nil
        desktopMode = .browsing

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            // Verify actual window positions against intended
            actionLog.verify()
            self?.desktopSnapshot = self?.buildDesktopInventory()
        }
    }

    /// Flatten selected layers into the lowest one
    func flattenScreenMapLayers() {
        guard let editor = screenMapEditor else { return }
        let before = editor.actionLog.snapshot(editor.windows)
        let result = editor.flattenSelectedLayers()
        let after = editor.actionLog.snapshot(editor.windows)
        let summary: String
        if let result = result {
            summary = "Merged \(result.count) windows into L\(result.target)"
        } else {
            summary = "Select 2+ layers to flatten"
        }
        let entry = editor.actionLog.record(action: "flatten", summary: summary, before: before, after: after)
        editor.lastActionRef = entry.ref
        flash("\(summary)  [\(entry.ref)]")
        objectWillChange.send()
    }

    // MARK: - Layer Preview

    /// Single overlay window + event monitors
    var previewWindow: NSWindow? = nil
    private var previewGlobalMonitor: Any? = nil
    private var previewLocalMonitor: Any? = nil

    /// Captured window images for preview (wid → NSImage)
    var previewCaptures: [UInt32: NSImage] = [:]

    /// Toggle preview: capture screenshots + show overlay
    func previewScreenMapLayer() {
        guard let editor = screenMapEditor else { return }

        if editor.isPreviewing {
            endScreenMapPreview()
            return
        }

        let visible = editor.visibleWindows
        guard !visible.isEmpty else {
            flash("No windows to preview")
            return
        }

        let diag = DiagnosticLog.shared
        diag.info("[Preview] capturing \(visible.count) windows")

        // Capture screenshot of each window via CGWindowListCreateImage
        var captures: [UInt32: NSImage] = [:]
        for win in visible {
            if let cgImage = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                CGWindowID(win.id),
                [.boundsIgnoreFraming, .bestResolution]
            ) {
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: win.editedFrame.width, height: win.editedFrame.height))
                captures[win.id] = nsImage
                diag.info("[Preview] captured wid=\(win.id) \(win.app): \(cgImage.width)×\(cgImage.height)px → frame=\(Int(win.editedFrame.origin.x)),\(Int(win.editedFrame.origin.y)) \(Int(win.editedFrame.width))×\(Int(win.editedFrame.height))")
            } else {
                diag.warn("[Preview] failed to capture wid=\(win.id) \(win.app)")
            }
        }
        previewCaptures = captures

        editor.isPreviewing = true
        objectWillChange.send()

        // View layer will call showPreviewWindow() via onChange
    }

    /// Called from the view layer to create the overlay window spanning all screens
    func showPreviewWindow(contentView: NSView) {
        // Compute union of all screen frames (AppKit coords, bottom-left origin)
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        var unionFrame = screens[0].frame
        for screen in screens.dropFirst() {
            unionFrame = unionFrame.union(screen.frame)
        }
        let diag = DiagnosticLog.shared
        diag.info("[Preview] union frame: \(Int(unionFrame.origin.x)),\(Int(unionFrame.origin.y)) \(Int(unionFrame.width))×\(Int(unionFrame.height))")

        let window = NSWindow(
            contentRect: unionFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        window.hasShadow = false
        window.contentView = contentView
        window.setFrame(unionFrame, display: true)
        window.orderFrontRegardless()
        previewWindow = window

        // Arm event monitors immediately (no AX calls → no activation race)
        previewGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.endScreenMapPreview()
        }
        previewLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.endScreenMapPreview()
            return nil
        }
    }

    /// Dismiss the preview overlay
    func endScreenMapPreview() {
        guard screenMapEditor?.isPreviewing == true else { return }

        previewWindow?.orderOut(nil)
        previewWindow = nil

        if let m = previewGlobalMonitor { NSEvent.removeMonitor(m) }
        if let m = previewLocalMonitor { NSEvent.removeMonitor(m) }
        previewGlobalMonitor = nil
        previewLocalMonitor = nil

        previewCaptures = [:]
        screenMapEditor?.isPreviewing = false

        objectWillChange.send()
    }

    /// Consolidate screen map layers (defrag) and show flash
    func exposeScreenMapLayer() {
        guard let editor = screenMapEditor else { return }
        let before = editor.actionLog.snapshot(editor.windows)
        let count = editor.exposeLayer()
        let after = editor.actionLog.snapshot(editor.windows)
        let summary: String
        if count >= 2 {
            summary = "Exposed \(count) windows"
        } else if count == 1 {
            summary = "Only 1 window in layer"
        } else {
            summary = "Select a single layer first"
        }
        let entry = editor.actionLog.record(action: "expose", summary: summary, before: before, after: after)
        editor.lastActionRef = entry.ref
        flash("\(summary)  [\(entry.ref)]")
        objectWillChange.send()
    }

    /// Public entry points for action bar buttons
    func applyScreenMapEditsFromButton() {
        if screenMapEditor?.isPreviewing == true { endScreenMapPreview() }
        applyScreenMapEdits()
    }

    func exitScreenMap() {
        if screenMapEditor?.isPreviewing == true { endScreenMapPreview() }
        if let editor = screenMapEditor, editor.pendingEditCount > 0 {
            editor.discardEdits()
            flash("Edits discarded")
        } else {
            screenMapEditor = nil
            desktopMode = .browsing
        }
    }

    func smartSpreadScreenMapLayer() {
        guard let editor = screenMapEditor else { return }
        let before = editor.actionLog.snapshot(editor.windows)
        let count = editor.smartSpreadLayer()
        let after = editor.actionLog.snapshot(editor.windows)
        let summary: String
        if count >= 2 {
            summary = "Spread \(count) windows"
        } else if count == 1 {
            summary = "Only 1 window in layer"
        } else {
            summary = "Select a single layer first"
        }
        let entry = editor.actionLog.record(action: "spread", summary: summary, before: before, after: after)
        editor.lastActionRef = entry.ref
        flash("\(summary)  [\(entry.ref)]")
        objectWillChange.send()
    }

    func tileScreenMapLayer() {
        guard let editor = screenMapEditor else { return }
        let before = editor.actionLog.snapshot(editor.windows)
        let count = editor.autoTileLayer()
        let after = editor.actionLog.snapshot(editor.windows)
        let summary: String
        if count >= 2 {
            summary = "Tiled \(count) windows"
        } else if count == 1 {
            summary = "Only 1 window in layer"
        } else {
            summary = "Select a single layer first"
        }
        let entry = editor.actionLog.record(action: "tile", summary: summary, before: before, after: after)
        editor.lastActionRef = entry.ref
        flash("\(summary)  [\(entry.ref)]")
        objectWillChange.send()
    }

    func consolidateScreenMapLayers() {
        guard let editor = screenMapEditor else { return }
        let before = editor.actionLog.snapshot(editor.windows)
        let result = editor.consolidateLayers()
        let after = editor.actionLog.snapshot(editor.windows)
        let summary = result.old == result.new
            ? "Already optimal"
            : "Consolidated \(result.old) → \(result.new) layers"
        let entry = editor.actionLog.record(action: "merge", summary: summary, before: before, after: after)
        editor.lastActionRef = entry.ref
        flash("\(summary)  [\(entry.ref)]")
        objectWillChange.send()
    }

    // MARK: - Selection Actions

    /// Move selection up/down within the flat window list (stays in same display column when possible)
    private func moveSelectionVertical(_ delta: Int) {
        guard let snapshot = filteredSnapshot else { return }

        let anchor = cursorWindowId ?? selectedWindowId
        if let anchor = anchor,
           let displayIdx = displayIndex(for: anchor, in: snapshot) {
            let displayWindows = windowsInDisplay(displayIdx, snapshot: snapshot)
            if let localIdx = displayWindows.firstIndex(where: { $0.id == anchor }) {
                let newIdx = max(0, min(displayWindows.count - 1, localIdx + delta))
                selectSingle(displayWindows[newIdx].id)
            }
        } else {
            // No selection — pick first window in first display
            let windows = flatWindowList
            guard !windows.isEmpty else { return }
            if let id = delta > 0 ? windows.first?.id : windows.last?.id {
                selectSingle(id)
            }
        }

        if let wid = cursorWindowId, let win = flatWindowList.first(where: { $0.id == wid }) {
            let title = win.title.isEmpty ? "(untitled)" : String(win.title.prefix(30))
            DiagnosticLog.shared.info("Select: wid=\(wid) \"\(title)\"")
        }
    }

    /// Extend selection up/down (Shift+arrow) — adds items without removing existing selection
    private func extendSelectionVertical(_ delta: Int) {
        guard let snapshot = filteredSnapshot else { return }

        let anchor = cursorWindowId ?? selectedWindowId
        if let anchor = anchor,
           let displayIdx = displayIndex(for: anchor, in: snapshot) {
            let displayWindows = windowsInDisplay(displayIdx, snapshot: snapshot)
            if let localIdx = displayWindows.firstIndex(where: { $0.id == anchor }) {
                let newIdx = max(0, min(displayWindows.count - 1, localIdx + delta))
                let newId = displayWindows[newIdx].id
                selectedWindowIds.insert(newId)
                cursorWindowId = newId
            }
        } else {
            let windows = flatWindowList
            guard !windows.isEmpty else { return }
            if let id = delta > 0 ? windows.first?.id : windows.last?.id {
                selectedWindowIds.insert(id)
                cursorWindowId = id
            }
        }
    }

    /// Jump selection to the adjacent display column
    private func moveSelectionToDisplay(delta: Int) {
        guard let snapshot = filteredSnapshot, snapshot.displays.count > 1 else { return }

        let displayCount = snapshot.displays.count

        // Find current display index
        let currentDisplayIdx: Int
        if let wid = selectedWindowId, let idx = displayIndex(for: wid, in: snapshot) {
            currentDisplayIdx = idx
        } else {
            // No selection — start from first or last display
            currentDisplayIdx = delta > 0 ? -1 : displayCount
        }

        let targetIdx = currentDisplayIdx + delta
        guard targetIdx >= 0, targetIdx < displayCount else { return }

        // Find the position in the current display for context
        let targetWindows = windowsInDisplay(targetIdx, snapshot: snapshot)
        guard !targetWindows.isEmpty else { return }

        // Try to land at a similar position (same row index)
        if let wid = selectedWindowId,
           let srcIdx = displayIndex(for: wid, in: snapshot) {
            let srcWindows = windowsInDisplay(srcIdx, snapshot: snapshot)
            let srcPos = srcWindows.firstIndex(where: { $0.id == wid }) ?? 0
            let targetPos = min(srcPos, targetWindows.count - 1)
            selectSingle(targetWindows[targetPos].id)
        } else if let id = targetWindows.first?.id {
            selectSingle(id)
        }

        DiagnosticLog.shared.info("Jump to display \(targetIdx + 1)")
    }

    // MARK: - Display Helpers

    /// Get the display index for a given window ID
    private func displayIndex(for wid: UInt32, in snapshot: DesktopInventorySnapshot) -> Int? {
        for (dIdx, display) in snapshot.displays.enumerated() {
            for space in display.spaces {
                for app in space.apps {
                    if app.windows.contains(where: { $0.id == wid }) {
                        return dIdx
                    }
                }
            }
        }
        return nil
    }

    /// Get all windows in a display as a flat list (preserving space/app order)
    private func windowsInDisplay(_ displayIdx: Int, snapshot: DesktopInventorySnapshot) -> [DesktopInventorySnapshot.InventoryWindowInfo] {
        guard displayIdx < snapshot.displays.count else { return [] }
        return snapshot.displays[displayIdx].spaces.flatMap { $0.apps.flatMap { $0.windows } }
    }

    private func bringSelectedToFront() {
        guard let wid = selectedWindowId,
              let window = flatWindowList.first(where: { $0.id == wid }) else { return }
        DiagnosticLog.shared.info("Front: wid=\(wid) pid=\(window.pid)")
        WindowTiler.raiseWindowAndReactivate(wid: wid, pid: window.pid)
    }

    private func bringAllSelectedToFront() {
        let windows = flatWindowList.filter { selectedWindowIds.contains($0.id) }
        guard !windows.isEmpty else { return }
        DiagnosticLog.shared.info("Front all: \(windows.count) windows")
        WindowTiler.raiseWindowsAndReactivate(windows: windows.map { (wid: $0.id, pid: $0.pid) })
    }

    private func focusSelectedWindow() {
        guard let wid = selectedWindowId,
              let window = flatWindowList.first(where: { $0.id == wid }) else { return }
        DiagnosticLog.shared.info("Focus: wid=\(wid) pid=\(window.pid)")
        WindowTiler.raiseWindowAndReactivate(wid: wid, pid: window.pid)
    }

    private func highlightSelectedWindow() {
        guard let wid = selectedWindowId else { return }
        DiagnosticLog.shared.info("Highlight: wid=\(wid)")
        WindowTiler.highlightWindowById(wid: wid)
    }

    private func tileSelectedWindow(to position: TilePosition) {
        if selectedWindowIds.count > 1 {
            tileAllSelected(to: position)
            return
        }
        guard let wid = selectedWindowId,
              let window = flatWindowList.first(where: { $0.id == wid }) else { return }

        DiagnosticLog.shared.info("Tile: wid=\(wid) → \(position.rawValue)")
        WindowTiler.tileWindowById(wid: wid, pid: window.pid, to: position)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.desktopSnapshot = self?.buildDesktopInventory()
        }
    }

    private func tileAllSelected(to position: TilePosition) {
        let windows = flatWindowList.filter { selectedWindowIds.contains($0.id) }
        guard !windows.isEmpty else { return }

        // For left/right with 2+ windows: distribute evenly across width
        if windows.count >= 2 && (position == .left || position == .right) {
            distributeSelectedHorizontally()
            return
        }

        DiagnosticLog.shared.info("Tile all \(windows.count): \(position.rawValue)")
        for win in windows {
            WindowTiler.tileWindowById(wid: win.id, pid: win.pid, to: position)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.desktopSnapshot = self?.buildDesktopInventory()
        }
    }

    private func distributeSelectedHorizontally() {
        let windows = flatWindowList.filter { selectedWindowIds.contains($0.id) }
        guard windows.count >= 2 else { return }
        DiagnosticLog.shared.info("Distribute H: \(windows.count) windows")
        WindowTiler.tileDistributeHorizontally(windows: windows.map { (wid: $0.id, pid: $0.pid) })
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.desktopSnapshot = self?.buildDesktopInventory()
        }
    }

    // MARK: - Batch Actions (multi-select)

    func focusAllSelected() {
        let windows = flatWindowList.filter { selectedWindowIds.contains($0.id) }
        guard !windows.isEmpty else { return }
        DiagnosticLog.shared.info("Focus all: \(windows.count) windows")
        WindowTiler.raiseWindowsAndReactivate(windows: windows.map { (wid: $0.id, pid: $0.pid) })
    }

    func highlightAllSelected() {
        let wids = flatWindowList.filter { selectedWindowIds.contains($0.id) }.map(\.id)
        guard !wids.isEmpty else { return }
        DiagnosticLog.shared.info("Highlight all: \(wids.count) windows")
        for wid in wids {
            WindowTiler.highlightWindowById(wid: wid)
        }
    }

    /// Show all selected windows (raise to front) without changing layout
    func showAllSelected() {
        let windows = flatWindowList.filter { selectedWindowIds.contains($0.id) }
        guard !windows.isEmpty else { return }
        savePositions(for: windows)
        WindowTiler.raiseWindowsAndReactivate(windows: windows.map { (wid: $0.id, pid: $0.pid) })
        flash("Showing \(windows.count) window\(windows.count == 1 ? "" : "s")")
    }

    /// Show all selected windows AND distribute in smart grid — single batch operation
    func showAndDistributeSelected() {
        let windows = flatWindowList.filter { selectedWindowIds.contains($0.id) }
        guard !windows.isEmpty else { return }
        savePositions(for: windows)
        WindowTiler.batchRaiseAndDistribute(windows: windows.map { (wid: $0.id, pid: $0.pid) })
        let shape = WindowTiler.gridShape(for: windows.count)
        let grid = shape.map(String.init).joined(separator: "+")
        flash("\(windows.count) windows [\(grid)]")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.desktopSnapshot = self?.buildDesktopInventory()
        }
    }

    /// Distribute selected in smart grid without raising
    func distributeSelected() {
        let windows = flatWindowList.filter { selectedWindowIds.contains($0.id) }
        guard !windows.isEmpty else { return }
        savePositions(for: windows)
        WindowTiler.batchRaiseAndDistribute(windows: windows.map { (wid: $0.id, pid: $0.pid) })
        let shape = WindowTiler.gridShape(for: windows.count)
        let grid = shape.map(String.init).joined(separator: "+")
        flash("\(windows.count) windows [\(grid)]")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.desktopSnapshot = self?.buildDesktopInventory()
        }
    }

    /// Save current positions of windows so they can be restored later
    private func savePositions(for windows: [DesktopInventorySnapshot.InventoryWindowInfo]) {
        // Don't overwrite if already saved (allow chaining actions)
        guard savedPositions == nil else { return }
        var positions: [UInt32: (pid: Int32, frame: WindowFrame)] = [:]
        for win in windows {
            positions[win.id] = (pid: win.pid, frame: win.frame)
        }
        savedPositions = positions
        DiagnosticLog.shared.info("Saved positions for \(positions.count) windows")
    }

    /// Restore windows to their saved positions — single batch operation
    func restorePositions() {
        guard let positions = savedPositions else { return }
        DiagnosticLog.shared.info("Restoring \(positions.count) window positions")
        let restores = positions.map { (wid: $0.key, pid: $0.value.pid, frame: $0.value.frame) }
        WindowTiler.batchRestoreWindows(restores)
        savedPositions = nil
        flash("Restored \(restores.count) window\(restores.count == 1 ? "" : "s")")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.desktopSnapshot = self?.buildDesktopInventory()
        }
    }

    /// Accept the current layout — discard saved positions
    func discardSavedPositions() {
        savedPositions = nil
        DiagnosticLog.shared.info("Accepted layout, discarded saved positions")
    }

    /// Show a brief flash message that auto-dismisses
    func flash(_ message: String) {
        flashMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            if self?.flashMessage == message { self?.flashMessage = nil }
        }
    }

    /// Copy a text representation of the desktop inventory to clipboard
    func copyInventoryToClipboard() {
        guard let snapshot = desktopSnapshot else { return }
        var lines: [String] = ["DESKTOP INVENTORY"]
        lines.append(String(repeating: "─", count: 60))

        for display in snapshot.displays {
            lines.append("")
            lines.append("\(display.name)  \(display.visibleFrame.w)×\(display.visibleFrame.h)  (\(display.spaceCount) spaces)")
            for space in display.spaces {
                let tag = space.isCurrent ? " ◀ active" : ""
                let winCount = space.apps.reduce(0) { $0 + $1.windows.count }
                lines.append("  Space \(space.index)\(tag)  (\(winCount) windows)")
                for app in space.apps {
                    if app.windows.count == 1, let win = app.windows.first {
                        let tile = win.tilePosition?.label ?? "—"
                        let title = win.title.isEmpty ? "(untitled)" : win.title
                        let dmx = win.isLattice ? " [lattice]" : ""
                        let path = win.inventoryPath?.description ?? ""
                        lines.append("    \(app.appName)  \(title)\(dmx)  \(Int(win.frame.w))×\(Int(win.frame.h))  \(tile)  \(path)")
                    } else {
                        lines.append("    \(app.appName)")
                        for win in app.windows {
                            let tile = win.tilePosition?.label ?? "—"
                            let title = win.title.isEmpty ? "(untitled)" : win.title
                            let dmx = win.isLattice ? " [lattice]" : ""
                            let path = win.inventoryPath?.description ?? ""
                            lines.append("      \(title)\(dmx)  \(Int(win.frame.w))×\(Int(win.frame.h))  \(tile)  \(path)")
                        }
                    }
                }
            }
        }

        let text = lines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        DiagnosticLog.shared.success("Copied inventory to clipboard (\(text.count) chars)")
    }

    func dismiss() {
        phase = .idle
        onDismiss?()
    }

    // MARK: - Inventory Builder

    private func buildInventory() -> CommandModeInventory {
        let workspace = WorkspaceManager.shared
        let tmux = TmuxModel.shared
        let inventoryMgr = InventoryManager.shared

        // Refresh inventory so orphans are current
        inventoryMgr.refresh()

        let activeLayer = workspace.activeLayer
        let layerCount = workspace.config?.layers?.count ?? 0

        var items: [CommandModeInventory.Item] = []

        // Active layer projects
        if let layer = activeLayer {
            for lp in layer.projects {
                if let groupId = lp.group, let group = workspace.group(byId: groupId) {
                    let running = workspace.isGroupRunning(group)
                    let paneCount = group.tabs.count
                    items.append(.init(
                        name: group.label,
                        group: "Layer: \(layer.label)",
                        status: running ? .running : .stopped,
                        paneCount: paneCount,
                        tileHint: lp.tile
                    ))
                } else if let path = lp.path {
                    let name = (path as NSString).lastPathComponent
                    let sessionName = WorkspaceManager.sessionName(for: path)
                    let session = tmux.sessions.first(where: { $0.name == sessionName })
                    let status: CommandModeInventory.Status
                    if let s = session {
                        status = s.attached ? .attached : .running
                    } else {
                        status = .stopped
                    }
                    items.append(.init(
                        name: name,
                        group: "Layer: \(layer.label)",
                        status: status,
                        paneCount: session?.panes.count ?? 0,
                        tileHint: lp.tile
                    ))
                }
            }
        }

        // Tab groups not in active layer
        if let groups = workspace.config?.groups {
            let layerGroupIds = Set(activeLayer?.projects.compactMap(\.group) ?? [])
            for group in groups where !layerGroupIds.contains(group.id) {
                let running = workspace.isGroupRunning(group)
                items.append(.init(
                    name: group.label,
                    group: "Group: \(group.label)",
                    status: running ? .running : .stopped,
                    paneCount: group.tabs.count,
                    tileHint: nil
                ))
            }
        }

        // Orphans
        for orphan in inventoryMgr.orphans {
            items.append(.init(
                name: orphan.name,
                group: "Orphan",
                status: orphan.attached ? .attached : .running,
                paneCount: orphan.panes.count,
                tileHint: nil
            ))
        }

        return CommandModeInventory(
            activeLayer: activeLayer?.label,
            layerCount: layerCount,
            items: items
        )
    }

    // MARK: - Desktop Inventory Builder

    private func buildDesktopInventory() -> DesktopInventorySnapshot {
        let originalScreens = NSScreen.screens
        let displaySpaces = WindowTiler.getDisplaySpaces()
        let primaryHeight = originalScreens.first?.frame.height ?? 0

        // Sort screens left-to-right by frame origin, tie-break top-to-bottom
        let sortedScreens = originalScreens.sorted {
            if $0.frame.origin.x != $1.frame.origin.x {
                return $0.frame.origin.x < $1.frame.origin.x
            }
            return $0.frame.origin.y > $1.frame.origin.y
        }
        // Map sorted index → original index for displaySpaces lookup
        let sortedToOriginal = sortedScreens.map { s in originalScreens.firstIndex(where: { $0 === s })! }
        let screens = sortedScreens

        // Build space-to-display mapping: spaceId → (displayIndex, spaceIndex)
        var spaceToDisplay: [Int: (displayIdx: Int, spaceIdx: Int)] = [:]
        for (dIdx, ds) in displaySpaces.enumerated() {
            for space in ds.spaces {
                spaceToDisplay[space.id] = (dIdx, space.index)
            }
        }

        // Current space IDs per display
        let currentSpaceIds = Set(displaySpaces.map(\.currentSpaceId))

        // Query ALL windows (not just on-screen) to capture every space
        guard let rawList = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return DesktopInventorySnapshot(displays: [], timestamp: Date())
        }

        // Parse raw CG window info
        struct RawWindow {
            let wid: UInt32; let app: String; let pid: Int32
            let title: String; let frame: WindowFrame
            let latticeSession: String?; let spaceIds: [Int]
        }

        // System/helper processes that create layer-0 windows users don't care about
        let blockedApps: Set<String> = [
            // macOS system
            "WindowServer", "Dock", "SystemUIServer", "Control Center",
            "Notification Center", "NotificationCenter", "Spotlight", "WindowManager",
            "TextInputMenuAgent", "TextInputSwitcher", "universalAccessAuthWarn",
            "AXVisualSupportAgent", "loginwindow", "ScreenSaverEngine",
            // UI service helpers (run as XPC, show popover/autofill UI)
            "AutoFill", "AuthenticationServicesHelper", "CursorUIViewService",
            "SharedWebCredentialViewService", "CoreServicesUIAgent",
            "UserNotificationCenter", "SecurityAgent", "OSDUIHelper",
            "PassKit UIService", "QuickLookUIService", "ScopedBookmarkAgent",
            // Dev tool helpers
            "Instruments", "FileMerge",
        ]
        // Also block apps whose name ends with known helper suffixes
        let blockedSuffixes = ["UIService", "UIHelper", "Agent", "Helper", "ViewService"]

        let ownPid = ProcessInfo.processInfo.processIdentifier
        let rawCount = rawList.count

        var allWindows: [RawWindow] = []
        for info in rawList {
            guard let wid = info[kCGWindowNumber as String] as? UInt32,
                  let ownerName = info[kCGWindowOwnerName as String] as? String,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary
            else { continue }

            // Skip our own windows
            guard pid != ownPid else { continue }

            // Skip known system/helper processes
            guard !blockedApps.contains(ownerName) else { continue }
            if blockedSuffixes.contains(where: { ownerName.hasSuffix($0) }) { continue }

            var rect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict, &rect),
                  rect.width >= 100, rect.height >= 50 else { continue }

            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 else { continue }

            let title = info[kCGWindowName as String] as? String ?? ""
            let isOnScreen = info[kCGWindowIsOnscreen as String] as? Bool ?? false
            let spaceIds = WindowTiler.getSpacesForWindow(wid)

            // Skip windows not assigned to any space (background helpers)
            guard !spaceIds.isEmpty else { continue }

            // For windows on a current space, require them to be actually visible.
            // This filters hidden helper windows (AutoFill, CursorUIViewService, etc.)
            // while keeping real windows on other spaces.
            let isOnCurrentSpace = spaceIds.contains(where: { currentSpaceIds.contains($0) })
            if isOnCurrentSpace && !isOnScreen { continue }

            let frame = WindowFrame(x: Double(rect.origin.x), y: Double(rect.origin.y),
                                    w: Double(rect.width), h: Double(rect.height))

            var latticeSession: String?
            if let range = title.range(of: #"\[lattice:([^\]]+)\]"#, options: .regularExpression) {
                let match = String(title[range])
                latticeSession = String(match.dropFirst(8).dropLast(1))
            }

            allWindows.append(RawWindow(wid: wid, app: ownerName, pid: pid, title: title,
                                        frame: frame, latticeSession: latticeSession, spaceIds: spaceIds))
        }

        DiagnosticLog.shared.info("Desktop scan: \(rawCount) raw → \(allWindows.count) after filter")

        // Assign each window to (display, space)
        struct AssignedWindow {
            let win: RawWindow; let displayIdx: Int; let spaceId: Int; let spaceIdx: Int; let isOnScreen: Bool
        }

        var assigned: [AssignedWindow] = []
        for win in allWindows {
            // Primary: use space→display mapping
            for sid in win.spaceIds {
                if let mapping = spaceToDisplay[sid] {
                    assigned.append(AssignedWindow(
                        win: win,
                        displayIdx: mapping.displayIdx,
                        spaceId: sid,
                        spaceIdx: mapping.spaceIdx,
                        isOnScreen: currentSpaceIds.contains(sid)
                    ))
                    break  // assign to first known space
                }
            }

            // Fallback: match by frame center (no space info)
            if !win.spaceIds.contains(where: { spaceToDisplay[$0] != nil }) {
                let cx = win.frame.x + win.frame.w / 2
                let cy = win.frame.y + win.frame.h / 2
                let nsCy = primaryHeight - cy
                for (sIdx, screen) in screens.enumerated() {
                    if screen.frame.contains(NSPoint(x: cx, y: nsCy)) {
                        let origIdx = sortedToOriginal[sIdx]
                        let ds = origIdx < displaySpaces.count ? displaySpaces[origIdx] : nil
                        let currentSid = ds?.currentSpaceId ?? 0
                        let currentIdx = ds?.spaces.first(where: { $0.isCurrent })?.index ?? 1
                        assigned.append(AssignedWindow(
                            win: win, displayIdx: origIdx,
                            spaceId: currentSid, spaceIdx: currentIdx, isOnScreen: true
                        ))
                        break
                    }
                }
            }
        }

        // Build hierarchical: Display → Space → App → Windows
        var displays: [DesktopInventorySnapshot.DisplayInfo] = []

        for (screenIdx, screen) in screens.enumerated() {
            let frame = screen.frame
            let visible = screen.visibleFrame
            let name = screen.localizedName

            let originalIdx = sortedToOriginal[screenIdx]
            let ds = originalIdx < displaySpaces.count ? displaySpaces[originalIdx] : nil
            let spaceCount = ds?.spaces.count ?? 1
            let currentSpaceIdx = ds?.spaces.first(where: { $0.isCurrent })?.index ?? 1

            let screenWindows = assigned.filter { $0.displayIdx == originalIdx }

            // Group by space
            var windowsBySpace: [Int: [AssignedWindow]] = [:]
            for aw in screenWindows {
                windowsBySpace[aw.spaceId, default: []].append(aw)
            }

            // Build SpaceGroups sorted by space index
            let isMain = screen == NSScreen.main
            let displayLabel = InventoryPath.displayName(for: screen, isMain: isMain)
            var spaceGroups: [DesktopInventorySnapshot.SpaceGroup] = []
            let allSpacesForDisplay = ds?.spaces ?? []

            for spaceInfo in allSpacesForDisplay {
                let spaceWindows = windowsBySpace[spaceInfo.id] ?? []
                guard !spaceWindows.isEmpty else { continue }

                // Group by app within space
                var appGroups: [String: [AssignedWindow]] = [:]
                for aw in spaceWindows {
                    appGroups[aw.win.app, default: []].append(aw)
                }

                var groups: [DesktopInventorySnapshot.AppGroup] = []
                for appName in appGroups.keys.sorted() {
                    let wins = appGroups[appName]!
                    let appType = AppTypeClassifier.classify(appName)
                    let inventoryWindows = wins.map { aw -> DesktopInventorySnapshot.InventoryWindowInfo in
                        let tile = aw.isOnScreen ? WindowTiler.inferTilePosition(frame: aw.win.frame, screen: screen) : nil
                        let path = InventoryPath(
                            display: displayLabel,
                            space: "space\(aw.spaceIdx)",
                            appType: appType.rawValue,
                            appName: appName,
                            windowTitle: aw.win.title.isEmpty ? "untitled" : aw.win.title
                        )
                        return DesktopInventorySnapshot.InventoryWindowInfo(
                            id: aw.win.wid,
                            pid: aw.win.pid,
                            title: aw.win.title,
                            frame: aw.win.frame,
                            tilePosition: tile,
                            isLattice: aw.win.latticeSession != nil,
                            latticeSession: aw.win.latticeSession,
                            spaceIndex: aw.spaceIdx,
                            isOnScreen: aw.isOnScreen,
                            inventoryPath: path,
                            appName: appName
                        )
                    }
                    groups.append(DesktopInventorySnapshot.AppGroup(
                        id: "\(spaceInfo.id)-\(appName)",
                        appName: appName,
                        windows: inventoryWindows
                    ))
                }

                spaceGroups.append(DesktopInventorySnapshot.SpaceGroup(
                    id: spaceInfo.id,
                    index: spaceInfo.index,
                    isCurrent: spaceInfo.isCurrent,
                    apps: groups
                ))
            }

            displays.append(DesktopInventorySnapshot.DisplayInfo(
                id: ds?.displayId ?? "display-\(screenIdx)",
                name: name,
                resolution: (w: Int(frame.width), h: Int(frame.height)),
                visibleFrame: (w: Int(visible.width), h: Int(visible.height)),
                isMain: isMain,
                spaceCount: spaceCount,
                currentSpaceIndex: currentSpaceIdx,
                spaces: spaceGroups
            ))
        }

        return DesktopInventorySnapshot(displays: displays, timestamp: Date())
    }

    // MARK: - Chord Map

    private func buildChords() -> [Chord] {
        let workspace = WorkspaceManager.shared

        var chords: [Chord] = []

        // [a] tile all — re-tile active layer's windows
        chords.append(Chord(key: "a", keyCode: 0, label: "tile all") {
            WorkspaceManager.shared.retileCurrentLayer()
        })

        // [s] split — tile two most recent left/right
        chords.append(Chord(key: "s", keyCode: 1, label: "split") {
            let running = ProjectScanner.shared.projects.filter(\.isRunning)
            let term = Preferences.shared.terminal
            if running.count >= 2 {
                WindowTiler.tile(session: running[0].sessionName, terminal: term, to: .left)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    WindowTiler.tile(session: running[1].sessionName, terminal: term, to: .right)
                }
            } else if running.count == 1 {
                WindowTiler.tile(session: running[0].sessionName, terminal: term, to: .maximize)
            }
        })

        // [m] maximize — maximize frontmost terminal
        chords.append(Chord(key: "m", keyCode: 46, label: "maximize") {
            let term = Preferences.shared.terminal
            // Find frontmost running project
            let running = ProjectScanner.shared.projects.filter(\.isRunning)
            if let first = running.first {
                WindowTiler.tile(session: first.sessionName, terminal: term, to: .maximize)
            }
        })

        // [1]-[3] layer focus (dynamic)
        let layers = workspace.config?.layers ?? []
        let layerKeyCodes: [UInt16] = [18, 19, 20]  // 1, 2, 3
        for (i, layer) in layers.prefix(3).enumerated() {
            let idx = i
            chords.append(Chord(key: "\(i + 1)", keyCode: layerKeyCodes[i], label: layer.label.lowercased()) {
                WorkspaceManager.shared.focusLayer(index: idx)
            })
        }

        // [l] launch layer — explicitly start non-running projects
        chords.append(Chord(key: "l", keyCode: 37, label: "launch layer") {
            let ws = WorkspaceManager.shared
            ws.switchToLayer(index: ws.activeLayerIndex, force: true)
        })

        // [r] refresh
        chords.append(Chord(key: "r", keyCode: 15, label: "refresh") {
            ProjectScanner.shared.scan()
            TmuxModel.shared.poll()
            InventoryManager.shared.refresh()
        })

        // [p] palette
        chords.append(Chord(key: "p", keyCode: 35, label: "palette") {
            CommandPaletteWindow.shared.show()
        })

        return chords
    }
}
