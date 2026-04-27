import SwiftUI

/// Adaptive grid of paired Macs. Each card carries live per-machine state
/// (scene, focused app, last action, agent, attention) so the user can
/// pick a target meaningfully — not just by name.
///
/// Adaptive: 1 = single rich card, 2 = split, 3-4 = 2x2 grid, 5+ = compact.
/// Tap → enter Deck for that machine.
///
/// Size budget: ~150-220pt depending on machine count.
struct HomeTargetsRow: View {
    let machines: [HomeMachine]
    var onEnterDeck: ((HomeMachine) -> Void)? = nil
    var onAttention: ((HomeMachine) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            LatsSectionLabel(text: "Machines")
            Spacer(minLength: 0)
            LatsBadge(text: "\(machines.count)", tint: LatsPalette.textDim)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch machines.count {
        case 0:
            LatsEmptyState(
                title: "No paired machines",
                subtitle: "Pair a Mac to see its live state here.",
                icon: "laptopcomputer.slash"
            )
        case 1:
            HomeTargetCard(
                machine: machines[0],
                emphasis: .full,
                onEnterDeck: onEnterDeck,
                onAttention: onAttention
            )
        case 2:
            HStack(spacing: 12) {
                ForEach(machines) { m in
                    HomeTargetCard(
                        machine: m,
                        emphasis: m.isForeground ? .deemphasized : .full,
                        onEnterDeck: onEnterDeck,
                        onAttention: onAttention
                    )
                }
            }
        default:
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 280, maximum: 420), spacing: 12)],
                spacing: 12
            ) {
                ForEach(machines) { m in
                    HomeTargetCard(
                        machine: m,
                        emphasis: m.isForeground ? .deemphasized : .full,
                        onEnterDeck: onEnterDeck,
                        onAttention: onAttention
                    )
                }
            }
        }
    }
}

// MARK: - Card

private enum HomeTargetEmphasis {
    case full          // background machines — primary focus of the row
    case deemphasized  // foreground machine — same card, lower contrast body
}

private struct HomeTargetCard: View {
    let machine: HomeMachine
    var emphasis: HomeTargetEmphasis = .full
    var onEnterDeck: ((HomeMachine) -> Void)? = nil
    var onAttention: ((HomeMachine) -> Void)? = nil

    var body: some View {
        Button(action: { onEnterDeck?(machine) }) {
            LatsCard(padding: 12, radius: 8) {
                VStack(alignment: .leading, spacing: 10) {
                    headerRow
                    identityBlock
                    LatsHairlineDivider()
                    bodyBlock
                    LatsHairlineDivider()
                    footerRow
                }
            }
        }
        .buttonStyle(.plain)
        .opacity(emphasis == .deemphasized ? 0.78 : 1.0)
    }

    // MARK: Header — icon, status, attention, chevron

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 10) {
            iconTile
            VStack(alignment: .leading, spacing: 3) {
                Text(machine.name)
                    .font(LatsFont.mono(13, weight: .semibold))
                    .foregroundStyle(bodyText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(machine.host)
                    .font(LatsFont.mono(10))
                    .foregroundStyle(LatsPalette.textDim)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 6) {
                    if machine.attentionCount > 0 {
                        attentionDot
                    }
                    LatsBadge(
                        text: machine.status.label,
                        tint: machine.status.tint,
                        dot: machine.status == .active
                    )
                }
                if let lat = machine.latencyMs, machine.status != .offline {
                    Text("\(lat)ms")
                        .font(LatsFont.mono(9))
                        .tracking(0.4)
                        .foregroundStyle(LatsPalette.textFaint)
                }
            }
        }
    }

    private var iconTile: some View {
        let tint = machine.status.tint
        return ZStack {
            RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.15))
            Image(systemName: machine.icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(tint)
        }
        .frame(width: 38, height: 38)
        .overlay(
            RoundedRectangle(cornerRadius: 8).stroke(tint.opacity(0.4), lineWidth: 1)
        )
    }

    private var attentionDot: some View {
        Button(action: { onAttention?(machine) }) {
            Text("\(machine.attentionCount)")
                .font(LatsFont.mono(9, weight: .bold))
                .foregroundStyle(LatsPalette.text)
                .padding(.horizontal, 5)
                .frame(minWidth: 16, minHeight: 14)
                .background(
                    RoundedRectangle(cornerRadius: 7).fill(LatsPalette.red.opacity(0.85))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7).stroke(LatsPalette.red, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(onAttention == nil)
    }

    // MARK: Identity — scene line

    @ViewBuilder
    private var identityBlock: some View {
        if let scene = machine.scene {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(LatsPalette.teal)
                Text(scene)
                    .font(LatsFont.ui(12, weight: .medium))
                    .foregroundStyle(bodyText)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        } else if machine.status == .offline {
            HStack(spacing: 6) {
                Image(systemName: "moon.zzz")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(LatsPalette.textFaint)
                Text("unreachable")
                    .font(LatsFont.mono(10))
                    .foregroundStyle(LatsPalette.textFaint)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Body — focused app + window, last action

    private var bodyBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            focusedRow
            lastActionRow
        }
    }

    @ViewBuilder
    private var focusedRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("FOCUS")
                .font(LatsFont.mono(9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(LatsPalette.textFaint)
                .frame(width: 44, alignment: .leading)
            if let app = machine.focusedApp {
                Text(app)
                    .font(LatsFont.mono(11, weight: .semibold))
                    .foregroundStyle(bodyText)
                    .lineLimit(1)
                if let win = machine.focusedWindow {
                    Text("·")
                        .font(LatsFont.mono(11))
                        .foregroundStyle(LatsPalette.textFaint)
                    Text(win)
                        .font(LatsFont.mono(11))
                        .foregroundStyle(bodyDim)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                Text("—")
                    .font(LatsFont.mono(11))
                    .foregroundStyle(LatsPalette.textFaint)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var lastActionRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("LAST")
                .font(LatsFont.mono(9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(LatsPalette.textFaint)
                .frame(width: 44, alignment: .leading)
            if let action = machine.lastAction {
                Text(action)
                    .font(LatsFont.mono(11))
                    .foregroundStyle(bodyText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let ago = machine.lastActionAgo {
                    Text("·")
                        .font(LatsFont.mono(11))
                        .foregroundStyle(LatsPalette.textFaint)
                    Text(ago)
                        .font(LatsFont.mono(10))
                        .foregroundStyle(bodyDim)
                }
            } else {
                Text(machine.lastActionAgo ?? "—")
                    .font(LatsFont.mono(11))
                    .foregroundStyle(LatsPalette.textFaint)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Footer — agent + chevron

    private var footerRow: some View {
        HStack(spacing: 8) {
            agentChip
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(emphasis == .deemphasized ? LatsPalette.textFaint : LatsPalette.textDim)
        }
    }

    private var agentChip: some View {
        let isRunning: Bool = {
            if case .running = machine.agentState { return true }
            return false
        }()
        let isWaiting: Bool = {
            if case .waiting = machine.agentState { return true }
            return false
        }()
        let tint = machine.agentState.tint

        return HStack(spacing: 6) {
            Text("AGENT")
                .font(LatsFont.mono(9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(LatsPalette.textFaint)
            if isRunning {
                AgentPulseDot(color: tint)
            } else {
                Circle().fill(tint.opacity(isWaiting ? 0.85 : 0.55)).frame(width: 5, height: 5)
            }
            Text(agentLabel)
                .font(LatsFont.mono(10, weight: isRunning ? .semibold : .regular))
                .foregroundStyle(isRunning ? tint : (isWaiting ? tint : LatsPalette.textDim))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var agentLabel: String {
        switch machine.agentState {
        case .idle: return "idle"
        case .running(let task): return "running · \(task)"
        case .waiting(let msg): return "waiting · \(msg)"
        }
    }

    // MARK: Emphasis-aware foregrounds

    private var bodyText: Color {
        emphasis == .deemphasized ? LatsPalette.textDim : LatsPalette.text
    }

    private var bodyDim: Color {
        emphasis == .deemphasized ? LatsPalette.textFaint : LatsPalette.textDim
    }
}

// MARK: - Agent pulse

private struct AgentPulseDot: View {
    let color: Color
    @State private var pulse: Bool = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .overlay(
                Circle()
                    .stroke(color.opacity(0.6), lineWidth: 1)
                    .scaleEffect(pulse ? 2.2 : 1.0)
                    .opacity(pulse ? 0.0 : 0.9)
            )
            .onAppear {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
    }
}

// MARK: - Previews

#Preview("Targets · 1") {
    LatsBackground {
        ScrollView {
            HomeTargetsRow(machines: HomeMock.fleetOne) { _ in }
                .padding(14)
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Targets · 2") {
    LatsBackground {
        ScrollView {
            HomeTargetsRow(machines: HomeMock.fleetTwo) { _ in }
                .padding(14)
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Targets · 4") {
    LatsBackground {
        ScrollView {
            HomeTargetsRow(machines: HomeMock.fleetFour) { _ in }
                .padding(14)
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Targets · empty") {
    LatsBackground {
        ScrollView {
            HomeTargetsRow(machines: HomeMock.fleetEmpty)
                .padding(14)
        }
    }
    .preferredColorScheme(.dark)
}
