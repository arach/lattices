import AppKit
import SwiftUI

// MARK: - Space Switch HUD

/// One retained filmstrip and backdrop. All input is already cached by the
/// desktop inventory; showing this never scans windows or captures pixels.
/// Main-thread only. The switch queue never waits for presentation.
final class SpaceSwitchBezel {
    static let shared = SpaceSwitchBezel()

    private var panel: NSPanel?
    private var backdrop: NSPanel?
    private let filmstrip = SpaceFilmstripView()
    private var dismissTimer: Timer?
    private var generation = 0
    private var holdingForSwitch = false
    /// Window alpha is presentation state, not a reliable lifecycle flag:
    /// AppKit can still report 1 while its animator is already fading out.
    private var isDismissing = false
    private var displayID: String?
    private var spaceIDs: [Int] = []
    /// Where the surface sits for this gesture. Decided once on open so a
    /// reversal never moves the tray — travel-edge included.
    private var surfaceFrame: CGRect?
    private let wash = SpaceSwitchWash()
    private var transitCovers: [CGDirectDisplayID: NSPanel] = [:]
    private var transitImages: [CGDirectDisplayID: CGImage] = [:]
    private var transitFrames: [CGDirectDisplayID: CGRect] = [:]
    private var transitVisible = false
    private var captureTask: Task<Void, Never>?
    private var transitGeneration = 0

    func show(direction: Int, targetIndex: Int?, currentIndex: Int?, display: DisplaySpaces, holding: Bool = false, scrubbing: Bool = false, fullscreenOrdinal: Int? = nil, on screen: NSScreen? = nil) {
        guard let screen = screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let desktopTarget = display.spaces.firstIndex(where: { $0.index == targetIndex })
        guard desktopTarget != nil || fullscreenOrdinal != nil else { return }
        let target = desktopTarget ?? filmstrip.selected ?? 0
        let started = CACurrentMediaTime()
        dismissTimer?.invalidate()
        generation &+= 1
        holdingForSwitch = holding
        if scrubbing, filmstrip.isScrubbing, panel?.isVisible == true, displayID == display.displayId {
            filmstrip.scrub(number: fullscreenOrdinal ?? targetIndex ?? 1,
                total: display.orderedSpaceIds.count,
                animated: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                selectedIndex: desktopTarget)
            return
        }
        let opening = panel?.isVisible != true
        let ids = display.spaces.map(\.id)
        let changedDisplay = displayID != display.displayId
        let width = SpaceFilmstripLayout.trayWidth(screenWidth: screen.frame.width, count: ids.count)
        let size = CGSize(width: width, height: SpaceFilmstripLayout.height)
        if opening || changedDisplay || surfaceFrame?.size != size || surfaceFrame.map(screen.frame.contains) != true {
            surfaceFrame = Self.frame(position: Preferences.shared.spaceSwitchBezelPosition, direction: direction,
                                      size: size, screen: screen.frame)
        }
        guard let frame = surfaceFrame else { return }
        if panel == nil {
            let p = Self.makePanel()
            p.contentView = filmstrip
            panel = p
        }
        guard let panel else { return }
        if panel.frame != frame { panel.setFrame(frame, display: false) }
        if opening || changedDisplay || spaceIDs != ids {
            displayID = display.displayId
            spaceIDs = ids
            let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
            let bounds = CGRect(x: screen.frame.minX, y: primaryHeight - screen.frame.maxY,
                                width: screen.frame.width, height: screen.frame.height)
            let cards = SpaceFilmstripLayout.cards(spaces: display.spaces,
                windows: DesktopModel.shared.allWindows(), bounds: bounds)
            filmstrip.configure(cards: cards, size: size, scale: screen.backingScaleFactor)
            let departure = display.spaces.firstIndex(where: { $0.index == currentIndex }) ?? target
            filmstrip.select(departure, animated: false)
        }
        // Backdrop and strip arrive together. A press that lands during the
        // fade-out retargets the same fade back up from where it is, rather
        // than popping to full; a reused panel keeps us from allocating
        // another display surface per press.
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let fadingOut = isDismissing || (!opening && panel.alphaValue < 1)
        isDismissing = false
        if opening {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        let washHost = showBackdrop(on: screen, opening: opening)
        if opening || fadingOut {
            // Still geometry, two depths: the backdrop acknowledges the
            // chord immediately, then the frame resolves into focus. AppKit
            // retargets an interrupted fade from its current visible alpha.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = reduceMotion ? 0 : 0.24
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0, 0.22, 1)
                panel.animator().alphaValue = 1
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = reduceMotion ? 0 : 0.12
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0.2, 1)
                self.backdrop?.animator().alphaValue = 1
            }
            if opening { filmstrip.illuminateFrame(animated: !reduceMotion) }
        }
        if scrubbing {
            filmstrip.scrub(number: fullscreenOrdinal ?? targetIndex ?? 1,
                           total: display.orderedSpaceIds.count, animated: !reduceMotion, selectedIndex: desktopTarget)
        } else if filmstrip.isScrubbing {
            filmstrip.endScrubbing(at: desktopTarget, animated: !reduceMotion)
        } else {
            filmstrip.select(target, animated: !reduceMotion)
        }
        if !scrubbing, direction != 0, !reduceMotion, SpaceSwitchWash.isEnabled, let washHost {
            wash.pass(direction: direction < 0 ? -1 : 1, in: washHost)
        }
        if !holding { armDismissal() }
        DiagnosticLog.shared.info("SpaceFilmstrip: presentMs=\(String(format: "%.2f", (CACurrentMediaTime() - started) * 1000)) opening=\(opening)")
    }

    /// One bounded, optional departure still per held gesture, captured
    /// asynchronously while the user selects. Never capture on taps/repeats.
    /// Exclude our panels, cap pixels, and discard it as soon as transit ends.
    static func captureWindowIDs(_ numbers: [Int]) -> [CGWindowID] {
        // AppKit status-item windows can carry 64-bit synthetic identifiers.
        // They are not WindowServer capture IDs; never narrow them by force.
        numbers.compactMap { $0 > 0 ? CGWindowID(exactly: $0) : nil }
    }

    func prepareTransitCover(on screen: NSScreen?) {
        endTransitCover()
        guard let screen else { return }
        // Mission Control opens on every display. Keep each display still,
        // including the ones which aren't participating in navigation.
        let screens = [screen] + NSScreen.screens.filter { $0 != screen }
        let displays = screens.compactMap { screen -> (CGDirectDisplayID, CGRect)? in
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return nil }
            return (id, screen.frame)
        }
        transitFrames = Dictionary(uniqueKeysWithValues: displays)
        let mine = transitGeneration
        let excluded = Self.captureWindowIDs(([panel, backdrop] + transitCovers.values.map { Optional($0) }).compactMap { $0?.windowNumber })
        captureTask = Task { @MainActor [weak self] in
            for (id, _) in displays {
                guard !Task.isCancelled else { return }
                let image = await WindowCapture.display(displayID: id, showsCursor: false,
                    excludingWindowIDs: excluded, maximumPixelSize: 1600)
                guard let self, !Task.isCancelled, self.transitGeneration == mine,
                      !self.transitVisible else { return }
                self.transitImages[id] = image
                DiagnosticLog.shared.info("SpaceScrub: capture display=\(id) pixels=\(image?.width ?? 0)x\(image?.height ?? 0)")
            }
        }
    }

    /// Finish the one-shot capture if a very short hold outran it. Readiness
    /// races a small deadline, so ScreenCaptureKit can never stall navigation.
    func withTransitCover(_ completion: @escaping () -> Void) {
        let mine = transitGeneration
        let pendingCapture = captureTask
        var started = false
        let start = { [weak self] in
            guard !started else { return }
            started = true
            if let self, self.transitGeneration == mine { self.beginTransitCover() }
            completion()
        }
        if transitImages.count == transitFrames.count || pendingCapture == nil {
            start()
        } else {
            Task { @MainActor in
                await pendingCapture?.value
                start()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: start)
        }
    }

    func beginTransitCover() {
        transitVisible = true
        for (id, frame) in transitFrames {
            let cover: NSPanel
            if let retained = transitCovers[id] {
                cover = retained
            } else {
                cover = Self.makePanel()
                cover.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 2)
                cover.isOpaque = true
                let view = NSView()
                view.wantsLayer = true
                view.layer?.backgroundColor = NSColor(calibratedRed: 0.045, green: 0.055, blue: 0.065, alpha: 1).cgColor
                cover.contentView = view
                transitCovers[id] = cover
            }
            cover.setFrame(frame, display: false)
            cover.contentView?.layer?.contents = transitImages[id]
            cover.contentView?.layer?.contentsGravity = .resize
            cover.alphaValue = 1
            cover.orderFrontRegardless()
        }
        DiagnosticLog.shared.info("SpaceScrub: cover snapshots=\(transitImages.count)/\(transitFrames.count)")
        CATransaction.flush()
    }

    func endTransitCover() {
        transitGeneration &+= 1
        captureTask?.cancel()
        captureTask = nil
        for cover in transitCovers.values {
            cover.orderOut(nil)
            cover.contentView?.layer?.contents = nil
        }
        transitImages.removeAll()
        transitFrames.removeAll()
        transitVisible = false
    }

    /// Called after the switch queue settles, never awaited by that queue.
    /// A merged 1→18 burst can take longer than the ordinary idle timeout.
    func finishSwitch() {
        guard holdingForSwitch else { return }
        holdingForSwitch = false
        armDismissal()
    }

    /// After a missed switch, once the queue is idle: give a late landing a
    /// moment, then move the strip to the Space actually showing. Any newer
    /// press bumps the generation and owns the strip instead.
    func settleOnCurrentSpace() {
        guard panel?.isVisible == true else { return }
        let mine = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay) { [weak self] in
            guard let self, self.generation == mine, self.panel?.isVisible == true else { return }
            WindowTiler.showSpaceSwitchBezelForCurrentSpace()
        }
    }

    static let settleDelay: TimeInterval = 0.2

    private func armDismissal() {
        dismissTimer?.invalidate()
        let mine = generation
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 1.1, repeats: false) { [weak self] _ in
            guard let self, self.generation == mine else { return }
            self.dismiss()
        }
    }

    func dismiss() {
        endTransitCover()
        holdingForSwitch = false
        dismissTimer?.invalidate()
        dismissTimer = nil
        generation &+= 1
        let mine = generation
        guard let panel, panel.isVisible else {
            isDismissing = false
            backdrop?.orderOut(nil)
            return
        }
        isDismissing = true
        NSAnimationContext.runAnimationGroup({ ctx in
            // A gentle release, accelerating out of the way. No shrinking,
            // translation, or reverse travel on the preview track.
            ctx.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.20
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.8, 0.35)
            panel.animator().alphaValue = 0
            self.backdrop?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.generation == mine else { return }
            self.isDismissing = false
            panel.orderOut(nil)
            self.backdrop?.orderOut(nil)
            // Clear card backing stores after a gesture; keep only the two
            // panels and small layer scaffold, with no image cache to grow.
            self.filmstrip.clear()
            self.wash.release()
            self.spaceIDs = []
            self.surfaceFrame = nil
        })
    }

    @discardableResult
    private func showBackdrop(on screen: NSScreen, opening: Bool) -> NSView? {
        if backdrop == nil {
            let p = Self.makePanel()
            p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
            let view = NSView()
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor(calibratedRed: 0.015, green: 0.03, blue: 0.045, alpha: 0.20).cgColor
            p.contentView = view
            backdrop = p
        }
        guard let backdrop, let view = backdrop.contentView else { return nil }
        if backdrop.frame != screen.frame { backdrop.setFrame(screen.frame, display: false) }
        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        if !reduceTransparency, view.subviews.isEmpty {
            let blur = NSVisualEffectView(frame: view.bounds)
            blur.autoresizingMask = [.width, .height]
            blur.material = .hudWindow
            blur.blendingMode = .behindWindow
            blur.state = .active
            blur.appearance = NSAppearance(named: .darkAqua)
            blur.alphaValue = 0.14
            view.addSubview(blur)
        } else if reduceTransparency {
            view.subviews.forEach { $0.removeFromSuperview() }
        }
        if opening || !backdrop.isVisible {
            backdrop.alphaValue = 0
            backdrop.orderFrontRegardless()
        }
        // The wash is a transparency effect; Reduce Transparency goes without.
        return reduceTransparency ? nil : view
    }

    private static func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .statusBar
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.isMovable = false
        p.ignoresMouseEvents = true
        p.animationBehavior = .none
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        return p
    }

    static func frame(position: SpaceSwitchBezelPosition, direction: Int, size: CGSize, screen: CGRect) -> CGRect {
        var origin = CGPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
        switch position {
        case .center: break
        case .top: origin.y = screen.maxY - size.height - 50
        case .bottom: origin.y = screen.minY + 68
        case .travelEdge: origin.x = direction >= 0 ? screen.maxX - size.width - 26 : screen.minX + 26
        }
        return CGRect(origin: origin, size: size)
    }
}

// MARK: - Passing light

/// A barely luminous band that crosses the backdrop in the direction of
/// travel, from the "Passing light" study. It is the only full-screen motion:
/// tray, focus frame and desktop stay put. Held keys soften the pass so the
/// screen never strobes. Three retained bands rotate so a new pass never cuts
/// one off mid-screen; the oldest has faded out by the time it is reused.
/// Bands are made on first pass and released with the gesture.
/// Main-thread only.
final class SpaceSwitchWash {
    static let duration: CFTimeInterval = 0.48
    /// A press inside this window of the last pass reads as a held key.
    static let heldInterval: CFTimeInterval = 0.18
    static let peak: Float = 0.8
    static let heldPeak: Float = 0.3
    private static let bandCount = 3

    /// On unless `spaceSwitchKeys.passingLight` is set false.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "spaceSwitchKeys.passingLight") as? Bool ?? true
    }

    private var bands: [CAGradientLayer] = []
    private var next = 0
    private var lastPass: CFTimeInterval = 0
    private var lastDirection = 0

    func pass(direction: Int, in view: NSView) {
        guard let host = view.layer, view.bounds.width > 0 else { return }
        let now = CACurrentMediaTime()
        let held = now - lastPass < Self.heldInterval
        // Repeats faster than a switch can land keep the band already
        // travelling instead of relaunching one from the edge.
        if direction == lastDirection, now - lastPass < Self.heldInterval / 3 { return }
        lastPass = now
        lastDirection = direction
        if bands.isEmpty {
            bands = (0..<Self.bandCount).map { _ in Self.makeBand() }
        }
        let band = bands[next]
        next = (next + 1) % bands.count
        if band.superlayer !== host { host.addSublayer(band) }

        let size = view.bounds.size
        let width = size.width * 0.3
        let start = direction > 0 ? -width * 0.7 : size.width + width * 0.7
        let end = direction > 0 ? size.width + width * 0.7 : -width * 0.7
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        band.removeAllAnimations()
        band.bounds = CGRect(x: 0, y: 0, width: width, height: size.height)
        band.position = CGPoint(x: end, y: size.height / 2)
        // CSS skewX(-12deg) in a y-up layer: the top leans forward.
        band.transform = CATransform3DMakeAffineTransform(CGAffineTransform(a: 1, b: 0, c: tan(12 * .pi / 180), d: 1, tx: 0, ty: 0))
        band.opacity = 0

        let travel = CABasicAnimation(keyPath: "position.x")
        travel.fromValue = start
        travel.toValue = end
        travel.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        let glow = CAKeyframeAnimation(keyPath: "opacity")
        glow.values = [0, held ? Self.heldPeak : Self.peak, 0]
        glow.keyTimes = [0, 0.15, 1]
        let group = CAAnimationGroup()
        group.animations = [travel, glow]
        group.duration = Self.duration
        band.add(group, forKey: "pass")
        CATransaction.commit()
    }

    /// Drop the bands with the gesture; nothing full-screen outlives it.
    func release() {
        bands.forEach { $0.removeAllAnimations(); $0.removeFromSuperlayer() }
        bands.removeAll()
        next = 0
        lastPass = 0
        lastDirection = 0
    }

    var liveBandCount: Int { bands.count }

    private static func makeBand() -> CAGradientLayer {
        let band = CAGradientLayer()
        let light = NSColor(calibratedRed: 0.68, green: 0.87, blue: 1, alpha: 0.145)
        band.colors = [light.withAlphaComponent(0).cgColor, light.cgColor, light.withAlphaComponent(0).cgColor]
        band.startPoint = CGPoint(x: 0, y: 0.5)
        band.endPoint = CGPoint(x: 1, y: 0.5)
        band.opacity = 0
        return band
    }
}

// MARK: - Space landscape

/// Wide strip of every Space on one display. Shown for Ctrl+Shift+←/→,
/// which switches the same way as Ctrl+←/→. Cards open as the window
/// blocks already on screen. Screenshots are taken afterward, off the
/// switch, and each block is replaced when its own picture is ready.
final class SpaceLandscape {
    static let shared = SpaceLandscape()

    private var panel: NSPanel?
    private var dismissTimer: Timer?
    private var token = 0
    private var captureTask: Task<Void, Never>?
    private let state = SpaceLandscapeState()
    private var windowShots: [UInt32: NSImage] = [:]

    /// `activeSpaceId` is the Space to highlight — the switch target, which
    /// may not have landed yet. Cards follow Mission Control order, so
    /// fullscreen app Spaces get a card between the desktops.
    func show(
        direction: Int,
        display: DisplaySpaces,
        activeSpaceId: Int,
        windows: [WindowEntry],
        on screen: NSScreen? = nil
    ) {
        dismissTimer?.invalidate()
        guard let screen = screen ?? NSScreen.main ?? NSScreen.screens.first,
              !display.orderedSpaceIds.isEmpty else { return }

        let cards = Self.cards(
            display: display,
            activeId: activeSpaceId,
            on: screen,
            windowShots: windowShots,
            windows: windows
        )
        // Pictures for windows that left the strip are dropped; the rest stay
        // as instant paint until this show's captures replace them.
        let liveWids = Set(cards.flatMap { $0.windows.map(\.id) })
        windowShots = windowShots.filter { liveWids.contains($0.key) }

        state.direction = direction
        state.cards = cards
        state.activeLabel = cards.first(where: \.active).map { card in
            card.index.map { "DESKTOP \($0)" } ?? card.label.uppercased()
        }

        let sf = screen.frame
        let width = min(sf.width - 72, 1880)
        let height: CGFloat = 340
        let frame = NSRect(
            x: sf.midX - width / 2,
            y: sf.maxY - height - 46,
            width: width,
            height: height
        )

        token &+= 1
        let mine = token

        if panel == nil {
            let p = NSPanel(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.isOpaque = false
            p.backgroundColor = .clear
            p.level = .statusBar
            p.hasShadow = false
            p.hidesOnDeactivate = false
            p.isReleasedWhenClosed = false
            p.isMovable = false
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            p.contentView = NSHostingView(rootView: SpaceLandscapeView(state: state))
            panel = p
        }
        guard let p = panel else { return }
        p.setFrame(frame, display: true)
        if p.isVisible {
            p.alphaValue = 1
        } else {
            p.alphaValue = 0
            p.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.16
                p.animator().alphaValue = 1
            }
        }

        dismissTimer = Timer.scheduledTimer(withTimeInterval: 1.1, repeats: false) { [weak self] _ in
            guard let self, self.token == mine else { return }
            self.dismiss()
        }

        // Shapes are already on screen. Pictures are fetched after this
        // returns, and a newer chord cancels the previous fetch so a fast
        // traverse does not pile captures on top of the switch.
        captureTask?.cancel()
        let windowIDs = Self.captureWindowIDs(in: cards)
        captureTask = Task.detached(priority: .utility) { [weak self] in
            await WindowCapture.thumbnails(windowIDs: windowIDs, maximumPixelSize: 480) { batch in
                await MainActor.run {
                    guard let self, self.token == mine else { return }
                    for (id, cg) in batch {
                        self.windowShots[id] = NSImage(
                            cgImage: cg,
                            size: NSSize(width: cg.width, height: cg.height)
                        )
                    }
                    self.state.apply(windowShots: self.windowShots)
                }
            }
        }
    }

    /// Active card first, then outward — the Space you're looking at, then
    /// its neighbors, get their pictures before the far end of the strip.
    private static func captureWindowIDs(in cards: [SpaceLandscapeCard]) -> [CGWindowID] {
        let activeIndex = cards.firstIndex(where: \.active) ?? 0
        let ordered = cards.indices.sorted { abs($0 - activeIndex) < abs($1 - activeIndex) }
        var ids: [CGWindowID] = []
        var seen = Set<UInt32>()
        for index in ordered {
            for window in cards[index].windows where seen.insert(window.id).inserted {
                ids.append(window.id)
            }
        }
        return ids
    }

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        captureTask?.cancel()
        captureTask = nil
        token &+= 1
        let mine = token
        guard let p = panel, p.isVisible else {
            state.cards = []
            windowShots.removeAll()
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            p.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.token == mine else { return }
            p.orderOut(nil)
            self.state.cards = []
            self.windowShots.removeAll()
        })
    }

    private static func cards(
        display: DisplaySpaces,
        activeId: Int,
        on screen: NSScreen,
        windowShots: [UInt32: NSImage],
        windows: [WindowEntry]
    ) -> [SpaceLandscapeCard] {
        let bounds = cgBounds(of: screen)
        return display.orderedSpaceIds.map { spaceId in
            let members = windows.filter { $0.spaceIds.contains(spaceId) && $0.app != "Lattices" }
            let placed = members
                .sorted { $0.zIndex > $1.zIndex }
                .compactMap { entry -> SpaceLandscapeWindow? in
                    guard bounds.width > 1, bounds.height > 1 else { return nil }
                    let rect = CGRect(
                        x: (entry.frame.x - bounds.minX) / bounds.width,
                        y: (entry.frame.y - bounds.minY) / bounds.height,
                        width: entry.frame.w / bounds.width,
                        height: entry.frame.h / bounds.height
                    ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
                    guard rect.width > 0.01, rect.height > 0.01 else { return nil }
                    return SpaceLandscapeWindow(id: entry.wid, rect: rect, image: windowShots[entry.wid])
                }
                .sorted { ($0.rect.width * $0.rect.height) > ($1.rect.width * $1.rect.height) }
            let limited = Array(placed.prefix(6))
            // Fullscreen app Spaces have no desktop number; name the app.
            let index = display.spaces.first(where: { $0.id == spaceId })?.index
            let label = index.map(String.init)
                ?? members.min(by: { $0.zIndex < $1.zIndex })?.app
                ?? "Fullscreen"
            return SpaceLandscapeCard(
                id: spaceId,
                index: index,
                label: label,
                active: spaceId == activeId,
                windows: limited
            )
        }
    }

    /// CGWindow coordinates for this screen: top-left origin, y downward.
    private static func cgBounds(of screen: NSScreen) -> CGRect {
        let primary = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let frame = screen.frame
        return CGRect(x: frame.minX, y: primary - frame.maxY, width: frame.width, height: frame.height)
    }
}

struct SpaceLandscapeCard: Identifiable {
    let id: Int
    /// Desktop number; nil for a fullscreen app Space.
    let index: Int?
    let label: String
    let active: Bool
    var windows: [SpaceLandscapeWindow]
}

struct SpaceLandscapeWindow: Identifiable {
    let id: UInt32
    let rect: CGRect
    var image: NSImage?
}

final class SpaceLandscapeState: ObservableObject {
    @Published var direction: Int = 1
    @Published var activeLabel: String?
    @Published var cards: [SpaceLandscapeCard] = []

    func apply(windowShots: [UInt32: NSImage]) {
        var next = cards
        for cardIndex in next.indices {
            for windowIndex in next[cardIndex].windows.indices {
                let id = next[cardIndex].windows[windowIndex].id
                if let image = windowShots[id] {
                    next[cardIndex].windows[windowIndex].image = image
                }
            }
        }
        cards = next
    }
}

private struct SpaceLandscapeView: View {
    @ObservedObject var state: SpaceLandscapeState

    private var accent: Color { HUDChrome.cyan }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(state.direction < 0 ? "‹" : "›")
                    .font(Typo.monoBold(13))
                    .foregroundStyle(accent)
                Text(state.activeLabel ?? "")
                    .lineLimit(1)
                    .font(Typo.monoBold(10))
                    .tracking(0.7)
                    .foregroundStyle(Palette.text)
                Spacer(minLength: 8)
                Text("\(state.cards.count) SPACES")
                    .font(Typo.monoBold(6.5))
                    .tracking(1.1)
                    .foregroundStyle(Palette.textDim)
                Text("LATTICES")
                    .font(Typo.monoBold(6.5))
                    .tracking(1.2)
                    .foregroundStyle(Palette.textDim)
            }

            HStack(spacing: 8) {
                ForEach(state.cards) { card in
                    SpaceLandscapeCardView(card: card)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [HUDChrome.baseTop, HUDChrome.baseBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.45), radius: 18, y: 8)
    }
}

private struct SpaceLandscapeCardView: View {
    let card: SpaceLandscapeCard

    private var accent: Color { HUDChrome.cyan }

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white.opacity(card.active ? 0.06 : 0.03))
                    ForEach(card.windows) { window in
                        let size = geo.size
                        let frame = CGSize(
                            width: max(2, window.rect.width * size.width),
                            height: max(2, window.rect.height * size.height)
                        )
                        Group {
                            if let image = window.image {
                                Image(nsImage: image)
                                    .resizable()
                                    .interpolation(.medium)
                                    .frame(width: frame.width, height: frame.height)
                            } else {
                                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                    .fill(Color.white.opacity(card.active ? 0.55 : 0.28))
                                    .frame(width: frame.width, height: frame.height)
                            }
                        }
                        .offset(
                            x: window.rect.minX * size.width,
                            y: window.rect.minY * size.height
                        )
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(card.active ? accent.opacity(0.9) : Color.white.opacity(0.12), lineWidth: card.active ? 1.25 : 0.6)
            )
            .shadow(color: card.active ? accent.opacity(0.28) : .clear, radius: 6)

            Text(card.label)
                .font(Typo.monoBold(8))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(card.active ? accent : Palette.textDim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Current space number

/// A quiet number in the top-left of each display that has more than one
/// Space. Sits in the visible frame, under the menu bar, and ignores clicks.
final class SpaceNumberMark {
    static let shared = SpaceNumberMark()

    private var marks: [Int: (panel: NSPanel, state: SpaceNumberMarkState)] = [:]

    func refresh() {
        dispatchPrecondition(condition: .onQueue(.main))
        let displays = WindowTiler.getDisplaySpaces()
        var live = Set<Int>()
        for display in displays where display.spaces.count > 1 {
            // SkyLight's display order isn't NSScreen's — match by UUID.
            guard let screen = DisplayGeometryMapper.screen(for: display, in: NSScreen.screens) else { continue }
            // A fullscreen app Space has no desktop number to show.
            guard let number = display.spaces.first(where: { $0.id == display.currentSpaceId })?.index else { continue }
            live.insert(display.displayIndex)
            place(number, key: display.displayIndex, on: screen)
        }
        for key in marks.keys where !live.contains(key) {
            marks[key]?.panel.orderOut(nil)
            marks.removeValue(forKey: key)
        }
    }

    private func place(_ number: Int, key: Int, on screen: NSScreen) {
        let state: SpaceNumberMarkState
        let panel: NSPanel
        if let existing = marks[key] {
            state = existing.state
            panel = existing.panel
        } else {
            let created = SpaceNumberMarkState()
            let hosting = NSHostingView(rootView: SpaceNumberMarkView(state: created))
            let p = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.isOpaque = false
            p.backgroundColor = .clear
            p.level = .floating
            p.hasShadow = false
            p.hidesOnDeactivate = false
            p.isReleasedWhenClosed = false
            p.isMovable = false
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            p.contentView = hosting
            marks[key] = (p, created)
            state = created
            panel = p
        }

        if state.number != number { state.number = number }
        let vf = screen.visibleFrame
        let size = NSSize(width: 28, height: 22)
        let frame = NSRect(x: vf.minX + 12, y: vf.maxY - size.height - 8, width: size.width, height: size.height)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        if !panel.isVisible {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
    }
}

final class SpaceNumberMarkState: ObservableObject {
    @Published var number: Int = 1
}

private struct SpaceNumberMarkView: View {
    @ObservedObject var state: SpaceNumberMarkState

    var body: some View {
        Text("\(state.number)")
            .font(Typo.monoBold(11))
            .foregroundStyle(Color.white.opacity(0.58))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.black.opacity(0.22))
            )
    }
}
