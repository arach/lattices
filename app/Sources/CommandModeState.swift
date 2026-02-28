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

// DisplayGeometry, ScreenMapWindowEntry, ScreenMapEditorState, ScreenMapActionLog
// are defined in ScreenMapState.swift
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
        case .tiling:       return handleTilingKey(keyCode, modifiers: modifiers)
        case .gridPreview:  return handleGridPreviewKey(keyCode)
        case .screenMap:    return true  // handled by standalone ScreenMapWindowController
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

        case 46: // m → screen map editor (standalone window)
            if isSearching { deactivateSearch() }
            ScreenMapWindowController.shared.show()
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

    private func handleTilingKey(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) -> Bool {
        switch keyCode {
        case 53: // Escape → back to browsing
            desktopMode = .browsing
            return true

        case 123: tileSelectedWindow(to: .left); return true       // ←
        case 124: tileSelectedWindow(to: .right); return true      // →
        case 126: // ↑ — shift=maximize, plain=top half
            if modifiers.contains(.shift) {
                tileSelectedWindow(to: .maximize)
            } else {
                tileSelectedWindow(to: .top)
            }
            return true
        case 125: tileSelectedWindow(to: .bottom); return true     // ↓
        case 18:  tileSelectedWindow(to: .topLeft); return true    // 1
        case 19:  tileSelectedWindow(to: .topRight); return true   // 2
        case 20:  tileSelectedWindow(to: .bottomLeft); return true // 3
        case 21:  tileSelectedWindow(to: .bottomRight); return true// 4
        case 23:  tileSelectedWindow(to: .leftThird); return true  // 5
        case 22:  tileSelectedWindow(to: .centerThird); return true// 6
        case 26:  tileSelectedWindow(to: .rightThird); return true // 7
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
                WorkspaceManager.shared.tileLayer(index: idx)
            })
        }

        // [l] launch layer — explicitly start non-running projects
        chords.append(Chord(key: "l", keyCode: 37, label: "launch layer") {
            let ws = WorkspaceManager.shared
            ws.tileLayer(index: ws.activeLayerIndex, launch: true, force: true)
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
