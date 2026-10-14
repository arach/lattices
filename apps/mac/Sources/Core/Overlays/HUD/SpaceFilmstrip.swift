import AppKit
import QuartzCore

struct SpaceFilmstripCard {
    let id: Int
    let number: Int
    let windows: [SpaceFilmstripWindow]
}

struct SpaceFilmstripWindow {
    let rect: CGRect
    let app: String
}

/// Pure geometry shared by the renderer and regression tests. No screen
/// capture, AX, image decoding, or WindowServer calls occur in this model.
enum SpaceFilmstripLayout {
    static let cardWidth: CGFloat = 168
    static let cardHeight: CGFloat = 105
    static let stride: CGFloat = 178
    static let height: CGFloat = 178

    static func trayWidth(screenWidth: CGFloat, count: Int) -> CGFloat {
        min(max(0, screenWidth - 48), 1000, max(240, CGFloat(count) * stride + 32))
    }

    static func offset(selected: Int, viewportWidth: CGFloat) -> CGFloat {
        viewportWidth / 2 - cardWidth / 2 - CGFloat(selected) * stride
    }

    static func cards(spaces: [SpaceInfo], windows: [WindowEntry], bounds: CGRect) -> [SpaceFilmstripCard] {
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        return spaces.map { space in
            // Keep the six frontmost content windows, then paint back to front.
            // Inactive desktops often have no CG title and cannot be
            // verified through AX. Geometry previews don't need either;
            // requiring them would label real desktops as empty.
            let members = windows.filter {
                $0.spaceIds.contains(space.id) && !$0.appHidden && !$0.collapsed
                    && $0.pid != getpid() && $0.frame.w >= 120 && $0.frame.h >= 120
            }.sorted { $0.zIndex < $1.zIndex }
            let placed = members.compactMap { window -> SpaceFilmstripWindow? in
                guard bounds.width > 0, bounds.height > 0 else { return nil }
                let frame = window.frame
                let rect = CGRect(x: (frame.x - bounds.minX) / bounds.width,
                                  y: (frame.y - bounds.minY) / bounds.height,
                                  width: frame.w / bounds.width, height: frame.h / bounds.height).intersection(unit)
                guard !rect.isNull, rect.width > 0.01, rect.height > 0.01 else { return nil }
                return SpaceFilmstripWindow(rect: rect, app: window.app)
            }
            return SpaceFilmstripCard(id: space.id, number: space.index, windows: Array(placed.prefix(6).reversed()))
        }
    }
}

/// Native layer tree: move one track, keep one focus frame still.
///
/// Retargets are additive: the model jumps to the new goal and an additive
/// animation carries the remaining delta down to zero. Nothing reads the
/// presentation layer, which lags the model until Core Animation commits —
/// a reopen or two selects in one run-loop pass used to start the travel
/// from the previous gesture's resting place, a visible hop. The curve
/// leaves with zero slope, so position and speed both stay continuous
/// through reversals and merged bursts.
/// No frame callbacks, SwiftUI invalidations, or work on the switch queue.
final class SpaceFilmstripView: NSView {
    override var isFlipped: Bool { true }
    private let tray = CALayer()
    private let surface = CAGradientLayer()
    private let rim = CAGradientLayer()
    private let rimMask = CAShapeLayer()
    private let channel = CALayer()
    private let viewport = CALayer()
    private let track = CALayer()
    private let focus = CAGradientLayer()
    private let focusMask = CAShapeLayer()
    private let focusKeyline = CALayer()
    private let guides = CAShapeLayer()
    private let fade = CAGradientLayer()
    private let rail = CALayer()
    private let marker = CALayer()
    private let counter = CALayer()
    private var reels: [CALayer] = []
    private var counterNumber: Int?
    private(set) var isScrubbing = false
    /// The mark's one accent, `#ef6a47`: only the active desktop takes hue.
    static let accent = NSColor(srgbRed: 0.937, green: 0.416, blue: 0.278, alpha: 1)
    private var cards: [CALayer] = []
    private var bookends: [CALayer] = []
    private var railCells: [CALayer] = []
    private(set) var selected: Int?
    private var scale: CGFloat = 2
    private var railStride: CGFloat = 11
    private var railCellSize: CGFloat = 7
    private var legSerial = 0

    static let travelDuration: CFTimeInterval = 0.26
    /// Zero initial slope: stacked additive deltas never add a speed step.
    static let travelTiming = CAMediaTimingFunction(controlPoints: 0.22, 0, 0, 1)

    /// Model goals, for tests and diagnostics. Never the presentation layer.
    var trackX: CGFloat { track.position.x }
    var markerX: CGFloat { marker.position.x }
    var cardOpacities: [Float] { cards.map(\.opacity) }
    var animationCount: Int {
        ([track, marker, viewport, counter] + cards + reels).reduce(0) { $0 + ($1.animationKeys()?.count ?? 0) }
    }
    /// Remaining additive travel legs on the track, oldest first.
    var trackDeltas: [CGFloat] {
        (track.animationKeys() ?? []).sorted {
            (Int($0.dropFirst(4)) ?? 0) < (Int($1.dropFirst(4)) ?? 0)
        }.compactMap {
            ((track.animation(forKey: $0) as? CABasicAnimation)?.fromValue as? NSNumber).map { CGFloat($0.doubleValue) }
        }
    }

    static func emphasis(distance: Int) -> Float {
        distance == 0 ? 1 : distance == 1 ? 0.72 : distance == 2 ? 0.50 : 0.36
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(tray)
        tray.cornerRadius = 16
        tray.shadowColor = NSColor.black.cgColor
        tray.shadowOpacity = 0.34
        tray.shadowRadius = 14
        tray.shadowOffset = CGSize(width: 0, height: 6)
        // A shallow machined lip around a recessed film channel. All of this
        // is retained vector geometry: no material sampling or image cache.
        surface.colors = [NSColor(calibratedRed: 0.095, green: 0.109, blue: 0.122, alpha: 0.98).cgColor,
                          NSColor(calibratedRed: 0.043, green: 0.051, blue: 0.063, alpha: 0.98).cgColor]
        surface.startPoint = CGPoint(x: 0.5, y: 0)
        surface.endPoint = CGPoint(x: 0.5, y: 1)
        surface.cornerRadius = 16
        tray.addSublayer(surface)
        channel.backgroundColor = NSColor.black.withAlphaComponent(0.24).cgColor
        channel.cornerRadius = 10
        channel.borderWidth = 0.5
        channel.borderColor = NSColor.black.withAlphaComponent(0.40).cgColor
        tray.addSublayer(channel)
        tray.addSublayer(viewport)
        viewport.masksToBounds = true
        viewport.addSublayer(track)
        viewport.mask = fade
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        fade.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        tray.addSublayer(focus)
        focus.colors = [NSColor(calibratedWhite: 1, alpha: 0.93).cgColor,
                        NSColor(calibratedWhite: 0.88, alpha: 0.48).cgColor,
                        NSColor(calibratedWhite: 0.93, alpha: 0.68).cgColor]
        focus.locations = [0, 0.65, 1]
        focus.startPoint = CGPoint(x: 0.5, y: 0)
        focus.endPoint = CGPoint(x: 0.5, y: 1)
        focus.mask = focusMask
        focusMask.fillColor = nil
        focusMask.strokeColor = NSColor.black.cgColor
        focusMask.lineWidth = 1
        focusKeyline.cornerRadius = 8
        focusKeyline.borderWidth = 0.5
        focusKeyline.borderColor = NSColor.black.withAlphaComponent(0.65).cgColor
        tray.addSublayer(focusKeyline)
        // The aperture's straight edges continue past its soft corners and
        // stop just short of meeting: the lattice cell the mark is built on.
        guides.fillColor = nil
        guides.strokeColor = NSColor.white.withAlphaComponent(0.30).cgColor
        guides.lineWidth = 0.75
        guides.lineCap = .butt
        tray.addSublayer(guides)
        rim.colors = [NSColor.white.withAlphaComponent(0.26).cgColor,
                      NSColor.white.withAlphaComponent(0.06).cgColor,
                      NSColor.white.withAlphaComponent(0.10).cgColor]
        rim.locations = [0, 0.55, 1]
        rim.startPoint = CGPoint(x: 0.5, y: 0)
        rim.endPoint = CGPoint(x: 0.5, y: 1)
        rim.mask = rimMask
        rimMask.fillColor = nil
        rimMask.strokeColor = NSColor.black.cgColor
        rimMask.lineWidth = 0.75
        tray.addSublayer(rim)
        tray.addSublayer(rail)
        marker.backgroundColor = Self.accent.cgColor
        marker.cornerRadius = 2
        rail.addSublayer(marker)
        counter.masksToBounds = true
        counter.opacity = 0
        tray.addSublayer(counter)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(cards models: [SpaceFilmstripCard], size: CGSize, scale: CGFloat) {
        clear()
        self.scale = scale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tray.frame = CGRect(x: 16, y: 12, width: size.width - 32, height: size.height - 28)
        tray.shadowPath = CGPath(roundedRect: tray.bounds, cornerWidth: 16, cornerHeight: 16, transform: nil)
        surface.frame = tray.bounds
        channel.frame = tray.bounds.insetBy(dx: 6, dy: 6)
        channel.frame.size.height = 117
        rim.frame = tray.bounds
        rimMask.frame = rim.bounds
        rimMask.path = CGPath(roundedRect: rim.bounds.insetBy(dx: 0.5, dy: 0.5),
                              cornerWidth: 15.5, cornerHeight: 15.5, transform: nil)
        viewport.frame = CGRect(x: 0, y: 6, width: tray.bounds.width, height: 133)
        fade.frame = viewport.bounds
        let stop = min(0.25, 22 / max(1, viewport.bounds.width))
        fade.locations = [0, NSNumber(value: Double(stop)), NSNumber(value: Double(1 - stop)), 1]
        track.anchorPoint = .zero
        track.transform = CATransform3DIdentity
        track.position = .zero
        track.bounds = CGRect(x: 0, y: 0, width: CGFloat(models.count) * SpaceFilmstripLayout.stride, height: 133)
        focus.frame = CGRect(x: (tray.bounds.width - 176) / 2, y: 7, width: 176, height: 113)
        focusMask.frame = focus.bounds
        focusMask.path = CGPath(roundedRect: focus.bounds.insetBy(dx: 0.5, dy: 0.5),
                                cornerWidth: 9, cornerHeight: 9, transform: nil)
        focusKeyline.frame = focus.frame.insetBy(dx: 1.5, dy: 1.5)
        guides.frame = tray.bounds
        guides.path = Self.cornerGuides(around: focus.frame.insetBy(dx: 0.5, dy: 0.5), gap: 1.5, reach: 4)
        [surface, channel, rim, rimMask, focus, focusMask, focusKeyline, guides].forEach { $0.contentsScale = scale }
        for (i, model) in models.enumerated() {
            let card = makeCard(model)
            card.frame = CGRect(x: CGFloat(i) * SpaceFilmstripLayout.stride, y: 5, width: 168, height: 127)
            track.addSublayer(card)
            cards.append(card)
        }
        // Bookends belong to the track, but never to the desktop selection.
        // They take whole slots of the film's own stride, as many as the
        // half-viewport beside an end card can show (at most two), so the
        // reel's rhythm runs straight into them. Their details disappear
        // with the viewport during number-only holds.
        let reach = (viewport.bounds.width - SpaceFilmstripLayout.cardWidth) / 2
        let slots = min(2, Int(reach / SpaceFilmstripLayout.stride))
        if !models.isEmpty, slots > 0 {
            let span = CGFloat(slots) * SpaceFilmstripLayout.stride
            let empty = models.filter(\.windows.isEmpty).count
            for (x, leading) in [(-span, true), (CGFloat(models.count) * SpaceFilmstripLayout.stride, false)] {
                let bookend = makeBookend(count: models.count, empty: empty,
                                          width: span - (SpaceFilmstripLayout.stride - SpaceFilmstripLayout.cardWidth),
                                          leading: leading)
                bookend.frame.origin = CGPoint(x: x, y: 5)
                track.addSublayer(bookend)
                bookends.append(bookend)
            }
        }
        railStride = min(11, (tray.bounds.width - 48) / CGFloat(max(1, models.count)))
        railCellSize = min(7, railStride * 0.64)
        let railWidth = CGFloat(max(0, models.count - 1)) * railStride + railCellSize
        rail.frame = CGRect(x: (tray.bounds.width - railWidth) / 2, y: 140, width: railWidth, height: 3)
        for i in models.indices {
            let cell = CALayer()
            cell.frame = CGRect(x: CGFloat(i) * railStride, y: 0, width: railCellSize, height: 3)
            cell.cornerRadius = min(1.5, railCellSize / 2)
            cell.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
            rail.insertSublayer(cell, below: marker)
            railCells.append(cell)
        }
        counter.frame = CGRect(x: (tray.bounds.width - 68) / 2, y: 34, width: 68, height: 52)
        marker.transform = CATransform3DIdentity
        marker.frame = CGRect(x: 0, y: 0, width: railCellSize, height: 3)
        CATransaction.commit()
    }

    func select(_ index: Int, animated: Bool) {
        guard cards.indices.contains(index), selected != index else { return }
        let animate = animated && selected != nil
        let x = SpaceFilmstripLayout.offset(selected: index, viewportWidth: viewport.bounds.width)
        let markerX = CGFloat(index) * railStride + railCellSize / 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        retarget(track, keyPath: "position.x", from: track.position.x, to: x, animate: animate)
        track.position.x = x
        retarget(marker, keyPath: "position.x", from: marker.position.x, to: markerX, animate: animate)
        marker.position.x = markerX
        for (i, card) in cards.enumerated() {
            let opacity = Self.emphasis(distance: abs(i - index))
            retarget(card, keyPath: "opacity", from: CGFloat(card.opacity), to: CGFloat(opacity), animate: animate)
            card.opacity = opacity
        }
        selected = index
        CATransaction.commit()
        setAccessibilityLabel("Desktop \(index + 1) of \(cards.count)")
    }

    /// One clipped reel per decimal place. Each row is retained for the
    /// gesture; repeats only move two layers and never select a preview card.
    private func configureCounter(total: Int) {
        reels.forEach { $0.removeFromSuperlayer() }
        reels = []
        let digits = max(2, String(total).count)
        counter.frame = CGRect(x: (tray.bounds.width - CGFloat(digits) * 34) / 2, y: 34, width: CGFloat(digits) * 34, height: 52)
        for column in 0..<digits {
            let divisor = Int(pow(10.0, Double(digits - column - 1)))
            let reel = CALayer()
            reel.anchorPoint = .zero
            reel.frame = CGRect(x: CGFloat(column) * 34, y: 0, width: 34,
                                height: CGFloat(total / divisor + 1) * 52)
            for row in 0...(total / divisor) {
                let digit = label("\(row % 10)", size: 42, color: NSColor.white.withAlphaComponent(0.94))
                digit.alignmentMode = .center
                digit.frame = CGRect(x: 0, y: CGFloat(row) * 52, width: 34, height: 52)
                reel.addSublayer(digit)
            }
            counter.addSublayer(reel)
            reels.append(reel)
        }
    }

    func scrub(number: Int, total: Int, animated: Bool, selectedIndex: Int? = nil) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if reels.isEmpty { configureCounter(total: max(total, number)) }
        if !isScrubbing {
            // Finish any single-tap travel; the previews stay in this position
            // for the whole hold and never chase the odometer.
            track.removeAllAnimations()
            cards.forEach { $0.removeAllAnimations() }
            viewport.opacity = 0
            counter.opacity = 1
            isScrubbing = true
        }
        marker.removeAllAnimations()
        marker.position.x = CGFloat(min(max(selectedIndex ?? number - 1, 0), max(0, cards.count - 1))) * railStride + railCellSize / 2
        if number != counterNumber {
            for (column, reel) in reels.enumerated() {
                let divisor = Int(pow(10.0, Double(reels.count - column - 1)))
                let y = -CGFloat(number / divisor) * 52
                retarget(reel, keyPath: "position.y", from: reel.position.y, to: y,
                         animate: animated && counterNumber != nil, duration: 0.12)
                reel.position.y = y
            }
            counterNumber = number
        }
        CATransaction.commit()
        setAccessibilityLabel("\(number) of \(total)")
    }

    func endScrubbing(at index: Int?, animated: Bool) {
        guard isScrubbing else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        isScrubbing = false
        track.removeAllAnimations()
        marker.removeAllAnimations()
        cards.forEach { $0.removeAllAnimations() }
        if let index { select(index, animated: false) }
        retarget(viewport, keyPath: "opacity", from: CGFloat(viewport.opacity), to: 1, animate: animated, duration: 0.16)
        viewport.opacity = 1
        retarget(counter, keyPath: "opacity", from: CGFloat(counter.opacity), to: 0, animate: animated, duration: 0.12)
        counter.opacity = 0
        counterNumber = nil
        CATransaction.commit()
    }

    func clear() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.removeAllAnimations()
        marker.removeAllAnimations()
        rim.removeAllAnimations()
        focus.removeAllAnimations()
        guides.removeAllAnimations()
        cards.forEach { $0.removeAllAnimations(); $0.removeFromSuperlayer() }
        railCells.forEach { $0.removeFromSuperlayer() }
        bookends.forEach { $0.removeFromSuperlayer() }
        bookends.removeAll(keepingCapacity: false)
        cards.removeAll(keepingCapacity: false)
        railCells.removeAll(keepingCapacity: false)
        selected = nil
        isScrubbing = false
        counterNumber = nil
        counter.removeAllAnimations()
        viewport.removeAllAnimations()
        reels.forEach { $0.removeAllAnimations(); $0.removeFromSuperlayer() }
        reels = []
        counter.opacity = 0
        viewport.opacity = 1
        CATransaction.commit()
    }

    /// The edge light resolves a beat after the surface arrives, outer rim
    /// first, then settling inward onto the aperture and its guides; all of
    /// it lands at 320ms. Only on a fresh opening; key repeats and
    /// interrupted departures retain the frame.
    func illuminateFrame(animated: Bool) {
        guard animated else { return }
        let now = CACurrentMediaTime()
        for (edge, delay) in [(rim, 0.0), (focus, 0.05), (guides, 0.05)] as [(CALayer, CFTimeInterval)] {
            let light = CABasicAnimation(keyPath: "opacity")
            light.isAdditive = true
            light.fromValue = -0.65
            light.toValue = 0
            light.beginTime = delay > 0 ? edge.convertTime(now, from: nil) + delay : 0
            light.fillMode = .backwards
            light.duration = 0.32 - delay
            light.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0, 0.25, 1)
            edge.add(light, forKey: "arrivalLight")
        }
    }

    /// Eight short strokes on the extensions of `rect`'s edges, outside each
    /// corner, leaving `gap` before the virtual square corner.
    static func cornerGuides(around rect: CGRect, gap: CGFloat, reach: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for (x, sx) in [(rect.minX, -1.0), (rect.maxX, 1.0)] as [(CGFloat, CGFloat)] {
            for (y, sy) in [(rect.minY, -1.0), (rect.maxY, 1.0)] as [(CGFloat, CGFloat)] {
                path.move(to: CGPoint(x: x + sx * gap, y: y))
                path.addLine(to: CGPoint(x: x + sx * (gap + reach), y: y))
                path.move(to: CGPoint(x: x, y: y + sy * gap))
                path.addLine(to: CGPoint(x: x, y: y + sy * (gap + reach)))
            }
        }
        return path
    }

    /// Adds the remaining delta as an additive, self-removing animation.
    /// Each leg gets its own key, so an in-flight leg keeps easing out
    /// underneath the new one and removes itself when done.
    private func retarget(_ layer: CALayer, keyPath: String, from: CGFloat, to: CGFloat, animate: Bool, duration: CFTimeInterval = SpaceFilmstripView.travelDuration) {
        guard animate, abs(from - to) > 0.001 else { return }
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.isAdditive = true
        animation.fromValue = from - to
        animation.toValue = 0
        animation.duration = duration
        animation.timingFunction = Self.travelTiming
        legSerial &+= 1
        layer.add(animation, forKey: "leg.\(legSerial)")
    }

    /// A quiet, non-interactive colophon at each end of the desktop reel: a
    /// ghost frame whose fill and hairline dissolve away from the film, with
    /// its type set flush to the reel-facing edge. Built once per opening;
    /// selection and repeat events do no summary work. Every figure comes
    /// from the cards themselves — `empty` matches the cards' own "Empty".
    private func makeBookend(count: Int, empty: Int, width: CGFloat, leading: Bool) -> CALayer {
        let card = CALayer()
        card.bounds = CGRect(x: 0, y: 0, width: width, height: SpaceFilmstripLayout.cardHeight)
        // Strong at the film, gone by the far edge.
        let toward = leading ? CGPoint(x: 1, y: 0.5) : CGPoint(x: 0, y: 0.5)
        let away = leading ? CGPoint(x: 0, y: 0.5) : CGPoint(x: 1, y: 0.5)
        let fill = CAGradientLayer()
        fill.frame = card.bounds
        fill.cornerRadius = 6
        fill.colors = [NSColor.white.withAlphaComponent(0.035).cgColor, NSColor.white.withAlphaComponent(0).cgColor]
        fill.startPoint = toward
        fill.endPoint = away
        card.addSublayer(fill)
        let edge = CAGradientLayer()
        edge.frame = card.bounds
        edge.colors = [NSColor.white.withAlphaComponent(0.13).cgColor, NSColor.white.withAlphaComponent(0).cgColor]
        edge.locations = [0, 0.8]
        edge.startPoint = toward
        edge.endPoint = away
        let edgeMask = CAShapeLayer()
        edgeMask.frame = edge.bounds
        edgeMask.path = CGPath(roundedRect: edge.bounds.insetBy(dx: 0.375, dy: 0.375),
                               cornerWidth: 6, cornerHeight: 6, transform: nil)
        edgeMask.fillColor = nil
        edgeMask.strokeColor = NSColor.black.cgColor
        edgeMask.lineWidth = 0.75
        edge.mask = edgeMask
        card.addSublayer(edge)
        [fill, edge, edgeMask].forEach { $0.contentsScale = scale }

        let inset: CGFloat = 18
        let flush: CATextLayerAlignmentMode = leading ? .right : .left
        let column = CGRect(x: inset, y: 0, width: width - inset * 2, height: card.bounds.height)
        // `trail` is space kept free after the text in reading order: to its
        // left on the trailing bookend, to its right on the leading one.
        func place(_ text: CATextLayer, y: CGFloat, height: CGFloat, trail: CGFloat = 0) {
            text.alignmentMode = flush
            text.frame = CGRect(x: column.minX + (leading ? 0 : trail), y: y,
                                width: column.width - trail, height: height)
            card.addSublayer(text)
        }

        // Lockup: LatticesMark's geometry (pad 10%, gap 6%, radius 18% of a
        // cell) in white, the orange stays with the active desktop.
        let wordFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let word = label("Lattices", size: 11, color: NSColor.white.withAlphaComponent(0.62))
        word.font = wordFont
        let wordWidth = ceil(("Lattices" as NSString).size(withAttributes: [.font: wordFont]).width)
        let markSize: CGFloat = 14, markGap: CGFloat = 6
        let markX = leading ? column.maxX - wordWidth - markGap - markSize : column.minX
        let pad = markSize * 0.1, gap = markSize * 0.06, cell = (markSize - 2 * pad - 2 * gap) / 3
        for (i, bright) in [true, false, false, true, false, false, true, true, true].enumerated() {
            let square = CALayer()
            square.frame = CGRect(x: markX + pad + CGFloat(i % 3) * (cell + gap),
                                  y: 16 + pad + CGFloat(i / 3) * (cell + gap), width: cell, height: cell)
            square.cornerRadius = cell * 0.18
            square.backgroundColor = NSColor.white.withAlphaComponent(bright ? 0.62 : 0.14).cgColor
            card.addSublayer(square)
        }
        place(word, y: 15.5, height: 16, trail: leading ? 0 : markSize + markGap)

        // The total, set like the odometer that replaces this view mid-hold.
        let figure = "\(count)", noun = count == 1 ? "desktop" : "desktops"
        let figureFont = NSFont.monospacedSystemFont(ofSize: 24, weight: .medium)
        let figureWidth = ceil((figure as NSString).size(withAttributes: [.font: figureFont]).width)
        let nounWidth = ceil((noun as NSString)
            .size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)]).width)
        let number = label(figure, size: 24, color: NSColor.white.withAlphaComponent(0.80))
        number.font = figureFont
        place(number, y: 43, height: 30, trail: leading ? nounWidth + 6 : 0)
        place(label(noun, size: 10, color: NSColor.white.withAlphaComponent(0.48)), y: 57, height: 14,
              trail: leading ? 0 : figureWidth + 6)

        let detail = empty > 0 ? "This display \u{00B7} \(empty) empty" : "This display"
        place(label(detail, size: 9.5, color: NSColor.white.withAlphaComponent(0.36)), y: 80, height: 14)
        return card
    }

    private func makeCard(_ model: SpaceFilmstripCard) -> CALayer {
        let card = CALayer()
        let shot = CALayer()
        shot.frame = CGRect(x: 0, y: 0, width: 168, height: 105)
        shot.cornerRadius = 6
        shot.masksToBounds = true
        shot.backgroundColor = NSColor(calibratedRed: 0.10, green: 0.13, blue: 0.155, alpha: 1).cgColor
        shot.borderWidth = 0.75
        shot.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
        card.addSublayer(shot)
        for window in model.windows {
            let zone = CALayer()
            zone.frame = CGRect(x: 5 + window.rect.minX * 158, y: 5 + window.rect.minY * 95,
                                width: window.rect.width * 158, height: window.rect.height * 95)
            zone.cornerRadius = 2.5
            zone.masksToBounds = true
            zone.backgroundColor = NSColor(calibratedRed: 0.65, green: 0.75, blue: 0.80, alpha: 0.12).cgColor
            zone.borderWidth = 0.6
            zone.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
            shot.addSublayer(zone)
            let bar = CALayer()
            bar.frame = CGRect(x: 0, y: 0, width: zone.bounds.width, height: min(6, zone.bounds.height))
            bar.backgroundColor = NSColor.white.withAlphaComponent(0.09).cgColor
            zone.addSublayer(bar)
            if zone.bounds.width > 36, zone.bounds.height > 22 {
                let name = label(window.app, size: 7, color: NSColor.white.withAlphaComponent(0.65))
                name.frame = CGRect(x: 5, y: 10, width: zone.bounds.width - 10, height: 12)
                zone.addSublayer(name)
            }
        }
        if model.windows.isEmpty {
            let empty = label("Empty", size: 10, color: NSColor.white.withAlphaComponent(0.25))
            empty.alignmentMode = .center
            empty.frame = CGRect(x: 8, y: 45, width: 152, height: 16)
            shot.addSublayer(empty)
        }
        let caption = label("\(model.number)   Desktop", size: 10, color: NSColor.white.withAlphaComponent(0.83))
        caption.frame = CGRect(x: 2, y: 111, width: 122, height: 15)
        card.addSublayer(caption)
        for i in 0..<min(4, model.windows.count) {
            let dot = CALayer()
            dot.frame = CGRect(x: 161 - CGFloat(i) * 7, y: 115, width: 4, height: 4)
            dot.cornerRadius = 2
            dot.backgroundColor = NSColor.white.withAlphaComponent(0.4).cgColor
            card.addSublayer(dot)
        }
        return card
    }

    private func label(_ text: String, size: CGFloat, color: NSColor) -> CATextLayer {
        let label = CATextLayer()
        label.string = text
        label.font = NSFont.monospacedSystemFont(ofSize: size, weight: .medium)
        label.fontSize = size
        label.foregroundColor = color.cgColor
        label.contentsScale = scale
        label.truncationMode = .end
        return label
    }
}
