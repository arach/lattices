import AppKit
import BlinkCore
import HudsonObservability

/// A selection lifted out of the frontmost app — usually a long answer in a
/// terminal — and set as a reading sheet over the dimmed screen. Transient:
/// Esc, ⌘W, a click outside the sheet, the hotkey again, or switching to
/// another app puts it away; ⌘S keeps it as a note.
///
/// Arrival is one sequence, drawn in fab's Woven language (`ReaderChrome`):
/// the cue lands by the cursor the instant the hotkey fires, the screen dims
/// and the sheet rises while the cue flies to its centre, and once the editor
/// is ready the cue fades and the text streams in block by block. The editor
/// starts loading in parallel with the selection grab.
///
/// Two windows: a full-screen backdrop and the sheet above it. The sheet is a
/// titled, resizable window at the normal level, and Blink activates while it
/// is up, so it is the frontmost app's focused window — the target window
/// managers (Lattices placement shortcuts) act on. Wherever it gets placed is
/// where it opens next time on that screen.
///
/// It is not a note: its text never touches NoteStore unless kept, and it
/// renders under the editor's untrusted-text policy.
@MainActor
final class ReaderLayer {
    /// Keep the current text as a new note.
    var onKeep: ((String) -> Void)?

    private var backdrop: ReaderBackdrop?
    private var column: ReaderColumn?
    private var editor: EditorWebView?
    private var cue: ReaderCue?
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    /// The app the selection came from, reactivated on close.
    private var sourceApp: NSRunningApplication?
    private var text = ""
    private var fontSize: Double = 17
    /// Between the hotkey and the sheet: the grab is in flight.
    private var isArriving = false
    /// Stream once both are true: the editor reported ready, the sheet settled.
    private var editorReady = false
    private var sheetSettled = false
    private var pendingStream: String?
    private let log = HudLogger(category: "blink.reader")

    private static let frameKey = "reader.columnFrame"
    /// The sheet's rise and the cue's flight to its centre.
    private static let settleDuration: TimeInterval = 0.42

    var isVisible: Bool { column != nil }

    /// Grab the selection and present it; a second press closes the layer.
    func toggle() {
        if isVisible {
            close()
            return
        }
        guard !isArriving else { return }
        isArriving = true

        let config = BlinkConfigStore.shared.config
        let scheme = AppearanceManager.shared.scheme
        fontSize = config.reader.fontSize

        let cue = ReaderCue(scheme: scheme)
        cue.show(at: NSEvent.mouseLocation)
        self.cue = cue

        // Load the editor while the grab runs; it is the slow part.
        let editor = EditorWebView()
        editorReady = false
        sheetSettled = false
        pendingStream = nil
        editor.onReady = { [weak self] in
            self?.editorReady = true
            self?.streamIfReady()
        }
        editor.onContentChanged = { [weak self] text in self?.text = text }
        editor.load()
        editor.setUntrusted(true)
        editor.setSheet("card")
        editor.setTheme(themeVars(config))
        editor.setMode("read")
        self.editor = editor

        Task {
            let selection = await SelectionGrabber.grab()
            isArriving = false
            let cleaned = selection.map { TerminalText.clean($0.text) } ?? ""
            guard let selection, !cleaned.isEmpty else {
                abandonArrival()
                NSSound.beep()
                return
            }
            log.info(
                "[BLINK] reader opened",
                metadata: [
                    "source": selection.source.rawValue,
                    "app": selection.app?.bundleIdentifier ?? "?",
                    "chars": "\(cleaned.count)",
                ]
            )
            present(cleaned, from: selection.app)
        }
    }

    /// Re-theme a live layer after a config or appearance change.
    func applyTheme(_ config: BlinkConfig) {
        guard let backdrop, let column, let editor else { return }
        backdrop.apply(config)
        column.apply()
        editor.setTheme(themeVars(config))
    }

    // MARK: - Presentation

    private func present(_ content: String, from app: NSRunningApplication?) {
        let config = BlinkConfigStore.shared.config
        let mouse = NSEvent.mouseLocation
        guard let editor,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        else {
            abandonArrival()
            return
        }

        text = content
        sourceApp = app

        let backdrop = ReaderBackdrop(screen: screen, config: config)
        backdrop.onClick = { [weak self] in self?.close() }
        let frame = columnFrame(on: screen, config: config)
        let column = ReaderColumn(frame: frame, webView: editor.webView)

        // The sheet rises 14pt into place (fab's mock rise) as the screen dims.
        let rise: CGFloat = Woven.reduceMotion ? 0 : 14
        backdrop.alphaValue = 0
        column.alphaValue = 0
        column.setFrame(frame.offsetBy(dx: 0, dy: -rise), display: false)

        // Blink has to be the active app for its window to be the one
        // placement shortcuts resolve as frontmost.
        NSApp.activate()
        backdrop.orderFront(nil)
        column.makeKeyAndOrderFront(nil)
        column.makeFirstResponder(editor.webView)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = Woven.expoOut
            backdrop.animator().alphaValue = 1
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.settleDuration
            context.timingFunction = Woven.expoOut
            column.animator().alphaValue = 1
            column.animator().setFrame(frame, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.sheetSettled = true
                self?.streamIfReady()
            }
        }
        cue?.settle(centeredIn: frame, duration: Self.settleDuration)

        self.backdrop = backdrop
        self.column = column
        pendingStream = content
        installKeyMonitor()
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close(reactivate: false) }
        }
    }

    /// The last beat: the cue gives way and the text streams in.
    private func streamIfReady() {
        guard editorReady, sheetSettled, let content = pendingStream, let editor else { return }
        pendingStream = nil
        editor.stream(content)
        cue?.dismiss()
        cue = nil
    }

    /// The grab found nothing: take the cue back and drop the preloaded editor.
    private func abandonArrival() {
        isArriving = false
        cue?.dismiss()
        cue = nil
        editor?.teardown()
        editor = nil
    }

    func close() {
        close(reactivate: true)
    }

    private func close(reactivate: Bool) {
        guard let column, let backdrop else { return }
        UserDefaults.standard.set(NSStringFromRect(column.frame), forKey: Self.frameKey)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        cue?.dismiss()
        cue = nil
        pendingStream = nil
        editor?.teardown()
        editor = nil
        self.column = nil
        self.backdrop = nil

        if reactivate, NSApp.isActive, let sourceApp, !sourceApp.isTerminated {
            sourceApp.activate()
        }
        sourceApp = nil

        // Exits only fade.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            column.animator().alphaValue = 0
            backdrop.animator().alphaValue = 0
        } completionHandler: {
            // orderOut, never an idle alpha-0 window: Mission Control would
            // show it as a bare thumbnail.
            MainActor.assumeIsolated {
                column.orderOut(nil)
                backdrop.orderOut(nil)
            }
        }
    }

    private func keep() {
        let content = text
        close(reactivate: false)
        onKeep?(content)
    }

    /// The last placed frame when it sits on `screen`; otherwise a centered
    /// sheet in the screen's visible frame.
    private func columnFrame(on screen: NSScreen, config: BlinkConfig) -> NSRect {
        let visible = screen.visibleFrame
        if let saved = UserDefaults.standard.string(forKey: Self.frameKey) {
            let frame = NSRectFromString(saved)
            if frame.width >= 200, frame.height >= 200,
               visible.contains(NSPoint(x: frame.midX, y: frame.midY)) {
                return frame
            }
        }
        let width = min(config.reader.width, visible.width * 0.8)
        let height = visible.height * 0.86
        return NSRect(
            x: visible.midX - width / 2,
            y: visible.midY - height / 2,
            width: width,
            height: height
        ).integral
    }

    // MARK: - Keys

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let column = self.column, event.window === column else { return event }
            return self.handle(event) ? nil : event
        }
    }

    /// Returns true when the reader consumed the key.
    private func handle(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        if event.keyCode == 53 {  // Esc
            close()
            return true
        }
        guard mods == .command || mods == [.command, .shift] else { return false }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "w":
            close()
        case "s":
            keep()
        case "=", "+":
            resize(by: 1)
        case "-":
            resize(by: -1)
        case "0":
            fontSize = BlinkConfigStore.shared.config.reader.fontSize
            editor?.setTheme(themeVars(BlinkConfigStore.shared.config))
        default:
            return false
        }
        return true
    }

    private func resize(by step: Double) {
        fontSize = min(32, max(11, fontSize + step))
        editor?.setTheme(themeVars(BlinkConfigStore.shared.config))
    }

    // MARK: - Theme

    private func themeVars(_ config: BlinkConfig) -> [String: String] {
        let scheme = AppearanceManager.shared.scheme
        var vars = config.editorThemeVars(scheme: scheme)
        vars.merge(Woven.editorVars(scheme)) { _, woven in woven }
        vars["--blink-font-size"] = "\(fontSize)px"
        vars["--blink-h1-size"] = "\((fontSize * 1.5).rounded())px"
        vars["--blink-h2-size"] = "\((fontSize * 1.28).rounded())px"
        vars["--blink-h3-size"] = "\((fontSize * 1.1).rounded())px"
        vars["--blink-card-pad-x"] = "\(Int(fontSize * 2.6))px"
        vars["--blink-card-pad-y"] = "\(Int(fontSize * 2.2))px"
        return vars
    }
}

// MARK: - Windows

/// The full-screen dim behind the sheet, with the shortcut keycaps along the
/// bottom. Untitled and never key, so window managers don't treat it as a
/// placement target; a click on it dismisses the layer.
@MainActor
private final class ReaderBackdrop: NSWindow {
    var onClick: (() -> Void)?

    private let veil = BackdropView()

    init(screen: NSScreen, config: BlinkConfig) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        collectionBehavior = [.fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        setFrame(screen.frame, display: false)

        veil.wantsLayer = true
        veil.onClick = { [weak self] in self?.onClick?() }
        contentView = veil

        let hints = readerHints([
            (["esc"], "close"),
            (["⌘S"], "keep"),
            (["⌘+", "⌘−"], "size"),
        ])
        hints.translatesAutoresizingMaskIntoConstraints = false
        veil.addSubview(hints)
        NSLayoutConstraint.activate([
            hints.centerXAnchor.constraint(equalTo: veil.centerXAnchor),
            hints.bottomAnchor.constraint(equalTo: veil.bottomAnchor, constant: -22),
        ])

        apply(config)
    }

    func apply(_ config: BlinkConfig) {
        veil.layer?.backgroundColor = Woven.veil.withAlphaComponent(config.reader.dim).cgColor
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The reading sheet: a solid Woven sheet (fill, 1pt ink hairline, 14pt
/// radius) holding the editor webview in read mode. Titled, resizable, and at
/// the normal level so AX placement works.
@MainActor
private final class ReaderColumn: NSWindow {
    private let surface = NSView()

    init(frame: NSRect, webView: NSView) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        // Names the window for AX and window managers; borderless, so never drawn.
        title = "Reader"
        collectionBehavior = [.fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        minSize = NSSize(width: 280, height: 200)
        setFrame(frame, display: false)

        surface.wantsLayer = true
        surface.layer?.cornerRadius = 14
        surface.layer?.cornerCurve = .continuous
        surface.layer?.masksToBounds = true
        surface.layer?.borderWidth = 1
        contentView = surface

        webView.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: surface.topAnchor),
            webView.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
        ])

        apply()
    }

    func apply() {
        let scheme = AppearanceManager.shared.scheme
        let palette = Woven.palette(scheme)
        appearance = NSAppearance(named: scheme.nsAppearanceName)
        surface.layer?.backgroundColor = palette.sheet.cgColor
        // A layer's border draws above its sublayers, so the hairline stays
        // visible over the webview's own fill.
        surface.layer?.borderColor = palette.hairline.cgColor
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The backdrop's root; a click on it dismisses the layer.
private final class BackdropView: NSView {
    var onClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
