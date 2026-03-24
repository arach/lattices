import AppKit
import Combine
import SwiftUI

// MARK: - KeyableHUDPanel

private class KeyableHUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// Suppress NSBeep — our local event monitor handles all keys
    override func keyDown(with event: NSEvent) {
        // Don't call super — that's what triggers the system bonk sound
    }

    /// Allow performKeyEquivalent to pass through for event monitor
    override func performKeyEquivalent(with event: NSEvent) -> Bool { false }
}

// MARK: - HUDController (singleton, cockpit-style HUD)
//
// Speed strategy:
//   1. Panels are pre-built at launch with content already rendered
//   2. Panels stay ordered (never orderOut on dismiss — just alpha=0)
//   3. Show = synchronous alphaValue=1 + makeKey (zero animation, instant paint)
//   4. Data refresh happens AFTER first paint
//   5. Dismiss = short slide-out animation (non-blocking, delightful)

final class HUDController {
    static let shared = HUDController()

    private var topPanel: NSPanel?
    private var bottomPanel: NSPanel?
    private var leftPanel: NSPanel?
    private var rightPanel: NSPanel?
    private var minimapPanels: [NSPanel] = []
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var minimapObserver: AnyCancellable?
    private let state = HUDState()

    private let topHeight: CGFloat = 44
    private let bottomHeight: CGFloat = 48
    private let leftWidth: CGFloat = 320
    private let rightWidth: CGFloat = 400
    private let expandedMapWidth: CGFloat = 380
    private let expandedMapHeight: CGFloat = 240

    /// Track which screen panels are positioned on (for multi-monitor repositioning)
    private var positionedScreen: NSScreen?

    var isVisible: Bool { leftPanel?.alphaValue ?? 0 > 0.5 }
    private(set) var voiceBarVisible: Bool = false
    private var voiceBarObserver: AnyCancellable?

    func toggle() {
        if isVisible { dismiss() } else { show() }
    }

    // MARK: - Voice bar (top panel only, for HandsOff mode)

    private var voiceBarKeyMonitor: Any?

    func showVoiceBar() {
        guard !isVisible else { return } // full HUD is showing, no need
        ensurePanels()

        state.voiceActive = true

        let screen = mouseScreen()
        if positionedScreen != screen { positionAllPanels(on: screen) }

        // Show only top + bottom bars
        topPanel?.alphaValue = 1
        topPanel?.orderFront(nil)
        bottomPanel?.alphaValue = 1
        bottomPanel?.orderFront(nil)
        voiceBarVisible = true

        // Escape key dismisses the voice bar
        if voiceBarKeyMonitor == nil {
            voiceBarKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { // Escape
                    DispatchQueue.main.async { self?.hideVoiceBar() }
                }
            }
        }

        // Auto-hide 3s after HandsOff goes idle (turn complete)
        voiceBarObserver = HandsOffSession.shared.$state.sink { [weak self] hsState in
            if hsState == .idle {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    guard let self, self.voiceBarVisible,
                          HandsOffSession.shared.state == .idle else { return }
                    self.hideVoiceBar()
                }
            }
        }
    }

    func hideVoiceBar() {
        guard voiceBarVisible else { return }
        voiceBarObserver = nil
        if let m = voiceBarKeyMonitor { NSEvent.removeMonitor(m); voiceBarKeyMonitor = nil }
        state.voiceActive = false
        voiceBarVisible = false

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            topPanel?.animator().alphaValue = 0
            bottomPanel?.animator().alphaValue = 0
        })
    }

    // MARK: - Warm up (call at launch)

    func warmUp() {
        ensurePanels()

        let screen = NSScreen.main ?? NSScreen.screens.first!
        positionAllPanels(on: screen)

        // Order into window server at alpha 0 — instant show later
        for p in allPanels { p.orderFrontRegardless(); p.alphaValue = 0 }
    }

    // MARK: - Show (instant first paint)

    func show() {
        ensurePanels()

        state.query = ""
        state.selectedIndex = 0
        state.selectedItem = nil
        state.selectedItems = []
        state.focus = .list

        let screen = mouseScreen()
        if positionedScreen != screen { positionAllPanels(on: screen) }

        // Pre-compute tile grid BEFORE showing panels (captures real z-order)
        DesktopModel.shared.poll()
        precomputeTileGrid(on: screen)

        // ── INSTANT SHOW ── alphaValue flip, zero animation
        let isExpanded = state.minimapMode == .expanded
        for p in allPanels {
            // Minimap panels only show when expanded
            if minimapPanels.contains(where: { $0 === p }) && !isExpanded { continue }
            p.alphaValue = 1
        }
        leftPanel?.makeKey()

        installMonitors()

        DispatchQueue.main.async { ProjectScanner.shared.scan() }
    }

    // MARK: - Dismiss (animated, delightful)

    func dismiss() {
        guard isVisible else { return }
        removeMonitors()

        // Restore untiled windows only if user actually tiled something
        if !state.tiledWindows.isEmpty {
            restoreUntiled()
        } else {
            // Just clean up tile state without moving anything
            state.tileSnapshot = []
            state.tileMode = false
        }

        if state.voiceActive {
            if HandsOffSession.shared.state == .listening { HandsOffSession.shared.toggle() }
            state.voiceActive = false
        }

        let sf = (positionedScreen ?? mouseScreen()).visibleFrame

        NSAnimationContext.runAnimationGroup({ [weak self] ctx in
            guard let self else { return }
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)

            topPanel?.animator().setFrame(
                NSRect(x: sf.minX + leftWidth, y: sf.maxY,
                       width: sf.width - leftWidth - rightWidth, height: topHeight), display: false)
            bottomPanel?.animator().setFrame(
                NSRect(x: sf.minX + leftWidth, y: sf.minY - bottomHeight,
                       width: sf.width - leftWidth - rightWidth, height: bottomHeight), display: false)
            leftPanel?.animator().setFrame(
                NSRect(x: sf.minX - leftWidth * 0.3, y: sf.minY, width: leftWidth, height: sf.height), display: false)
            rightPanel?.animator().setFrame(
                NSRect(x: sf.maxX + rightWidth * 0.3 - rightWidth, y: sf.minY, width: rightWidth, height: sf.height), display: false)
            for p in allPanels { p.animator().alphaValue = 0 }
        }) { [weak self] in
            guard let self, let screen = self.positionedScreen else { return }
            self.positionAllPanels(on: screen)
        }
    }

    // MARK: - Position panels on screen

    private var allPanels: [NSPanel] {
        [topPanel, bottomPanel, leftPanel, rightPanel].compactMap { $0 } + minimapPanels
    }

    private func positionAllPanels(on screen: NSScreen) {
        let sf = screen.visibleFrame
        let midWidth = sf.width - leftWidth - rightWidth

        topPanel?.setFrame(NSRect(x: sf.minX + leftWidth, y: sf.maxY - topHeight,
                                  width: midWidth, height: topHeight), display: false)
        bottomPanel?.setFrame(NSRect(x: sf.minX + leftWidth, y: sf.minY,
                                     width: midWidth, height: bottomHeight), display: false)
        leftPanel?.setFrame(NSRect(x: sf.minX, y: sf.minY,
                                   width: leftWidth, height: sf.height), display: false)
        rightPanel?.setFrame(NSRect(x: sf.maxX - rightWidth, y: sf.minY,
                                    width: rightWidth, height: sf.height), display: false)
        positionMinimapPanels()
        positionedScreen = screen
    }

    private func buildMinimapPanels(dismiss: @escaping () -> Void) {
        minimapPanels.forEach { $0.orderOut(nil) }
        minimapPanels.removeAll()

        for i in 0..<NSScreen.screens.count {
            let mp = makePanel()
            mp.contentView = NSHostingView(rootView:
                HUDMinimap(state: state, onDismiss: dismiss, screenIndex: i).preferredColorScheme(.dark))
            mp.alphaValue = 0
            minimapPanels.append(mp)
        }
    }

    private func positionMinimapPanels() {
        let screens = NSScreen.screens
        let hudScreen = positionedScreen ?? screens.first!

        for (i, mp) in minimapPanels.enumerated() {
            guard i < screens.count else { continue }
            let screen = screens[i]
            let sf = screen.visibleFrame

            if screen == hudScreen {
                // On HUD screen: attach to left bar + bottom bar corner
                mp.setFrame(NSRect(
                    x: sf.minX + leftWidth,
                    y: sf.minY + bottomHeight,
                    width: expandedMapWidth,
                    height: expandedMapHeight
                ), display: false)
            } else {
                // On other screens: bottom-left corner
                mp.setFrame(NSRect(
                    x: sf.minX + 12,
                    y: sf.minY + 12,
                    width: expandedMapWidth,
                    height: expandedMapHeight
                ), display: false)
            }
        }
    }

    // MARK: - Build panels (once)

    @discardableResult
    private func ensurePanels() -> Void {
        guard topPanel == nil else { return }
        let dismiss: () -> Void = { [weak self] in self?.dismiss() }

        let tp = makePanel()
        tp.contentView = NSHostingView(rootView:
            HUDTopBar(state: state, onDismiss: dismiss).preferredColorScheme(.dark))

        let bp = makePanel()
        bp.contentView = NSHostingView(rootView:
            HUDBottomBar(state: state, onDismiss: dismiss).preferredColorScheme(.dark))

        let lp = makePanel(keyable: true)
        lp.contentView = NSHostingView(rootView:
            HUDLeftBar(state: state, onDismiss: dismiss).preferredColorScheme(.dark))

        let rp = makePanel()
        rp.contentView = NSHostingView(rootView:
            HUDRightBar(state: state, onDismiss: dismiss).preferredColorScheme(.dark))

        self.topPanel = tp
        self.bottomPanel = bp
        self.leftPanel = lp
        self.rightPanel = rp

        // Create one minimap panel per screen
        buildMinimapPanels(dismiss: dismiss)

        // Observe minimap mode changes to show/hide expanded panels
        minimapObserver = state.$minimapMode.sink { [weak self] mode in
            guard let self else { return }
            if mode == .expanded {
                self.positionMinimapPanels()
                for mp in self.minimapPanels {
                    mp.alphaValue = 1
                    mp.orderFront(nil)
                }
            } else {
                for mp in self.minimapPanels { mp.alphaValue = 0 }
            }
        }
    }

    private func makePanel(keyable: Bool = false) -> NSPanel {
        let p: NSPanel
        if keyable {
            p = KeyableHUDPanel(contentRect: .zero,
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        } else {
            p = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        }
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .floating
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.isMovableByWindowBackground = false
        p.alphaValue = 0
        // Visible to screen recorders (default .readWrite allows capture)
        p.sharingType = .readOnly
        // Keep composited even when transparent — eliminates ordering cost on show
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return p
    }

    // MARK: - Keyboard routing

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        let keyCode = event.keyCode

        // Escape: tile mode → exit tile, search → list, otherwise dismiss
        if keyCode == 53 {
            if state.tileMode {
                exitTileMode()
                return nil
            }
            if state.focus == .search {
                state.focus = .list
                return nil
            }
            dismiss()
            return nil
        }

        // Tab: cycle focus
        if keyCode == 48 {
            switch state.focus {
            case .search:
                if !state.flatItems.isEmpty {
                    state.focus = .list
                    if state.selectedItem == nil {
                        state.selectedIndex = 0
                        state.selectedItem = state.flatItems[safe: 0]
                    }
                }
            case .list:      state.focus = .inspector
            case .inspector: state.focus = .search
            }
            return nil
        }

        // Down arrow (Shift = extend multi-select)
        if keyCode == 125 {
            let shift = event.modifierFlags.contains(.shift)
            if state.focus == .search {
                state.focus = .list
                if let firstItem = state.flatItems[safe: 0] {
                    state.selectSingle(firstItem, index: 0)
                }
            } else if state.focus == .list {
                state.moveSelection(by: 1, extend: shift)
            }
            return nil
        }

        // Up arrow (Shift = extend multi-select)
        if keyCode == 126 {
            let shift = event.modifierFlags.contains(.shift)
            if state.focus == .list {
                if state.selectedIndex == 0 && !shift {
                    state.focus = .search
                } else if state.selectedIndex > 0 {
                    state.moveSelection(by: -1, extend: shift)
                }
            }
            return nil
        }

        // Enter: activate
        if keyCode == 36 {
            if let item = state.selectedItem, state.focus != .search {
                activateItem(item)
            }
            return nil
        }

        // Option+V: toggle voice from ANY context (including search)
        if keyCode == 9 && event.modifierFlags.contains(.option) {
            toggleVoice()
            return nil
        }

        // V key (keyCode 9): toggle voice mode (works from any non-search context)
        if keyCode == 9 && state.focus != .search {
            toggleVoice()
            return nil
        }

        // M key (keyCode 46): cycle minimap mode (hidden → docked → expanded → hidden)
        if keyCode == 46 && state.focus != .search {
            switch state.minimapMode {
            case .hidden:   state.minimapMode = .docked
            case .docked:   state.minimapMode = .expanded
            case .expanded: state.minimapMode = .hidden
            }
            return nil
        }

        // T key (keyCode 17): tile selected windows or toggle tile mode
        if keyCode == 17 && state.focus != .search {
            DiagnosticLog.shared.info("[TileKey] tileMode=\(state.tileMode) multiSelection=\(state.multiSelectionCount) items=\(state.effectiveSelectionIDs)")
            if state.tileMode {
                exitTileMode()
            } else if !selectedWindowsForActions().isEmpty {
                tileSelectedItems()
            } else {
                enterTileMode()
            }
            return nil
        }

        // D key (keyCode 2): detach selected projects or distribute selected windows
        if keyCode == 2 && state.focus != .search {
            if detachSelectedProjects() {
                return nil
            }
            if distributeSelectedWindows() {
                return nil
            }
        }

        // Tile mode keys — H/J/K/L/F for tiling selected window
        if state.tileMode && state.focus != .search {
            let tileMap: [UInt16: TilePosition] = [
                4:  .left,       // H = left half
                37: .right,      // L = right half
                40: .top,        // K = top half
                38: .bottom,     // J = bottom half
                3:  .maximize,   // F = maximize/fullscreen
                // Quadrants: Y U B N
                16: .topLeft,    // Y = top-left
                32: .topRight,   // U = top-right
                11: .bottomLeft, // B = bottom-left
                45: .bottomRight,// N = bottom-right
            ]
            if let position = tileMap[keyCode] {
                tileSelectedWindow(to: position)
                return nil
            }
        }

        // / key (keyCode 44): enter search mode
        if keyCode == 44 && state.focus != .search {
            state.focus = .search
            return nil
        }

        // [ key (keyCode 33): cycle layer prev
        if keyCode == 33 && state.focus != .search {
            let ws = WorkspaceManager.shared
            if let layers = ws.config?.layers, !layers.isEmpty {
                let prev = ws.activeLayerIndex <= 0 ? layers.count - 1 : ws.activeLayerIndex - 1
                ws.focusLayer(index: prev)
            }
            return nil
        }

        // ] key (keyCode 30): cycle layer next
        if keyCode == 30 && state.focus != .search {
            let ws = WorkspaceManager.shared
            if let layers = ws.config?.layers, !layers.isEmpty {
                let next = (ws.activeLayerIndex + 1) % layers.count
                ws.focusLayer(index: next)
            }
            return nil
        }

        // Number keys 1-2: jump to section (when not in search)
        if state.focus != .search {
            let numberMap: [UInt16: Int] = [18: 1, 19: 2]
            if let num = numberMap[keyCode], let offset = state.sectionOffsets[num] {
                state.focus = .list
                if let item = state.flatItems[safe: offset] {
                    state.selectSingle(item, index: offset)
                }
                return nil
            }
        }

        // In search mode, pass through to text field
        if state.focus == .search { return event }

        return event
    }

    private func toggleVoice() {
        playTap()
        state.voiceActive.toggle()
        if state.voiceActive {
            HandsOffSession.shared.start()
            HandsOffSession.shared.toggle()
        } else {
            if HandsOffSession.shared.state == .listening {
                HandsOffSession.shared.toggle()
            }
        }
    }

    private var tapSound: NSSound? = {
        guard let url = Bundle.main.url(forResource: "tap", withExtension: "wav") else { return nil }
        return NSSound(contentsOf: url, byReference: true)
    }()

    private func playTap() {
        tapSound?.stop()
        tapSound?.play()
    }

    // MARK: - Tile mode

    /// Pre-compute tile grid on HUD show — top 10 frontmost windows, grid positions ready
    private func precomputeTileGrid(on screen: NSScreen) {
        let sf = screen.visibleFrame
        let primaryH = NSScreen.screens.first?.frame.height ?? 900
        let screenCGX = sf.origin.x
        let screenCGY = primaryH - sf.origin.y - sf.height

        // Get the focused window's wid via AX (always include it)
        let focusedWid: UInt32? = {
            guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var focusedValue: AnyObject?
            guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedValue) == .success else { return nil }
            let axWin = focusedValue as! AXUIElement
            var widValue: CGWindowID = 0
            let result = _AXUIElementGetWindow(axWin, &widValue)
            return result == .success ? UInt32(widValue) : nil
        }()

        // Front 6 by z-order (most recently used first).
        let allOnScreen = DesktopModel.shared.allWindows()
            .filter { $0.isOnScreen && $0.app != "Lattices" && !$0.title.isEmpty }
            .filter { win in
                let cx = win.frame.x + win.frame.w / 2
                let cy = win.frame.y + win.frame.h / 2
                return cx >= Double(screenCGX) && cx < Double(screenCGX + sf.width) &&
                       cy >= Double(screenCGY) && cy < Double(screenCGY + sf.height)
            }

        let log = DiagnosticLog.shared
        log.info("[TileGrid.input] screenSize=\(sf.width)x\(sf.height) onScreen=\(allOnScreen.count)")
        for (i, w) in allOnScreen.prefix(10).enumerated() {
            log.info("[TileGrid.eval] #\(i) z=\(w.zIndex) app=\(w.app) title=\(w.title.prefix(30))")
        }

        var windows = Array(allOnScreen.prefix(6))

        // Ensure the focused window is always included
        if let fwid = focusedWid,
           !windows.contains(where: { $0.wid == fwid }),
           let focusedWin = allOnScreen.first(where: { $0.wid == fwid }) {
            if windows.count >= 6 {
                windows[windows.count - 1] = focusedWin // swap out last
            } else {
                windows.append(focusedWin)
            }
            log.info("[TileGrid.focused] swapped in focusedWid=\(fwid) (\(focusedWin.app): \(focusedWin.title.prefix(30)))")
        }

        log.info("[TileGrid.result] picked=\(windows.count)")

        let count = windows.count
        guard count > 0 else { state.precomputedGrid = []; return }

        let cols = Int(ceil(sqrt(Double(count))))
        let rows = Int(ceil(Double(count) / Double(cols)))
        let cellW = sf.width / CGFloat(cols)
        let cellH = sf.height / CGFloat(rows)
        let gap: CGFloat = 2

        state.precomputedGrid = windows.enumerated().map { (i, win) in
            let col = i % cols
            let row = i / cols
            let frame = CGRect(
                x: screenCGX + CGFloat(col) * cellW + gap,
                y: screenCGY + CGFloat(row) * cellH + gap,
                width: cellW - gap * 2,
                height: cellH - gap * 2
            )
            return (win.wid, win.pid, frame)
        }
    }

    private func enterTileMode() {
        guard !state.precomputedGrid.isEmpty else { return }

        // Snapshot current positions (for restore on dismiss)
        state.tileSnapshot = state.precomputedGrid.map { move in
            // Look up current frame from DesktopModel
            let win = DesktopModel.shared.windows[move.wid]
            let currentFrame = win.map {
                CGRect(x: $0.frame.x, y: $0.frame.y, width: $0.frame.w, height: $0.frame.h)
            } ?? CGRect.zero
            return HUDState.WindowSnapshot(wid: move.wid, pid: move.pid, frame: currentFrame)
        }
        state.tiledWindows = []
        state.tileMode = true

        // Apply pre-computed grid — instant
        WindowTiler.batchMoveAndRaiseWindows(state.precomputedGrid)

        // Auto-expand minimap
        if state.minimapMode != .expanded {
            state.minimapMode = .expanded
        }

        // Select first window
        let firstWid = state.precomputedGrid.first?.wid
        if let wid = firstWid,
           let win = DesktopModel.shared.windows[wid],
           let idx = state.flatItems.firstIndex(of: .window(win)) {
            state.focus = .list
            state.selectedIndex = idx
            state.selectedItem = .window(win)
        }

        playTap()
    }

    private func exitTileMode() {
        state.tileMode = false
        playTap()
    }

    private func tileSelectedWindow(to position: TilePosition) {
        guard let item = state.selectedItem,
              case .window(let win) = item else { return }

        let screen = positionedScreen ?? mouseScreen()
        let frame = WindowTiler.tileFrame(for: position, on: screen)
        WindowTiler.batchMoveAndRaiseWindows([(win.wid, win.pid, frame)])

        state.tiledWindows.insert(win.wid)
        playTap()
    }

    /// Restore windows that weren't explicitly tiled back to their original positions
    private func restoreUntiled() {
        guard !state.tileSnapshot.isEmpty else { return }

        var restores: [(wid: UInt32, pid: Int32, frame: CGRect)] = []
        for snap in state.tileSnapshot {
            if !state.tiledWindows.contains(snap.wid) {
                restores.append((snap.wid, snap.pid, snap.frame))
            }
        }

        if !restores.isEmpty {
            WindowTiler.batchMoveAndRaiseWindows(restores)
        }

        state.tileSnapshot = []
        state.tiledWindows = []
        state.tileMode = false
    }

    /// Tile only the multi-selected windows from the sidebar
    private func tileSelectedItems() {
        let windows = selectedWindowsForActions()
        guard !windows.isEmpty else { return }

        let screen = positionedScreen ?? mouseScreen()
        let sf = screen.visibleFrame
        let primaryH = NSScreen.screens.first?.frame.height ?? 900
        let screenCGX = sf.origin.x
        let screenCGY = primaryH - sf.origin.y - sf.height

        // Snapshot for restore
        state.tileSnapshot = windows.map { win in
            HUDState.WindowSnapshot(
                wid: win.wid, pid: win.pid,
                frame: CGRect(x: win.frame.x, y: win.frame.y,
                              width: win.frame.w, height: win.frame.h)
            )
        }
        state.tiledWindows = []
        state.tileMode = true

        // Grid layout
        let count = windows.count
        let cols = Int(ceil(sqrt(Double(count))))
        let rows = Int(ceil(Double(count) / Double(cols)))
        let cellW = sf.width / CGFloat(cols)
        let cellH = sf.height / CGFloat(rows)
        let gap: CGFloat = 2

        var moves: [(wid: UInt32, pid: Int32, frame: CGRect)] = []
        for (i, win) in windows.enumerated() {
            let col = i % cols
            let row = i / cols
            let frame = CGRect(
                x: screenCGX + CGFloat(col) * cellW + gap,
                y: screenCGY + CGFloat(row) * cellH + gap,
                width: cellW - gap * 2,
                height: cellH - gap * 2
            )
            moves.append((win.wid, win.pid, frame))
        }

        WindowTiler.batchMoveAndRaiseWindows(moves)
        state.precomputedGrid = moves

        // Expand minimap
        if state.minimapMode != .expanded { state.minimapMode = .expanded }

        playTap()
        DiagnosticLog.shared.info("[TileGrid.selected] tiled \(windows.count) selected windows")
    }

    private func detachSelectedProjects() -> Bool {
        let projects = selectedProjectsForActions().filter(\.isRunning)
        guard !projects.isEmpty else { return false }

        for project in projects {
            SessionManager.detach(project: project)
        }

        playTap()
        DiagnosticLog.shared.info("[Detach.selected] detached \(projects.count) project(s)")
        dismiss()
        return true
    }

    private func distributeSelectedWindows() -> Bool {
        let windows = selectedWindowsForActions()
        guard windows.count > 1 else { return false }

        WindowTiler.batchRaiseAndDistribute(windows: windows.map { (wid: $0.wid, pid: $0.pid) })
        playTap()
        DiagnosticLog.shared.info("[Distribute.selected] distributed \(windows.count) window(s)")
        return true
    }

    private func selectedProjectsForActions() -> [Project] {
        let ids = state.effectiveSelectionIDs
        guard !ids.isEmpty else { return [] }

        return state.flatItems.compactMap { item in
            guard ids.contains(item.id), case .project(let project) = item else { return nil }
            return project
        }
    }

    private func selectedWindowsForActions() -> [WindowEntry] {
        let ids = state.effectiveSelectionIDs
        guard !ids.isEmpty else { return [] }

        var seen = Set<UInt32>()
        var windows: [WindowEntry] = []

        for item in state.flatItems {
            guard ids.contains(item.id) else { continue }

            switch item {
            case .window(let window):
                if seen.insert(window.wid).inserted {
                    windows.append(window)
                }
            case .project(let project):
                guard project.isRunning else { continue }
                let projectWindows = DesktopModel.shared.allWindows().filter { $0.latticesSession == project.sessionName }
                for window in projectWindows where seen.insert(window.wid).inserted {
                    windows.append(window)
                }
            }
        }

        return windows
    }

    private func activateItem(_ item: HUDItem) {
        switch item {
        case .project(let p):  SessionManager.launch(project: p)
        case .window(let w):   _ = WindowTiler.focusWindow(wid: w.wid, pid: w.pid)
        }
        dismiss()
    }

    // MARK: - Event monitors

    private func installMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event) ?? event
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.dismiss() }
                return
            }
            let loc = NSEvent.mouseLocation
            let inAny = self.allPanels
                .compactMap { $0 }
                .contains { $0.frame.contains(loc) }
            if !inAny { self.dismiss() }
        }
    }

    private func removeMonitors() {
        if let m = keyMonitor   { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
    }

    private func mouseScreen() -> NSScreen {
        let loc = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(loc) })
            ?? NSScreen.main ?? NSScreen.screens.first!
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
