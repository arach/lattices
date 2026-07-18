import DeckKit
import SwiftUI
import UIKit

// MARK: - Design System

enum LatsPalette {
    static let bgEdge   = Color(hue: 0.62, saturation: 0.05, brightness: 0.08)
    static let bg       = Color(hue: 0.62, saturation: 0.05, brightness: 0.13)
    static let surface  = Color(hue: 0.62, saturation: 0.06, brightness: 0.18)
    static let surface2 = Color(hue: 0.62, saturation: 0.07, brightness: 0.22)

    static let hairline  = Color.white.opacity(0.06)
    static let hairline2 = Color.white.opacity(0.10)

    static let text      = Color(white: 0.96)
    static let textDim   = Color(white: 0.96).opacity(0.55)
    static let textFaint = Color(white: 0.96).opacity(0.32)

    static let red    = Color(red: 0.95, green: 0.40, blue: 0.42)
    static let amber  = Color(red: 0.96, green: 0.74, blue: 0.36)
    static let green  = Color(red: 0.43, green: 0.86, blue: 0.55)
    static let teal   = Color(red: 0.43, green: 0.83, blue: 0.84)
    static let blue   = Color(red: 0.49, green: 0.71, blue: 0.97)
    static let violet = Color(red: 0.74, green: 0.59, blue: 0.99)
    static let pink   = Color(red: 0.97, green: 0.58, blue: 0.81)
}

enum LatsTint: String, CaseIterable {
    case red, amber, green, teal, blue, violet, pink

    var color: Color {
        switch self {
        case .red: return LatsPalette.red
        case .amber: return LatsPalette.amber
        case .green: return LatsPalette.green
        case .teal: return LatsPalette.teal
        case .blue: return LatsPalette.blue
        case .violet: return LatsPalette.violet
        case .pink: return LatsPalette.pink
        }
    }

    static func from(token: String?) -> LatsTint {
        guard let token = token?.lowercased() else { return .blue }
        return LatsTint(rawValue: token) ?? .blue
    }
}

enum LatsFont {
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

// MARK: - Models

enum CockpitMode: String, CaseIterable {
    case idle, rec, replay, agent

    var label: String { rawValue.uppercased() }
    var color: Color {
        switch self {
        case .idle: return LatsPalette.green
        case .rec: return LatsPalette.red
        case .replay: return LatsPalette.green
        case .agent: return LatsPalette.violet
        }
    }
}

enum ShortcutCategory: String {
    case voice, agent, system, window, dev
    var color: Color {
        switch self {
        case .voice: return LatsPalette.red
        case .agent: return LatsPalette.violet
        case .system: return LatsPalette.amber
        case .window: return LatsPalette.blue
        case .dev: return LatsPalette.green
        }
    }
}

enum SimAction { case rec, voice, agent, tile, move, palette, none }

// MARK: - Live data adapters

extension CockpitMode {
    init(from deckMode: DeckCockpitMode) {
        switch deckMode {
        case .idle: self = .idle
        case .rec: self = .rec
        case .replay: self = .replay
        case .agent: self = .agent
        }
    }
}

extension LatsTelemetry {
    init(from deck: DeckSystemTelemetry) {
        self.cpu = deck.cpuLoadPercent ?? 0
        self.mem = deck.memoryUsedPercent ?? 0
        self.gpu = deck.gpuLoadPercent ?? 0
        if let temperature = deck.temperatureCelsius {
            self.therm = temperature
        } else {
            // No stable public Mac temperature API; map pressure into the design gauge.
            let pressure = deck.thermalPressurePercent ?? 0
            self.therm = 42 + (pressure / 100.0) * 30
        }
        self.batt = deck.batteryPercent ?? 0
        self.windows = deck.windowCount
    }
}

struct LatsShortcut: Identifiable {
    let id: String
    let label: String
    let icon: String      // SF Symbol name
    let tint: LatsTint
    let category: ShortcutCategory
    let hint: String
    let sim: SimAction
    var actionID: String? = nil
    var payload: [String: DeckValue] = [:]
    var controlKind: DeckCockpitControlKind? = nil
    var col: Int? = nil
    var row: Int? = nil
    var colSpan: Int? = nil
    var rowSpan: Int? = nil
    var isEnabled = true

    init(
        id: String = UUID().uuidString,
        label: String,
        icon: String,
        tint: LatsTint,
        category: ShortcutCategory,
        hint: String,
        sim: SimAction,
        actionID: String? = nil,
        payload: [String: DeckValue] = [:],
        controlKind: DeckCockpitControlKind? = nil,
        col: Int? = nil,
        row: Int? = nil,
        colSpan: Int? = nil,
        rowSpan: Int? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.label = label
        self.icon = icon
        self.tint = tint
        self.category = category
        self.hint = hint
        self.sim = sim
        self.actionID = actionID
        self.payload = payload
        self.controlKind = controlKind
        self.col = col
        self.row = row
        self.colSpan = colSpan
        self.rowSpan = rowSpan
        self.isEnabled = isEnabled
    }
}

struct LatsWindow: Identifiable {
    let id = UUID()
    let x: Double
    let y: Double
    let w: Double
    let h: Double
    let tint: LatsTint
    let tag: String
}

struct CommandDeck {
    static let accent: LatsTint = .green
    static let name = "command"
    static let hint = "core"

    static let shortcuts: [LatsShortcut] = [
        .init(label: "Dictate",     icon: "mic.fill",                 tint: .red,    category: .voice,  hint: "F1",  sim: .rec),
        .init(label: "Voice Cmd",   icon: "waveform",                  tint: .red,    category: .voice,  hint: "F2",  sim: .voice),
        .init(label: "Record",      icon: "record.circle.fill",        tint: .red,    category: .voice,  hint: "F3",  sim: .rec),
        .init(label: "Search",      icon: "magnifyingglass",           tint: .blue,   category: .system, hint: "F4",  sim: .palette),
        .init(label: "Palette",     icon: "command",                   tint: .violet, category: .system, hint: "⌘K",  sim: .palette),
        .init(label: "Pairing",     icon: "laptopcomputer.and.iphone", tint: .pink,   category: .system, hint: "⌘P",  sim: .none),
        .init(label: "Claude",      icon: "sparkles",                  tint: .violet, category: .agent,  hint: "F7",  sim: .agent),
        .init(label: "Pi",          icon: "sparkle",                   tint: .teal,   category: .agent,  hint: "F8",  sim: .agent),
        .init(label: "Workflows",   icon: "point.3.connected.trianglepath.dotted", tint: .teal, category: .system, hint: "F11", sim: .none),
        .init(label: "Pending",     icon: "clock",                     tint: .amber,  category: .system, hint: "F12", sim: .none),
        .init(label: "Recents",     icon: "clock.arrow.circlepath",    tint: .violet, category: .system, hint: "F9",  sim: .none),
        .init(label: "Home",        icon: "house.fill",                tint: .pink,   category: .system, hint: "F10", sim: .none),
        .init(label: "Tile 2-up",   icon: "rectangle.split.2x1",       tint: .blue,   category: .window, hint: "⌘1",  sim: .tile),
        .init(label: "Tile 4-up",   icon: "rectangle.split.2x2",       tint: .blue,   category: .window, hint: "⌘2",  sim: .tile),
        .init(label: "L Monitor",   icon: "display",                   tint: .blue,   category: .window, hint: "⌘3",  sim: .move),
        .init(label: "R Monitor",   icon: "display",                   tint: .blue,   category: .window, hint: "⌘4",  sim: .move),
        .init(label: "Desktop Pv",  icon: "macwindow.on.rectangle",    tint: .blue,   category: .window, hint: "⌘5",  sim: .none),
        .init(label: "Memos",       icon: "note.text",                 tint: .amber,  category: .voice,  hint: "⌘M",  sim: .none),
    ]

    static let stage: [[LatsWindow]] = [
        [   // Display 0 — terminals
            .init(x: 5,  y: 12, w: 42, h: 78, tint: .green, tag: "tmux"),
            .init(x: 50, y: 12, w: 45, h: 38, tint: .green, tag: "vim"),
            .init(x: 50, y: 54, w: 45, h: 36, tint: .green, tag: "logs"),
        ],
        [   // Display 1 — chrome + figma
            .init(x: 5,  y: 14, w: 50, h: 76, tint: .blue,   tag: "chr"),
            .init(x: 58, y: 14, w: 38, h: 36, tint: .blue,   tag: "chr"),
            .init(x: 58, y: 54, w: 38, h: 36, tint: .violet, tag: "fig"),
        ],
    ]

    static let transcript = [
        "move all terminals to the left monitor",
        "open shell in the lats project",
        "tile chrome two up on the right",
    ]
}

struct LatsTelemetry {
    var cpu: Double = 32
    var mem: Double = 68
    var gpu: Double = 18
    var therm: Double = 52
    var batt: Double = 65
    var windows: Int = 23
}

// MARK: - Top Chrome

struct LatsTopChrome: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let deckName: String
    let deckNames: [String]
    let accent: Color
    let onSwitcher: () -> Void
    let onClose: () -> Void

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                compactChrome
            } else {
                regularChrome
            }
        }
        .background(Color.black.opacity(0.25))
        .overlay(alignment: .bottom) {
            Rectangle().fill(LatsPalette.hairline).frame(height: 1)
        }
    }

    private var compactChrome: some View {
        HStack(spacing: 10) {
            Text("LATS · DECK")
                .font(LatsFont.mono(11, weight: .bold))
                .foregroundStyle(LatsPalette.text)
                .tracking(1.3)
                .fixedSize()

            Button(action: onSwitcher) {
                HStack(spacing: 5) {
                    Text(deckName)
                        .font(LatsFont.mono(10, weight: .bold))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(LatsPalette.textFaint)
                }
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 5).fill(accent.opacity(0.10)))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(accent.opacity(0.30), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LatsPalette.textDim)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close deck")
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
    }

    private var regularChrome: some View {
        HStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("LATS · DECK")
                    .font(LatsFont.mono(11, weight: .bold))
                    .foregroundStyle(LatsPalette.text)
                    .tracking(1.5)
                Text("·").foregroundStyle(LatsPalette.textFaint)
                Button(action: onSwitcher) {
                    HStack(spacing: 6) {
                        ForEach(Array(deckNames.enumerated()), id: \.offset) { index, name in
                            if index > 0 {
                                Text("/").font(LatsFont.mono(11)).foregroundStyle(LatsPalette.textFaint)
                            }
                            Text(name)
                                .font(LatsFont.mono(11, weight: name == deckName ? .bold : .regular))
                                .foregroundStyle(name == deckName ? accent : LatsPalette.textDim)
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(LatsPalette.textFaint)
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer()

            HStack(spacing: 14) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(LatsPalette.textDim)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(LatsPalette.textDim)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
    }
}

// MARK: - Cockpit Shell

struct LatsCockpitShell<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(LatsPalette.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(LatsPalette.hairline2, lineWidth: 1)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.045))
                .frame(height: 1)
                .padding(.horizontal, 6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: Color.black.opacity(0.48), radius: 7, x: 0, y: 4)
    }
}

// MARK: - Trackpad Surface

struct LatsTrackpadSurface: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let mode: CockpitMode
    let recTime: Double
    let agentProgress: Double
    let replayMessage: String
    let replayUndoLabel: String
    let agentRows: [DeckAgentPlanRow]
    let telemetry: LatsTelemetry
    let stage: [[LatsWindow]]
    let space: Int
    let spaceCount: Int
    let spaceName: String?
    let transcript: [String]
    let activityLog: [DeckActivityLogEntry]
    let hostLabel: String
    let trackpadState: DeckTrackpadState?
    var spaceDisplays: [DeckSpaceDisplay] = []
    var frontmostApp: String? = nil
    var frontmostTitle: String? = nil
    var onSendKey: ((String, [String]) -> Void)? = nil
    var onReplayUndo: (() -> Void)? = nil
    var onTrackpadEvent: ((DeckTrackpadEvent, Double, Double) -> Void)? = nil
    var onSpaceTap: ((Int) -> Void)? = nil
    var onMonitorSwipe: ((_ display: Int, _ direction: Int) -> Void)? = nil

    @State private var lastTrackpadLocation: CGPoint?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(LatsPalette.bgEdge)
                .overlay(LatsGridBackground())
                .contentShape(Rectangle())
                .gesture(trackpadDragGesture)
                .simultaneousGesture(trackpadTapGesture)
                .allowsHitTesting(isTrackpadReady)

            // Top bezel: useful state — Mac name (left), live mode (center), frontmost app/title (right).
            // Symmetric with the bottom action bezel; together they frame the touch surface.
            VStack(spacing: 0) {
                LatsTrackpadTopBezel(
                    hostLabel: hostLabel,
                    isAvailable: trackpadState?.isAvailable ?? false,
                    mode: mode,
                    recTime: recTime,
                    agentRows: agentRows,
                    frontmostApp: frontmostApp,
                    frontmostTitle: frontmostTitle
                )
                Spacer()
            }
            .allowsHitTesting(false)

            // Center mode visual
            LatsTrackpadModeVisual(
                mode: mode,
                recTime: recTime,
                agentProgress: agentProgress,
                replayMessage: replayMessage,
                replayUndoLabel: replayUndoLabel,
                agentRows: agentRows,
                onReplayUndo: onReplayUndo
            )
            .allowsHitTesting(mode == .replay && onReplayUndo != nil)

            if horizontalSizeClass != .compact {
                // LEFT column — system on top, displays bottom; equal share of vertical space
                VStack(alignment: .leading, spacing: 8) {
                    LatsInsetSlice {
                        CompactSystemPanel(hostLabel: hostLabel, telemetry: telemetry)
                    }
                    .frame(maxHeight: .infinity)
                    LatsInsetSlice {
                        CompactDisplaysPanel(
                            stage: stage,
                            space: space,
                            spaceCount: spaceCount,
                            spaceName: spaceName,
                            spaceDisplays: spaceDisplays,
                            onSpaceTap: onSpaceTap,
                            onMonitorSwipe: onMonitorSwipe
                        )
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(width: 240)
                .padding(.top, 30)
                .padding(.bottom, 56)
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                // RIGHT column — transcript on top, activity bottom; equal share of vertical space
                VStack(alignment: .leading, spacing: 8) {
                    LatsInsetSlice {
                        CompactTranscriptPanel(items: transcript)
                    }
                    .frame(maxHeight: .infinity)
                    LatsInsetSlice {
                        CompactActivityLogPanel(entries: activityLog)
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(width: 240)
                .padding(.top, 30)
                .padding(.bottom, 56)
                .padding(.trailing, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            }

            // Bottom bezel: keyboard buttons sit on a quiet ledge that mirrors the top bezel.
            VStack(spacing: 0) {
                Spacer()
                LatsActionKeyboardRow(onSendKey: onSendKey)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.32))
                    .overlay(alignment: .top) {
                        Rectangle().fill(LatsPalette.hairline).frame(height: 1)
                    }
            }
        }
        .background(LatsPalette.bgEdge)
    }

    private var isTrackpadReady: Bool {
        guard let state = trackpadState else { return onTrackpadEvent != nil }
        return state.isEnabled && state.isAvailable && onTrackpadEvent != nil
    }

    private var trackpadDragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard isTrackpadReady else { return }
                guard let previous = lastTrackpadLocation else {
                    lastTrackpadLocation = value.location
                    return
                }

                let dx = value.location.x - previous.x
                let dy = value.location.y - previous.y
                lastTrackpadLocation = value.location

                guard abs(dx) > 0.2 || abs(dy) > 0.2 else { return }
                let scale = trackpadState?.pointerScale ?? 1.6
                onTrackpadEvent?(.move, Double(dx) * scale, Double(dy) * scale)
            }
            .onEnded { _ in
                lastTrackpadLocation = nil
            }
    }

    private var trackpadTapGesture: some Gesture {
        TapGesture()
            .onEnded {
                guard isTrackpadReady else { return }
                onTrackpadEvent?(.click, 0, 0)
            }
    }
}

/// Symmetric counterpart to the bottom action bezel. Hosts genuinely useful state
/// — paired Mac (left), live cockpit mode (center), frontmost app/title (right) —
/// using the same dark ledge + hairline so top and bottom frame the touch surface.
struct LatsTrackpadTopBezel: View {
    let hostLabel: String
    let isAvailable: Bool
    let mode: CockpitMode
    let recTime: Double
    let agentRows: [DeckAgentPlanRow]
    let frontmostApp: String?
    let frontmostTitle: String?

    var body: some View {
        HStack(spacing: 10) {
            // LEFT — paired Mac
            HStack(spacing: 5) {
                Circle()
                    .fill(isAvailable ? LatsPalette.green : LatsPalette.amber)
                    .frame(width: 5, height: 5)
                Text(shortHost)
                    .font(LatsFont.mono(9, weight: .semibold))
                    .foregroundStyle(LatsPalette.text)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // CENTER — live mode (replaces the floating modeBadge)
            modeText
                .font(LatsFont.mono(9, weight: .semibold))
                .tracking(1.2)
                .textCase(.uppercase)

            // RIGHT — what the user is controlling on the Mac
            HStack(spacing: 4) {
                if let app = frontmostApp, !app.isEmpty {
                    Text(app)
                        .font(LatsFont.mono(9, weight: .semibold))
                        .foregroundStyle(LatsPalette.text)
                        .lineLimit(1)
                    if let title = frontmostTitle, !title.isEmpty {
                        Text("·")
                            .font(LatsFont.mono(9))
                            .foregroundStyle(LatsPalette.textFaint)
                        Text(title)
                            .font(LatsFont.mono(9))
                            .foregroundStyle(LatsPalette.textDim)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } else {
                    Text("idle")
                        .font(LatsFont.mono(9))
                        .foregroundStyle(LatsPalette.textFaint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.32))
        .overlay(alignment: .bottom) {
            Rectangle().fill(LatsPalette.hairline).frame(height: 1)
        }
    }

    private var shortHost: String {
        hostLabel
            .replacingOccurrences(of: ".local", with: "")
            .replacingOccurrences(of: ".lan", with: "")
    }

    @ViewBuilder
    private var modeText: some View {
        switch mode {
        case .idle:
            Text(isAvailable ? "ready" : "tap to wake")
                .foregroundStyle(isAvailable ? LatsPalette.green : LatsPalette.amber)
        case .rec:
            HStack(spacing: 4) {
                Circle().fill(LatsPalette.red).frame(width: 5, height: 5)
                Text("rec · \(recTime, specifier: "%.1f")s")
                    .foregroundStyle(LatsPalette.red)
            }
        case .replay:
            Text("✓ done · \(recTime, specifier: "%.1f")s")
                .foregroundStyle(LatsPalette.green)
        case .agent:
            let liveIndex = agentRows.firstIndex(where: { $0.state == .live }).map { $0 + 1 } ?? 1
            let total = max(agentRows.count, 1)
            Text("agent · \(liveIndex)/\(total)")
                .foregroundStyle(LatsPalette.violet)
        }
    }
}

struct LatsGridBackground: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 20
            let lineColor = Color.white.opacity(0.025)
            var path = Path()
            var x: CGFloat = 0
            while x < size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y: CGFloat = 0
            while y < size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            context.stroke(path, with: .color(lineColor), lineWidth: 1)
        }
    }
}

struct LatsInsetSlice<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hue: 0.62, saturation: 0.05, brightness: 0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(LatsPalette.hairline2, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Compact Inset Modules

struct CompactSystemPanel: View {
    let hostLabel: String
    let telemetry: LatsTelemetry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(hostLabel)
                    .font(LatsFont.mono(10, weight: .semibold))
                    .foregroundStyle(LatsPalette.text)
                Spacer()
                Text("● 14ms")
                    .font(LatsFont.mono(8.5))
                    .foregroundStyle(LatsPalette.green)
            }
            telemetryRow("cpu", value: telemetry.cpu, color: LatsPalette.green)
            telemetryRow("mem", value: telemetry.mem, color: LatsPalette.amber)
            telemetryRow("gpu", value: telemetry.gpu, color: LatsPalette.violet)
            HStack {
                Text("batt \(Int(telemetry.batt))%")
                Spacer()
                Text("\(Int(telemetry.therm))°C")
                Spacer()
                Text("\(telemetry.windows)w")
            }
            .font(LatsFont.mono(8.5))
            .foregroundStyle(LatsPalette.textFaint)
            .padding(.top, 2)
            .overlay(alignment: .top) {
                Rectangle().fill(LatsPalette.hairline).frame(height: 1)
            }
        }
    }

    private func telemetryRow(_ key: String, value: Double, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(key.uppercased())
                .font(LatsFont.mono(9))
                .foregroundStyle(LatsPalette.textFaint)
                .frame(width: 24, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color)
                        .frame(width: geo.size.width * value / 100, height: 3)
                }
            }
            .frame(height: 3)
            Text("\(Int(value))%")
                .font(LatsFont.mono(9))
                .foregroundStyle(LatsPalette.text)
                .frame(width: 26, alignment: .trailing)
        }
    }
}

struct CompactDisplaysPanel: View {
    let stage: [[LatsWindow]]
    let space: Int
    let spaceCount: Int
    let spaceName: String?
    var spaceDisplays: [DeckSpaceDisplay] = []
    var onSpaceTap: ((Int) -> Void)? = nil
    var onMonitorSwipe: ((_ display: Int, _ direction: Int) -> Void)? = nil

    @State private var selectedDisplay: Int = 0

    /// Authoritative monitor count: stage mirrors NSScreen.screens.count from the
    /// bridge, falling back to live spaceDisplays then 1. Never silently 2.
    private var monitorCount: Int {
        if !stage.isEmpty { return stage.count }
        if !spaceDisplays.isEmpty { return spaceDisplays.count }
        return 1
    }

    private var activeDisplay: Int {
        max(0, min(selectedDisplay, monitorCount - 1))
    }

    private var windowsForActiveDisplay: [LatsWindow] {
        activeDisplay < stage.count ? stage[activeDisplay] : []
    }

    private var spacesForActiveDisplay: [Int] {
        if activeDisplay < spaceDisplays.count {
            return spaceDisplays[activeDisplay].spaces.map(\.index)
        }
        return Array(0..<max(spaceCount, 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("displays")
                    .font(LatsFont.mono(10, weight: .semibold))
                    .foregroundStyle(LatsPalette.text)
                Spacer()
                if monitorCount > 1 {
                    HStack(spacing: 3) {
                        ForEach(0..<monitorCount, id: \.self) { d in
                            displayPill(d)
                        }
                    }
                } else {
                    Text(spaceName ?? "\(space + 1)")
                        .font(LatsFont.mono(8.5))
                        .foregroundStyle(LatsPalette.textFaint)
                }
            }

            // Single mini-display for the selected monitor (full panel width).
            miniDisplay(windows: windowsForActiveDisplay)
                .contentShape(Rectangle())
                .gesture(monitorSwipeGesture(displayIndex: activeDisplay))
                .frame(maxHeight: .infinity)

            // Space cells for the selected monitor.
            let indices = spacesForActiveDisplay
            if !indices.isEmpty {
                HStack(spacing: 2) {
                    ForEach(indices, id: \.self) { i in
                        spaceCell(index: i)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func displayPill(_ d: Int) -> some View {
        let isActive = d == activeDisplay
        return Button {
            selectedDisplay = d
        } label: {
            Text("D\(d + 1)")
                .font(LatsFont.mono(8, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? LatsPalette.green : LatsPalette.textDim)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isActive ? LatsPalette.green.opacity(0.2) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(isActive ? LatsPalette.green : LatsPalette.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    /// Horizontal swipe on a monitor: left → previous space, right → next space.
    private func monitorSwipeGesture(displayIndex: Int) -> some Gesture {
        DragGesture(minimumDistance: 18)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > 60, abs(dx) > abs(dy) * 1.4 else { return }
                onMonitorSwipe?(displayIndex, dx < 0 ? 1 : -1)
            }
    }

    private func miniDisplay(windows: [LatsWindow]) -> some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(LatsPalette.bgEdge)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(LatsPalette.hairline, lineWidth: 1)
                    )
                ForEach(windows) { w in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(w.tint.color.opacity(0.3))
                        .overlay(
                            RoundedRectangle(cornerRadius: 1)
                                .stroke(w.tint.color.opacity(0.6), lineWidth: 1)
                        )
                        .frame(
                            width: geo.size.width * w.w / 100,
                            height: geo.size.height * w.h / 100
                        )
                        .position(
                            x: geo.size.width * (w.x + w.w / 2) / 100,
                            y: geo.size.height * (w.y + w.h / 2) / 100
                        )
                }
            }
        }
    }

    private func spaceCell(index: Int) -> some View {
        let isActive = index == space
        let label = Text("\(index + 1)")
            .font(LatsFont.mono(8, weight: isActive ? .semibold : .regular))
            .foregroundStyle(isActive ? LatsPalette.green : LatsPalette.textDim)
            .frame(maxWidth: .infinity, maxHeight: 14)
            .background(
                RoundedRectangle(cornerRadius: 2)
                    .fill(isActive ? LatsPalette.green.opacity(0.25) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(isActive ? LatsPalette.green : LatsPalette.hairline, lineWidth: 1)
            )
            .contentShape(Rectangle())

        return Group {
            if let onSpaceTap {
                Button { onSpaceTap(index) } label: { label }.buttonStyle(.plain)
            } else {
                label
            }
        }
    }
}

struct CompactTranscriptPanel: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("transcript")
                    .font(LatsFont.mono(10, weight: .semibold))
                    .foregroundStyle(LatsPalette.text)
                Spacer()
                HStack(spacing: 3) {
                    Circle().fill(LatsPalette.amber).frame(width: 4, height: 4)
                    Text("live")
                        .font(LatsFont.mono(8.5))
                        .foregroundStyle(LatsPalette.amber)
                }
            }
            ForEach(Array(items.prefix(3).enumerated()), id: \.offset) { idx, text in
                HStack(alignment: .top, spacing: 4) {
                    Text("›")
                        .font(LatsFont.mono(9))
                        .foregroundStyle(LatsPalette.amber)
                    Text("\"\(text)\"")
                        .font(LatsFont.mono(9))
                        .foregroundStyle(idx == 0 ? LatsPalette.text : LatsPalette.textDim)
                        .opacity(1 - Double(idx) * 0.2)
                        .lineLimit(1)
                }
            }
        }
    }
}

struct CompactActivityLogPanel: View {
    let entries: [DeckActivityLogEntry]

    private var sortedEntries: [DeckActivityLogEntry] {
        entries.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("activity")
                    .font(LatsFont.mono(10, weight: .semibold))
                    .foregroundStyle(LatsPalette.text)
                Spacer()
                Text("\(entries.count)")
                    .font(LatsFont.mono(8.5))
                    .foregroundStyle(LatsPalette.textFaint)
            }

            if sortedEntries.isEmpty {
                HStack(spacing: 4) {
                    Text("IDLE")
                        .font(LatsFont.mono(8.5, weight: .semibold))
                        .foregroundStyle(LatsPalette.textFaint)
                        .frame(width: 44, alignment: .leading)
                    Text("waiting for bridge events")
                        .font(LatsFont.mono(9))
                        .foregroundStyle(LatsPalette.textFaint)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(sortedEntries) { entry in
                            HStack(alignment: .top, spacing: 4) {
                                Text(entry.tag.uppercased())
                                    .font(LatsFont.mono(8.5, weight: .semibold))
                                    .foregroundStyle(LatsTint.from(token: entry.tint).color)
                                    .frame(width: 44, alignment: .leading)
                                Text(entry.text)
                                    .font(LatsFont.mono(9))
                                    .foregroundStyle(LatsPalette.textDim)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.04),
                            .init(color: .black, location: 0.92),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            }
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Mode Visuals (center of trackpad)

struct LatsTrackpadModeVisual: View {
    let mode: CockpitMode
    let recTime: Double
    let agentProgress: Double
    let replayMessage: String
    let replayUndoLabel: String
    let agentRows: [DeckAgentPlanRow]
    var onReplayUndo: (() -> Void)? = nil

    var body: some View {
        Group {
            switch mode {
            case .idle: idleView
            case .rec: recView
            case .replay: replayView
            case .agent: agentView
            }
        }
    }

    private var idleView: some View {
        VStack(spacing: 4) {
            Image(systemName: "cursorarrow.motionlines")
                .font(.system(size: 13, weight: .light))
                .foregroundColor(.white.opacity(0.18))
            Text("TRACKPAD")
                .font(.system(size: 8, weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.12))
                .tracking(1.5)
        }
    }

    private var recView: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<70, id: \.self) { i in
                    let phase = t * 5 + Double(i) * 0.3
                    let h: Double = 6 + abs(sin(phase) * 32) + abs(sin(phase * 1.7) * 18)
                    let active = i < 56
                    Capsule()
                        .fill(active ? LatsPalette.red : Color.white.opacity(0.12))
                        .frame(width: 2, height: h)
                }
            }
            .frame(maxWidth: 360)
        }
    }

    private var replayView: some View {
        let content = VStack(spacing: 8) {
            Text("\u{201C}\(replayMessage)\u{201D}")
                .font(LatsFont.ui(16, weight: .medium))
                .foregroundStyle(LatsPalette.text)
                .multilineTextAlignment(.center)
            Text("✓ confirmed · \(replayUndoLabel)")
                .font(LatsFont.mono(10))
                .tracking(0.5)
                .foregroundStyle(LatsPalette.green)
        }
        .frame(maxWidth: 480)
        .padding(.horizontal, 24)

        return Group {
            if let onReplayUndo {
                Button(action: onReplayUndo) { content }
                    .buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    private var agentView: some View {
        let rows = normalizedAgentRows
        return HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    agentRow(row.tag, row.text, row.color)
                }
            }
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 3)
                    .frame(width: 90, height: 90)
                Circle()
                    .trim(from: 0, to: min(1, agentProgress / 264))
                    .stroke(LatsPalette.violet, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 90, height: 90)
                Text("\(Int(agentProgress / 264 * 100))%")
                    .font(LatsFont.mono(18, weight: .semibold))
                    .foregroundStyle(LatsPalette.text)
            }
        }
    }

    private var normalizedAgentRows: [(tag: String, text: String, color: Color)] {
        if agentRows.isEmpty {
            return [
                ("done", "enumerate workspaces", LatsPalette.green),
                ("done", "find terminals", LatsPalette.green),
                ("live", "apply current plan", LatsPalette.violet),
                ("next", "confirm result", LatsPalette.textFaint)
            ]
        }

        return Array(agentRows.prefix(5)).map { row in
            switch row.state {
            case .done:
                return ("done", row.text, LatsPalette.green)
            case .live:
                return ("live", row.text, LatsPalette.violet)
            case .next:
                return ("next", row.text, LatsPalette.textFaint)
            }
        }
    }

    private func agentRow(_ tag: String, _ msg: String, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Text(tag.uppercased())
                .font(LatsFont.mono(9, weight: .semibold))
                .tracking(1)
                .foregroundStyle(color)
                .frame(width: 38, alignment: .leading)
            Text(msg)
                .font(LatsFont.mono(11))
                .foregroundStyle(tag == "next" ? LatsPalette.textFaint : LatsPalette.text)
        }
    }
}

// MARK: - Action Keyboard Row

/// Sticky modifier model. The bottom-row keyboard tracks each modifier in one of
/// three states so the user can compose chords by tapping rather than holding.
///
/// - `off`: not engaged.
/// - `armed`: single-tap one-shot — included in the next non-modifier key press,
///   then clears back to `off`.
/// - `locked`: double-tap sticky — stays held across multiple key presses until
///   the modifier is tapped again.
enum LatsModifier: String, CaseIterable, Hashable {
    case control, option, shift, command

    /// Glyph rendered on the chip (matches the existing aesthetic).
    var glyph: String {
        switch self {
        case .control: return "⌃"
        case .option:  return "⌥"
        case .shift:   return "⇧"
        case .command: return "⌘"
        }
    }

    /// Wire value sent in `keys.send`'s `modifiers` array. The Mac side
    /// (`CompanionKeyboardController.normalizeModifier`) accepts both the long
    /// name and the glyph; we use the long name for clarity in logs.
    var wire: String { rawValue }
}

enum LatsModifierState {
    case off, armed, locked
}

struct LatsActionKeyboardRow: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var onSendKey: ((String, [String]) -> Void)? = nil

    /// Source of truth for sticky modifier state. Tapping a chip cycles
    /// `off → armed → locked → off`. A non-modifier key press clears any
    /// `armed` chips back to `off` (locked chips remain).
    @State private var modifierStates: [LatsModifier: LatsModifierState] = [:]

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                compactRow
            } else {
                regularRow
            }
        }
    }

    private var compactRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ActionKey(label: "esc", width: 30) { send("escape", []) }
                ActionKey(label: "⌘C", width: 30) { send("c", [.command]) }
                ActionKey(label: "⌘V", width: 30) { send("v", [.command]) }
                ActionKey(label: "space", width: 52) { send("space", []) }
                ArrowCluster(onTap: { dir in send(dir, []) })
                ForEach(LatsModifier.allCases, id: \.self) { mod in
                    ModifierKey(
                        label: mod.glyph,
                        state: modifierStates[mod] ?? .off,
                        onSingleTap: { cycleModifier(mod) },
                        onDoubleTap: { setModifier(mod, .locked) }
                    )
                }
                EnterPill { send("return", []) }
            }
            .padding(.horizontal, 4)
        }
    }

    private var regularRow: some View {
        HStack(spacing: 12) {
            // Left — utility keys + common combos. Combos fold in any active
            // sticky modifiers so e.g. armed Shift + ⌘C → ⇧⌘C.
            HStack(spacing: 4) {
                ActionKey(label: "esc", width: 30) { send("escape", []) }
                ActionKey(label: "⌘C", width: 30) { send("c", [.command]) }
                ActionKey(label: "⌘V", width: 30) { send("v", [.command]) }
                ActionKey(label: "⌘Z", width: 30) { send("z", [.command]) }
                ActionKey(label: "⇧⇥", width: 30) { send("tab", [.shift]) }
                ActionKey(label: "space", width: 56) { send("space", []) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Center — arrow cluster (also picks up active modifiers).
            ArrowCluster(onTap: { dir in send(dir, []) })

            // Right — sticky modifiers + enter.
            HStack(spacing: 4) {
                ForEach(LatsModifier.allCases, id: \.self) { mod in
                    ModifierKey(
                        label: mod.glyph,
                        state: modifierStates[mod] ?? .off,
                        onSingleTap: { cycleModifier(mod) },
                        onDoubleTap: { setModifier(mod, .locked) }
                    )
                }
                EnterPill { send("return", []) }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 4)
    }

    // MARK: Modifier state machine

    /// Single-tap cycles a modifier through `off → armed → locked → off`.
    /// Tap once to arm for the next key, tap again to lock it, tap a third
    /// time to release. Double-tap is handled separately in `ModifierKey`
    /// and jumps straight to `locked` via `setModifier`.
    private func cycleModifier(_ mod: LatsModifier) {
        let current = modifierStates[mod] ?? .off
        let next: LatsModifierState
        switch current {
        case .off:    next = .armed
        case .armed:  next = .locked
        case .locked: next = .off
        }
        withAnimation(.easeOut(duration: 0.12)) {
            modifierStates[mod] = next
        }
    }

    /// Direct setter used by double-tap (and any future explicit transition).
    private func setModifier(_ mod: LatsModifier, _ state: LatsModifierState) {
        withAnimation(.easeOut(duration: 0.12)) {
            modifierStates[mod] = state
        }
    }

    /// Wire helper that takes a key and an explicit set of "preset" modifiers
    /// (e.g. ⌘C) and folds in any armed/locked sticky modifiers, then clears
    /// armed ones. Locked modifiers persist for the next press.
    private func send(_ key: String, _ presets: [LatsModifier]) {
        var active = Set<LatsModifier>(presets)
        for (mod, state) in modifierStates where state != .off {
            active.insert(mod)
        }

        // Stable, predictable order to match Mac-side display ordering
        // (control, option, shift, command).
        let ordered = LatsModifier.allCases.filter { active.contains($0) }
        let wire = ordered.map(\.wire)

        onSendKey?(key, wire)

        // Clear armed modifiers; locked modifiers stay engaged.
        let armed = modifierStates.filter { $0.value == .armed }.map(\.key)
        if !armed.isEmpty {
            withAnimation(.easeOut(duration: 0.12)) {
                for mod in armed { modifierStates[mod] = .off }
            }
        }
    }
}

/// A single sticky-modifier chip. Visually distinguishes three states using
/// the existing `LatsPalette` greens — armed shows an outlined glow; locked
/// fills the chip and adds a tiny lock badge so the held state is unmistakable.
struct ModifierKey: View {
    let label: String
    let state: LatsModifierState
    let onSingleTap: () -> Void
    let onDoubleTap: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Text(label)
                .font(LatsFont.mono(10, weight: state == .off ? .medium : .semibold))
                .foregroundStyle(foreground)
                .frame(minWidth: 26)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(background)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(border, lineWidth: state == .off ? 1 : 1.25)
                )
                .shadow(
                    color: state == .off ? .clear : LatsPalette.green.opacity(state == .locked ? 0.35 : 0.22),
                    radius: state == .off ? 0 : 4,
                    x: 0,
                    y: 0
                )

            if state == .locked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(LatsPalette.bgEdge)
                    .padding(2)
                    .background(Circle().fill(LatsPalette.green))
                    .offset(x: 4, y: -4)
            }
        }
        // Double-tap is declared first so SwiftUI gives it priority when a
        // tap could match either gesture; single-tap fires only after the
        // double-tap window elapses.
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onDoubleTap() }
        .onTapGesture(count: 1) { onSingleTap() }
        .accessibilityLabel(Text("\(label) modifier"))
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityHint(Text("Tap to arm for next key, double-tap to lock"))
    }

    private var foreground: Color {
        switch state {
        case .off:    return LatsPalette.textDim
        case .armed:  return LatsPalette.green
        case .locked: return LatsPalette.bgEdge
        }
    }

    private var background: Color {
        switch state {
        case .off:    return Color.white.opacity(0.04)
        case .armed:  return LatsPalette.green.opacity(0.18)
        case .locked: return LatsPalette.green.opacity(0.95)
        }
    }

    private var border: Color {
        switch state {
        case .off:    return LatsPalette.hairline
        case .armed:  return LatsPalette.green.opacity(0.7)
        case .locked: return LatsPalette.green
        }
    }

    private var accessibilityValue: String {
        switch state {
        case .off:    return "off"
        case .armed:  return "armed"
        case .locked: return "locked"
        }
    }
}

struct ActionKey: View {
    let label: String
    var width: CGFloat = 28
    var accent: Color? = nil
    var onTap: (() -> Void)? = nil

    var body: some View {
        let label = Text(label)
            .font(LatsFont.mono(10, weight: .medium))
            .foregroundStyle(accent ?? LatsPalette.textDim)
            .frame(minWidth: width)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(accent.map { $0.opacity(0.16) } ?? Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(accent ?? LatsPalette.hairline, lineWidth: 1)
            )

        if let onTap {
            Button(action: onTap) { label }.buttonStyle(.plain)
        } else {
            label
        }
    }
}

struct ArrowCluster: View {
    var onTap: ((String) -> Void)? = nil

    var body: some View {
        HStack(spacing: 2) {
            arrow("arrow.left", key: "left")
            arrow("arrow.up", key: "up")
            arrow("arrow.down", key: "down")
            arrow("arrow.right", key: "right")
        }
    }

    private func arrow(_ icon: String, key: String) -> some View {
        let label = Image(systemName: icon)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(LatsPalette.textDim)
            .frame(width: 24, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(LatsPalette.hairline, lineWidth: 1)
            )

        return Group {
            if let onTap {
                Button { onTap(key) } label: { label }.buttonStyle(.plain)
            } else {
                label
            }
        }
    }
}

struct EnterPill: View {
    var onTap: (() -> Void)? = nil

    var body: some View {
        let label = HStack(spacing: 4) {
            Image(systemName: "return")
                .font(.system(size: 10, weight: .semibold))
            Text("enter")
                .font(LatsFont.mono(10, weight: .semibold))
        }
        .foregroundStyle(LatsPalette.green)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(LatsPalette.green.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(LatsPalette.green.opacity(0.5), lineWidth: 1)
        )

        if let onTap {
            Button(action: onTap) { label }.buttonStyle(.plain)
        } else {
            label
        }
    }
}

// MARK: - Shortcut Grid

struct LatsShortcutGrid: View {
    let shortcuts: [LatsShortcut]
    let columns: Int
    var rows: Int? = nil
    let onTap: (LatsShortcut) -> Void
    var onJoystickMove: ((_ dx: Double, _ dy: Double) -> Void)? = nil
    var onJoystickInteractionChanged: ((Bool) -> Void)? = nil
    var joystickEnabled = false
    var joystickScale = 1.6
    var minimumControlHeight: CGFloat = 80

    @State private var recentlyPressed: String?

    var body: some View {
        if let rows, shortcuts.contains(where: { $0.col != nil && $0.row != nil }) {
            positionedGrid(rows: rows)
        } else {
            let cols = Array(repeating: GridItem(.flexible(), spacing: 10), count: columns)
            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(Array(shortcuts.enumerated()), id: \.element.id) { idx, shortcut in
                    control(for: shortcut, index: idx + 1)
                        .frame(minHeight: shortcut.controlKind == .joystick ? max(150, minimumControlHeight) : minimumControlHeight)
                }
            }
        }
    }

    private func positionedGrid(rows: Int) -> some View {
        let rowHeight: CGFloat = 96
        let spacing: CGFloat = 10
        let totalHeight = CGFloat(rows) * rowHeight + CGFloat(max(0, rows - 1)) * spacing
        return GeometryReader { proxy in
            let cellWidth = (proxy.size.width - CGFloat(max(0, columns - 1)) * spacing) / CGFloat(max(1, columns))
            ZStack(alignment: .topLeading) {
                ForEach(Array(shortcuts.enumerated()), id: \.element.id) { idx, shortcut in
                    let col = shortcut.col ?? (idx % max(1, columns))
                    let row = shortcut.row ?? (idx / max(1, columns))
                    let colSpan = min(max(1, shortcut.colSpan ?? 1), max(1, columns - col))
                    let rowSpan = min(max(1, shortcut.rowSpan ?? 1), max(1, rows - row))
                    control(for: shortcut, index: idx + 1)
                        .frame(
                            width: CGFloat(colSpan) * cellWidth + CGFloat(colSpan - 1) * spacing,
                            height: CGFloat(rowSpan) * rowHeight + CGFloat(rowSpan - 1) * spacing
                        )
                        .offset(
                            x: CGFloat(col) * (cellWidth + spacing),
                            y: CGFloat(row) * (rowHeight + spacing)
                        )
                }
            }
        }
        .frame(height: totalHeight)
    }

    @ViewBuilder
    private func control(for shortcut: LatsShortcut, index: Int) -> some View {
        if shortcut.controlKind == .joystick {
            LatsJoystickControl(
                shortcut: shortcut,
                isEnabled: joystickEnabled && shortcut.isEnabled,
                pointerScale: joystickScale,
                onMove: onJoystickMove,
                onInteractionChanged: onJoystickInteractionChanged
            )
        } else {
            LatsShortcutTile(
                shortcut: shortcut,
                index: index,
                isRecent: recentlyPressed == shortcut.id
            ) {
                onTap(shortcut)
                withAnimation { recentlyPressed = shortcut.id }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    if recentlyPressed == shortcut.id {
                        withAnimation { recentlyPressed = nil }
                    }
                }
            }
        }
    }
}

struct LatsJoystickControl: View {
    let shortcut: LatsShortcut
    let isEnabled: Bool
    let pointerScale: Double
    let onMove: ((_ dx: Double, _ dy: Double) -> Void)?
    let onInteractionChanged: ((Bool) -> Void)?

    @State private var knobOffset: CGSize = .zero
    @State private var driveTimer: Timer?

    var body: some View {
        GeometryReader { proxy in
            let diameter = max(54, min(proxy.size.width, proxy.size.height) * 0.72)
            let knobDiameter = max(30, diameter * 0.38)
            let radius = max(1, (diameter - knobDiameter) * 0.5)

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.22))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(LatsPalette.hairline2, lineWidth: 1))

                VStack(spacing: 3) {
                    Text(shortcut.label)
                        .font(LatsFont.ui(12, weight: .semibold))
                        .foregroundStyle(LatsPalette.text)
                    Text(isEnabled ? "pointer · hold to steer" : "enable trackpad on Mac")
                        .font(LatsFont.mono(9))
                        .foregroundStyle(isEnabled ? LatsPalette.textFaint : LatsPalette.amber)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(12)

                ZStack {
                    Circle()
                        .fill(shortcut.tint.color.opacity(0.07))
                        .overlay(Circle().stroke(shortcut.tint.color.opacity(0.30), lineWidth: 1))
                    Circle()
                        .stroke(LatsPalette.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        .padding(diameter * 0.22)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [shortcut.tint.color, shortcut.tint.color.opacity(0.62), Color.black.opacity(0.88)],
                                center: .topLeading,
                                startRadius: 1,
                                endRadius: knobDiameter * 0.62
                            )
                        )
                        .overlay(Circle().stroke(shortcut.tint.color.opacity(0.58), lineWidth: 1))
                        .shadow(color: .black.opacity(0.7), radius: 8, y: 5)
                        .frame(width: knobDiameter, height: knobDiameter)
                        .offset(knobOffset)
                }
                .frame(width: diameter, height: diameter)
                .opacity(isEnabled ? 1 : 0.45)
                .highPriorityGesture(joystickGesture(radius: radius))
            }
        }
        .onDisappear(perform: stopDriving)
    }

    private func joystickGesture(radius: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isEnabled else { return }
                let length = hypot(value.translation.width, value.translation.height)
                let scale = length > radius ? radius / length : 1
                knobOffset = CGSize(
                    width: value.translation.width * scale,
                    height: value.translation.height * scale
                )
                startDriving(radius: radius)
            }
            .onEnded { _ in
                stopDriving()
                withAnimation(.spring(response: 0.24, dampingFraction: 0.72)) {
                    knobOffset = .zero
                }
            }
    }

    private func startDriving(radius: CGFloat) {
        guard driveTimer == nil else { return }
        onInteractionChanged?(true)
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            let x = Double(knobOffset.width / radius)
            let y = Double(knobOffset.height / radius)
            let magnitude = min(1, hypot(x, y))
            guard magnitude > 0.08 else { return }
            let speed = pow((magnitude - 0.08) / 0.92, 1.35) * 8.0 * pointerScale
            onMove?(x / magnitude * speed, y / magnitude * speed)
        }
        RunLoop.main.add(timer, forMode: .common)
        driveTimer = timer
    }

    private func stopDriving() {
        let wasDriving = driveTimer != nil
        driveTimer?.invalidate()
        driveTimer = nil
        if wasDriving { onInteractionChanged?(false) }
    }
}

struct LatsShortcutTile: View {
    let shortcut: LatsShortcut
    let index: Int
    let isRecent: Bool
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    iconBadge
                    Spacer()
                    Text(shortcut.hint)
                        .font(LatsFont.mono(9))
                        .tracking(0.8)
                        .foregroundStyle(LatsPalette.textFaint)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 2) {
                    Text(shortcut.label)
                        .font(LatsFont.mono(12, weight: .medium))
                        .foregroundStyle(LatsPalette.text)
                    Text("act.\(String(format: "%02d", index)) · \(shortcut.category.rawValue)")
                        .font(LatsFont.mono(9))
                        .tracking(0.5)
                        .foregroundStyle(LatsPalette.textFaint)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            .background(tileBackground)
            .overlay(tileBorder)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(isPressed ? 0.035 : 0.065))
                    .frame(height: 1)
                    .padding(.horizontal, 7)
            }
            .overlay(alignment: .topTrailing) {
                if isRecent {
                    Circle()
                        .fill(shortcut.tint.color)
                        .frame(width: 6, height: 6)
                        .padding(8)
                        .shadow(color: shortcut.tint.color, radius: 4)
                }
            }
            .scaleEffect(isPressed ? 0.985 : 1.0)
            .offset(y: isPressed ? 1 : 0)
            .shadow(
                color: Color.black.opacity(isPressed ? 0.28 : 0.62),
                radius: isPressed ? 2 : 5,
                x: 0,
                y: isPressed ? 1 : 3
            )
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, perform: {}, onPressingChanged: { pressing in
            withAnimation(.easeOut(duration: 0.08)) { isPressed = pressing }
        })
    }

    private var iconBadge: some View {
        Image(systemName: shortcut.icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(shortcut.tint.color)
            .frame(width: 25, height: 25)
            .background(
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [shortcut.tint.color.opacity(0.22), Color.black.opacity(0.34)],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 18
                        )
                    )
            )
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: shortcut.tint.color.opacity(0.16), radius: 4)
    }

    @ViewBuilder
    private var tileBackground: some View {
        let base = RoundedRectangle(cornerRadius: 7)
        if isPressed {
            base.fill(
                LinearGradient(
                    colors: [LatsPalette.surface, Color.black.opacity(0.34)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        } else if isRecent {
            base.fill(shortcut.tint.color.opacity(0.12).blendMode(.plusLighter))
                .background(base.fill(LatsPalette.surface))
        } else {
            base.fill(
                LinearGradient(
                    colors: [LatsPalette.surface2.opacity(0.74), LatsPalette.surface, Color.black.opacity(0.20)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }

    private var tileBorder: some View {
        RoundedRectangle(cornerRadius: 7)
            .stroke(
                isRecent
                    ? AnyShapeStyle(shortcut.tint.color)
                    : AnyShapeStyle(
                        LinearGradient(
                            colors: [Color.white.opacity(0.11), Color.white.opacity(0.035)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    ),
                lineWidth: 1
            )
            .shadow(color: isRecent ? shortcut.tint.color.opacity(0.14) : .clear, radius: 3)
    }
}

// MARK: - Cursor-style Status Bar

struct LatsStatusBar: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let mode: CockpitMode
    let recTime: Double
    let telemetry: LatsTelemetry
    let space: Int
    let spaceCount: Int
    let spaceName: String?
    let hostLabel: String
    let onModeTap: () -> Void
    let onSpaceTap: () -> Void
    let onPaletteTap: () -> Void
    let onSwitcherTap: () -> Void

    private var modeLabel: String {
        switch mode {
        case .idle: return "READY"
        case .rec: return "LISTENING"
        case .replay: return "CONFIRMED"
        case .agent: return "AGENT"
        }
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                compactBar
            } else {
                regularBar
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, horizontalSizeClass == .compact ? 4 : 14)
        .padding(.bottom, 4)
        .background {
            if #available(iOS 26.0, *) {
                Color.clear
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 0))
            } else {
                Color.black.opacity(0.32)
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    private var compactBar: some View {
        HStack(spacing: 8) {
            Button(action: onModeTap) {
                HStack(spacing: 6) {
                    Image(systemName: "mic.fill")
                    Text(modeLabel)
                        .font(LatsFont.mono(9, weight: .bold))
                        .tracking(0.8)
                }
                .foregroundStyle(mode.color)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 6).fill(mode.color.opacity(0.16)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(mode.color.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(shortHostLabel)
                    .font(LatsFont.mono(9, weight: .semibold))
                    .foregroundStyle(LatsPalette.green)
                    .lineLimit(1)
                Text("space \(space + 1)/\(spaceCount)")
                    .font(LatsFont.mono(8))
                    .foregroundStyle(LatsPalette.textFaint)
            }

            Spacer(minLength: 0)

            Button(action: onSwitcherTap) {
                HStack(spacing: 5) {
                    Image(systemName: "square.grid.2x2.fill")
                    Text("DECKS")
                        .font(LatsFont.mono(9, weight: .bold))
                }
                .foregroundStyle(LatsPalette.text)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.055)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(LatsPalette.hairline2, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
    }

    private var regularBar: some View {
        HStack(spacing: 0) {
            modePill
            StatusItem(icon: "mic", label: "hold·space", tint: LatsPalette.text, onTap: onModeTap)
            StatusItem(icon: "laptopcomputer.and.iphone", label: "\(shortHostLabel) ↔ deck", tint: LatsPalette.green)
            StatusItem(label: "◉ \(telemetry.windows)w")
            StatusItem(label: "▢ \(space + 1)/\(spaceCount)", onTap: onSpaceTap)
            StatusItem(label: "cpu \(Int(telemetry.cpu))%", tint: telemetry.cpu > 70 ? LatsPalette.amber : LatsPalette.textDim)
            StatusItem(label: "mem \(Int(telemetry.mem))%", tint: telemetry.mem > 80 ? LatsPalette.amber : LatsPalette.textDim)
            StatusItem(label: "\(Int(telemetry.therm))°", tint: telemetry.therm > 65 ? LatsPalette.amber : LatsPalette.textDim)

            Spacer(minLength: 0)

            StatusItem(icon: "sparkles", label: "agent · \(mode == .agent ? "thinking" : "ready")", tint: mode == .agent ? LatsPalette.violet : LatsPalette.textDim)
            StatusItem(label: "claude", tint: LatsPalette.violet)
            StatusItem(label: spaceName ?? "main", tint: LatsPalette.amber)
            StatusItem(label: "●3", tint: LatsPalette.amber)
            StatusItem(label: "⌘K", tint: LatsPalette.text, onTap: onPaletteTap)
            StatusItem(label: "⌘⇧P", tint: LatsPalette.text, onTap: onSwitcherTap)
        }
    }

    private var modePill: some View {
        Button(action: onModeTap) {
            HStack(spacing: 5) {
                Circle()
                    .fill(mode.color)
                    .frame(width: 5, height: 5)
                Text(modeLabel)
                    .font(LatsFont.mono(9, weight: .semibold))
                    .tracking(1)
                if mode == .rec {
                    Text("· \(recTime, specifier: "%.1f")s")
                        .font(LatsFont.mono(9))
                }
            }
            .foregroundStyle(mode.color)
            .padding(.horizontal, 8)
            .frame(height: 12)
            .background(mode.color.opacity(0.24))
            .overlay(alignment: .trailing) {
                Rectangle().fill(LatsPalette.hairline).frame(width: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var shortHostLabel: String {
        hostLabel
            .replacingOccurrences(of: ".local", with: "")
            .replacingOccurrences(of: ".lan", with: "")
    }
}

struct StatusItem: View {
    var icon: String? = nil
    let label: String
    var tint: Color = LatsPalette.textDim
    var onTap: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        let content = HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 9)) }
            Text(label)
                .font(LatsFont.mono(9))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .frame(height: 12)
        .background(isHovered && onTap != nil ? Color.white.opacity(0.06) : .clear)
        .overlay(alignment: .trailing) {
            Rectangle().fill(LatsPalette.hairline).frame(width: 1)
        }

        if let onTap {
            Button(action: onTap) { content }
                .buttonStyle(.plain)
                .onHover { isHovered = $0 }
        } else {
            content
        }
    }
}

// MARK: - Main Screen

struct LatsDeckScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSize

    /// Live snapshot from the Mac bridge. When nil, the screen runs a self-contained
    /// mock state machine for offline preview.
    var liveSnapshot: DeckRuntimeSnapshot?

    /// Active bridge label supplied by the connection store.
    var connectionLabel: String?

    /// When connected, tile presses and keyboard sends route through this callback.
    var onAction: ((_ actionID: String, _ payload: [String: DeckValue], _ label: String?) -> Void)?

    /// When connected, the full-screen cockpit surface forwards pointer events here.
    var onTrackpadEvent: ((_ event: DeckTrackpadEvent, _ dx: Double, _ dy: Double) -> Void)?

    /// Which deck to render. Defaults to "command".
    var deckID: String = "command"

    // ── Mock-mode state (only used when liveSnapshot is nil) ──
    @State private var selectedDeckID: String?
    @State private var mockMode: CockpitMode = .idle
    @State private var mockRecTime: Double = 0
    @State private var mockAgentProgress: Double = 80
    @State private var mockReplayMessage = "Move all terminals to the left, Chrome to the right."
    @State private var mockTelemetry = LatsTelemetry()
    @State private var mockStage: [[LatsWindow]] = CommandDeck.stage
    @State private var mockSpace: Int = 0
    @State private var mockTranscript: [String] = CommandDeck.transcript

    @State private var recTimer: Timer?
    @State private var agentTimer: Timer?
    @State private var modeAutoReturn: DispatchWorkItem?
    @State private var isUsingJoystick = false
    @State private var joystickSwipeSuppressedUntil = Date.distantPast

    private var isConnected: Bool { liveSnapshot != nil }

    private var effectiveDeckID: String {
        selectedDeckID ?? deckID
    }

    private var gridColumns: Int {
        if hSize == .compact { return 2 }
        if let columns = activeCockpitPage()?.columns {
            if activeCockpitPage()?.rows != nil { return columns }
            return columns
        }
        return 6
    }

    // ── Resolved values: prefer live, fall back to mock ──

    private var mode: CockpitMode {
        if let m = liveSnapshot?.cockpitMode?.mode { return CockpitMode(from: m) }
        return mockMode
    }

    private var recTime: Double {
        liveSnapshot?.cockpitMode?.elapsedSeconds ?? mockRecTime
    }

    private var agentProgress: Double {
        // Live agentProgress is 0...1; legacy mock visual uses 0...264 (stroke dasharray)
        if let p = liveSnapshot?.cockpitMode?.agentProgress { return p * 264 }
        return mockAgentProgress
    }

    private var replayMessage: String {
        liveSnapshot?.cockpitMode?.replayMessage ?? mockReplayMessage
    }

    private var replayUndoLabel: String {
        guard let expiresAt = liveSnapshot?.cockpitMode?.replayUndoExpiresAt else {
            return "undo within 5s"
        }
        let seconds = max(0, Int(ceil(expiresAt.timeIntervalSinceNow)))
        return seconds > 0 ? "undo within \(seconds)s" : "undo expired"
    }

    private var agentRows: [DeckAgentPlanRow] {
        liveSnapshot?.cockpitMode?.agentRows ?? []
    }

    private var telemetry: LatsTelemetry {
        if let t = liveSnapshot?.telemetry { return LatsTelemetry(from: t) }
        return mockTelemetry
    }

    private var space: Int {
        let liveIndex = liveSnapshot?.spaces?.currentSpaceIndex
            ?? liveSnapshot?.desktop?.currentSpaceIndex
        if let liveIndex {
            return max(0, liveIndex - 1)
        }
        return mockSpace
    }

    private var spaceCount: Int {
        max(1, liveSnapshot?.spaces?.displays.first?.spaces.count ?? 6)
    }

    private var spaceName: String? {
        liveSnapshot?.spaces?.currentSpaceName
            ?? liveSnapshot?.desktop?.currentSpaceName
    }

    private var spaceDisplays: [DeckSpaceDisplay] {
        liveSnapshot?.spaces?.displays ?? []
    }

    private var transcript: [String] {
        if let lines = liveSnapshot?.voice?.transcriptLines, !lines.isEmpty {
            return Array(lines.sorted { $0.createdAt > $1.createdAt }.prefix(5).map(\.text))
        }
        if let one = liveSnapshot?.voice?.transcript, !one.isEmpty { return [one] }
        return mockTranscript
    }

    private var activityLog: [DeckActivityLogEntry] {
        liveSnapshot?.activityLog ?? []
    }

    private var hostLabel: String {
        let label = connectionLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let label, !label.isEmpty { return label }
        return isConnected ? "Mac" : "preview"
    }

    private var stage: [[LatsWindow]] {
        guard let preview = liveSnapshot?.layout?.preview else { return mockStage }
        // Bridge sends each preview window with a `displayIndex` plus a `displayCount`.
        // Bucket windows into per-display columns so the iPad mini-frames render the
        // correct windows on the correct monitor.
        let displayCount = max(preview.displayCount ?? 1, 1)
        var buckets: [[LatsWindow]] = Array(repeating: [], count: displayCount)
        for w in preview.windows {
            let idx = w.displayIndex ?? 0
            guard idx >= 0, idx < displayCount else { continue }
            buckets[idx].append(LatsWindow(
                x: w.normalizedFrame.x * 100,
                y: w.normalizedFrame.y * 100,
                w: w.normalizedFrame.w * 100,
                h: w.normalizedFrame.h * 100,
                tint: LatsTint.from(token: w.appCategoryTint),
                tag: String(w.title.prefix(4))
            ))
        }
        return buckets
    }

    private var shortcuts: [LatsShortcut] {
        if let live = liveShortcuts(), !live.isEmpty { return live }
        return CommandDeck.shortcuts
    }

    private var deckAccent: Color {
        // Pull tint from the first tile of the active cockpit page, since DeckCockpitPage
        // doesn't carry an accent token directly.
        if let tile = activeCockpitPage()?.tiles.first {
            return LatsTint.from(token: tile.accentToken).color
        }
        return CommandDeck.accent.color
    }

    private var deckName: String {
        activeCockpitPage()?.title.lowercased() ?? CommandDeck.name
    }

    private var deckNames: [String] {
        let liveNames = liveSnapshot?.cockpit?.pages
            .map { $0.title.lowercased() }
            .filter { !$0.isEmpty } ?? []
        return liveNames.isEmpty ? ["command", "dev", "media", "windows", "voice"] : liveNames
    }

    var body: some View {
        ZStack {
            LatsPalette.bgEdge.ignoresSafeArea()

            VStack(spacing: 0) {
                LatsTopChrome(
                    deckName: deckName,
                    deckNames: deckNames,
                    accent: deckAccent,
                    onSwitcher: { cycleDeck() },
                    onClose: { dismiss() }
                )

                GeometryReader { geo in
                    let isPad = geo.size.width > 700 && hSize == .regular
                    let cockpitH: CGFloat = hSize == .compact
                        ? min(250, max(210, geo.size.height * 0.30))
                        : (isPad ? max(380, geo.size.height * 0.50) : max(320, geo.size.height * 0.44))

                    VStack(spacing: 0) {
                        // Cockpit
                        ZStack {
                            LatsCockpitShell {
                                LatsTrackpadSurface(
                                    mode: mode,
                                    recTime: recTime,
                                    agentProgress: agentProgress,
                                    replayMessage: replayMessage,
                                    replayUndoLabel: replayUndoLabel,
                                    agentRows: agentRows,
                                    telemetry: telemetry,
                                    stage: stage,
                                    space: space,
                                    spaceCount: spaceCount,
                                    spaceName: spaceName,
                                    transcript: transcript,
                                    activityLog: activityLog,
                                    hostLabel: hostLabel,
                                    trackpadState: liveSnapshot?.trackpad,
                                    spaceDisplays: spaceDisplays,
                                    frontmostApp: liveSnapshot?.layout?.frontmostWindow?.appName
                                        ?? liveSnapshot?.desktop?.activeAppName,
                                    frontmostTitle: liveSnapshot?.layout?.frontmostWindow?.title,
                                    onSendKey: handleSendKey,
                                    onReplayUndo: handleReplayUndo,
                                    onTrackpadEvent: onTrackpadEvent,
                                    onSpaceTap: handleSpaceTap,
                                    onMonitorSwipe: handleMonitorSwipe
                                )
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                        .frame(height: cockpitH)
                        .background(Color.black.opacity(0.18))
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(LatsPalette.hairline).frame(height: 1)
                        }

                        // Shortcut grid (deck keys) — horizontal swipe cycles decks
                        ScrollView {
                            LatsShortcutGrid(
                                shortcuts: shortcuts,
                                columns: gridColumns,
                                rows: hSize == .compact ? nil : activeCockpitPage()?.rows,
                                onTap: handleTilePress,
                                onJoystickMove: { dx, dy in
                                    onTrackpadEvent?(.move, dx, dy)
                                },
                                onJoystickInteractionChanged: { active in
                                    isUsingJoystick = active
                                    if !active {
                                        joystickSwipeSuppressedUntil = Date().addingTimeInterval(0.25)
                                    }
                                },
                                joystickEnabled: joystickReady,
                                joystickScale: liveSnapshot?.trackpad?.pointerScale ?? 1.6
                            )
                            .padding(14)
                            .id(effectiveDeckID)
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                        }
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        // simultaneousGesture so the ScrollView's vertical scroll
                        // and the horizontal deck-cycle swipe can both recognize.
                        .simultaneousGesture(deckSwipeGesture)
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    // Anchor the bar inside the bottom safe-area inset so the
                    // chips can ride right up to the rounded corner.
                    LatsStatusBar(
                        mode: mode,
                        recTime: recTime,
                        telemetry: telemetry,
                        space: space,
                        spaceCount: spaceCount,
                        spaceName: spaceName,
                        hostLabel: hostLabel,
                        onModeTap: { toggleVoice() },
                        onSpaceTap: { if !isConnected { mockSpace = (mockSpace + 1) % 6 } },
                        onPaletteTap: {},
                        onSwitcherTap: { cycleDeck() }
                    )
                }
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .onChange(of: mockMode) { _, newMode in
            if !isConnected { handleModeChange(newMode) }
        }
        .onAppear {
            if !isConnected { jitterTelemetry() }
        }
    }

    // MARK: - Live snapshot helpers

    private func activeCockpitPage() -> DeckCockpitPage? {
        guard let pages = liveSnapshot?.cockpit?.pages else { return nil }
        return pages.first(where: { $0.id == effectiveDeckID }) ?? pages.first
    }

    private func liveShortcuts() -> [LatsShortcut]? {
        guard let activePage = activeCockpitPage() else { return nil }
        return activePage.tiles.map { tile in
            LatsShortcut(
                id: tile.id,
                label: tile.title,
                icon: tile.iconSystemName,
                tint: LatsTint.from(token: tile.categoryTint ?? tile.accentToken),
                category: shortcutCategory(for: tile),
                hint: tile.subtitle ?? "",
                sim: simAction(from: tile.actionID),
                actionID: tile.actionID,
                payload: tile.payload,
                controlKind: tile.controlKind,
                col: tile.col,
                row: tile.row,
                colSpan: tile.colSpan,
                rowSpan: tile.rowSpan,
                isEnabled: tile.isEnabled
            )
        }
    }

    private var joystickReady: Bool {
        guard onTrackpadEvent != nil else { return false }
        guard let trackpad = liveSnapshot?.trackpad else { return isConnected }
        return trackpad.isEnabled && trackpad.isAvailable
    }

    private func shortcutCategory(for tile: DeckCockpitTile) -> ShortcutCategory {
        let raw = [
            tile.deckID,
            tile.actionID,
            tile.title,
            tile.subtitle
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")

        if raw.contains("voice") || raw.contains("dictate") || raw.contains("rec") { return .voice }
        if raw.contains("agent") || raw.contains("claude") || raw.contains("pi") { return .agent }
        if raw.contains("window") || raw.contains("layout") || raw.contains("tile") || raw.contains("display") { return .window }
        if raw.contains("dev") || raw.contains("terminal") || raw.contains("server") { return .dev }
        return .system
    }

    private func simAction(from actionID: String?) -> SimAction {
        guard let id = actionID?.lowercased() else { return .none }
        if id.contains("voice") || id.contains("dictate") || id.contains("rec") { return .rec }
        if id.contains("agent") || id.contains("claude") || id.contains("pi") { return .agent }
        if id.contains("tile") { return .tile }
        if id.contains("move") || id.contains("monitor") { return .move }
        if id.contains("palette") || id.contains("search") { return .palette }
        return .none
    }

    // MARK: - Behaviour

    private func handleTilePress(_ shortcut: LatsShortcut) {
        if let onAction, let actionID = shortcut.actionID {
            var payload = shortcut.payload
            if actionID == "clipboard.pasteFromDevice",
               let text = UIPasteboard.general.string,
               !text.isEmpty {
                payload["text"] = .string(text)
                payload["source"] = .string("ios-pasteboard")
            }
            onAction(actionID, payload, shortcut.label)
            return
        }

        // Mock fallback
        switch shortcut.sim {
        case .rec, .voice:
            startMockRec()
            scheduleModeReturn(after: 2.4) {
                mockReplayMessage = "Move all terminals to the left, Chrome to the right."
                mockMode = .replay
                scheduleModeReturn(after: 3.0) { mockMode = .idle }
            }
        case .agent:
            mockMode = .agent
            mockAgentProgress = 20
            scheduleModeReturn(after: 9.0) {
                mockReplayMessage = "Agent moved 7 windows across 2 displays."
                mockMode = .replay
                scheduleModeReturn(after: 3.0) { mockMode = .idle }
            }
        case .tile:
            mockReplayMessage = "Tiled 4-up on display 1"
            mockMode = .replay
            scheduleModeReturn(after: 2.4) { mockMode = .idle }
        case .move:
            mockReplayMessage = "Moved windows by display target."
            mockMode = .replay
            scheduleModeReturn(after: 2.4) { mockMode = .idle }
        case .palette, .none:
            mockReplayMessage = "\(shortcut.label) fired."
            mockMode = .replay
            scheduleModeReturn(after: 1.8) { mockMode = .idle }
        }
    }

    private func handleSendKey(_ key: String, _ modifiers: [String]) {
        if let onAction {
            let payload: [String: DeckValue] = [
                "key": .string(key),
                "modifiers": .array(modifiers.map { .string($0) })
            ]
            let chord = (modifiers + [key.uppercased()]).joined()
            onAction("keys.send", payload, chord)
        }
    }

    private func handleReplayUndo() {
        guard mode == .replay, replayUndoLabel != "undo expired" else { return }
        if let onAction {
            let actionID = liveSnapshot?.cockpitMode?.replayUndoActionID ?? "history.undoLast"
            onAction(actionID, [:], "Undo last action")
        } else {
            mockReplayMessage = "Undid the last action."
            mockMode = .replay
            scheduleModeReturn(after: 1.6) { mockMode = .idle }
        }
    }

    private func handleSpaceTap(_ index: Int) {
        if let onAction {
            // Mac-side gap: bridge needs a "spaces.focusIndex" handler to honor this.
            onAction("spaces.focusIndex", ["index": .int(index)], "Switch to space \(index + 1)")
        } else {
            mockSpace = index
        }
    }

    /// Swipe a monitor to the next/previous space. Falls back to Ctrl+Left/Right via
    /// keys.send when the bridge has no per-display swipe action.
    private func handleMonitorSwipe(_ display: Int, _ direction: Int) {
        if let onAction {
            let key = direction > 0 ? "right" : "left"
            let label = direction > 0 ? "Next space" : "Previous space"
            onAction(
                "keys.send",
                ["key": .string(key), "modifiers": .array([.string("⌃")])],
                label
            )
        } else {
            mockSpace = max(0, min(spaceCount - 1, mockSpace + direction))
        }
    }

    /// Horizontal swipe on the shortcut grid cycles decks.
    /// Swipe left → next deck, swipe right → previous deck.
    private var deckSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                guard !isUsingJoystick, Date() >= joystickSwipeSuppressedUntil else { return }
                let dx = value.translation.width
                let dy = value.translation.height
                // Require dominantly-horizontal motion so vertical scrolls don't
                // accidentally trigger a deck change.
                guard abs(dx) > 60, abs(dx) > abs(dy) * 2.0 else { return }
                cycleDeck(forward: dx < 0)
            }
    }

    private func cycleDeck(forward: Bool = true) {
        let liveIDs = liveSnapshot?.cockpit?.pages.map(\.id).filter { !$0.isEmpty } ?? []
        let ids = liveIDs.isEmpty ? ["command", "dev", "media", "windows", "voice"] : liveIDs
        guard !ids.isEmpty else { return }
        guard let currentIndex = ids.firstIndex(of: effectiveDeckID) else {
            withAnimation(.easeOut(duration: 0.22)) { selectedDeckID = ids.first }
            return
        }
        let nextIndex = forward
            ? (currentIndex + 1) % ids.count
            : (currentIndex - 1 + ids.count) % ids.count
        withAnimation(.easeOut(duration: 0.22)) { selectedDeckID = ids[nextIndex] }
    }

    private func toggleVoice() {
        if let onAction {
            let actionID = mode == .rec ? "voice.cancel" : "voice.toggle"
            onAction(actionID, [:], nil)
            return
        }
        if mockMode == .rec {
            mockMode = .replay
            scheduleModeReturn(after: 1.8) { mockMode = .idle }
        } else {
            startMockRec()
        }
    }

    private func startMockRec() {
        mockRecTime = 0
        mockMode = .rec
    }

    private func scheduleModeReturn(after seconds: Double, action: @escaping () -> Void) {
        modeAutoReturn?.cancel()
        let work = DispatchWorkItem { action() }
        modeAutoReturn = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func handleModeChange(_ newMode: CockpitMode) {
        recTimer?.invalidate(); recTimer = nil
        agentTimer?.invalidate(); agentTimer = nil

        if newMode == .rec {
            mockRecTime = 0
            recTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                Task { @MainActor in mockRecTime += 0.1 }
            }
        }
        if newMode == .agent {
            agentTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { _ in
                Task { @MainActor in mockAgentProgress = min(264, mockAgentProgress + 4) }
            }
        }
    }

    private func jitterTelemetry() {
        Timer.scheduledTimer(withTimeInterval: 1.4, repeats: true) { _ in
            Task { @MainActor in
                mockTelemetry.cpu = max(8, min(90, mockTelemetry.cpu + .random(in: -4...4)))
                mockTelemetry.mem = max(40, min(85, mockTelemetry.mem + .random(in: -2...2)))
                mockTelemetry.gpu = max(5, min(60, mockTelemetry.gpu + .random(in: -5...5)))
                mockTelemetry.therm = max(42, min(72, mockTelemetry.therm + .random(in: -0.75...0.75)))
            }
        }
    }
}

// MARK: - Fleet Deck

/// Multi-Mac cockpit. Landscape renders up to four independent decks beside
/// one another; portrait keeps the same sessions in a swipeable single-deck
/// pager. Each child observes its own `DeckStore`, preserving host ownership
/// all the way from visible controls to bridge requests.
struct FleetDeckScreen: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var primaryStore: DeckStore
    @ObservedObject var fleetStore: DeckFleetStore
    var initialMachineID: String?
    var previewStores: [DeckStore]? = nil

    @State private var selectedSessionID: UUID?

    private var stores: [DeckStore] {
        previewStores ?? fleetStore.stores(including: primaryStore)
    }

    var body: some View {
        Group {
            if stores.count == 1, let store = stores.first, store.snapshot != nil {
                singleDeck(store)
            } else {
                fleetLayout
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .onAppear {
            if previewStores == nil {
                fleetStore.synchronize(with: primaryStore)
                fleetStore.setUIPriority(.fast, primaryStore: primaryStore)
            }
            selectInitialSessionIfNeeded()
        }
        .onChange(of: primaryStore.discoveredBridges) { _, _ in
            guard previewStores == nil else { return }
            fleetStore.synchronize(with: primaryStore)
            selectInitialSessionIfNeeded()
        }
        .onChange(of: fleetStore.secondaryStores.map(\.sessionID)) { _, _ in
            selectInitialSessionIfNeeded()
        }
        .onDisappear {
            if previewStores == nil {
                fleetStore.setUIPriority(.ambient, primaryStore: primaryStore)
            }
        }
    }

    @ViewBuilder
    private func singleDeck(_ store: DeckStore) -> some View {
        LatsDeckScreen(
            liveSnapshot: store.snapshot,
            connectionLabel: store.connectionLabel,
            onAction: { actionID, payload, label in
                store.perform(actionID: actionID, pageID: "cockpit", payload: payload, label: label)
            },
            onTrackpadEvent: { event, dx, dy in
                store.sendTrackpad(event: event, dx: dx, dy: dy)
            }
        )
    }

    private var fleetLayout: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height

            LatsBackground(grid: true) {
                VStack(spacing: 0) {
                    fleetTopBar(isLandscape: isLandscape)
                    if stores.isEmpty {
                        fleetEmptyState
                    } else if isLandscape {
                        landscapeDecks(size: proxy.size)
                    } else {
                        portraitDecks
                    }
                }
            }
        }
    }

    private func fleetTopBar(isLandscape: Bool) -> some View {
        LatsTopBar(
            product: "LATS",
            section: "DECK",
            trailing: AnyView(
                HStack(spacing: 8) {
                    LatsBadge(
                        text: isLandscape ? "\(stores.count)-UP" : "SWIPE",
                        tint: LatsPalette.green,
                        dot: true
                    )
                    Text("\(stores.count) MAC\(stores.count == 1 ? "" : "S")")
                        .font(LatsFont.mono(9, weight: .semibold))
                        .foregroundStyle(LatsPalette.textFaint)
                        .tracking(0.8)
                }
            ),
            onClose: { dismiss() }
        )
    }

    private func landscapeDecks(size: CGSize) -> some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(stores.enumerated()), id: \.element.sessionID) { index, store in
                        FleetLanePicker(
                            store: store,
                            laneNumber: index + 1,
                            accent: fleetAccent(for: index),
                            isSelected: selectedStore?.sessionID == store.sessionID,
                            onSelect: {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    selectedSessionID = store.sessionID
                                }
                            }
                        )
                        .frame(width: laneWidth(for: size.width))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
            }
            .frame(height: min(255, max(225, size.height * 0.25)))

            FleetLaneFader(
                laneCount: stores.count,
                selectedIndex: selectedLaneIndex,
                accents: stores.indices.map(fleetAccent(for:)),
                onSelect: { index in
                    guard stores.indices.contains(index) else { return }
                    withAnimation(.easeOut(duration: 0.16)) {
                        selectedSessionID = stores[index].sessionID
                    }
                }
            )
            .frame(height: 58)
            .padding(.horizontal, 12)

            if let selectedStore,
               let selectedIndex = stores.firstIndex(where: { $0.sessionID == selectedStore.sessionID }) {
                FleetSharedDeck(
                    store: selectedStore,
                    accent: fleetAccent(for: selectedIndex),
                    laneNumber: selectedIndex + 1
                )
                .id(selectedStore.sessionID)
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .transition(.opacity)
            }
        }
    }

    private var selectedStore: DeckStore? {
        if let selectedSessionID,
           let selected = stores.first(where: { $0.sessionID == selectedSessionID }) {
            return selected
        }
        return stores.first
    }

    private var selectedLaneIndex: Int {
        guard let selectedStore else { return 0 }
        return stores.firstIndex(where: { $0.sessionID == selectedStore.sessionID }) ?? 0
    }

    private func laneWidth(for availableWidth: CGFloat) -> CGFloat {
        let visibleCount = min(max(stores.count, 1), 4)
        let totalSpacing = CGFloat(max(0, visibleCount - 1)) * 10
        let fitted = (availableWidth - 24 - totalSpacing) / CGFloat(visibleCount)
        return max(245, fitted)
    }

    private var portraitDecks: some View {
        TabView(selection: selectedSessionBinding) {
            ForEach(Array(stores.enumerated()), id: \.element.sessionID) { index, store in
                FleetMachineDeck(store: store, accentOverride: fleetAccent(for: index))
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 28)
                    .tag(store.sessionID)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
    }

    private var selectedSessionBinding: Binding<UUID> {
        Binding(
            get: { selectedSessionID ?? stores.first?.sessionID ?? primaryStore.sessionID },
            set: { selectedSessionID = $0 }
        )
    }

    private var fleetEmptyState: some View {
        LatsEmptyState(
            title: "No reachable Macs",
            subtitle: "Open Lattices on a paired Mac to add its deck.",
            icon: "laptopcomputer.slash"
        )
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func selectInitialSessionIfNeeded() {
        if let selectedSessionID,
           stores.contains(where: { $0.sessionID == selectedSessionID }) {
            return
        }

        if let initialMachineID,
           let requested = stores.first(where: { $0.activeEndpoint?.id == initialMachineID }) {
            selectedSessionID = requested.sessionID
        } else {
            selectedSessionID = stores.first?.sessionID
        }
    }

    private func fleetAccent(for index: Int) -> Color {
        let palette = [
            LatsPalette.teal,
            LatsPalette.violet,
            LatsPalette.green,
            LatsPalette.amber,
            LatsPalette.blue,
            LatsPalette.pink
        ]
        return palette[index % palette.count]
    }
}

#if DEBUG
struct FleetDeckPreviewHost: View {
    @StateObject private var primaryStore: DeckStore
    @StateObject private var fleetStore = DeckFleetStore()
    private let previewStores: [DeckStore]

    init(machineCount: Int = 4) {
        let names = ["Arach MacBook Pro", "Studio", "Mac mini", "Build Mac"]
        let stores = (0..<max(1, min(machineCount, names.count))).map {
            DeckStore.fleetPreview(name: names[$0], index: $0)
        }
        previewStores = stores
        _primaryStore = StateObject(wrappedValue: stores[0])
    }

    var body: some View {
        FleetDeckScreen(
            primaryStore: primaryStore,
            fleetStore: fleetStore,
            previewStores: previewStores
        )
    }
}
#endif

private struct FleetLaneFader: View {
    let laneCount: Int
    let selectedIndex: Int
    let accents: [Color]
    let onSelect: (Int) -> Void

    private var selectedAccent: Color {
        accents.indices.contains(selectedIndex) ? accents[selectedIndex] : LatsPalette.teal
    }

    var body: some View {
        GeometryReader { proxy in
            let count = max(1, laneCount)
            let inset: CGFloat = 28
            let travel = max(1, proxy.size.width - inset * 2)
            let step = count > 1 ? travel / CGFloat(count - 1) : 0
            let knobX = inset + CGFloat(min(max(0, selectedIndex), count - 1)) * step

            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(LatsPalette.surface.opacity(0.72))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(LatsPalette.hairline2, lineWidth: 1))

                Capsule()
                    .fill(Color.black.opacity(0.72))
                    .frame(height: 7)
                    .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
                    .padding(.horizontal, inset)

                HStack {
                    Text("CHANNEL ROUTE")
                        .font(LatsFont.mono(7, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(LatsPalette.textFaint)
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(selectedAccent)
                            .frame(width: 7, height: 7)
                            .shadow(color: selectedAccent.opacity(0.9), radius: 6)
                        Text("DECK OUT · CH \(String(format: "%02d", selectedIndex + 1))")
                            .font(LatsFont.mono(7, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(selectedAccent)
                    }
                }
                .padding(.horizontal, 12)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 7)

                ForEach(0..<count, id: \.self) { index in
                    let x = inset + CGFloat(index) * step
                    VStack(spacing: 3) {
                        Circle()
                            .fill(index == selectedIndex ? selectedAccent : Color.white.opacity(0.12))
                            .frame(width: index == selectedIndex ? 7 : 5, height: index == selectedIndex ? 7 : 5)
                        Text("\(index + 1)")
                            .font(LatsFont.mono(6, weight: .semibold))
                            .foregroundStyle(index == selectedIndex ? selectedAccent : LatsPalette.textFaint)
                    }
                    .position(x: x, y: 37)
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.20), LatsPalette.surface2, Color.black.opacity(0.55)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(selectedAccent.opacity(0.70), lineWidth: 1)
                    Rectangle()
                        .fill(selectedAccent.opacity(0.88))
                        .frame(width: 2, height: 18)
                }
                .frame(width: 34, height: 24)
                .shadow(color: Color.black.opacity(0.8), radius: 5, y: 3)
                .shadow(color: selectedAccent.opacity(0.18), radius: 7)
                .position(x: knobX, y: 32)
            }
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        guard count > 1 else { return }
                        let normalized = min(1, max(0, (value.location.x - inset) / travel))
                        let index = Int((normalized * CGFloat(count - 1)).rounded())
                        if index != selectedIndex { onSelect(index) }
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Computer channel fader")
            .accessibilityValue("Channel \(selectedIndex + 1) of \(count)")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: onSelect(min(count - 1, selectedIndex + 1))
                case .decrement: onSelect(max(0, selectedIndex - 1))
                @unknown default: break
                }
            }
        }
    }
}

private struct FleetAgentTapeEntry: Identifiable {
    let id: String
    let label: String
    let text: String
    let tint: Color
    let isLive: Bool
}

private struct FleetLanePicker: View {
    @ObservedObject var store: DeckStore
    let laneNumber: Int
    let accent: Color
    let isSelected: Bool
    let onSelect: () -> Void

    private var statusColor: Color {
        if store.errorMessage != nil { return LatsPalette.red }
        if store.snapshot != nil { return LatsPalette.green }
        return store.isLoading ? LatsPalette.amber : LatsPalette.textFaint
    }

    private var activeApp: String {
        store.snapshot?.layout?.frontmostWindow?.appName
            ?? store.snapshot?.desktop?.activeAppName
            ?? "No active app"
    }

    private var activeWindow: String {
        store.snapshot?.layout?.frontmostWindow?.title
            ?? store.snapshot?.desktop?.currentSpaceName
            ?? "Waiting for desktop state"
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 0) {
                laneHeader
                LatsHairlineDivider()
                contextStrip
                LatsHairlineDivider()
                agentTape
                LatsHairlineDivider()
                routeFooter
            }
            .background(
                LinearGradient(
                    colors: [
                        isSelected ? accent.opacity(0.075) : Color.white.opacity(0.018),
                        LatsPalette.bg.opacity(0.98)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isSelected ? accent.opacity(0.62) : LatsPalette.hairline2, lineWidth: 1)
            )
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(isSelected ? accent.opacity(0.82) : Color.white.opacity(0.055))
                    .frame(height: isSelected ? 2 : 1)
                    .padding(.horizontal, 7)
            }
            .shadow(
                color: isSelected ? accent.opacity(0.10) : Color.black.opacity(0.48),
                radius: isSelected ? 9 : 5,
                x: 0,
                y: 4
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Route lane \(laneNumber), \(store.connectionLabel), to common deck")
    }

    private var laneHeader: some View {
        HStack(spacing: 8) {
            Text("CH \(String(format: "%02d", laneNumber))")
                .font(LatsFont.mono(8, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(isSelected ? accent : LatsPalette.textFaint)

            Rectangle()
                .fill(LatsPalette.hairline2)
                .frame(width: 1, height: 15)

            Image(systemName: machineIcon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? accent : LatsPalette.textDim)

            Text(store.connectionLabel)
                .font(LatsFont.mono(10, weight: .semibold))
                .foregroundStyle(LatsPalette.text)
                .lineLimit(1)

            Spacer(minLength: 4)

            Circle().fill(statusColor).frame(width: 5, height: 5)
            Text(store.snapshot == nil ? "LINK" : "LIVE")
                .font(LatsFont.mono(7, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 11)
        .frame(height: 42)
    }

    private var contextStrip: some View {
        ZStack {
            LatsPalette.bgEdge
            LatsGridBackground().opacity(isSelected ? 0.48 : 0.30)

            HStack(spacing: 9) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CONTEXT")
                        .font(LatsFont.mono(7, weight: .bold))
                        .tracking(1.3)
                        .foregroundStyle(isSelected ? accent : LatsPalette.textFaint)
                    Text(activeApp)
                        .font(LatsFont.mono(11, weight: .semibold))
                        .foregroundStyle(LatsPalette.text)
                        .lineLimit(1)
                    Text(activeWindow)
                        .font(LatsFont.mono(7))
                        .foregroundStyle(LatsPalette.textDim)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 9) {
                    laneMetric("CPU", value: percent(store.snapshot?.telemetry?.cpuLoadPercent))
                    laneMetric("MEM", value: percent(store.snapshot?.telemetry?.memoryUsedPercent))
                    laneMetric("WIN", value: String(store.snapshot?.telemetry?.windowCount ?? 0))
                }
            }
            .padding(12)
        }
        .frame(height: 66)
        .contentShape(Rectangle())
    }

    private var routeFooter: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(isSelected ? accent : LatsPalette.textFaint)
                .frame(width: 5, height: 5)
                .shadow(color: isSelected ? accent.opacity(0.55) : .clear, radius: 4)
            Text(isSelected ? "ROUTED TO DECK" : "TAP TO ROUTE")
                .font(LatsFont.mono(8, weight: .bold))
                .tracking(1)
                .foregroundStyle(isSelected ? accent : LatsPalette.textFaint)
            Spacer()
            Text(isSelected ? "ON DECK" : "STANDBY")
                .font(LatsFont.mono(7, weight: .semibold))
                .foregroundStyle(isSelected ? LatsPalette.text : LatsPalette.textFaint)
        }
        .padding(.horizontal, 11)
        .frame(height: 34)
        .background(Color.black.opacity(isSelected ? 0.26 : 0.16))
    }

    private var agentTape: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("AGENT TAPE")
                    .font(LatsFont.mono(7, weight: .bold))
                    .tracking(1.25)
                    .foregroundStyle(LatsPalette.violet.opacity(0.82))
                Spacer()
                if agentEntries.contains(where: \.isLive) {
                    Circle()
                        .fill(LatsPalette.violet)
                        .frame(width: 5, height: 5)
                        .shadow(color: LatsPalette.violet.opacity(0.8), radius: 4)
                    Text("ACTIVE")
                        .font(LatsFont.mono(6, weight: .bold))
                        .foregroundStyle(LatsPalette.violet)
                } else {
                    Text("IDLE")
                        .font(LatsFont.mono(6, weight: .bold))
                        .foregroundStyle(LatsPalette.textFaint)
                }
            }
            .padding(.bottom, 5)

            if agentEntries.isEmpty {
                Text("no agents on this channel")
                    .font(LatsFont.mono(7))
                    .foregroundStyle(LatsPalette.textFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(agentEntries.prefix(3))) { entry in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(entry.tint)
                            .frame(width: 5, height: 5)
                            .shadow(color: entry.isLive ? entry.tint.opacity(0.65) : .clear, radius: 3)
                        Text(entry.label.uppercased())
                            .font(LatsFont.mono(6, weight: .bold))
                            .tracking(0.55)
                            .foregroundStyle(entry.tint.opacity(0.88))
                            .frame(width: 42, alignment: .leading)
                        Text(entry.text)
                            .font(LatsFont.mono(7))
                            .foregroundStyle(entry.isLive ? LatsPalette.textDim : LatsPalette.textFaint)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(height: 15)
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.black.opacity(0.20))
    }

    private var agentEntries: [FleetAgentTapeEntry] {
        let activityEntries = (store.snapshot?.activityLog ?? [])
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(3)
            .map { entry in
                FleetAgentTapeEntry(
                    id: entry.id,
                    label: entry.tag,
                    text: entry.text,
                    tint: LatsTint.from(token: entry.tint).color,
                    isLive: entry.createdAt.timeIntervalSinceNow > -120
                )
            }
        if !activityEntries.isEmpty { return Array(activityEntries) }

        return (store.snapshot?.cockpitMode?.agentRows ?? []).map { row in
            let tint: Color
            let live: Bool
            switch row.state {
            case .done:
                tint = LatsPalette.green
                live = false
            case .live:
                tint = LatsPalette.violet
                live = true
            case .next:
                tint = LatsPalette.textFaint
                live = false
            }
            return FleetAgentTapeEntry(id: row.id, label: "agent", text: row.text, tint: tint, isLive: live)
        }
    }

    private func laneMetric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(LatsFont.mono(7, weight: .bold))
                .foregroundStyle(LatsPalette.textFaint)
            Text(value)
                .font(LatsFont.mono(9, weight: .semibold))
                .foregroundStyle(LatsPalette.textDim)
        }
    }

    private func percent(_ value: Double?) -> String {
        "\(Int((value ?? 0).rounded()))%"
    }

    private var machineIcon: String {
        let label = store.connectionLabel.lowercased()
        if label.contains("mini") { return "macmini" }
        if label.contains("studio") { return "macstudio" }
        if label.contains("imac") { return "desktopcomputer" }
        return "laptopcomputer"
    }
}

private struct FleetSharedDeck: View {
    @ObservedObject var store: DeckStore
    let accent: Color
    let laneNumber: Int

    @State private var selectedPageID: String?

    private var pages: [DeckCockpitPage] {
        store.snapshot?.cockpit?.pages ?? []
    }

    private var activePage: DeckCockpitPage? {
        if let selectedPageID,
           let page = pages.first(where: { $0.id == selectedPageID }) {
            return page
        }
        return pages.first
    }

    private var shortcuts: [LatsShortcut] {
        activePage?.tiles.map(shortcut(from:)) ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            deckHeader
            LatsHairlineDivider()

            LatsCockpitShell {
                LatsTrackpadSurface(
                    mode: cockpitMode,
                    recTime: store.snapshot?.cockpitMode?.elapsedSeconds ?? 0,
                    agentProgress: (store.snapshot?.cockpitMode?.agentProgress ?? 0) * 264,
                    replayMessage: store.snapshot?.cockpitMode?.replayMessage ?? "",
                    replayUndoLabel: replayUndoLabel,
                    agentRows: store.snapshot?.cockpitMode?.agentRows ?? [],
                    telemetry: fleetTelemetry,
                    stage: fleetStage,
                    space: fleetSpace,
                    spaceCount: fleetSpaceCount,
                    spaceName: store.snapshot?.spaces?.currentSpaceName
                        ?? store.snapshot?.desktop?.currentSpaceName,
                    transcript: fleetTranscript,
                    activityLog: store.snapshot?.activityLog ?? [],
                    hostLabel: store.connectionLabel,
                    trackpadState: store.snapshot?.trackpad,
                    spaceDisplays: store.snapshot?.spaces?.displays ?? [],
                    frontmostApp: store.snapshot?.layout?.frontmostWindow?.appName
                        ?? store.snapshot?.desktop?.activeAppName,
                    frontmostTitle: store.snapshot?.layout?.frontmostWindow?.title,
                    onSendKey: sendKey,
                    onReplayUndo: undoReplay,
                    onTrackpadEvent: { event, dx, dy in
                        store.sendTrackpad(event: event, dx: dx, dy: dy)
                    },
                    onSpaceTap: focusSpace,
                    onMonitorSwipe: swipeMonitor
                )
                .environment(\.horizontalSizeClass, .regular)
            }
            .frame(height: 280)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            LatsHairlineDivider()

            GeometryReader { proxy in
                let columns = max(1, min(3, shortcuts.count))
                let rows = max(1, Int(ceil(Double(shortcuts.count) / Double(columns))))
                let availableHeight = max(96, proxy.size.height - 24 - CGFloat(max(0, rows - 1)) * 10)
                let controlHeight = availableHeight / CGFloat(rows)

                ScrollView {
                    LatsShortcutGrid(
                        shortcuts: shortcuts,
                        columns: columns,
                        onTap: perform,
                        onJoystickMove: { dx, dy in store.sendTrackpad(event: .move, dx: dx, dy: dy) },
                        joystickEnabled: joystickReady,
                        joystickScale: store.snapshot?.trackpad?.pointerScale ?? 1.6,
                        minimumControlHeight: controlHeight
                    )
                    .padding(12)
                    .frame(minHeight: proxy.size.height, alignment: .bottom)
                }
                .scrollIndicators(.hidden)
            }

            deckFooter
        }
        .background(
            LinearGradient(
                colors: [LatsPalette.surface.opacity(0.66), LatsPalette.bg.opacity(0.99)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(LatsPalette.hairline2, lineWidth: 1)
        )
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [.clear, accent.opacity(0.78), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)
            .padding(.horizontal, 8)
        }
        .shadow(color: Color.black.opacity(0.60), radius: 9, x: 0, y: 5)
        .onAppear(perform: selectFirstPageIfNeeded)
        .onChange(of: pages.map(\.id)) { _, _ in selectFirstPageIfNeeded() }
    }

    private var deckHeader: some View {
        HStack(spacing: 10) {
            Text("COMMON DECK")
                .font(LatsFont.mono(9, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(LatsPalette.text)

            Text("CH \(String(format: "%02d", laneNumber))")
                .font(LatsFont.mono(8, weight: .bold))
                .foregroundStyle(accent)
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(RoundedRectangle(cornerRadius: 4).fill(accent.opacity(0.11)))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(accent.opacity(0.30), lineWidth: 1))

            Image(systemName: "arrow.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(LatsPalette.textFaint)

            Text(store.connectionLabel)
                .font(LatsFont.mono(9, weight: .semibold))
                .foregroundStyle(LatsPalette.textDim)
                .lineLimit(1)

            Spacer(minLength: 12)

            HStack(spacing: 5) {
                ForEach(pages) { page in
                    let isSelected = page.id == activePage?.id
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { selectedPageID = page.id }
                    } label: {
                        Text(page.title.uppercased())
                            .font(LatsFont.mono(8, weight: isSelected ? .bold : .regular))
                            .foregroundStyle(isSelected ? accent : LatsPalette.textFaint)
                            .padding(.horizontal, 9)
                            .frame(height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(isSelected ? accent.opacity(0.11) : Color.white.opacity(0.025))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(isSelected ? accent.opacity(0.28) : LatsPalette.hairline, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(Color.black.opacity(0.22))
    }

    private var deckFooter: some View {
        HStack(spacing: 8) {
            Circle().fill(LatsPalette.green).frame(width: 5, height: 5)
            Text("OUTPUT")
                .font(LatsFont.mono(7, weight: .bold))
                .tracking(1)
                .foregroundStyle(LatsPalette.textFaint)
            Text(store.lastActionLabel ?? store.connectionLabel)
                .font(LatsFont.mono(8))
                .foregroundStyle(LatsPalette.textDim)
                .lineLimit(1)
            Spacer()
            if let cpu = store.snapshot?.telemetry?.cpuLoadPercent {
                Text("CPU \(Int(cpu.rounded()))%")
                    .font(LatsFont.mono(8))
                    .foregroundStyle(LatsPalette.textFaint)
            }
            Text("LANE \(laneNumber) · READY")
                .font(LatsFont.mono(8, weight: .semibold))
                .foregroundStyle(accent)
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(Color.black.opacity(0.25))
        .overlay(alignment: .top) {
            Rectangle().fill(LatsPalette.hairline).frame(height: 1)
        }
    }

    private var joystickReady: Bool {
        guard let state = store.snapshot?.trackpad else { return false }
        return state.isEnabled && state.isAvailable
    }

    private var cockpitMode: CockpitMode {
        guard let mode = store.snapshot?.cockpitMode?.mode else { return .idle }
        return CockpitMode(from: mode)
    }

    private var replayUndoLabel: String {
        guard let expiresAt = store.snapshot?.cockpitMode?.replayUndoExpiresAt else {
            return "undo within 5s"
        }
        let seconds = max(0, Int(ceil(expiresAt.timeIntervalSinceNow)))
        return seconds > 0 ? "undo within \(seconds)s" : "undo expired"
    }

    private var fleetTelemetry: LatsTelemetry {
        guard let telemetry = store.snapshot?.telemetry else { return LatsTelemetry() }
        return LatsTelemetry(from: telemetry)
    }

    private var fleetSpace: Int {
        let index = store.snapshot?.spaces?.currentSpaceIndex
            ?? store.snapshot?.desktop?.currentSpaceIndex
            ?? 1
        return max(0, index - 1)
    }

    private var fleetSpaceCount: Int {
        max(1, store.snapshot?.spaces?.displays.first?.spaces.count ?? 1)
    }

    private var fleetTranscript: [String] {
        if let lines = store.snapshot?.voice?.transcriptLines, !lines.isEmpty {
            return Array(lines.sorted { $0.createdAt > $1.createdAt }.prefix(5).map(\.text))
        }
        if let transcript = store.snapshot?.voice?.transcript, !transcript.isEmpty {
            return [transcript]
        }
        return []
    }

    private var fleetStage: [[LatsWindow]] {
        guard let preview = store.snapshot?.layout?.preview else { return CommandDeck.stage }
        let displayCount = max(preview.displayCount ?? 1, 1)
        var buckets = Array(repeating: [LatsWindow](), count: displayCount)
        for window in preview.windows {
            let index = window.displayIndex ?? 0
            guard buckets.indices.contains(index) else { continue }
            buckets[index].append(
                LatsWindow(
                    x: window.normalizedFrame.x * 100,
                    y: window.normalizedFrame.y * 100,
                    w: window.normalizedFrame.w * 100,
                    h: window.normalizedFrame.h * 100,
                    tint: LatsTint.from(token: window.appCategoryTint),
                    tag: String(window.title.prefix(4))
                )
            )
        }
        return buckets
    }

    private func sendKey(_ key: String, _ modifiers: [String]) {
        store.perform(
            actionID: "keys.send",
            pageID: activePage?.id ?? "cockpit",
            payload: [
                "key": .string(key),
                "modifiers": .array(modifiers.map { .string($0) })
            ],
            label: (modifiers + [key.uppercased()]).joined()
        )
    }

    private func undoReplay() {
        let actionID = store.snapshot?.cockpitMode?.replayUndoActionID ?? "history.undoLast"
        store.perform(actionID: actionID, pageID: activePage?.id ?? "cockpit", label: "Undo last action")
    }

    private func focusSpace(_ index: Int) {
        store.perform(
            actionID: "spaces.focusIndex",
            pageID: activePage?.id ?? "cockpit",
            payload: ["index": .int(index)],
            label: "Switch to space \(index + 1)"
        )
    }

    private func swipeMonitor(_ display: Int, _ direction: Int) {
        let key = direction > 0 ? "right" : "left"
        store.perform(
            actionID: "keys.send",
            pageID: activePage?.id ?? "cockpit",
            payload: ["key": .string(key), "modifiers": .array([.string("⌃")])],
            label: direction > 0 ? "Next space" : "Previous space"
        )
    }

    private func shortcut(from tile: DeckCockpitTile) -> LatsShortcut {
        LatsShortcut(
            id: tile.id,
            label: tile.title,
            icon: tile.iconSystemName,
            tint: LatsTint.from(token: tile.categoryTint ?? tile.accentToken),
            category: shortcutCategory(for: tile),
            hint: tile.subtitle ?? "",
            sim: .none,
            actionID: tile.actionID,
            payload: tile.payload,
            controlKind: tile.controlKind,
            isEnabled: tile.isEnabled
        )
    }

    private func shortcutCategory(for tile: DeckCockpitTile) -> ShortcutCategory {
        let searchable = [tile.deckID, tile.actionID, tile.title, tile.subtitle]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        if searchable.contains("voice") || searchable.contains("dictate") { return .voice }
        if searchable.contains("agent") || searchable.contains("claude") { return .agent }
        if searchable.contains("window") || searchable.contains("tile") { return .window }
        if searchable.contains("dev") || searchable.contains("terminal") { return .dev }
        return .system
    }

    private func perform(_ shortcut: LatsShortcut) {
        guard shortcut.isEnabled, let actionID = shortcut.actionID else { return }
        var payload = shortcut.payload
        if actionID == "clipboard.pasteFromDevice",
           let text = UIPasteboard.general.string,
           !text.isEmpty {
            payload["text"] = .string(text)
            payload["source"] = .string("ios-pasteboard")
        }
        store.perform(
            actionID: actionID,
            pageID: activePage?.id ?? "cockpit",
            payload: payload,
            label: shortcut.label
        )
    }

    private func selectFirstPageIfNeeded() {
        if let selectedPageID, pages.contains(where: { $0.id == selectedPageID }) { return }
        selectedPageID = pages.first?.id
    }
}

private struct FleetMachineDeck: View {
    @ObservedObject var store: DeckStore
    var accentOverride: Color? = nil

    @State private var selectedPageID: String?

    private var pages: [DeckCockpitPage] {
        store.snapshot?.cockpit?.pages ?? []
    }

    private var activePage: DeckCockpitPage? {
        if let selectedPageID,
           let page = pages.first(where: { $0.id == selectedPageID }) {
            return page
        }
        return pages.first
    }

    private var shortcuts: [LatsShortcut] {
        activePage?.tiles.map(shortcut(from:)) ?? []
    }

    private var accent: Color {
        if let accentOverride { return accentOverride }
        // Give each Mac a stable cockpit identity instead of inheriting the
        // first shortcut's semantic tint (which made voice-first decks all
        // look red). Individual shortcut icons still keep their action colors.
        let palette = [
            LatsPalette.teal,
            LatsPalette.blue,
            LatsPalette.violet,
            LatsPalette.green,
            LatsPalette.amber,
            LatsPalette.pink
        ]
        let identity = store.activeEndpoint?.bridgeFingerprint
            ?? store.activeEndpoint?.host
            ?? store.connectionLabel
        var hash: UInt64 = 2_166_136_261
        for byte in identity.utf8 {
            hash = (hash ^ UInt64(byte)) &* 16_777_619
        }
        return palette[Int(hash % UInt64(palette.count))]
    }

    private var statusColor: Color {
        if store.errorMessage != nil { return LatsPalette.red }
        if store.snapshot != nil { return LatsPalette.green }
        return store.isLoading ? LatsPalette.amber : LatsPalette.textFaint
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                machineHeader
                LatsCockpitShell {
                    LatsTrackpadSurface(
                        mode: cockpitMode,
                        recTime: store.snapshot?.cockpitMode?.elapsedSeconds ?? 0,
                        agentProgress: (store.snapshot?.cockpitMode?.agentProgress ?? 0) * 264,
                        replayMessage: store.snapshot?.cockpitMode?.replayMessage ?? "",
                        replayUndoLabel: "undo within 5s",
                        agentRows: store.snapshot?.cockpitMode?.agentRows ?? [],
                        telemetry: fleetTelemetry,
                        stage: fleetStage,
                        space: fleetSpace,
                        spaceCount: fleetSpaceCount,
                        spaceName: store.snapshot?.spaces?.currentSpaceName
                            ?? store.snapshot?.desktop?.currentSpaceName,
                        transcript: fleetTranscript,
                        activityLog: store.snapshot?.activityLog ?? [],
                        hostLabel: store.connectionLabel,
                        trackpadState: store.snapshot?.trackpad,
                        spaceDisplays: store.snapshot?.spaces?.displays ?? [],
                        frontmostApp: store.snapshot?.layout?.frontmostWindow?.appName
                            ?? store.snapshot?.desktop?.activeAppName,
                        frontmostTitle: store.snapshot?.layout?.frontmostWindow?.title,
                        onSendKey: sendKey,
                        onReplayUndo: undoReplay,
                        onTrackpadEvent: { event, dx, dy in
                            store.sendTrackpad(event: event, dx: dx, dy: dy)
                        },
                        onSpaceTap: focusSpace,
                        onMonitorSwipe: swipeMonitor
                    )
                    .environment(\.horizontalSizeClass, .compact)
                }
                .frame(height: min(240, max(190, proxy.size.height * 0.29)))
                .padding(.horizontal, 10)
                .padding(.bottom, 9)

                if pages.count > 1 {
                    deckPageStrip
                }

                LatsHairlineDivider()

                Group {
                    if !shortcuts.isEmpty {
                        shortcutGrid(width: proxy.size.width)
                    } else {
                        connectionState
                    }
                }
                .frame(maxHeight: .infinity)

                machineFooter
            }
            .background(
                LinearGradient(
                    colors: [accent.opacity(0.045), LatsPalette.bg.opacity(0.98)],
                    startPoint: .topLeading,
                    endPoint: .center
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(
                        store.errorMessage == nil
                            ? accent.opacity(store.snapshot == nil ? 0.22 : 0.30)
                            : statusColor.opacity(0.55),
                        lineWidth: 1
                    )
            )
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(accent.opacity(store.snapshot == nil ? 0.26 : 0.50))
                    .frame(height: 1)
                    .padding(.horizontal, 5)
            }
            .shadow(color: Color.black.opacity(0.50), radius: 6, x: 0, y: 3)
        }
        .onAppear(perform: selectFirstPageIfNeeded)
        .onChange(of: pages.map(\.id)) { _, _ in selectFirstPageIfNeeded() }
    }

    private var machineHeader: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(accent.opacity(0.14))
                Image(systemName: machineIcon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(accent)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(store.connectionLabel)
                    .font(LatsFont.ui(13, weight: .semibold))
                    .foregroundStyle(LatsPalette.text)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Circle().fill(statusColor).frame(width: 5, height: 5)
                    Text(connectionStateLabel)
                        .font(LatsFont.mono(8, weight: .semibold))
                        .foregroundStyle(statusColor)
                        .tracking(0.8)
                }
            }

            Spacer(minLength: 4)

            if store.isPerformingAction {
                ProgressView()
                    .controlSize(.small)
                    .tint(accent)
            } else if let page = activePage {
                Button(action: cyclePage) {
                    HStack(spacing: 5) {
                        Text(page.title.uppercased())
                            .font(LatsFont.mono(8, weight: .bold))
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 7, weight: .bold))
                    }
                    .foregroundStyle(accent)
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 5).fill(accent.opacity(0.10)))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(accent.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 52)
        .overlay(alignment: .bottom) {
            Rectangle().fill(LatsPalette.hairline).frame(height: 1)
        }
    }

    private var deckPageStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(pages) { page in
                    let isSelected = page.id == activePage?.id
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) { selectedPageID = page.id }
                    } label: {
                        Text(page.title.uppercased())
                            .font(LatsFont.mono(8, weight: isSelected ? .bold : .regular))
                            .foregroundStyle(isSelected ? accent : LatsPalette.textFaint)
                            .padding(.horizontal, 8)
                            .frame(height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(isSelected ? accent.opacity(0.10) : Color.white.opacity(0.025))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    private func shortcutGrid(width: CGFloat) -> some View {
        GeometryReader { proxy in
            ScrollView {
                LatsShortcutGrid(
                    shortcuts: shortcuts,
                    columns: width >= 560 ? 3 : 2,
                    onTap: perform,
                    onJoystickMove: { dx, dy in store.sendTrackpad(event: .move, dx: dx, dy: dy) },
                    joystickEnabled: joystickReady,
                    joystickScale: store.snapshot?.trackpad?.pointerScale ?? 1.6
                )
                .padding(10)
                .frame(minHeight: proxy.size.height, alignment: .bottom)
                .id(activePage?.id)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var connectionState: some View {
        VStack(spacing: 12) {
            Image(systemName: store.errorMessage == nil ? "dot.radiowaves.left.and.right" : "wifi.exclamationmark")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(statusColor)

            Text(store.errorMessage == nil ? "CONNECTING TO MAC" : "MAC UNAVAILABLE")
                .font(LatsFont.mono(10, weight: .bold))
                .foregroundStyle(LatsPalette.text)
                .tracking(1)

            if let error = store.errorMessage {
                Text(error)
                    .font(LatsFont.mono(9))
                    .foregroundStyle(LatsPalette.textDim)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(.horizontal, 16)

                LatsButton(title: "Retry", icon: "arrow.clockwise", style: .ghost) {
                    if let endpoint = store.activeEndpoint { store.connect(to: endpoint) }
                }
            } else {
                ProgressView().tint(LatsPalette.amber)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var machineFooter: some View {
        HStack(spacing: 7) {
            Circle().fill(statusColor).frame(width: 5, height: 5)
            Text(footerLabel)
                .font(LatsFont.mono(8))
                .foregroundStyle(store.lastActionResult?.ok == false ? LatsPalette.red : LatsPalette.textDim)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let cpu = store.snapshot?.telemetry?.cpuLoadPercent {
                Text("CPU \(Int(cpu.rounded()))%")
                    .font(LatsFont.mono(8))
                    .foregroundStyle(LatsPalette.textFaint)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Color.black.opacity(0.20))
        .overlay(alignment: .top) {
            Rectangle().fill(LatsPalette.hairline).frame(height: 1)
        }
    }

    private var connectionStateLabel: String {
        if store.errorMessage != nil { return "OFFLINE" }
        if store.snapshot != nil { return "LIVE" }
        return "LINKING"
    }

    private var footerLabel: String {
        if let result = store.lastActionResult { return result.summary }
        if let label = store.lastActionLabel { return label }
        if let app = store.snapshot?.layout?.frontmostWindow?.appName
            ?? store.snapshot?.desktop?.activeAppName {
            return app
        }
        return connectionStateLabel.lowercased()
    }

    private var machineIcon: String {
        let label = store.connectionLabel.lowercased()
        if label.contains("mini") { return "macmini" }
        if label.contains("studio") { return "macstudio" }
        if label.contains("imac") { return "desktopcomputer" }
        return "laptopcomputer"
    }

    private var joystickReady: Bool {
        guard let state = store.snapshot?.trackpad else { return false }
        return state.isEnabled && state.isAvailable
    }

    private var cockpitMode: CockpitMode {
        guard let mode = store.snapshot?.cockpitMode?.mode else { return .idle }
        return CockpitMode(from: mode)
    }

    private var fleetTelemetry: LatsTelemetry {
        guard let telemetry = store.snapshot?.telemetry else { return LatsTelemetry() }
        return LatsTelemetry(from: telemetry)
    }

    private var fleetSpace: Int {
        let index = store.snapshot?.spaces?.currentSpaceIndex
            ?? store.snapshot?.desktop?.currentSpaceIndex
            ?? 1
        return max(0, index - 1)
    }

    private var fleetSpaceCount: Int {
        max(1, store.snapshot?.spaces?.displays.first?.spaces.count ?? 1)
    }

    private var fleetTranscript: [String] {
        if let lines = store.snapshot?.voice?.transcriptLines, !lines.isEmpty {
            return Array(lines.sorted { $0.createdAt > $1.createdAt }.prefix(5).map(\.text))
        }
        if let transcript = store.snapshot?.voice?.transcript, !transcript.isEmpty {
            return [transcript]
        }
        return []
    }

    private var fleetStage: [[LatsWindow]] {
        guard let preview = store.snapshot?.layout?.preview else { return CommandDeck.stage }
        let displayCount = max(preview.displayCount ?? 1, 1)
        var buckets = Array(repeating: [LatsWindow](), count: displayCount)
        for window in preview.windows {
            let index = window.displayIndex ?? 0
            guard buckets.indices.contains(index) else { continue }
            buckets[index].append(
                LatsWindow(
                    x: window.normalizedFrame.x * 100,
                    y: window.normalizedFrame.y * 100,
                    w: window.normalizedFrame.w * 100,
                    h: window.normalizedFrame.h * 100,
                    tint: LatsTint.from(token: window.appCategoryTint),
                    tag: String(window.title.prefix(4))
                )
            )
        }
        return buckets
    }

    private func sendKey(_ key: String, _ modifiers: [String]) {
        store.perform(
            actionID: "keys.send",
            pageID: activePage?.id ?? "cockpit",
            payload: [
                "key": .string(key),
                "modifiers": .array(modifiers.map { .string($0) })
            ],
            label: (modifiers + [key.uppercased()]).joined()
        )
    }

    private func undoReplay() {
        let actionID = store.snapshot?.cockpitMode?.replayUndoActionID ?? "history.undoLast"
        store.perform(actionID: actionID, pageID: activePage?.id ?? "cockpit", label: "Undo last action")
    }

    private func focusSpace(_ index: Int) {
        store.perform(
            actionID: "spaces.focusIndex",
            pageID: activePage?.id ?? "cockpit",
            payload: ["index": .int(index)],
            label: "Switch to space \(index + 1)"
        )
    }

    private func swipeMonitor(_ display: Int, _ direction: Int) {
        let key = direction > 0 ? "right" : "left"
        store.perform(
            actionID: "keys.send",
            pageID: activePage?.id ?? "cockpit",
            payload: ["key": .string(key), "modifiers": .array([.string("⌃")])],
            label: direction > 0 ? "Next space" : "Previous space"
        )
    }

    private func shortcut(from tile: DeckCockpitTile) -> LatsShortcut {
        LatsShortcut(
            id: tile.id,
            label: tile.title,
            icon: tile.iconSystemName,
            tint: LatsTint.from(token: tile.categoryTint ?? tile.accentToken),
            category: shortcutCategory(for: tile),
            hint: tile.subtitle ?? "",
            sim: .none,
            actionID: tile.actionID,
            payload: tile.payload,
            controlKind: tile.controlKind,
            isEnabled: tile.isEnabled
        )
    }

    private func shortcutCategory(for tile: DeckCockpitTile) -> ShortcutCategory {
        let searchable = [tile.deckID, tile.actionID, tile.title, tile.subtitle]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        if searchable.contains("voice") || searchable.contains("dictate") { return .voice }
        if searchable.contains("agent") || searchable.contains("claude") { return .agent }
        if searchable.contains("window") || searchable.contains("tile") { return .window }
        if searchable.contains("dev") || searchable.contains("terminal") { return .dev }
        return .system
    }

    private func perform(_ shortcut: LatsShortcut) {
        guard shortcut.isEnabled, let actionID = shortcut.actionID else { return }
        var payload = shortcut.payload
        if actionID == "clipboard.pasteFromDevice",
           let text = UIPasteboard.general.string,
           !text.isEmpty {
            payload["text"] = .string(text)
            payload["source"] = .string("ios-pasteboard")
        }
        store.perform(
            actionID: actionID,
            pageID: activePage?.id ?? "cockpit",
            payload: payload,
            label: shortcut.label
        )
    }

    private func selectFirstPageIfNeeded() {
        if let selectedPageID, pages.contains(where: { $0.id == selectedPageID }) { return }
        selectedPageID = pages.first?.id
    }

    private func cyclePage() {
        guard pages.count > 1 else { return }
        let current = pages.firstIndex(where: { $0.id == activePage?.id }) ?? 0
        selectedPageID = pages[(current + 1) % pages.count].id
    }
}

private struct FleetTrackpadSurface: View {
    let machineLabel: String
    let activeApp: String?
    let activeWindow: String?
    let spaceName: String?
    let telemetry: DeckSystemTelemetry?
    let state: DeckTrackpadState?
    let accent: Color
    let sendEvent: (DeckTrackpadEvent, Double, Double) -> Void

    @State private var lastLocation: CGPoint?

    private var isEnabled: Bool {
        state?.isEnabled == true && state?.isAvailable == true
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.black.opacity(0.28))
                trackpadGrid(size: proxy.size)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("CONTROL SURFACE")
                                .font(LatsFont.mono(8, weight: .bold))
                                .foregroundStyle(LatsPalette.textFaint)
                                .tracking(1.2)
                            Text(activeApp ?? machineLabel)
                                .font(LatsFont.ui(12, weight: .semibold))
                                .foregroundStyle(LatsPalette.text)
                                .lineLimit(1)
                            Text(activeWindow ?? (isEnabled ? "glide · tap" : state?.statusTitle ?? "trackpad unavailable"))
                                .font(LatsFont.mono(8))
                                .foregroundStyle(LatsPalette.textDim)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        Image(systemName: isEnabled ? "cursorarrow.motionlines" : "cursorarrow.slash")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(isEnabled ? accent : LatsPalette.textFaint)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        if let spaceName, !spaceName.isEmpty {
                            compactMetric(icon: "square.3.layers.3d", text: spaceName)
                        }
                        if let count = telemetry?.windowCount {
                            compactMetric(icon: "macwindow", text: "\(count)")
                        }
                        Spacer(minLength: 0)
                        Text(isEnabled ? "LIVE INPUT" : "VIEW ONLY")
                            .font(LatsFont.mono(7, weight: .bold))
                            .foregroundStyle(isEnabled ? accent : LatsPalette.textFaint)
                            .tracking(0.8)
                    }
                }
                .padding(11)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isEnabled ? accent.opacity(0.30) : LatsPalette.hairline2, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .gesture(trackpadGesture)
            .simultaneousGesture(
                TapGesture().onEnded {
                    guard isEnabled else { return }
                    sendEvent(.click, 0, 0)
                }
            )
        }
        .opacity(isEnabled ? 1 : 0.72)
    }

    private func trackpadGrid(size: CGSize) -> some View {
        Path { path in
            for column in 1..<5 {
                let x = CGFloat(column) * size.width / 5
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            for row in 1..<3 {
                let y = CGFloat(row) * size.height / 3
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
        }
        .stroke(Color.white.opacity(0.035), style: StrokeStyle(lineWidth: 1, dash: [3, 6]))
        .padding(8)
    }

    private var trackpadGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard isEnabled else { return }
                guard let previous = lastLocation else {
                    lastLocation = value.location
                    return
                }
                let dx = value.location.x - previous.x
                let dy = value.location.y - previous.y
                lastLocation = value.location
                guard abs(dx) > 0.2 || abs(dy) > 0.2 else { return }
                let scale = state?.pointerScale ?? 1.6
                sendEvent(.move, Double(dx) * scale, Double(dy) * scale)
            }
            .onEnded { _ in lastLocation = nil }
    }

    private func compactMetric(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 8))
            Text(text).font(LatsFont.mono(7, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(LatsPalette.textFaint)
    }
}

// MARK: - Preview

#Preview("Lats Deck — iPad landscape") {
    LatsDeckScreen()
        .frame(width: 1180, height: 820)
        .preferredColorScheme(.dark)
}

#if DEBUG
#Preview("Fleet Deck — 4-up landscape") {
    FleetDeckPreviewHost(machineCount: 4)
        .frame(width: 1366, height: 1024)
        .preferredColorScheme(.dark)
}
#endif
