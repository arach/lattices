import SwiftUI

struct StageHUDRootView: View {
    @ObservedObject var model: StageHUDViewModel
    @ObservedObject private var themeStore = ActionThemeStore.shared

    var body: some View {
        VStack(spacing: 7) {
            header
            captureInstrument
            controlBay
            telemetryFooter
        }
        .padding(10)
        .frame(width: 336, height: 456, alignment: .top)
        .background(monolithShell)
        .preferredColorScheme(.dark)
        .id(themeStore.revision)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                ActionChamferedShape(cornerCut: 5)
                    .fill(StageHUDTheme.hudCoral)
                    .overlay(
                        ActionChamferedShape(cornerCut: 5)
                            .stroke(StageHUDTheme.hudPaper.opacity(0.22), lineWidth: 1)
                    )

                Text("A")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(StageHUDTheme.hudInk)
            }
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)

            Rectangle()
                .fill(StageHUDTheme.hudStrokeStrong)
                .frame(width: 1, height: 23)

            Text(model.targetApp.uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(StageHUDTheme.hudPaper)
                .lineLimit(1)

            Spacer(minLength: 5)

            Rectangle()
                .fill(StageHUDTheme.hudStrokeStrong)
                .frame(width: 1, height: 23)

            HStack(spacing: 7) {
                Circle()
                    .fill(accentColor)
                    .frame(width: 7, height: 7)
                    .shadow(color: accentColor.opacity(isLive ? 0.85 : 0.3), radius: isLive ? 7 : 3)

                Text(headerStateLabel)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(accentColor)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Capture status: \(model.phaseLabel)")
        }
        .padding(.horizontal, 3)
        .frame(height: 44)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(StageHUDTheme.hudStrokeStrong)
                .frame(height: 1)
        }
    }

    private var captureInstrument: some View {
        ZStack {
            StageHUDAperture(color: accentColor, energized: isActive)
                .frame(width: 220, height: 220)
                .offset(y: -8)

            VStack(spacing: 0) {
                HStack {
                    Text(model.captureStatusTitle)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(accentColor)

                    Spacer()

                    if model.phase != "completing", let progress = model.stepProgressText {
                        Text(progress)
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(StageHUDTheme.hudMuted)
                            .lineLimit(1)
                            .frame(maxWidth: 118, alignment: .trailing)
                    }
                }

                Spacer(minLength: 0)

                Text(readout)
                    .font(.system(size: readout.count > 5 ? 41 : 55, weight: .medium, design: .monospaced))
                    .tracking(-3)
                    .foregroundStyle(StageHUDTheme.hudPaper)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .contentTransition(.numericText())
                    .shadow(color: StageHUDTheme.hudPaper.opacity(0.08), radius: 5)
                    .accessibilityLabel(readoutAccessibilityLabel)

                Spacer(minLength: 0)

                StageHUDWaveform(color: accentColor, energized: isActive)
                    .frame(height: 26)

                HStack(spacing: 9) {
                    Rectangle()
                        .fill(StageHUDTheme.hudStrokeStrong)
                        .frame(width: 32, height: 1)

                    Text(model.summary)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(0.35)
                        .foregroundStyle(StageHUDTheme.hudPaper.opacity(0.82))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(maxWidth: .infinity)

                    Rectangle()
                        .fill(StageHUDTheme.hudStrokeStrong)
                        .frame(width: 32, height: 1)
                }
                .padding(.top, 3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(height: 244)
        .background {
            // The instrument sits in a sunken well: a dark floor that lifts
            // slightly toward the aperture, with a shadow pooling at the top lip.
            ZStack {
                RadialGradient(
                    colors: [
                        StageHUDTheme.hudRecess.opacity(0.42),
                        StageHUDTheme.hudRecess.opacity(0.78)
                    ],
                    center: .center,
                    startRadius: 8,
                    endRadius: 168
                )
                LinearGradient(
                    colors: [StageHUDTheme.hudBevelShadow, .clear],
                    startPoint: .top,
                    endPoint: .center
                )
                .blendMode(.multiply)
            }
        }
        .overlay(
            ActionChamferedShape(cornerCut: 8)
                .stroke(StageHUDTheme.hudStrokeStrong, lineWidth: 1)
        )
        .overlay {
            // Recessed rim: shadow bites at the top, light grazes the bottom lip.
            ActionChamferedShape(cornerCut: 8)
                .stroke(
                    LinearGradient(
                        colors: [StageHUDTheme.hudBevelShadow, .clear, StageHUDTheme.hudBevelLight],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .padding(0.5)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(accentColor.opacity(0.55))
                .frame(width: 44, height: 1)
        }
        .clipShape(ActionChamferedShape(cornerCut: 8))
        .accessibilityElement(children: .contain)
    }

    private var controlBay: some View {
        HStack(spacing: 7) {
            if model.phase == "completing" {
                StageHUDBusyControl(title: "Saving Take", detail: "Writing movie + marker")
            } else if usesPairedControls {
                monolithButton("start", icon: model.phase == "paused" ? "play.fill" : "forward.fill")
                monolithButton("stop", icon: "xmark")
            } else {
                leadingHardwareControl
                monolithButton(primaryControlID, icon: primaryControlIcon)
                trailingHardwareControl
            }
        }
        .padding(8)
        .frame(height: 78)
        .background {
            LinearGradient(
                colors: [StageHUDTheme.hudMetalTrough, StageHUDTheme.hudRecess],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .overlay(
            ActionChamferedShape(cornerCut: 8)
                .stroke(StageHUDTheme.hudStrokeStrong, lineWidth: 1)
        )
        .overlay {
            // Recessed tray: shadow sinks under the top lip, light rides the base.
            ActionChamferedShape(cornerCut: 8)
                .stroke(
                    LinearGradient(
                        colors: [StageHUDTheme.hudBevelShadow, .clear, StageHUDTheme.hudBevelLight],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .padding(0.5)
                .allowsHitTesting(false)
        }
        .clipShape(ActionChamferedShape(cornerCut: 8))
    }

    // During live phases the control bay carries only the real stop/interrupt
    // affordance. The clear/quit hardware buttons appear only for terminal or
    // idle sessions; no decorative controls flank the primary action.
    @ViewBuilder
    private var leadingHardwareControl: some View {
        if showsSessionControls {
            hardwareButton("clear", icon: "xmark")
        }
    }

    @ViewBuilder
    private var trailingHardwareControl: some View {
        if showsSessionControls {
            hardwareButton("quit", icon: "power")
        }
    }

    private var telemetryFooter: some View {
        HStack(spacing: 9) {
            Text(latestEvent)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(0.45)
                .foregroundStyle(StageHUDTheme.hudPaper.opacity(0.76))
                .lineLimit(1)

            Spacer(minLength: 4)

            Rectangle()
                .fill(StageHUDTheme.hudStrokeStrong)
                .frame(width: 1, height: 17)

            Text(String(format: "%02d", model.recentLogs.count))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(StageHUDTheme.hudPaper)
        }
        .padding(.horizontal, 10)
        .frame(height: 31)
        .background(StageHUDTheme.hudRecess.opacity(0.7))
        .overlay(
            ActionChamferedShape(cornerCut: 4)
                .stroke(StageHUDTheme.hudStroke, lineWidth: 1)
        )
        .overlay {
            ActionChamferedShape(cornerCut: 4)
                .stroke(
                    LinearGradient(
                        colors: [StageHUDTheme.hudBevelShadow, .clear, StageHUDTheme.hudBevelLight],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .padding(0.5)
                .allowsHitTesting(false)
        }
        .clipShape(ActionChamferedShape(cornerCut: 4))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Latest event: \(latestEvent). \(model.recentLogs.count) events.")
    }

    private var monolithShell: some View {
        ActionChamferedShape(cornerCut: 11)
            .fill(
                LinearGradient(
                    colors: [StageHUDTheme.hudMetalTop, StageHUDTheme.hudCanvas],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                // Brushed graphite grain + a soft top-lit vignette give the
                // slab believable machined depth without reading as noise.
                StageHUDGraphite()
                    .clipShape(ActionChamferedShape(cornerCut: 11))
                    .allowsHitTesting(false)
            }
            .overlay {
                RadialGradient(
                    colors: [.clear, StageHUDTheme.hudGrainDark],
                    center: .center,
                    startRadius: 90,
                    endRadius: 260
                )
                .clipShape(ActionChamferedShape(cornerCut: 11))
                .allowsHitTesting(false)
            }
            .overlay(
                ActionChamferedShape(cornerCut: 11)
                    .stroke(StageHUDTheme.hudMetalEdge, lineWidth: 1)
            )
            .overlay {
                // Rolled outer edge: a light catch along the top, a settled
                // shadow along the bottom, so the slab has a chamfered lip.
                ActionChamferedShape(cornerCut: 11)
                    .stroke(
                        LinearGradient(
                            colors: [StageHUDTheme.hudBevelHairline, .clear, StageHUDTheme.hudBevelShadow],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                    .padding(0.5)
                    .allowsHitTesting(false)
            }
            .overlay {
                ActionChamferedShape(cornerCut: 8)
                    .stroke(StageHUDTheme.hudStroke, lineWidth: 1)
                    .padding(4)
            }
            .overlay(alignment: .top) {
                HStack(spacing: 0) {
                    Rectangle().fill(StageHUDTheme.hudCoral).frame(width: 72)
                    Rectangle().fill(StageHUDTheme.hudCyan).frame(width: 26)
                    Rectangle().fill(StageHUDTheme.hudStroke)
                }
                .frame(height: 2)
                .padding(.horizontal, 13)
            }
            .shadow(color: StageHUDTheme.hudShadow.opacity(0.72), radius: 12, x: 0, y: 6)
    }

    private var headerStateLabel: String {
        isLive ? "LIVE" : model.phaseLabel
    }

    private var accentColor: Color {
        switch model.phaseAccent {
        case .neutral:
            return StageHUDTheme.hudCyan
        case .paused:
            return StageHUDTheme.hudAmber
        case .recording:
            return StageHUDTheme.hudCoral
        }
    }

    private var isLive: Bool {
        model.phase == "recording" || model.phase == "acting"
    }

    private var isActive: Bool {
        isLive || model.phase == "countdown" || model.phase == "analyzing"
    }

    private var showsSessionControls: Bool {
        switch model.phase {
        case "created", "staging", "completed", "failed", "cancelled":
            return true
        default:
            return false
        }
    }

    private var usesPairedControls: Bool {
        buttonIsEnabled("start") && buttonIsEnabled("stop")
    }

    private var primaryControlID: String {
        if model.phase == "completed", buttonIsEnabled("replay") {
            return "replay"
        }
        if buttonIsEnabled("stop") && !buttonIsEnabled("start") {
            return "stop"
        }
        return "start"
    }

    private var primaryControlIcon: String {
        switch primaryControlID {
        case "stop":
            return "stop.fill"
        case "replay":
            return "arrow.counterclockwise"
        default:
            return "record.circle"
        }
    }

    private var readout: String {
        if let countdown = model.countdownText {
            return countdown
        }
        if let elapsed = model.elapsedText {
            return elapsed
        }
        switch model.phase {
        case "completed":
            return "SAVED"
        case "failed":
            return "FAULT"
        case "cancelled":
            return "ENDED"
        case "completing":
            return "WRITE"
        default:
            return "00:00"
        }
    }

    private var readoutAccessibilityLabel: String {
        if let countdown = model.countdownText {
            return "Capture begins in \(countdown)"
        }
        if let elapsed = model.elapsedText {
            return "Elapsed time \(elapsed)"
        }
        return readout.capitalized
    }

    private var latestEvent: String {
        model.recentLogs.last ?? model.detailText
    }

    private func button(_ id: String) -> StageHUDViewModel.ButtonModel? {
        model.buttons.first(where: { $0.id == id })
    }

    private func buttonIsEnabled(_ id: String) -> Bool {
        button(id)?.enabled ?? false
    }

    private func displayTitle(for id: String) -> String {
        return button(id)?.title ?? id.capitalized
    }

    private func monolithButton(_ id: String, icon: String) -> some View {
        StageHUDMonolithButton(
            title: displayTitle(for: id),
            icon: icon,
            tone: button(id)?.tone ?? .secondary,
            enabled: buttonIsEnabled(id),
            hint: button(id)?.hint ?? ""
        ) {
            model.send(id)
        }
    }

    private func hardwareButton(_ id: String, icon: String) -> some View {
        StageHUDHardwareButton(
            title: displayTitle(for: id),
            icon: icon,
            enabled: buttonIsEnabled(id),
            hint: button(id)?.hint ?? ""
        ) {
            model.send(id)
        }
        .frame(width: 44)
    }
}

private struct StageHUDAperture: View {
    let color: Color
    let energized: Bool

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 8
            let signal = energized ? 0.72 : 0.2

            drawCrosshair(context: &context, center: center, radius: radius)
            drawRings(context: &context, center: center, radius: radius, signal: signal)
            drawTicks(context: &context, center: center, radius: radius)
            drawArcs(context: &context, center: center, radius: radius)
        }
        .accessibilityHidden(true)
    }

    private func drawCrosshair(context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        var crosshair = Path()
        crosshair.move(to: CGPoint(x: center.x, y: center.y - radius - 3))
        crosshair.addLine(to: CGPoint(x: center.x, y: center.y + radius + 3))
        crosshair.move(to: CGPoint(x: center.x - radius - 3, y: center.y))
        crosshair.addLine(to: CGPoint(x: center.x + radius + 3, y: center.y))
        context.stroke(crosshair, with: .color(StageHUDTheme.hudEtch.opacity(0.52)), lineWidth: 0.6)
    }

    private func drawRings(context: inout GraphicsContext, center: CGPoint, radius: CGFloat, signal: Double) {
        for inset in [CGFloat(0), 22, 44] {
            let ringRadius = radius - inset
            let rect = CGRect(
                x: center.x - ringRadius,
                y: center.y - ringRadius,
                width: ringRadius * 2,
                height: ringRadius * 2
            )
            let opacity = inset == 22 ? 0.18 + signal * 0.12 : 0.13
            context.stroke(
                Path(ellipseIn: rect),
                with: .color(inset == 24 ? color.opacity(opacity) : StageHUDTheme.hudEtch.opacity(opacity)),
                lineWidth: inset == 0 ? 1.2 : 0.7
            )
        }
    }

    private func drawTicks(context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        for index in 0..<32 {
            let angle = Double(index) / 32 * .pi * 2 - .pi / 2
            let isMajor = index.isMultiple(of: 4)
            let outer = radius - 13
            let inner = outer - (isMajor ? 9 : 4)
            var tick = Path()
            tick.move(to: CGPoint(
                x: center.x + CGFloat(cos(angle)) * inner,
                y: center.y + CGFloat(sin(angle)) * inner
            ))
            tick.addLine(to: CGPoint(
                x: center.x + CGFloat(cos(angle)) * outer,
                y: center.y + CGFloat(sin(angle)) * outer
            ))
            context.stroke(
                tick,
                with: .color(isMajor ? StageHUDTheme.hudPaper.opacity(0.34) : StageHUDTheme.hudEtch.opacity(0.22)),
                lineWidth: isMajor ? 1 : 0.6
            )
        }
    }

    private func drawArcs(context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        for index in 0..<3 {
            let start = Double(index) * (.pi * 2 / 3) + 0.24
            var arc = Path()
            arc.addArc(
                center: center,
                radius: radius - 5,
                startAngle: .radians(start),
                endAngle: .radians(start + 0.52),
                clockwise: false
            )
            context.stroke(arc, with: .color(StageHUDTheme.hudEtch.opacity(0.48)), lineWidth: 2)

            var accent = Path()
            accent.addArc(
                center: center,
                radius: radius - 5,
                startAngle: .radians(start + 0.38),
                endAngle: .radians(start + 0.48),
                clockwise: false
            )
            context.stroke(accent, with: .color(color.opacity(0.85)), lineWidth: 2.4)
        }
    }
}

private struct StageHUDWaveform: View {
    let color: Color
    let energized: Bool

    var body: some View {
        // A fixed signal trace. Live state reads through tint and the header
        // indicator, never through motion — the HUD stays calm while recording.
        Canvas { context, size in
            let centerY = size.height / 2
            var baseline = Path()
            baseline.move(to: CGPoint(x: 0, y: centerY))
            baseline.addLine(to: CGPoint(x: size.width, y: centerY))
            context.stroke(baseline, with: .color(StageHUDTheme.hudEtch.opacity(0.30)), lineWidth: 0.5)

            let barCount = 28
            let spacing = size.width / CGFloat(barCount)
            for index in 0..<barCount {
                let normalized = Double(index) / Double(barCount - 1)
                let envelope = sin(normalized * .pi)
                let profile = 0.34 + 0.28 * abs(sin(Double(index) * 0.7))
                let activity = energized ? profile : 0.14
                let height = max(1.5, size.height * 0.5 * envelope * activity)
                let x = CGFloat(index) * spacing + spacing / 2
                let rect = CGRect(x: x - 1, y: centerY - height, width: 2, height: height * 2)
                context.fill(Path(rect), with: .color(color.opacity(index.isMultiple(of: 9) ? 0.92 : 0.66)))
            }
        }
        .accessibilityHidden(true)
    }
}

private struct StageHUDGraphite: View {
    var body: some View {
        Canvas { context, size in
            // A top-to-bottom ambient wash: the slab catches a little light up
            // high and settles into shadow below.
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .linearGradient(
                    Gradient(colors: [StageHUDTheme.hudGrain, .clear, StageHUDTheme.hudGrainDark]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )

            // Fine brushed striations. Deterministic per-column opacity keeps the
            // grain stable between frames and reads as metal, not photographic noise.
            let step: CGFloat = 2
            var x: CGFloat = 0
            var column = 0
            while x < size.width {
                let hash = (column &* 2654435761) & 0xFF
                let weight = Double(hash) / 255.0
                let light = (column & 1) == 0
                let opacity = 0.012 + weight * 0.02
                var line = Path()
                line.move(to: CGPoint(x: x, y: 0))
                line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(
                    line,
                    with: .color((light ? Color.white : Color.black).opacity(opacity)),
                    lineWidth: 0.5
                )
                x += step
                column += 1
            }
        }
        .accessibilityHidden(true)
    }
}

private struct StageHUDMonolithButton: View {
    let title: String
    let icon: String
    let tone: StageHUDViewModel.ButtonTone
    let enabled: Bool
    let hint: String
    let action: () -> Void

    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(ActionIcon.small)
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .tracking(0.3)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(StageHUDMonolithButtonStyle(
            tone: tone,
            enabled: enabled,
            isHovered: isHovered,
            isFocused: isFocused
        ))
        .disabled(!enabled)
        .focused($isFocused)
        .onHover { isHovered = $0 }
        .accessibilityLabel(title)
        .accessibilityHint(enabled ? hint : "Unavailable in the current capture state")
        .help(hint)
    }
}

private struct StageHUDMonolithButtonStyle: ButtonStyle {
    let tone: StageHUDViewModel.ButtonTone
    let enabled: Bool
    let isHovered: Bool
    let isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foregroundColor)
            .background {
                // Convex key: solid tone, then a top-lit/bottom-shaded bevel so
                // the button reads as raised machined material, not a flat swatch.
                ActionChamferedShape(cornerCut: 7)
                    .fill(buttonFill(configuration: configuration))
                    .overlay {
                        ActionChamferedShape(cornerCut: 7)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        StageHUDTheme.hudBevelLight,
                                        .clear,
                                        StageHUDTheme.hudBevelShadow.opacity(0.55)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .blendMode(configuration.isPressed ? .plusDarker : .normal)
                    }
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(StageHUDTheme.hudPaper.opacity(0.18))
                    .frame(height: 1)
                    .padding(.horizontal, 7)
            }
            .overlay(
                ActionChamferedShape(cornerCut: 7)
                    .stroke(isFocused ? StageHUDTheme.hudCyan : borderColor, lineWidth: isFocused ? 2 : 1)
            )
            .clipShape(ActionChamferedShape(cornerCut: 7))
            .offset(y: configuration.isPressed ? 1 : 0)
            .scaleEffect(configuration.isPressed ? 0.992 : 1)
            .opacity(enabled ? 1 : 0.32)
            .shadow(color: shadowColor, radius: 4, y: 2)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.12), value: isFocused)
    }

    private var foregroundColor: Color {
        tone == .secondary ? StageHUDTheme.hudPaper : StageHUDTheme.hudInk
    }

    private func buttonFill(configuration: Configuration) -> Color {
        switch tone {
        case .primary:
            return isHovered ? StageHUDTheme.hudCyan : StageHUDTheme.hudPaper
        case .destructive:
            return configuration.isPressed ? StageHUDTheme.hudCoral.opacity(0.78) : (isHovered ? StageHUDTheme.hudCoralHot : StageHUDTheme.hudCoral)
        case .secondary:
            return isHovered ? StageHUDTheme.hudPanelRaised : StageHUDTheme.hudMetalTop
        }
    }

    private var borderColor: Color {
        switch tone {
        case .primary:
            return StageHUDTheme.hudPaper.opacity(0.74)
        case .destructive:
            return StageHUDTheme.hudCoralHot.opacity(0.64)
        case .secondary:
            return StageHUDTheme.hudStrokeStrong
        }
    }

    private var shadowColor: Color {
        // A steady, calm grounding shadow. Hover changes fill and border only,
        // so moving the pointer over the bay does not pulse light around it.
        switch tone {
        case .primary:
            return StageHUDTheme.hudCyan.opacity(0.10)
        case .destructive:
            return StageHUDTheme.hudCoral.opacity(0.12)
        case .secondary:
            return StageHUDTheme.hudShadow.opacity(0.30)
        }
    }
}

private struct StageHUDHardwareButton: View {
    let title: String
    let icon: String
    let enabled: Bool
    let hint: String
    let action: () -> Void

    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(ActionIcon.small)
                .foregroundStyle(isHovered ? StageHUDTheme.hudPaper : StageHUDTheme.hudMuted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovered ? StageHUDTheme.hudPanelRaised : StageHUDTheme.hudMetalTop.opacity(0.58))
        .overlay(
            ActionChamferedShape(cornerCut: 4)
                .stroke(isFocused ? StageHUDTheme.hudCyan : StageHUDTheme.hudStrokeStrong, lineWidth: isFocused ? 2 : 1)
        )
        .clipShape(ActionChamferedShape(cornerCut: 4))
        .opacity(enabled ? 1 : 0.3)
        .disabled(!enabled)
        .focused($isFocused)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isFocused)
        .accessibilityLabel(title)
        .accessibilityHint(enabled ? hint : "Unavailable in the current capture state")
        .help(hint)
    }
}

private struct StageHUDBusyControl: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(StageHUDTheme.hudCyan)
                .frame(width: 7, height: 7)
                .overlay(Circle().stroke(StageHUDTheme.hudPaper.opacity(0.22), lineWidth: 1))
                .shadow(color: StageHUDTheme.hudCyan.opacity(0.32), radius: 3)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(StageHUDTheme.hudPaper)
                Text(detail)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(StageHUDTheme.hudMuted)
            }

            Spacer()
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(StageHUDTheme.hudMetalTop.opacity(0.58))
        .overlay(
            ActionChamferedShape(cornerCut: 7)
                .stroke(StageHUDTheme.hudStrokeStrong, lineWidth: 1)
        )
        .clipShape(ActionChamferedShape(cornerCut: 7))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Saving take")
        .accessibilityValue("Writing the movie and finished marker")
    }
}
