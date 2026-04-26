import DeckKit
import SwiftUI

// MARK: - Design System

enum LatsPalette {
    static let bgEdge   = Color(hue: 0.62, saturation: 0.05, brightness: 0.10)
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
    let id = UUID()
    let label: String
    let icon: String      // SF Symbol name
    let tint: LatsTint
    let category: ShortcutCategory
    let hint: String
    let sim: SimAction
    var actionID: String? = nil
    var payload: [String: DeckValue] = [:]
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
    let deckName: String
    let accent: Color
    let onSwitcher: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("LATS · DECK")
                    .font(LatsFont.mono(11, weight: .bold))
                    .foregroundStyle(LatsPalette.text)
                    .tracking(1.5)
                Text("·").foregroundStyle(LatsPalette.textFaint)
                Button(action: onSwitcher) {
                    HStack(spacing: 6) {
                        ForEach(["command", "dev", "media", "windows", "voice"], id: \.self) { name in
                            if name != "command" {
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
        .background(Color.black.opacity(0.25))
        .overlay(alignment: .bottom) {
            Rectangle().fill(LatsPalette.hairline).frame(height: 1)
        }
    }
}

// MARK: - Cockpit Shell

struct LatsCockpitShell<Content: View>: View {
    let deckName: String
    let deckHint: String
    let accent: Color
    @Binding var mode: CockpitMode
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            header
            content()
        }
        .background(
            LinearGradient(
                colors: [LatsPalette.surface, LatsPalette.surface.opacity(0.9)],
                startPoint: .top, endPoint: .bottom
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(LatsPalette.hairline2, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var header: some View {
        HStack {
            HStack(spacing: 10) {
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)
                    .shadow(color: accent, radius: 4)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("COCKPIT")
                        .font(LatsFont.mono(9, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(LatsPalette.textFaint)
                    Text("· \(deckName)")
                        .font(LatsFont.ui(13, weight: .semibold))
                        .foregroundStyle(LatsPalette.text)
                    Text(deckHint)
                        .font(LatsFont.mono(9))
                        .foregroundStyle(LatsPalette.textFaint)
                }
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(CockpitMode.allCases, id: \.self) { m in
                    LatsModeChip(mode: m, isActive: mode == m) { mode = m }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.2))
        .overlay(alignment: .bottom) {
            Rectangle().fill(LatsPalette.hairline).frame(height: 1)
        }
    }
}

struct LatsModeChip: View {
    let mode: CockpitMode
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(mode.rawValue)
                .font(LatsFont.mono(9, weight: isActive ? .semibold : .regular))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(isActive ? mode.color : LatsPalette.textFaint)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isActive ? mode.color.opacity(0.24) : .clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isActive ? mode.color : LatsPalette.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Trackpad Surface

struct LatsTrackpadSurface: View {
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
    var onSendKey: ((String, [String]) -> Void)? = nil
    var onReplayUndo: (() -> Void)? = nil

    var body: some View {
        ZStack {
            // Grid background
            LatsGridBackground()

            // Mode badge top center
            VStack {
                modeBadge
                    .padding(.top, 8)
                Spacer()
            }

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

            // Top-left inset stack
            VStack(alignment: .leading, spacing: 6) {
                LatsInsetSlice {
                    CompactSystemPanel(telemetry: telemetry)
                }
                LatsInsetSlice {
                    CompactDisplaysPanel(
                        stage: stage,
                        space: space,
                        spaceCount: spaceCount,
                        spaceName: spaceName
                    )
                }
                Spacer()
            }
            .frame(width: 200)
            .padding(.top, 38)
            .padding(.leading, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Top-right inset stack
            VStack(alignment: .leading, spacing: 6) {
                LatsInsetSlice {
                    CompactTranscriptPanel(items: transcript)
                }
                LatsInsetSlice {
                    CompactActivityLogPanel(entries: activityLog)
                }
                Spacer()
            }
            .frame(width: 220)
            .padding(.top, 38)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            // Bottom action keyboard row
            VStack {
                Spacer()
                LatsActionKeyboardRow(onSendKey: onSendKey)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
        }
        .background(LatsPalette.bgEdge)
    }

    private var modeBadge: some View {
        Group {
            switch mode {
            case .idle:
                Text("trackpad · awaiting input")
                    .foregroundStyle(LatsPalette.textFaint)
            case .rec:
                HStack(spacing: 4) {
                    Circle().fill(LatsPalette.red).frame(width: 6, height: 6)
                    Text("recording · \(recTime, specifier: "%.1f")s")
                        .foregroundStyle(LatsPalette.red)
                }
            case .replay:
                Text("✓ done · \(recTime, specifier: "%.1f")s")
                    .foregroundStyle(LatsPalette.green)
            case .agent:
                let liveIndex = agentRows.firstIndex(where: { $0.state == .live }).map { $0 + 1 } ?? 1
                let total = max(agentRows.count, 1)
                Text("thinking · step \(liveIndex)/\(total)")
                    .foregroundStyle(LatsPalette.violet)
            }
        }
        .font(LatsFont.mono(9))
        .tracking(1.5)
        .textCase(.uppercase)
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(Color.black.opacity(0.4))
        )
        .overlay(
            Capsule().stroke(LatsPalette.hairline, lineWidth: 1)
        )
    }
}

struct LatsGridBackground: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 20
            let lineColor = Color.white.opacity(0.035)
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
    let telemetry: LatsTelemetry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("air.local")
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

    private var cappedSpaceCount: Int {
        max(1, min(spaceCount, 9))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("displays")
                    .font(LatsFont.mono(10, weight: .semibold))
                    .foregroundStyle(LatsPalette.text)
                Spacer()
                Text("\(max(stage.count, 1)) · \(spaceName ?? "\(space + 1)")")
                    .font(LatsFont.mono(8.5))
                    .foregroundStyle(LatsPalette.textFaint)
            }
            HStack(spacing: 3) {
                ForEach(0..<2, id: \.self) { d in
                    miniDisplay(windows: d < stage.count ? stage[d] : [])
                }
            }
            .frame(height: 32)
            HStack(spacing: 2) {
                ForEach(0..<cappedSpaceCount, id: \.self) { i in
                    spaceCell(index: i)
                }
            }
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
        return Text("\(index + 1)")
            .font(LatsFont.mono(7, weight: isActive ? .semibold : .regular))
            .foregroundStyle(isActive ? LatsPalette.green : LatsPalette.textDim)
            .frame(maxWidth: .infinity, maxHeight: 11)
            .background(
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isActive ? LatsPalette.green.opacity(0.25) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 1.5)
                    .stroke(isActive ? LatsPalette.green : LatsPalette.hairline, lineWidth: 1)
            )
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

    private var visibleEntries: [DeckActivityLogEntry] {
        Array(entries.sorted { $0.createdAt > $1.createdAt }.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("activity")
                    .font(LatsFont.mono(10, weight: .semibold))
                    .foregroundStyle(LatsPalette.text)
                Spacer()
                Text("\(entries.count)")
                    .font(LatsFont.mono(8.5))
                    .foregroundStyle(LatsPalette.textFaint)
            }

            if visibleEntries.isEmpty {
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
            } else {
                ForEach(visibleEntries) { entry in
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
        }
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
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(LatsPalette.green.opacity(0.25), lineWidth: 1)
                    .frame(width: 64, height: 64)
                Circle()
                    .stroke(LatsPalette.green.opacity(0.18), lineWidth: 1)
                    .frame(width: 44, height: 44)
                ZStack {
                    Circle()
                        .stroke(LatsPalette.green, lineWidth: 1)
                        .frame(width: 20, height: 20)
                    Rectangle().fill(LatsPalette.green.opacity(0.6)).frame(width: 1, height: 36)
                    Rectangle().fill(LatsPalette.green.opacity(0.6)).frame(width: 36, height: 1)
                    Circle().fill(LatsPalette.green).frame(width: 3, height: 3)
                }
                .shadow(color: LatsPalette.green.opacity(0.5), radius: 7)
            }
            Text("TAP · DRAG · PINCH")
                .font(LatsFont.mono(10, weight: .semibold))
                .tracking(2.5)
                .foregroundStyle(LatsPalette.textDim)
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

struct LatsActionKeyboardRow: View {
    var onSendKey: ((String, [String]) -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            // Left — modifier / utility keys
            HStack(spacing: 4) {
                ActionKey(label: "esc", width: 30) { send("escape", []) }
                ActionKey(label: "⌘C", width: 30) { send("c", ["⌘"]) }
                ActionKey(label: "⌘V", width: 30) { send("v", ["⌘"]) }
                ActionKey(label: "⌘Z", width: 30) { send("z", ["⌘"]) }
                ActionKey(label: "⇧⇥", width: 30) { send("tab", ["⇧"]) }
                ActionKey(label: "space", width: 56) { send("space", []) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Center — arrow cluster
            ArrowCluster(onTap: { dir in send(dir, []) })

            // Right — modifiers (visual only, no single-key action) + enter
            HStack(spacing: 4) {
                ActionKey(label: "⌃", width: 26)
                ActionKey(label: "⌥", width: 26)
                ActionKey(label: "⇧", width: 26)
                ActionKey(label: "⌘", width: 26)
                EnterPill { send("return", []) }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hue: 0.62, saturation: 0.05, brightness: 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(LatsPalette.hairline2, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
    }

    private func send(_ key: String, _ modifiers: [String]) {
        onSendKey?(key, modifiers)
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
        VStack(spacing: 2) {
            arrow("arrow.up", key: "up")
            HStack(spacing: 2) {
                arrow("arrow.left", key: "left")
                arrow("arrow.down", key: "down")
                arrow("arrow.right", key: "right")
            }
        }
    }

    private func arrow(_ icon: String, key: String) -> some View {
        let label = Image(systemName: icon)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(LatsPalette.textDim)
            .frame(width: 24, height: 12)
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
    let onTap: (LatsShortcut) -> Void

    @State private var recentlyPressed: UUID?

    var body: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 10), count: columns)
        LazyVGrid(columns: cols, spacing: 10) {
            ForEach(Array(shortcuts.enumerated()), id: \.element.id) { idx, s in
                LatsShortcutTile(
                    shortcut: s,
                    index: idx + 1,
                    isRecent: recentlyPressed == s.id
                ) {
                    onTap(s)
                    withAnimation { recentlyPressed = s.id }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        if recentlyPressed == s.id {
                            withAnimation { recentlyPressed = nil }
                        }
                    }
                }
            }
        }
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
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 2) {
                    Text(shortcut.label)
                        .font(LatsFont.ui(12, weight: .medium))
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
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, perform: {}, onPressingChanged: { pressing in
            withAnimation(.easeOut(duration: 0.08)) { isPressed = pressing }
        })
    }

    private var iconBadge: some View {
        Image(systemName: shortcut.icon)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(shortcut.tint.color)
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(shortcut.tint.color.opacity(0.18))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(shortcut.tint.color.opacity(0.28), lineWidth: 1)
            )
    }

    @ViewBuilder
    private var tileBackground: some View {
        let base = RoundedRectangle(cornerRadius: 8)
        if isPressed {
            base.fill(Color.white.opacity(0.06))
        } else if isRecent {
            base.fill(shortcut.tint.color.opacity(0.12).blendMode(.plusLighter))
                .background(base.fill(LatsPalette.surface))
        } else {
            base.fill(LatsPalette.surface)
        }
    }

    private var tileBorder: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(isRecent ? shortcut.tint.color : LatsPalette.hairline, lineWidth: 1)
            .shadow(color: isRecent ? shortcut.tint.color.opacity(0.14) : .clear, radius: 3)
    }
}

// MARK: - Cursor-style Status Bar

struct LatsStatusBar: View {
    let mode: CockpitMode
    let recTime: Double
    let telemetry: LatsTelemetry
    let space: Int
    let spaceCount: Int
    let spaceName: String?
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
        HStack(spacing: 0) {
            modePill
            StatusItem(icon: "mic", label: "hold·space", tint: LatsPalette.text, onTap: onModeTap)
            StatusItem(icon: "laptopcomputer.and.iphone", label: "air ↔ deck", tint: LatsPalette.green)
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
        .frame(height: 26)
        .background(Color.black.opacity(0.5))
        .overlay(alignment: .top) {
            Rectangle().fill(LatsPalette.hairline).frame(height: 1)
        }
    }

    private var modePill: some View {
        Button(action: onModeTap) {
            HStack(spacing: 6) {
                Circle()
                    .fill(mode.color)
                    .frame(width: 6, height: 6)
                Text(modeLabel)
                    .font(LatsFont.mono(10, weight: .semibold))
                    .tracking(1)
                if mode == .rec {
                    Text("· \(recTime, specifier: "%.1f")s")
                        .font(LatsFont.mono(10))
                }
            }
            .foregroundStyle(mode.color)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(mode.color.opacity(0.24))
            .overlay(alignment: .trailing) {
                Rectangle().fill(LatsPalette.hairline).frame(width: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct StatusItem: View {
    var icon: String? = nil
    let label: String
    var tint: Color = LatsPalette.textDim
    var onTap: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        let content = HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 10)) }
            Text(label).font(LatsFont.mono(10))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .frame(height: 26)
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

    /// When connected, tile presses and keyboard sends route through this callback.
    var onAction: ((_ actionID: String, _ payload: [String: DeckValue], _ label: String?) -> Void)?

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

    private var isConnected: Bool { liveSnapshot != nil }

    private var effectiveDeckID: String {
        selectedDeckID ?? deckID
    }

    private var gridColumns: Int {
        if let columns = activeCockpitPage()?.columns {
            return hSize == .compact ? min(3, columns) : columns
        }
        return hSize == .compact ? 3 : 6
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

    private var stage: [[LatsWindow]] {
        guard let preview = liveSnapshot?.layout?.preview else { return mockStage }
        // Bridge currently returns one preview per layout; project all windows onto display 0
        // until per-display preview lands. Empty display 1 keeps the second mini-frame.
        let windows: [LatsWindow] = preview.windows.map { w in
            LatsWindow(
                x: w.normalizedFrame.x * 100,
                y: w.normalizedFrame.y * 100,
                w: w.normalizedFrame.w * 100,
                h: w.normalizedFrame.h * 100,
                tint: LatsTint.from(token: w.appCategoryTint),
                tag: String(w.title.prefix(4))
            )
        }
        return [windows, []]
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

    private var deckHint: String {
        activeCockpitPage()?.subtitle ?? CommandDeck.hint
    }

    var body: some View {
        ZStack {
            LatsPalette.bgEdge.ignoresSafeArea()

            VStack(spacing: 0) {
                LatsTopChrome(
                    deckName: deckName,
                    accent: deckAccent,
                    onSwitcher: { cycleDeck() },
                    onClose: { dismiss() }
                )

                GeometryReader { geo in
                    let isPad = geo.size.width > 700 && hSize == .regular
                    let cockpitH: CGFloat = isPad ? max(440, geo.size.height * 0.58) : max(360, geo.size.height * 0.50)

                    VStack(spacing: 0) {
                        // Cockpit
                        ZStack {
                            LatsCockpitShell(
                                deckName: deckName,
                                deckHint: deckHint,
                                accent: deckAccent,
                                mode: cockpitModeBinding
                            ) {
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
                                    onSendKey: handleSendKey,
                                    onReplayUndo: handleReplayUndo
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

                        // Shortcut grid
                        ScrollView {
                            LatsShortcutGrid(
                                shortcuts: shortcuts,
                                columns: gridColumns,
                                onTap: handleTilePress
                            )
                            .padding(14)
                        }
                        .frame(maxHeight: .infinity)
                    }
                }

                LatsStatusBar(
                    mode: mode,
                    recTime: recTime,
                    telemetry: telemetry,
                    space: space,
                    spaceCount: spaceCount,
                    spaceName: spaceName,
                    onModeTap: { toggleVoice() },
                    onSpaceTap: { if !isConnected { mockSpace = (mockSpace + 1) % 6 } },
                    onPaletteTap: {},
                    onSwitcherTap: { cycleDeck() }
                )
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
                label: tile.title,
                icon: tile.iconSystemName,
                tint: LatsTint.from(token: tile.categoryTint ?? tile.accentToken),
                category: shortcutCategory(for: tile),
                hint: tile.subtitle ?? "",
                sim: simAction(from: tile.actionID),
                actionID: tile.actionID,
                payload: tile.payload
            )
        }
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

    private var cockpitModeBinding: Binding<CockpitMode> {
        Binding(
            get: { mode },
            set: { newValue in
                if isConnected {
                    // Modes are an output when connected; ignore manual chip taps.
                } else {
                    mockMode = newValue
                }
            }
        )
    }

    // MARK: - Behaviour

    private func handleTilePress(_ shortcut: LatsShortcut) {
        if let onAction, let actionID = shortcut.actionID {
            onAction(actionID, shortcut.payload, shortcut.label)
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

    private func cycleDeck() {
        let liveIDs = liveSnapshot?.cockpit?.pages.map(\.id).filter { !$0.isEmpty } ?? []
        let ids = liveIDs.isEmpty ? ["command", "dev", "media", "windows", "voice"] : liveIDs
        guard let currentIndex = ids.firstIndex(of: effectiveDeckID) else {
            selectedDeckID = ids.first
            return
        }
        selectedDeckID = ids[(currentIndex + 1) % ids.count]
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

// MARK: - Preview

#Preview("Lats Deck — iPad landscape") {
    LatsDeckScreen()
        .frame(width: 1180, height: 820)
        .preferredColorScheme(.dark)
}
