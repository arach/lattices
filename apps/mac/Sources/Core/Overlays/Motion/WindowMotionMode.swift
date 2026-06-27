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

    enum Entry { case hyperspace, inPlace }

    private var panel: MotionPanel?
    private var activeEntry: Entry?
    private var lastToggle: CFTimeInterval = 0

    var isActive: Bool { panel != nil }

    func toggleHyperspace() { toggle(entry: .hyperspace) }
    func toggleInPlace() { toggle(entry: .inPlace) }

    private func toggle(entry: Entry) {
        // Debounce machine-gun re-fire. The Hyper trigger rides the Caps Lock
        // transport remap, which can flicker active/inactive and fire the hotkey
        // several times in a few ms — racing activate against deactivate. A human
        // toggle is never this fast, so swallow anything inside the window.
        let now = CACurrentMediaTime()
        if now - lastToggle < 0.18 { return }
        lastToggle = now
        if isActive {
            if activeEntry == entry { deactivate() }
            else { deactivate(); activate(entry: entry) }
        } else {
            activate(entry: entry)
        }
    }

    private func activate(entry: Entry = .hyperspace) {
        guard panel == nil else { return }
        // Defensive: clear any overlay panels orphaned by a prior race before we
        // open a fresh one, so we never stack a new survey on top of a stuck one.
        MotionPanel.teardownStrayPanels()
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
        let inPlace = entry == .inPlace
        let p = MotionPanel(eligible: eligible, inPlace: inPlace)
        p.loadStart = t0
        let tInit = CACurrentMediaTime()
        p.onExit = { [weak self] in self?.deactivate() }
        panel = p
        activeEntry = entry
        p.present()
        let tUp = CACurrentMediaTime()
        let tag = inPlace ? "In-place" : "Hyperspace"
        // Time-to-load profile (the async capture + first-paint marks land later,
        // logged from the panel). Read it back from ~/.lattices/lattices.log.
        DiagnosticLog.shared.info(String(
            format: "%@ load — poll %.1f · build %.1f · init %.1f · present+expose %.1f · on-screen %.1fms (from trigger)",
            tag,
            (tPoll - t0) * 1000, (tEligible - tPoll) * 1000, (tInit - tEligible) * 1000,
            (tUp - tInit) * 1000, (tUp - t0) * 1000))
    }

    func deactivate() {
        panel?.dismiss()
        panel = nil
        activeEntry = nil
        // Belt-and-suspenders: sweep up any Hyperspace overlay panel still on screen
        // even if we lost the reference to it. Guarantees the toggle hotkey always
        // clears the spread — the recovery path for the "stuck on top" trap.
        MotionPanel.teardownStrayPanels()
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

/// Full-screen overlay host. SwiftUI marks empty regions with allowsHitTesting(false)
/// so super.hitTest returns nil and clicks reach the desktop; gesture-backed HUD
/// targets resolve to self and must be kept (the old `self → nil` pass-through broke taps).
/// In-place mode also captures clicks over live window frames (see InPlaceHostingView).
private final class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point)
    }
}

/// Hyper+G overlay: HUD regions stay SwiftUI-tappable; clicks on real desktop windows
/// are captured here (local monitors never see them — they go to the app underneath).
private final class InPlaceHostingView<Content: View>: NSHostingView<Content> {
    weak var panel: MotionPanel?
    var screen: NSScreen?

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let hit = super.hitTest(point) { return hit }
        guard let panel, let screen, panel.inPlaceCapturesDesktopClick(at: point, in: self, on: screen) else { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        if let panel, let screen, panel.inPlaceCapturesDesktopClick(at: local, in: self, on: screen) {
            panel.performInPlaceDesktopSelect(at: local, in: self, on: screen)
            return
        }
        super.mouseDown(with: event)
    }
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
/// modifiers (⇧ halves · ⌥ thirds · ⌘ fine · ⌃ dense) override the selector while held.
enum LatticeRes: Int, CaseIterable {
    case halves, thirds, quarters, fine, dense

    var dims: (cols: Int, rows: Int) {
        switch self {
        case .halves:   return (2, 1)
        case .thirds:   return (3, 1)
        case .quarters: return (2, 2)
        case .fine:     return (4, 4)
        case .dense:    return (8, 8)
        }
    }
    var glyph: String {
        switch self {
        case .halves:   return "½"
        case .thirds:   return "⅓"
        case .quarters: return "¼"
        case .fine:     return "▦"
        case .dense:    return "⊞"
        }
    }
    var name: String {
        switch self {
        case .halves:   return "halves"
        case .thirds:   return "thirds"
        case .quarters: return "quarters"
        case .fine:     return "fine"
        case .dense:    return "dense"
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

/// Balanced cell assignments within a lattice grid, anchored at the drop cell.
/// Short final rows are centered — same logic as `MotionPanel.balancedGrid`.
private func balancedGridCells(count: Int, latticeCols: Int, latticeRows: Int,
                               anchorCol: Int, anchorRow: Int) -> [(col: Int, row: Int)]? {
    guard count > 0 else { return [] }
    let subCols = max(1, Int(ceil(Double(count).squareRoot())))
    let subRows = max(1, Int(ceil(Double(count) / Double(subCols))))
    guard anchorCol + subCols <= latticeCols, anchorRow + subRows <= latticeRows else { return nil }
    return (0..<count).map { i in
        let r = i / subCols, c = i % subCols
        let itemsInRow = min(subCols, count - r * subCols)
        let xOffset = (subCols - itemsInRow) / 2
        return (col: anchorCol + xOffset + c, row: anchorRow + r)
    }
}

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
    @Published var hoverCurrentView = false  // cursor over the Current View screen-map
    @Published var hoverLayoutWid: UInt32?   // outline under the cursor in Current View
    @Published var hoverSurveyWid: UInt32?   // survey tile under the cursor — links to Current View
    @Published var hoverGrid = false         // cursor over the Grid drop zone mid-drag
    @Published var inspectCurrentView = false // plain hover on Current View (no drag)
    var ghostTint: Color?                    // tinted ghost when dragging an outline without a thumb
    @Published var hoverLayer: String?       // layer pile under the cursor (layer id, or newLayerKey)
    @Published var inspectLayer: String?     // pile under a plain mouse hover (no drag) — reveals its roster
    @Published var inspectScreen: String?    // which screen that hovered pile is on
    @Published var selectedLayer: String?    // layer pile clicked open → the inspector modal (layer id)
    @Published var screenID: String = ""     // which screen owns the in-flight drag
    /// Where the in-flight drag started — survey tile vs Current View outline.
    var dragSource: DragSource?
    /// Full selection when dragging a picked window (2+); otherwise just the one window.
    var dragWids: [UInt32] = []

    enum DragSource { case survey, currentView }

    // Right-click "place me" mode: a tile was secondary-clicked, opening a life-size
    // interactive stage to pick its grid spot (mouse-only alternative to drag → Grid).
    @Published var placeWid: UInt32?         // window in placement mode (nil = off)
    @Published var placeScreen: String?      // which screen its stage shows on
    @Published var placeCell: HoverCell?     // cell under the cursor on the stage
    var isPlacing: Bool { placeWid != nil }
    func beginPlacing(_ wid: UInt32, on screen: String) { placeWid = wid; placeScreen = screen; placeCell = nil }
    func endPlacing() { placeWid = nil; placeScreen = nil; placeCell = nil }

    var latticeFrames: [String: CGRect] = [:]              // per-screen lattice grid frame (root space)
    var currentViewFrames: [String: CGRect] = [:]          // per-screen Current View canvas frame (root space)
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
        dragWids = []
        image = nil
        dragSource = nil
        hoverCell = nil
        hoverCurrentView = false
        hoverLayoutWid = nil
        hoverSurveyWid = nil
        hoverGrid = false
        ghostTint = nil
        inspectCurrentView = false
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
    private var fillAimWid: UInt32?                  // last click/Tab aim — F fills this window
    private var group: Set<UInt32> = []             // plucked window ids
    private var resolved: [UInt32: AXUIElement] = [:]
    private var animators: [UInt32: RealWindowAnimator] = [:]
    private var borderLayers: [CALayer] = []
    private var originalFrames: [UInt32: CGRect] = [:]   // for Esc-undo
    private var exposed = false                          // Exposé spread is laid out
    private var dismissed = false                        // torn down — any late async work must no-op

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
    private var layoutRefreshTimer: Timer?   // keep Current View frames live while surveying
    /// In-place tools (Hyper+G): float Current View + inventory over the live desktop.
    /// Hyperspace (Hyper+Space) keeps the full scrim + screenshot survey.
    private let inPlaceMode: Bool
    private var scrollMonitor: Any?
    private var mouseUpMonitor: Any?    // re-claims key focus after a survey click/drag
    private var keyMonitor: Any?        // catches Enter/Esc even when a survey panel holds key
    private var newLayerPanel: NewLayerPanel?   // the "create a new layer" authoring flow, when open
    private var rulePanel: LayerRulePanel?       // the "add/edit layer rule" flow, when open
    private var commandPanel: HyperspaceCommandPanel?   // the `/` command bar, when open

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
    private var clusterSearchQueryByScreen: [String: [Int: String]] = [:]
    private var activeClusterSearchByScreen: [String: Int] = [:]
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

    init(eligible: [WindowEntry], inPlace: Bool = false) {
        self.eligible = eligible
        self.inPlaceMode = inPlace

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
            fillAimWid = eligible[bestIdx].wid
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
            // Hyper+G is a staging session — clicks and window raises must not dismiss it.
            // Leave only via Enter (commit) or Esc (cancel).
            if self.inPlaceMode {
                DiagnosticLog.shared.info("MotionPanel: in-place key resign — reclaiming key")
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.exposed, !self.dismissed else { return }
                    self.makeKey()
                }
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
                guard let self, self.exposed, !self.isKeyWindow, self.commandPanel == nil else { return }
                self.makeKey()
            }
            return event   // don't swallow — the click/drag still needs to process
        }
        // Belt-and-suspenders for the "couldn't hit Enter to confirm" bug: if a survey
        // screen-panel (canBecomeKey == false) or nothing holds key, the MotionPanel's own
        // keyDown never fires. Catch Enter/Esc here and route them so they never fall on the
        // floor. When the MotionPanel *is* key, defer to its keyDown (don't double-handle).
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Stand down while the New Layer panel, rule panel, or command bar is up — they own
            // the keyboard (text field).
            guard let self, self.exposed, !self.isKeyWindow,
                  self.newLayerPanel == nil, self.rulePanel == nil, self.commandPanel == nil else { return event }
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
        // Mark dead FIRST. A rapid hotkey re-fire can land a deactivate while the
        // async survey capture / first-paint from the *previous* activate is still
        // in flight. Those callbacks check `exposed` and self-heal via
        // rebuildExposeView() → installExposeHosts() — which, after teardown, would
        // resurrect the survey panels on a controller we no longer track (no key
        // monitor, no resign observer). That's the "Hyperspace stuck on top, esc /
        // quit / hotkey do nothing" trap. Clearing `exposed` + `dismissed` makes
        // every late callback a no-op so nothing can come back.
        dismissed = true
        stopLayoutRefresh()
        exposed = false
        ignoresMouseEvents = false
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
        rulePanel?.close()
        rulePanel = nil
        commandPanel?.close()
        commandPanel = nil
        animators.values.forEach { $0.cancel() }
        removeExposeHost()
        orderOut(nil)
    }

    /// Force every Hyperspace overlay panel off screen — even ones no live
    /// controller still tracks. Used as the recovery sweep so the toggle hotkey
    /// can always clear a survey that a prior race left orphaned (no key monitor,
    /// no resign observer) and stuck on top. Cheap; runs only on activate/deactivate.
    static func teardownStrayPanels() {
        for window in NSApp.windows where window is HyperspaceScreenPanel || window is MotionPanel {
            window.orderOut(nil)
            window.close()
        }
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

        // Fresh z-order from CGWindowList — stale eligible zIndex picks the wrong overlap.
        DesktopModel.shared.forcePoll()
        let myPid = ProcessInfo.processInfo.processIdentifier
        let eligibleWids = Set(eligible.map(\.wid))
        guard let fresh = DesktopModel.shared.frontWindow(at: cg, excludingPid: myPid),
              eligibleWids.contains(fresh.wid),
              let hit = eligible.first(where: { $0.wid == fresh.wid }) else { return }

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
        if exposed, handleClusterSearchKey(event) { return }
        if code == 53 {                                     // Esc — close inspector / placement stage first, else leave
            if dragModel.selectedLayer != nil { dragModel.selectedLayer = nil; return }
            if dragModel.isPlacing { dragModel.endPlacing(); return }
            undoAndExit(); return
        }
        if code == 36 || code == 76 {                       // Return / keypad Enter — confirm: keep + leave
            if exposed && inPlaceMode {
                let screen = validSurveyScreen(screenForPointer())
                    ?? validSurveyScreen(screenForEvent(event))
                    ?? activeSurveyScreen
                if let screen {
                    commitStagedIntents(on: screen)
                    DiagnosticLog.shared.info("In-place confirm — commit staged + exit")
                }
                onExit?()
            } else if exposed {                             // Hyperspace: gather the plucked, then leave
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
            case 14 where !mods.contains(.shift) && !inPlaceMode: collapseExpose(); return  // E — collapse survey
            case 5  where !mods.contains(.shift):                            // G — grid selection (stay in mode)
                if let eventScreen { gatherInPlace(on: eventScreen) }
                return
            case 3  where !mods.contains(.shift) && inPlaceMode:             // F — fill available space
                fillAvailableSpace()
                return
            case 1  where !mods.contains(.shift) && inPlaceMode:             // S — swap first two picks
                if let eventScreen, let id = screenID,
                   let a = pickOrderByScreen[id]?[safe: 0],
                   let b = pickOrderByScreen[id]?[safe: 1] {
                    swapWindows(widA: a, widB: b, on: eventScreen)
                } else { NSSound.beep() }
                return
            case 24: zoomCanvasStep(0.2); return                            // = / +  — zoom in
            case 27: zoomCanvasStep(-0.2); return                           // −      — zoom out
            case 29:
                if let eventScreen { canvasForScreen(eventScreen).reset() }  // 0      — reset to fit
                return
            case 44:                                                         // / — curated command bar
                if let eventScreen { presentCommandBar(on: eventScreen) }
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
        case 3:                                             // F — grow into open space until a neighbor
            fillAvailableSpace()
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
            fillAimWid = activeEntry.wid
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
        DiagnosticLog.shared.info("Motion — saved \(picked.count) selected windows as layer '\(layer.name)' [\(layer.summary)]")
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
        placeEntry(activeEntry, to: target, label: "place")
    }

    private func placeEntry(_ entry: WindowEntry, to target: CGRect, label: String = "place") {
        guard let el = ax(for: entry) else { NSSound.beep(); return }
        recordOriginal(entry.wid, el)
        let before = RealWindowAnimator.axFrame(el) ?? .zero
        raising { RealWindowAnimator.setFrameRobust(el, target, pid: entry.pid, raise: true) }
        let after = RealWindowAnimator.axFrame(el) ?? .zero
        DiagnosticLog.shared.info("Motion \(label) \(entry.app) wid=\(entry.wid) step=\(cycleStep) before=\(rectStr(before)) target=\(rectStr(target)) after=\(rectStr(after))")
        refreshBorders()
        updateStack()
        if exposed { rebuildExposeView() }
    }

    /// F — expand the aimed window until it hits a same-screen neighbor or the
    /// display edge. Perpendicular overlap counts as a wall (same rule as Screen Map grow).
    private func fillAvailableSpace(for wid: UInt32? = nil) {
        guard let target = wid.flatMap({ w in eligible.first(where: { $0.wid == w }) }) ?? fillTargetEntry(),
              let el = ax(for: target),
              let me = RealWindowAnimator.axFrame(el) else { NSSound.beep(); return }

        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let currentCenter = CGPoint(x: me.midX, y: primaryH - me.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(currentCenter) }) ?? screen(for: target) else {
            NSSound.beep(); return
        }

        let bounds = WindowTiler.tileFrame(fractions: (0, 0, 1, 1), on: screen)
        var left = bounds.minX, right = bounds.maxX, top = bounds.minY, bottom = bounds.maxY
        let tolerance: CGFloat = 2

        for other in eligible where other.wid != target.wid {
            guard entry(other, isOn: screen),
                  let otherEl = ax(for: other),
                  let of = RealWindowAnimator.axFrame(otherEl) else { continue }
            if of.maxX <= me.minX + tolerance && of.maxY > me.minY + tolerance && of.minY < me.maxY - tolerance {
                left = max(left, of.maxX)
            }
            if of.minX >= me.maxX - tolerance && of.maxY > me.minY + tolerance && of.minY < me.maxY - tolerance {
                right = min(right, of.minX)
            }
            if of.maxY <= me.minY + tolerance && of.maxX > me.minX + tolerance && of.minX < me.maxX - tolerance {
                top = max(top, of.maxY)
            }
            if of.minY >= me.maxY - tolerance && of.maxX > me.minX + tolerance && of.minX < me.maxX - tolerance {
                bottom = min(bottom, of.minY)
            }
        }

        let newFrame = CGRect(x: left, y: top, width: right - left, height: bottom - top)
        guard newFrame.width >= 160, newFrame.height >= 120 else { NSSound.beep(); return }
        if abs(newFrame.minX - me.minX) < tolerance && abs(newFrame.minY - me.minY) < tolerance
            && abs(newFrame.width - me.width) < tolerance && abs(newFrame.height - me.height) < tolerance {
            NSSound.beep(); return
        }

        lastSide = nil
        placeEntry(target, to: newFrame, label: "fill")
    }

    /// Pin keyboard actions (F fill, half-tiles, etc.) to the window the user last
    /// clicked or Tab-aimed — not a stale expose index from mode entry.
    private func aimWindow(_ wid: UInt32, on surveyScreen: NSScreen? = nil) {
        fillAimWid = wid
        if let idx = eligible.firstIndex(where: { $0.wid == wid }) {
            reticle = idx
        }
        let resolvedScreen = surveyScreen
            ?? activeSurveyScreen
            ?? eligible.first(where: { $0.wid == wid }).flatMap { self.screen(for: $0) }
        if let resolvedScreen {
            let id = MotionPanel.screenID(resolvedScreen)
            if let order = exposeOrderByScreen[id], let aimIdx = order.firstIndex(of: wid) {
                exposeAimByScreen[id] = aimIdx
                if activeSurveyScreen.map(MotionPanel.screenID) == id {
                    exposeAim = aimIdx
                }
            }
        }
    }

    private func fillTargetEntry() -> WindowEntry? {
        if let wid = fillAimWid, let entry = eligible.first(where: { $0.wid == wid }) {
            return entry
        }
        return activeEntry
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
        var moves: [(wid: UInt32, pid: Int32, frame: CGRect)] = []
        moves.reserveCapacity(members.count)
        for (i, m) in members.enumerated() {
            let r = rects[i]
            let target = WindowTiler.tileFrame(fractions: (r.minX, r.minY, r.width, r.height), on: screen)
            if let el = ax(for: m) { recordOriginal(m.wid, el) }
            moves.append((wid: m.wid, pid: m.pid, frame: target))
        }
        guard !moves.isEmpty else { return }
        raising {
            WindowTiler.batchMoveAndRaiseWindows(moves)
        }
        AppFeedback.shared.playTapSound()
        DiagnosticLog.shared.info("Motion grid — \(moves.count) windows")
    }

    /// Refresh inventory chrome after a grid snap without blocking the batch move.
    private func refreshAfterGridMove() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            DesktopModel.shared.poll()
            self.rebuildExposeView()
            self.updateLegend()
            self.refreshBorders()
            self.updateStack()
            self.makeKey()
        }
    }

    /// G — make sure the aimed window is part of the group, then lay out the grid.
    private func distributeGroup() {
        if !group.contains(activeEntry.wid) { togglePicked(activeEntry.wid) }
        relayoutGroup()
        updateLegend()
        if inPlaceMode {
            refreshAfterGridMove()
        } else {
            refreshBorders()
            updateStack()
        }
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
        ignoresMouseEvents = !inPlaceMode
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
        startLayoutRefresh()

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
        stopLayoutRefresh()
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

    /// Stage a balanced sub-grid for a multi-window drop onto the lattice, anchored at `anchor`.
    private func handleGridGroupDrop(_ wids: [UInt32], res: LatticeRes, anchor: HoverCell) {
        let (cols, rows) = res.dims
        guard let cells = balancedGridCells(count: wids.count, latticeCols: cols, latticeRows: rows,
                                            anchorCol: anchor.col, anchorRow: anchor.row) else {
            NSSound.beep()
            return
        }
        for (i, wid) in wids.enumerated() {
            let cell = cells[i]
            guard let gp = GridPlacement(columns: cols, rows: rows, column: cell.col, row: cell.row) else { continue }
            handleDrop(wid, PlacementSpec.grid(gp))
        }
        DiagnosticLog.shared.info("Hyperspace stage — \(wids.count) windows grid @ \(anchor.col),\(anchor.row) (\(res.name))")
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

    /// Edit mode: drop one rule clause from a layer (the ✕ on a pile's rule chip).
    /// Writes straight through to StudioLayerStore — these are committed rules, not
    /// staged intents. A layer whose last rule is removed is deleted (a ruleless
    /// layer matches nothing). The band rebuilds so the pile preview re-resolves.
    private func removeLayerClause(_ layerId: String, _ clauseIndex: Int) {
        let store = StudioLayerStore.shared
        guard var layer = store.layers.first(where: { $0.id == layerId }),
              layer.match.indices.contains(clauseIndex) else { return }
        layer.match.remove(at: clauseIndex)
        if layer.match.isEmpty {
            store.delete(id: layerId)
        } else {
            store.update(layer)
        }
        DiagnosticLog.shared.info("Hyperspace edit — layer \(layer.name) dropped clause \(clauseIndex)")
        rebuildExposeView()
    }

    /// Edit mode: write a new or edited rule clause from the Hyperspace inspector.
    private func saveLayerClause(_ layerId: String, _ clauseIndex: Int?, _ clause: StudioLayerClause) {
        let store = StudioLayerStore.shared
        guard var layer = store.layers.first(where: { $0.id == layerId }) else { return }
        if let clauseIndex, layer.match.indices.contains(clauseIndex) {
            layer.match[clauseIndex] = clause
            DiagnosticLog.shared.info("Hyperspace edit — layer \(layer.name) updated clause \(clauseIndex)")
        } else {
            layer.match.append(clause)
            DiagnosticLog.shared.info("Hyperspace edit — layer \(layer.name) added clause [\(clause.summary)]")
        }
        store.update(layer)
        rebuildExposeView()
    }

    private func presentLayerRuleEditor(_ layerId: String, _ clauseIndex: Int?, _ clause: StudioLayerClause, on screen: NSScreen) {
        guard exposed, rulePanel == nil,
              let layer = StudioLayerStore.shared.layers.first(where: { $0.id == layerId }) else { return }
        ignoreResign = true
        let panel = LayerRulePanel(
            layerName: layer.name,
            clauseIndex: clauseIndex,
            clause: clause,
            onSave: { [weak self] saved in
                guard let self else { return }
                self.saveLayerClause(layerId, clauseIndex, saved)
                self.finishLayerRuleEditor()
            },
            onCancel: { [weak self] in self?.finishLayerRuleEditor() }
        )
        rulePanel = panel
        panel.present(on: screen)
    }

    private func finishLayerRuleEditor() {
        rulePanel = nil
        ignoreResign = false
        makeKey()
    }

    /// Edit mode: delete a whole layer (the "Delete layer" item in a pile's right-click menu).
    private func deleteLayer(_ layerId: String) {
        let name = StudioLayerStore.shared.layers.first(where: { $0.id == layerId })?.name ?? layerId
        StudioLayerStore.shared.delete(id: layerId)
        DiagnosticLog.shared.info("Hyperspace edit — deleted layer \(name)")
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
                let clauses = apps.map { StudioLayerClause(appEquals: $0) }
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
                    frac: MotionPanel.frac(of: layoutFrame(for: freshEntry(w)), in: screenAX),
                    tint: Color(nsColor: MotionPanel.tint(for: w.app)),
                    image: thumbs[w.wid])
            }
            let stagedCount = stagedIntents.values.filter { $0.layers.contains(layer.id) }.count
            return ExposeView.LayerPile(id: layer.id, name: layer.name, count: onScreen.count,
                                        members: members, rule: layer.summary, clauses: layer.match,
                                        isNew: false, staged: stagedCount > 0, stagedCount: stagedCount)
        }
        let newCount = stagedIntents.values.filter { $0.newLayer }.count
        piles.append(ExposeView.LayerPile(id: HyperspaceDrag.newLayerKey, name: "new", count: 0,
                                          isNew: true, staged: newCount > 0, stagedCount: newCount))
        return piles
    }

    /// Latest polled entry for a survey window (DesktopModel refreshes on its own timer).
    private func freshEntry(_ w: WindowEntry) -> WindowEntry {
        DesktopModel.shared.allWindows().first { $0.wid == w.wid } ?? w
    }

    /// Live AX frame when we can resolve it, else the freshest polled CG frame.
    private func layoutFrame(for entry: WindowEntry) -> CGRect {
        if let el = ax(for: entry), let f = RealWindowAnimator.axFrame(el) { return f }
        return layoutCGFrame(for: entry)
    }

    /// Polled CG frame for display maps — matches DesktopModel / inferTilePlacement coords.
    private func layoutCGFrame(for entry: WindowEntry) -> CGRect {
        let fresh = freshEntry(entry)
        return CGRect(x: fresh.frame.x, y: fresh.frame.y, width: fresh.frame.w, height: fresh.frame.h)
    }

    /// Same eligibility rules as the survey, but polled live so moved / raised windows
    /// still appear in Current View without reopening Hyperspace.
    private func liveMembers(on screen: NSScreen) -> [WindowEntry] {
        let myPid = ProcessInfo.processInfo.processIdentifier
        return DesktopModel.shared.allWindows()
            .filter { $0.pid != myPid && $0.isOnScreen && !$0.title.isEmpty }
            .filter { entry($0, isOn: screen) }
    }

    private func layoutSignificantOverlap(_ a: CGRect, _ b: CGRect) -> Bool {
        let inter = a.intersection(b)
        guard !inter.isNull && inter.width > 0 && inter.height > 0 else { return false }
        let interArea = inter.width * inter.height
        let smallerArea = min(a.width * a.height, b.width * b.height)
        guard smallerArea > 0 else { return false }
        return interArea / smallerArea >= 0.15
    }

    /// Every window currently on a screen, as fractional footprints — the Current View's
    /// always-on baseline ("what this display looks like right now"). Uses live members
    /// + CG frames (not the open-time snapshot) and paints back-to-front so frontmost
    /// reads on top; windows covered by a front neighbor are marked `behind`.
    private func currentLayout(on screen: NSScreen) -> [ExposeView.LayerMember] {
        DesktopModel.shared.poll()
        let screenAX = MotionPanel.axRect(of: screen)
        let windows = liveMembers(on: screen).sorted { $0.zIndex < $1.zIndex }
        let frames = windows.map { layoutCGFrame(for: $0) }
        return windows.enumerated().map { i, w in
            let frame = frames[i]
            let behind = (0..<i).contains { j in
                layoutSignificantOverlap(frames[j], frame)
            }
            return ExposeView.LayerMember(
                id: w.wid,
                frac: MotionPanel.frac(of: frame, in: screenAX),
                tint: Color(nsColor: MotionPanel.tint(for: w.app)),
                image: thumbs[w.wid],
                behind: behind)
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

    /// Swap two windows' live frames in place — no grid staging, no separate flow.
    private func clearPicks(on screen: NSScreen) {
        let id = MotionPanel.screenID(screen)
        pickOrderByScreen[id] = []
        restorePickState(for: screen)
        rebuildExposeView()
        updateLegend()
        updateStack()
    }

    private func focusWindow(_ wid: UInt32, on screen: NSScreen) {
        guard let entry = eligible.first(where: { $0.wid == wid }), let el = ax(for: entry) else {
            NSSound.beep()
            return
        }
        raising { RealWindowAnimator.raise(el) }
        DesktopModel.shared.markInteraction(wid: wid)
        DispatchQueue.main.async { [weak self] in self?.makeKey() }
        DiagnosticLog.shared.info("In-place focus — wid=\(wid) app=\(entry.app)")
    }

    /// Immediate tile (explicit menu action) — distinct from staging for Enter.
    private func applyPlacementNow(_ wid: UInt32, _ placement: PlacementSpec, on screen: NSScreen) {
        guard let entry = eligible.first(where: { $0.wid == wid }) else { NSSound.beep(); return }
        if originalFrames[wid] == nil, let el = ax(for: entry), let cur = RealWindowAnimator.axFrame(el) {
            originalFrames[wid] = cur
        }
        raising {
            WindowTiler.tileWindowById(wid: wid, pid: entry.pid, to: placement, on: screen)
        }
        DesktopModel.shared.poll()
        rebuildExposeView()
        updateLegend()
        refreshBorders()
        DispatchQueue.main.async { [weak self] in self?.makeKey() }
        DiagnosticLog.shared.info("In-place apply — wid=\(wid) \(placement.wireValue)")
    }

    private func swapWindows(widA: UInt32, widB: UInt32, on screen: NSScreen) {
        guard widA != widB,
              let entryA = eligible.first(where: { $0.wid == widA }),
              let entryB = eligible.first(where: { $0.wid == widB }) else {
            NSSound.beep()
            return
        }
        DesktopModel.shared.poll()
        let frameA = layoutFrame(for: entryA)
        let frameB = layoutFrame(for: entryB)
        if originalFrames[widA] == nil { originalFrames[widA] = frameA }
        if originalFrames[widB] == nil { originalFrames[widB] = frameB }
        raising {
            WindowTiler.batchMoveAndRaiseWindows([
                (wid: widA, pid: entryA.pid, frame: frameB),
                (wid: widB, pid: entryB.pid, frame: frameA),
            ])
        }
        let id = MotionPanel.screenID(screen)
        pickOrderByScreen[id]?.removeAll { $0 == widA || $0 == widB }
        if activeSurveyScreen.map(MotionPanel.screenID) == id {
            restorePickState(for: screen)
        }
        DiagnosticLog.shared.info("Hyperspace swap — \(entryA.app) ↔ \(entryB.app)")
        rebuildExposeView()
        updateLegend()
        refreshBorders()
        updateStack()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.rebuildExposeView()
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

    /// Add an exact app clause to a layer's rule so it (and future windows of that
    /// app) join the layer.
    /// No-op if the layer already matches the app.
    private func addAppToLayer(_ app: String, layerID: String) {
        let store = StudioLayerStore.shared
        guard var layer = store.layers.first(where: { $0.id == layerID }) else { return }
        let already = layer.match.contains { clause in
            let appOnly = clause.titleContains == nil
                && clause.titleEquals == nil
                && clause.titleRegex == nil
                && clause.session == nil
                && clause.sessionContains == nil
                && clause.isOnScreen == nil
                && clause.spaceId == nil
                && (clause.not?.isEmpty ?? true)
            let sameExactApp = clause.appEquals?.localizedCaseInsensitiveCompare(app) == .orderedSame
            let sameLegacyApp = clause.app?.localizedCaseInsensitiveCompare(app) == .orderedSame
                && clause.appRegex == nil
            return appOnly && (sameExactApp || sameLegacyApp)
        }
        guard !already else { return }
        layer.match.append(StudioLayerClause(appEquals: app))
        store.update(layer)
        DiagnosticLog.shared.info("Hyperspace commit — layer '\(layer.name)' += app '\(app)'")
    }

    /// Gather the picked set into a balanced grid on the active display (the only
    /// place real windows move) and stay in the mode. Un-picked windows are left
    /// exactly where they are — in the survey they never moved. Shared by G and ⏎.
    private func gatherInPlace() {
        let screen = activeSurveyScreen ?? NSScreen.main ?? NSScreen.screens[0]
        commitStagedIntents(on: screen)   // drag & drop plan; no-op until staged
        let members = gatherMembers()
        if members.count >= 2 {
            relayoutGroup()                                       // picked set snaps into the grid, on top
        } else if let only = members.first, let el = ax(for: only) {
            raising { RealWindowAnimator.raise(el) }              // a single pick just comes forward
        }
        if inPlaceMode {
            refreshAfterGridMove()
            return
        }
        removeExposeHost()
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
        clusterSearchQueryByScreen = clusterSearchQueryByScreen.filter { validIDs.contains($0.key) }
        activeClusterSearchByScreen = activeClusterSearchByScreen.filter { validIDs.contains($0.key) }
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

        let clusterIDs = Set(clusters.map(\.id))
        clusterSearchQueryByScreen[id] = (clusterSearchQueryByScreen[id] ?? [:])
            .filter { clusterIDs.contains($0.key) }
        if let activeID = activeClusterSearchByScreen[id], !clusterIDs.contains(activeID) {
            activeClusterSearchByScreen[id] = nil
        }

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
        if inPlaceMode {
            return max(188, min(screen.frame.height * 0.24, 260))
        }
        // Reserve a touch under the top third for the intent band so the survey
        // grid gets the bottom ~2/3 (design/hyperspace-drag-drop.md). Floored so the
        // Layers/Lattice/Spaces cards still fit on a short display, capped so it
        // doesn't bloat on a tall external one.
        return max(196, min(screen.frame.height * 0.30, 420))
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
        guard !dismissed else { return }   // never re-create panels after teardown (orphan guard)
        removeExposeHost()
        for screen in surveyScreens() {
            let id = MotionPanel.screenID(screen)
            let placeholder = ExposeView(
                clusters: [],
                tileWidth: autoTileWidth(count: max(1, surveyMembers(on: screen).count), screen: screen),
                canvas: canvasForScreen(screen),
                drag: dragModel,
                screenID: id,
                bandHeight: bandHeight(for: screen),
                inPlace: inPlaceMode,
                screenAspect: screen.visibleFrame.width / max(1, screen.visibleFrame.height),
                usableInset: MotionPanel.usableInset(of: screen),
                onNewLayer: { [weak self] in self?.presentNewLayer() })
            let hosting: NSHostingView<ExposeView>
            if inPlaceMode {
                let inPlaceHost = InPlaceHostingView(rootView: placeholder)
                inPlaceHost.panel = self
                inPlaceHost.screen = screen
                hosting = inPlaceHost
            } else {
                hosting = NSHostingView(rootView: placeholder)
            }
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

    /// Poll DesktopModel and refresh Current View outlines while the survey is open.
    private func startLayoutRefresh() {
        stopLayoutRefresh()
        layoutRefreshTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            guard let self, self.exposed, !self.dismissed, !self.dragModel.isActive else { return }
            self.rebuildExposeView()
        }
    }

    private func stopLayoutRefresh() {
        layoutRefreshTimer?.invalidate()
        layoutRefreshTimer = nil
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
            let searchQueries = clusterSearchQueryByScreen[id] ?? [:]
            let activeSearchID = activeClusterSearchByScreen[id]
            let vm = clusters.map { box in
                ExposeView.Cluster(
                    id: box.id,
                    name: box.name,
                    rule: box.rule,
                    userDefined: box.userDefined,
                    hint: screenClusterHintFor[box.id] ?? "",
                    searchQuery: searchQueries[box.id] ?? "",
                    searchActive: activeSearchID == box.id,
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
                inPlace: inPlaceMode,
                screenAspect: screen.visibleFrame.width / max(1, screen.visibleFrame.height),
                usableInset: MotionPanel.usableInset(of: screen),
                onPick: { [weak self] wid in self?.exposeToggle(wid, on: screen) },
                onDrop: { [weak self] wid, spec in self?.handleDrop(wid, spec) },
                onDropGridGroup: { [weak self] wids, res, anchor in
                    self?.handleGridGroupDrop(wids, res: res, anchor: anchor)
                },
                onDropLayer: { [weak self] wid, key in self?.handleLayerDrop(wid, key) },
                onSwap: { [weak self] a, b in self?.swapWindows(widA: a, widB: b, on: screen) },
                onGridSelection: { [weak self] in self?.gatherInPlace(on: screen) },
                onSwapFirstTwo: { [weak self] in
                    guard let self, let a = self.pickOrderByScreen[id]?[safe: 0],
                          let b = self.pickOrderByScreen[id]?[safe: 1] else { NSSound.beep(); return }
                    self.swapWindows(widA: a, widB: b, on: screen)
                },
                onSwapWith: { [weak self] a, b in self?.swapWindows(widA: a, widB: b, on: screen) },
                onFocusWindow: { [weak self] wid in self?.focusWindow(wid, on: screen) },
                onClearSelection: { [weak self] in self?.clearPicks(on: screen) },
                onApplyPlacement: { [weak self] wid, spec in self?.applyPlacementNow(wid, spec, on: screen) },
                onFillAvailable: { [weak self] wid in self?.fillAvailableSpace(for: wid) },
                onOpenHyperspace: {
                    WindowMotionMode.shared.deactivate()
                    WindowMotionMode.shared.toggleHyperspace()
                },
                layers: layerPiles(on: screen),
                stagedPlan: stagedPlan(on: screen),
                currentLayout: currentLayout(on: screen),
                pickedWids: Set(pickOrderByScreen[id] ?? []),
                pickedOrder: pickOrderByScreen[id] ?? [],
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
                onRecallLayer: { [weak self] id in self?.pluckLayer(id, on: screen) },
                onBeginClusterSearch: { [weak self] cid in self?.activateClusterSearch(cid, on: screen) },
                onClearClusterSearch: { [weak self] cid in self?.clearClusterSearch(cid, on: screen) },
                onEditClause: { [weak self] id, idx, clause in self?.presentLayerRuleEditor(id, idx, clause, on: screen) },
                onRemoveClause: { [weak self] id, idx in self?.removeLayerClause(id, idx) },
                onDeleteLayer: { [weak self] id in self?.deleteLayer(id) },
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
        aimWindow(wid)
        rebuildExposeView()
        updateLegend()
        updateStack()
    }

    private func exposeToggle(_ wid: UInt32, on screen: NSScreen) {
        aimWindow(wid, on: screen)
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

    // MARK: - Cluster-local search

    private func activateClusterSearch(_ clusterID: Int, on screen: NSScreen) {
        let screenID = MotionPanel.screenID(screen)
        activeClusterSearchByScreen.removeAll()
        activeClusterSearchByScreen[screenID] = clusterID
        var queries = clusterSearchQueryByScreen[screenID] ?? [:]
        queries[clusterID] = queries[clusterID] ?? ""
        clusterSearchQueryByScreen[screenID] = queries
        if activeSurveyScreen.map(MotionPanel.screenID) != screenID {
            setActiveSurveyScreen(screen)
        }
        rebuildExposeView()
    }

    private func clearClusterSearch(_ clusterID: Int, on screen: NSScreen) {
        let screenID = MotionPanel.screenID(screen)
        var queries = clusterSearchQueryByScreen[screenID] ?? [:]
        queries[clusterID] = ""
        clusterSearchQueryByScreen[screenID] = queries
        activeClusterSearchByScreen[screenID] = clusterID
        if activeSurveyScreen.map(MotionPanel.screenID) != screenID {
            setActiveSurveyScreen(screen)
        }
        rebuildExposeView()
    }

    private func activeClusterSearchTarget() -> (screen: NSScreen, screenID: String, clusterID: Int)? {
        for (screenID, clusterID) in activeClusterSearchByScreen {
            if let screen = NSScreen.screens.first(where: { MotionPanel.screenID($0) == screenID }) {
                return (screen, screenID, clusterID)
            }
        }
        return nil
    }

    private func handleClusterSearchKey(_ event: NSEvent) -> Bool {
        guard commandPanel == nil, newLayerPanel == nil, rulePanel == nil,
              let target = activeClusterSearchTarget() else { return false }

        switch event.keyCode {
        case 53:                                                    // Esc — clear, then leave filter mode
            let q = clusterSearchQueryByScreen[target.screenID]?[target.clusterID] ?? ""
            if q.isEmpty {
                activeClusterSearchByScreen[target.screenID] = nil
            } else {
                setClusterSearchQuery("", clusterID: target.clusterID, screenID: target.screenID)
            }
            rebuildExposeView()
            return true
        case 51:                                                    // Delete / Backspace
            var q = clusterSearchQueryByScreen[target.screenID]?[target.clusterID] ?? ""
            if !q.isEmpty {
                q.removeLast()
                setClusterSearchQuery(q, clusterID: target.clusterID, screenID: target.screenID)
                rebuildExposeView()
            }
            return true
        case 36, 76:                                                // Return — pluck visible matches
            selectClusterSearchMatches(target.clusterID, on: target.screen)
            return true
        default:
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let blocked = flags.contains(.command) || flags.contains(.control) || flags.contains(.option)
            guard !blocked, let text = clusterSearchText(from: event) else { return false }
            let current = clusterSearchQueryByScreen[target.screenID]?[target.clusterID] ?? ""
            setClusterSearchQuery(current + text, clusterID: target.clusterID, screenID: target.screenID)
            rebuildExposeView()
            return true
        }
    }

    private func setClusterSearchQuery(_ query: String, clusterID: Int, screenID: String) {
        var queries = clusterSearchQueryByScreen[screenID] ?? [:]
        queries[clusterID] = String(query.prefix(80))
        clusterSearchQueryByScreen[screenID] = queries
    }

    private func clusterSearchText(from event: NSEvent) -> String? {
        guard let chars = event.characters, !chars.isEmpty else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_./:@#")
        guard chars.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return chars
    }

    private func selectClusterSearchMatches(_ clusterID: Int, on screen: NSScreen) {
        let screenID = MotionPanel.screenID(screen)
        guard let box = exposeClustersByScreen[screenID]?.first(where: { $0.id == clusterID }) else {
            NSSound.beep()
            return
        }
        let query = clusterSearchQueryByScreen[screenID]?[clusterID] ?? ""
        let hints = hintForByScreen[screenID] ?? [:]
        let matches = box.members
            .filter { Self.clusterSearchMatches($0, query: query, hint: hints[$0.wid] ?? "") }
            .map(\.wid)
        guard !matches.isEmpty else {
            NSSound.beep()
            return
        }

        var order = pickOrderByScreen[screenID] ?? []
        for wid in matches where !order.contains(wid) {
            order.append(wid)
            if let e = eligible.first(where: { $0.wid == wid }) { _ = ax(for: e) }
        }
        pickOrderByScreen[screenID] = order
        setClusterSearchQuery("", clusterID: clusterID, screenID: screenID)
        activeClusterSearchByScreen[screenID] = nil
        if activeSurveyScreen.map(MotionPanel.screenID) != screenID {
            setActiveSurveyScreen(screen)
        } else {
            restorePickState(for: screen)
        }
        rebuildExposeView()
        updateLegend()
        updateStack()
    }

    private static func clusterSearchMatches(_ entry: WindowEntry, query: String, hint: String) -> Bool {
        let terms = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .split(whereSeparator: { $0.isWhitespace })
        guard !terms.isEmpty else { return true }
        let haystack = "\(entry.title) \(entry.app) \(hint)".lowercased()
        return terms.allSatisfy { haystack.range(of: String($0)) != nil }
    }

    // MARK: - Command bar (/)

    /// Open the curated `/` palette for one monitor: search its windows, target a
    /// group/layer (⏎ plucks), or /tile to stage a placement. Snapshots this screen's
    /// windows/clusters/layers and wires each verb to the survey's own selection path.
    private func presentCommandBar(on screen: NSScreen) {
        guard commandPanel == nil else { return }
        let id = MotionPanel.screenID(screen)
        let windows = surveyMembers(on: screen).map {
            HyperspaceCommandModel.WindowItem(wid: $0.wid, title: $0.title.isEmpty ? $0.app : $0.title, app: $0.app)
        }
        let hintFor = clusterHintForByScreen[id] ?? [:]
        let groups = (exposeClustersByScreen[id] ?? []).map { cluster in
            HyperspaceCommandModel.GroupItem(cid: cluster.id, name: cluster.name,
                                             hint: hintFor[cluster.id] ?? "", members: cluster.members.map(\.wid))
        }
        let store = StudioLayerStore.shared
        let layers = store.layers.map { layer in
            HyperspaceCommandModel.LayerItem(lid: layer.id, name: layer.name,
                                             members: store.resolve(layer).filter { self.entry($0, isOn: screen) }.map(\.wid))
        }
        let model = HyperspaceCommandModel(windows: windows, groups: groups, layers: layers)
        model.onPluckWindow = { [weak self] wid in self?.exposeToggle(wid, on: screen) }
        model.onPluckGroup  = { [weak self] cid in self?.exposeToggleCluster(cid, on: screen) }
        model.onRecallLayer = { [weak self] lid in self?.pluckLayer(lid, on: screen) }
        model.onTile        = { [weak self] gp  in self?.stageTileForSelection(gp, on: screen) }
        model.onSaveLayer   = { [weak self] in self?.saveGroupAsLayer() }
        model.pluckedProvider = { [weak self] in self?.pickOrderByScreen[id] ?? [] }
        let panel = HyperspaceCommandPanel(model: model, onClose: { [weak self] in self?.dismissCommandBar() })
        commandPanel = panel
        ignoreResign = true                 // the bar takes key → our key-resign must NOT exit the survey
        panel.present(on: screen)
    }

    private func dismissCommandBar() {
        commandPanel?.close()
        commandPanel = nil
        ignoreResign = false
        makeKey()                           // reclaim key so the survey keeps responding
    }

    /// Select every on-screen window a layer's rule resolves to — the survey-native
    /// read of "recall this layer": it builds the selection (nothing raises), and
    /// gather (⏎/G) is still the only real move.
    private func pluckLayer(_ layerID: String, on screen: NSScreen) {
        let store = StudioLayerStore.shared
        guard let layer = store.layers.first(where: { $0.id == layerID }) else { NSSound.beep(); return }
        let members = store.resolve(layer).filter { entry($0, isOn: screen) }
        guard !members.isEmpty else { NSSound.beep(); return }
        let id = MotionPanel.screenID(screen)
        var order = pickOrderByScreen[id] ?? []
        for w in members where !order.contains(w.wid) {
            order.append(w.wid)
            if let e = eligible.first(where: { $0.wid == w.wid }) { _ = ax(for: e) }
        }
        pickOrderByScreen[id] = order
        if activeSurveyScreen.map(MotionPanel.screenID) != id { setActiveSurveyScreen(screen) }
        else { restorePickState(for: screen) }
        rebuildExposeView(); updateLegend(); updateStack()
    }

    /// Stage a named placement for the plucked set on this screen — the same staging
    /// a drag onto the Grid does. Nothing moves until gather (⏎/G).
    private func stageTileForSelection(_ gp: GridPlacement, on screen: NSScreen) {
        let id = MotionPanel.screenID(screen)
        let picked = pickOrderByScreen[id] ?? []
        guard !picked.isEmpty else { NSSound.beep(); return }
        let spec = PlacementSpec.grid(gp)
        for wid in picked { handleDrop(wid, spec) }
        rebuildExposeView()
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

    // MARK: - In-place desktop click (Hyper+G)

    /// Frontmost eligible window at a desktop click. Walks CGWindowList fresh so
    /// z-order and bounds match what you see at click time — the open-time
    /// `eligible` snapshot can be stale after raises.
    private func topWindowAtDesktopClick(cg: CGPoint, on screen: NSScreen) -> WindowEntry? {
        let selectable = Dictionary(uniqueKeysWithValues: surveyMembers(on: screen).map { ($0.wid, $0) })
        guard !selectable.isEmpty,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let myPid = ProcessInfo.processInfo.processIdentifier
        for info in list {
            guard let wid = info[kCGWindowNumber as String] as? UInt32,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary else { continue }
            if pid == myPid { continue }       // skip our transparent overlay panels

            var rect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict, &rect),
                  rect.width >= 50, rect.height >= 50,
                  rect.contains(cg) else { continue }

            let isOnScreen = info[kCGWindowIsOnscreen as String] as? Bool ?? true
            guard isOnScreen else { continue }

            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 else {
                return nil                      // front menu/panel/etc. blocks windows behind it
            }

            // The first real window containing the click owns the click.  If it
            // is not in this in-place survey roster, do not fall through and pick
            // some eligible window hidden behind it.
            return selectable[wid]
        }
        return nil
    }

    /// AppKit screen point (bottom-left origin) → CG top-left, matching liveFrame / AX.
    fileprivate func cgPoint(fromAppKitScreen point: CGPoint) -> CGPoint {
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: point.x, y: primaryH - point.y)
    }

    fileprivate func appKitScreenPoint(from viewPoint: NSPoint, in view: NSView) -> CGPoint {
        let windowPoint = view.convert(viewPoint, to: nil)
        if let window = view.window {
            return window.convertPoint(toScreen: windowPoint)
        }
        return NSEvent.mouseLocation
    }

    /// True when this click should be captured by the overlay (over a live window).
    fileprivate func inPlaceCapturesDesktopClick(at viewPoint: NSPoint, in view: NSView, on screen: NSScreen) -> Bool {
        guard exposed, inPlaceMode, !dismissed, !dragModel.isActive, !dragModel.isPlacing else { return false }
        guard commandPanel == nil, newLayerPanel == nil, rulePanel == nil else { return false }
        let cg = cgPoint(fromAppKitScreen: appKitScreenPoint(from: viewPoint, in: view))
        return topWindowAtDesktopClick(cg: cg, on: screen) != nil
    }

    fileprivate func performInPlaceDesktopSelect(at viewPoint: NSPoint, in view: NSView, on screen: NSScreen) {
        let cg = cgPoint(fromAppKitScreen: appKitScreenPoint(from: viewPoint, in: view))
        guard let hit = topWindowAtDesktopClick(cg: cg, on: screen) else { return }
        exposeToggle(hit.wid, on: screen)
        DiagnosticLog.shared.info("In-place select — click wid=\(hit.wid) app=\(hit.app) fillAim=\(hit.wid)")
        DispatchQueue.main.async { [weak self] in
            guard let self, self.exposed, !self.isKeyWindow, self.commandPanel == nil else { return }
            self.makeKey()
        }
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
        if let wid = exposeOrder[safe: exposeAim] { aimWindow(wid) }
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
        if let wid = order[safe: exposeAimByScreen[id] ?? 0] { aimWindow(wid, on: screen) }
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
        frac(of: CGRect(x: frame.x, y: frame.y, width: frame.w, height: frame.h), in: screenAX)
    }

    static func frac(of frame: CGRect, in screenAX: CGRect) -> CGRect {
        guard screenAX.width > 1, screenAX.height > 1 else { return .zero }
        let x = (frame.minX - screenAX.minX) / screenAX.width
        let y = (frame.minY - screenAX.minY) / screenAX.height
        let cx = min(max(x, 0), 1), cy = min(max(y, 0), 1)
        return CGRect(x: cx, y: cy,
                      width: min(frame.width / screenAX.width, 1 - cx),
                      height: min(frame.height / screenAX.height, 1 - cy))
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
                     inPlace: inPlaceMode,
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
        if inPlaceMode {
            stackHost.isHidden = true
            return
        }
        stackHost.isHidden = false
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
    var inPlace: Bool = false
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
                if inPlace {
                    keyHint("click", "select")
                    keyHint("a–z", "select")
                    keyHint("S", "swap 2")
                    keyHint("G", "grid")
                    keyHint("F", "fill")
                    keyHint("drag", "stage")
                    keyHint("⏎", "commit")
                    keyHint("esc", "exit")
                    keyHint("Hyper+␣", "survey")
                } else {
                    keyHint("a–z", "select")
                    keyHint("⇧a–z", "group")
                    keyHint("Tab", "aim")
                    keyHint("⌘scroll", "zoom")
                    keyHint("⏎", "gather")
                    if groupCount > 0 { keyHint("⌘L", "save layer") }
                    keyHint("E", "collapse")
                    keyHint("esc", "cancel")
                    keyHint("Hyper+G", "in-place")
                }
            } else {
                keyHint("Tab", "aim")
                keyHint("Space", "select")
                keyHint("E", "expose")
                keyHint("G", "grid")
                keyHint("F", "fill")
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

/// Collects the Current View screen-map frame (root space) for drop hit-testing.
private struct CurrentViewFrameKey: PreferenceKey {
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
        let searchQuery: String
        let searchActive: Bool
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
        var behind: Bool = false   // covered by a more-front window on this display
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
        var clauses: [StudioLayerClause] = []// structured rules, for edit-mode removal
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
    var inPlace: Bool = false
    var screenAspect: CGFloat = 1.6
    var usableInset = EdgeInsets()   // full panel(frame) → visibleFrame, so the Place stage clears the menu bar/Dock
    var onPick: (UInt32) -> Void = { _ in }
    var onDrop: (UInt32, PlacementSpec?) -> Void = { _, _ in }
    var onDropGridGroup: ([UInt32], LatticeRes, HoverCell) -> Void = { _, _, _ in }
    var onDropLayer: (UInt32, String) -> Void = { _, _ in }
    var onSwap: (UInt32, UInt32) -> Void = { _, _ in }
    var onGridSelection: () -> Void = {}
    var onSwapFirstTwo: () -> Void = {}
    var onSwapWith: (UInt32, UInt32) -> Void = { _, _ in }
    var onFocusWindow: (UInt32) -> Void = { _ in }
    var onClearSelection: () -> Void = {}
    var onApplyPlacement: (UInt32, PlacementSpec) -> Void = { _, _ in }
    var onFillAvailable: (UInt32) -> Void = { _ in }
    var onOpenHyperspace: () -> Void = {}
    var layers: [LayerPile] = []
    var stagedPlan: [StagedMarker] = []
    var currentLayout: [LayerMember] = []   // every window on this display — context for the Place stage
    var pickedWids: Set<UInt32> = []      // plucked on this screen — outlined brighter when focused
    var pickedOrder: [UInt32] = []        // pick order — swap uses the first two
    var displayScope: DisplayScope?
    var onLayout: ([UInt32: CGRect]) -> Void = { _ in }
    var onHandKeys: (Bool) -> Void = { _ in }
    var onExit: () -> Void = { }              // mouse-driven leave (the ✕ button)
    var onNewLayer: () -> Void = { }          // tap the ＋ pile → open the New Layer authoring flow
    var onRecallLayer: (String) -> Void = { _ in } // add every live match to the survey selection
    var onBeginClusterSearch: (Int) -> Void = { _ in }
    var onClearClusterSearch: (Int) -> Void = { _ in }
    var onEditClause: (String, Int?, StudioLayerClause) -> Void = { _, _, _ in }
    var onRemoveClause: (String, Int) -> Void = { _, _ in }  // edit mode: drop a rule clause (layerId, clauseIndex)
    var onDeleteLayer: (String) -> Void = { _ in }           // edit mode: delete a whole layer (layerId)
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
    @State private var showInPlaceCommands = false

    @State private var perfMode = false
    @State private var perfFlat = false                  // A = true, B = false
    @StateObject private var perf = PerfStats()

    var body: some View {
        ZStack {
            if inPlace {
                inPlaceSignatureBackdrop
            } else {
                backdrop
                VStack(spacing: 0) {
                    overlayIntentChrome(mode: "hyperspace", detail: "window survey")
                    survey
                }
            }
            if inPlace {
                VStack(spacing: 0) {
                    overlayIntentChrome(mode: "in-place", detail: "shared with hyperspace")
                    Spacer(minLength: 0).allowsHitTesting(false)
                }
                VStack {
                    Spacer(minLength: 0).allowsHitTesting(false)
                    HStack {
                        Spacer(minLength: 0)
                        floatingWindowInventory
                    }
                    .padding(.trailing, 18)
                    .padding(.bottom, 18)
                }
            }
            placementStage
            ghostOverlay
            dropPulseOverlay
        }
        .coordinateSpace(name: ExposeView.rootSpace)    // band, survey, ghost share one space
        .animation(.spring(response: 0.26, dampingFraction: 0.82), value: rosterPileID)
        .animation(.spring(response: 0.26, dampingFraction: 0.82), value: drag.placeWid)
        .animation(.spring(response: 0.2, dampingFraction: 0.74), value: drag.placeCell)
        .overlay(alignment: .bottomLeading) {
            if !drag.isPlacing {
                LatticesOverlayWatermarkPlacement()
            }
        }
        .overlay(alignment: .topTrailing) {
            if !drag.isPlacing {                            // the Place stage owns the screen
                VStack(alignment: .trailing, spacing: 8) {
                    exitButton
                    if !inPlace { settingsToggle }
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
                planSummaryBar.padding(.top, intentChromeHeight + 4)   // sits just under the intent strip
            }
        }
        .overlay {
            if let id = drag.selectedLayer, let pile = layers.first(where: { $0.id == id }) {
                layerInspector(pile).transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.16), value: drag.selectedLayer)
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

    private enum InPlaceCommandRail { case leading, trailing }

    // In-place command hints flank the Current View mini-map — mouse + keys on the sides.
    private func inPlaceCommandRail(_ side: InPlaceCommandRail) -> some View {
        let leading = side == .leading
        let hints: [(String, String)] = leading
            ? [("a–z", "select"), ("S", "swap"), ("G", "grid"), ("F", "fill"), ("drag", "stage")]
            : [("⏎", "commit"), ("esc", "discard"), ("Hyper+␣", "survey")]
        return VStack(alignment: leading ? .leading : .trailing, spacing: 6) {
            inPlaceMouseCommandHint(side: side)
            ForEach(Array(hints.enumerated()), id: \.offset) { _, hint in
                inPlaceCommandHint(key: hint.0, label: hint.1, leading: leading)
            }
        }
        .frame(width: leading ? 76 : 86, alignment: leading ? .leading : .trailing)
    }

    private func inPlaceCommandHint(key: String, label: String, leading: Bool) -> some View {
        HStack(spacing: 5) {
            if !leading { inPlaceCommandLabel(label) }
            inPlaceCommandKey(key)
            if leading { inPlaceCommandLabel(label) }
        }
        .lineLimit(1)
    }

    private func inPlaceCommandLabel(_ label: String) -> some View {
        Text(label)
            .font(Typo.mono(10))
            .foregroundColor(Palette.textDim)
    }

    private func inPlaceCommandKey(_ key: String) -> some View {
        Text(key)
            .font(Typo.monoBold(10))
            .foregroundColor(Palette.text)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(0.10))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.borderLit, lineWidth: 0.5))
            )
    }

    private func inPlaceMouseCommandHint(side: InPlaceCommandRail) -> some View {
        let leading = side == .leading
        let icon = leading ? "hand.tap.fill" : "contextualmenu.and.cursorarrow"
        let key = leading ? "click" : "right-click"
        let label = leading ? "select" : "actions"
        return HStack(spacing: 5) {
            if !leading { inPlaceCommandLabel(label) }
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Palette.running.opacity(0.9))
            inPlaceCommandKey(key)
            if leading { inPlaceCommandLabel(label) }
        }
        .lineLimit(1)
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
        .help(inPlace ? "Exit In-Place" : "Exit Hyperspace")
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

                LatticesLatticeGrid(spacing: 26, opacity: 0.04, tint: Palette.running)
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

    /// All survey tiles on this display — drives the floating inventory roster.
    private var inventoryTiles: [Tile] {
        clusters.flatMap(\.tiles).sorted {
            $0.app.localizedCaseInsensitiveCompare($1.app) == .orderedAscending
        }
    }

    // Quiet signature wash under the live desktop — corner mark does the heavy lifting.
    private var inPlaceSignatureBackdrop: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [Palette.running.opacity(0.04), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 140)
            .frame(maxHeight: .infinity, alignment: .top)
            LatticesLatticeGrid(spacing: 28, opacity: 0.028, tint: Palette.running)
                .mask(
                    LinearGradient(
                        colors: [.white.opacity(0.5), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .allowsHitTesting(false)
    }

    // Inline monitor readout for the strip header — avoids a second top-left chip.
    private func displayScopeChip(_ scope: DisplayScope) -> some View {
        HStack(spacing: 6) {
            Image(systemName: scope.index == 0 ? "display" : "rectangle.on.rectangle")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Palette.running)
            Text(scope.label)
                .font(Typo.monoBold(9))
                .foregroundColor(Palette.text)
            if scope.count > 1 {
                Text("\(scope.index + 1)/\(scope.count)")
                    .font(Typo.mono(8))
                    .foregroundColor(Palette.textMuted)
            }
            Text("\(scope.windowCount)")
                .font(Typo.monoBold(9))
                .foregroundColor(Palette.running)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(Palette.running.opacity(0.12))
                        .overlay(Capsule().strokeBorder(Palette.running.opacity(0.28), lineWidth: 0.5))
                )
        }
        .lineLimit(1)
    }

    /// Header row + intent band — shared by Hyperspace survey and Hyper+G in-place.
    private var intentChromeHeight: CGFloat { bandHeight + 44 }

    private func overlayIntentChrome(mode: String, detail: String?) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                LatticesOverlayStripHeader(mode: mode, detail: detail)
                Spacer(minLength: 0)
                if let displayScope { displayScopeChip(displayScope) }
            }
            .padding(.horizontal, LatticesOverlayMetrics.edgeInset)
            .padding(.top, 10)
            .padding(.bottom, 6)
            intentBand
                .frame(height: bandHeight)
                .clipped()
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .background { LatticesOverlayStripBackground() }
    }

    // Bottom-right window inventory — compact roster linked to Current View.
    private var floatingWindowInventory: some View {
        let tiles = inventoryTiles
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Palette.running)
                Text("Windows")
                    .font(Typo.monoBold(11))
                    .foregroundColor(.white)
                Text("\(tiles.count)")
                    .font(Typo.monoBold(10))
                    .foregroundColor(Palette.running)
                Spacer(minLength: 0)
                if !pickedWids.isEmpty {
                    Text("\(pickedWids.count) selected")
                        .font(Typo.mono(9))
                        .foregroundColor(Palette.running)
                }
                Text("a–z")
                    .font(Typo.mono(8))
                    .foregroundColor(Palette.textMuted)
            }
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(tiles) { t in
                        inventoryRow(t)
                    }
                }
            }
            .frame(maxHeight: min(380, CGFloat(tiles.count) * 58 + 8))
        }
        .frame(width: 292)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Palette.borderLit, lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.5), radius: 22, y: 10)
    }

    private func inventoryRow(_ t: Tile) -> some View {
        let linked = activeLinkWid == t.id
        let picked = t.pickSlot != nil
        let lit = surveyHighlightWids?.contains(t.id) == true
        let hasSelection = !pickedWids.isEmpty
        let dimmed = hasSelection && !picked
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let thumbW: CGFloat = 72
        let thumbH: CGFloat = 44
        return HStack(spacing: 8) {
            if picked {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Palette.running)
                    .frame(width: 3, height: thumbH)
            }
            ZStack {
                shape.fill(t.tint.opacity(picked ? 0.32 : 0.22))
                if let img = t.image {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                }
                if picked {
                    shape.fill(Palette.running.opacity(0.12))
                }
            }
            .frame(width: thumbW, height: thumbH)
            .clipShape(shape)
            .overlay(shape.strokeBorder(
                linked ? HUDChrome.cyan
                    : (picked ? Palette.running : t.tint.opacity(0.55)),
                lineWidth: linked ? 2 : (picked ? 2 : 0.75)))
            VStack(alignment: .leading, spacing: 2) {
                Text(t.app)
                    .font(Typo.monoBold(10))
                    .foregroundColor(picked ? .white : .white.opacity(dimmed ? 0.65 : 1))
                    .lineLimit(1)
                Text(t.title)
                    .font(Typo.mono(8.5))
                    .foregroundColor(picked ? Palette.running.opacity(0.9) : Palette.textMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if picked {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Palette.running)
                    if let slot = t.pickSlot {
                        Text("\(slot)")
                            .font(Typo.monoBold(9))
                            .foregroundColor(Palette.bg)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(Palette.running))
                    }
                }
            } else if inPlace, !t.hint.isEmpty {
                Text(t.hint)
                    .font(Typo.monoBold(9))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(picked ? Palette.running.opacity(0.14)
                      : (lit ? Color.white.opacity(0.08) : Color.white.opacity(0.03)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(linked ? HUDChrome.cyan.opacity(0.7)
                                    : (picked ? Palette.running.opacity(0.75) : Palette.border),
                                  lineWidth: linked ? 1.5 : (picked ? 1.5 : 0.5)))
        )
        .opacity(dimmed ? 0.48 : 1)
        .contentShape(Rectangle())
        .highPriorityGesture(TapGesture().onEnded { onPick(t.id) })
        .gesture(
            DragGesture(minimumDistance: 10, coordinateSpace: .named(ExposeView.rootSpace))
                .onChanged { handleDragChange(t, tileWidth: thumbW, $0) }
                .onEnded { handleDragEnd(t, $0) }
        )
        .onHover { over in
            guard !drag.isActive else { return }
            if over { drag.hoverSurveyWid = t.id }
            else if drag.hoverSurveyWid == t.id { drag.hoverSurveyWid = nil }
        }
        .contextMenu { windowContextMenu(t) }
        .animation(.easeOut(duration: 0.14), value: linked)
        .animation(.easeOut(duration: 0.14), value: picked)
    }

    private func pickSlot(for wid: UInt32) -> Int? {
        pickedOrder.firstIndex(of: wid).map { $0 + 1 }
    }

    @ViewBuilder
    private func windowContextMenu(_ t: Tile) -> some View {
        if inPlace { inPlaceTileMenu(t) } else { tileMenu(t) }
    }

    private var intentBand: some View {
        // Three slots: Layers (pick/tag) · Current View (select) · Grid (drop a cell).
        GeometryReader { geo in
            let sideW = (geo.size.width * (inPlace ? 0.14 : 0.18)).rounded()
            let centerW = (geo.size.width * (inPlace ? 0.44 : 0.18)).rounded()
            let gap = (geo.size.width * (inPlace ? 0.01 : 0.018)).rounded()
            HStack(alignment: .top, spacing: gap) {
                layersSection.frame(width: sideW)
                currentViewSection.frame(width: centerW)
                gridSection.frame(width: sideW)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, inPlace ? 2 : 4)
            .padding(.bottom, inPlace ? 2 : 8)
        }
    }

    // Layer piles chunked into rows of two for the 2×N band grid (＋ pile trails last).
    private var layerRows: [[LayerPile]] {
        stride(from: 0, to: layers.count, by: 2).map {
            Array(layers[$0 ..< min($0 + 2, layers.count)])
        }
    }

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
                    Button(action: onNewLayer) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Palette.bg)
                            .frame(width: 22, height: 22)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Palette.running))
                    }
                    .buttonStyle(.plain)
                    .help("New layer")
                }
                // Fixed 2-wide grid: layers fill row-major and the ＋ pile trails as the
                // next free cell ([L1][＋] → [L1][L2]/[＋] → …). Eager VStack/HStack — not a
                // lazy grid — so every pile reports its LayerFrameKey for drag hit-testing.
                GeometryReader { geo in
                    let pileW = layerPileWidth(in: geo.size)
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: inPlace ? 6 : 10) {
                            ForEach(layerRows.indices, id: \.self) { r in
                                HStack(alignment: .top, spacing: inPlace ? 6 : 10) {
                                    ForEach(layerRows[r]) { layerPileView($0, mapW: pileW) }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .onPreferenceChange(LayerFrameKey.self) { drag.layerFrames[screenID] = $0 }
                }
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
    private func layerPileView(_ pile: LayerPile, mapW: CGFloat = 104) -> some View {
        let lit = dragOnThisScreen && drag.hoverLayer == pile.id
        let on = lit || pile.staged
        let mapH = layerMapHeight(for: mapW)
        return VStack(spacing: 4) {
            Group {
                if pile.isNew {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(on ? HUDChrome.cyan.opacity(0.9) : Color.white.opacity(0.05))
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
                    .strokeBorder(on ? HUDChrome.cyan : Palette.border, lineWidth: on ? 1.5 : 0.5)
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
                .font(Typo.mono(inPlace ? 8 : 9)).foregroundColor(.white.opacity(on ? 0.9 : 0.65))
                .lineLimit(1).frame(maxWidth: mapW)
            if !inPlace {
                layerPileMeta(pile, active: on, width: mapW)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: pile.stagedCount)
        .scaleEffect(lit ? 1.06 : 1)
        .shadow(color: lit ? HUDChrome.cyan.opacity(0.5) : .clear, radius: lit ? 8 : 0)
        .animation(.spring(response: 0.24, dampingFraction: 0.72), value: lit)
        .background(layerFrameReporter(pile.id))     // hit-test = the compact footprint
        .onHover { hovering in
            if hovering { drag.inspectLayer = pile.id; drag.inspectScreen = screenID }
            else if drag.inspectLayer == pile.id { drag.inspectLayer = nil; drag.inspectScreen = nil }
        }
        .onTapGesture {                                    // ＋ → author a new layer; else open the inspector
            if pile.isNew { onNewLayer() } else { drag.selectedLayer = pile.id }
        }
        .contextMenu { layerPileMenu(pile) }               // right-click → inspect / remove rules, delete layer
    }

    // Right-click menu for a layer pile: see each rule, what it currently matches, and
    // remove it — plus delete the whole layer. The rules are the committed StudioLayer
    // clauses (the same ones the Studio panel and, later, the agent edit). Empty for the
    // ＋ pile (it has no layer yet).
    @ViewBuilder
    private func layerPileMenu(_ pile: LayerPile) -> some View {
        if !pile.isNew {
            Text(pile.name)
            Divider()
            Button("Select matching windows") {
                onRecallLayer(pile.id)
            }
            Divider()
            if pile.clauses.isEmpty {
                Text("No rules")
            } else {
                ForEach(Array(pile.clauses.enumerated()), id: \.offset) { idx, clause in
                    let matches = DesktopModel.shared.allWindows().filter { clause.matches($0) }
                    Menu("\(clauseTitle(clause))  ·  \(matches.count)") {
                        if matches.isEmpty {
                            Text("No live windows match")
                        } else {
                            ForEach(matches.prefix(12), id: \.wid) { w in
                                Text(w.title.isEmpty ? w.app : "\(w.app) — \(w.title)")
                            }
                            if matches.count > 12 { Text("+\(matches.count - 12) more") }
                        }
                        Divider()
                        Button("Remove this rule", role: .destructive) { onRemoveClause(pile.id, idx) }
                    }
                }
            }
            Divider()
            Button("Delete layer “\(pile.name)”", role: .destructive) { onDeleteLayer(pile.id) }
        }
    }

    // A rule clause as a readable menu label.
    private func clauseTitle(_ clause: StudioLayerClause) -> String {
        clause.summary
    }

    private func layerPileMeta(_ pile: LayerPile, active: Bool, width: CGFloat) -> some View {
        HStack(spacing: 4) {
            Image(systemName: pile.isNew ? "plus.square" : "line.3.horizontal.decrease.circle")
                .font(.system(size: 7.5, weight: .semibold))
            if pile.isNew {
                Text("create")
            } else {
                Text("\(pile.clauses.count) rule\(pile.clauses.count == 1 ? "" : "s")")
                if pile.count == 0 {
                    Text("empty")
                        .foregroundColor(Palette.detach.opacity(active ? 0.9 : 0.65))
                }
            }
        }
        .font(Typo.mono(7.5))
        .foregroundColor(active ? Palette.running : .white.opacity(0.38))
        .lineLimit(1)
        .frame(maxWidth: width)
    }

    // MARK: - Layer inspector (click a pile to open)
    //
    // A top-area modal: the layer's match rules on the left, the windows they currently
    // resolve to on the right (a table). Backdrop tap / ✕ / esc closes it. Rules are the
    // committed StudioLayer clauses — editable in place (remove), the live source of truth.
    @ViewBuilder
    private func layerInspector(_ pile: LayerPile) -> some View {
        let allWindows = DesktopModel.shared.allWindows()
        let windows = allWindows.filter { w in pile.clauses.contains { $0.matches(w) } }
        GeometryReader { geo in
            let panelW = min(760, max(440, geo.size.width * 0.55))
            let panelH = min(440, max(260, geo.size.height * 0.52))
            ZStack(alignment: .top) {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { drag.selectedLayer = nil }
                inspectorPanel(pile, windows: windows, allWindows: allWindows)
                    .frame(width: panelW, height: panelH)
                    .padding(.top, max(24, geo.size.height * 0.12))
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func inspectorPanel(_ pile: LayerPile, windows: [WindowEntry], allWindows: [WindowEntry]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(HUDChrome.cyan)
                Text(pile.name).font(Typo.monoBold(14)).foregroundColor(.white)
                Text("\(windows.count) window\(windows.count == 1 ? "" : "s")")
                    .font(Typo.mono(10)).foregroundColor(.white.opacity(0.5))
                Spacer()
                Button {
                    onRecallLayer(pile.id)
                    drag.selectedLayer = nil
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "scope")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Select")
                            .font(Typo.monoBold(10))
                    }
                    .foregroundColor(Palette.bg)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Palette.running))
                }
                .buttonStyle(.plain)
                .disabled(windows.isEmpty)
                .opacity(windows.isEmpty ? 0.4 : 1)
                .help("Select matching windows")
                Button { drag.selectedLayer = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.6)).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Rectangle().fill(Palette.border).frame(height: 0.5)
            inspectorSummary(pile, windows: windows)
            Rectangle().fill(Palette.border).frame(height: 0.5)
            HStack(alignment: .top, spacing: 0) {
                inspectorRules(pile, allWindows: allWindows).frame(width: 240)
                Rectangle().fill(Palette.border).frame(width: 0.5)
                inspectorWindows(windows).frame(maxWidth: .infinity)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.35)))
        )
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.borderLit, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
    }

    private func inspectorSummary(_ pile: LayerPile, windows: [WindowEntry]) -> some View {
        HStack(spacing: 8) {
            inspectorMetric("rules", "\(pile.clauses.count)")
            inspectorMetric("live", "\(windows.count)")
            inspectorMetric("screen", "\(pile.count)")
            Text(pile.rule.isEmpty ? "no rule" : pile.rule)
                .font(Typo.mono(9))
                .foregroundColor(.white.opacity(0.5))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.14))
    }

    private func inspectorMetric(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundColor(.white.opacity(0.38))
            Text(value).foregroundColor(.white.opacity(0.82))
        }
        .font(Typo.monoBold(9))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5))
        )
    }

    // Left column: the layer's match rules, each removable.
    private func inspectorRules(_ pile: LayerPile, allWindows: [WindowEntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("RULES").font(Typo.monoBold(9)).foregroundColor(.white.opacity(0.4)).tracking(0.5)
                Spacer()
                Button {
                    onEditClause(pile.id, nil, StudioLayerClause())
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Palette.bg)
                        .frame(width: 18, height: 18)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Palette.running))
                }
                .buttonStyle(.plain)
                .help("Add rule")
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            Rectangle().fill(Palette.border).frame(height: 0.5)
            if pile.clauses.isEmpty {
                Text("No rules — matches nothing")
                    .font(Typo.mono(11)).foregroundColor(.white.opacity(0.4)).padding(14)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(pile.clauses.enumerated()), id: \.offset) { idx, clause in
                        inspectorRuleRow(clause, count: allWindows.filter { clause.matches($0) }.count) {
                            onEditClause(pile.id, idx, clause)
                        } remove: {
                            onRemoveClause(pile.id, idx)
                        }
                    }
                }
                .padding(12)
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func inspectorRuleRow(
        _ clause: StudioLayerClause,
        count: Int,
        edit: @escaping () -> Void,
        remove: @escaping () -> Void
    ) -> some View {
        return HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                Text(clause.summary)
                    .font(Typo.mono(10))
                    .foregroundColor(clause.not?.isEmpty == false ? Palette.detach : .white.opacity(0.85))
                    .lineLimit(2)
                Text("\(count) live match\(count == 1 ? "" : "es")")
                    .font(Typo.mono(8))
                    .foregroundColor(count == 0 ? Palette.detach.opacity(0.72) : .white.opacity(0.38))
            }
            Spacer(minLength: 4)
            Button(action: edit) {
                Image(systemName: "pencil").font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.45)).contentShape(Rectangle())
            }.buttonStyle(.plain).help("Edit rule")
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.35)).contentShape(Rectangle())
            }.buttonStyle(.plain).help("Remove this rule")
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.border, lineWidth: 0.5))
        )
    }

    // Right column: the windows the rules currently resolve to — a simple app/title table.
    private func inspectorWindows(_ windows: [WindowEntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("APP").frame(width: 84, alignment: .leading)
                Text("WINDOW").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(Typo.monoBold(9)).foregroundColor(.white.opacity(0.4)).tracking(0.5)
            .padding(.horizontal, 14).padding(.vertical, 8)
            Rectangle().fill(Palette.border).frame(height: 0.5)
            if windows.isEmpty {
                Text("No live windows match")
                    .font(Typo.mono(11)).foregroundColor(.white.opacity(0.4)).padding(14)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(windows, id: \.wid) { w in
                            HStack(spacing: 8) {
                                HStack(spacing: 6) {
                                    Circle().fill(Color(nsColor: MotionPanel.tint(for: w.app)))
                                        .frame(width: 6, height: 6)
                                    Text(w.app).font(Typo.mono(10)).foregroundColor(.white.opacity(0.7)).lineLimit(1)
                                }
                                .frame(width: 84, alignment: .leading)
                                Text(w.title.isEmpty ? "—" : w.title)
                                    .font(Typo.mono(10)).foregroundColor(.white.opacity(0.85))
                                    .frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            Rectangle().fill(Palette.border.opacity(0.5)).frame(height: 0.5)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // Map height for a given width — the active screen's aspect, clamped so a very wide
    // or very tall display still reads as a tidy tile.
    private func layerMapHeight(for width: CGFloat) -> CGFloat {
        (width / min(max(screenAspect, 1.2), 2.6)).rounded()
    }

    /// Pile thumbnail width for the Layers grid. In-place mode gives the side column a
    /// lot of horizontal space but a short band — size from the vertical budget so piles
    /// don't spill below the reserved intent zone.
    private func layerPileWidth(in size: CGSize) -> CGFloat {
        let colW = max(52, ((size.width - 10) / 2).rounded())
        guard inPlace else {
            return max(104, min(220, colW))
        }
        let rowCount = CGFloat(max(1, layerRows.count))
        let rowGap: CGFloat = 6
        let labelStack: CGFloat = 22   // name under map (+ spacing); meta hidden in-place
        let hoverPad: CGFloat = 1.08   // pile scaleEffect headroom
        let availH = max(40, size.height)
        let perRowH = (availH - rowGap * (rowCount - 1)) / rowCount
        let mapH = max(22, (perRowH - labelStack) / hoverPad)
        let wFromH = mapH * min(max(screenAspect, 1.2), 2.6)
        return min(colW, wFromH, 132).rounded()
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

    // One window on the Current View map — true fractional size (no 8px floor), with a
    // thumbnail when we have one so the mini-map reads like the desktop, not an abstract grid.
    private func currentViewWindow(_ frac: CGRect, _ tint: Color, _ image: NSImage?,
                                   _ box: CGSize, staged: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
        let w = max(2, frac.width * box.width)
        let h = max(2, frac.height * box.height)
        let r = CGRect(x: frac.minX * box.width, y: frac.minY * box.height, width: w, height: h)
        return ZStack {
            shape.fill(tint.opacity(staged ? 0.42 : 0.22))
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).opacity(staged ? 0.65 : 0.45)
            }
        }
        .frame(width: w, height: h)
        .clipShape(shape)
        .overlay(shape.strokeBorder(staged ? tint : tint.opacity(0.7),
                                    lineWidth: staged ? 1.25 : 0.75))
        .position(x: r.midX, y: r.midY)
    }

    // Visual + hit rects for a layout outline in canvas-local coords. Behind windows peek
    // out from under a front neighbor and get a larger hit pad so stacks stay grabbable.
    private struct LayoutMetrics {
        let visual: CGRect
        let hit: CGRect
    }

    private func layoutMetrics(frac: CGRect, box: CGSize, behind: Bool) -> LayoutMetrics {
        let peek: CGFloat = behind ? 7 : 0
        let minHit: CGFloat = behind ? 28 : 22
        let vw = max(2, frac.width * box.width)
        let vh = max(2, frac.height * box.height)
        let visual = CGRect(x: frac.minX * box.width + peek, y: frac.minY * box.height + peek,
                            width: vw, height: vh)
        let hw = max(minHit, vw)
        let hh = max(minHit, vh)
        let hit = CGRect(x: visual.midX - hw / 2, y: visual.midY - hh / 2, width: hw, height: hh)
        return LayoutMetrics(visual: visual, hit: hit)
    }

    // Cross-link: hover from Current View or the survey lattice, plus any plucked picks.
    private var activeLinkWid: UInt32? {
        drag.hoverLayoutWid ?? drag.hoverSurveyWid
    }

    private var peekWids: Set<UInt32> {
        var s = pickedWids
        if let w = activeLinkWid { s.insert(w) }
        return s
    }

    /// Survey dim/highlight — layer-roster preview takes priority, then cross-link peeks.
    private var surveyHighlightWids: Set<UInt32>? {
        if let layer = highlightWids { return layer }
        if !peekWids.isEmpty { return peekWids }
        return nil
    }

    // Screenshot peek inside a layout footprint — shown when linked from either direction.
    private func layoutPeekCard(_ rect: CGRect, _ tint: Color, _ image: NSImage?,
                                picked: Bool, hovered: Bool, behind: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
        let stroke: Color = picked ? Palette.running : (hovered ? .white : HUDChrome.cyan)
        let lineW: CGFloat = picked || hovered ? 2 : 1.5
        return ZStack {
            shape.fill(Color.black.opacity(0.25))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .opacity(0.94)
            } else {
                shape.fill(tint.opacity(0.35))
            }
            shape.strokeBorder(stroke, lineWidth: lineW)
        }
        .frame(width: rect.width, height: rect.height)
        .clipShape(shape)
        .shadow(color: tint.opacity(0.55), radius: hovered ? 8 : 5)
        .scaleEffect(hovered ? 1.07 : 1.03, anchor: .center)
        .position(x: rect.midX, y: rect.midY)
    }

    // Hollow footprint drawn at a canvas-local rect.
    private func currentViewOutlineAt(_ rect: CGRect, _ tint: Color,
                                      picked: Bool, hovered: Bool, dragged: Bool, behind: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
        let stroke: Color = dragged ? HUDChrome.cyan
            : (picked ? Palette.running : (hovered ? .white : tint))
        let lineW: CGFloat = dragged ? 2 : (picked || hovered ? 1.75 : (behind ? 0.75 : 1))
        let fillOpacity = dragged ? 0.16 : (picked ? 0.12 : (hovered ? 0.09 : (behind ? 0.02 : 0.05)))
        let strokeOpacity = dragged ? 1.0 : (behind ? 0.5 : (hovered ? 1.0 : 0.82))
        return shape
            .fill(tint.opacity(fillOpacity))
            .overlay(
                shape.stroke(
                    stroke.opacity(strokeOpacity),
                    style: StrokeStyle(lineWidth: lineW, dash: behind ? [4, 3] : [])
                )
            )
            .shadow(color: dragged ? HUDChrome.cyan.opacity(0.4)
                    : (hovered ? tint.opacity(0.35) : .clear),
                    radius: dragged ? 5 : (hovered ? 4 : 0))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }

    // Expanded invisible pad + visual outline + grab affordance. The pad is what you
    // actually hit — tiny quarter-tiles on the mini-map would otherwise be un-grabbable.
    private func layoutOutlineInteractive(_ m: LayerMember, box: CGSize) -> some View {
        let metrics = layoutMetrics(frac: m.frac, box: box, behind: m.behind)
        let hovered = drag.hoverLayoutWid == m.id
        let linked = activeLinkWid == m.id
        let picked = pickedWids.contains(m.id)
        let peeking = peekWids.contains(m.id)
        let lifted = drag.wid == m.id && drag.screenID == screenID
        return ZStack {
            Color.white.opacity(0.001)
                .frame(width: metrics.hit.width, height: metrics.hit.height)
                .contentShape(Rectangle())
                .position(x: metrics.hit.midX, y: metrics.hit.midY)
                .highPriorityGesture(TapGesture().onEnded { onPick(m.id) })
                .gesture(layoutDragGesture(m))
            Group {
                if peeking && !lifted {
                    layoutPeekCard(metrics.visual, m.tint, m.image,
                                   picked: picked, hovered: hovered || linked, behind: m.behind)
                } else {
                    currentViewOutlineAt(metrics.visual, m.tint,
                                         picked: picked, hovered: hovered, dragged: lifted, behind: m.behind)
                        .scaleEffect(hovered && !lifted ? 1.06 : 1, anchor: .center)
                }
            }
            .animation(.spring(response: 0.2, dampingFraction: 0.72), value: peeking)
            if hovered && !lifted && !drag.isActive && !peeking {
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.45), radius: 2)
                    .position(x: metrics.visual.midX, y: metrics.visual.midY)
                    .allowsHitTesting(false)
            }
        }
        .opacity(lifted ? 0.3 : (m.behind && !peeking ? 0.72 : 1))
        .overlay {
            if lifted {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.25, dash: [4, 3]))
                    .foregroundColor(HUDChrome.cyan.opacity(0.85))
                    .frame(width: metrics.visual.width, height: metrics.visual.height)
                    .position(x: metrics.visual.midX, y: metrics.visual.midY)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topLeading) {
            if picked, let slot = pickSlot(for: m.id), !lifted {
                Text("\(slot)")
                    .font(Typo.monoBold(8))
                    .foregroundColor(Palette.bg)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Capsule().fill(Palette.running))
                    .position(x: metrics.visual.minX + 10, y: metrics.visual.minY + 8)
                    .allowsHitTesting(false)
            }
        }
        .zIndex(peeking ? 100 : (hovered || picked ? 10 : (m.behind ? 0 : 1)))
        .onHover { over in
            if over {
                drag.hoverLayoutWid = m.id
                if !drag.isActive { NSCursor.openHand.push() }
            } else {
                if drag.hoverLayoutWid == m.id { drag.hoverLayoutWid = nil }
                if !drag.isActive { NSCursor.pop() }
            }
        }
        .contextMenu {
            if inPlace, let t = tileForWid(m.id) { inPlaceTileMenu(t) }
        }
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

    /// Current View highlights while hovering an outline or a linked survey tile.
    private var currentViewFocused: Bool {
        drag.inspectCurrentView && drag.inspectScreen == screenID
            || drag.hoverLayoutWid != nil
            || drag.hoverSurveyWid != nil
    }

    /// In-place shortcut rails: on hover, or pinned while windows are selected.
    private var inPlaceCommandsVisible: Bool {
        showInPlaceCommands || !pickedOrder.isEmpty
    }

    private var currentViewSub: String {
        if drag.isActive, drag.screenID == screenID {
            let n = drag.dragWids.count
            if drag.hoverGrid || drag.hoverCell != nil {
                return n > 1 ? "release \(n) on cell" : "release on cell"
            }
            return n > 1 ? "drag \(n) to grid →" : "drag to grid →"
        }
        if !pickedOrder.isEmpty { return "\(pickedOrder.count) selected" }
        if inPlace { return inPlaceCommandsVisible ? "shortcuts" : "hover for shortcuts" }
        return "click or a–z to select"
    }

    // The Current View section (middle): a screen-map of this display's windows at their
    // real positions. Tap two to swap; drag an outline into Grid to stage a cell.
    private var currentViewSection: some View {
        sectionCard(title: "Current View", icon: "rectangle.on.rectangle",
                    sub: currentViewSub,
                    live: true, armed: currentViewFocused || (drag.isActive && drag.dragSource == .currentView)) {
            if inPlace {
                HStack(alignment: .center, spacing: inPlaceCommandsVisible ? 4 : 0) {
                    if inPlaceCommandsVisible {
                        inPlaceCommandRail(.leading)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    currentLayoutCanvas
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if inPlaceCommandsVisible {
                        inPlaceCommandRail(.trailing)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .animation(.easeOut(duration: 0.16), value: inPlaceCommandsVisible)
                .onHover { hovering in
                    showInPlaceCommands = hovering
                }
            } else {
                currentLayoutCanvas
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // Screen-map canvas: always hollow outlines at each window's live fractional rect —
    // a wireframe of the desktop (including stacked-behind windows as dashed footprints).
    private var currentLayoutCanvas: some View {
        let focused = currentViewFocused
        let showHint = !inPlace && focused && activeLinkWid == nil && pickedWids.isEmpty && !drag.isActive
        let showHoverCue = inPlace && !inPlaceCommandsVisible && !drag.isActive
        return GeometryReader { geo in
            let box = aspectFit(in: geo.size, aspect: screenAspect)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.black.opacity(0.38))
                ForEach(currentLayout) { m in
                    layoutOutlineInteractive(m, box: box)
                }
                if showHoverCue {
                    HStack(spacing: 4) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 8, weight: .semibold))
                        Text("hover for shortcuts")
                            .font(Typo.mono(9))
                    }
                    .foregroundColor(.white.opacity(0.38))
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.32)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 6)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
                if showHint {
                    Text("click windows to select")
                        .font(Typo.monoBold(8))
                        .foregroundColor(.white.opacity(0.45))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Capsule().fill(Color.black.opacity(0.35)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 5)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: box.width, height: box.height)
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(focused ? HUDChrome.cyan : Palette.border, lineWidth: focused ? 1.5 : 0.5)
            )
            .scaleEffect(focused ? 1.03 : 1)
            .shadow(color: focused ? HUDChrome.cyan.opacity(0.45) : .clear, radius: focused ? 8 : 0)
            .animation(.spring(response: 0.24, dampingFraction: 0.72), value: focused)
            .background(
                GeometryReader { g in
                    Color.clear.preference(key: CurrentViewFrameKey.self,
                                           value: g.frame(in: .named(ExposeView.rootSpace)))
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onHover { hovering in
                if hovering {
                    drag.inspectCurrentView = true
                    drag.inspectScreen = screenID
                } else if drag.inspectScreen == screenID {
                    drag.inspectCurrentView = false
                    drag.inspectScreen = nil
                    drag.hoverLayoutWid = nil
                }
            }
        }
        .onPreferenceChange(CurrentViewFrameKey.self) { drag.currentViewFrames[screenID] = $0 }
    }

    // The Grid section (right): a resolution selector above a grid of drop positions.
    // Dropping a window on a cell stages that position.
    private var gridSection: some View {
        let draggingHere = dragOnThisScreen && drag.isActive
        let dragN = drag.dragWids.count
        let sub: String = {
            guard draggingHere else { return "drop a position" }
            if drag.hoverCell != nil {
                return dragN > 1 ? "release \(dragN) here" : "release here"
            }
            if drag.hoverGrid { return dragN > 1 ? "pick anchor cell" : "pick a cell" }
            return dragN > 1 ? "drop \(dragN) here" : "drop here"
        }()
        let armed = dragOnThisScreen && drag.isActive && (drag.hoverCell != nil || drag.hoverGrid)
        return sectionCard(title: "Grid", icon: "rectangle.split.2x2", sub: sub,
                    live: true, armed: armed) {
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
    // "fullscreen". Modifiers override it live mid-drag (⇧ halves · ⌥ thirds · ⌘ fine ·
    // ⌃ dense); releasing returns to the selection. A name readout sits at the trailing edge.
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
        case .dense:   return "⌃"
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
            let warm = active && drag.hoverGrid && drag.hoverCell == nil
            VStack(spacing: 3) {
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: 3) {
                        ForEach(0..<cols, id: \.self) { c in
                            let lit = active && drag.hoverCell == HoverCell(col: c, row: r)
                            gridCell(lit: lit, warm: warm,
                                     w: max(8, cw - 3), h: max(8, ch - 3))
                        }
                    }
                }
            }
            // Glide the highlight between cells instead of snapping.
            .animation(.spring(response: 0.24, dampingFraction: 0.72), value: drag.hoverCell)
            .frame(width: box.width, height: box.height)
            .clipped()
            .background(                                          // measure the fixed grid box…
                GeometryReader { g in
                    Color.clear.preference(key: LatticeFrameKey.self,
                                           value: g.frame(in: .named(ExposeView.rootSpace)))
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)   // …then center it in the section
            .clipped()
        }
        .onPreferenceChange(LatticeFrameKey.self) { drag.latticeFrames[screenID] = $0 }
    }

    // One drop-grid cell — a plain target that lights under the cursor. The actual
    // placement preview now renders in the middle Preview canvas, not in the cell.
    private func gridCell(lit: Bool, warm: Bool, w: CGFloat, h: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        let fill = lit ? Palette.running.opacity(0.32)
            : (warm ? Palette.running.opacity(0.12) : Color.white.opacity(0.05))
        let stroke = lit ? Palette.running : (warm ? Palette.running.opacity(0.45) : Palette.border)
        return shape
            .fill(fill)
            .overlay(shape.strokeBorder(stroke, lineWidth: lit ? 1.5 : (warm ? 1 : 0.5)))
            .frame(width: w, height: h)
            .scaleEffect(lit ? 1.08 : (warm ? 1.02 : 1))
            .shadow(color: lit ? Palette.running.opacity(0.55)
                    : (warm ? Palette.running.opacity(0.2) : .clear),
                    radius: lit ? 9 : (warm ? 4 : 0))
            .zIndex(lit ? 1 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: lit)
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
        sectionCard(title: title, icon: icon, sub: sub, live: live, armed: armed,
                    trailing: { EmptyView() }, content: content)
    }

    private func sectionCard<Content: View, Trailing: View>(title: String, icon: String, sub: String,
                                            live: Bool, armed: Bool = false,
                                            @ViewBuilder trailing: () -> Trailing,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(live ? 0.85 : 0.5))
                Text(title)
                    .font(Typo.monoBold(11)).foregroundColor(.white).tracking(0.3)
                Text(sub)
                    .font(Typo.mono(8.5)).foregroundColor(armed ? HUDChrome.cyan : Palette.textMuted)
                Spacer(minLength: 0)
                trailing()
            }
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .padding(.horizontal, inPlace ? 8 : 12).padding(.top, inPlace ? 7 : 9).padding(.bottom, inPlace ? 6 : 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)                                  // frosted glass — opacity + blur, no colour wash
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(armed ? HUDChrome.cyan.opacity(0.10) : Color.white.opacity(0.02)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(armed ? HUDChrome.cyan.opacity(0.5) : Palette.borderLit, lineWidth: armed ? 1.5 : 1)
        )
        .shadow(color: armed ? HUDChrome.cyan.opacity(0.22) : Color.black.opacity(0.3), radius: armed ? 12 : 14, y: 6)
        .animation(.easeOut(duration: 0.16), value: armed)
    }

    // The dragged thumbnail, following the cursor on the owning screen only. Over a
    // live drop target (a grid cell or a layer pile) it shrinks — a clear "about to
    // land here" tell that also previews how small the window reads in the target.
    @ViewBuilder
    private var ghostOverlay: some View {
        if drag.isActive, drag.screenID == screenID, drag.image != nil || drag.ghostTint != nil {
            let armed = drag.hoverCell != nil || drag.hoverLayer != nil
            let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
            Group {
                if let img = drag.image {
                    Image(nsImage: img)
                        .resizable().aspectRatio(contentMode: .fill)
                } else if let tint = drag.ghostTint {
                    ZStack {
                        shape.fill(tint.opacity(0.38))
                        Image(systemName: "arrow.up.forward")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
            }
            .frame(width: drag.tileSize.width, height: drag.tileSize.height)
            .clipShape(shape)
            .overlay(shape.strokeBorder(armed ? HUDChrome.cyan : Palette.running, lineWidth: armed ? 2.5 : 2))
            .shadow(color: .black.opacity(armed ? 0.6 : 0.5), radius: armed ? 10 : 16, x: 0, y: armed ? 4 : 8)
            .scaleEffect(armed ? 0.62 : 1, anchor: .center)
            .opacity(armed ? 1 : 0.92)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: armed)
            .overlay(alignment: .topTrailing) {
                if drag.dragWids.count > 1 {
                    Text("\(drag.dragWids.count)")
                        .font(Typo.monoBold(10))
                        .foregroundColor(Palette.bg)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Capsule().fill(Palette.running))
                        .offset(x: 8, y: -8)
                }
            }
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
        if f.contains(.control) { return .dense }
        if f.contains(.command) { return .fine }
        if f.contains(.option)  { return .thirds }
        if f.contains(.shift)   { return .halves }
        return nil
    }

    private func handleDragChange(_ t: Tile, tileWidth: CGFloat, _ v: DragGesture.Value) {
        handleDragChange(wid: t.id, image: t.image, source: .survey,
                         tileW: tileWidth, tileH: (tileWidth * 0.62).rounded(), v)
    }

    private func popDragCursor() {
        NSCursor.pop()
    }

    private func layoutDragGesture(_ m: LayerMember) -> some Gesture {
        let ghostW: CGFloat = 72
        let ghostH = (ghostW * 0.62).rounded()
        return DragGesture(minimumDistance: 10, coordinateSpace: .named(ExposeView.rootSpace))
            .onChanged { handleDragChange(wid: m.id, image: m.image, ghostTint: m.tint,
                                          source: .currentView, tileW: ghostW, tileH: ghostH, $0) }
            .onEnded { handleLayoutDragEnd(m, $0) }
    }

    private func dragWidsFor(_ wid: UInt32) -> [UInt32] {
        if pickedWids.contains(wid), pickedOrder.count >= 2 { return pickedOrder }
        return [wid]
    }

    private func handleDragChange(wid: UInt32, image: NSImage?, ghostTint: Color? = nil,
                                  source: HyperspaceDrag.DragSource,
                                  tileW: CGFloat, tileH: CGFloat, _ v: DragGesture.Value) {
        drag.location = v.location
        let dist = hypot(v.translation.width, v.translation.height)
        if drag.wid == nil {
            guard dist >= 10 else { return }
            drag.wid = wid
            drag.dragWids = dragWidsFor(wid)
            drag.image = image
            drag.ghostTint = image == nil ? ghostTint : nil
            drag.screenID = screenID
            drag.dragSource = source
            drag.tileSize = CGSize(width: tileW, height: tileH)
            if source == .currentView {
                NSCursor.pop()                 // openHand from hover
                NSCursor.closedHand.push()
            }
        }
        drag.res = Self.modifierRes() ?? drag.baseRes
        updateHoverCell()
        updateHoverCurrentView()
        updateHoverLayer()
    }

    private func handleLayoutDragEnd(_ m: LayerMember, _ v: DragGesture.Value) {
        handleDragEnd(wid: m.id, source: .currentView, onTap: { onPick(m.id) }, v)
    }

    private func handleDragEnd(_ t: Tile, _ v: DragGesture.Value) {
        handleDragEnd(wid: t.id, source: .survey, onTap: { onPick(t.id) }, v)
    }

    private func handleDragEnd(wid: UInt32, source: HyperspaceDrag.DragSource,
                               onTap: () -> Void, _ v: DragGesture.Value) {
        let dist = hypot(v.translation.width, v.translation.height)
        let wasDragging = drag.wid != nil
        let dragWids = drag.dragWids.isEmpty ? [wid] : drag.dragWids
        // Resolve the drop target before reset() clears the hover state. Priority:
        // Grid cell → layer pile → miss.
        var gridCell: HoverCell?
        var pulseFrame: CGRect?
        if wasDragging,
           let frame = drag.latticeFrames[screenID], frame.contains(v.location),
           let cell = drag.hoverCell {
            gridCell = cell
            let (cols, rows) = drag.res.dims
            let cw = frame.width / CGFloat(cols), ch = frame.height / CGFloat(rows)
            if dragWids.count > 1,
               let cells = balancedGridCells(count: dragWids.count, latticeCols: cols, latticeRows: rows,
                                             anchorCol: cell.col, anchorRow: cell.row),
               let last = cells.last {
                let spanCols = last.col - cell.col + 1
                let spanRows = last.row - cell.row + 1
                pulseFrame = CGRect(x: frame.minX + CGFloat(cell.col) * cw,
                                    y: frame.minY + CGFloat(cell.row) * ch,
                                    width: cw * CGFloat(spanCols), height: ch * CGFloat(spanRows))
            } else {
                pulseFrame = CGRect(x: frame.minX + CGFloat(cell.col) * cw,
                                    y: frame.minY + CGFloat(cell.row) * ch, width: cw, height: ch)
            }
        }
        let layerKey = (wasDragging && gridCell == nil) ? drag.hoverLayer : nil
        let dropRes = drag.res
        if let layerKey { pulseFrame = drag.layerFrames[screenID]?[layerKey] }
        let fromLayout = drag.dragSource == .currentView
        drag.reset()
        if fromLayout { popDragCursor() }
        if !wasDragging && dist < 12 {
            onTap()
        } else if let layerKey {
            for w in dragWids { onDropLayer(w, layerKey) }
            if let pulseFrame { drag.firePulse(at: pulseFrame) }
        } else if let cell = gridCell {
            if dragWids.count > 1 {
                onDropGridGroup(dragWids, dropRes, cell)
            } else {
                let (cols, rows) = dropRes.dims
                let spec = GridPlacement(columns: cols, rows: rows, column: cell.col, row: cell.row).map(PlacementSpec.grid)
                onDrop(wid, spec)
            }
            if let pulseFrame { drag.firePulse(at: pulseFrame) }
        } else {
            onDrop(wid, nil)
        }
    }

    private func updateHoverCurrentView() {
        guard let frame = drag.currentViewFrames[screenID], frame.width > 1 else {
            if drag.hoverCurrentView { drag.hoverCurrentView = false }
            return
        }
        let hit = frame.contains(drag.location)
        if drag.hoverCurrentView != hit { drag.hoverCurrentView = hit }
    }

    private func updateHoverLayer() {
        let frames = drag.layerFrames[screenID] ?? [:]
        let hit = frames.first { $0.value.width > 1 && $0.value.contains(drag.location) }?.key
        if drag.hoverLayer != hit { drag.hoverLayer = hit }
    }

    private func updateHoverCell() {
        guard let frame = drag.latticeFrames[screenID], frame.width > 1 else {
            if drag.hoverCell != nil { drag.hoverCell = nil }
            if drag.hoverGrid { drag.hoverGrid = false }
            return
        }
        // Forgiving hit: pad the grid bounds so you don't have to thread the needle.
        let pad: CGFloat = drag.isActive ? 14 : 0
        let hitFrame = frame.insetBy(dx: -pad, dy: -pad)
        guard hitFrame.contains(drag.location) else {
            if drag.hoverCell != nil { drag.hoverCell = nil }
            if drag.hoverGrid { drag.hoverGrid = false }
            return
        }
        if !drag.hoverGrid { drag.hoverGrid = true }
        let (cols, rows) = drag.res.dims
        let cw = frame.width / CGFloat(cols)
        let ch = frame.height / CGFloat(rows)
        // Snap to the nearest cell center — more forgiving than strict rect partitions.
        var bestCol = 0
        var bestRow = 0
        var bestDist = CGFloat.infinity
        for r in 0..<rows {
            for c in 0..<cols {
                let cx = frame.minX + (CGFloat(c) + 0.5) * cw
                let cy = frame.minY + (CGFloat(r) + 0.5) * ch
                let d = hypot(drag.location.x - cx, drag.location.y - cy)
                if d < bestDist { bestDist = d; bestCol = c; bestRow = r }
            }
        }
        let cell = HoverCell(col: bestCol, row: bestRow)
        if drag.hoverCell != cell { drag.hoverCell = cell }
    }

    private func clusterBox(_ c: Cluster) -> some View {
        let expanded = isExpandedTerminalCluster(c)
        let shown = filteredTiles(in: c)
        let localTile = clusterTileWidth(c)
        let cap = clusterColumnCap(c)
        let cols = min(max(shown.count, 1), cap)
        let innerW = localTile * CGFloat(cols) + 8 * CGFloat(max(0, cols - 1))
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
                        .help("Select the whole \(c.name) group")
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
                if expanded {
                    Text("\(c.tiles.count)")
                        .font(Typo.monoBold(8))
                        .tracking(0.6)
                        .foregroundColor(HUDChrome.cyan.opacity(0.9))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(HUDChrome.cyan.opacity(0.10))
                                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(HUDChrome.cyan.opacity(0.35), lineWidth: 0.5))
                        )
                        .help("\(c.tiles.count) windows in this terminal group")
                }
                Spacer(minLength: 16)
                Text(c.userDefined ? "you" : "smart")
                    .font(Typo.mono(8))
                    .tracking(0.6)
                    .foregroundColor(c.userDefined ? Palette.running : Palette.textMuted)
            }
            if expanded {
                clusterSearchBar(c, visibleCount: shown.count)
                    .frame(width: innerW, alignment: .leading)
            }
            FlowLayout(spacing: 8, lineSpacing: 8) {
                if shown.isEmpty {
                    emptyClusterSearchState(c)
                } else {
                    ForEach(shown) { tileView($0, width: localTile) }
                }
            }
            .frame(maxWidth: innerW, alignment: .leading)
        }
        .padding(.horizontal, 11).padding(.top, 9).padding(.bottom, 11)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.white.opacity(expanded ? 0.032 : (c.userDefined ? 0.03 : 0.018)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(expanded ? HUDChrome.cyan.opacity(0.30) : (c.userDefined ? Palette.borderLit : Palette.border),
                              lineWidth: expanded ? 1.15 : 1)
        )
    }

    private func isExpandedTerminalCluster(_ c: Cluster) -> Bool {
        guard c.tiles.count >= 10 else { return false }
        let needles = ["iterm", "terminal", "warp", "ghostty", "wezterm", "kitty", "alacritty"]
        let clusterName = c.name.lowercased()
        return needles.contains { needle in
            clusterName.contains(needle) ||
                c.tiles.contains { $0.app.lowercased().contains(needle) }
        }
    }

    private func clusterColumnCap(_ c: Cluster) -> Int {
        if isExpandedTerminalCluster(c) { return layoutTall ? 3 : 6 }
        return colCap
    }

    private func clusterTileWidth(_ c: Cluster) -> CGFloat {
        guard isExpandedTerminalCluster(c) else { return tile }
        return min((tile * 1.16).rounded(), tile + 36)
    }

    private func filteredTiles(in c: Cluster) -> [Tile] {
        let q = c.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return c.tiles }
        return c.tiles.filter { tileMatchesClusterSearch($0, query: q) }
    }

    private func tileMatchesClusterSearch(_ t: Tile, query: String) -> Bool {
        let terms = query.lowercased().split(whereSeparator: { $0.isWhitespace })
        guard !terms.isEmpty else { return true }
        let haystack = "\(t.title) \(t.app) \(t.hint)".lowercased()
        return terms.allSatisfy { haystack.range(of: String($0)) != nil }
    }

    private func clusterSearchBar(_ c: Cluster, visibleCount: Int) -> some View {
        let active = c.searchActive
        let query = c.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        return HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(active ? HUDChrome.cyan : Palette.textMuted)
            Text(query.isEmpty ? "filter \(c.name)" : query)
                .font(Typo.mono(10))
                .foregroundColor(query.isEmpty ? Palette.textMuted : Palette.text)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if !query.isEmpty {
                Text("\(visibleCount)/\(c.tiles.count)")
                    .font(Typo.monoBold(8))
                    .foregroundColor(visibleCount > 0 ? HUDChrome.cyan.opacity(0.9) : Palette.detach)
                Button { onClearClusterSearch(c.id) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Palette.textMuted)
                }
                .buttonStyle(.plain)
            } else if active {
                Text("typing")
                    .font(Typo.monoBold(8))
                    .foregroundColor(HUDChrome.cyan.opacity(0.8))
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(
            shape.fill(Color.black.opacity(active ? 0.34 : 0.24))
                .overlay(shape.strokeBorder(active ? HUDChrome.cyan.opacity(0.55) : Color.white.opacity(0.12), lineWidth: 0.75))
        )
        .contentShape(Rectangle())
        .onTapGesture { onBeginClusterSearch(c.id) }
        .help("Click, type to filter \(c.name), Return selects matches")
    }

    private func emptyClusterSearchState(_ c: Cluster) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
            Text("no matches")
                .font(Typo.mono(10))
        }
        .foregroundColor(Palette.textMuted)
        .frame(width: clusterTileWidth(c), height: (clusterTileWidth(c) * 0.62).rounded())
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.035))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), style: StrokeStyle(lineWidth: 0.75, dash: [4, 4])))
        )
    }

    private func tileForWid(_ wid: UInt32) -> Tile? {
        clusters.flatMap(\.tiles).first { $0.id == wid }
    }

    // Hyper+G inventory / Current View menu — selection-aware actions, not just placements.
    @ViewBuilder
    private func inPlaceTileMenu(_ t: Tile) -> some View {
        inPlaceSelectionActions(t)
        Divider()
        Button { onFocusWindow(t.id) } label: {
            Label("Focus on Desktop", systemImage: "macwindow.on.rectangle")
        }
        Divider()
        inPlacePlacementMenus(t)
        inPlaceLayerMenu(t)
        Divider()
        Button { onOpenHyperspace() } label: {
            Label("Open Hyperspace Survey", systemImage: "rectangle.on.rectangle.angled")
        }
    }

    @ViewBuilder
    private func inPlaceSelectionActions(_ t: Tile) -> some View {
        let picked = t.pickSlot != nil
        let pickCount = pickedWids.count
        Button { onPick(t.id) } label: {
            Label(picked ? "Deselect" : "Select", systemImage: picked ? "minus.circle" : "plus.circle")
        }
        if pickCount > 0 {
            Divider()
            Button { onGridSelection() } label: {
                Label(pickCount >= 2 ? "Grid \(pickCount) Windows" : "Grid Selection",
                      systemImage: "square.grid.2x2")
            }
            .disabled(pickCount < 2)
            if pickCount >= 2 {
                Button { onSwapFirstTwo() } label: {
                    Label("Swap First Two (S)", systemImage: "arrow.left.arrow.right")
                }
            }
            inPlaceSwapWithMenu(t)
            Button(role: .destructive) { onClearSelection() } label: {
                Label("Clear Selection", systemImage: "xmark.circle")
            }
        }
    }

    @ViewBuilder
    private func inPlaceSwapWithMenu(_ t: Tile) -> some View {
        let picked = t.pickSlot != nil
        let others = pickedOrder.filter { $0 != t.id }
        if picked, !others.isEmpty {
            Menu("Swap with…", systemImage: "arrow.triangle.swap") {
                ForEach(others, id: \.self) { wid in
                    Button(tileForWid(wid)?.app ?? "Window") { onSwapWith(t.id, wid) }
                }
            }
        }
    }

    @ViewBuilder
    private func inPlacePlacementMenus(_ t: Tile) -> some View {
        Button { onFillAvailable(t.id) } label: {
            Label("Fill Available Space (F)", systemImage: "arrow.up.backward.and.arrow.down.forward")
        }
        Menu("Apply Now", systemImage: "arrow.up.left.and.arrow.down.right") {
            placementQuickItems(wid: t.id, handler: onApplyPlacement)
        }
        Menu("Stage for Enter", systemImage: "clock.badge.checkmark") {
            Button { drag.beginPlacing(t.id, on: screenID) } label: {
                Label("Place…", systemImage: "rectangle.dashed")
            }
            Divider()
            placementQuickItems(wid: t.id) { wid, spec in onDrop(wid, spec) }
        }
    }

    @ViewBuilder
    private func inPlaceLayerMenu(_ t: Tile) -> some View {
        Divider()
        Menu("Add to Layer", systemImage: "square.stack.3d.up") {
            Button("New Layer") { onNewLayer() }
            let joinable = layers.filter { !$0.isNew }
            if !joinable.isEmpty {
                Divider()
                ForEach(joinable) { p in
                    Button(p.name) { onDropLayer(t.id, p.id) }
                }
            }
        }
    }

    @ViewBuilder
    private func placementQuickItems(wid: UInt32,
                                     handler: @escaping (UInt32, PlacementSpec) -> Void) -> some View {
        Button("Left Half")   { handler(wid, GridPlacement(columns: 2, rows: 1, column: 0, row: 0).map(PlacementSpec.grid)!) }
        Button("Right Half")  { handler(wid, GridPlacement(columns: 2, rows: 1, column: 1, row: 0).map(PlacementSpec.grid)!) }
        Button("Top Half")    { handler(wid, GridPlacement(columns: 1, rows: 2, column: 0, row: 0).map(PlacementSpec.grid)!) }
        Button("Bottom Half") { handler(wid, GridPlacement(columns: 1, rows: 2, column: 0, row: 1).map(PlacementSpec.grid)!) }
        Menu("Quarter") {
            Button("Top Left")     { handler(wid, GridPlacement(columns: 2, rows: 2, column: 0, row: 0).map(PlacementSpec.grid)!) }
            Button("Top Right")    { handler(wid, GridPlacement(columns: 2, rows: 2, column: 1, row: 0).map(PlacementSpec.grid)!) }
            Button("Bottom Left")  { handler(wid, GridPlacement(columns: 2, rows: 2, column: 0, row: 1).map(PlacementSpec.grid)!) }
            Button("Bottom Right") { handler(wid, GridPlacement(columns: 2, rows: 2, column: 1, row: 1).map(PlacementSpec.grid)!) }
        }
        Button("Maximize") { handler(wid, GridPlacement(columns: 1, rows: 1, column: 0, row: 0).map(PlacementSpec.grid)!) }
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
        placementQuickItems(wid: t.id) { wid, spec in onDrop(wid, spec) }
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

    private func tileView(_ t: Tile, width: CGFloat? = nil) -> some View {
        let w = width ?? tile
        let h = (w * 0.62).rounded()
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let picked = t.pickSlot != nil
        let staged = t.staged != nil || !t.layerTags.isEmpty
        let beingDragged = drag.wid == t.id && drag.screenID == screenID
        // Cross-link + layer roster: highlighted tiles pop, the rest sink.
        let inHighlight = surveyHighlightWids?.contains(t.id)
        let highlightLit = inHighlight == true
        let highlightDimmed = inHighlight == false && surveyHighlightWids != nil
        let crossLinked = activeLinkWid == t.id
        let lit = t.isAimed || picked || highlightLit
        let strokeColor: Color = staged ? HUDChrome.cyan
            : (crossLinked ? HUDChrome.cyan
               : (picked ? HUDChrome.cyan : (highlightLit ? Palette.running
                  : (t.isAimed ? Color.white.opacity(0.9) : Color.white.opacity(0.1)))))
        let strokeW: CGFloat = staged ? 2
            : (crossLinked ? 2.5 : (picked || highlightLit ? 2 : (t.isAimed ? 1.5 : 0.75)))
        let veil: Double = highlightLit || lit ? 0 : spotlight * 0.5
        let bloom: Color = t.isAimed ? lightColor.opacity(0.7 * spotlight) : .clear
        let bloomR: CGFloat = t.isAimed ? 8 + spotlight * 22 : 0
        return tileBody(t, w: w, h: h, shape: shape)
            .overlay(shape.fill(Color.black.opacity(veil)))    // spotlight: off-stage tiles sink to shadow
            .overlay(shape.strokeBorder(strokeColor, lineWidth: strokeW))
            .overlay(alignment: .topTrailing) { hintChip(t) }
            .overlay(alignment: .topLeading) { if let s = t.pickSlot { slotBadge(s, HUDChrome.cyan) } }
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
            .overlay {
                if crossLinked {
                    shape.strokeBorder(HUDChrome.cyan, lineWidth: 2.5)
                        .shadow(color: HUDChrome.cyan.opacity(0.55), radius: 10)
                } else if highlightLit {
                    shape.strokeBorder(Palette.running, lineWidth: 2)
                }
            }
            .scaleEffect(crossLinked ? 1.05 : 1, anchor: .center)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: crossLinked)
            // While this tile is the one being dragged, hollow it out so it keeps its
            // slot (no reflow) but reads as "lifted" — the ghost is what moves.
            .opacity(beingDragged ? 0.22 : (highlightDimmed ? 0.26 : 1))
            .overlay {
                if beingDragged {
                    shape.strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .foregroundColor(HUDChrome.cyan.opacity(0.8))
                }
            }
            .background(frameReporter(t.id))
            .shadow(color: .black.opacity(picked ? 0.5 : 0.35), radius: picked ? 14 : 8, x: 0, y: 5)
            .shadow(color: crossLinked ? HUDChrome.cyan.opacity(0.6)
                    : (highlightLit ? Palette.running.opacity(0.45) : bloom),
                    radius: crossLinked ? 16 : (highlightLit ? 14 : bloomR))
            .contentShape(Rectangle())
            .onHover { over in
                guard !drag.isActive else { return }
                if over {
                    drag.hoverSurveyWid = t.id
                } else if drag.hoverSurveyWid == t.id {
                    drag.hoverSurveyWid = nil
                }
            }
            // Right-click → a menu of options (not a surprise action). Quick tile presets stage
            // immediately; "Place…" opens the life-size stage for a visual pick.
            .contextMenu { tileMenu(t) }
            .highPriorityGesture(TapGesture().onEnded { onPick(t.id) })
            .gesture(
                DragGesture(minimumDistance: 10, coordinateSpace: .named(ExposeView.rootSpace))
                    .onChanged { handleDragChange(t, tileWidth: w, $0) }
                    .onEnded { handleDragEnd(t, $0) }
            )
    }

    private func stagedBadge(_ text: String) -> some View {
        Text(text)
            .font(Typo.monoBold(9))
            .foregroundColor(HUDChrome.onSignal)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill(HUDChrome.cyan))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5))
            .padding(5)
    }

    // The tile's image + app-tint accent, clipped to the rounded card.
    private func tileBody(_ t: Tile, w: CGFloat, h: CGFloat, shape: RoundedRectangle) -> some View {
        ZStack(alignment: .topLeading) {
            ZStack {
                Color.white.opacity(0.04)
                if let img = t.image {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                }
            }
            .frame(width: w, height: h)
            .clipShape(shape)

            VStack(spacing: 0) {                                   // a light top edge, not an app colour
                Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
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
                    .foregroundColor(HUDChrome.onSignal)
                    .lineLimit(1)
                    .padding(.horizontal, 4).padding(.vertical, 1.5)
                    .background(Capsule().fill(HUDChrome.cyan))
            }
            if tags.count > 3 {
                Text("+\(tags.count - 3)")
                    .font(Typo.monoBold(8)).foregroundColor(HUDChrome.cyan)
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
