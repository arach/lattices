import AppKit
import BlinkCore
import Carbon
import QuartzCore

/// The nine teachable desk positions, in the same arrangement as their keys.
private enum GridSlot: String, CaseIterable {
    case q = "Q"
    case w = "W"
    case e = "E"
    case a = "A"
    case s = "S"
    case d = "D"
    case z = "Z"
    case x = "X"
    case c = "C"

    var row: Int {
        switch self {
        case .q, .w, .e: 0
        case .a, .s, .d: 1
        case .z, .x, .c: 2
        }
    }

    var column: Int {
        switch self {
        case .q, .a, .z: 0
        case .w, .s, .x: 1
        case .e, .d, .c: 2
        }
    }

    var keyCode: UInt32 {
        switch self {
        case .q: UInt32(kVK_ANSI_Q)
        case .w: UInt32(kVK_ANSI_W)
        case .e: UInt32(kVK_ANSI_E)
        case .a: UInt32(kVK_ANSI_A)
        case .s: UInt32(kVK_ANSI_S)
        case .d: UInt32(kVK_ANSI_D)
        case .z: UInt32(kVK_ANSI_Z)
        case .x: UInt32(kVK_ANSI_X)
        case .c: UInt32(kVK_ANSI_C)
        }
    }

    /// Deliberately outside the app-wide hotkey id range (1–3).
    var hotkeyID: UInt32 { 100 + UInt32(row * 3 + column) }
}

/// A relationship is visually undirected. Canonicalizing its ids avoids laying
/// the same line down twice when two notes link to each other (or one repeats a
/// link).
private struct GridThread: Hashable {
    let firstID: String
    let secondID: String

    init(_ sourceID: String, _ targetID: String) {
        if sourceID < targetID {
            firstID = sourceID
            secondID = targetID
        } else {
            firstID = targetID
            secondID = sourceID
        }
    }
}

/// Borderless windows are already non-key by default, but make that invariant
/// explicit: the page must never take focus away from a note.
private final class GridOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Native drawing surface for the desk page. Every coordinate supplied to this
/// view is local to the overlay's screen, so AppKit's normal bottom-left origin
/// lines up with global window coordinates after subtracting the screen origin.
private final class GridOverlayView: NSView {
    var slotFrames: [GridSlot: NSRect] = [:]
    var panelFrames: [String: NSRect] = [:]
    var threads: Set<GridThread> = []

    override var isOpaque: Bool { false }

    /// The guide "ink" follows the app scheme so the constellation reads on
    /// either backdrop: luminous white in dark mode, near-black in light.
    private var ink: NSColor {
        AppearanceManager.shared.scheme.isDark ? .white : NSColor(white: 0.12, alpha: 1)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.black.withAlphaComponent(0.15).setFill()
        bounds.fill()

        NSGraphicsContext.current?.shouldAntialias = true
        drawDotGrid()
        drawSlots()
        drawThreads()
        drawPanelOutlines()
    }

    private func drawDotGrid() {
        let dots = NSBezierPath()
        let spacing: CGFloat = 24
        let radius: CGFloat = 0.75
        var x = bounds.minX + spacing / 2
        while x <= bounds.maxX {
            var y = bounds.minY + spacing / 2
            while y <= bounds.maxY {
                dots.appendOval(
                    in: NSRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                )
                y += spacing
            }
            x += spacing
        }
        ink.withAlphaComponent(0.08).setFill()
        dots.fill()
    }

    private func drawSlots() {
        let dash: [CGFloat] = [7, 7]
        let letterFont = NSFont.monospacedSystemFont(ofSize: 48, weight: .thin)
        let letterAttributes: [NSAttributedString.Key: Any] = [
            .font: letterFont,
            .foregroundColor: ink.withAlphaComponent(0.09),
        ]

        for slot in GridSlot.allCases {
            guard let rect = slotFrames[slot] else { continue }
            let outline = NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16)
            outline.lineWidth = 1
            outline.setLineDash(dash, count: dash.count, phase: 0)
            ink.withAlphaComponent(0.13).setStroke()
            outline.stroke()

            let label = slot.rawValue as NSString
            let labelSize = label.size(withAttributes: letterAttributes)
            label.draw(
                at: NSPoint(x: rect.minX + 18, y: rect.maxY - labelSize.height - 10),
                withAttributes: letterAttributes
            )
        }
    }

    private func drawPanelOutlines() {
        for rect in panelFrames.values {
            let looseRect = rect.insetBy(dx: -2.5, dy: -2.5)
            let outline = NSBezierPath(roundedRect: looseRect, xRadius: 14, yRadius: 14)
            outline.lineWidth = 1.2
            outline.lineCapStyle = .round
            ink.withAlphaComponent(0.31).setStroke()
            outline.stroke()

            // A barely offset second pass keeps the line from reading as a
            // selection border; it feels more like a pencil finding its edge.
            let echo = NSBezierPath(
                roundedRect: looseRect.offsetBy(dx: 0.7, dy: -0.45),
                xRadius: 14,
                yRadius: 14
            )
            echo.lineWidth = 0.55
            ink.withAlphaComponent(0.10).setStroke()
            echo.stroke()
        }
    }

    private func drawThreads() {
        for thread in threads {
            guard let first = panelFrames[thread.firstID],
                  let second = panelFrames[thread.secondID]
            else { continue }

            let (start, end) = nearestEdgeMidpoints(first, second)
            let distance = hypot(end.x - start.x, end.y - start.y)
            let sag = min(86, max(22, distance * 0.11))
            let threadPath = NSBezierPath()
            threadPath.move(to: start)
            threadPath.curve(
                to: end,
                controlPoint1: NSPoint(
                    x: start.x + (end.x - start.x) * 0.33,
                    y: start.y + (end.y - start.y) * 0.33 - sag
                ),
                controlPoint2: NSPoint(
                    x: start.x + (end.x - start.x) * 0.67,
                    y: start.y + (end.y - start.y) * 0.67 - sag
                )
            )
            threadPath.lineWidth = 1.5
            threadPath.lineCapStyle = .round
            ink.withAlphaComponent(0.35).setStroke()
            threadPath.stroke()

            ink.withAlphaComponent(0.45).setFill()
            for point in [start, end] {
                NSBezierPath(
                    ovalIn: NSRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5)
                ).fill()
            }
        }
    }

    /// Pick the closest pair among each rectangle's four edge midpoints.
    private func nearestEdgeMidpoints(_ first: NSRect, _ second: NSRect) -> (NSPoint, NSPoint) {
        func midpoints(of rect: NSRect) -> [NSPoint] {
            [
                NSPoint(x: rect.minX, y: rect.midY),
                NSPoint(x: rect.maxX, y: rect.midY),
                NSPoint(x: rect.midX, y: rect.minY),
                NSPoint(x: rect.midX, y: rect.maxY),
            ]
        }

        var nearest = (NSPoint.zero, NSPoint.zero)
        var nearestDistance = CGFloat.greatestFiniteMagnitude
        for firstPoint in midpoints(of: first) {
            for secondPoint in midpoints(of: second) {
                let distance = hypot(secondPoint.x - firstPoint.x, secondPoint.y - firstPoint.y)
                if distance < nearestDistance {
                    nearestDistance = distance
                    nearest = (firstPoint, secondPoint)
                }
            }
        }
        return nearest
    }
}

/// Owns the constellation page's window, scoped Carbon key registrations,
/// relationship snapshot, and live geometry tracking.
@MainActor
final class GridOverlay {
    private static let escapeHotkeyID: UInt32 = 120

    private let store: NoteStore
    private let panelsProvider: () -> [String: NotePanel]
    private let placementPanelProvider: () -> NotePanel?
    private let onHide: () -> Void
    private let window: GridOverlayWindow
    private let drawingView = GridOverlayView()

    private var screenFrame = NSRect.zero
    private var notificationObservers: [NSObjectProtocol] = []
    private var idleTask: Task<Void, Never>?
    private var placementDismissTask: Task<Void, Never>?
    private var relationshipTask: Task<Void, Never>?
    private var relationshipRevision = 0

    private(set) var isVisible = false

    init(
        store: NoteStore,
        panels: @escaping () -> [String: NotePanel],
        placementPanel: @escaping () -> NotePanel?,
        onHide: @escaping () -> Void
    ) {
        self.store = store
        panelsProvider = panels
        placementPanelProvider = placementPanel
        self.onHide = onHide

        let overlayWindow = GridOverlayWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        overlayWindow.isOpaque = false
        overlayWindow.backgroundColor = .clear
        overlayWindow.ignoresMouseEvents = true
        overlayWindow.level = .floating
        overlayWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        overlayWindow.appearance = NSAppearance(named: AppearanceManager.shared.scheme.nsAppearanceName)
        overlayWindow.hasShadow = false
        overlayWindow.contentView = drawingView
        window = overlayWindow
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        guard !isVisible else { return }
        let placementPanel = placementPanelProvider()
        guard let screen = placementPanel?.screen ?? NSScreen.main ?? NSScreen.screens.first else {
            return
        }

        isVisible = true
        screenFrame = screen.frame
        window.setFrame(screen.frame, display: false)
        drawingView.frame = NSRect(origin: .zero, size: screen.frame.size)
        drawingView.slotFrames = makeSlotFrames(visibleFrame: screen.visibleFrame)
        installObservers()
        guard registerPlacementHotkeys() else {
            // A partial set would let an unclaimed letter leak into the note
            // beneath the page. Fail closed and restore every claimed key.
            hide()
            return
        }
        updateGeometry()
        refreshRelationships()
        orderBelowPanels()
        // AppKit can defer the first ordering transaction until the new
        // borderless window reaches the WindowServer. Reassert it on the next
        // main-actor turn so a freshly shown page can never flash above notes.
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.isVisible else { return }
            self.orderBelowPanels()
        }
        scheduleIdleDismissal()
    }

    /// Immediately makes every modifier-less key available to the system again.
    /// The window is ordered out rather than merely faded so visibility and key
    /// registration lifetime always have the exact same boundary.
    func hide() {
        guard isVisible else { return }
        isVisible = false
        idleTask?.cancel()
        idleTask = nil
        placementDismissTask?.cancel()
        placementDismissTask = nil
        relationshipTask?.cancel()
        relationshipTask = nil
        relationshipRevision += 1
        unregisterPlacementHotkeys()
        removeObservers()
        window.orderOut(nil)
        onHide()
    }

    /// Called by PanelManager when the set of panels changes while the page is
    /// visible. Window move/resize notifications use the cheaper geometry-only
    /// path instead of reparsing note content for every animation frame.
    func refresh() {
        guard isVisible else { return }
        updateGeometry()
        refreshRelationships()
        orderBelowPanels()
    }

    private func makeSlotFrames(visibleFrame: NSRect) -> [GridSlot: NSRect] {
        // Local coordinates (the drawing view's space); `BlinkGrid` computes in
        // whatever space it's handed, and its row-major index matches GridSlot's
        // `row * 3 + column`, so both surfaces share one source of truth.
        let localVisibleFrame = visibleFrame.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
        let frames = BlinkGrid.slotFrames(in: localVisibleFrame)
        return Dictionary(uniqueKeysWithValues: GridSlot.allCases.map { slot in
            (slot, frames[slot.row * 3 + slot.column])
        })
    }

    private func updateGeometry() {
        guard isVisible else { return }
        drawingView.panelFrames = panelsProvider().mapValues { panel in
            panel.frame.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
        }
        drawingView.needsDisplay = true
    }

    private func refreshRelationships() {
        guard isVisible else { return }
        relationshipTask?.cancel()
        relationshipRevision += 1
        let revision = relationshipRevision
        let openIDs = Set(panelsProvider().keys)

        relationshipTask = Task { [weak self, store] in
            let notes = await store.all().filter { openIDs.contains($0.id) }
            guard !Task.isCancelled else { return }
            self?.applyRelationships(from: notes, revision: revision)
        }
    }

    private func applyRelationships(from notes: [Note], revision: Int) {
        guard isVisible, revision == relationshipRevision else { return }
        let expression = try? NSRegularExpression(pattern: #"\[\[([^\]|]+)"#)
        var resolvedThreads = Set<GridThread>()

        for source in notes {
            guard let expression else { break }
            let fullRange = NSRange(source.content.startIndex..<source.content.endIndex, in: source.content)
            for match in expression.matches(in: source.content, range: fullRange) {
                guard let targetRange = Range(match.range(at: 1), in: source.content) else { continue }
                let target = source.content[targetRange]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !target.isEmpty else { continue }

                // Prefer an id match when a title happens to collide with a
                // different note's id; both comparisons are case-insensitive.
                let targetNote = notes.first {
                    $0.id != source.id && $0.id.compare(target, options: .caseInsensitive) == .orderedSame
                } ?? notes.first {
                    $0.id != source.id && $0.title.compare(target, options: .caseInsensitive) == .orderedSame
                }
                if let targetNote {
                    resolvedThreads.insert(GridThread(source.id, targetNote.id))
                }
            }
        }

        drawingView.threads = resolvedThreads
        drawingView.needsDisplay = true
    }

    private func installObservers() {
        let center = NotificationCenter.default
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            notificationObservers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.updateGeometry()
                    }
                }
            )
        }
        for name in [Notification.Name.blinkNoteUpdated, .blinkNoteDeleted] {
            notificationObservers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.refreshRelationships()
                    }
                }
            )
        }
    }

    private func removeObservers() {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
    }

    private func orderBelowPanels() {
        let openPanels = Array(panelsProvider().values.filter { $0.isVisible })
        let identities = Set(openPanels.map(ObjectIdentifier.init))
        var frontToBack = NSApp.orderedWindows.compactMap { window -> NotePanel? in
            guard let panel = window as? NotePanel,
                  identities.contains(ObjectIdentifier(panel))
            else { return nil }
            return panel
        }
        // Nonactivating panels are occasionally absent from orderedWindows
        // during their first WindowServer transaction. They still have valid
        // window numbers, so include them without waiting for another redraw.
        let alreadyOrdered = Set(frontToBack.map(ObjectIdentifier.init))
        frontToBack.append(contentsOf: openPanels.filter {
            !alreadyOrdered.contains(ObjectIdentifier($0))
        })

        if let backmostPanel = frontToBack.last {
            window.order(.below, relativeTo: backmostPanel.windowNumber)
            // Belt and braces: make the inverse relationship explicit too.
            // Iterating front-to-back preserves the panels' existing order.
            for panel in frontToBack {
                panel.order(.above, relativeTo: window.windowNumber)
            }
        } else {
            window.orderFrontRegardless()
        }
    }

    private func registerPlacementHotkeys() -> Bool {
        var registeredEveryKey = true
        for slot in GridSlot.allCases {
            if !HotkeyManager.shared.register(
                id: slot.hotkeyID,
                keyCode: slot.keyCode,
                modifiers: 0,
                callback: { [weak self] in self?.placePanel(in: slot) }
            ) {
                registeredEveryKey = false
            }
        }
        if !HotkeyManager.shared.register(
            id: Self.escapeHotkeyID,
            keyCode: UInt32(kVK_Escape),
            modifiers: 0,
            callback: { [weak self] in self?.hide() }
        ) {
            registeredEveryKey = false
        }
        return registeredEveryKey
    }

    private func unregisterPlacementHotkeys() {
        for slot in GridSlot.allCases {
            HotkeyManager.shared.unregister(id: slot.hotkeyID)
        }
        HotkeyManager.shared.unregister(id: Self.escapeHotkeyID)
    }

    private func placePanel(in slot: GridSlot) {
        guard isVisible, let localFrame = drawingView.slotFrames[slot] else { return }
        if let panel = placementPanelProvider() {
            let globalFrame = localFrame.offsetBy(dx: screenFrame.minX, dy: screenFrame.minY)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(globalFrame, display: true)
            } completionHandler: { [weak self, weak panel] in
                MainActor.assumeIsolated {
                    if let panel {
                        panel.saveFrame(usingName: "blink.note.\(panel.noteID)")
                    }
                    self?.updateGeometry()
                }
            }
        }

        idleTask?.cancel()
        idleTask = nil
        placementDismissTask?.cancel()
        placementDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    private func scheduleIdleDismissal() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }
}
