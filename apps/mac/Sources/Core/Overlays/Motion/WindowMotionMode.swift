import AppKit
import SwiftUI

// MARK: - WindowMotionMode
//
// A keyboard-driven "quick motion" mode for moving/tiling real desktop windows.
// Trigger (Hyper+Space) arms a transparent key-capturing overlay. Plain vim/
// arrow keys fling the active window into a tile; Tab points at other windows
// and Space "plucks" them into a group you can grid with G. Moves animate the
// real window with a little drift/wind-up (see RealWindowAnimator).

final class WindowMotionMode {
    static let shared = WindowMotionMode()
    private var panel: MotionPanel?

    var isActive: Bool { panel != nil }

    func toggle() {
        if isActive { deactivate() } else { activate() }
    }

    func activate() {
        guard panel == nil else { return }
        let t0 = CACurrentMediaTime()
        DesktopModel.shared.forcePoll()
        let tPoll = CACurrentMediaTime()
        // Eligible = real app windows (never our own), frontmost first.
        let myPid = ProcessInfo.processInfo.processIdentifier
        let eligible = DesktopModel.shared.allWindows()
            .filter { $0.pid != myPid && $0.isOnScreen && !$0.title.isEmpty }
            .sorted { $0.zIndex < $1.zIndex }
        guard !eligible.isEmpty else {
            DiagnosticLog.shared.warn("MotionMode: no eligible app window to act on")
            NSSound.beep()
            return
        }
        let tEligible = CACurrentMediaTime()
        let p = MotionPanel(eligible: eligible)
        p.loadStart = t0
        let tInit = CACurrentMediaTime()
        p.onExit = { [weak self] in self?.deactivate() }
        panel = p
        p.present()
        let tUp = CACurrentMediaTime()
        // Time-to-load profile (the async capture + first-paint marks land later,
        // logged from the panel). Read it back from ~/.lattices/lattices.log.
        DiagnosticLog.shared.info(String(
            format: "Hyperspace load — poll %.1f · build %.1f · init %.1f · present+expose %.1f · on-screen %.1fms (from trigger)",
            (tPoll - t0) * 1000, (tEligible - tPoll) * 1000, (tInit - tEligible) * 1000,
            (tUp - tInit) * 1000, (tUp - t0) * 1000))
    }

    func deactivate() {
        panel?.dismiss()
        panel = nil
    }
}

// MARK: - Motion key mapping

private enum MotionSide { case left, right, top, bottom }

private enum MotionKeys {
    static func side(_ code: UInt16) -> MotionSide? {
        switch code {
        case 4, 123:  return .left
        case 37, 124: return .right
        case 40, 126: return .top
        case 38, 125: return .bottom
        default:      return nil
        }
    }

    static func special(_ code: UInt16) -> TilePosition? {
        switch code {
        case 16:    return .topLeft     // y
        case 32:    return .topRight    // u
        case 11:    return .bottomLeft  // b
        case 45:    return .bottomRight // n
        case 3:     return .maximize    // f
        case 8:     return .center      // c
        default:    return nil
        }
    }

    static func arrow(_ code: UInt16) -> CGVector? {
        switch code {
        case 123: return CGVector(dx: -1, dy: 0)
        case 124: return CGVector(dx: 1, dy: 0)
        case 126: return CGVector(dx: 0, dy: -1)
        case 125: return CGVector(dx: 0, dy: 1)
        default:  return nil
        }
    }
}

// MARK: - MotionPanel

private final class MotionPanel: NSPanel {
    var onExit: (() -> Void)?
    var loadStart: CFTimeInterval = 0          // set by activate(); base for load-profile marks

    private var firstPaintAt: CFTimeInterval = 0
    private var capturesAt: CFTimeInterval = 0
    private var captureCount = 0

    private let eligible: [WindowEntry]
    private var reticle = 0                          // index of the active window
    private var group: Set<UInt32> = []             // plucked window ids
    private var resolved: [UInt32: AXUIElement] = [:]
    private var animators: [UInt32: RealWindowAnimator] = [:]
    private var borderLayers: [CALayer] = []
    private var originalFrames: [UInt32: CGRect] = [:]   // for Esc-undo
    private var exposed = false                          // Exposé spread is laid out

    private var lastSide: MotionSide?
    private var cycleStep = 0
    private var ignoreResign = false        // swallow the transient key-resign while raising windows
    private let tileGap: CGFloat = 0.02     // even margin for the 2nd-tap "floating half"
    private let exposeGap: CGFloat = 0.012  // gutter between cells in the Exposé spread
    private let nudgeStep: CGFloat = 60
    private let resizeStep: CGFloat = 60

    private var legendHost: NSHostingView<MotionLegend>?
    private var stackHost: NSHostingView<MotionStack>?
    private var chromeHost: NSView?                       // bottom layer-host for window borders/previews
    private var thumbs: [UInt32: NSImage] = [:]          // cached window snapshots
    private var captureFrame: [UInt32: CGRect] = [:]     // the frame each capture was taken at
    private var thumbInFlight: Set<UInt32> = []          // de-dupe in-flight captures
    private let stackMargin: CGFloat = 24
    private var keyObserver: Any?

    // Selection order — `group` is membership, `pickOrder` is the order picks were
    // made, which is what the slot numbers (and the gather grid) follow.
    private var pickOrder: [UInt32] = []

    // Screenshot Exposé: real windows never move during the survey. We render a
    // clustered lattice of live captures and pluck by home-row hint key; only the
    // gather (⏎ / G) moves real windows.
    private var exposeHost: NSHostingView<ExposeView>?
    private var exposeClusters: [ExposeCluster] = []      // structural clusters for the spread
    private var exposeOrder: [UInt32] = []                // wids in spread layout order
    private var exposeAim = 0                             // highlighted tile (Tab/Space fallback)
    private var hintFor: [UInt32: String] = [:]          // wid → home-row hint letter
    private var hintMap: [String: UInt32] = [:]          // hint letter → wid
    private var clusterHintFor: [Int: String] = [:]      // cluster id → ⇧-letter (display, uppercase)
    private var clusterHintMap: [String: Int] = [:]      // letter → cluster id (⇧+letter plucks the group)
    private var exposeTileW: CGFloat = 240
    private var clusterRules: [ClusterRule] = []
    private var exposeFrames: [UInt32: CGRect] = [:]   // tile wid → laid-out frame (survey space)
    private lazy var handKeysMode = UserDefaults.standard.bool(forKey: "hyperspace.handKeys")

    private var activeEntry: WindowEntry { eligible[reticle] }

    init(eligible: [WindowEntry]) {
        self.eligible = eligible

        let union = MotionPanel.screensUnion()
        super.init(contentRect: union, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)

        isFloatingPanel = true
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false   // capture clicks so you can pluck windows by clicking
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let host = NSView(frame: NSRect(origin: .zero, size: union.size))
        host.wantsLayer = true
        host.layer?.masksToBounds = false
        contentView = host

        // Window borders/previews draw into this dedicated bottom container so they
        // can never stack above the chrome (instruction strip + minimap), which are
        // added as subviews on top of it.
        let chrome = NSView(frame: NSRect(origin: .zero, size: union.size))
        chrome.wantsLayer = true
        chrome.layer?.masksToBounds = false
        chrome.autoresizingMask = [.width, .height]
        host.addSubview(chrome)
        chromeHost = chrome

        clusterRules = MotionPanel.loadClusterRules()
        seedActiveFromFocus()
        installLegend(on: host)
        installStack(on: host)
        refreshBorders()
        updateStack()
    }

    /// Align the initial active window to the frontmost app's *focused* AX
    /// window — the one the user is actually in — and cache that exact element.
    /// This avoids relying on CGWindowID→AX mapping (unreliable for Chrome etc.).
    private func seedActiveFromFocus() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        let pid = frontApp.processIdentifier
        let appEl = AXUIElementCreateApplication(pid)
        var wref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &wref) == .success,
              let value = wref, CFGetTypeID(value) == AXUIElementGetTypeID() else { return }
        let focused = value as! AXUIElement
        guard let ff = RealWindowAnimator.axFrame(focused) else { return }

        // Point the reticle at the eligible entry whose frame matches the
        // focused window, and pin the resolved element so we act on exactly it.
        var bestIdx: Int?
        var bestDelta = CGFloat.greatestFiniteMagnitude
        for (i, e) in eligible.enumerated() where e.pid == pid {
            let ef = CGRect(x: e.frame.x, y: e.frame.y, width: e.frame.w, height: e.frame.h)
            let d = abs(ef.minX - ff.minX) + abs(ef.minY - ff.minY)
                + abs(ef.width - ff.width) + abs(ef.height - ff.height)
            if d < bestDelta { bestDelta = d; bestIdx = i }
        }
        if let bestIdx, bestDelta < 80 {
            reticle = bestIdx
            resolved[eligible[bestIdx].wid] = focused
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        orderFrontRegardless()
        makeKey()
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: self, queue: .main
        ) { [weak self] _ in
            guard let self, !self.ignoreResign else { return }
            self.onExit?()
        }
        // Hyperspace lands you straight in the survey. E collapses back to plain
        // motion; expose() no-ops to plain mode if there's <2 windows to lay out.
        expose()
    }

    func dismiss() {
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        keyObserver = nil
        animators.values.forEach { $0.cancel() }
        orderOut(nil)
    }

    override func mouseDown(with event: NSEvent) {
        // Click = a targeted pluck: toggle the window under the cursor in/out of the
        // picked set. Like Space, it only *marks* — it never grids or moves a window
        // (that happens later on G / ⏎), so clicking stays calm and predictable.
        let p = event.locationInWindow

        // Ignore clicks on our own HUDs so they don't pluck a window behind them.
        // (The minimap handles its own clicks — clicking a cell deselects it.)
        if let s = stackHost, s.frame.contains(p) { return }
        if let l = legendHost, l.frame.contains(p) { return }

        // In the screenshot survey the spread (ExposeView) and minimap own all
        // clicks. Live-frame plucking here would toggle whatever real window sits
        // under the cursor — a *different* window than the tile you see — so skip it.
        if exposed { return }

        let globalAppKit = CGPoint(x: p.x + frame.origin.x, y: p.y + frame.origin.y)
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let cg = CGPoint(x: globalAppKit.x, y: primaryH - globalAppKit.y)   // CG top-left

        // Hit-test each window's *live* frame so a click lands on what you see.
        let hit = eligible
            .filter { liveFrame(for: $0).contains(cg) }
            .min(by: { $0.zIndex < $1.zIndex })
        guard let hit else { return }

        togglePicked(hit.wid)
        updateLegend()
        refreshBorders()
        updateStack()
    }

    override func keyDown(with event: NSEvent) {
        let code = event.keyCode
        if code == 53 { undoAndExit(); return }             // Esc — cancel: revert all changes + leave
        if code == 36 || code == 76 {                       // Return / keypad Enter — confirm: keep + leave
            if exposed {                                    // gather the plucked, send the rest home, then leave
                DiagnosticLog.shared.info("Motion confirm — gather \(group.count) from Exposé + exit")
                gatherAndExit()
            } else {
                // Deferred gridding: lay the picked set out now (if any), then leave.
                if !group.isEmpty {
                    DiagnosticLog.shared.info("Motion confirm — grid \(group.count) + exit")
                    relayoutGroup()
                } else {
                    DiagnosticLog.shared.info("Motion confirm — keep changes + exit")
                }
                onExit?()
            }
            return
        }
        let mods = event.modifierFlags

        // In the screenshot Exposé survey the keyboard drives a clustered lattice:
        // Tab/Space move & pluck the highlighted tile, a–z pluck by hint letter,
        // G gathers in place, E collapses back. Nothing here moves a real window
        // except the gather (G), matching the "survey on screenshots" model.
        if exposed {
            switch code {
            case 48: exposeAimStep(mods.contains(.shift) ? -1 : 1); return   // Tab — move highlight
            case 49:                                                         // Space — pluck highlighted
                if let wid = exposeOrder[safe: exposeAim] { exposeToggle(wid) }
                return
            case 14 where !mods.contains(.shift): collapseExpose(); return  // E — collapse survey
            case 5  where !mods.contains(.shift): gatherInPlace(); return   // G — gather, stay in mode
            default:
                let ch = event.charactersIgnoringModifiers?.lowercased()
                if mods.contains(.shift), let ch, let cid = clusterHintMap[ch] {
                    exposeToggleCluster(cid)                                 // ⇧a–z — pluck a whole group
                } else if let ch, let wid = hintMap[ch] {
                    exposeToggle(wid)                                        // a–z — pluck by hint
                } else {
                    NSSound.beep()
                }
                return
            }
        }

        switch code {
        case 48:                                            // Tab — point at next/prev window
            moveReticle(mods.contains(.shift) ? -1 : 1)
            return
        case 49:                                            // Space — pluck into group
            togglePluck()
            return
        case 14:                                            // E — toggle the Exposé spread
            toggleExpose()
            return
        case 5:                                             // G — grid the group (in Exposé: gather but stay)
            if exposed { gatherInPlace() } else { distributeGroup() }
            return
        default:
            break
        }

        if mods.contains(.shift), let v = MotionKeys.arrow(code) { nudge(v); return }
        if mods.contains(.option), let v = MotionKeys.arrow(code) { resize(v); return }
        if let s = MotionKeys.side(code) { cycleTile(s); return }
        if let position = MotionKeys.special(code) { tile(position); lastSide = nil; return }
        NSSound.beep()
    }

    /// Command-modified keys arrive here, not in `keyDown`. ⌘L remembers the
    /// current plucked set as a rule-backed Studio layer — the one ⌘-combo we
    /// claim while the survey is up (every letter is a pluck hint in Exposé, so
    /// a bare key won't do).
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.keyCode == 37 {                                // ⌘L — save the pluck as a layer
            saveGroupAsLayer()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Selection

    private func moveReticle(_ delta: Int) {
        let n = eligible.count
        reticle = ((reticle + delta) % n + n) % n
        lastSide = nil
        _ = ax(for: activeEntry)          // resolve + cache
        updateLegend()
        refreshBorders()                  // fake bring-to-front: preview the aimed window in place, don't raise it
        updateStack()
    }

    private func togglePluck() {
        togglePicked(activeEntry.wid)
        // Pluck only *marks* the window — nothing moves. You build the selection
        // calmly, then arrange it when you're ready: G grids in place, ⏎ gathers.
        // (No more re-gridding on every pluck.)
        updateLegend()
        refreshBorders()
        updateStack()
    }

    /// Toggle a window in/out of the picked set, keeping `pickOrder` in sync so
    /// slot numbers (and the gather grid) follow the order you picked things.
    private func togglePicked(_ wid: UInt32) {
        if group.contains(wid) {
            group.remove(wid)
            pickOrder.removeAll { $0 == wid }
        } else {
            group.insert(wid)
            pickOrder.append(wid)
            if let e = eligible.first(where: { $0.wid == wid }) { _ = ax(for: e) }
        }
    }

    /// The picked windows in pick order — the order their slot numbers run and the
    /// order they fill the balanced gather grid (so slot N lands in cell N).
    private func orderedGroup() -> [WindowEntry] {
        pickOrder.compactMap { wid in eligible.first { $0.wid == wid } }
    }

    /// ⌘L — remember the current plucked set as a rule-backed Studio layer. The
    /// rule is inferred from the plucked windows' apps, so it survives restarts
    /// and auto-includes future matching windows. Nothing moves — this only
    /// records the selection — and we stay in the mode so you can keep arranging.
    private func saveGroupAsLayer() {
        let picked = orderedGroup()
        guard !picked.isEmpty else { NSSound.beep(); return }
        let layer = StudioLayerStore.shared.saveFromPluck(picked)
        DiagnosticLog.shared.info("Motion — saved \(picked.count) plucked windows as layer '\(layer.name)' [\(layer.summary)]")
        LayerBezel.shared.show(label: "Saved · \(layer.name)", index: 0, total: 1, allLabels: ["Saved · \(layer.name)"])
    }

    // MARK: - Single-window operations (on the active window)

    /// Same logic for all four sides: a tap puts the window at that side's flush
    /// half; tapping again *when already at that half* advances to the "floating
    /// half" (the same half inset by an even gap on all four sides). Decided from
    /// the window's CURRENT geometry (not session memory), so e.g. a full-width
    /// window always goes to half first, and a floating half toggles back to flush.
    private func cycleTile(_ side: MotionSide) {
        guard let el = ax(for: activeEntry), let cur = RealWindowAnimator.axFrame(el) else { return }

        // Pick the display from the live AX frame, not the stale polled
        // WindowEntry.frame; after a move this keeps repeated taps on the
        // screen where the window actually is.
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let currentCenter = CGPoint(x: cur.midX, y: primaryH - cur.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(currentCenter) }) ?? screen(for: activeEntry) else { return }

        let halfFrame = WindowTiler.tileFrame(fractions: fractions(side, step: 0), on: screen)
        let tolerance: CGFloat = 8
        let alreadyHalf = abs(cur.minX - halfFrame.minX) < tolerance && abs(cur.minY - halfFrame.minY) < tolerance
            && abs(cur.width - halfFrame.width) < tolerance && abs(cur.height - halfFrame.height) < tolerance
        let step = alreadyHalf ? 1 : 0
        lastSide = side
        cycleStep = step
        placeActive(to: WindowTiler.tileFrame(fractions: fractions(side, step: step), on: screen))
    }

    private func fractions(_ side: MotionSide, step: Int) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        if step == 0 {
            switch side {
            case .left:   return TilePosition.left.rect
            case .right:  return TilePosition.right.rect
            case .top:    return TilePosition.top.rect
            case .bottom: return TilePosition.bottom.rect
            }
        }
        // 2nd tap: the same half region, inset by an even gap on all four sides
        // so it floats (the gutter between two floating halves is 2·g).
        let g = tileGap
        switch side {
        case .left:   return (g,       g, 0.5 - 2 * g, 1 - 2 * g)
        case .right:  return (0.5 + g, g, 0.5 - 2 * g, 1 - 2 * g)
        case .top:    return (g,       g, 1 - 2 * g,   0.5 - 2 * g)
        case .bottom: return (g, 0.5 + g, 1 - 2 * g,   0.5 - 2 * g)
        }
    }

    private func tile(_ position: TilePosition) {
        guard let screen = screen(for: activeEntry) else { return }
        placeActive(to: WindowTiler.tileFrame(for: position, on: screen))
    }

    private func nudge(_ v: CGVector) {
        lastSide = nil
        guard let el = ax(for: activeEntry), let cur = RealWindowAnimator.axFrame(el) else { return }
        let target = CGRect(
            x: cur.minX + v.dx * nudgeStep,
            y: cur.minY + v.dy * nudgeStep,
            width: cur.width,
            height: cur.height
        )
        placeActive(to: target)
    }

    private func resize(_ v: CGVector) {
        lastSide = nil
        guard let el = ax(for: activeEntry), let cur = RealWindowAnimator.axFrame(el) else { return }
        let minWidth: CGFloat = 160
        let minHeight: CGFloat = 120
        var target = cur

        if v.dx < 0 {
            target.origin.x -= resizeStep
            target.size.width += resizeStep
        } else if v.dx > 0 {
            target.size.width += resizeStep
        }

        if v.dy < 0 {
            target.origin.y -= resizeStep
            target.size.height += resizeStep
        } else if v.dy > 0 {
            target.size.height += resizeStep
        }

        target.size.width = max(minWidth, target.width)
        target.size.height = max(minHeight, target.height)
        placeActive(to: target)
    }

    /// Place the active window instantly and exactly — snappy, no jittery tween.
    private func placeActive(to target: CGRect) {
        guard let el = ax(for: activeEntry) else { NSSound.beep(); return }
        recordOriginal(activeEntry.wid, el)
        let before = RealWindowAnimator.axFrame(el) ?? .zero
        raising { RealWindowAnimator.setFrameRobust(el, target, pid: activeEntry.pid, raise: true) }
        let after = RealWindowAnimator.axFrame(el) ?? .zero
        DiagnosticLog.shared.info("Motion place \(activeEntry.app) wid=\(activeEntry.wid) step=\(cycleStep) before=\(rectStr(before)) target=\(rectStr(target)) after=\(rectStr(after))")
        refreshBorders()
        updateStack()
    }

    private func rectStr(_ r: CGRect) -> String {
        "(\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height)))"
    }

    private func recordOriginal(_ wid: UInt32, _ el: AXUIElement) {
        if originalFrames[wid] == nil, let cur = RealWindowAnimator.axFrame(el) {
            originalFrames[wid] = cur
        }
    }

    /// Esc: restore every window we moved back to where it started — frame *and*
    /// stacking order — so nothing the session touched is left ahead, then leave.
    private func undoAndExit() {
        for (wid, frame) in originalFrames {
            guard let entry = eligible.first(where: { $0.wid == wid }), let el = ax(for: entry) else { continue }
            RealWindowAnimator.setFrameRobust(el, frame, pid: entry.pid)
        }
        restoreOriginalOrder()
        onExit?()
    }

    /// Re-stack every window in the front-to-back order it had when the mode
    /// opened (`eligible` is sorted frontmost-first). Tab/preview raises only lift
    /// the aimed window transiently; this is what makes them ephemeral — replaying
    /// the original order back→front leaves the original frontmost window on top.
    private func restoreOriginalOrder() {
        raising {
            for entry in eligible.reversed() {
                guard let el = ax(for: entry) else { continue }
                RealWindowAnimator.raise(el)
            }
        }
    }

    // MARK: - Group grid

    private func gridDims(_ n: Int) -> (cols: Int, rows: Int) {
        let cols = max(1, Int(ceil(Double(n).squareRoot())))
        let rows = max(1, Int(ceil(Double(n) / Double(cols))))
        return (cols, rows)
    }

    /// Balanced grid: `n` items in ceil(√n) columns, but each row is centered so a
    /// short final row sits in the middle instead of leaving a lopsided blank corner
    /// (e.g. 3 → two on top, one centered below). Returns normalized rects
    /// (x, y, w, h in 0…1), row-major. Used for the real gather *and* the minimap, so
    /// the two always match.
    private func balancedGrid(_ n: Int) -> [CGRect] {
        guard n > 0 else { return [] }
        let (cols, rows) = gridDims(n)
        let cw = 1 / CGFloat(cols), ch = 1 / CGFloat(rows)
        return (0..<n).map { i in
            let r = i / cols, c = i % cols
            let itemsInRow = min(cols, n - r * cols)
            let xOffset = (1 - CGFloat(itemsInRow) * cw) / 2          // center short rows
            return CGRect(x: xOffset + CGFloat(c) * cw, y: CGFloat(r) * ch, width: cw, height: ch)
        }
    }

    /// Lay the plucked group out live: 2+ windows tile into a grid (each moved
    /// AND raised so it actually comes to the front); a lone window is just
    /// raised. Called on every pluck/unpluck so a position opens up as soon as
    /// you add a window. Moves are real but revertible (Enter confirms, Esc resets).
    private func relayoutGroup() {
        let members = orderedGroup()
        guard let screen = screen(for: activeEntry), !members.isEmpty else { return }
        if members.count == 1 {
            if let el = ax(for: members[0]) { raising { RealWindowAnimator.raise(el) } }
            return
        }
        let rects = balancedGrid(members.count)
        raising {
            for (i, m) in members.enumerated() {
                guard let el = ax(for: m) else { continue }
                let r = rects[i]
                let target = WindowTiler.tileFrame(fractions: (r.minX, r.minY, r.width, r.height), on: screen)
                recordOriginal(m.wid, el)
                RealWindowAnimator.setFrameRobust(el, target, pid: m.pid, raise: true)
                DiagnosticLog.shared.info("Motion grid \(m.app) wid=\(m.wid) target=\(rectStr(target)) after=\(rectStr(RealWindowAnimator.axFrame(el) ?? .zero))")
            }
        }
    }

    /// G — make sure the aimed window is part of the group, then lay out the grid.
    private func distributeGroup() {
        if !group.contains(activeEntry.wid) { togglePicked(activeEntry.wid) }
        relayoutGroup()
        updateLegend()
        refreshBorders()
        updateStack()
    }

    // MARK: - Screenshot Exposé (the lattice survey)
    //
    // E lifts every window on the active display into a *clustered lattice of live
    // captures* — the real windows never move. Tiles are grouped into clusters
    // (your own rules first, then smart by-app) and each wears a home-row hint
    // letter; press it (or click) to pluck. Picks get slot numbers in pick order.
    // ⏎/G gather the picked set into a balanced grid (the only real window moves);
    // E collapses the survey; Esc reverts everything. See study 05 in
    // design/hyperspace-lattice-studio.html for the visual language.

    private func toggleExpose() {
        if exposed { collapseExpose() } else { expose() }
    }

    /// Build the survey: cluster the active-display windows, assign hint letters,
    /// size the tiles, show the spread overlay, and kick off live captures. No
    /// real window is touched — this is a screenshot survey.
    private func expose() {
        guard let screen = screen(for: activeEntry) else { return }
        let members = eligible.filter { entry($0, isOn: screen) }
        guard members.count > 1 else { NSSound.beep(); return }   // nothing to survey

        exposed = true
        exposeFrames.removeAll()                                  // stale positions from a prior survey
        exposeClusters = buildClusters(members)
        assignHints()
        exposeTileW = autoTileWidth(count: members.count, screen: screen)
        installExposeHost(on: screen)
        captureCount = members.count
        members.forEach { captureThumb(for: $0) }                 // seed from the shared cache; capture only misses
        rebuildExposeView()
        checkCapturesSettled()                                     // every tile a cache hit → already done

        // First-paint mark: the next main-loop turn after we install and lay out
        // the spread is a good proxy for "the survey is on screen."
        if firstPaintAt == 0, loadStart > 0 {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.firstPaintAt == 0 else { return }
                self.firstPaintAt = CACurrentMediaTime()
                DiagnosticLog.shared.info(String(format: "Hyperspace load — first paint %.1fms (from trigger)", (self.firstPaintAt - self.loadStart) * 1000))
            }
        }

        DiagnosticLog.shared.info("Motion expose — survey \(members.count) windows in \(exposeClusters.count) clusters")
        updateLegend()
        updateStack()
        refreshBorders()                                          // clears real-window chrome while surveying
    }

    /// E (while surveying) — drop the spread, back to normal motion mode. Picks
    /// are kept (nothing moved), so you can still gather or keep arranging.
    private func collapseExpose() {
        removeExposeHost()
        exposed = false
        updateLegend()
        refreshBorders()
        updateStack()
    }

    /// Gather the picked set into a balanced grid on the active display (the only
    /// place real windows move) and stay in the mode. Un-picked windows are left
    /// exactly where they are — in the survey they never moved. Shared by G and ⏎.
    private func gatherInPlace() {
        removeExposeHost()
        let members = orderedGroup()
        if members.count >= 2 {
            relayoutGroup()                                       // picked set snaps into the grid, on top
        } else if let only = members.first, let el = ax(for: only) {
            raising { RealWindowAnimator.raise(el) }              // a single pick just comes forward
        }
        exposed = false
        updateLegend()
        refreshBorders()
        updateStack()
    }

    private func gatherAndExit() {
        gatherInPlace()
        onExit?()
    }

    // MARK: - Clustering

    /// Group the survey windows into clusters: the user's own rules first (a
    /// cluster is a named rule — see ~/.lattices/clusters.json), then everything
    /// left over smart-clustered by app. Tint stays per-app; the cluster is an
    /// independent grouping axis.
    private func buildClusters(_ members: [WindowEntry]) -> [ExposeCluster] {
        var remaining = members
        var boxes: [ExposeCluster] = []
        var id = 0

        for rule in clusterRules {
            let matched = remaining.filter { rule.matches($0) }
            guard !matched.isEmpty else { continue }
            boxes.append(ExposeCluster(id: id, name: rule.name, rule: rule.summary, userDefined: true, members: matched))
            id += 1
            let matchedIds = Set(matched.map { $0.wid })
            remaining.removeAll { matchedIds.contains($0.wid) }
        }

        let byApp = Dictionary(grouping: remaining) { $0.app }
        for app in byApp.keys.sorted() {
            let ms = (byApp[app] ?? []).sorted { $0.title < $1.title }
            boxes.append(ExposeCluster(id: id, name: app, rule: "app", userDefined: false, members: ms))
            id += 1
        }
        return boxes
    }

    /// Letters the survey reserves for commands, so no tile or cluster is ever dealt
    /// one (E = collapse, G = gather — see keyDown, where their keycodes are matched
    /// before the hint logic). Kept out of every hint pool below, so ⇧E/⇧G carry no
    /// cluster meaning and the bare keys always mean their command.
    private static let reservedKeys: Set<Character> = ["e", "g"]

    /// Assign the spread's layout order and per-window hint letters. Two schemes:
    /// reading-order (clusters in display order) or — when hand-keys mode is on and
    /// we know where the tiles landed — a spatial split where left-of-centre tiles
    /// take left-hand keys and right-of-centre tiles take right-hand keys, each
    /// dealt centre→edge so the strongest fingers land the most central windows.
    /// ⇧-letter cluster plucks are assigned separately (own, shifted key space).
    private func assignHints() {
        exposeOrder = exposeClusters.flatMap { $0.members.map(\.wid) }
        exposeAim = 0
        (hintFor, hintMap) = (handKeysMode && exposeFrames.count >= exposeOrder.count)
            ? computeHandHints(exposeFrames) : readingHints()
        assignClusterHints()
    }

    /// Home-row letters dealt in display order — the original scheme.
    private func readingHints() -> ([UInt32: String], [String: UInt32]) {
        let homerow = Array("asdfghjklqwertyuiopzxcvbnm").filter { !MotionPanel.reservedKeys.contains($0) }
        var hf: [UInt32: String] = [:], hm: [String: UInt32] = [:]
        for (i, wid) in exposeOrder.enumerated() where i < homerow.count {
            let h = String(homerow[i]); hf[wid] = h; hm[h] = wid
        }
        return (hf, hm)
    }

    /// Spatial hand-split letters. Tiles left of the spread's mid-line get left-hand
    /// keys, the rest right-hand keys; within a hand they're dealt centre→edge so the
    /// key location predicts the window's location. Needs the laid-out tile frames.
    private func computeHandHints(_ frames: [UInt32: CGRect]) -> ([UInt32: String], [String: UInt32]) {
        let rightKeys = Array("jkluiophynm;").filter  { !MotionPanel.reservedKeys.contains($0) }   // right hand, centre → edge
        let leftKeys  = Array("fdsarewqgtvcxzb").filter { !MotionPanel.reservedKeys.contains($0) }  // left hand,  centre → edge (e/g reserved)
        let placed = exposeOrder.compactMap { wid in frames[wid].map { (wid: wid, rect: $0) } }
        guard !placed.isEmpty else { return readingHints() }
        let mids = placed.map { $0.rect.midX }
        let mid = (mids.min()! + mids.max()!) / 2
        func sortKey(_ r: CGRect) -> (CGFloat, CGFloat) { (abs(r.midX - mid), r.minY) }
        let left  = placed.filter { $0.rect.midX <= mid }.sorted { sortKey($0.rect) < sortKey($1.rect) }
        let right = placed.filter { $0.rect.midX >  mid }.sorted { sortKey($0.rect) < sortKey($1.rect) }
        var hf: [UInt32: String] = [:], hm: [String: UInt32] = [:]
        for (i, t) in left.enumerated()  where i < leftKeys.count  { let h = String(leftKeys[i]);  hf[t.wid] = h; hm[h] = t.wid }
        for (i, t) in right.enumerated() where i < rightKeys.count { let h = String(rightKeys[i]); hf[t.wid] = h; hm[h] = t.wid }
        return (hf, hm)
    }

    /// Recompute per-window hints after the spread lays out, or when the mode flips.
    /// Idempotent — only rebuilds the view if the letters actually changed.
    private func reassignHandHints() {
        guard exposed else { return }
        let (hf, hm) = (handKeysMode && exposeFrames.count >= exposeOrder.count)
            ? computeHandHints(exposeFrames) : readingHints()
        guard hf != hintFor else { return }
        hintFor = hf; hintMap = hm
        rebuildExposeView()
    }

    /// Per-cluster shortcut: ⇧+letter plucks the whole group at once (e.g. ⇧I →
    /// every iTerm). Prefer a letter from the cluster's name so it's guessable,
    /// falling back to the next free letter. Lives in its own (shifted) key space,
    /// so it never collides with the lowercase per-window hints above.
    private func assignClusterHints() {
        clusterHintFor.removeAll(); clusterHintMap.removeAll()
        var used = Set<String>()
        let alphabet = "abcdefghijklmnopqrstuvwxyz".map(String.init)
        for box in exposeClusters {
            let fromName = box.name.lowercased().filter { $0.isLetter }.map(String.init)
            guard let letter = (fromName + alphabet).first(where: {
                !used.contains($0) && !MotionPanel.reservedKeys.contains(Character($0))
            }) else { continue }
            used.insert(letter)
            clusterHintFor[box.id] = letter.uppercased()
            clusterHintMap[letter] = box.id
        }
    }

    /// Pick a tile width that fills the survey: few windows zoom in, many zoom out.
    /// A free-grid fit over the display's working area — try every column count and
    /// keep the width that best uses both axes — then a packing margin and clamps so
    /// the clustered layout (a little less dense than a bare grid) still fits cleanly.
    private func autoTileWidth(count n: Int, screen: NSScreen) -> CGFloat {
        let area = screen.frame
        let pad: CGFloat = 72            // 36pt survey padding each side
        let availW = max(200, area.width - pad)
        let availH = max(200, area.height - pad)
        let aspect: CGFloat = 0.62       // tile height / width
        let gap: CGFloat = 26            // tile gaps + cluster chrome, averaged
        let count = max(1, n)
        var best: CGFloat = 0
        let maxCols = max(1, min(count, Int(availW / 150)))
        for cols in 1...maxCols {
            let rows = Int((Double(count) / Double(cols)).rounded(.up))
            let w = (availW - gap * CGFloat(cols - 1)) / CGFloat(cols)
            let h = (availH - gap * CGFloat(rows - 1)) / CGFloat(rows)
            best = max(best, min(w, h / aspect))
        }
        // Packing margin: sit the survey a little inside the fill so there's air
        // around the lattice — the extra room reads as perspective, not a wall of tiles.
        return min(max((best * 0.74).rounded(), 150), 520)
    }

    private static func loadClusterRules() -> [ClusterRule] {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".lattices/clusters.json")
        guard let data = try? Data(contentsOf: url),
              let rules = try? JSONDecoder().decode([ClusterRule].self, from: data) else { return [] }
        return rules
    }

    // MARK: - Survey overlay (SwiftUI spread)

    private func installExposeHost(on screen: NSScreen) {
        let hosting = NSHostingView(rootView: ExposeView(clusters: [], tileWidth: exposeTileW))
        hosting.frame = panelLocal(screen.frame)                  // dim + spread the active display
        // Sit beneath the legend/minimap HUDs so they stay readable over the survey.
        if let below = legendHost ?? stackHost {
            contentView?.addSubview(hosting, positioned: .below, relativeTo: below)
        } else {
            contentView?.addSubview(hosting)
        }
        exposeHost = hosting
    }

    private func removeExposeHost() {
        exposeHost?.removeFromSuperview()
        exposeHost = nil
    }

    /// Rebuild the spread's view-model from current picks/aim/captures. Cheap —
    /// the cluster *structure* is fixed for the life of a survey; only the per-tile
    /// pick slot, highlight, and image change.
    private func rebuildExposeView() {
        guard exposed, let exposeHost else { return }
        let vm = exposeClusters.map { box in
            ExposeView.Cluster(
                id: box.id, name: box.name, rule: box.rule, userDefined: box.userDefined,
                hint: clusterHintFor[box.id] ?? "",
                tiles: box.members.map { tileVM($0) }
            )
        }
        exposeHost.rootView = ExposeView(
            clusters: vm, tileWidth: exposeTileW,
            onPick: { [weak self] wid in self?.exposeToggle(wid) },
            onLayout: { [weak self] frames in
                guard let self else { return }
                DispatchQueue.main.async {
                    guard self.exposed, frames != self.exposeFrames else { return }
                    self.exposeFrames = frames
                    if self.handKeysMode { self.reassignHandHints() }
                }
            },
            onHandKeys: { [weak self] on in
                guard let self else { return }
                self.handKeysMode = on
                self.reassignHandHints()
            },
            loadSummary: loadSummaryText())
    }

    /// Compact load readout for the survey: time-to-first-paint and time-to-all-
    /// captures, both measured from the Hyper+Space trigger. "…" until the mark lands.
    private func loadSummaryText() -> String {
        guard loadStart > 0 else { return "" }
        func ms(_ t: CFTimeInterval) -> String { t > 0 ? "\(Int(((t - loadStart) * 1000).rounded()))" : "…" }
        return "up \(ms(firstPaintAt))ms · caps \(ms(capturesAt))ms·\(captureCount)"
    }

    private func tileVM(_ w: WindowEntry) -> ExposeView.Tile {
        ExposeView.Tile(
            id: w.wid, app: w.app, title: w.title,
            tint: Color(nsColor: MotionPanel.tint(for: w.app)),
            image: thumbs[w.wid],
            hint: hintFor[w.wid] ?? "",
            pickSlot: pickOrder.firstIndex(of: w.wid).map { $0 + 1 },
            isAimed: exposeOrder[safe: exposeAim] == w.wid
        )
    }

    /// Pluck a tile by wid (hint key or click) and refresh the survey + minimap.
    private func exposeToggle(_ wid: UInt32) {
        togglePicked(wid)
        rebuildExposeView()
        updateLegend()
        updateStack()
    }

    /// ⇧+letter — pluck a whole cluster at once (e.g. all iTerms). If the group is
    /// already fully picked it unplucks the group; otherwise it adds the members
    /// that aren't picked yet. Toggling on the "all-picked" state makes the same key
    /// select then clear the group.
    private func exposeToggleCluster(_ id: Int) {
        guard let box = exposeClusters.first(where: { $0.id == id }) else { NSSound.beep(); return }
        let wids = box.members.map { $0.wid }
        guard !wids.isEmpty else { return }
        let allPicked = wids.allSatisfy { group.contains($0) }
        for wid in wids {
            let picked = group.contains(wid)
            if allPicked && picked { togglePicked(wid) }          // clear the whole group
            else if !allPicked && !picked { togglePicked(wid) }   // fill in the missing members
        }
        rebuildExposeView()
        updateLegend()
        updateStack()
    }

    /// Clicking a minimap cell deselects it — the requested "unpluck with the
    /// mouse" path, working in both the survey and plain motion mode.
    private func minimapToggle(_ wid: UInt32) {
        togglePicked(wid)
        if exposed { rebuildExposeView() }
        updateLegend()
        refreshBorders()
        updateStack()
    }

    /// Move the Tab/Space highlight across the spread in layout order.
    private func exposeAimStep(_ delta: Int) {
        guard !exposeOrder.isEmpty else { return }
        let n = exposeOrder.count
        exposeAim = ((exposeAim + delta) % n + n) % n
        rebuildExposeView()
    }

    /// True if the window's center sits on `screen` (AppKit coords, like screen(for:)).
    private func entry(_ e: WindowEntry, isOn screen: NSScreen) -> Bool {
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let center = CGPoint(x: e.frame.x + e.frame.w / 2, y: primaryH - (e.frame.y + e.frame.h / 2))
        return screen.frame.contains(center)
    }

    /// Run window-raising work while swallowing the transient key-resign it can
    /// trigger, so the overlay doesn't auto-exit mid-operation.
    private func raising(_ body: () -> Void) {
        ignoreResign = true
        body()
        DispatchQueue.main.async { [weak self] in self?.ignoreResign = false }
    }

    // MARK: - AX resolution (cached per window)

    private func ax(for entry: WindowEntry) -> AXUIElement? {
        if let cached = resolved[entry.wid] { return cached }
        let expected = CGRect(x: entry.frame.x, y: entry.frame.y, width: entry.frame.w, height: entry.frame.h)
        let el = RealWindowAnimator.resolve(wid: entry.wid, pid: entry.pid, expectedFrame: expected)
        resolved[entry.wid] = el
        return el
    }

    /// The window's current on-screen frame in CG (top-left) coords — the live AX
    /// frame when we can resolve it (windows move during a spread/tile), else the
    /// polled frame. Used for click hit-testing so a click lands on what you see.
    private func liveFrame(for entry: WindowEntry) -> CGRect {
        if let el = ax(for: entry), let f = RealWindowAnimator.axFrame(el) { return f }
        return CGRect(x: entry.frame.x, y: entry.frame.y, width: entry.frame.w, height: entry.frame.h)
    }

    // MARK: - Borders (drawn in the always-on-top overlay)

    private func refreshBorders() {
        guard let root = chromeHost?.layer else { return }
        borderLayers.forEach { $0.removeFromSuperlayer() }
        borderLayers.removeAll()

        // During the screenshot survey the SwiftUI spread (ExposeView) draws
        // everything; real-window chrome would just double up behind it.
        if exposed { return }

        let activeWid = activeEntry.wid

        // Outlines for the picked set (always) and, in Exposé, every spread window —
        // drawn first so the aimed window's preview sits on top of them. The aimed
        // window is handled separately below.
        for entry in eligible where entry.wid != activeWid {
            let inGroup = group.contains(entry.wid)
            guard inGroup || exposed else { continue }
            guard let el = ax(for: entry), let axf = RealWindowAnimator.axFrame(el) else { continue }
            let local = panelLocal(appKitFrame(fromAX: axf))
            let layer = CALayer()
            layer.frame = local
            layer.cornerRadius = 10
            layer.cornerCurve = .continuous
            layer.borderWidth = 1.5
            let color = MotionPanel.tint(for: entry.app)
            // Un-picked spread windows sit back at a dim alpha; picked read fuller.
            layer.borderColor = color.withAlphaComponent(inGroup ? 0.6 : 0.28).cgColor
            if inGroup { layer.backgroundColor = color.withAlphaComponent(0.05).cgColor }
            root.addSublayer(layer)
            borderLayers.append(layer)
        }

        // The aimed window — a *fake* bring-to-front. We never raise the real window
        // (cycling stays ephemeral, nothing on the desktop is re-stacked); instead we
        // lift its live capture on top, at its actual frame, with a soft shadow so it
        // reads as forward in place even when real neighbours overlap it.
        guard let el = ax(for: activeEntry), let axf = RealWindowAnimator.axFrame(el) else { return }
        let local = panelLocal(appKitFrame(fromAX: axf))

        // Only lift the capture while it still matches the window's current size. The
        // shot is cached at one size; after a tile/resize (full-width, half, maximize)
        // the window jumps to a very different shape and a stretched screenshot looks
        // awkward — so we drop it and just frame the correctly-sized real window.
        let sizeMatches = captureFrame[activeWid].map {
            abs($0.width - axf.width) <= max(8, axf.width * 0.03)
                && abs($0.height - axf.height) <= max(8, axf.height * 0.03)
        } ?? false

        if sizeMatches, let img = thumbs[activeWid], let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            // Shadow plate: its black body is fully covered by the capture above, so
            // only the blurred edge spills out and sells the lift.
            let shadow = CALayer()
            shadow.frame = local
            shadow.cornerRadius = 10
            shadow.cornerCurve = .continuous
            shadow.backgroundColor = NSColor.black.cgColor
            shadow.shadowColor = NSColor.black.cgColor
            shadow.shadowOpacity = 0.45
            shadow.shadowRadius = 20
            shadow.shadowOffset = CGSize(width: 0, height: -8)
            root.addSublayer(shadow)
            borderLayers.append(shadow)

            let preview = CALayer()
            preview.frame = local
            preview.cornerRadius = 10
            preview.cornerCurve = .continuous
            preview.masksToBounds = true
            preview.contentsGravity = .resizeAspectFill
            preview.contents = cg
            root.addSublayer(preview)
            borderLayers.append(preview)
        }
        // The capture lands asynchronously (captureThumb → refreshBorders); until it
        // does we draw only the border and the real window shows through underneath.

        let border = CALayer()
        border.frame = local
        border.cornerRadius = 10
        border.cornerCurve = .continuous
        border.borderWidth = 2
        border.borderColor = NSColor.white.withAlphaComponent(0.95).cgColor
        root.addSublayer(border)
        borderLayers.append(border)
    }

    // MARK: - Geometry

    private func appKitFrame(fromAX ax: CGRect) -> NSRect {
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: ax.origin.x, y: primaryH - ax.origin.y - ax.height, width: ax.width, height: ax.height)
    }

    private func panelLocal(_ global: NSRect) -> NSRect {
        NSRect(x: global.minX - frame.origin.x, y: global.minY - frame.origin.y,
               width: global.width, height: global.height)
    }

    private func screen(for entry: WindowEntry) -> NSScreen? {
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let cx = entry.frame.x + entry.frame.w / 2
        let cy = primaryH - (entry.frame.y + entry.frame.h / 2)
        let center = CGPoint(x: cx, y: cy)
        return NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    private static func screensUnion() -> NSRect {
        NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }
    }

    static func tint(for app: String) -> NSColor {
        var v: UInt64 = 5381
        for b in app.utf8 { v = (v &* 33) &+ UInt64(b) }
        let hue = CGFloat(v % 360) / 360.0
        return NSColor(hue: hue, saturation: 0.58, brightness: 0.98, alpha: 1)
    }

    // MARK: - Legend

    private func installLegend(on host: NSView) {
        let hosting = NSHostingView(rootView: legendModel())
        let size = hosting.fittingSize
        let screenFrame = (screen(for: activeEntry) ?? NSScreen.main)?.frame ?? frame
        let x = screenFrame.midX - size.width / 2 - frame.origin.x
        let y = screenFrame.minY + 70 - frame.origin.y
        hosting.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
        host.addSubview(hosting)
        legendHost = hosting
    }

    private func updateLegend() {
        legendHost?.rootView = legendModel()
        if let hosting = legendHost {
            let size = hosting.fittingSize
            let screenFrame = (screen(for: activeEntry) ?? NSScreen.main)?.frame ?? frame
            hosting.frame = NSRect(x: screenFrame.midX - size.width / 2 - frame.origin.x,
                                   y: screenFrame.minY + 70 - frame.origin.y,
                                   width: size.width, height: size.height)
        }
        raiseLegend()
    }

    /// Keep the instruction strip at the highest z-index at all times — above the
    /// minimap and the Exposé spread — so it stays readable and clickable no matter
    /// what else gets added to the overlay.
    private func raiseLegend() {
        guard let legendHost, let superview = legendHost.superview else { return }
        superview.addSubview(legendHost, positioned: .above, relativeTo: nil)
    }

    private func legendModel() -> MotionLegend {
        MotionLegend(app: activeEntry.app,
                     tint: Color(nsColor: MotionPanel.tint(for: activeEntry.app)),
                     groupCount: group.count,
                     exposed: exposed)
    }

    // MARK: - Snapshot stack (bottom-left)
    //
    // A vertical stack of live window snapshots so the selection is concrete:
    // the active (aimed) window on top, plucked group members below. Snapshots
    // come from ScreenCaptureKit per-window capture, so an occluded window still
    // shows its real content — fixing the "phantom selection" feel.

    private func installStack(on host: NSView) {
        let hosting = NSHostingView(rootView: MotionStack(cells: []))
        // Keep the minimap beneath the instruction strip so the strip is never hidden.
        if let legendHost {
            host.addSubview(hosting, positioned: .below, relativeTo: legendHost)
        } else {
            host.addSubview(hosting)
        }
        stackHost = hosting
        positionStack()
    }

    private func updateStack() {
        guard let stackHost else { return }
        let activeWid = activeEntry.wid
        let groupMembers = orderedGroup()                                   // picked set, in pick order

        // The minimap mirrors the gather plan: the picked windows in the exact
        // balanced grid they'll snap to. Shown only once you've picked something —
        // while you're just browsing there's nothing to plan, so it stays hidden.
        let rects = balancedGrid(groupMembers.count)
        let cells = groupMembers.enumerated().map { (i, m) in
            MotionStack.Cell(
                id: m.wid,
                tint: Color(nsColor: MotionPanel.tint(for: m.app)),
                image: thumbs[m.wid],
                rect: rects[i],
                slot: i + 1,                                                // pick-order slot number
                isActive: m.wid == activeWid
            )
        }
        let screenFrame = (screen(for: activeEntry) ?? NSScreen.main)?.frame ?? frame
        let aspect = screenFrame.height > 0 ? screenFrame.width / screenFrame.height : 1.6

        stackHost.rootView = MotionStack(cells: cells, aspect: aspect,
                                         onToggle: { [weak self] wid in self?.minimapToggle(wid) })
        positionStack()

        // Capture thumbnails for the active window (its in-place preview) + the
        // picked group (the minimap), cached per wid.
        captureThumb(for: activeEntry)
        groupMembers.forEach { captureThumb(for: $0) }
    }

    /// Bottom-left, anchored at the bottom so the stack grows upward as it fills.
    private func positionStack() {
        guard let stackHost else { return }
        let screenFrame = (screen(for: activeEntry) ?? NSScreen.main)?.frame ?? frame
        let size = stackHost.fittingSize
        stackHost.frame = NSRect(
            x: screenFrame.minX + stackMargin - frame.origin.x,
            y: screenFrame.minY + stackMargin - frame.origin.y,
            width: size.width,
            height: size.height
        )
    }

    private func captureThumb(for entry: WindowEntry) {
        let wid = entry.wid
        guard thumbs[wid] == nil, !thumbInFlight.contains(wid) else { return }

        // Reuse the HUD's warm cache: if the shared store already has this window,
        // use it instantly — no capture. (The store's warmer keeps it stocked.)
        if let cached = WindowPreviewStore.shared.image(for: wid) {
            thumbs[wid] = cached
            captureFrame[wid] = liveFrame(for: entry)
            return
        }

        thumbInFlight.insert(wid)
        let cgWid = CGWindowID(wid)
        Task { @MainActor [weak self] in
            let cg = await WindowCapture.image(
                listOption: .optionIncludingWindow,
                windowID: cgWid,
                imageOption: [.boundsIgnoreFraming, .nominalResolution]
            )
            guard let self else { return }
            self.thumbInFlight.remove(wid)
            guard let cg else { self.checkCapturesSettled(); return }
            self.thumbs[wid] = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            self.captureFrame[wid] = self.liveFrame(for: entry)   // remember the size this shot represents
            WindowPreviewStore.shared.ingest(cgImage: cg, for: wid, frame: entry.frame)  // write back to the shared cache
            self.updateStack()
            if self.exposed { self.rebuildExposeView() }          // a survey tile's capture just landed
            self.checkCapturesSettled()
            // A fresh capture for the aimed window is its fake bring-to-front image.
            if wid == self.activeEntry.wid { self.refreshBorders() }
        }
    }

    /// Mark (once) the moment every survey tile has its image — captures done,
    /// whether they came from the shared cache or a fresh grab.
    private func checkCapturesSettled() {
        guard exposed, thumbInFlight.isEmpty, capturesAt == 0, loadStart > 0 else { return }
        capturesAt = CACurrentMediaTime()
        DiagnosticLog.shared.info(String(format: "Hyperspace load — captures complete %.1fms · %d windows (from trigger)", (capturesAt - loadStart) * 1000, captureCount))
    }
}

// MARK: - Legend view

private struct MotionLegend: View {
    let app: String
    let tint: Color
    let groupCount: Int
    var exposed: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(app)
                    .font(Typo.monoBold(11))
                    .foregroundColor(Palette.text)
                    .lineLimit(1)
                if groupCount > 0 {
                    Text("+\(groupCount)")
                        .font(Typo.monoBold(10))
                        .foregroundColor(Palette.running)
                }
            }

            Rectangle().fill(Palette.border).frame(width: 1, height: 13)

            if exposed {
                keyHint("a–z", "pluck")
                keyHint("⇧a–z", "group")
                keyHint("Tab", "aim")
                keyHint("⏎", "gather")
                if groupCount > 0 { keyHint("⌘L", "save layer") }
                keyHint("E", "collapse")
                keyHint("esc", "cancel")
            } else {
                keyHint("Tab", "aim")
                keyHint("Space", "pluck")
                keyHint("E", "expose")
                keyHint("G", "grid")
                if groupCount > 0 { keyHint("⌘L", "save layer") }
                keyHint("←↑→↓", "half · gap")
                keyHint("⇧/⌥", "nudge/size")
                keyHint("⏎", "confirm")
                keyHint("esc", "cancel")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.black.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 0.5)
                )
        )
        .fixedSize()
    }

    private func keyHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(Typo.monoBold(10))
                .foregroundColor(Palette.text)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.07))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.border, lineWidth: 0.5))
                )
            Text(label)
                .font(Typo.mono(9))
                .foregroundColor(Palette.textMuted)
        }
    }
}

// MARK: - Snapshot stack view

private struct MotionStack: View {
    struct Cell: Identifiable {
        let id: UInt32
        let tint: Color
        let image: NSImage?        // real window capture; falls back to tint while loading
        let rect: CGRect           // normalized 0…1 placement in the minimap
        let slot: Int              // pick-order slot number (matches the gather grid)
        let isActive: Bool         // the aimed window — highlighted
    }

    let cells: [Cell]
    var aspect: CGFloat = 1.6
    var onToggle: (UInt32) -> Void = { _ in }   // tap a cell to deselect it

    // The minimap lives in a constant box and the screen-aspect grid is *contained*
    // inside it, so the panel is one predictable size on any display (no more
    // collapsing into a wide strip that crowds the logo on an ultrawide).
    private let boxW: CGFloat = 196
    private let boxH: CGFloat = 118
    private let gutter: CGFloat = 5

    var body: some View {
        if cells.isEmpty {
            // Nothing picked yet → no panel. The in-place preview is enough while
            // you browse; the plan only appears once there's a plan.
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                header
                minimap
                caption
                footer
            }
            .padding(13)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.74))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 22, x: 0, y: 10)
        }
    }

    // Branded title row: a lattice glyph + wordmark, with the live pick count.
    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Palette.running)
            Text("Lattices")
                .font(Typo.monoBold(11))
                .foregroundColor(Palette.text)
                .tracking(0.5)
            Text("hyperspace")
                .font(Typo.mono(9))
                .foregroundColor(Palette.textMuted)
            Spacer(minLength: 10)
            Text("\(cells.count)")
                .font(Typo.monoBold(11))
                .foregroundColor(Palette.running)
            Text(cells.count == 1 ? "pick" : "picks")
                .font(Typo.mono(9))
                .foregroundColor(Palette.textMuted)
        }
    }

    // Contain the screen-aspect rectangle inside the fixed box (small inset so
    // cells don't touch the edge). Keeps the gather proportions truthful while the
    // panel stays a constant size.
    private var fittedSize: CGSize {
        let inset: CGFloat = 8
        let availW = boxW - inset, availH = boxH - inset
        let a = max(aspect, 0.3)
        if a >= availW / availH { return CGSize(width: availW, height: (availW / a).rounded()) }
        return CGSize(width: (availH * a).rounded(), height: availH)
    }

    private var minimap: some View {
        let fit = fittedSize
        return ZStack {                                   // centered grid in a constant box
            ZStack(alignment: .topLeading) {
                ForEach(cells) { cell in
                    tile(cell)
                        .frame(width:  max(fit.width  * cell.rect.width  - gutter, 1),
                               height: max(fit.height * cell.rect.height - gutter, 1))
                        .offset(x: fit.width  * cell.rect.minX + gutter / 2,
                                y: fit.height * cell.rect.minY + gutter / 2)
                }
            }
            .frame(width: fit.width, height: fit.height, alignment: .topLeading)
        }
        .frame(width: boxW, height: boxH)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.border.opacity(0.8), lineWidth: 0.75))
    }

    private var caption: some View {
        Text("tap a tile to deselect")
            .font(Typo.mono(8))
            .foregroundColor(Palette.textMuted)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            chip("⏎"); Text("gather").font(Typo.mono(9)).foregroundColor(Palette.textMuted)
            Spacer(minLength: 8)
            chip("esc"); Text("cancel").font(Typo.mono(9)).foregroundColor(Palette.textMuted)
        }
    }

    private func chip(_ key: String) -> some View {
        Text(key)
            .font(Typo.monoBold(9))
            .foregroundColor(Palette.text)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.07))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.border, lineWidth: 0.5))
            )
    }

    private func tile(_ cell: Cell) -> some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        return ZStack {
            cell.tint.opacity(0.9)
            if let image = cell.image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            }
        }
        .clipShape(shape)
        .overlay(alignment: .topLeading) {
            Text("\(cell.slot)")
                .font(Typo.monoBold(9))
                .foregroundColor(Color(red: 0.02, green: 0.03, blue: 0.05))
                .frame(width: 14, height: 14)
                .background(Circle().fill(cell.tint))
                .padding(3)
        }
        .overlay(shape.strokeBorder(cell.isActive ? Color.white.opacity(0.95)
                                                  : Color.white.opacity(0.14),
                                    lineWidth: cell.isActive ? 1.5 : 0.75))
        .contentShape(Rectangle())
        .onTapGesture { onToggle(cell.id) }
    }
}

// MARK: - Cluster rule (user-definable; a cluster IS a named rule)

/// A user-defined cluster from ~/.lattices/clusters.json. A window joins the
/// cluster when it satisfies every present criterion. Smart by-app clusters fill
/// in whatever the user's rules don't claim.
struct ClusterRule: Decodable {
    let name: String
    var app: String?            // app name contains (case-insensitive)
    var titleContains: String?  // window title contains (case-insensitive)

    func matches(_ e: WindowEntry) -> Bool {
        var matched = false
        if let app {
            if !e.app.localizedCaseInsensitiveContains(app) { return false }
            matched = true
        }
        if let titleContains {
            if !e.title.localizedCaseInsensitiveContains(titleContains) { return false }
            matched = true
        }
        return matched
    }

    var summary: String {
        switch (app, titleContains) {
        case let (a?, t?): return "app \(a) · ~\(t)"
        case let (a?, nil): return "app \(a)"
        case let (nil, t?): return "~\(t)"
        default: return "rule"
        }
    }
}

/// A resolved cluster for one survey: a named box of windows.
struct ExposeCluster {
    let id: Int
    let name: String
    let rule: String
    let userDefined: Bool
    let members: [WindowEntry]
}

// MARK: - Expose spread view (the lattice survey)
//
// A clustered lattice of live window captures over a dimmed active display.
// Each tile wears a home-row hint letter; picked tiles get a slot number (the
// order they'll fill the gather grid). Tint = app identity; the box = cluster.
// Renders study 05 ("Converged") from design/hyperspace-lattice-studio.html.

/// A behind-window blur of the live desktop — the frosted-glass backdrop the
/// survey floats on. Forced dark so it reads as a HUD regardless of system theme.
private struct VisualEffectBackdrop: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        v.isEmphasized = true
        v.appearance = NSAppearance(named: .vibrantDark)
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
    }
}

/// Collects each survey tile's laid-out frame (in the survey coordinate space) so
/// the panel can deal hand-split hint keys by real on-screen position.
private struct TileFramesKey: PreferenceKey {
    static let defaultValue: [UInt32: CGRect] = [:]
    static func reduce(value: inout [UInt32: CGRect], nextValue: () -> [UInt32: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Live frame-cadence stats for the survey perf harness. `record` is fed each
/// animation tick; the EMA keeps the readout steady, worst-frame surfaces
/// hitches. Reset between A/B runs for a clean comparison.
private final class PerfStats: ObservableObject {
    @Published var fps: Double = 0
    @Published var ms: Double = 0
    @Published var worstMs: Double = 0

    private var last: Double = 0
    private var ema: Double = 0

    func record(_ now: Double) {
        defer { last = now }
        guard last != 0 else { return }
        let dt = (now - last) * 1000
        guard dt > 0.1, dt < 250 else { return }   // ignore tab-away gaps
        ema = ema == 0 ? dt : ema * 0.88 + dt * 0.12
        ms = ema
        fps = 1000 / ema
        if dt > worstMs { worstMs = dt }
    }

    func reset() {
        last = 0; ema = 0; ms = 0; fps = 0; worstMs = 0
    }
}

struct ExposeView: View {
    struct Tile: Identifiable {
        let id: UInt32
        let app: String
        let title: String
        let tint: Color
        let image: NSImage?
        let hint: String
        let pickSlot: Int?
        let isAimed: Bool
    }

    struct Cluster: Identifiable {
        let id: Int
        let name: String
        let rule: String
        let userDefined: Bool
        let hint: String          // ⇧-letter that plucks the whole cluster
        let tiles: [Tile]
    }

    let clusters: [Cluster]
    let tileWidth: CGFloat
    var onPick: (UInt32) -> Void = { _ in }
    var onLayout: ([UInt32: CGRect]) -> Void = { _ in }
    var onHandKeys: (Bool) -> Void = { _ in }
    var loadSummary: String = ""

    private let ink = Color(red: 0.02, green: 0.03, blue: 0.05)
    static let surveySpace = "hyperspace.survey"

    // The lighting rig — all persisted, all live. The survey is lit like a room:
    // an ambient floor, one directional key light you can aim, a focus spotlight
    // that follows the aimed tile, and a warm↔cool temperature gel on the light.
    @AppStorage("hyperspace.ambient")   private var ambient: Double = 0.5
    @AppStorage("hyperspace.keyLight")  private var keyLight: Double = 0.4
    @AppStorage("hyperspace.keyAngle")  private var keyAngle: Int = 0       // 0 ◤ · 1 ▲ · 2 ◥
    @AppStorage("hyperspace.spotlight") private var spotlight: Double = 0.3
    @AppStorage("hyperspace.temp")      private var temp: Double = 0.5       // 0 cool · 1 warm

    // Size & layout. `sizeAuto` fills the display from the window count (the panel
    // does the fit); with it off, `tileScale` biases that base up or down. `layoutTall`
    // drops the per-cluster column cap so the lattice grows downward into the vertical.
    @AppStorage("hyperspace.sizeAuto")   private var sizeAuto: Bool = true
    @AppStorage("hyperspace.tileScale")  private var tileScale: Double = 1.0
    @AppStorage("hyperspace.layoutTall") private var layoutTall: Bool = false

    // Hand-split hint keys (assignment lives in the panel; the toggle pings it).
    @AppStorage("hyperspace.handKeys") private var handKeys: Bool = false

    // Perf A/B harness (diagnostic, not persisted): A = a plain dark-gray fill,
    // B = the full frosted stack. The HUD reads live frame cadence.
    @State private var perfMode = false
    @State private var perfFlat = false                  // A = true, B = false
    @StateObject private var perf = PerfStats()

    var body: some View {
        ZStack {
            if perfMode {
                // Continuous repaint so the cadence reflects sustained paint cost,
                // and a gently drifting grid gives the renderer real work to do.
                TimelineView(.animation) { ctx in
                    surveyContent(phase: ctx.date.timeIntervalSinceReferenceDate)
                        .onChange(of: ctx.date) { _, d in perf.record(d.timeIntervalSinceReferenceDate) }
                }
            } else {
                surveyContent(phase: 0)
            }
        }
        .overlay(alignment: .topTrailing) { dials.padding(20) }
        .overlay(alignment: .top) { if perfMode { perfHUD.padding(.top, 22) } }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func surveyContent(phase: Double) -> some View {
        ZStack {
            scrim(phase: phase)
            FlowLayout(spacing: 18, lineSpacing: 18) {
                ForEach(clusters) { clusterBox($0) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(36)
            .coordinateSpace(name: ExposeView.surveySpace)
            .onPreferenceChange(TileFramesKey.self) { onLayout($0) }
        }
    }

    // The control rig — a compact stack top-right, clear of the legend (bottom)
    // and minimap (bottom-left). Lighting, then layout, then keys. Every value persists.
    private var dials: some View {
        VStack(alignment: .leading, spacing: 7) {
            dial("moon.stars",         "amb",  $ambient)
            keyRow
            dial("flashlight.on.fill", "spot", $spotlight)
            dial("thermometer.medium", "temp", $temp) { _ in temp < 0.45 ? "cool" : temp > 0.55 ? "warm" : "·" }
            divider
            sizeRow
            twoWay("rectangle.grid.2x2", "scan", "tall", isFirst: !layoutTall) { layoutTall = !$0 }
            twoWay("keyboard", "read", "hands", isFirst: !handKeys) { handKeys = !$0; onHandKeys(handKeys) }
            divider
            HStack(spacing: 8) {
                perfToggle
                Spacer(minLength: 0)
                if perfMode { abToggle }
            }
            if !loadSummary.isEmpty {
                Text(loadSummary)
                    .font(Typo.mono(8))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.5))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5))
        )
    }

    private var divider: some View {
        Rectangle().fill(Palette.border).frame(height: 0.5).padding(.vertical, 1)
    }

    // The key-light row: an intensity slider plus a three-way origin picker (◤ ▲ ◥).
    private var keyRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "sun.max").font(.system(size: 10)).foregroundColor(.white.opacity(0.6)).frame(width: 14)
            Text("key").font(Typo.mono(9)).foregroundColor(.white.opacity(0.45)).frame(width: 28, alignment: .leading)
            Slider(value: $keyLight, in: 0...1).frame(width: 70).controlSize(.mini).tint(Palette.running)
            HStack(spacing: 2) { angleSeg(0, "◤"); angleSeg(1, "▲"); angleSeg(2, "◥") }
        }
    }

    private func angleSeg(_ a: Int, _ glyph: String) -> some View {
        Button { keyAngle = a } label: {
            Text(glyph).font(.system(size: 9))
                .foregroundColor(keyAngle == a ? Palette.bg : .white.opacity(0.5))
                .frame(width: 16, height: 16)
                .background(RoundedRectangle(cornerRadius: 3).fill(keyAngle == a ? Palette.running : Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    // Size row: an "auto" pill (default on — the panel fits tiles to the window count)
    // plus a manual bias slider. Auto dims the slider; grabbing it takes manual over.
    private var sizeRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 10)).foregroundColor(.white.opacity(0.6)).frame(width: 14)
            Text("size").font(Typo.mono(9)).foregroundColor(.white.opacity(0.45)).frame(width: 28, alignment: .leading)
            Slider(value: $tileScale, in: 0.55...1.7, onEditingChanged: { editing in if editing { sizeAuto = false } })
                .frame(width: 66).controlSize(.mini).tint(Palette.running)
                .opacity(sizeAuto ? 0.35 : 1)
            pill("auto", sizeAuto) { sizeAuto.toggle() }
            Text(sizeAuto ? "auto" : String(format: "%.2f×", tileScale))
                .font(Typo.mono(9)).foregroundColor(.white.opacity(0.5)).frame(width: 30, alignment: .trailing)
        }
    }

    private func dial(_ icon: String, _ label: String, _ value: Binding<Double>,
                      in range: ClosedRange<Double> = 0...1,
                      readout: ((Double) -> String)? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 14)
            Text(label)
                .font(Typo.mono(9))
                .foregroundColor(.white.opacity(0.45))
                .frame(width: 28, alignment: .leading)
            Slider(value: value, in: range)
                .frame(width: 104)
                .controlSize(.mini)
                .tint(Palette.running)
            Text(readout?(value.wrappedValue) ?? "\(Int((value.wrappedValue * 100).rounded()))")
                .font(Typo.mono(9))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 30, alignment: .trailing)
        }
    }

    // A two-segment pill toggle (label-driven). `isFirst` selects the left segment;
    // `set` is called with the new "is-first" state when either segment is tapped.
    private func twoWay(_ icon: String, _ a: String, _ b: String, isFirst: Bool, _ set: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 10)).foregroundColor(.white.opacity(0.6)).frame(width: 14)
            HStack(spacing: 2) {
                pill(a, isFirst)  { set(true) }
                pill(b, !isFirst) { set(false) }
            }
            .padding(2)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 0.5))
            Spacer(minLength: 0)
        }
    }

    private func pill(_ t: String, _ on: Bool, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(t).font(Typo.monoBold(9))
                .foregroundColor(on ? Palette.bg : .white.opacity(0.55))
                .padding(.horizontal, 9).frame(height: 16)
                .background(Capsule().fill(on ? Palette.running : Color.clear))
        }
        .buttonStyle(.plain)
    }

    // Treatment A vs B. A is a plain opaque dark-gray fill — the cheapest possible
    // backdrop, the baseline. B is the lit room: behind-window blur + an ambient
    // floor + a directional, temperature-gelled key light + a vignette that deepens
    // as the room darkens. `phase` is non-zero only under the perf harness, where it
    // gives the key light a faint breathing drift so the renderer has real work to do.
    @ViewBuilder
    private func scrim(phase: Double) -> some View {
        if perfFlat {
            Color(red: 0.11, green: 0.11, blue: 0.12)   // A — flat fill, no lighting
        } else {
            ZStack {
                // Frosted glass: blur the real desktop into a soft wash.
                VisualEffectBackdrop(material: .hudWindow)
                    .ignoresSafeArea()

                // Ambient floor: how lit the room is. Low = near-black and dramatic,
                // high = airy. A little blur always survives so it never goes flat.
                Color.black.opacity(0.82 - ambient * 0.60)

                // Directional key light, gelled warm↔cool by temperature.
                EllipticalGradient(
                    colors: [lightColor.opacity(keyLight * 0.5), .clear],
                    center: keyCenter,
                    startRadiusFraction: 0,
                    endRadiusFraction: 1.0 + 0.06 * CGFloat(sin(phase * 2))
                )

                // Vignette — deepens as the room darkens, so bright vibes stay open.
                EllipticalGradient(
                    colors: [.clear, Color.black.opacity(0.30 * (1 - ambient * 0.5))],
                    center: .center,
                    startRadiusFraction: 0.5,
                    endRadiusFraction: 1.0
                )
            }
        }
    }

    // Where the key light originates: ◤ top-left, ▲ top, ◥ top-right.
    private var keyCenter: UnitPoint {
        switch keyAngle { case 0: return .topLeading; case 2: return .topTrailing; default: return .top }
    }

    // The light's colour along a cool→neutral→warm temperature axis.
    private var lightColor: Color {
        func lerp(_ a: Double, _ b: Double, _ f: Double) -> Double { a + (b - a) * f }
        let cool = (0.60, 0.71, 0.96), neutral = (0.86, 0.88, 0.92), warm = (1.00, 0.83, 0.60)
        if temp < 0.5 {
            let f = temp / 0.5
            return Color(red: lerp(cool.0, neutral.0, f), green: lerp(cool.1, neutral.1, f), blue: lerp(cool.2, neutral.2, f))
        } else {
            let f = (temp - 0.5) / 0.5
            return Color(red: lerp(neutral.0, warm.0, f), green: lerp(neutral.1, warm.1, f), blue: lerp(neutral.2, warm.2, f))
        }
    }

    // Effective tile width — the panel's fill-fit base, optionally biased by the size
    // dial — and the per-cluster column cap (lower in "tall" so the lattice fills the
    // vertical space).
    private var tile: CGFloat {
        sizeAuto ? tileWidth : (tileWidth * CGFloat(tileScale)).rounded()
    }
    private var colCap: Int { layoutTall ? 2 : 4 }

    // MARK: Perf harness UI

    private var perfHUD: some View {
        HStack(spacing: 16) {
            perfStat(perfFlat ? "A · flat fill" : "B · full stack", Palette.running)
            perfStat(String(format: "%.0f fps", perf.fps), .white)
            perfStat(String(format: "%.1f ms", perf.ms), .white)
            perfStat(String(format: "worst %.1f", perf.worstMs), perf.worstMs > 18 ? Palette.detach : .white.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.black.opacity(0.62))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5))
        )
    }

    private func perfStat(_ text: String, _ color: Color) -> some View {
        Text(text).font(Typo.monoBold(11)).foregroundColor(color)
    }

    private var perfToggle: some View {
        Button {
            perfMode.toggle(); perf.reset()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "speedometer").font(.system(size: 10))
                Text("perf").font(Typo.mono(9))
            }
            .foregroundColor(perfMode ? Palette.bg : .white.opacity(0.6))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(perfMode ? Palette.running : Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private var abToggle: some View {
        HStack(spacing: 2) {
            abSeg("A", perfFlat)  { perfFlat = true;  perf.reset() }
            abSeg("B", !perfFlat) { perfFlat = false; perf.reset() }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 0.5))
    }

    private func abSeg(_ t: String, _ on: Bool, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(t).font(Typo.monoBold(9))
                .foregroundColor(on ? Palette.bg : .white.opacity(0.55))
                .frame(width: 20, height: 16)
                .background(Capsule().fill(on ? Palette.running : Color.clear))
        }
        .buttonStyle(.plain)
    }

    private func clusterBox(_ c: Cluster) -> some View {
        let cols = min(max(c.tiles.count, 1), colCap)
        let innerW = tile * CGFloat(cols) + 8 * CGFloat(cols - 1)
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                if !c.hint.isEmpty {
                    Text("⇧\(c.hint)")
                        .font(Typo.monoBold(9)).foregroundColor(.white).tracking(0.3)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(c.userDefined ? Palette.running.opacity(0.8) : Color.white.opacity(0.16))
                                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.28), lineWidth: 0.5))
                        )
                        .help("Pluck the whole \(c.name) group")
                }
                Text(c.name)
                    .font(Typo.monoBold(11)).foregroundColor(.white).tracking(0.3)
                Text(c.rule)
                    .font(Typo.mono(9)).foregroundColor(Palette.textMuted)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.05))
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.border, lineWidth: 0.5))
                    )
                Spacer(minLength: 16)
                Text(c.userDefined ? "you" : "smart")
                    .font(Typo.mono(8))
                    .tracking(0.6)
                    .foregroundColor(c.userDefined ? Palette.running : Palette.textMuted)
            }
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(c.tiles) { tileView($0) }
            }
            .frame(maxWidth: innerW, alignment: .leading)
        }
        .padding(.horizontal, 11).padding(.top, 9).padding(.bottom, 11)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(c.userDefined ? Palette.running.opacity(0.04) : Color.white.opacity(0.018))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(c.userDefined ? Palette.running.opacity(0.32) : Palette.border, lineWidth: 1)
        )
    }

    private func tileView(_ t: Tile) -> some View {
        let w = tile
        let h = (tile * 0.62).rounded()
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let picked = t.pickSlot != nil
        let lit = t.isAimed || picked                          // on the spotlight's stage
        let strokeColor: Color = picked ? t.tint : (t.isAimed ? Color.white.opacity(0.9) : Color.white.opacity(0.1))
        let strokeW: CGFloat = picked ? 2 : (t.isAimed ? 1.5 : 0.75)
        let veil: Double = lit ? 0 : spotlight * 0.5
        let bloom: Color = t.isAimed ? lightColor.opacity(0.7 * spotlight) : .clear
        let bloomR: CGFloat = t.isAimed ? 8 + spotlight * 22 : 0
        return tileBody(t, w: w, h: h, shape: shape)
            .overlay(shape.fill(Color.black.opacity(veil)))    // spotlight: off-stage tiles sink to shadow
            .overlay(shape.strokeBorder(strokeColor, lineWidth: strokeW))
            .overlay(alignment: .topTrailing) { hintChip(t) }
            .overlay(alignment: .topLeading) { if let s = t.pickSlot { slotBadge(s, t.tint) } }
            .overlay(alignment: .bottomLeading) { titleLabel(t) }
            .background(frameReporter(t.id))
            .shadow(color: .black.opacity(picked ? 0.5 : 0.35), radius: picked ? 14 : 8, x: 0, y: 5)
            .shadow(color: bloom, radius: bloomR)              // aimed tile catches the key light
            .contentShape(Rectangle())
            .onTapGesture { onPick(t.id) }
    }

    // The tile's image + app-tint accent, clipped to the rounded card.
    private func tileBody(_ t: Tile, w: CGFloat, h: CGFloat, shape: RoundedRectangle) -> some View {
        ZStack(alignment: .topLeading) {
            ZStack {
                t.tint.opacity(0.16)
                if let img = t.image {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                }
            }
            .frame(width: w, height: h)
            .clipShape(shape)

            VStack(spacing: 0) {                                   // app-tint top accent
                Rectangle().fill(t.tint).frame(height: 2)
                Spacer(minLength: 0)
            }
        }
        .frame(width: w, height: h)
        .clipShape(shape)
    }

    // Reports this tile's laid-out frame up to the panel for hand-split key dealing.
    private func frameReporter(_ id: UInt32) -> some View {
        GeometryReader { g in
            Color.clear.preference(key: TileFramesKey.self,
                                   value: [id: g.frame(in: .named(ExposeView.surveySpace))])
        }
    }

    private func hintChip(_ t: Tile) -> some View {
        Text(t.hint.uppercased())
            .font(Typo.monoBold(11))
            .foregroundColor(ink)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 3).fill(t.tint))
            .padding(5)
    }

    private func slotBadge(_ n: Int, _ tint: Color) -> some View {
        Text("\(n)")
            .font(Typo.monoBold(11))
            .foregroundColor(ink)
            .frame(width: 20, height: 20)
            .background(Circle().fill(tint))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 0.5))
            .padding(5)
    }

    private func titleLabel(_ t: Tile) -> some View {
        Text(t.title)
            .font(Typo.mono(8))
            .foregroundColor(.white.opacity(0.85))
            .lineLimit(1)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill(Color.black.opacity(0.5)))
            .padding(5)
    }
}

// MARK: - Flow layout
//
// Wraps subviews left-to-right onto centered rows, and centers the whole block
// in its bounds. Used twice: clusters flow across the survey, tiles flow inside
// each cluster.

struct FlowLayout: Layout {
    var spacing: CGFloat = 12
    var lineSpacing: CGFloat = 12
    var alignment: HorizontalAlignment = .center   // row packing: centered (default) or left/right

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = computeRows(maxWidth: maxWidth, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(maxWidth: bounds.width, subviews: subviews)
        let totalH = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, rows.count - 1))
        var y = bounds.minY + max(0, (bounds.height - totalH) / 2)
        for row in rows {
            var x: CGFloat
            if alignment == .leading {
                x = bounds.minX
            } else if alignment == .trailing {
                x = bounds.maxX - row.width
            } else {
                x = bounds.minX + max(0, (bounds.width - row.width) / 2)
            }
            for idx in row.indices {
                let size = subviews[idx].sizeThatFits(.unspecified)
                subviews[idx].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func computeRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (i, sv) in subviews.enumerated() {
            let s = sv.sizeThatFits(.unspecified)
            let projected = row.indices.isEmpty ? s.width : row.width + spacing + s.width
            if !row.indices.isEmpty && projected > maxWidth {
                rows.append(row)
                row = Row(indices: [i], width: s.width, height: s.height)
            } else {
                row.width = row.indices.isEmpty ? s.width : row.width + spacing + s.width
                row.indices.append(i)
                row.height = max(row.height, s.height)
            }
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

private extension Array {
    /// Bounds-checked access — nil instead of a crash for out-of-range indices.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
