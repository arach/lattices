import AppKit
import Combine

/// Pure state for a right-click under the physical ⌃⌥ hold. A stroke that
/// starts on an exact ⌃⌥ right-down (no ⌘ or ⇧: the Caps-to-Hyper chord
/// carries all four) is the menu's, its drags and its release included,
/// whatever the modifiers do meanwhile. The menu opens on the release, and no
/// stroke starts until it closes.
struct WindowQuickMenuStroke {
    enum Verdict: Equatable { case pass, consume, open }

    private var owned = false
    private(set) var menuOpen = false

    /// A stroke is under way or its menu is up.
    var isActive: Bool { owned || menuOpen }

    mutating func rightMouseDown(control: Bool, option: Bool, command: Bool, shift: Bool) -> Verdict {
        owned = !menuOpen && control && option && !command && !shift
        return owned ? .consume : .pass
    }

    func rightMouseDragged() -> Verdict { owned ? .consume : .pass }

    mutating func rightMouseUp() -> Verdict {
        guard owned else { return .pass }
        owned = false
        menuOpen = true
        return .open
    }

    mutating func menuClosed() { menuOpen = false }

    /// The tap went away or was disabled, so a release may never come.
    mutating func reset() { owned = false }
}

/// Hold ⌃⌥ and right-click a window: a menu that sends it to a ⌘⌥ layer, a
/// desktop or a display. It acts on the window under the pointer, not the
/// frontmost one. The click never reaches the app, and the hold's own use
/// (Tile HUD or Spatial Lens) stands down for it, so letting go of ⌃⌥
/// neither tiles nor places.
final class WindowQuickMenu {
    static let shared = WindowQuickMenu()

    /// How long a move waits for the modifiers to lift. A desktop move drags
    /// in Mission Control, and held modifiers ride on its synthetic drag.
    private static let releaseWait: TimeInterval = 4

    private let lock = NSLock()
    private var stroke = WindowQuickMenuStroke()   // under lock; the tap thread writes it
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var subscriptions: Set<AnyCancellable> = []

    // Main thread only.
    private var target: WindowEntry?

    private init() {}

    /// A ⌃⌥ right-click is under way or its menu is up. The Tile HUD and
    /// Spatial Lens don't start meanwhile.
    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stroke.isActive
    }

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard subscriptions.isEmpty else { return }
        Preferences.shared.$ctrlOptionHoldMode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
        PermissionChecker.shared.$accessibility
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
    }

    // MARK: Tap

    private func refresh() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard Preferences.shared.ctrlOptionHoldMode != .off,
              PermissionChecker.shared.accessibility else {
            removeTap()
            return
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        } else {
            installTap()
        }
    }

    private func installTap() {
        var mask = CGEventMask(0)
        mask |= CGEventMask(1) << CGEventType.rightMouseDown.rawValue
        mask |= CGEventMask(1) << CGEventType.rightMouseDragged.rawValue
        mask |= CGEventMask(1) << CGEventType.rightMouseUp.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.callback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            DiagnosticLog.shared.warn("QuickMenu: couldn't install the ⌃⌥ right-click tap")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source
        if let source { EventTapThread.overlay.add(source: source) }
        CGEvent.tapEnable(tap: tap, enable: true)
        DiagnosticLog.shared.info("QuickMenu: ⌃⌥ right-click ready")
    }

    private func removeTap() {
        if let runLoopSource { EventTapThread.overlay.remove(source: runLoopSource) }
        runLoopSource = nil
        if let eventTap { CFMachPortInvalidate(eventTap) }
        eventTap = nil
        lock.lock()
        stroke.reset()
        lock.unlock()
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let menu = Unmanaged<WindowQuickMenu>.fromOpaque(userInfo).takeUnretainedValue()
        return menu.handle(type, event) ? nil : Unmanaged.passUnretained(event)
    }

    /// On the tap thread. True when the event is the menu's and goes no
    /// further.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let verdict: WindowQuickMenuStroke.Verdict
        lock.lock()
        switch type {
        case .rightMouseDown:
            let flags = event.flags
            verdict = stroke.rightMouseDown(
                control: flags.contains(.maskControl),
                option: flags.contains(.maskAlternate),
                command: flags.contains(.maskCommand),
                shift: flags.contains(.maskShift)
            )
        case .rightMouseDragged:
            verdict = stroke.rightMouseDragged()
        case .rightMouseUp:
            verdict = stroke.rightMouseUp()
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            stroke.reset()
            verdict = .pass
            DispatchQueue.main.async { [weak self] in self?.refresh() }
        default:
            verdict = .pass
        }
        lock.unlock()

        switch verdict {
        case .pass:
            return false
        case .consume:
            if type == .rightMouseDown {
                let point = event.location
                DispatchQueue.main.async { [weak self] in self?.began(at: point) }
            }
            return true
        case .open:
            DispatchQueue.main.async { [weak self] in self?.open() }
            return true
        }
    }

    // MARK: Menu

    /// The stroke's first moment: the hold stands down and the window under
    /// the pointer (`point`, CG global) becomes the menu's.
    private func began(at point: CGPoint) {
        TilePointerController.shared.cancelApply()
        BundleModules.resetForSystemInputBoundary(reason: "quick menu")
        target = DesktopModel.shared.liveFrontWindow(at: point, excludingPid: getpid())
    }

    private func open() {
        defer {
            lock.lock()
            stroke.menuClosed()
            lock.unlock()
        }
        guard let live = target else {
            DiagnosticLog.shared.info("QuickMenu: no window under the pointer")
            return
        }
        target = nil
        let window = DesktopModel.shared.windows[live.wid] ?? live
        DiagnosticLog.shared.info("QuickMenu: \(window.app) wid=\(window.wid)")
        makeMenu(for: window).popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func makeMenu(for window: WindowEntry) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(.sectionHeader(title: Self.heading(for: window)))
        if let layers = layerItem(for: window) { menu.addItem(layers) }
        let target = WindowMoveMenuModel.Target(wid: window.wid, pid: window.pid)
        WindowMovementMenuBuilder.appendSection(
            to: menu,
            model: WindowMovementService.menuModel(windowFrame: window.frame, targets: [target], anchorWid: window.wid),
            onMove: { display in
                self.afterRelease {
                    WindowMovementService.moveTargets([target], to: display) { self.report($0.message, ok: $0.ok) }
                }
            },
            onMoveDesktop: { desktop in
                self.afterRelease {
                    WindowMovementService.moveTargets([target], to: desktop) { self.report($0.message, ok: $0.ok) }
                }
            }
        )
        return menu
    }

    /// "Move to Layer", with the layer that holds the window ticked. Nil
    /// when there are no layers or the window isn't one a layer can hold.
    private func layerItem(for window: WindowEntry) -> NSMenuItem? {
        let workspace = WorkspaceManager.shared
        let layers = workspace.layers
        guard !layers.isEmpty, DesktopModel.isContent(window) else { return nil }
        let current = workspace.layerMembership(in: DesktopModel.shared.allWindows())
            .owners[window.wid].flatMap { workspace.layerIndex(id: $0.layerId) }

        let submenu = NSMenu()
        for (index, layer) in layers.enumerated() {
            let item: NSMenuItem
            if index == current {
                item = NSMenuItem(title: layer.label, action: nil, keyEquivalent: "")
                item.state = .on
            } else {
                item = NSMenuItem(title: layer.label, action: #selector(WindowMovementMenuTarget.perform(_:)), keyEquivalent: "")
                item.target = WindowMovementMenuTarget.shared
                item.representedObject = WindowMovementMenuAction { self.send(window, from: current, to: index) }
            }
            submenu.addItem(item)
        }
        let item = NSMenuItem(title: "Move to Layer", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    /// Membership only: the window moves when its layer is next switched to.
    private func send(_ window: WindowEntry, from current: Int?, to index: Int) {
        let workspace = WorkspaceManager.shared
        guard workspace.layers.indices.contains(index) else { return }
        let name = workspace.layers[index].label
        do {
            if let current, workspace.layers.indices.contains(current) {
                let source = workspace.layers[current].label
                switch try workspace.moveWindow(window, from: current, to: index) {
                case .moved: report("Sent to \(name)", ok: true)
                case .copied: report("Also in \(name); an entry in \(source) still matches it", ok: true)
                case .unchanged: report("Already in \(name)", ok: true)
                }
            } else {
                let added = try workspace.addWindows([window], toLayer: index)
                report(added > 0 ? "Sent to \(name)" : "Already in \(name)", ok: true)
            }
        } catch {
            report(error.localizedDescription, ok: false)
        }
    }

    /// Runs `work` once no modifier is held, or after `releaseWait`.
    private func afterRelease(_ work: @escaping () -> Void) {
        let deadline = Date().addingTimeInterval(Self.releaseWait)
        func attempt() {
            let held = CGEventSource.flagsState(.combinedSessionState)
                .intersection([.maskControl, .maskAlternate, .maskCommand, .maskShift])
            if held.isEmpty || Date() >= deadline {
                work()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { attempt() }
            }
        }
        attempt()
    }

    private func report(_ text: String, ok: Bool) {
        if ok { AppFeedback.shared.commitHaptic() }
        ScreenOverlayCanvasController.shared.publishLayer(ScreenOverlayLayerSnapshot(
            id: ScreenOverlayLayerID("quickMenu.result"),
            owner: .quickMenu,
            screen: .all,
            zIndex: 700,
            opacity: 1,
            payload: .toast(ScreenOverlayTextPayload(
                text: text,
                detail: nil,
                point: nil,
                placement: .bottom,
                style: ok ? .info : .warning
            )),
            expiresAt: Date().addingTimeInterval(ok ? 1.6 : 2.6)
        ))
    }

    private static func heading(for window: WindowEntry) -> String {
        let title = (window.fullTitle ?? window.title).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != window.app else { return window.app }
        let short = title.count > 48 ? String(title.prefix(47)) + "…" : title
        return "\(window.app) — \(short)"
    }
}
