import AppKit
import BlinkCore
import HudsonObservability

/// A selection lifted out of the frontmost app — usually a long answer in a
/// terminal — and set as a reading column over a blurred, dimmed screen.
/// Transient: Esc, ⌘W, a click outside the column, the hotkey again, or
/// switching to another app puts it away; ⌘S keeps it as a note.
///
/// Two windows: a full-screen backdrop and the column above it. The column is
/// a titled, resizable window at the normal level, and Blink activates while
/// it is up, so it is the frontmost app's focused window — the target window
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
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    /// The app the selection came from, reactivated on close.
    private var sourceApp: NSRunningApplication?
    private var text = ""
    private var fontSize: Double = 17
    private let log = HudLogger(category: "blink.reader")

    private static let frameKey = "reader.columnFrame"

    var isVisible: Bool { column != nil }

    /// Grab the selection and present it; a second press closes the layer.
    func toggle() {
        if isVisible {
            close()
            return
        }
        Task {
            guard let selection = await SelectionGrabber.grab() else {
                NSSound.beep()
                return
            }
            let cleaned = TerminalText.clean(selection.text)
            guard !cleaned.isEmpty else {
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
        column.apply(config)
        editor.setTheme(themeVars(config))
    }

    // MARK: - Presentation

    private func present(_ content: String, from app: NSRunningApplication?) {
        let config = BlinkConfigStore.shared.config
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        else { return }

        text = content
        fontSize = config.reader.fontSize
        sourceApp = app

        let editor = EditorWebView()
        editor.onContentChanged = { [weak self] text in self?.text = text }
        editor.load()
        editor.setUntrusted(true)
        editor.setSheet("glass")
        editor.setTheme(themeVars(config))
        editor.setMode("read")
        editor.setContent(content)

        let backdrop = ReaderBackdrop(screen: screen, config: config)
        backdrop.onClick = { [weak self] in self?.close() }
        let column = ReaderColumn(
            frame: columnFrame(on: screen, config: config),
            config: config,
            webView: editor.webView
        )

        backdrop.alphaValue = 0
        column.alphaValue = 0
        // Blink has to be the active app for its window to be the one
        // placement shortcuts resolve as frontmost.
        NSApp.activate()
        backdrop.orderFront(nil)
        column.makeKeyAndOrderFront(nil)
        column.makeFirstResponder(editor.webView)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            backdrop.animator().alphaValue = 1
            column.animator().alphaValue = 1
        }

        self.editor = editor
        self.backdrop = backdrop
        self.column = column
        installKeyMonitor()
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close(reactivate: false) }
        }
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
        editor?.teardown()
        editor = nil
        self.column = nil
        self.backdrop = nil

        if reactivate, NSApp.isActive, let sourceApp, !sourceApp.isTerminated {
            sourceApp.activate()
        }
        sourceApp = nil

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
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
    /// column in the screen's visible frame.
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
        var vars = config.editorThemeVars(scheme: AppearanceManager.shared.scheme)
        vars["--blink-font-size"] = "\(fontSize)px"
        vars["--blink-pad-x"] = "\(Int(fontSize * 2.6))px"
        vars["--blink-pad-y"] = "\(Int(fontSize * 2.2))px"
        return vars
    }
}

// MARK: - Windows

/// The full-screen blur + dim behind the column. Untitled and never key, so
/// window managers don't treat it as a placement target; a click on it
/// dismisses the layer.
@MainActor
private final class ReaderBackdrop: NSWindow {
    var onClick: (() -> Void)?

    private let blur = PassthroughEffectView()
    private let dimView = NSView()
    private let hints = NSTextField(labelWithString: "esc  ·  ⌘S keep  ·  ⌘+ ⌘−")

    init(screen: NSScreen, config: BlinkConfig) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        collectionBehavior = [.fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        setFrame(screen.frame, display: false)

        // Blur and dim are siblings under a plain root: content nested inside
        // a behind-window effect view doesn't draw.
        let root = BackdropView()
        root.onClick = { [weak self] in self?.onClick?() }
        contentView = root

        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        pin(blur, to: root)

        dimView.wantsLayer = true
        pin(dimView, to: root)

        hints.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        hints.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(hints)
        NSLayoutConstraint.activate([
            hints.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            hints.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18),
        ])

        apply(config)
    }

    func apply(_ config: BlinkConfig) {
        let scheme = AppearanceManager.shared.scheme
        appearance = NSAppearance(named: scheme.nsAppearanceName)
        let base: NSColor = scheme.isDark ? .black : .white
        dimView.layer?.backgroundColor = base.withAlphaComponent(config.reader.dim).cgColor
        hints.textColor = (scheme.isDark ? NSColor.white : NSColor.black).withAlphaComponent(0.4)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The reading column: glass, contrast tint, and the editor webview in read
/// mode. Titled, resizable, and at the normal level so AX placement works.
@MainActor
private final class ReaderColumn: NSWindow {
    private let container = NSView()
    private let glass = NSVisualEffectView()
    private let tint = NSView()

    init(frame: NSRect, config: BlinkConfig, webView: NSView) {
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

        container.wantsLayer = true
        container.layer?.masksToBounds = true
        contentView = container

        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.masksToBounds = true
        pin(glass, to: container)
        tint.wantsLayer = true
        pin(tint, to: container)
        pin(webView, to: container)

        apply(config)
    }

    func apply(_ config: BlinkConfig) {
        let scheme = AppearanceManager.shared.scheme
        appearance = NSAppearance(named: scheme.nsAppearanceName)
        glass.material = NotePanel.glassMaterial(config, scheme)
        tint.layer?.backgroundColor = NotePanel.tintColor(scheme)
        tint.alphaValue = config.panel.tintRead
        container.layer?.cornerRadius = config.panel.cornerRadius
        glass.layer?.cornerRadius = config.panel.cornerRadius
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

/// The full-screen blur; clicks fall through to the root.
private final class PassthroughEffectView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
private func pin(_ view: NSView, to parent: NSView) {
    view.translatesAutoresizingMaskIntoConstraints = false
    parent.addSubview(view)
    NSLayoutConstraint.activate([
        view.topAnchor.constraint(equalTo: parent.topAnchor),
        view.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
        view.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
        view.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
    ])
}
