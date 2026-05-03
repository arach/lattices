import SwiftUI

// MARK: - Telemetry models

/// Compact telemetry segment shown in the bottom bar's middle cluster.
/// Each segment is a short mono token (e.g. "19w", "1/7", "cpu 51%").
struct HomeBottomTelemetry: Equatable {
    var contextLabel: String     // "air ~ home"  — machine · scene-ish breadcrumb
    var windows: Int             // open windows on the foreground machine
    var displayIndex: Int        // current display
    var displayCount: Int        // total displays
    var cpuPercent: Int          // 0-100
    var memPercent: Int          // 0-100
    var tempCelsius: Int?        // optional thermal reading

    /// Empty / unwired telemetry — used when no host telemetry is available.
    /// Renderers treat an empty `contextLabel` as a signal to suppress the
    /// telemetry cluster entirely instead of showing zeros.
    static let empty = HomeBottomTelemetry(
        contextLabel: "",
        windows: 0,
        displayIndex: 0,
        displayCount: 0,
        cpuPercent: 0,
        memPercent: 0,
        tempCelsius: nil
    )

    static let mock = HomeBottomTelemetry(
        contextLabel: "air ~ home",
        windows: 19,
        displayIndex: 1,
        displayCount: 7,
        cpuPercent: 51,
        memPercent: 98,
        tempCelsius: 45
    )
}

/// Per-machine telemetry row used inside the expanded accordion.
struct HomeBottomMachineTelemetry: Identifiable, Equatable {
    let id: String
    let name: String
    let cpuPercent: Int
    let memPercent: Int
    let windows: Int
    let buildState: String       // "idle" / "building" / "ok" / "fail"
    let buildTint: LatsTint
}

extension HomeBottomMachineTelemetry {
    static let mock: [HomeBottomMachineTelemetry] = [
        HomeBottomMachineTelemetry(id: "m1", name: "arach-laptop", cpuPercent: 51, memPercent: 98, windows: 19, buildState: "building", buildTint: .amber),
        HomeBottomMachineTelemetry(id: "m2", name: "arach-mini",   cpuPercent: 12, memPercent: 41, windows: 6,  buildState: "idle",     buildTint: .blue),
        HomeBottomMachineTelemetry(id: "m3", name: "arach-studio", cpuPercent: 68, memPercent: 73, windows: 11, buildState: "ok",       buildTint: .green),
    ]
}

// MARK: - Bottom bar

/// Bottom chrome — symmetric to `HomeTopBar`. Carries dense ambient state:
/// status dot, hold-space hint, machine context, telemetry segments, agent
/// state, and a right-edge product/version mark. Tapping the telemetry
/// cluster expands an accordion with per-machine rows.
///
/// Surface follows the Talkie BottomTrayBackground pattern: the dark surface
/// extends into the bottom safe area while content sits above the home
/// indicator via internal padding. The hairline lives only at the top edge.
///
/// Size budget: ~40pt collapsed, ~96pt expanded (excluding safe-area extension).
struct HomeBottomBar: View {
    var statusLabel: String = "READY"
    var versionLabel: String = "v0.4.2"
    var holdHint: String = "hold·space"
    var product: String = "claude · Lattices"
    var agentState: HomeAgentState = .idle
    var telemetry: HomeBottomTelemetry = .empty
    var machineTelemetry: [HomeBottomMachineTelemetry] = []
    var onCommand: (() -> Void)? = nil
    var onVoice: (() -> Void)? = nil

    private var hasTelemetry: Bool { !telemetry.contextLabel.isEmpty }

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            collapsedBar
            if isExpanded {
                expandedStrip
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .bottom)),
                            removal: .opacity
                        )
                    )
            }
        }
        .background(barSurface)
        .overlay(alignment: .top) {
            Rectangle().fill(LatsPalette.hairline2).frame(height: 1)
        }
    }

    // MARK: - Surface (extends into bottom safe area)

    private var barSurface: some View {
        Color.black.opacity(isExpanded ? 0.30 : 0.25)
            .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Collapsed row

    private var collapsedBar: some View {
        HStack(spacing: 10) {
            statusSegment
            holdHintSegment
            if hasTelemetry {
                separator
                contextSegment
                separator
                telemetryCluster
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                            isExpanded.toggle()
                        }
                    }
            }

            Spacer(minLength: 8)

            agentSegment
            separator
            rightMark
            if !machineTelemetry.isEmpty {
                disclosure
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 16)   // lift content above home indicator
        .frame(height: 54, alignment: .top)
        .padding(.top, 0)
    }

    // MARK: - Segments

    private var statusSegment: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(LatsPalette.green)
                .frame(width: 6, height: 6)
                .shadow(color: .clear, radius: 0)
            Text(statusLabel.uppercased())
                .font(LatsFont.mono(9, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(LatsPalette.green.opacity(0.92))
        }
        .fixedSize()
    }

    private var holdHintSegment: some View {
        Text(holdHint)
            .font(LatsFont.mono(8))
            .tracking(0.4)
            .foregroundStyle(LatsPalette.textFaint)
            .fixedSize()
    }

    private var contextSegment: some View {
        Text(telemetry.contextLabel)
            .font(LatsFont.mono(9))
            .tracking(0.5)
            .foregroundStyle(LatsPalette.textDim)
            .lineLimit(1)
            .fixedSize()
    }

    private var telemetryCluster: some View {
        HStack(spacing: 7) {
            telemetryToken("\(telemetry.windows)w")
            middleDot
            telemetryToken("\(telemetry.displayIndex)/\(telemetry.displayCount)")
            middleDot
            telemetryToken("cpu \(telemetry.cpuPercent)%", tint: cpuTint)
            middleDot
            telemetryToken("mem \(telemetry.memPercent)%", tint: memTint)
            if let t = telemetry.tempCelsius {
                middleDot
                telemetryToken("\(t)°", tint: tempTint(t))
            }
        }
        .fixedSize()
    }

    private func telemetryToken(_ text: String, tint: Color = LatsPalette.textDim) -> some View {
        Text(text)
            .font(LatsFont.mono(9))
            .tracking(0.4)
            .foregroundStyle(tint)
    }

    private var middleDot: some View {
        Text("·")
            .font(LatsFont.mono(9))
            .foregroundStyle(LatsPalette.textFaint)
    }

    private var separator: some View {
        Rectangle()
            .fill(LatsPalette.hairline2)
            .frame(width: 1, height: 12)
    }

    private var agentSegment: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(agentDotTint)
                .frame(width: 5, height: 5)
            Text("agent \(agentLabel)")
                .font(LatsFont.mono(9, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(agentTextTint)
                .lineLimit(1)
        }
        .fixedSize()
    }

    private var rightMark: some View {
        HStack(spacing: 6) {
            Text(product)
                .font(LatsFont.mono(9))
                .tracking(0.5)
                .foregroundStyle(LatsPalette.textFaint)
            Text("·")
                .foregroundStyle(LatsPalette.textFaint)
            Text(versionLabel)
                .font(LatsFont.mono(9, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(LatsPalette.textDim)
        }
        .fixedSize()
    }

    private var disclosure: some View {
        Button {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                isExpanded.toggle()
            }
        } label: {
            Image(systemName: "chevron.up")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(LatsPalette.textDim)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(isExpanded ? 0.05 : 0))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Collapse telemetry" : "Expand telemetry")
    }

    // MARK: - Expanded strip

    private var expandedStrip: some View {
        VStack(spacing: 0) {
            Rectangle().fill(LatsPalette.hairline).frame(height: 1)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(machineTelemetry) { row in
                        MachineTelemetryCell(row: row)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }

    // MARK: - Tint helpers

    private var cpuTint: Color {
        switch telemetry.cpuPercent {
        case ..<60: return LatsPalette.textDim
        case 60..<85: return LatsPalette.amber
        default: return LatsPalette.red
        }
    }

    private var memTint: Color {
        switch telemetry.memPercent {
        case ..<70: return LatsPalette.textDim
        case 70..<92: return LatsPalette.amber
        default: return LatsPalette.red
        }
    }

    private func tempTint(_ t: Int) -> Color {
        switch t {
        case ..<55: return LatsPalette.textDim
        case 55..<75: return LatsPalette.amber
        default: return LatsPalette.red
        }
    }

    private var agentDotTint: Color {
        switch agentState {
        case .idle: return LatsPalette.green
        case .running: return LatsPalette.violet
        case .waiting: return LatsPalette.amber
        }
    }

    private var agentTextTint: Color {
        switch agentState {
        case .idle: return LatsPalette.green.opacity(0.9)
        case .running: return LatsPalette.violet
        case .waiting: return LatsPalette.amber
        }
    }

    private var agentLabel: String {
        switch agentState {
        case .idle: return "ready"
        case .running(let task): return task
        case .waiting(let msg): return msg
        }
    }
}

// MARK: - Expanded telemetry cell

private struct MachineTelemetryCell: View {
    let row: HomeBottomMachineTelemetry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(row.buildTint.color).frame(width: 5, height: 5)
                Text(row.name)
                    .font(LatsFont.mono(10, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(LatsPalette.text)
                    .lineLimit(1)
            }

            HStack(spacing: 7) {
                tokenView("cpu \(row.cpuPercent)%", tint: cpuTint)
                middleDot
                tokenView("mem \(row.memPercent)%", tint: memTint)
                middleDot
                tokenView("\(row.windows)w")
            }

            HStack(spacing: 6) {
                Image(systemName: "hammer")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(LatsPalette.textFaint)
                Text(row.buildState)
                    .font(LatsFont.mono(10))
                    .foregroundStyle(row.buildTint.color)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minWidth: 168, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(LatsPalette.hairline, lineWidth: 1)
        )
    }

    private func tokenView(_ text: String, tint: Color = LatsPalette.textDim) -> some View {
        Text(text)
            .font(LatsFont.mono(10))
            .tracking(0.3)
            .foregroundStyle(tint)
    }

    private var middleDot: some View {
        Text("·")
            .font(LatsFont.mono(10))
            .foregroundStyle(LatsPalette.textFaint)
    }

    private var cpuTint: Color {
        switch row.cpuPercent {
        case ..<60: return LatsPalette.textDim
        case 60..<85: return LatsPalette.amber
        default: return LatsPalette.red
        }
    }

    private var memTint: Color {
        switch row.memPercent {
        case ..<70: return LatsPalette.textDim
        case 70..<92: return LatsPalette.amber
        default: return LatsPalette.red
        }
    }
}

// MARK: - Previews

#Preview("Default · ready") {
    LatsBackground {
        VStack(spacing: 0) {
            Spacer()
            HomeBottomBar()
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Agent running") {
    LatsBackground {
        VStack(spacing: 0) {
            Spacer()
            HomeBottomBar(
                statusLabel: "ACTIVE",
                agentState: .running(task: "writing tile spec")
            )
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Hot machine") {
    LatsBackground {
        VStack(spacing: 0) {
            Spacer()
            HomeBottomBar(
                agentState: .waiting(message: "needs auth"),
                telemetry: HomeBottomTelemetry(
                    contextLabel: "studio ~ build",
                    windows: 32,
                    displayIndex: 2,
                    displayCount: 7,
                    cpuPercent: 91,
                    memPercent: 95,
                    tempCelsius: 78
                )
            )
        }
    }
    .preferredColorScheme(.dark)
}
