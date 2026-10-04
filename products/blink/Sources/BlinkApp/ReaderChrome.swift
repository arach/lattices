import AppKit
import QuartzCore

/// The reader layer's look, in fab's Woven language: paper and ink, one
/// vermilion thread for the live thing (the working cue), solid sheets with a
/// hairline instead of glass, expo-out rises, fade-only exits, no springs.
enum Woven {
    struct Palette {
        let sheet: NSColor
        let ink: NSColor
        let inkSoft: NSColor
        let label: NSColor
        let hairline: NSColor
        let thread: NSColor
    }

    static func palette(_ scheme: AppScheme) -> Palette {
        scheme.isDark ? night : paper
    }

    static let paper = Palette(
        sheet: hex(0xFAF6EC),
        ink: hex(0x1D1B18),
        inkSoft: hex(0x5C564B),
        label: hex(0x6B6558),
        hairline: hex(0x1D1B18, alpha: 0.12),
        thread: hex(0xB64025)
    )

    static let night = Palette(
        sheet: hex(0x211E18),
        ink: hex(0xEFE8D8),
        inkSoft: hex(0xB3AA98),
        label: hex(0xB3AA98),
        hairline: hex(0xEFE8D8, alpha: 0.12),
        thread: hex(0xE0583A)
    )

    /// The dim laid over the screen behind the sheet (fab's night).
    static let veil = hex(0x16140F)

    /// fab's `--ease-out-expo`.
    static var expoOut: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1) }

    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Editor theme variables that re-ink the card sheet as Woven paper.
    static func editorVars(_ scheme: AppScheme) -> [String: String] {
        if scheme.isDark {
            return [
                "--blink-card-bg": "#211e18",
                "--blink-text": "rgba(239, 232, 216, 0.9)",
                "--blink-text-strong": "#efe8d8",
                "--blink-text-muted": "#b3aa98",
                "--blink-marker": "rgba(179, 170, 152, 0.8)",
                "--blink-accent": "#efe8d8",
                "--blink-accent-dim": "#b3aa98",
                "--blink-code-bg": "rgba(239, 232, 216, 0.07)",
                "--blink-code-text": "rgba(239, 232, 216, 0.88)",
                "--blink-quote-text": "#b3aa98",
                "--blink-quote-border": "rgba(239, 232, 216, 0.22)",
                "--blink-rule": "rgba(239, 232, 216, 0.14)",
                "--blink-selection": "rgba(224, 88, 58, 0.28)",
                "--blink-caret": "#e0583a",
            ]
        }
        return [
            "--blink-card-bg": "#faf6ec",
            "--blink-text": "#1d1b18",
            "--blink-text-strong": "#1d1b18",
            "--blink-text-muted": "#6b6558",
            "--blink-marker": "#6b6558",
            "--blink-accent": "#1d1b18",
            "--blink-accent-dim": "#5c564b",
            "--blink-code-bg": "rgba(29, 27, 24, 0.06)",
            "--blink-code-text": "#1d1b18",
            "--blink-quote-text": "#5c564b",
            "--blink-quote-border": "rgba(29, 27, 24, 0.22)",
            "--blink-rule": "rgba(29, 27, 24, 0.12)",
            "--blink-selection": "rgba(182, 64, 37, 0.18)",
            "--blink-caret": "#b64025",
        ]
    }

    /// Mono silkscreen label: uppercase, 0.16em tracking.
    static func silkscreen(_ text: String, size: CGFloat, color: NSColor) -> NSAttributedString {
        NSAttributedString(
            string: text.uppercased(),
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: size, weight: .medium),
                .foregroundColor: color,
                .kern: size * 0.16,
            ]
        )
    }

    static func hex(_ value: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha
        )
    }
}

// MARK: - Cue

/// The working indicator. It lands next to the cursor the instant the hotkey
/// fires, flies to the sheet's centre and grows while the text loads, then
/// fades as the text streams in. A breathing thread dot, not a spinner.
@MainActor
final class ReaderCue {
    static let smallSize = NSSize(width: 28, height: 28)
    static let largeSize = NSSize(width: 132, height: 84)

    private let window: NSPanel
    private let view: CueView

    init(scheme: AppScheme) {
        window = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.smallSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        // Above the reader column (normal level); untitled so window managers skip it.
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        view = CueView(palette: Woven.palette(scheme))
        window.contentView = view
    }

    /// Land beside the cursor: rise 4pt and fade in.
    func show(at cursor: NSPoint) {
        let frame = NSRect(
            x: cursor.x + 12,
            y: cursor.y - 12 - Self.smallSize.height,
            width: Self.smallSize.width,
            height: Self.smallSize.height
        )
        window.setFrame(frame.offsetBy(dx: 0, dy: Woven.reduceMotion ? 0 : -4), display: false)
        window.alphaValue = 0
        window.orderFrontRegardless()
        view.startBreathing()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = Woven.expoOut
            window.animator().alphaValue = 1
            window.animator().setFrame(frame, display: true)
        }
    }

    /// Fly to the centre of `rect` and grow, showing the "reading" label.
    func settle(centeredIn rect: NSRect, duration: TimeInterval) {
        let size = Self.largeSize
        let target = NSRect(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2,
            width: size.width,
            height: size.height
        ).integral
        window.orderFrontRegardless()
        if Woven.reduceMotion {
            window.setFrame(target, display: true)
            view.labelAlpha = 1
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = Woven.expoOut
            window.animator().setFrame(target, display: true)
        }
        view.fadeInLabel(after: duration * 0.4, duration: duration * 0.6)
    }

    /// Fade out and order out (never left idle at alpha 0).
    func dismiss() {
        let window = window
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { window.orderOut(nil) }
        }
    }
}

/// A hairline card disc carrying the breathing thread dot, with the silkscreen
/// label beneath once the cue has grown. Laid out by hand from the window's
/// size so the disc and dot scale smoothly through the fly-in.
private final class CueView: NSView {
    private let disc = CALayer()
    private let dot = CALayer()
    private let label = NSTextField(labelWithString: "")

    var labelAlpha: CGFloat {
        get { label.alphaValue }
        set { label.alphaValue = newValue }
    }

    init(palette: Woven.Palette) {
        super.init(frame: .zero)
        wantsLayer = true
        disc.backgroundColor = palette.sheet.cgColor
        disc.borderColor = palette.hairline.cgColor
        disc.borderWidth = 1
        disc.shadowColor = NSColor(srgbRed: 60 / 255, green: 45 / 255, blue: 20 / 255, alpha: 1).cgColor
        disc.shadowOpacity = 0.35
        disc.shadowRadius = 10
        disc.shadowOffset = CGSize(width: 0, height: -6)
        dot.backgroundColor = palette.thread.cgColor
        layer?.addSublayer(disc)
        layer?.addSublayer(dot)

        label.attributedStringValue = Woven.silkscreen("reading", size: 10.5, color: palette.label)
        label.alignment = .center
        label.alphaValue = 0
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let small = ReaderCue.smallSize.width
        let large = ReaderCue.largeSize.width
        let t = max(0, min(1, (bounds.width - small) / (large - small)))
        let diameter = small + t * (44 - small)
        let discFrame = CGRect(x: (bounds.width - diameter) / 2, y: 0, width: diameter, height: diameter)
        let dotSize = (diameter * 0.27).rounded()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        disc.frame = discFrame
        disc.cornerRadius = diameter / 2
        dot.bounds = CGRect(x: 0, y: 0, width: dotSize, height: dotSize)
        dot.cornerRadius = dotSize / 2
        dot.position = CGPoint(x: discFrame.midX, y: discFrame.midY)
        CATransaction.commit()

        label.frame = NSRect(x: 0, y: diameter + 12, width: bounds.width, height: 16)
    }

    /// fab's `breathe`: 1.1s ease-in-out, opacity 1→0.45, scale 1→0.8.
    func startBreathing() {
        guard !Woven.reduceMotion else { return }
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 1
        opacity.toValue = 0.45
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1
        scale.toValue = 0.8
        let breathe = CAAnimationGroup()
        breathe.animations = [opacity, scale]
        breathe.duration = 0.55
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dot.add(breathe, forKey: "breathe")
    }

    func fadeInLabel(after delay: TimeInterval, duration: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = Woven.expoOut
                self?.label.animator().alphaValue = 1
            }
        }
    }
}

// MARK: - Keycaps

/// A row of named shortcuts: fab settings keycaps (mono legend, hairline rim,
/// 1pt bottom edge) followed by a quiet sans caption.
@MainActor
func readerHints(_ items: [(keys: [String], caption: String)]) -> NSStackView {
    let palette = Woven.night
    let row = NSStackView()
    row.orientation = .horizontal
    row.spacing = 18
    for item in items {
        let group = NSStackView()
        group.orientation = .horizontal
        group.spacing = 4
        for key in item.keys { group.addArrangedSubview(Keycap(legend: key, palette: palette)) }
        group.setCustomSpacing(8, after: group.arrangedSubviews.last!)
        let caption = NSTextField(labelWithString: item.caption)
        caption.font = .systemFont(ofSize: 12, weight: .regular)
        caption.textColor = palette.inkSoft
        group.addArrangedSubview(caption)
        row.addArrangedSubview(group)
    }
    return row
}

private final class Keycap: NSView {
    init(legend: String, palette: Woven.Palette) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = palette.sheet.cgColor
        layer?.cornerRadius = 5
        layer?.borderWidth = 1
        layer?.borderColor = palette.ink.withAlphaComponent(0.22).cgColor
        // The 1pt travel edge under the cap.
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.6
        layer?.shadowRadius = 0
        layer?.shadowOffset = CGSize(width: 0, height: -1)

        let text = NSTextField(labelWithString: legend)
        text.font = .monospacedSystemFont(ofSize: 11.5, weight: .medium)
        text.textColor = palette.inkSoft
        text.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 24),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 24),
            text.centerXAnchor.constraint(equalTo: centerXAnchor),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 7),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
