import AppKit
import SwiftUI

// MARK: - Hint assignment

/// Home-row jump letters for the nav-hint overlay (reading order on screen).
enum InPlaceWindowHintAssigner {
    static let reservedKeys: Set<Character> = ["e", "g"]
    private static let alphabet: [String] = Array("asdfghjklqwertyuiopzxcvbnm")
        .filter { !reservedKeys.contains($0) }
        .map(String.init)

    /// Assign one letter per window in display reading order (top→bottom, left→right).
    static func assign(windows: [WindowEntry]) -> [UInt32: String] {
        let ordered = windows
            .filter(\.isOnScreen)
            .sorted { a, b in
                if a.frame.y != b.frame.y { return a.frame.y < b.frame.y }
                return a.frame.x < b.frame.x
            }
        var map: [UInt32: String] = [:]
        for (index, window) in ordered.enumerated() where index < alphabet.count {
            map[window.wid] = alphabet[index]
        }
        return map
    }

    static func reverse(_ hints: [UInt32: String]) -> [String: UInt32] {
        var map: [String: UInt32] = [:]
        for (wid, letter) in hints { map[letter] = wid }
        return map
    }
}

// MARK: - Badge

/// Top-right jump letter — same chrome as the HUD badges, no modifier prefix.
struct WindowNavHintBadge: View {
    let letter: String

    static let glowMargin: CGFloat = 7

    var body: some View {
        Text(letter.uppercased())
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .foregroundColor(HUDChrome.cyan)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [HUDChrome.baseTop, HUDChrome.baseBottom],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(HUDChrome.cyan.opacity(0.55), lineWidth: 1)
            )
            .shadow(color: HUDChrome.cyan.opacity(0.30), radius: 6, y: 1)
            .shadow(color: Color.black.opacity(0.45), radius: 5, y: 2)
            .padding(Self.glowMargin)
            .fixedSize()
    }
}

// MARK: - Overlay controller

/// Toggle with Hyper+H: every visible window wears a jump letter. Press the letter
/// to focus that window; Esc or click dismisses. Does not enter in-place or Hyperspace.
final class InPlaceChordHintOverlay {
    static let shared = InPlaceChordHintOverlay()

    private struct Bezel {
        let panel: NSPanel
        let hosting: NSHostingView<WindowNavHintBadge>
    }

    private static let cornerGap: CGFloat = 3

    private var bezels: [UInt32: Bezel] = [:]
    private var hints: [UInt32: String] = [:]
    private var hintMap: [String: UInt32] = [:]
    private var hiddenWids: Set<UInt32> = []
    private var keyEventTap: CFMachPort?
    private var keyRunLoopSource: CFRunLoopSource?
    private var clickMonitor: Any?
    private var pollTimer: Timer?

    private(set) var isVisible = false

    func toggle() {
        if isVisible { dismiss() } else { show() }
    }

    func show() {
        DesktopModel.shared.forcePoll()
        isVisible = true
        refreshHints()
        guard installMonitors() else {
            DiagnosticLog.shared.warn("Window nav hints: unable to capture navigation keys")
            NSSound.beep()
            dismiss()
            return
        }
        startPolling()
        applyVisibility()
    }

    func dismiss() {
        isVisible = false
        removeMonitors()
        pollTimer?.invalidate()
        pollTimer = nil
        for bezel in bezels.values { bezel.panel.orderOut(nil) }
        bezels.removeAll()
        hiddenWids.removeAll()
        hints.removeAll()
        hintMap.removeAll()
    }

    // MARK: - Direct access

    private func jump(to letter: String) {
        guard let wid = hintMap[letter.lowercased()],
              let window = DesktopModel.shared.windows[wid] else { NSSound.beep(); return }
        dismiss()
        _ = WindowTiler.focusWindow(wid: window.wid, pid: window.pid)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 900
        let frame = appKitRect(for: window.frame, primaryHeight: primaryHeight)
        WindowHighlight.shared.flash(frame: frame)
    }

    // MARK: - Layout

    private func refreshHints() {
        let myPid = ProcessInfo.processInfo.processIdentifier
        let eligible = DesktopModel.shared.allWindows()
            .filter { $0.pid != myPid && $0.isOnScreen && !$0.title.isEmpty }
        hints = InPlaceWindowHintAssigner.assign(windows: eligible)
        hintMap = InPlaceWindowHintAssigner.reverse(hints)
        updateBezels()
    }

    private func updateBezels() {
        let windows = DesktopModel.shared.windows
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 900
        let screenFrames = NSScreen.screens.map(\.frame)
        let allWindows = Array(windows.values)

        for wid in Array(bezels.keys) where hints[wid] == nil { drop(wid) }

        var nextHidden: Set<UInt32> = []
        for (wid, letter) in hints {
            guard let window = windows[wid], window.isOnScreen else { drop(wid); continue }
            let frame = appKitRect(for: window.frame, primaryHeight: primaryHeight)
            guard screenFrames.contains(where: { $0.intersects(frame) }) else { drop(wid); continue }

            let bezel = bezels[wid] ?? makeBezel()
            bezel.hosting.rootView = WindowNavHintBadge(letter: letter)
            let size = bezel.hosting.fittingSize
            bezel.panel.setContentSize(size)

            let originX = frame.maxX - Self.cornerGap - size.width
            let originY = frame.maxY - Self.cornerGap - size.height
            bezel.panel.setFrameOrigin(NSPoint(x: originX, y: originY))
            bezels[wid] = bezel

            let centerAppKit = NSPoint(x: originX + size.width / 2, y: originY + size.height / 2)
            let centerCG = CGPoint(x: centerAppKit.x, y: primaryHeight - centerAppKit.y)
            let occluded = allWindows.contains { other in
                other.wid != wid && other.isOnScreen && other.zIndex < window.zIndex &&
                cgRect(other.frame).contains(centerCG)
            }
            if occluded { nextHidden.insert(wid) }
        }

        hiddenWids = nextHidden
        if isVisible { applyVisibility() }
    }

    private func applyVisibility() {
        for (wid, bezel) in bezels {
            let shouldShow = isVisible && !hiddenWids.contains(wid)
            bezel.panel.alphaValue = shouldShow ? 1 : 0
            if shouldShow { bezel.panel.orderFrontRegardless() }
        }
    }

    private func drop(_ wid: UInt32) {
        bezels[wid]?.panel.orderOut(nil)
        bezels.removeValue(forKey: wid)
    }

    private func makeBezel() -> Bezel {
        let hosting = NSHostingView(rootView: WindowNavHintBadge(letter: ""))
        hosting.sizingOptions = []
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 64, height: 36),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.alphaValue = 0
        panel.sharingType = .readOnly
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = hosting
        return Bezel(panel: panel, hosting: hosting)
    }

    // MARK: - Monitors

    private func installMonitors() -> Bool {
        guard installKeyEventTap() else { return false }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
        return true
    }

    private func removeMonitors() {
        if let source = keyRunLoopSource {
            EventTapThread.shared.remove(source: source)
        }
        keyRunLoopSource = nil
        if let tap = keyEventTap {
            CFMachPortInvalidate(tap)
        }
        keyEventTap = nil
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
    }

    /// A global NSEvent monitor can observe a hint letter but cannot consume it,
    /// which would also type that letter into the foreground app. A short-lived
    /// session event tap makes the hint overlay a true keyboard mode: handled
    /// letters and Escape are swallowed, while unrelated shortcuts pass through.
    private func installKeyEventTap() -> Bool {
        var mask = CGEventMask(0)
        mask |= CGEventMask(1) << CGEventType.keyDown.rawValue
        mask |= CGEventMask(1) << CGEventType.keyUp.rawValue

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.keyEventTapCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        keyEventTap = tap
        keyRunLoopSource = source
        if let source {
            EventTapThread.shared.add(source: source)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private static let keyEventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let overlay = Unmanaged<InPlaceChordHintOverlay>.fromOpaque(userInfo).takeUnretainedValue()
        return overlay.handleKeyEvent(type: type, event: event)
    }

    private func handleKeyEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let keyEventTap { CGEvent.tapEnable(tap: keyEventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard isVisible, type == .keyDown || type == .keyUp,
              let nsEvent = NSEvent(cgEvent: event) else {
            return Unmanaged.passUnretained(event)
        }

        let flags = nsEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.isEmpty || flags == .capsLock else {
            return Unmanaged.passUnretained(event)
        }

        if nsEvent.keyCode == 53 {
            if type == .keyDown {
                DispatchQueue.main.async { [weak self] in self?.dismiss() }
            }
            return nil
        }

        guard let key = nsEvent.charactersIgnoringModifiers?.lowercased(),
              key.count == 1,
              key.first?.isLetter == true else {
            return Unmanaged.passUnretained(event)
        }
        if type == .keyDown {
            DispatchQueue.main.async { [weak self] in self?.jump(to: key) }
        }
        return nil
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            guard let self, self.isVisible else { return }
            DesktopModel.shared.poll()
            self.updateBezels()
        }
    }

    // MARK: - Geometry

    private func cgRect(_ frame: WindowFrame) -> CGRect {
        CGRect(x: frame.x, y: frame.y, width: frame.w, height: frame.h)
    }

    private func appKitRect(for frame: WindowFrame, primaryHeight: CGFloat) -> NSRect {
        NSRect(
            x: frame.x,
            y: primaryHeight - frame.y - frame.h,
            width: frame.w,
            height: frame.h
        )
    }
}
