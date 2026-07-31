import SwiftUI

/// The roster of paired hosts. Each card carries live per-machine state
/// (scene, focused app, last action, agent, attention) so the user can pick a
/// target meaningfully — not just by name.
///
/// **The roster wants to be one row.** It is a rank of things you choose
/// between, and a rank reads as a rank when you can take it in at a glance.
/// So the layout holds the row and spends *density*: cards thin from the full
/// two-column card into a single-column one as the fleet grows, and only wrap
/// when even the compact card would be too narrow to say anything.
///
/// The previous rule did the opposite — a fixed 260pt minimum per card, which
/// on a 690pt row meant two columns and a third host stranded on its own line.
/// Holding card width constant and spending rows is the wrong trade for a
/// roster: three hosts on two rows reads as two groups.
///
/// Tap → enter Deck for that machine.
struct HomeTargetsRow: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let machines: [HomeMachine]
    /// How many unpaired Macs discovery can currently see. Shown on the add
    /// cell — this line is the whole replacement for the app auto-connecting to
    /// whatever it found: it still tells you it can see something, it just no
    /// longer acts on that by itself.
    var nearbyCandidateCount: Int = 0
    var onEnterDeck: ((HomeMachine) -> Void)? = nil
    var onEnterFleet: (() -> Void)? = nil
    var onAddHost: (() -> Void)? = nil
    var onAttention: ((HomeMachine) -> Void)? = nil

    /// Measured width of the roster. Zero until first layout, which is why
    /// every fit test below treats zero as "assume it fits" — the first frame
    /// should not flash a wrapped grid on its way to a row.
    @State private var rowWidth: CGFloat = 0

    /// On a narrow screen there is no room beside the cards, so the slot lies
    /// down into a thin strip rather than claiming a card's worth of height.
    private var slotIsHorizontal: Bool { horizontalSizeClass == .compact }

    // MARK: Fit thresholds
    //
    // Both are the width at which the card in question stops being able to say
    // what it is for, measured against its own contents rather than picked
    // round: `full` needs room for the 110pt gauge column plus a machine name
    // beside it; `compact` needs room for a name and a focused-app line.

    private let cardGap: CGFloat = 12
    private let uprightSlotWidth: CGFloat = 84
    private let fullCardMin: CGFloat = 268
    private let compactCardMin: CGFloat = 168

    /// Width each card gets if the whole roster sits on a single row.
    private var perCardWidth: CGFloat {
        guard !machines.isEmpty, rowWidth > 0 else { return .infinity }
        let slot = (onAddHost != nil && !slotIsHorizontal) ? uprightSlotWidth + cardGap : 0
        let gaps = CGFloat(machines.count - 1) * cardGap
        return (rowWidth - slot - gaps) / CGFloat(machines.count)
    }

    private var density: HomeTargetDensity {
        perCardWidth >= fullCardMin ? .full : .compact
    }

    private var fitsOneRow: Bool {
        perCardWidth >= compactCardMin
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content
            fleetDoor
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
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

    /// Machines, with the add slot alongside them.
    ///
    /// The slot sits *beside* the roster rather than under it: an empty bay is
    /// not worth a card's worth of height, and standing it up next to the real
    /// hosts is also what it means — there is room here for one more.
    @ViewBuilder
    private var content: some View {
        if machines.isEmpty {
            addSlot
        } else if fitsOneRow {
            singleRow
        } else if slotIsHorizontal {
            VStack(spacing: 12) {
                machineGrid
                addSlot
            }
        } else {
            HStack(alignment: .top, spacing: cardGap) {
                machineGrid
                addSlot
            }
        }
    }

    @ViewBuilder
    private var singleRow: some View {
        if slotIsHorizontal {
            VStack(spacing: 10) {
                HStack(alignment: .top, spacing: cardGap) { targetCards }
                addSlot
            }
        } else {
            HStack(alignment: .top, spacing: cardGap) {
                targetCards
                addSlot
            }
        }
    }

    /// Fallback for a fleet too large to rank on one row at this width. Cards
    /// are already at compact density here, so the grid minimum matches it.
    private var machineGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: compactCardMin, maximum: 420), spacing: cardGap)],
            spacing: cardGap
        ) {
            ForEach(machines) { m in
                HomeTargetCard(
                    machine: m,
                    emphasis: m.isForeground ? .deemphasized : .full,
                    density: .compact,
                    onEnterDeck: onEnterDeck,
                    onAttention: onAttention
                )
            }
        }
    }

    @ViewBuilder
    private var targetCards: some View {
        ForEach(machines) { machine in
            HomeTargetCard(
                machine: machine,
                emphasis: machine.isForeground ? .deemphasized : .full,
                density: density,
                onEnterDeck: onEnterDeck,
                onAttention: onAttention
            )
        }
    }

    @ViewBuilder
    private var addSlot: some View {
        if onAddHost != nil {
            HomeAddHostSlot(
                nearbyCount: nearbyCandidateCount,
                isHorizontal: slotIsHorizontal,
                onTap: onAddHost
            )
        }
    }

    // MARK: - The second door

    /// With one Mac there is nothing to switch between, so the fleet view only
    /// earns its place once there is a fleet.
    @ViewBuilder
    private var fleetDoor: some View {
        if machines.count >= 2, let onEnterFleet {
            HomeFleetDoor(machines: machines, onTap: onEnterFleet)
        }
    }
}

// MARK: - Fleet door

/// The way into the multi-host deck.
///
/// This used to be a 6pt-padded capsule in the section header, which is where
/// you put a filter — and it is not a filter, it is the surface where the whole
/// fleet is operable at once. A door that leads somewhere bigger than the page
/// it sits on should not be smaller than the page's smallest control.
///
/// It gets the app's one accent, applied twice (tile fill, hairline) and
/// nowhere else on Home, so it reads as *the* destination without the band
/// having to shout. The subtitle names what is behind the door rather than
/// repeating the title, because "Fleet Deck" alone does not tell a first-time
/// reader that it is where they act on every host at once.
private struct HomeFleetDoor: View {
    let machines: [HomeMachine]
    var onTap: () -> Void

    private var liveCount: Int {
        machines.filter { $0.status != .offline }.count
    }

    private var subtitle: String {
        let n = machines.count
        if liveCount == n {
            return "Watch and drive all \(n) hosts on one surface"
        }
        return "Watch and drive all \(n) hosts — \(liveCount) reachable now"
    }

    private var attentionTotal: Int {
        machines.reduce(0) { $0 + $1.attentionCount }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DeckTheme.Space.x12) {
                tile

                VStack(alignment: .leading, spacing: 2) {
                    Text("Fleet Deck")
                        .font(DeckTheme.title())
                        .foregroundStyle(DeckTheme.text)
                    Text(subtitle)
                        .font(DeckTheme.secondary())
                        .foregroundStyle(DeckTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if attentionTotal > 0 {
                    Text("\(attentionTotal) waiting")
                        .font(DeckTheme.caption(.medium))
                        .foregroundStyle(DeckTheme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(DeckTheme.accentFill))
                }

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DeckTheme.accent)
            }
            .padding(.horizontal, DeckTheme.Space.cardPadH)
            .padding(.vertical, DeckTheme.Space.cardPadV)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: DeckTheme.radiusCard, style: .continuous)
                    .fill(DeckTheme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DeckTheme.radiusCard, style: .continuous)
                    .stroke(DeckTheme.accent.opacity(0.30), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Fleet Deck for all \(machines.count) machines")
    }

    private var tile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DeckTheme.radiusCard, style: .continuous)
                .fill(DeckTheme.accentFill)
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(DeckTheme.accent)
        }
        .frame(width: 40, height: 40)
    }
}

// MARK: - Add slot

/// The way into pairing: an empty bay at the end of the roster.
///
/// Deliberately not a card. A card announces a host; this announces *room for*
/// one, so it takes a slot's width and none of a card's detail. It stands
/// upright beside the hosts where there is width for it, and lies down into a
/// thin strip where there isn't.
private struct HomeAddHostSlot: View {
    let nearbyCount: Int
    let isHorizontal: Bool
    var onTap: (() -> Void)? = nil

    /// Width of the upright slot — wide enough to tap, narrow enough that it
    /// never reads as a host that failed to load.
    private let slotWidth: CGFloat = 84

    private var nearbyLabel: String {
        switch nearbyCount {
        case 0:  return "none nearby"
        case 1:  return "1 nearby"
        default: return "\(nearbyCount) nearby"
        }
    }

    var body: some View {
        Button { onTap?() } label: {
            if isHorizontal { strip } else { upright }
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
        .accessibilityLabel("Add a host. \(nearbyLabel).")
    }

    private var upright: some View {
        VStack(spacing: 8) {
            plus
            Text("Add")
                .font(DeckTheme.caption(.medium))
                .foregroundStyle(DeckTheme.textSecondary)
            Text(nearbyLabel)
                .font(DeckTheme.caption())
                .foregroundStyle(DeckTheme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 12)
        .frame(width: slotWidth)
        .frame(minHeight: 140, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DeckTheme.card)
        )
    }

    private var strip: some View {
        HStack(spacing: 10) {
            plus
            Text("Add a host")
                .font(DeckTheme.secondary(.medium))
                .foregroundStyle(DeckTheme.textSecondary)
            Spacer(minLength: 0)
            Text(nearbyLabel)
                .font(DeckTheme.caption())
                .foregroundStyle(DeckTheme.textTertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DeckTheme.card)
        )
    }

    private var plus: some View {
        Image(systemName: "plus")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(DeckTheme.textSecondary)
            .frame(width: 26, height: 26)
    }
}

// MARK: - Card

private enum HomeTargetEmphasis {
    case full          // background machines — primary focus of the row
    case deemphasized  // foreground machine — same card, lower contrast body
}

/// How much card there is room for.
///
/// Not a style choice — a fit. `full` is the two-column card with the tall
/// gauge stack beside the text; `compact` folds it into one column and lays the
/// gauges flat, which is what fits once three or more hosts share a row.
enum HomeTargetDensity {
    case full
    case compact
}

private struct HomeTargetCard: View {
    let machine: HomeMachine
    var emphasis: HomeTargetEmphasis = .full
    var density: HomeTargetDensity = .full
    var onEnterDeck: ((HomeMachine) -> Void)? = nil
    var onAttention: ((HomeMachine) -> Void)? = nil

    /// Shared minimum card height per density. Picked so the gauges have room
    /// to breathe and offline cards reserve the same space — geometry stays
    /// identical regardless of state, so a host going dark never reflows the row.
    private var cardMinHeight: CGFloat {
        density == .full ? 156 : 140
    }

    var body: some View {
        Button(action: { onEnterDeck?(machine) }) {
            LatsCard(padding: 12, radius: 8) {
                Group {
                    switch density {
                    case .full:    fullBody
                    case .compact: compactBody
                    }
                }
                .frame(minHeight: cardMinHeight)
            }
        }
        .buttonStyle(.plain)
        .opacity(emphasis == .deemphasized ? 0.78 : 1.0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(machine.name), \(machine.status.label)")
    }

    private func hasGaugeContent(_ m: HomeMachineMetrics) -> Bool {
        m.cpuPercent != nil
            || m.gpuPercent != nil
            || m.memoryPercent != nil
            || m.thermalPercent != nil
    }

    private var gauges: HomeMachineMetrics? {
        guard let m = machine.metrics, hasGaugeContent(m) else { return nil }
        return m
    }

    // MARK: Full — two columns

    private var fullBody: some View {
        HStack(alignment: .top, spacing: 14) {
            leftColumn
            rightColumn
        }
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            nameRow
            identityBlock
            metadataBlock
            Spacer(minLength: 0)
            footerRow
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var nameRow: some View {
        HStack(spacing: 10) {
            iconTile(size: 38, glyph: 18)
            Text(machine.name)
                .font(DeckTheme.body(.medium))
                .foregroundStyle(bodyText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var rightColumn: some View {
        VStack(alignment: .trailing, spacing: 10) {
            statusStack

            if let metrics = gauges {
                Spacer(minLength: 4)
                HomeMachineGauges(metrics: metrics, barHeight: 80)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(width: 110, alignment: .trailing)
    }

    private var statusStack: some View {
        VStack(alignment: .trailing, spacing: 4) {
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
                    .font(DeckTheme.caption())
                    .foregroundStyle(DeckTheme.textTertiary)
            }
        }
    }

    // MARK: Compact — one column
    //
    // The status badge moves down to the footer rather than competing with the
    // name for a ~170pt row, and the gauges lie flat under the text where the
    // full card stands them up beside it. Nothing is dropped except the latency
    // line, which has no producer yet anyway.

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            compactNameRow
            identityBlock
            metadataBlock
            Spacer(minLength: 0)
            if let metrics = gauges {
                HomeMachineGauges(metrics: metrics, barHeight: 26)
            }
            compactFooterRow
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var compactNameRow: some View {
        HStack(spacing: 8) {
            iconTile(size: 30, glyph: 15)
            Text(machine.name)
                .font(DeckTheme.body(.medium))
                .foregroundStyle(bodyText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if machine.attentionCount > 0 {
                attentionDot
            }
        }
    }

    private var compactFooterRow: some View {
        HStack(spacing: 8) {
            LatsBadge(
                text: machine.status.label,
                tint: machine.status.tint,
                dot: machine.status == .active
            )
            agentChip
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(emphasis == .deemphasized ? DeckTheme.textTertiary : DeckTheme.textSecondary)
        }
    }

    // MARK: Metadata — focus/last for live targets, paired info for offline

    @ViewBuilder
    private var metadataBlock: some View {
        switch machine.status {
        case .offline:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Paired \(machine.lastActionAgo ?? "—") ago")
                    .font(DeckTheme.secondary())
                    .foregroundStyle(DeckTheme.textTertiary)
                Spacer(minLength: 0)
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                focusedRow
                if density == .full {
                    lastActionRow
                }
            }
        }
    }

    private func iconTile(size: CGFloat, glyph: CGFloat) -> some View {
        let tint = machine.status.tint
        return ZStack {
            RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.15))
            Image(systemName: machine.icon)
                .font(.system(size: glyph, weight: .regular))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: 8).stroke(tint.opacity(0.4), lineWidth: 1)
        )
    }

    private var attentionDot: some View {
        Button(action: { onAttention?(machine) }) {
            Text("\(machine.attentionCount)")
                .font(DeckTheme.caption(.semibold))
                .foregroundStyle(DeckTheme.text)
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
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DeckTheme.textSecondary)
                Text(scene)
                    .font(DeckTheme.secondary(.medium))
                    .foregroundStyle(bodyText)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        } else if machine.status == .offline {
            HStack(spacing: 6) {
                Image(systemName: "moon.zzz")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(LatsPalette.textFaint)
                Text("Unreachable")
                    .font(DeckTheme.secondary())
                    .foregroundStyle(DeckTheme.textTertiary)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Focused app + last action rows (active/online machines)

    @ViewBuilder
    private var focusedRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let app = machine.focusedApp {
                Text(app)
                    .font(DeckTheme.secondary(.medium))
                    .foregroundStyle(bodyText)
                    .lineLimit(1)
                if let win = machine.focusedWindow, density == .full {
                    Text("·")
                        .font(DeckTheme.secondary())
                        .foregroundStyle(DeckTheme.textTertiary)
                    Text(win)
                        .font(DeckTheme.secondary())
                        .foregroundStyle(bodyDim)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                Text("Nothing focused")
                    .font(DeckTheme.secondary())
                    .foregroundStyle(DeckTheme.textTertiary)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var lastActionRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let action = machine.lastAction {
                Text(action)
                    .font(DeckTheme.caption())
                    .foregroundStyle(DeckTheme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let ago = machine.lastActionAgo {
                    Text("· \(ago)")
                        .font(DeckTheme.caption())
                        .foregroundStyle(DeckTheme.textTertiary)
                }
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
                .foregroundStyle(emphasis == .deemphasized ? DeckTheme.textTertiary : DeckTheme.textSecondary)
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
            if isRunning {
                AgentPulseDot(color: tint)
            } else {
                Circle().fill(tint.opacity(isWaiting ? 0.85 : 0.55)).frame(width: 5, height: 5)
            }
            Text(agentLabel)
                .font(DeckTheme.caption(isRunning ? .medium : .regular))
                .foregroundStyle(isRunning ? tint : (isWaiting ? tint : LatsPalette.textDim))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var agentLabel: String {
        switch machine.agentState {
        case .idle: return "idle"
        case .running(let task): return density == .full ? "running · \(task)" : "running"
        case .waiting(let msg):  return density == .full ? "waiting · \(msg)"  : "waiting"
        }
    }

    // MARK: Emphasis-aware foregrounds

    private var bodyText: Color {
        emphasis == .deemphasized ? DeckTheme.textSecondary : DeckTheme.text
    }

    private var bodyDim: Color {
        emphasis == .deemphasized ? DeckTheme.textTertiary : DeckTheme.textSecondary
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
            HomeTargetsRow(machines: HomeMock.fleetOne, onEnterDeck: { _ in }, onEnterFleet: {}, onAddHost: {})
                .padding(14)
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Targets · 2") {
    LatsBackground {
        ScrollView {
            HomeTargetsRow(machines: HomeMock.fleetTwo, onEnterDeck: { _ in }, onEnterFleet: {}, onAddHost: {})
                .padding(14)
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Targets · 3") {
    LatsBackground {
        ScrollView {
            HomeTargetsRow(
                machines: Array(HomeMock.fleetFour.prefix(3)),
                onEnterDeck: { _ in }, onEnterFleet: {}, onAddHost: {}
            )
            .padding(14)
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Targets · 4") {
    LatsBackground {
        ScrollView {
            HomeTargetsRow(machines: HomeMock.fleetFour, onEnterDeck: { _ in }, onEnterFleet: {}, onAddHost: {})
                .padding(14)
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Targets · empty") {
    LatsBackground {
        ScrollView {
            HomeTargetsRow(machines: HomeMock.fleetEmpty, onAddHost: {})
                .padding(14)
        }
    }
    .preferredColorScheme(.dark)
}
