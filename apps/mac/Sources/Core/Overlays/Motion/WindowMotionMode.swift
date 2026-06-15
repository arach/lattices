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

private final class HyperspaceScreenPanel: NSPanel {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        setFrame(screen.frame, display: true)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Expose canvas (zoom/pan)
//
// Ephemeral navigation state for the screenshot survey: a pure view transform over
// the already-laid-out lattice — no reflow, no real windows move. Owned by the panel
// (so it survives the frequent ExposeView rebuilds) and observed by ExposeView, which
// applies it as a scaleEffect + offset. Separate axis from the persisted "size" dial:
// size changes how big tiles are laid out; this magnifies whatever is laid out.
final class ExposeCanvas: ObservableObject {
    @Published var zoom: CGFloat = 1     // 1 = fit (floor). Pan only matters when > 1.
    @Published var pan: CGSize = .zero   // points, in SwiftUI offset space (+x right, +y down)
    let minZoom: CGFloat = 1.0
    let maxZoom: CGFloat = 4.0

    func reset() { zoom = 1; pan = .zero }
}

// MARK: - Drag & drop "intent layer" (design/hyperspace-drag-drop.md)

/// Resolution of the Lattice drop grid. Each step is a plain CxR grid you drop a
/// window onto; the cell maps straight to `PlacementSpec.grid`. Default is quarters;
/// modifiers (⇧ halves · ⌥ thirds · ⌘ fine) override the selector while held.
enum LatticeRes: Int, CaseIterable {
    case halves, thirds, quarters, fine

    var dims: (cols: Int, rows: Int) {
        switch self {
        case .halves:   return (2, 1)
        case .thirds:   return (3, 1)
        case .quarters: return (2, 2)
        case .fine:     return (4, 4)
        }
    }
    var glyph: String {
        switch self {
        case .halves:   return "½"
        case .thirds:   return "⅓"
        case .quarters: return "¼"
        case .fine:     return "▦"
        }
    }
    var name: String {
        switch self {
        case .halves:   return "halves"
        case .thirds:   return "thirds"
        case .quarters: return "quarters"
        case .fine:     return "fine"
        }
    }
    /// Map a grid's dims back to its selector glyph (for staged badges).
    static func glyph(cols: Int, rows: Int) -> String {
        LatticeRes.allCases.first { $0.dims == (cols, rows) }?.glyph ?? "▦"
    }
}

/// A cell coordinate in the lattice grid (0-indexed, top-left origin) — matches
/// `GridPlacement(column:row:)`.
struct HoverCell: Equatable { let col: Int; let row: Int }

/// Ephemeral drag state for the intent layer. Owned by `MotionPanel` (so it
/// survives the frequent ExposeView rebuilds) and observed by every screen's
/// ExposeView. The drag is scoped to one screen via `screenID`; only that screen
/// renders the ghost and accepts a drop. Nothing real moves here — a drop only
/// stages a destination (committed later on gather).
final class HyperspaceDrag: ObservableObject {
    @Published var wid: UInt32?              // window being dragged (nil = idle/tap-only)
    @Published var image: NSImage?           // ghost thumbnail following the cursor
    @Published var tileSize: CGSize = .zero
    @Published var location: CGPoint = .zero // cursor, in ExposeView's root space
    @Published var res: LatticeRes = .quarters   // effective resolution (modifier ?? base)
    @Published var baseRes: LatticeRes = .quarters // selector choice; modifiers override live
    @Published var hoverCell: HoverCell?     // cell under the cursor in the lattice grid
    @Published var hoverLayer: String?       // layer pile under the cursor (layer id, or newLayerKey)
    @Published var inspectLayer: String?     // pile under a plain mouse hover (no drag) — reveals its roster
    @Published var inspectScreen: String?    // which screen that hovered pile is on
    @Published var screenID: String = ""     // which screen owns the in-flight drag

    // Right-click "place me" mode: a tile was secondary-clicked, opening a life-size
    // interactive stage to pick its grid spot (mouse-only alternative to drag → Grid).
    @Published var placeWid: UInt32?         // window in placement mode (nil = off)
    @Published var placeScreen: String?      // which screen its stage shows on
    @Published var placeCell: HoverCell?     // cell under the cursor on the stage
    var isPlacing: Bool { placeWid != nil }
    func beginPlacing(_ wid: UInt32, on screen: String) { placeWid = wid; placeScreen = screen; placeCell = nil }
    func endPlacing() { placeWid = nil; placeScreen = nil; placeCell = nil }

    var latticeFrames: [String: CGRect] = [:]              // per-screen lattice grid frame (root space)
    var layerFrames: [String: [String: CGRect]] = [:]      // [screenID: [layerKey: frame]] (root space)

    static let newLayerKey = "+new"          // sentinel for the ＋ "new layer" pile

    // A one-shot "landing" beat fired at the drop target the instant you release, so a
    // drop reads as confirmed even though the target's hover highlight has cleared.
    struct DropPulse: Equatable { let id: Int; let frame: CGRect }
    @Published var dropPulse: DropPulse?
    private var pulseCounter = 0

    var isActive: Bool { wid != nil }

    func reset() {
        wid = nil
        image = nil
        hoverCell = nil
        hoverLayer = nil
    }

    /// Flash a ring at `frame` (root space) and auto-clear it after the beat. Tokened
    /// so each drop restarts the animation even on the same target.
    func firePulse(at frame: CGRect) {
        guard frame.width > 1 else { return }
        pulseCounter += 1
        let id = pulseCounter
        dropPulse = DropPulse(id: id, frame: frame)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            if self?.dropPulse?.id == id { self?.dropPulse = nil }
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
    private var didMoveWindows = false       // did we move/raise any real window? (gates the Esc restore)
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
    private var scrollMonitor: Any?
    private var mouseUpMonitor: Any?    // re-claims key focus after a survey click/drag
    private var keyMonitor: Any?        // catches Enter/Esc even when a survey panel holds key
    private var newLayerPanel: NewLayerPanel?   // the "create a new layer" authoring flow, when open

    // Selection order — `group` is membership, `pickOrder` is the order picks were
    // made, which is what the slot numbers (and the gather grid) follow.
    private var pickOrder: [UInt32] = []

    // Drag & drop "intent layer" (design/hyperspace-drag-drop.md). Each window can
    // be staged across three orthogonal axes; nothing real moves until the gather
    // commit. Populated by the drag UI (Phase 1+); committed in gatherInPlace().
    struct StagedIntent {
        var layers: Set<String> = []        // StudioLayer ids — multi-membership (Phase 2)
        var newLayer: Bool = false          // stage a fresh layer seeded from this window (＋ pile)
        var location: PlacementSpec?         // where on the active screen (Phase 1)
        var space: Int?                      // target macOS Space (Phase 3)
        var isEmpty: Bool { layers.isEmpty && !newLayer && location == nil && space == nil }
    }
    private var stagedIntents: [UInt32: StagedIntent] = [:]

    // Live drag state for the intent layer — owned here so it outlives the frequent
    // ExposeView rebuilds, observed by every screen's spread.
    private let dragModel = HyperspaceDrag()

    // Screenshot Exposé: real windows never move during the survey. We render a
    // clustered lattice of live captures and pluck by home-row hint key; only the
    // gather (⏎ / G) moves real windows.
    private var exposeHost: NSHostingView<ExposeView>?
    private var exposeHostsByScreenID: [String: NSHostingView<ExposeView>] = [:]
    private var exposePanelsByScreenID: [String: HyperspaceScreenPanel] = [:]
    private var canvasByScreenID: [String: ExposeCanvas] = [:]
    private var activeScreenID: String?
    private var pickOrderByScreen: [String: [UInt32]] = [:]
    private var exposeClustersByScreen: [String: [ExposeCluster]] = [:]
    private var exposeOrderByScreen: [String: [UInt32]] = [:]
    private var exposeAimByScreen: [String: Int] = [:]
    private var hintForByScreen: [String: [UInt32: String]] = [:]
    private var hintMapByScreen: [String: [String: UInt32]] = [:]
    private var clusterHintForByScreen: [String: [Int: String]] = [:]
    private var clusterHintMapByScreen: [String: [String: Int]] = [:]
    private var exposeTileWByScreen: [String: CGFloat] = [:]
    private var exposeFramesByScreen: [String: [UInt32: CGRect]] = [:]
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
    private var activeSurveyScreen: NSScreen? {
        if let activeScreenID,
           let screen = NSScreen.screens.first(where: { MotionPanel.screenID($0) == activeScreenID }) {
            return screen
        }
        return screen(for: activeEntry)
    }

    private var activeSurveyMembers: [WindowEntry] {
        guard let screen = activeSurveyScreen else { return [] }
        return eligible.filter { entry($0, isOn: screen) }
    }

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
        activeScreenID = activeSurveyScreen.map(MotionPanel.screenID)
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
        // Opening from the global Hyper+Space path churns focus: the keyboard
        // transport layer goes up/down around the same time this LSUIElement app
        // presents a key panel. A short startup resign can otherwise tear the
        // survey down right after first paint, which reads as "didn't load."
        ignoreResign = true
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: self, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if self.ignoreResign {
                DiagnosticLog.shared.info("MotionPanel: ignored transient key resign")
                return
            }
            DiagnosticLog.shared.info("MotionPanel: key resigned, exiting")
            self.onExit?()
        }
        // Survey zoom/pan: a local scroll monitor (gated to this panel) so ⌘-scroll /
        // scroll reach us even though the SwiftUI host would otherwise swallow them.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self,
                  event.window === self || self.exposePanelsByScreenID.values.contains(where: { event.window === $0 }) else {
                return event
            }
            return self.handleScroll(event) ? nil : event
        }
        // A click or drag on a survey screen-panel (canBecomeKey == false) can leave the
        // app with *no* key window, so Enter/Esc fall on the floor. After any mouse-up on
        // one of our panels, re-claim key on the next runloop turn (after the gesture's
        // onEnded settles) so the keyboard keeps working — the reported "couldn't hit
        // enter to confirm" bug.
        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            guard let self,
                  event.window === self || self.exposePanelsByScreenID.values.contains(where: { event.window === $0 }) else {
                return event
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.exposed, !self.isKeyWindow else { return }
                self.makeKey()
            }
            return event   // don't swallow — the click/drag still needs to process
        }
        // Belt-and-suspenders for the "couldn't hit Enter to confirm" bug: if a survey
        // screen-panel (canBecomeKey == false) or nothing holds key, the MotionPanel's own
        // keyDown never fires. Catch Enter/Esc here and route them so they never fall on the
        // floor. When the MotionPanel *is* key, defer to its keyDown (don't double-handle).
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Stand down while the New Layer panel is up — it owns the keyboard (text field).
            guard let self, self.exposed, !self.isKeyWindow, self.newLayerPanel == nil else { return event }
            switch event.keyCode {
            case 53:
                if self.dragModel.isPlacing { self.dragModel.endPlacing() } else { self.undoAndExit() }
                return nil                                          // Esc — close stage, else cancel
            case 36, 76:      self.keyDown(with: event); return nil   // Return / keypad Enter — confirm
            default:          return event
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.ignoreResign = false
        }
        // Hyperspace lands you straight in the survey. E collapses back to plain
        // motion; expose() no-ops to plain mode if there's <2 windows to lay out.
        expose()
    }

    func dismiss() {
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        keyObserver = nil
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
        if let mouseUpMonitor { NSEvent.removeMonitor(mouseUpMonitor) }
        mouseUpMonitor = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        newLayerPanel?.close()
        newLayerPanel = nil
        animators.values.forEach { $0.cancel() }
        removeExposeHost()
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

    // MARK: - Canvas zoom/pan (survey only)
    //
    // ⌘-scroll zooms toward the pointer; plain scroll pans once zoomed past fit. This
    // is a pure view transform on the screenshot lattice — nothing here moves a real
    // window. State lives per display; ExposeView observes it and applies the
    // scaleEffect + offset. Driven by a local .scrollWheel monitor (installed in
    // present()) rather than a scrollWheel override, since NSHostingView swallows
    // unhandled scroll — matching the ScreenMap/Studio canvas idiom.
    //
    // Returns true when the survey consumed the scroll (the monitor then swallows it).
    private func handleScroll(_ event: NSEvent) -> Bool {
        guard exposed,
              let screen = validSurveyScreen(screenForEvent(event)) ?? activeSurveyScreen,
              let host = exposeHostsByScreenID[MotionPanel.screenID(screen)] else { return false }
        let screenCanvas = canvasForScreen(screen)
        if activeSurveyScreen.map(MotionPanel.screenID) != MotionPanel.screenID(screen) {
            setActiveSurveyScreen(screen)
        }
        if event.modifierFlags.contains(.command) {
            let step = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.01 : 0.05)
            zoomCanvas(screenCanvas, by: step, towardWindowPoint: event.locationInWindow, host: host)
            return true
        }
        guard screenCanvas.zoom > 1.0001 else { return false }        // nothing to pan at fit
        // Sign matches the ScreenMap canvas (+x right, −y to follow natural scroll).
        screenCanvas.pan = clampPan(CGSize(width:  screenCanvas.pan.width  + event.scrollingDeltaX,
                                           height: screenCanvas.pan.height - event.scrollingDeltaY),
                                    zoom: screenCanvas.zoom, host: host)
        return true
    }

    /// Zoom by `delta`, keeping the survey point under `windowPoint` fixed (cursor anchor).
    /// `windowPoint` is panel/window coords (bottom-left origin); the survey offset is
    /// top-left/+y-down, so the vertical component is flipped into host space first.
    private func zoomCanvas(_ canvas: ExposeCanvas, by delta: CGFloat, towardWindowPoint windowPoint: CGPoint, host: NSView) {
        let z0 = canvas.zoom
        let z1 = min(max(z0 + delta, canvas.minZoom), canvas.maxZoom)
        guard z1 != z0 else { return }
        let ratio = z1 / z0
        // Cursor vector from the container centre, in SwiftUI offset axes (+x right, +y down).
        let cx = windowPoint.x - host.frame.minX
        let cyTop = host.frame.maxY - windowPoint.y
        let d = CGSize(width: cx - host.frame.width / 2, height: cyTop - host.frame.height / 2)
        let pan0 = canvas.pan
        canvas.zoom = z1
        canvas.pan = clampPan(CGSize(width:  d.width  - ratio * (d.width  - pan0.width),
                                     height: d.height - ratio * (d.height - pan0.height)),
                              zoom: z1, host: host)
    }

    /// Keyboard zoom — step toward the survey centre (no pointer), scaling the current
    /// pan proportionally so the framing holds, then re-clamp.
    private func zoomCanvasStep(_ delta: CGFloat) {
        guard let screen = activeSurveyScreen,
              let host = exposeHostsByScreenID[MotionPanel.screenID(screen)] else { return }
        zoomCanvas(canvasForScreen(screen), by: delta, towardWindowPoint: CGPoint(x: host.frame.midX, y: host.frame.midY), host: host)
    }

    /// Keep the centre-scaled lattice from sliding past its own edges (no empty gutters).
    private func clampPan(_ pan: CGSize, zoom: CGFloat, host: NSView) -> CGSize {
        let maxX = max(0, (zoom - 1) * host.frame.width  / 2)
        let maxY = max(0, (zoom - 1) * host.frame.height / 2)
        return CGSize(width:  min(max(pan.width,  -maxX), maxX),
                      height: min(max(pan.height, -maxY), maxY))
    }

    override func keyDown(with event: NSEvent) {
        let code = event.keyCode
        if code == 53 {                                     // Esc — close the placement stage first, else leave
            if dragModel.isPlacing { dragModel.endPlacing(); return }
            undoAndExit(); return
        }
        if code == 36 || code == 76 {                       // Return / keypad Enter — confirm: keep + leave
            if exposed {                                    // gather the plucked, send the rest home, then leave
                let screen = validSurveyScreen(screenForPointer())
                    ?? validSurveyScreen(screenForEvent(event))
                    ?? activeSurveyScreen
                if let screen {
                    let count = pickOrderByScreen[MotionPanel.screenID(screen)]?.count ?? 0
                    DiagnosticLog.shared.info("Motion confirm — gather \(count) from Exposé + exit")
                    gatherInPlace(on: screen)
                    onExit?()
                }
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
            let eventScreen = validSurveyScreen(screenForPointer())
                ?? validSurveyScreen(screenForEvent(event))
                ?? activeSurveyScreen
            if let eventScreen,
               activeSurveyScreen.map(MotionPanel.screenID) != MotionPanel.screenID(eventScreen) {
                setActiveSurveyScreen(eventScreen)
            }
            let screenID = eventScreen.map(MotionPanel.screenID)
            switch code {
            case 48:                                                         // Tab — move highlight
                if let eventScreen { exposeAimStep(mods.contains(.shift) ? -1 : 1, on: eventScreen) }
                return
            case 49:                                                         // Space — pluck highlighted
                if let eventScreen, let id = screenID {
                    let aim = exposeAimByScreen[id] ?? 0
                    if let wid = exposeOrderByScreen[id]?[safe: aim] { exposeToggle(wid, on: eventScreen) }
                }
                return
            case 14 where !mods.contains(.shift): collapseExpose(); return  // E — collapse survey
            case 5  where !mods.contains(.shift):                            // G — gather, stay in mode
                if let eventScreen { gatherInPlace(on: eventScreen) }
                return
            case 24: zoomCanvasStep(0.2); return                            // = / +  — zoom in
            case 27: zoomCanvasStep(-0.2); return                           // −      — zoom out
            case 29:
                if let eventScreen { canvasForScreen(eventScreen).reset() }  // 0      — reset to fit
                return
            default:
                let ch = event.charactersIgnoringModifiers?.lowercased()
                if let eventScreen, let id = screenID,
                   mods.contains(.shift), let ch, let cid = clusterHintMapByScreen[id]?[ch] {
                    exposeToggleCluster(cid, on: eventScreen)                // ⇧a–z — pluck a whole group
                } else if let eventScreen, let id = screenID,
                          let ch, let wid = hintMapByScreen[id]?[ch] {
                    exposeToggle(wid, on: eventScreen)                       // a–z — pluck by hint
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
        let members = activeSurveyMembers
        guard !members.isEmpty else { NSSound.beep(); return }
        let currentWid = activeEntry.wid
        let current = members.firstIndex { $0.wid == currentWid } ?? 0
        let next = ((current + delta) % members.count + members.count) % members.count
        if let idx = eligible.firstIndex(where: { $0.wid == members[next].wid }) {
            reticle = idx
        }
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
        savePickStateForActiveScreen()
    }

    /// The picked windows in pick order — the order their slot numbers run and the
    /// order they fill the balanced gather grid (so slot N lands in cell N).
    private func orderedGroup() -> [WindowEntry] {
        let activeIDs = Set(activeSurveyMembers.map(\.wid))
        return pickOrder.compactMap { wid in
            guard activeIDs.contains(wid) else { return nil }
            return eligible.first { $0.wid == wid }
        }
    }

    /// The picked windows that should fall into the balanced gather grid — i.e.
    /// the group minus any window that was drag-staged to a specific location
    /// (that one honours its dropped cell instead of the grid). No-op outside the
    /// survey, where nothing is ever staged.
    private func gatherMembers() -> [WindowEntry] {
        orderedGroup().filter { stagedIntents[$0.wid]?.location == nil }
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

    /// Esc: leave immediately, then restore anything we actually moved. The overlay tears
    /// down *first* so dismissal feels instant; the (slow) per-window AX restore only runs
    /// if we touched real windows this session — a pure survey/preview Esc skips it entirely
    /// instead of needlessly re-raising every window (the "Esc takes forever" bug).
    private func undoAndExit() {
        onExit?()                                   // instant visual dismiss
        guard didMoveWindows else { return }        // nothing real changed → done
        for (wid, frame) in originalFrames {
            guard let entry = eligible.first(where: { $0.wid == wid }), let el = ax(for: entry) else { continue }
            RealWindowAnimator.setFrameRobust(el, frame, pid: entry.pid)
        }
        restoreOriginalOrder()
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
        let members = gatherMembers()
        guard let screen = activeSurveyScreen, !members.isEmpty else { return }
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
        guard let screen = activeSurveyScreen else { return }
        let screens = surveyScreens()
        let members = eligible.filter { entry($0, isOn: screen) }
        let allMembers = screens.flatMap { surveyMembers(on: $0) }
        guard !members.isEmpty else { NSSound.beep(); return }    // nothing to survey

        exposed = true
        ignoresMouseEvents = true
        resetSurveyState(for: screens)
        for surveyScreen in screens {
            rebuildSurveyState(for: surveyScreen, resetAim: true)
            canvasForScreen(surveyScreen).reset()
        }
        restorePickState(for: screen)
        syncActiveSurveyState(from: screen)
        installExposeHosts()
        captureCount = allMembers.count
        allMembers.forEach { captureThumb(for: $0) }              // seed from the shared cache; capture only misses
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

        DiagnosticLog.shared.info("Motion expose — survey \(allMembers.count) windows across \(screens.count) displays; active \(members.count) windows in \(exposeClusters.count) clusters")
        updateLegend()
        updateStack()
        refreshBorders()                                          // clears real-window chrome while surveying
    }

    /// E (while surveying) — drop the spread, back to normal motion mode. Picks
    /// are kept (nothing moved), so you can still gather or keep arranging.
    private func collapseExpose() {
        removeExposeHost()
        exposed = false
        ignoresMouseEvents = false
        updateLegend()
        refreshBorders()
        updateStack()
    }

    /// A tile was dropped in the survey. A non-nil placement stages a location for
    /// that window (badge shows; nothing real moves until gather); nil means the
    /// drop missed every target — no change, we just rebuild to clear the drag
    /// placeholder. Either way the rebuild here un-suppresses the spread (rebuilds
    /// are skipped while a drag is in flight so the SwiftUI gesture survives).
    private func handleDrop(_ wid: UInt32, _ placement: PlacementSpec?) {
        if let placement {
            stagedIntents[wid, default: StagedIntent()].location = placement
            DiagnosticLog.shared.info("Hyperspace stage — wid=\(wid) location \(placement.wireValue)")
        }
        rebuildExposeView()
    }

    /// A tile was dropped on a Layers pile. The ＋ pile stages a brand-new layer; any
    /// other pile toggles a staged join (multi-membership). Only *stages* — nothing is
    /// written to StudioLayerStore until gather, so Esc still discards cleanly.
    private func handleLayerDrop(_ wid: UInt32, _ layerKey: String) {
        if layerKey == HyperspaceDrag.newLayerKey {
            stagedIntents[wid, default: StagedIntent()].newLayer.toggle()
        } else if stagedIntents[wid]?.layers.contains(layerKey) == true {
            stagedIntents[wid]?.layers.remove(layerKey)
        } else {
            stagedIntents[wid, default: StagedIntent()].layers.insert(layerKey)
        }
        DiagnosticLog.shared.info("Hyperspace stage — wid=\(wid) layer \(layerKey)")
        rebuildExposeView()
    }

    /// The ＋ pile's authoring flow: open the New Layer panel seeded with the apps on the active
    /// display (the plucked apps preselected, if any), let the user name it and pick which apps
    /// define it, then write a rule-backed StudioLayer. A real flow vs the drag-onto-＋ quick path.
    private func presentNewLayer() {
        guard exposed, newLayerPanel == nil,
              let screen = validSurveyScreen(activeSurveyScreen) ?? surveyScreens().first else { return }
        let id = MotionPanel.screenID(screen)
        let members = surveyMembers(on: screen)
        let plucked = Set(pickOrderByScreen[id] ?? [])

        // Unique apps on this display, each with a sample thumbnail + window count, in survey order.
        var order: [String] = []
        var img: [String: NSImage] = [:]
        var count: [String: Int] = [:]
        for w in members {
            if count[w.app] == nil { order.append(w.app) }
            count[w.app, default: 0] += 1
            if img[w.app] == nil, let t = thumbs[w.wid] { img[w.app] = t }
        }
        let candidates = order.map { NewLayerPanel.Candidate(app: $0, image: img[$0], count: count[$0] ?? 0) }
        let pluckedApps = Set(members.filter { plucked.contains($0.wid) }.map(\.app))
        let defaultName = Self.defaultLayerName(forApps: order.filter { pluckedApps.contains($0) })

        ignoreResign = true                         // making the panel key resigns ours — don't exit
        let panel = NewLayerPanel(
            candidates: candidates, preselected: pluckedApps, defaultName: defaultName,
            onCreate: { [weak self] name, apps in
                guard let self else { return }
                let clauses = apps.map { StudioLayerClause(app: $0, titleContains: nil) }
                let layer = StudioLayerStore.shared.add(
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Layer" : name,
                    match: clauses.isEmpty ? [StudioLayerClause()] : clauses)
                DiagnosticLog.shared.info("Hyperspace — created layer '\(layer.name)' from \(apps.count) app(s)")
                self.finishNewLayer()
                self.rebuildExposeView()            // the new pile appears in the band
            },
            onCancel: { [weak self] in self?.finishNewLayer() })
        newLayerPanel = panel
        panel.present(on: screen)
    }

    private func finishNewLayer() {
        newLayerPanel = nil
        ignoreResign = false
        makeKey()                                   // reclaim key so the survey keeps responding
    }

    /// A friendly default name from the apps that seed the layer (mirrors StudioLayerStore's).
    private static func defaultLayerName(forApps apps: [String]) -> String {
        switch apps.count {
        case 0:  return "Layer"
        case 1:  return apps[0]
        case 2:  return "\(apps[0]) + \(apps[1])"
        default: return "\(apps[0]) +\(apps.count - 1)"
        }
    }

    /// Build the Layers section view-models for a screen: each rule-backed layer as a
    /// pile whose preview is a *screen-map* of its member windows on this display (cheap
    /// per-monitor scoping — same layer can appear on both displays, each showing its
    /// local slice), plus a trailing ＋ pile. A pile reads as "staged" while any window
    /// holds a pending join to it.
    private func layerPiles(on screen: NSScreen) -> [ExposeView.LayerPile] {
        let store = StudioLayerStore.shared
        let screenAX = MotionPanel.axRect(of: screen)
        var piles = store.layers.map { layer -> ExposeView.LayerPile in
            let onScreen = store.resolve(layer).filter { entry($0, isOn: screen) }
            let members = onScreen.map { w -> ExposeView.LayerMember in
                ExposeView.LayerMember(
                    id: w.wid,
                    frac: MotionPanel.frac(of: w.frame, in: screenAX),
                    tint: Color(nsColor: MotionPanel.tint(for: w.app)),
                    image: thumbs[w.wid])
            }
            let stagedCount = stagedIntents.values.filter { $0.layers.contains(layer.id) }.count
            return ExposeView.LayerPile(id: layer.id, name: layer.name, count: onScreen.count,
                                        members: members, rule: layer.summary, isNew: false,
                                        staged: stagedCount > 0, stagedCount: stagedCount)
        }
        let newCount = stagedIntents.values.filter { $0.newLayer }.count
        piles.append(ExposeView.LayerPile(id: HyperspaceDrag.newLayerKey, name: "new", count: 0,
                                          isNew: true, staged: newCount > 0, stagedCount: newCount))
        return piles
    }

    /// Every window currently on a screen, as fractional footprints — the Preview's
    /// always-on baseline ("what this display looks like right now").
    private func currentLayout(on screen: NSScreen) -> [ExposeView.LayerMember] {
        let screenAX = MotionPanel.axRect(of: screen)
        return surveyMembers(on: screen).map { w in
            ExposeView.LayerMember(
                id: w.wid,
                frac: MotionPanel.frac(of: w.frame, in: screenAX),
                tint: Color(nsColor: MotionPanel.tint(for: w.app)),
                image: thumbs[w.wid])
        }
    }

    /// Staged *locations* on a given screen, as fractional footprints for the Lattice
    /// preview — persistent evidence of where each dragged window will land.
    private func stagedPlan(on screen: NSScreen) -> [ExposeView.StagedMarker] {
        let members = Set(surveyMembers(on: screen).map(\.wid))
        return stagedIntents.compactMap { wid, intent -> ExposeView.StagedMarker? in
            guard members.contains(wid), let loc = intent.location,
                  let w = eligible.first(where: { $0.wid == wid }) else { return nil }
            let f = loc.fractions
            return ExposeView.StagedMarker(
                id: wid,
                frac: CGRect(x: f.0, y: f.1, width: f.2, height: f.3),
                tint: Color(nsColor: MotionPanel.tint(for: w.app)),
                image: thumbs[wid],
                label: stagedLabel(for: wid) ?? "")
        }
    }

    /// Commit the drag & drop intent plan (design/hyperspace-drag-drop.md). Location
    /// moves the window; layer joins are written to StudioLayerStore; ＋ piles seed a
    /// fresh layer. (Space axis is Phase 3.) No-op until `stagedIntents` is populated,
    /// so it's safe to call on every gather.
    private func commitStagedIntents(on screen: NSScreen) {
        var newLayerSeeds: [WindowEntry] = []
        for (wid, intent) in stagedIntents where !intent.isEmpty {
            guard let entry = eligible.first(where: { $0.wid == wid }) else { continue }
            if let placement = intent.location {
                if originalFrames[wid] == nil, let el = ax(for: entry),
                   let cur = RealWindowAnimator.axFrame(el) {
                    originalFrames[wid] = cur
                }
                WindowTiler.tileWindowById(wid: wid, pid: entry.pid, to: placement, on: screen)
                didMoveWindows = true        // a real move → Esc must restore
            }
            for layerID in intent.layers {
                addAppToLayer(entry.app, layerID: layerID)
            }
            if intent.newLayer { newLayerSeeds.append(entry) }
            // Phase 3: intent.space → WindowTiler.moveViaCGS
        }
        if !newLayerSeeds.isEmpty {
            let layer = StudioLayerStore.shared.saveFromPluck(newLayerSeeds)
            DiagnosticLog.shared.info("Hyperspace commit — new layer '\(layer.name)' from \(newLayerSeeds.count) window(s)")
        }
    }

    /// Add an app clause to a layer's rule so it (and future windows of that app)
    /// join the layer. Rule-backed membership — coarse by design, like saveFromPluck.
    /// No-op if the layer already matches the app.
    private func addAppToLayer(_ app: String, layerID: String) {
        let store = StudioLayerStore.shared
        guard var layer = store.layers.first(where: { $0.id == layerID }) else { return }
        let already = layer.match.contains { $0.titleContains == nil && $0.app?.localizedCaseInsensitiveCompare(app) == .orderedSame }
        guard !already else { return }
        layer.match.append(StudioLayerClause(app: app, titleContains: nil))
        store.update(layer)
        DiagnosticLog.shared.info("Hyperspace commit — layer '\(layer.name)' += app '\(app)'")
    }

    /// Gather the picked set into a balanced grid on the active display (the only
    /// place real windows move) and stay in the mode. Un-picked windows are left
    /// exactly where they are — in the survey they never moved. Shared by G and ⏎.
    private func gatherInPlace() {
        removeExposeHost()
        let screen = activeSurveyScreen ?? NSScreen.main ?? NSScreen.screens[0]
        commitStagedIntents(on: screen)   // drag & drop plan; no-op until staged
        let members = gatherMembers()
        if members.count >= 2 {
            relayoutGroup()                                       // picked set snaps into the grid, on top
        } else if let only = members.first, let el = ax(for: only) {
            raising { RealWindowAnimator.raise(el) }              // a single pick just comes forward
        }
        exposed = false
        ignoresMouseEvents = false
        updateLegend()
        refreshBorders()
        updateStack()
    }

    private func gatherInPlace(on screen: NSScreen) {
        setActiveSurveyScreen(screen)
        gatherInPlace()
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

    private func resetSurveyState(for screens: [NSScreen]) {
        let validIDs = Set(screens.map(MotionPanel.screenID))
        pickOrderByScreen = pickOrderByScreen.filter { validIDs.contains($0.key) }
        exposeClustersByScreen.removeAll()
        exposeOrderByScreen.removeAll()
        exposeAimByScreen.removeAll()
        hintForByScreen.removeAll()
        hintMapByScreen.removeAll()
        clusterHintForByScreen.removeAll()
        clusterHintMapByScreen.removeAll()
        exposeTileWByScreen.removeAll()
        exposeFramesByScreen.removeAll()
        canvasByScreenID = canvasByScreenID.filter { validIDs.contains($0.key) }
    }

    private func rebuildSurveyState(for screen: NSScreen, resetAim: Bool = false) {
        let id = MotionPanel.screenID(screen)
        let members = surveyMembers(on: screen)
        let clusters = buildClusters(members)
        let order = clusters.flatMap { $0.members.map(\.wid) }
        let oldAim = exposeAimByScreen[id] ?? 0
        let frames = exposeFramesByScreen[id] ?? [:]
        let (hf, hm) = (handKeysMode && frames.count >= order.count)
            ? computeHandHints(order: order, frames: frames)
            : readingHints(for: order)
        let (chf, chm) = clusterHints(for: clusters)

        exposeClustersByScreen[id] = clusters
        exposeOrderByScreen[id] = order
        exposeAimByScreen[id] = resetAim ? 0 : min(oldAim, max(order.count - 1, 0))
        hintForByScreen[id] = hf
        hintMapByScreen[id] = hm
        clusterHintForByScreen[id] = chf
        clusterHintMapByScreen[id] = chm
        exposeTileWByScreen[id] = autoTileWidth(count: members.count, screen: screen)

        let memberIDs = Set(members.map(\.wid))
        pickOrderByScreen[id] = (pickOrderByScreen[id] ?? []).filter { memberIDs.contains($0) }
    }

    private func syncActiveSurveyState(from screen: NSScreen) {
        let id = MotionPanel.screenID(screen)
        exposeClusters = exposeClustersByScreen[id] ?? []
        exposeOrder = exposeOrderByScreen[id] ?? []
        exposeAim = exposeAimByScreen[id] ?? 0
        hintFor = hintForByScreen[id] ?? [:]
        hintMap = hintMapByScreen[id] ?? [:]
        clusterHintFor = clusterHintForByScreen[id] ?? [:]
        clusterHintMap = clusterHintMapByScreen[id] ?? [:]
        exposeTileW = exposeTileWByScreen[id] ?? autoTileWidth(count: surveyMembers(on: screen).count, screen: screen)
        exposeFrames = exposeFramesByScreen[id] ?? [:]
        restorePickState(for: screen)
    }

    private func readingHints(for order: [UInt32]) -> ([UInt32: String], [String: UInt32]) {
        let homerow = Array("asdfghjklqwertyuiopzxcvbnm").filter { !MotionPanel.reservedKeys.contains($0) }
        var hf: [UInt32: String] = [:], hm: [String: UInt32] = [:]
        for (i, wid) in order.enumerated() where i < homerow.count {
            let h = String(homerow[i]); hf[wid] = h; hm[h] = wid
        }
        return (hf, hm)
    }

    private func computeHandHints(order: [UInt32], frames: [UInt32: CGRect]) -> ([UInt32: String], [String: UInt32]) {
        let rightKeys = Array("jkluiophynm;").filter  { !MotionPanel.reservedKeys.contains($0) }
        let leftKeys  = Array("fdsarewqgtvcxzb").filter { !MotionPanel.reservedKeys.contains($0) }
        let placed = order.compactMap { wid in frames[wid].map { (wid: wid, rect: $0) } }
        guard !placed.isEmpty else { return readingHints(for: order) }
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

    private func clusterHints(for clusters: [ExposeCluster]) -> ([Int: String], [String: Int]) {
        var hf: [Int: String] = [:], hm: [String: Int] = [:]
        var used = Set<String>()
        let alphabet = "abcdefghijklmnopqrstuvwxyz".map(String.init)
        for box in clusters {
            let fromName = box.name.lowercased().filter { $0.isLetter }.map(String.init)
            guard let letter = (fromName + alphabet).first(where: {
                !used.contains($0) && !MotionPanel.reservedKeys.contains(Character($0))
            }) else { continue }
            used.insert(letter)
            hf[box.id] = letter.uppercased()
            hm[letter] = box.id
        }
        return (hf, hm)
    }

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
        guard let screen = activeSurveyScreen else { return }
        reassignHandHints(on: screen)
    }

    private func reassignHandHints(on screen: NSScreen) {
        guard exposed else { return }
        let id = MotionPanel.screenID(screen)
        let order = exposeOrderByScreen[id] ?? []
        let frames = exposeFramesByScreen[id] ?? [:]
        let (hf, hm) = (handKeysMode && frames.count >= order.count)
            ? computeHandHints(order: order, frames: frames)
            : readingHints(for: order)
        guard hf != hintForByScreen[id] else { return }
        hintForByScreen[id] = hf
        hintMapByScreen[id] = hm
        if activeSurveyScreen.map(MotionPanel.screenID) == id {
            hintFor = hf
            hintMap = hm
        }
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
    /// Height of the top intent band on a given display. Shared by the survey
    /// fit (so tiles never run under the band) and ExposeView (which draws it).
    private func bandHeight(for screen: NSScreen) -> CGFloat {
        // Reserve a touch under the top third for the intent band so the survey
        // grid gets the bottom ~2/3 (design/hyperspace-drag-drop.md). Floored so the
        // Layers/Lattice/Spaces cards still fit on a short display, capped so it
        // doesn't bloat on a tall external one.
        max(196, min(screen.frame.height * 0.30, 420))
    }

    private func autoTileWidth(count n: Int, screen: NSScreen) -> CGFloat {
        let area = screen.frame
        let pad: CGFloat = 72            // 36pt survey padding each side
        let availW = max(200, area.width - pad)
        let availH = max(200, area.height - pad - bandHeight(for: screen))   // reserve the intent band
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

    private func installExposeHosts() {
        removeExposeHost()
        for screen in surveyScreens() {
            let id = MotionPanel.screenID(screen)
            let hosting = NSHostingView(rootView: ExposeView(
                clusters: [],
                tileWidth: autoTileWidth(count: max(1, surveyMembers(on: screen).count), screen: screen),
                canvas: canvasForScreen(screen),
                drag: dragModel,
                screenID: id,
                bandHeight: bandHeight(for: screen),
                screenAspect: screen.visibleFrame.width / max(1, screen.visibleFrame.height),
                usableInset: MotionPanel.usableInset(of: screen),
                onNewLayer: { [weak self] in self?.presentNewLayer() }))
            hosting.frame = NSRect(origin: .zero, size: screen.frame.size)
            hosting.autoresizingMask = [.width, .height]
            let panel = HyperspaceScreenPanel(screen: screen)
            panel.contentView = hosting
            panel.orderFrontRegardless()
            exposeHostsByScreenID[id] = hosting
            exposePanelsByScreenID[id] = panel
        }
        exposeHost = activeSurveyScreen.flatMap { exposeHostsByScreenID[MotionPanel.screenID($0)] }
    }

    private func removeExposeHost() {
        exposePanelsByScreenID.values.forEach { $0.close() }
        exposePanelsByScreenID.removeAll()
        exposeHostsByScreenID.values.forEach { $0.removeFromSuperview() }
        exposeHostsByScreenID.removeAll()
        exposeHost = nil
    }

    /// Rebuild the spread's view-model from current picks/aim/captures. Cheap —
    /// the cluster *structure* is fixed for the life of a survey; only the per-tile
    /// pick slot, highlight, and image change.
    private func rebuildExposeView() {
        guard exposed else { return }
        // Replacing host.rootView mid-drag would tear down the in-flight SwiftUI
        // gesture and abort the drag. Skip while a drag is live; handleDrop()
        // rebuilds once it ends.
        guard !dragModel.isActive else { return }
        if exposeHostsByScreenID.isEmpty { installExposeHosts() }
        exposeHost = activeSurveyScreen.flatMap { exposeHostsByScreenID[MotionPanel.screenID($0)] }

        for screen in surveyScreens() {
            let id = MotionPanel.screenID(screen)
            guard let host = exposeHostsByScreenID[id] else { continue }
            let members = surveyMembers(on: screen)
            if exposeClustersByScreen[id] == nil {
                rebuildSurveyState(for: screen, resetAim: true)
            }
            let clusters = exposeClustersByScreen[id] ?? []
            let screenHintFor = hintForByScreen[id] ?? [:]
            let screenClusterHintFor = clusterHintForByScreen[id] ?? [:]
            let vm = clusters.map { box in
                ExposeView.Cluster(
                    id: box.id,
                    name: box.name,
                    rule: box.rule,
                    userDefined: box.userDefined,
                    hint: screenClusterHintFor[box.id] ?? "",
                    tiles: box.members.map { tileVM($0, on: screen, hints: screenHintFor) }
                )
            }
            host.rootView = ExposeView(
                clusters: vm,
                tileWidth: exposeTileWByScreen[id] ?? autoTileWidth(count: members.count, screen: screen),
                canvas: canvasForScreen(screen),
                drag: dragModel,
                screenID: id,
                bandHeight: bandHeight(for: screen),
                screenAspect: screen.visibleFrame.width / max(1, screen.visibleFrame.height),
                usableInset: MotionPanel.usableInset(of: screen),
                onPick: { [weak self] wid in self?.exposeToggle(wid, on: screen) },
                onDrop: { [weak self] wid, spec in self?.handleDrop(wid, spec) },
                onDropLayer: { [weak self] wid, key in self?.handleLayerDrop(wid, key) },
                layers: layerPiles(on: screen),
                stagedPlan: stagedPlan(on: screen),
                currentLayout: currentLayout(on: screen),
                displayScope: exposeDisplayScope(for: screen),
                onLayout: { [weak self] frames in
                    guard let self else { return }
                    DispatchQueue.main.async {
                        guard self.exposed, frames != self.exposeFramesByScreen[id] else { return }
                        self.exposeFramesByScreen[id] = frames
                        if self.handKeysMode { self.reassignHandHints(on: screen) }
                    }
                },
                onHandKeys: { [weak self] on in
                    guard let self else { return }
                    self.handKeysMode = on
                    self.surveyScreens().forEach { self.reassignHandHints(on: $0) }
                },
                onExit: { [weak self] in self?.onExit?() },   // ✕ — leave, keep what's on screen
                onNewLayer: { [weak self] in self?.presentNewLayer() },
                loadSummary: loadSummaryText())
        }
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

    private func tileVM(_ w: WindowEntry, on screen: NSScreen, hints: [UInt32: String]) -> ExposeView.Tile {
        let id = MotionPanel.screenID(screen)
        let savedOrder = pickOrderByScreen[id] ?? []
        let order = exposeOrderByScreen[id] ?? []
        let aim = exposeAimByScreen[id] ?? 0
        return ExposeView.Tile(
            id: w.wid, app: w.app, title: w.title,
            tint: Color(nsColor: MotionPanel.tint(for: w.app)),
            image: thumbs[w.wid],
            hint: hints[w.wid] ?? "",
            pickSlot: savedOrder.firstIndex(of: w.wid).map { $0 + 1 },
            isAimed: order[safe: aim] == w.wid,
            staged: stagedLabel(for: w.wid),
            layerTags: layerTags(for: w.wid)
        )
    }

    /// Names of the layers a window is staged to join (plus "new" for a staged ＋),
    /// shown as labels along the tile's bottom. Empty when nothing layer-ish is staged.
    private func layerTags(for wid: UInt32) -> [String] {
        guard let intent = stagedIntents[wid] else { return [] }
        let names = StudioLayerStore.shared.layers
            .filter { intent.layers.contains($0.id) }
            .map(\.name)
        return intent.newLayer ? names + ["new"] : names
    }

    /// Compact badge for a window's staged *location*, e.g. "¼ 1,0". Layer membership
    /// is shown separately as bottom labels (see layerTags) — a tag, not a move.
    private func stagedLabel(for wid: UInt32) -> String? {
        guard let loc = stagedIntents[wid]?.location else { return nil }
        if case let .grid(g) = loc {
            return "\(LatticeRes.glyph(cols: g.columns, rows: g.rows)) \(g.column),\(g.row)"
        }
        return loc.wireValue
    }

    /// Pluck a tile by wid (hint key or click) and refresh the survey + minimap.
    private func exposeToggle(_ wid: UInt32) {
        togglePicked(wid)
        rebuildExposeView()
        updateLegend()
        updateStack()
    }

    private func exposeToggle(_ wid: UInt32, on screen: NSScreen) {
        let id = MotionPanel.screenID(screen)
        var order = pickOrderByScreen[id] ?? []
        if order.contains(wid) {
            order.removeAll { $0 == wid }
        } else {
            order.append(wid)
            if let e = eligible.first(where: { $0.wid == wid }) { _ = ax(for: e) }
        }
        let memberIDs = Set(surveyMembers(on: screen).map(\.wid))
        pickOrderByScreen[id] = order.filter { memberIDs.contains($0) }
        if activeSurveyScreen.map(MotionPanel.screenID) != id {
            setActiveSurveyScreen(screen)
        } else {
            restorePickState(for: screen)
        }
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

    private func exposeToggleCluster(_ clusterID: Int, on screen: NSScreen) {
        let screenID = MotionPanel.screenID(screen)
        guard let box = exposeClustersByScreen[screenID]?.first(where: { $0.id == clusterID }) else {
            NSSound.beep()
            return
        }
        let wids = box.members.map { $0.wid }
        guard !wids.isEmpty else { return }
        var order = pickOrderByScreen[screenID] ?? []
        let selected = Set(order)
        let allPicked = wids.allSatisfy { selected.contains($0) }
        if allPicked {
            order.removeAll { wids.contains($0) }
        } else {
            for wid in wids where !order.contains(wid) {
                order.append(wid)
                if let e = eligible.first(where: { $0.wid == wid }) { _ = ax(for: e) }
            }
        }
        pickOrderByScreen[screenID] = order
        if activeSurveyScreen.map(MotionPanel.screenID) != screenID {
            setActiveSurveyScreen(screen)
        } else {
            restorePickState(for: screen)
        }
        rebuildExposeView()
        updateLegend()
        updateStack()
    }

    // MARK: - Display-scoped survey

    private func surveyScreens() -> [NSScreen] {
        NSScreen.screens.filter { screen in
            !surveyMembers(on: screen).isEmpty
        }
    }

    private func surveyMembers(on screen: NSScreen) -> [WindowEntry] {
        eligible.filter { entry($0, isOn: screen) }
    }

    private func engageSurveyScreen(_ screen: NSScreen, toggling wid: UInt32? = nil) {
        let targetID = MotionPanel.screenID(screen)
        let currentID = activeSurveyScreen.map(MotionPanel.screenID)
        if currentID != targetID {
            savePickStateForActiveScreen()
            setActiveSurveyScreen(screen)
        }
        if let wid {
            exposeToggle(wid)
        }
    }

    private func screenForEvent(_ event: NSEvent) -> NSScreen? {
        if let window = event.window,
           let screenID = exposePanelsByScreenID.first(where: { window === $0.value })?.key,
           let screen = NSScreen.screens.first(where: { MotionPanel.screenID($0) == screenID }) {
            return screen
        }
        let point = event.locationInWindow
        let global = CGPoint(x: point.x + frame.origin.x, y: point.y + frame.origin.y)
        return NSScreen.screens.first(where: { $0.frame.contains(global) })
    }

    private func screenForPointer() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(point) })
    }

    private func validSurveyScreen(_ screen: NSScreen?) -> NSScreen? {
        guard let screen, !surveyMembers(on: screen).isEmpty else { return nil }
        return screen
    }

    private func setActiveSurveyScreen(_ screen: NSScreen) {
        if activeSurveyScreen.map(MotionPanel.screenID) != MotionPanel.screenID(screen) {
            savePickStateForActiveScreen()
        }
        activeScreenID = MotionPanel.screenID(screen)

        let members = eligible.enumerated().filter { _, entry in self.entry(entry, isOn: screen) }
        let allMembers = surveyScreens().flatMap { surveyMembers(on: $0) }
        guard let first = members.first else { NSSound.beep(); return }
        if !entry(activeEntry, isOn: screen) {
            reticle = first.offset
        }

        lastSide = nil
        restorePickState(for: screen)

        if exposed {
            captureCount = allMembers.count
            if exposeClustersByScreen[MotionPanel.screenID(screen)] == nil {
                rebuildSurveyState(for: screen, resetAim: true)
            }
            syncActiveSurveyState(from: screen)
            if exposeHostsByScreenID.isEmpty {
                installExposeHosts()
            }
            allMembers.forEach { captureThumb(for: $0) }
            rebuildExposeView()
            checkCapturesSettled()
        }

        updateLegend()
        updateStack()
        refreshBorders()
    }

    private func savePickStateForActiveScreen() {
        guard let screen = activeSurveyScreen else { return }
        let memberIDs = Set(eligible.filter { entry($0, isOn: screen) }.map(\.wid))
        pickOrderByScreen[MotionPanel.screenID(screen)] = pickOrder.filter { memberIDs.contains($0) }
    }

    private func restorePickState(for screen: NSScreen) {
        let memberIDs = Set(eligible.filter { entry($0, isOn: screen) }.map(\.wid))
        let savedOrder = (pickOrderByScreen[MotionPanel.screenID(screen)] ?? []).filter { memberIDs.contains($0) }
        pickOrder = savedOrder
        group = Set(savedOrder)
    }

    private func canvasForScreen(_ screen: NSScreen) -> ExposeCanvas {
        let id = MotionPanel.screenID(screen)
        if let existing = canvasByScreenID[id] {
            return existing
        }
        let newCanvas = ExposeCanvas()
        canvasByScreenID[id] = newCanvas
        return newCanvas
    }

    private func exposeDisplayScope(for screen: NSScreen) -> ExposeView.DisplayScope? {
        let screens = surveyScreens()
        let screenID = MotionPanel.screenID(screen)
        guard let index = screens.firstIndex(where: { MotionPanel.screenID($0) == screenID }) else {
            return nil
        }
        let physicalIndex = NSScreen.screens.firstIndex(where: { MotionPanel.screenID($0) == screenID }) ?? index
        let windows = surveyMembers(on: screen).count
        return ExposeView.DisplayScope(
            index: physicalIndex,
            count: screens.count,
            label: physicalIndex == 0 ? "Main" : "Display \(physicalIndex + 1)",
            windowCount: windows,
            isActive: activeSurveyScreen.map(MotionPanel.screenID) == screenID
        )
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

    private func exposeAimStep(_ delta: Int, on screen: NSScreen) {
        let id = MotionPanel.screenID(screen)
        let order = exposeOrderByScreen[id] ?? []
        guard !order.isEmpty else { return }
        let current = exposeAimByScreen[id] ?? 0
        exposeAimByScreen[id] = ((current + delta) % order.count + order.count) % order.count
        if activeSurveyScreen.map(MotionPanel.screenID) != id {
            setActiveSurveyScreen(screen)
        } else {
            exposeAim = exposeAimByScreen[id] ?? 0
        }
        rebuildExposeView()
    }

    /// True if the window's center sits on `screen` (AppKit coords, like screen(for:)).
    private func entry(_ e: WindowEntry, isOn screen: NSScreen) -> Bool {
        MotionPanel.screenID(WindowTiler.screenForWindowFrame(e.frame)) == MotionPanel.screenID(screen)
    }

    /// Run window-raising work while swallowing the transient key-resign it can
    /// trigger, so the overlay doesn't auto-exit mid-operation.
    private func raising(_ body: () -> Void) {
        ignoreResign = true
        didMoveWindows = true        // every real move/raise funnels through here
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
        WindowTiler.screenForWindowFrame(entry.frame)
    }

    private static func screenID(_ screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return "display-\(number.intValue)"
        }
        let f = screen.frame
        return "display-\(Int(f.minX))-\(Int(f.minY))-\(Int(f.width))-\(Int(f.height))"
    }

    private static func screensUnion() -> NSRect {
        NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }
    }

    /// A screen's *usable* area (visibleFrame — below the menu bar, above the Dock) in AX/CG
    /// (top-left origin) coords — the same space as `WindowEntry.frame` AND the same rect
    /// `WindowTiler.tileFrame` divides into grid cells. Using visibleFrame (not the full frame)
    /// keeps the placement preview 1:1 with where windows actually land (no size mismatch).
    static func axRect(of screen: NSScreen) -> CGRect {
        let primaryH = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let vf = screen.visibleFrame
        let axTop = primaryH - vf.maxY
        return CGRect(x: vf.minX, y: axTop, width: vf.width, height: vf.height)
    }

    /// The inset from a screen's full frame to its usable visibleFrame, in SwiftUI top-left
    /// coords — so an overlay sized to the full panel can place content inside the menu bar/Dock.
    static func usableInset(of screen: NSScreen) -> EdgeInsets {
        let f = screen.frame, v = screen.visibleFrame
        return EdgeInsets(top: max(0, f.maxY - v.maxY),
                          leading: max(0, v.minX - f.minX),
                          bottom: max(0, v.minY - f.minY),
                          trailing: max(0, f.maxX - v.maxX))
    }

    /// A window frame as a top-origin fractional rect within `screenAX`, clamped to the
    /// unit square so off-screen spill doesn't blow out the map.
    static func frac(of frame: WindowFrame, in screenAX: CGRect) -> CGRect {
        guard screenAX.width > 1, screenAX.height > 1 else { return .zero }
        let x = (CGFloat(frame.x) - screenAX.minX) / screenAX.width
        let y = (CGFloat(frame.y) - screenAX.minY) / screenAX.height
        let cx = min(max(x, 0), 1), cy = min(max(y, 0), 1)
        return CGRect(x: cx, y: cy,
                      width: min(CGFloat(frame.w) / screenAX.width, 1 - cx),
                      height: min(CGFloat(frame.h) / screenAX.height, 1 - cy))
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
        let screenFrame = (activeSurveyScreen ?? screen(for: activeEntry) ?? NSScreen.main)?.frame ?? frame
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
            let screenFrame = (activeSurveyScreen ?? screen(for: activeEntry) ?? NSScreen.main)?.frame ?? frame
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
                     exposed: exposed,
                     displayCount: surveyScreens().count)
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
        let screenFrame = (activeSurveyScreen ?? screen(for: activeEntry) ?? NSScreen.main)?.frame ?? frame
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
        let screenFrame = (activeSurveyScreen ?? screen(for: activeEntry) ?? NSScreen.main)?.frame ?? frame
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
    var displayCount: Int = 1

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
                keyHint("⌘scroll", "zoom")
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

/// Reports the Lattice drop-grid's frame (in the root coordinate space) so a drop
/// can be hit-tested to a cell.
private struct LatticeFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// Collects each Layers pile's frame (root space, keyed by layer id / newLayerKey)
/// so a drop can be hit-tested to a pile.
private struct LayerFrameKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// The one-shot "landed" ring flashed at a drop target. Expands and fades on appear;
/// keyed by the pulse token (`.id`) so each drop replays it from scratch.
private struct DropPulseRing: View {
    let frame: CGRect
    let tint: Color
    @State private var on = false

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(tint, lineWidth: 2.5)
            .frame(width: frame.width, height: frame.height)
            .scaleEffect(on ? 1.35 : 0.92)
            .opacity(on ? 0 : 0.95)
            .position(x: frame.midX, y: frame.midY)
            .allowsHitTesting(false)
            .onAppear { withAnimation(.easeOut(duration: 0.45)) { on = true } }
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
        var staged: String? = nil      // drag-staged location badge, e.g. "¼ 1,0"
        var layerTags: [String] = []   // staged layer memberships (names) — shown as bottom labels
    }

    struct Cluster: Identifiable {
        let id: Int
        let name: String
        let rule: String
        let userDefined: Bool
        let hint: String          // ⇧-letter that plucks the whole cluster
        let tiles: [Tile]
    }

    struct DisplayScope {
        let index: Int
        let count: Int
        let label: String
        let windowCount: Int
        let isActive: Bool
    }

    // A member window of a layer, placed on its screen-map preview at its real
    // (screen-relative, top-origin) fractional rect.
    struct LayerMember: Identifiable {
        let id: UInt32
        let frac: CGRect
        let tint: Color
        let image: NSImage?
    }

    // A layer rendered as a drop "pile": a screen-map preview of its member windows
    // (so you see *what the layer looks like*), its name + on-screen count + rule.
    // `staged` marks a pending join (highlight). The ＋ pile uses
    // HyperspaceDrag.newLayerKey as its id.
    struct LayerPile: Identifiable {
        let id: String
        let name: String
        let count: Int                       // members on the active screen
        var members: [LayerMember] = []      // for the screen-map preview
        var rule: String = ""                // human-readable match rule, e.g. "Chrome · ~dev"
        var isNew: Bool = false
        var staged: Bool = false
        var stagedCount: Int = 0             // how many windows are staged to join this pile
    }

    // A window's staged *location* drawn into the Lattice preview as proof of the plan:
    // a translucent app-tinted footprint at its fractional target rect (resolution-
    // agnostic), so the band shows where everything will land before you commit.
    struct StagedMarker: Identifiable {
        let id: UInt32          // wid
        let frac: CGRect        // x,y,w,h in 0…1, top-origin (PlacementSpec.fractions)
        let tint: Color
        let image: NSImage?
        let label: String       // e.g. "¼ 1,0"
    }

    let clusters: [Cluster]
    let tileWidth: CGFloat
    @ObservedObject var canvas: ExposeCanvas
    @ObservedObject var drag: HyperspaceDrag
    var screenID: String = ""
    var bandHeight: CGFloat = 200
    var screenAspect: CGFloat = 1.6
    var usableInset = EdgeInsets()   // full panel(frame) → visibleFrame, so the Place stage clears the menu bar/Dock
    var onPick: (UInt32) -> Void = { _ in }
    var onDrop: (UInt32, PlacementSpec?) -> Void = { _, _ in }
    var onDropLayer: (UInt32, String) -> Void = { _, _ in }
    var layers: [LayerPile] = []
    var stagedPlan: [StagedMarker] = []
    var currentLayout: [LayerMember] = []   // every window on this display — context for the Place stage
    var displayScope: DisplayScope?
    var onLayout: ([UInt32: CGRect]) -> Void = { _ in }
    var onHandKeys: (Bool) -> Void = { _ in }
    var onExit: () -> Void = { }              // mouse-driven leave (the ✕ button)
    var onNewLayer: () -> Void = { }          // tap the ＋ pile → open the New Layer authoring flow
    var loadSummary: String = ""

    private let ink = Color(red: 0.02, green: 0.03, blue: 0.05)
    static let surveySpace = "hyperspace.survey"
    static let rootSpace = "hyperspace.root"   // band + survey + ghost share this space

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
    // The visual-settings rig (lighting/size/zoom/keys/perf) lives behind a gear
    // in the top-right; collapsed by default so it doesn't cover the intent band.
    @State private var dialsOpen = false

    @State private var perfMode = false
    @State private var perfFlat = false                  // A = true, B = false
    @StateObject private var perf = PerfStats()

    var body: some View {
        ZStack {
            backdrop                                    // full-bleed lit scrim
            VStack(spacing: 0) {
                intentBand                              // top: Layers · Grid
                    .frame(height: bandHeight)
                survey                                  // bottom: the window lattice (the preview surface)
            }
            placementStage                              // "Place…" → full-screen, click where it goes
            ghostOverlay                                // the dragged thumbnail
            dropPulseOverlay                            // the "landed" ring at the drop target
        }
        .coordinateSpace(name: ExposeView.rootSpace)    // band, survey, ghost share one space
        .animation(.spring(response: 0.26, dampingFraction: 0.82), value: rosterPileID)
        .animation(.spring(response: 0.26, dampingFraction: 0.82), value: drag.placeWid)
        .animation(.spring(response: 0.2, dampingFraction: 0.74), value: drag.placeCell)
        .overlay(alignment: .topLeading) {
            if let displayScope, !drag.isPlacing {
                displayBadge(displayScope)
                    .padding(20)
            }
        }
        .overlay(alignment: .topTrailing) {
            if !drag.isPlacing {                            // the Place stage owns the screen
                VStack(alignment: .trailing, spacing: 8) {
                    exitButton
                    settingsToggle
                    if dialsOpen { dials }
                }
                .padding(20)
            }
        }
        .overlay(alignment: .top) {
            if perfMode {
                perfHUD.padding(.top, 22)
            }
        }
        .overlay(alignment: .top) {
            if !drag.isPlacing {
                planSummaryBar.padding(.top, bandHeight + 4)   // sits just under the intent band
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // A one-line readout of the whole staged plan, so the grouped intent reads at a
    // glance and the commit/discard affordance is always in view. Shown only when
    // something is staged. Derived from the on-screen tiles (single-screen drag).
    @ViewBuilder
    private var planSummaryBar: some View {
        let tiles = clusters.flatMap(\.tiles)
        let placed = tiles.filter { $0.staged != nil }.count
        let tagged = tiles.filter { !$0.layerTags.isEmpty }.count
        if placed + tagged > 0 {
            HStack(spacing: 10) {
                if placed > 0 { planChip("▦", "\(placed) placed") }
                if tagged > 0 { planChip("▢", "\(tagged) tagged") }
                Rectangle().fill(Palette.border).frame(width: 0.5, height: 12)
                Text("⏎ commit").font(Typo.monoBold(9)).foregroundColor(Palette.running)
                Text("esc discard").font(Typo.mono(9)).foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(
                Capsule().fill(Color.black.opacity(0.6))
                    .overlay(Capsule().strokeBorder(Palette.running.opacity(0.4), lineWidth: 0.5))
            )
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.32, dampingFraction: 0.78), value: placed + tagged)
        }
    }

    private func planChip(_ glyph: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(glyph).font(.system(size: 10)).foregroundColor(Palette.running)
            Text(label).font(Typo.monoBold(9)).foregroundColor(.white.opacity(0.85))
        }
    }

    // The lit room behind everything. Under the perf harness it repaints every
    // frame (and feeds the cadence meter); otherwise it's a static pass.
    @ViewBuilder
    private var backdrop: some View {
        if perfMode {
            TimelineView(.animation) { ctx in
                scrim(phase: ctx.date.timeIntervalSinceReferenceDate)
                    .onChange(of: ctx.date) { _, d in perf.record(d.timeIntervalSinceReferenceDate) }
            }
        } else {
            scrim(phase: 0)
        }
    }

    // The window lattice — the bottom two-thirds. Top-anchored (frame alignment .top)
    // so the lattice sits just under the intent band instead of being centred in the
    // bottom region with a gap above it. Pure view transform (zoom/pan); no real
    // window moves here.
    private var survey: some View {
        FlowLayout(spacing: 18, lineSpacing: 18, vAlign: .top) {
            ForEach(clusters) { clusterBox($0) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 36)
        .padding(.top, 20)
        .padding(.bottom, 36)
        .coordinateSpace(name: ExposeView.surveySpace)   // tile frames measured here stay un-scaled
        .scaleEffect(canvas.zoom, anchor: .center)        // canvas zoom — transform sits OUTSIDE the space
        .offset(canvas.pan)
        .onPreferenceChange(TileFramesKey.self) { onLayout($0) }
    }

    // MARK: - Placement stage — right-click a window, pick its spot life-size
    //
    // A modal, life-size stage over the desktop area: the screen with its current windows drawn
    // faint for context, the right-clicked window as a bright ghost, and a grid of the active
    // resolution you *click* to place it. Mouse-only twin of drag → Grid — clicking a cell runs
    // the same `onDrop` staging path. Click-away or Esc cancels.
    @ViewBuilder
    private var placementStage: some View {
        if let wid = drag.placeWid, drag.placeScreen == screenID {
            let target = currentLayout.first { $0.id == wid }
            GeometryReader { geo in
                // A miniature of *this* monitor — bezel + screen — floating in a heavy scrim that
                // swallows the desktop noise. The screen shows the **projected future** layout (staged
                // moves applied), divided into clickable sections. A contained object, not a takeover:
                // it can't leak off-screen and it reads as a deliberate control.
                let screen = aspectFit(in: CGSize(width: geo.size.width * 0.52,
                                                  height: geo.size.height * 0.56), aspect: screenAspect)
                ZStack {
                    Color.black.opacity(0.96)                          // swallow the noise around the vessel
                        .contentShape(Rectangle())
                        .onTapGesture { drag.endPlacing() }            // click-away cancels
                    // Monitor centred in the screen; caption floats just above it (an overlay, so it
                    // doesn't push the monitor off-centre).
                    monitorVessel(screen: screen, wid: wid, target: target)
                        .overlay(alignment: .top) {
                            placementCaption(wid: wid).fixedSize().offset(y: -34)
                        }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .ignoresSafeArea()
            .transition(.opacity)
        }
    }

    // The miniature monitor: a bezel framing a screen that shows the *projected future* layout —
    // unchanged windows faint, staged moves bright at their new spots, the window being placed
    // tracking the hovered section. The bezel + heavy surrounding scrim make it read as an object.
    private func monitorVessel(screen: CGSize, wid: UInt32, target: ExposeView.LayerMember?) -> some View {
        let bezel: CGFloat = 16
        let screenShape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        let stagedById = Dictionary(stagedPlan.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return ZStack(alignment: .topLeading) {
            screenShape.fill(Color(red: 0.05, green: 0.06, blue: 0.08))           // opaque "screen" — no see-through
                .overlay(screenShape.fill(LinearGradient(colors: [.white.opacity(0.06), .clear],
                                                         startPoint: .top, endPoint: .bottom)))
            // The projected future screen: every window where it *will* be after commit.
            ForEach(currentLayout.filter { $0.id != wid }) { m in
                if let s = stagedById[m.id] {
                    zoneRect(s.frac, s.tint, s.image, screen, .staged)     // a staged move — bright, at its new spot
                } else {
                    zoneRect(m.frac, m.tint, nil, screen, .baseline)       // unchanged — a faint footprint
                }
            }
            placementGrid(wid: wid, stage: screen, tint: target?.tint ?? Palette.running)
            placementGhost(target: target, stage: screen)                  // the window being placed
        }
        .frame(width: screen.width, height: screen.height)
        .clipShape(screenShape)
        .overlay(screenShape.strokeBorder(.white.opacity(0.16), lineWidth: 1))
        .padding(.horizontal, bezel).padding(.top, bezel).padding(.bottom, bezel + 10)   // bezel + chin
        .background(
            RoundedRectangle(cornerRadius: bezel + 8, style: .continuous)
                .fill(Color(white: 0.07))
                .overlay(RoundedRectangle(cornerRadius: bezel + 8, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.6), radius: 40, y: 18)
        )
        .overlay(alignment: .bottom) {                                     // a little brand dot on the chin
            Circle().fill(.white.opacity(0.22)).frame(width: 5, height: 5).padding(.bottom, 6)
        }
    }

    // The clickable grid laid over the stage at the active resolution. Hover lights a cell;
    // click stages that position for the window and closes the stage.
    private func placementGrid(wid: UInt32, stage: CGSize, tint: Color) -> some View {
        let (cols, rows) = drag.baseRes.dims
        let cw = stage.width / CGFloat(cols)
        let ch = stage.height / CGFloat(rows)
        return ZStack(alignment: .topLeading) {
            ForEach(0..<rows, id: \.self) { r in
                ForEach(0..<cols, id: \.self) { c in
                    let cell = HoverCell(col: c, row: r)
                    let lit = drag.placeCell == cell
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(lit ? tint.opacity(0.18) : Color.white.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(lit ? tint : .white.opacity(0.22), lineWidth: lit ? 2.5 : 1))
                        .frame(width: cw - 6, height: ch - 6)
                        .contentShape(Rectangle())
                        .onHover { if $0 { drag.placeCell = cell } }
                        .onTapGesture { commitPlacement(wid: wid, col: c, row: r) }
                        .position(x: CGFloat(c) * cw + cw / 2, y: CGFloat(r) * ch + ch / 2)
                }
            }
        }
        .frame(width: stage.width, height: stage.height)
    }

    // The window being placed. While hovering a section the preview snaps to it, *exactly*
    // section-sized (never bigger than the spot). At rest it's just a quiet dashed outline at the
    // window's current/projected spot — so you see which window you're moving and where it is now.
    @ViewBuilder
    private func placementGhost(target: ExposeView.LayerMember?, stage: CGSize) -> some View {
        let tint = target?.tint ?? Palette.running
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        if let cell = drag.placeCell {
            let (cols, rows) = drag.baseRes.dims
            let frac = CGRect(x: CGFloat(cell.col) / CGFloat(cols), y: CGFloat(cell.row) / CGFloat(rows),
                              width: 1 / CGFloat(cols), height: 1 / CGFloat(rows))
            let r = CGRect(x: frac.minX * stage.width, y: frac.minY * stage.height,
                           width: frac.width * stage.width, height: frac.height * stage.height)
            ZStack {
                shape.fill(tint.opacity(0.26))
                if let img = target?.image {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill).opacity(0.45)
                }
            }
            .frame(width: max(8, r.width - 8), height: max(8, r.height - 8))
            .clipShape(shape)
            .overlay(shape.strokeBorder(tint, lineWidth: 3))
            .shadow(color: tint.opacity(0.5), radius: 14)
            .position(x: r.midX, y: r.midY)
            .allowsHitTesting(false)
        } else {
            let restFrac: CGRect? = {
                if let wid = drag.placeWid, let s = stagedPlan.first(where: { $0.id == wid }) { return s.frac }
                return target?.frac
            }()
            if let f = restFrac {
                let r = CGRect(x: f.minX * stage.width, y: f.minY * stage.height,
                               width: f.width * stage.width, height: f.height * stage.height)
                shape.fill(tint.opacity(0.10))
                    .overlay(shape.strokeBorder(tint.opacity(0.75), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                    .frame(width: max(8, r.width - 6), height: max(8, r.height - 6))
                    .position(x: r.midX, y: r.midY)
                    .allowsHitTesting(false)
            }
        }
    }

    private func placementCaption(wid: UInt32) -> some View {
        let t = clusters.flatMap(\.tiles).first { $0.id == wid }
        return HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "hand.point.up.left.fill")
                    .font(.system(size: 10, weight: .semibold)).foregroundColor(Palette.running)
                Text("Place \(t?.app ?? "window")").font(Typo.monoBold(11)).foregroundColor(.white)
                if let title = t?.title, !title.isEmpty {
                    Text(title).font(Typo.mono(9)).foregroundColor(Palette.textMuted).lineLimit(1)
                }
            }
            Rectangle().fill(Palette.border).frame(width: 0.5, height: 14)
            placeResSelector
            Rectangle().fill(Palette.border).frame(width: 0.5, height: 14)
            Text("click a section · esc cancel").font(Typo.mono(9)).foregroundColor(.white.opacity(0.4))
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Capsule().fill(Color.black.opacity(0.6))
            .overlay(Capsule().strokeBorder(Palette.running.opacity(0.4), lineWidth: 0.5)))
    }

    @ViewBuilder
    private var placeResSelector: some View {
        ForEach(LatticeRes.allCases, id: \.rawValue) { r in
            let active = drag.baseRes == r
            Button { drag.baseRes = r; drag.placeCell = nil } label: {
                resIcon(r, active: active)
                    .padding(.horizontal, 5).frame(height: 20)
                    .background(RoundedRectangle(cornerRadius: 5).fill(active ? Palette.running : Color.white.opacity(0.07)))
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(active ? Palette.running : Palette.border, lineWidth: active ? 1 : 0.5))
            }
            .buttonStyle(.plain)
            .help(r.name)
        }
    }

    private func commitPlacement(wid: UInt32, col: Int, row: Int) {
        let (cols, rows) = drag.baseRes.dims
        let spec = GridPlacement(columns: cols, rows: rows, column: col, row: row).map(PlacementSpec.grid)
        drag.endPlacing()
        onDrop(wid, spec)
    }

    private func displayBadge(_ scope: DisplayScope) -> some View {
        HStack(spacing: 8) {
            Image(systemName: scope.index == 0 ? "display" : "rectangle.on.rectangle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Palette.running)

            VStack(alignment: .leading, spacing: 1) {
                Text(scope.label)
                    .font(Typo.monoBold(10))
                    .foregroundColor(Palette.text)
                Text("\(scope.windowCount) \(scope.windowCount == 1 ? "window" : "windows")")
                    .font(Typo.caption(8.5))
                    .foregroundColor(Palette.textMuted)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.58))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.running.opacity(0.55), lineWidth: 0.5))
        )
    }

    // Mouse-driven leave: the keyboard has Enter (commit) / Esc (discard), but there was no
    // way out with the trackpad. This ✕ just *closes* the survey, keeping whatever's on screen
    // (Esc remains the explicit discard/revert). Top-right, above the gear.
    private var exitButton: some View {
        Button { onExit() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.black.opacity(0.5))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Palette.border, lineWidth: 0.5))
                )
        }
        .buttonStyle(.plain)
        .help("Exit Hyperspace")
    }

    // The gear that reveals the control rig. Small by default so the intent band
    // and the upper third of the survey stay visible.
    private var settingsToggle: some View {
        Button { dialsOpen.toggle() } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(dialsOpen ? Palette.bg : .white.opacity(0.7))
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(dialsOpen ? Palette.running : Color.black.opacity(0.5))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Palette.border, lineWidth: 0.5))
                )
        }
        .buttonStyle(.plain)
        .help("Visual settings")
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
            zoomRow
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

    // Canvas zoom — driven by ⌘-scroll / =/− (not a slider), so this is a live readout
    // plus a "fit" pill that snaps back to 1×. Separate axis from the size dial above:
    // size lays tiles bigger/smaller; zoom magnifies the whole spread to lean into a region.
    private var zoomRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10)).foregroundColor(.white.opacity(0.6)).frame(width: 14)
            Text("zoom").font(Typo.mono(9)).foregroundColor(.white.opacity(0.45)).frame(width: 28, alignment: .leading)
            Text("⌘scroll").font(Typo.mono(9)).foregroundColor(.white.opacity(0.3))
            Spacer(minLength: 0)
            pill("fit", canvas.zoom <= 1.0001) { canvas.reset() }
            Text(String(format: "%.1f×", canvas.zoom))
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

    // MARK: - Intent band (drag targets)
    //
    // The top third: three sections you drag a window thumbnail up into. Layers and
    // Spaces are scaffolded for Phase 2/3; Lattice is live — drop a tile on a cell to
    // stage a location (nothing real moves until gather). See
    // design/hyperspace-drag-drop.md.

    private var intentBand: some View {
        // Two slots: Layers (pick/tag) · Grid (drop a position). No preview canvas — the survey
        // *is* the preview: a staged move badges its tile, and hovering a layer lights its windows
        // in place. Centred. design/hyperspace-drag-drop.md
        HStack(alignment: .top, spacing: 14) {
            layersSection.frame(width: layersWidth)
            gridSection.frame(width: gridWidth)
        }
        .frame(maxWidth: .infinity)        // centre the cluster (not full-bleed)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // The Layers list hugs its pile count; Grid is a fixed, comfortable drop target.
    private var layersWidth: CGFloat {
        let pileSlot: CGFloat = 90
        return min(max(CGFloat(min(max(layers.count, 1), 3)) * pileSlot + 24, 220), 340)
    }
    private var gridWidth: CGFloat { 320 }

    // A not-yet-live section — visible so the three-axis model reads, dimmed so it's
    // clearly inert. Replaced by real piles / a Spaces strip in later phases.
    private func stubSection(_ title: String, _ icon: String, _ sub: String, _ phase: String) -> some View {
        sectionCard(title: title, icon: icon, sub: sub, live: false) {
            VStack(spacing: 6) {
                Spacer(minLength: 0)
                Text(phase)
                    .font(Typo.monoBold(10)).foregroundColor(.white.opacity(0.35))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.05)))
                    .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 0.5))
                Text("soon").font(Typo.mono(8)).foregroundColor(.white.opacity(0.25))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 220)
        .opacity(0.6)
    }

    // The Layers section (Phase 2): rule-backed layers as drop "piles" — drag a window
    // onto a pile to stage a join (multi-membership; drop again to un-stage), or onto
    // the ＋ pile to stage a brand-new layer seeded from it. Drops only *stage* (badge
    // the tile); StudioLayerStore is written on gather. design/hyperspace-drag-drop.md
    private var layersSection: some View {
        sectionCard(title: "Layers", icon: "square.stack.3d.up", sub: "tag · piles",
                    live: true, armed: dragOnThisScreen && drag.hoverLayer != nil) {
            VStack(alignment: .leading, spacing: 8) {
                controlRow {                                   // mirrors the Lattice selector slot
                    Text("\(max(0, layers.count - 1)) \(layers.count - 1 == 1 ? "layer" : "layers")")
                        .font(Typo.mono(9)).foregroundColor(.white.opacity(0.55))
                    Spacer(minLength: 6)
                    Text("hover → preview · drop to tag")
                        .font(Typo.mono(8.5)).foregroundColor(.white.opacity(0.35))
                }
                FlowLayout(spacing: 10, lineSpacing: 10, alignment: .leading) {
                    ForEach(layers) { layerPileView($0) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .onPreferenceChange(LayerFrameKey.self) { drag.layerFrames[screenID] = $0 }
            }
        }
    }

    // Shared 26pt control-row slot so Layers and Lattice line up under their headers.
    private func controlRow<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 5) { content() }
            .frame(height: 26)
    }

    /// True while a drag started on (and belongs to) this screen.
    private var dragOnThisScreen: Bool { drag.isActive && drag.screenID == screenID }

    // One layer pile — a compact *screen-map* of the layer's windows on this display, so
    // you read what the layer looks like at a glance (design/hyperspace-drag-drop.md). The
    // full-size formation renders in the middle Preview on hover / drop. Lights as a drop
    // target and stays tinted while it holds a staged join. ＋ = a new-layer drop slot.
    private func layerPileView(_ pile: LayerPile) -> some View {
        let lit = dragOnThisScreen && drag.hoverLayer == pile.id
        let on = lit || pile.staged
        let mapW: CGFloat = 104
        let mapH = layerMapHeight(for: mapW)
        return VStack(spacing: 4) {
            Group {
                if pile.isNew {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(on ? Palette.running.opacity(0.9) : Color.white.opacity(0.05))
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(on ? Palette.bg : .white.opacity(0.6))
                    }
                    .frame(width: mapW, height: mapH)
                } else {
                    layerMap(pile, width: mapW)            // the screen, with its windows
                }
            }
            .overlay(                                       // the "monitor" bezel
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(on ? Palette.running : Palette.border, lineWidth: on ? 1.5 : 0.5)
            )
            .overlay(alignment: .topTrailing) {
                if !pile.isNew && pile.count > 0 {
                    Text("\(pile.count)")
                        .font(Typo.monoBold(8)).foregroundColor(.white)
                        .padding(.horizontal, 3).padding(.vertical, 0.5)
                        .background(Capsule().fill(Color.black.opacity(0.6)))
                        .padding(2)
                }
            }
            .overlay(alignment: .topLeading) {       // evidence: how many windows staged to join
                if pile.stagedCount > 0 {
                    Text("＋\(pile.stagedCount)")
                        .font(Typo.monoBold(8)).foregroundColor(Palette.bg)
                        .padding(.horizontal, 3).padding(.vertical, 0.5)
                        .background(Capsule().fill(Palette.running))
                        .padding(2)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            Text(pile.isNew ? "new" : pile.name)
                .font(Typo.mono(9)).foregroundColor(.white.opacity(on ? 0.9 : 0.65))
                .lineLimit(1).frame(maxWidth: mapW)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: pile.stagedCount)
        .scaleEffect(lit ? 1.06 : 1)
        .shadow(color: lit ? Palette.running.opacity(0.5) : .clear, radius: lit ? 8 : 0)
        .animation(.spring(response: 0.24, dampingFraction: 0.72), value: lit)
        .background(layerFrameReporter(pile.id))     // hit-test = the compact footprint
        .onHover { hovering in
            if hovering { drag.inspectLayer = pile.id; drag.inspectScreen = screenID }
            else if drag.inspectLayer == pile.id { drag.inspectLayer = nil; drag.inspectScreen = nil }
        }
        .onTapGesture { if pile.isNew { onNewLayer() } }   // ＋ → author a new layer (name it, pick apps)
    }

    // Map height for a given width — the active screen's aspect, clamped so a very wide
    // or very tall display still reads as a tidy tile.
    private func layerMapHeight(for width: CGFloat) -> CGFloat {
        (width / min(max(screenAspect, 1.2), 2.6)).rounded()
    }

    // A layer's screen-map: its member windows drawn as app-tinted rects at their real
    // (screen-relative) positions — the "what does this layer look like" preview. `big`
    // (the expanded map) fills rects with the live thumbnail.
    private func layerMap(_ pile: LayerPile, width: CGFloat) -> some View {
        let h = layerMapHeight(for: width)
        let big = width > 160
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: big ? 8 : 7, style: .continuous)
                .fill(Color.black.opacity(0.38))
            if pile.members.isEmpty {
                Image(systemName: "rectangle.dashed")
                    .font(.system(size: width * 0.14))
                    .foregroundColor(.white.opacity(0.22))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(pile.members) { m in
                    let r = CGRect(x: m.frac.minX * width, y: m.frac.minY * h,
                                   width: max(big ? 6 : 3, m.frac.width * width),
                                   height: max(big ? 5 : 3, m.frac.height * h))
                    layerMemberRect(m, big: big)
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)
                }
            }
        }
        .frame(width: width, height: h)
        .clipShape(RoundedRectangle(cornerRadius: big ? 8 : 7, style: .continuous))
    }

    private func layerMemberRect(_ m: LayerMember, big: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: big ? 3 : 1.5, style: .continuous)
        return shape
            .fill(m.tint.opacity(0.5))
            .overlay {
                if big, let img = m.image {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                        .clipShape(shape).opacity(0.6)
                }
            }
            .overlay(shape.strokeBorder(m.tint, lineWidth: big ? 1 : 0.5))
    }

    // Reports a pile's frame (root space) keyed by its id so a drop can hit-test it.
    private func layerFrameReporter(_ key: String) -> some View {
        GeometryReader { g in
            Color.clear.preference(key: LayerFrameKey.self,
                                   value: [key: g.frame(in: .named(ExposeView.rootSpace))])
        }
    }

    // Which pile's roster to reveal on this screen: the drop target while dragging,
    // else a plain mouse-hovered pile. The ＋ pile has no roster.
    private var rosterPileID: String? {
        // Settle, don't chase the cursor: no live layer/placement preview while a drag is in
        // flight — the preview only updates once something *lands* (a drop stages the plan).
        if drag.isActive { return nil }
        guard drag.inspectScreen == screenID, let i = drag.inspectLayer, i != HyperspaceDrag.newLayerKey else { return nil }
        return i
    }

    // The window IDs of the layer being previewed (idle hover of a pile). Drives the
    // bottom survey's dim/highlight: everything fades except this layer's windows.
    private var highlightWids: Set<UInt32>? {
        guard let id = rosterPileID, let p = layers.first(where: { $0.id == id }) else { return nil }
        return Set(p.members.map(\.id))
    }

    // The Grid section (right): a resolution selector above a grid of drop positions.
    // Dropping a window on a cell stages that position; the result renders in the middle
    // Preview, so the grid here is purely the input (cells just light under the cursor).
    private var gridSection: some View {
        sectionCard(title: "Grid", icon: "rectangle.split.2x2", sub: "drop a position",
                    live: true, armed: dragOnThisScreen && drag.hoverCell != nil) {
            VStack(spacing: 8) {
                controlRow { resSelector }
                latticeGrid
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // The placement-resolution picker. Each option is a *real mini-grid* of its own
    // dims (2×1, 3×1, 2×2, 4×4) — far clearer than the old ½⅓¼▦ glyphs, where ▦ read as
    // "fullscreen". Modifiers override it live mid-drag (⇧ halves · ⌥ thirds · ⌘ fine);
    // releasing returns to the selection. A name readout sits at the trailing edge.
    @ViewBuilder
    private var resSelector: some View {
        ForEach(LatticeRes.allCases, id: \.rawValue) { r in
            let active = drag.res == r
            Button {
                drag.baseRes = r
                if !drag.isActive || Self.modifierRes() == nil { drag.res = r }
            } label: {
                resIcon(r, active: active)
                    .padding(.horizontal, 7).frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(active ? Palette.running : Color.white.opacity(0.07)))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(active ? Palette.running : Palette.border, lineWidth: active ? 1 : 0.5))
            }
            .buttonStyle(.plain)
            .help(r.name)
        }
        Spacer(minLength: 6)
        // Mode readout: the active resolution by name, with the held-modifier glyph when
        // one is overriding the selector — so "⌘ fine" reads at a glance.
        if let g = resOverrideGlyph {
            Text(g).font(Typo.monoBold(9)).foregroundColor(Palette.running)
        }
        Text(drag.res.name)
            .font(Typo.mono(9))
            .foregroundColor(resOverrideGlyph != nil ? Palette.running : .white.opacity(0.5))
            .animation(.easeOut(duration: 0.12), value: drag.res)
    }

    // A tiny true-to-life grid icon for a resolution: cols×rows cells in a screen-ish box.
    private func resIcon(_ r: LatticeRes, active: Bool) -> some View {
        let (cols, rows) = r.dims
        let bw: CGFloat = 22, bh: CGFloat = 15, gap: CGFloat = 1.5
        let cw = (bw - gap * CGFloat(cols - 1)) / CGFloat(cols)
        let ch = (bh - gap * CGFloat(rows - 1)) / CGFloat(rows)
        let color = active ? Palette.bg : Color.white.opacity(0.75)
        return VStack(spacing: gap) {
            ForEach(0..<rows, id: \.self) { _ in
                HStack(spacing: gap) {
                    ForEach(0..<cols, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(color).frame(width: cw, height: ch)
                    }
                }
            }
        }
        .frame(width: bw, height: bh)
    }

    /// The glyph of the modifier currently overriding the resolution (mid-drag), or nil.
    private var resOverrideGlyph: String? {
        guard drag.isActive else { return nil }
        switch Self.modifierRes() {
        case .fine:    return "⌘"
        case .thirds:  return "⌥"
        case .halves:  return "⇧"
        default:       return nil
        }
    }

    // The drop grid: cols×rows cells laid out at the screen's aspect ratio, centered
    // in the available space. Reports its frame (root space) for hit-testing; the cell
    // under the cursor lights while dragging.
    private var latticeGrid: some View {
        let (cols, rows) = drag.res.dims
        return GeometryReader { geo in
            let box = aspectFit(in: geo.size, aspect: screenAspect)
            let cw = box.width / CGFloat(cols)
            let ch = box.height / CGFloat(rows)
            let active = drag.isActive && drag.screenID == screenID
            VStack(spacing: 3) {
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: 3) {
                        ForEach(0..<cols, id: \.self) { c in
                            gridCell(lit: active && drag.hoverCell == HoverCell(col: c, row: r),
                                     w: max(8, cw - 3), h: max(8, ch - 3))
                        }
                    }
                }
            }
            // Glide the highlight between cells instead of snapping.
            .animation(.spring(response: 0.24, dampingFraction: 0.72), value: drag.hoverCell)
            .frame(width: box.width, height: box.height)
            .background(                                          // measure the fixed grid box…
                GeometryReader { g in
                    Color.clear.preference(key: LatticeFrameKey.self,
                                           value: g.frame(in: .named(ExposeView.rootSpace)))
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)   // …then center it in the section
        }
        .onPreferenceChange(LatticeFrameKey.self) { drag.latticeFrames[screenID] = $0 }
    }

    // One drop-grid cell — a plain target that lights under the cursor. The actual
    // placement preview now renders in the middle Preview canvas, not in the cell.
    private func gridCell(lit: Bool, w: CGFloat, h: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        return shape
            .fill(lit ? Palette.running.opacity(0.32) : Color.white.opacity(0.05))
            .overlay(shape.strokeBorder(lit ? Palette.running : Palette.border, lineWidth: lit ? 1.5 : 0.5))
            .frame(width: w, height: h)
            .scaleEffect(lit ? 1.07 : 1)
            .shadow(color: lit ? Palette.running.opacity(0.55) : .clear, radius: lit ? 9 : 0)
            .zIndex(lit ? 1 : 0)
    }

    // MARK: - Preview — a dedicated slot that always shows the screen's zones
    //
    // The middle band slot. Never empty: by default it renders the *current* layout of this
    // display (so it's always useful), with staged moves and a hovered layer drawn on top.
    // Display-only — drops still land on the Layers/Grid controls.

    private enum ZoneStyle { case baseline, staged, live }

    // A window zone on the placement stage. `baseline` = a faint "currently here" footprint;
    // `staged` = a bright planned move; `live` = the spot you're about to pick.
    private func zoneRect(_ frac: CGRect, _ tint: Color, _ image: NSImage?, _ box: CGSize, _ style: ZoneStyle) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        let r = CGRect(x: frac.minX * box.width, y: frac.minY * box.height,
                       width: max(8, frac.width * box.width), height: max(7, frac.height * box.height))
        let fillOpacity: Double = style == .baseline ? 0.14 : (style == .live ? 0.34 : 0.42)
        let imageOpacity: Double = style == .baseline ? 0.28 : 0.6
        let strokeColor: Color = style == .baseline ? .white.opacity(0.18) : tint
        let strokeW: CGFloat = style == .live ? 2 : (style == .baseline ? 0.75 : 1)
        // Clip the *framed container*, not the image: with aspectRatio(.fill) the image scales up to
        // cover (width-led), so clipping it directly lets its height overflow the zone. Framing the
        // ZStack then clipping confines it to the zone in both dimensions.
        return ZStack {
            shape.fill(tint.opacity(fillOpacity))
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).opacity(imageOpacity)
            }
        }
        .frame(width: r.width - 2, height: r.height - 2)
        .clipShape(shape)
        .overlay(shape.strokeBorder(strokeColor, lineWidth: strokeW))
        .position(x: r.midX, y: r.midY)
    }

    // Fit a rect of the given aspect (w/h) inside `size`, leaving a little air.
    private func aspectFit(in size: CGSize, aspect: CGFloat) -> CGSize {
        let avail = CGSize(width: max(1, size.width - 4), height: max(1, size.height - 4))
        var w = avail.width
        var h = w / max(0.1, aspect)
        if h > avail.height { h = avail.height; w = h * aspect }
        return CGSize(width: w, height: h)
    }

    // Shared chrome for a band section: a titled card. `live` tints it on-brand;
    // `armed` lights it up while the cursor is over it mid-drag, so you can see which
    // axis (location vs layer) you're about to commit.
    private func sectionCard<Content: View>(title: String, icon: String, sub: String,
                                            live: Bool, armed: Bool = false,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(live ? Palette.running : .white.opacity(0.5))
                Text(title)
                    .font(Typo.monoBold(11)).foregroundColor(.white).tracking(0.3)
                Text(sub)
                    .font(Typo.mono(8.5)).foregroundColor(armed ? Palette.running : Palette.textMuted)
                Spacer(minLength: 0)
            }
            content()
        }
        .padding(.horizontal, 12).padding(.top, 9).padding(.bottom, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(armed ? Palette.running.opacity(0.14) : (live ? Palette.running.opacity(0.05) : Color.white.opacity(0.02)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(armed ? Palette.running.opacity(0.75) : (live ? Palette.running.opacity(0.30) : Palette.border),
                              lineWidth: armed ? 1.5 : 1)
        )
        .shadow(color: armed ? Palette.running.opacity(0.35) : .clear, radius: armed ? 12 : 0)
        .animation(.easeOut(duration: 0.16), value: armed)
    }

    // The dragged thumbnail, following the cursor on the owning screen only. Over a
    // live drop target (a grid cell or a layer pile) it shrinks — a clear "about to
    // land here" tell that also previews how small the window reads in the target.
    @ViewBuilder
    private var ghostOverlay: some View {
        if drag.isActive, drag.screenID == screenID, let img = drag.image {
            let armed = drag.hoverCell != nil || drag.hoverLayer != nil
            Image(nsImage: img)
                .resizable().aspectRatio(contentMode: .fill)
                .frame(width: drag.tileSize.width, height: drag.tileSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.running, lineWidth: armed ? 2.5 : 2))
                .shadow(color: .black.opacity(armed ? 0.6 : 0.5), radius: armed ? 10 : 16, x: 0, y: armed ? 4 : 8)
                .scaleEffect(armed ? 0.6 : 1, anchor: .center)
                .opacity(armed ? 1 : 0.9)
                .animation(.spring(response: 0.22, dampingFraction: 0.72), value: armed)
                .position(drag.location)
                .allowsHitTesting(false)
        }
    }

    // The "landed" ring at the last drop target — fires the instant you release, so a
    // drop reads as confirmed even after the hover highlight has cleared.
    @ViewBuilder
    private var dropPulseOverlay: some View {
        if let p = drag.dropPulse, drag.screenID == screenID {
            DropPulseRing(frame: p.frame, tint: Palette.running)
                .id(p.id)
        }
    }

    // MARK: - Drag handling

    /// Modifier-driven resolution while a drag is held — overrides the selector.
    private static func modifierRes() -> LatticeRes? {
        let f = NSEvent.modifierFlags
        if f.contains(.command) { return .fine }
        if f.contains(.option)  { return .thirds }
        if f.contains(.shift)   { return .halves }
        return nil
    }

    private func handleDragChange(_ t: Tile, _ v: DragGesture.Value) {
        drag.location = v.location
        let dist = hypot(v.translation.width, v.translation.height)
        if drag.wid == nil {
            guard dist >= 8 else { return }       // below threshold → still a potential tap
            drag.wid = t.id
            drag.image = t.image
            drag.screenID = screenID
            drag.tileSize = CGSize(width: tile, height: (tile * 0.62).rounded())
        }
        drag.res = Self.modifierRes() ?? drag.baseRes
        updateHoverCell()
        updateHoverLayer()
    }

    private func handleDragEnd(_ t: Tile, _ v: DragGesture.Value) {
        let dist = hypot(v.translation.width, v.translation.height)
        let wasDragging = drag.wid != nil
        // Resolve the drop target before reset() clears the hover state. The Lattice
        // grid wins if the cursor is over it; otherwise a layer pile; else a miss.
        var spec: PlacementSpec?
        var pulseFrame: CGRect?                   // where to flash the "landed" ring
        if wasDragging,
           let frame = drag.latticeFrames[screenID], frame.contains(v.location),
           let cell = drag.hoverCell {
            let (cols, rows) = drag.res.dims
            spec = GridPlacement(columns: cols, rows: rows, column: cell.col, row: cell.row).map(PlacementSpec.grid)
            let cw = frame.width / CGFloat(cols), ch = frame.height / CGFloat(rows)
            pulseFrame = CGRect(x: frame.minX + CGFloat(cell.col) * cw,
                                y: frame.minY + CGFloat(cell.row) * ch, width: cw, height: ch)
        }
        let layerKey = (wasDragging && spec == nil) ? drag.hoverLayer : nil
        if let layerKey { pulseFrame = drag.layerFrames[screenID]?[layerKey] }
        let wid = t.id
        drag.reset()                              // clear FIRST so the panel rebuild isn't suppressed
        if !wasDragging && dist < 8 {
            onPick(wid)                           // a tap → pluck
        } else if let layerKey {
            onDropLayer(wid, layerKey)            // a drag onto a layer pile → stage join / new layer
            if let pulseFrame { drag.firePulse(at: pulseFrame) }
        } else {
            onDrop(wid, spec)                     // a drag → stage location (or nil = missed, just rebuild)
            if spec != nil, let pulseFrame { drag.firePulse(at: pulseFrame) }
        }
    }

    private func updateHoverLayer() {
        let frames = drag.layerFrames[screenID] ?? [:]
        let hit = frames.first { $0.value.width > 1 && $0.value.contains(drag.location) }?.key
        if drag.hoverLayer != hit { drag.hoverLayer = hit }
    }

    private func updateHoverCell() {
        guard let frame = drag.latticeFrames[screenID], frame.width > 1, frame.contains(drag.location) else {
            if drag.hoverCell != nil { drag.hoverCell = nil }
            return
        }
        let (cols, rows) = drag.res.dims
        let cw = frame.width / CGFloat(cols)
        let ch = frame.height / CGFloat(rows)
        let c = min(cols - 1, max(0, Int((drag.location.x - frame.minX) / cw)))
        let r = min(rows - 1, max(0, Int((drag.location.y - frame.minY) / ch)))
        let cell = HoverCell(col: c, row: r)
        if drag.hoverCell != cell { drag.hoverCell = cell }
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

    // The right-click menu for a window: quick tile presets (stage immediately), a visual
    // "Place…" that opens the life-size stage, layer joins, and pluck. Options, not actions —
    // nothing real moves until ⏎/G, same as the rest of Hyperspace.
    @ViewBuilder
    private func tileMenu(_ t: Tile) -> some View {
        Button { drag.beginPlacing(t.id, on: screenID) } label: {
            Label("Place…", systemImage: "rectangle.dashed")
        }
        Divider()
        Button("Left Half")   { stagePlacement(t.id, GridPlacement(columns: 2, rows: 1, column: 0, row: 0)) }
        Button("Right Half")  { stagePlacement(t.id, GridPlacement(columns: 2, rows: 1, column: 1, row: 0)) }
        Button("Top Half")    { stagePlacement(t.id, GridPlacement(columns: 1, rows: 2, column: 0, row: 0)) }
        Button("Bottom Half") { stagePlacement(t.id, GridPlacement(columns: 1, rows: 2, column: 0, row: 1)) }
        Menu("Quarter") {
            Button("Top Left")     { stagePlacement(t.id, GridPlacement(columns: 2, rows: 2, column: 0, row: 0)) }
            Button("Top Right")    { stagePlacement(t.id, GridPlacement(columns: 2, rows: 2, column: 1, row: 0)) }
            Button("Bottom Left")  { stagePlacement(t.id, GridPlacement(columns: 2, rows: 2, column: 0, row: 1)) }
            Button("Bottom Right") { stagePlacement(t.id, GridPlacement(columns: 2, rows: 2, column: 1, row: 1)) }
        }
        Button("Maximize") { stagePlacement(t.id, GridPlacement(columns: 1, rows: 1, column: 0, row: 0)) }
        let joinable = layers.filter { !$0.isNew }
        if !joinable.isEmpty {
            Divider()
            Menu("Add to Layer") {
                ForEach(joinable) { p in
                    Button(p.name) { onDropLayer(t.id, p.id) }
                }
            }
        }
        Divider()
        Button(t.pickSlot != nil ? "Remove from group" : "Add to group") { onPick(t.id) }
    }

    private func stagePlacement(_ wid: UInt32, _ gp: GridPlacement?) {
        onDrop(wid, gp.map(PlacementSpec.grid))
    }

    private func tileView(_ t: Tile) -> some View {
        let w = tile
        let h = (tile * 0.62).rounded()
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let picked = t.pickSlot != nil
        let staged = t.staged != nil || !t.layerTags.isEmpty
        let beingDragged = drag.wid == t.id && drag.screenID == screenID
        // Layer preview: when a pile is hovered, this layer's windows pop and the rest fade.
        let inLayer = highlightWids?.contains(t.id)
        let layerLit = inLayer == true
        let layerDimmed = inLayer == false
        let lit = t.isAimed || picked                          // on the spotlight's stage
        let strokeColor: Color = staged ? Palette.running
            : (picked ? t.tint : (t.isAimed ? Color.white.opacity(0.9) : Color.white.opacity(0.1)))
        let strokeW: CGFloat = staged ? 2 : (picked ? 2 : (t.isAimed ? 1.5 : 0.75))
        let veil: Double = lit ? 0 : spotlight * 0.5
        let bloom: Color = t.isAimed ? lightColor.opacity(0.7 * spotlight) : .clear
        let bloomR: CGFloat = t.isAimed ? 8 + spotlight * 22 : 0
        return tileBody(t, w: w, h: h, shape: shape)
            .overlay(shape.fill(Color.black.opacity(veil)))    // spotlight: off-stage tiles sink to shadow
            .overlay(shape.strokeBorder(strokeColor, lineWidth: strokeW))
            .overlay(alignment: .topTrailing) { hintChip(t) }
            .overlay(alignment: .topLeading) { if let s = t.pickSlot { slotBadge(s, t.tint) } }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 3) {
                    if !t.layerTags.isEmpty { layerTagRow(t.layerTags) }
                    titleLabel(t)
                }
                .padding(5)
            }
            .overlay(alignment: .bottomTrailing) {
                if let s = t.staged {
                    stagedBadge(s).transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.62), value: t.staged)        // location badge pops
            .animation(.spring(response: 0.3, dampingFraction: 0.62), value: t.layerTags)      // layer labels pop
            // While previewing a layer, this tile's windows ring on-brand and the rest sink.
            .overlay {
                if layerLit { shape.strokeBorder(Palette.running, lineWidth: 2) }
            }
            // While this tile is the one being dragged, hollow it out so it keeps its
            // slot (no reflow) but reads as "lifted" — the ghost is what moves.
            .opacity(beingDragged ? 0.22 : (layerDimmed ? 0.26 : 1))
            .overlay {
                if beingDragged {
                    shape.strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .foregroundColor(Palette.running.opacity(0.8))
                }
            }
            .background(frameReporter(t.id))
            .shadow(color: .black.opacity(picked ? 0.5 : 0.35), radius: picked ? 14 : 8, x: 0, y: 5)
            .shadow(color: layerLit ? Palette.running.opacity(0.55) : bloom, radius: layerLit ? 14 : bloomR)  // layer-lit / aimed tile glows
            .contentShape(Rectangle())
            // Right-click → a menu of options (not a surprise action). Quick tile presets stage
            // immediately; "Place…" opens the life-size stage for a visual pick.
            .contextMenu { tileMenu(t) }
            // One gesture does both: a near-zero move is a tap (pluck); a real drag
            // lifts a ghost and stages a location on drop.
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(ExposeView.rootSpace))
                    .onChanged { handleDragChange(t, $0) }
                    .onEnded { handleDragEnd(t, $0) }
            )
    }

    private func stagedBadge(_ text: String) -> some View {
        Text(text)
            .font(Typo.monoBold(9))
            .foregroundColor(Palette.bg)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill(Palette.running))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5))
            .padding(5)
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

    // The window title — inset is provided by the enclosing bottom-leading VStack
    // (which also carries any layer labels), so no outer padding here.
    private func titleLabel(_ t: Tile) -> some View {
        Text(t.title)
            .font(Typo.mono(8))
            .foregroundColor(.white.opacity(0.85))
            .lineLimit(1)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill(Color.black.opacity(0.5)))
    }

    // Staged layer memberships as small on-brand pills along the tile's bottom — a
    // label, since layer membership is non-exclusive and never moves the window.
    private func layerTagRow(_ tags: [String]) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(tags.prefix(3).enumerated()), id: \.offset) { _, tag in
                Text(tag)
                    .font(Typo.monoBold(8))
                    .foregroundColor(Palette.bg)
                    .lineLimit(1)
                    .padding(.horizontal, 4).padding(.vertical, 1.5)
                    .background(Capsule().fill(Palette.running))
            }
            if tags.count > 3 {
                Text("+\(tags.count - 3)")
                    .font(Typo.monoBold(8)).foregroundColor(Palette.running)
            }
        }
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
    var vAlign: VerticalAlignment = .center         // block placement within the bounds

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
        var y: CGFloat
        if vAlign == .top {
            y = bounds.minY
        } else if vAlign == .bottom {
            y = bounds.maxY - totalH
        } else {
            y = bounds.minY + max(0, (bounds.height - totalH) / 2)
        }
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
