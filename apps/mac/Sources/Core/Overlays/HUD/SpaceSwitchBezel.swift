import AppKit
import SwiftUI

// MARK: - Space Switch HUD

/// Compact acknowledgement for Ctrl+←/→ space jumps handled by
/// `SpaceSwitchInterceptor`. A boxy tray of logo-cells — one rounded square
/// per space, the logo's own bright/dim language — docked top-center by
/// default. `SpaceSwitchBezelPosition` is agent-configurable via
/// `settings.spaceBezel.set` (top, bottom, center, or travelEdge, which
/// docks at the screen edge the desktop is moving toward).
final class SpaceSwitchBezel {
    static let shared = SpaceSwitchBezel()

    private var panel: NSPanel?
    private var dismissTimer: Timer?
    private var token = 0
    private let state = SpaceBezelState()

    /// `direction`: -1 = left, +1 = right. `targetIndex` is the 1-based space
    /// we landed on; nil means the display was already at the edge and
    /// `currentIndex` is shown with the amber "EDGE" treatment instead.
    ///
    /// The tray itself is stable — it fades in once and never translates.
    /// Motion lives in the active cell, which glides between positions.
    func show(direction: Int, targetIndex: Int?, currentIndex: Int?, total: Int, on screen: NSScreen? = nil) {
        dismissTimer?.invalidate()
        guard let screen = screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let sf = screen.frame

        let height: CGFloat = 40
        let width = pillWidth(total: total)
        let endFrame = frame(for: Preferences.shared.spaceSwitchBezelPosition,
                             direction: direction, width: width, height: height, in: sf)

        token &+= 1
        let mine = token

        state.direction = direction
        state.activeIndex = targetIndex ?? currentIndex
        state.edge = targetIndex == nil
        state.total = total

        if panel == nil {
            let p = NSPanel(
                contentRect: endFrame,
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
            p.contentView = NSHostingView(rootView: SpaceSwitchBezelView(state: state))
            panel = p
        }
        guard let p = panel else { return }

        if p.isVisible {
            // Already up — keep the box anchored; the cell carries the motion.
            if p.frame != endFrame { p.setFrame(endFrame, display: true) }
            p.alphaValue = 1
            // A glide snapshot may have been ordered in at the same level.
            p.orderFrontRegardless()
        } else {
            p.setFrame(endFrame, display: false)
            p.alphaValue = 0
            p.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                p.animator().alphaValue = 1.0
            }
        }

        if !SpaceSwitchGlide.shared.isEnabled {
            SpaceEdgeSweep.shared.fire(direction: direction, edge: targetIndex == nil, on: screen)
        }

        dismissTimer = Timer.scheduledTimer(withTimeInterval: 1.1, repeats: false) { [weak self] _ in
            guard let self, self.token == mine else { return }
            self.dismiss()
        }
    }

    func dismiss() {
        guard let p = panel, p.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            p.animator().alphaValue = 0
        }, completionHandler: { p.orderOut(nil) })
    }

    private func frame(for position: SpaceSwitchBezelPosition, direction: Int,
                       width: CGFloat, height: CGFloat, in sf: NSRect) -> NSRect {
        switch position {
        case .travelEdge:
            let x = direction >= 0 ? sf.maxX - width - 26 : sf.minX + 26
            return NSRect(x: x, y: sf.midY - height / 2, width: width, height: height)
        case .top:
            return NSRect(x: sf.midX - width / 2, y: sf.maxY - height - 50, width: width, height: height)
        case .center:
            return NSRect(x: sf.midX - width / 2, y: sf.midY - height / 2, width: width, height: height)
        case .bottom:
            return NSRect(x: sf.midX - width / 2, y: sf.minY + 68, width: width, height: height)
        }
    }

    private func pillWidth(total: Int) -> CGFloat {
        let n = max(total, 1)
        let cell = Self.cellSize(total: total)
        let cellsWidth = n > 1 ? CGFloat(n) * cell + CGFloat(n - 1) * Self.cellGap : 0
        // tick(10) + gaps + hairline(1) + "DESKTOP N" + "LATTICES" + padding
        let labelWidth: CGFloat = total >= 10 ? 76 : 62
        return ceil(11 + 10 + 9 + cellsWidth + 9 + 1 + 9 + labelWidth + 9 + 44 + 11)
    }

    private static let cellGap: CGFloat = 6

    /// Logo cells stay 15pt through a dozen spaces, then shrink to keep the
    /// tray inside ~280pt.
    static func cellSize(total: Int) -> CGFloat {
        guard total > 12 else { return 15 }
        return max(7, floor((240 - CGFloat(total - 1) * cellGap) / CGFloat(total)))
    }
}

// MARK: - Bezel State + View

/// Mutable content for the persistent bezel panel — `show()` mutates this
/// and SwiftUI animates the cell, while the tray chrome stays put.
final class SpaceBezelState: ObservableObject {
    @Published var direction: Int = 1
    @Published var activeIndex: Int? = nil
    @Published var edge: Bool = false
    @Published var total: Int = 0
}

private struct SpaceSwitchBezelView: View {
    @ObservedObject var state: SpaceBezelState
    @Namespace private var travel

    private var accent: Color { state.edge ? HUDChrome.amber : HUDChrome.cyan }
    private var cellSize: CGFloat { SpaceSwitchBezel.cellSize(total: state.total) }

    var body: some View {
        HStack(spacing: 9) {
            // Direction tick — the only chromatic element besides EDGE.
            Text(state.edge ? "↔" : (state.direction < 0 ? "‹" : "›"))
                .font(Typo.monoBold(13))
                .foregroundStyle(accent)

            if state.total > 1 {
                HStack(spacing: 6) {
                    ForEach(1...state.total, id: \.self) { i in
                        RoundedRectangle(cornerRadius: cellSize * 0.24, style: .continuous)
                            .fill(Color.white.opacity(0.18))
                            .frame(width: cellSize, height: cellSize)
                            .overlay {
                                if i == state.activeIndex {
                                    RoundedRectangle(cornerRadius: cellSize * 0.24, style: .continuous)
                                        .fill(state.edge ? HUDChrome.amber : Color(white: 0.95))
                                        .matchedGeometryEffect(id: "active", in: travel)
                                        .shadow(color: accent.opacity(0.45), radius: 4)
                                }
                            }
                    }
                }
                .animation(.snappy(duration: 0.22, extraBounce: 0.05), value: state.activeIndex)
                .animation(.easeOut(duration: 0.18), value: state.edge)
            }

            HUDHairline(axis: .vertical, opacity: 0.9)
                .frame(height: 16)

            Text(state.edge ? "EDGE" : "DESKTOP \(state.activeIndex ?? 0)")
                .font(Typo.monoBold(10))
                .tracking(0.7)
                .foregroundStyle(state.edge ? HUDChrome.amber : Palette.text)

            Text("LATTICES")
                .font(Typo.monoBold(6.5))
                .tracking(1.2)
                .foregroundStyle(Palette.textDim)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 11)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [HUDChrome.baseTop, HUDChrome.baseBottom],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                // Directional wash — light bleeds in from the edge of travel.
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(state.edge ? 0.08 : 0.14), Color.clear],
                            startPoint: state.direction >= 0 ? .trailing : .leading,
                            endPoint: .center
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(state.edge ? HUDChrome.amber.opacity(0.38) : Color.white.opacity(0.10), lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.45), radius: 16, y: 8)
        .shadow(color: accent.opacity(state.edge ? 0.06 : 0.14), radius: 12)
    }
}

// MARK: - Edge Sweep

/// A hairline beam at the very top edge of the display that drifts in the
/// direction of travel and fades — a subtle directional echo of the space
/// change itself, since the switch renders as an instant cut.
final class SpaceEdgeSweep {
    static let shared = SpaceEdgeSweep()

    private var panel: NSPanel?
    private let state = SweepState()

    func fire(direction: Int, edge: Bool, on screen: NSScreen? = nil) {
        guard let screen = screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let vf = screen.visibleFrame
        let height: CGFloat = 2.5
        let beamWidth = vf.width * 0.32
        let y = vf.maxY - height

        state.direction = direction
        state.edge = edge

        let startX = direction >= 0 ? vf.minX : vf.maxX - beamWidth
        let endX = direction >= 0 ? vf.maxX - beamWidth : vf.minX
        let startFrame = NSRect(x: startX, y: y, width: beamWidth, height: height)
        let endFrame = startFrame.offsetBy(dx: endX - startX, dy: 0)

        if panel == nil {
            let p = NSPanel(
                contentRect: startFrame,
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
            p.contentView = NSHostingView(rootView: SweepView(state: state))
            panel = p
        }
        guard let p = panel else { return }

        p.setFrame(startFrame, display: true)
        p.alphaValue = 1
        p.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.42
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 0.7, 0.4, 1)
            p.animator().setFrame(endFrame, display: true)
            p.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
        })
    }
}

final class SweepState: ObservableObject {
    @Published var direction: Int = 1
    @Published var edge: Bool = false
}

private struct SweepView: View {
    @ObservedObject var state: SweepState

    private var accent: Color { state.edge ? HUDChrome.amber : HUDChrome.cyan }

    var body: some View {
        // Bright at the leading edge of travel, dying out behind it.
        LinearGradient(
            colors: [accent.opacity(0.9), accent.opacity(0.35), Color.clear],
            startPoint: state.direction >= 0 ? .trailing : .leading,
            endPoint: state.direction >= 0 ? .leading : .trailing
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        edge: Bool,
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
        state.edge = edge
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
                    guard let self else { return }
                    for (id, cg) in batch {
                        self.windowShots[id] = NSImage(
                            cgImage: cg,
                            size: NSSize(width: cg.width, height: cg.height)
                        )
                    }
                    guard self.token == mine else { return }
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
        guard let p = panel, p.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            p.animator().alphaValue = 0
        }, completionHandler: { p.orderOut(nil) })
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
    @Published var edge: Bool = false
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

    private var accent: Color { state.edge ? HUDChrome.amber : HUDChrome.cyan }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(state.edge ? "↔" : (state.direction < 0 ? "‹" : "›"))
                    .font(Typo.monoBold(13))
                    .foregroundStyle(accent)
                Text(state.edge ? "EDGE" : (state.activeLabel ?? ""))
                    .lineLimit(1)
                    .font(Typo.monoBold(10))
                    .tracking(0.7)
                    .foregroundStyle(state.edge ? HUDChrome.amber : Palette.text)
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
                    SpaceLandscapeCardView(card: card, edge: state.edge && card.active)
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
    let edge: Bool

    private var accent: Color { edge ? HUDChrome.amber : HUDChrome.cyan }

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

        state.number = number
        let vf = screen.visibleFrame
        let size = NSSize(width: 28, height: 22)
        panel.setFrame(
            NSRect(x: vf.minX + 12, y: vf.maxY - size.height - 8, width: size.width, height: size.height),
            display: true
        )
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
