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

    func toggle() {
        if isVisible { dismiss() } else { show() }
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
        state.focus = .list

        let screen = mouseScreen()
        if positionedScreen != screen { positionAllPanels(on: screen) }

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

        // Escape: search → list, otherwise dismiss
        if keyCode == 53 {
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

        // Down arrow
        if keyCode == 125 {
            if state.focus == .search {
                state.focus = .list
                state.selectedIndex = 0
                state.selectedItem = state.flatItems[safe: 0]
            } else if state.focus == .list {
                moveSelection(1)
            }
            return nil
        }

        // Up arrow
        if keyCode == 126 {
            if state.focus == .list {
                if state.selectedIndex == 0 {
                    state.focus = .search
                } else {
                    moveSelection(-1)
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
                state.selectedIndex = offset
                state.selectedItem = state.flatItems[safe: offset]
                return nil
            }
        }

        // In search mode, pass through to text field
        if state.focus == .search { return event }

        return event
    }

    private func moveSelection(_ delta: Int) {
        let items = state.flatItems
        guard !items.isEmpty else { return }
        let next = max(0, min(items.count - 1, state.selectedIndex + delta))
        state.selectedIndex = next
        state.selectedItem = items[safe: next]
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
