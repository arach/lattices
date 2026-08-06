import SwiftUI

// MARK: - Agent console
//
// `.acon .mcard.console` — the raised card that carries one agent's whole story:
// who it is, what it is doing, how far it got, and — when it is blocked — the
// decision itself, answerable right here rather than somewhere else.

struct FleetAgentConsole: View {
    let channel: FleetChannel
    /// Attention queue position, e.g. "1 OF 2" above the question.
    let queuePosition: Int?
    let queueCount: Int
    let nextBlockerLabel: String?
    /// True right after this channel's decision was answered — the design swaps
    /// the muted output line for a green confirmation.
    let justResolved: Bool
    /// Marks the card that changed with corner ticks.
    let isRecent: Bool
    /// Console buttons the Mac on deck can service.
    let enabledActions: Set<FleetConsoleAction>
    let onChoose: (Int) -> Void
    let onDefer: () -> Void
    let onApprove: () -> Void
    let onSteer: () -> Void
    let onRecap: () -> Void

    var body: some View {
        FleetCard(hero: true, recent: isRecent) {
            VStack(alignment: .leading, spacing: 0) {
                FleetCardHead(
                    title: "agent console",
                    trailing: channel.state.label,
                    trailingColor: headTrailingColor
                )

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(channel.agentName)
                        .font(FleetV6.mono(21, .medium))
                        .foregroundStyle(FleetV6.fg)
                    stateChip
                }

                if channel.decision == nil {
                    Text(channel.task)
                        .font(FleetV6.mono(12.5))
                        .foregroundStyle(FleetV6.fg2)
                        .lineSpacing(2.5)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }

                steps.padding(.top, 12)

                if let decision = channel.decision {
                    FleetDecisionCard(
                        decision: decision,
                        queuePosition: queuePosition,
                        queueCount: queueCount,
                        nextBlockerLabel: nextBlockerLabel,
                        onChoose: onChoose,
                        onDefer: onDefer
                    )
                    .padding(.top, 11)
                } else if justResolved {
                    resolvedNote.padding(.top, 11)
                } else {
                    outputNote.padding(.top, 10)
                }

                if channel.decision == nil {
                    actionButtons.padding(.top, 11)
                    Spacer(minLength: 8)
                    stats
                } else {
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var headTrailingColor: Color {
        switch channel.state {
        case .run:  return FleetV6.green
        case .attn: return FleetV6.fg3
        case .idle: return FleetV6.fg4
        case .down: return FleetV6.red
        }
    }

    // `.ac-chip`
    private var stateChip: some View {
        Text("\(channel.channelLabel) · \(channel.deviceName.uppercased())")
            .font(FleetV6.mono(9, .medium))
            .tracking(1.26)
            .foregroundStyle(channel.state == .idle ? FleetV6.fg4 : FleetV6.fg3)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(channel.state == .idle ? Color.clear : Color.white.opacity(0.03))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(FleetV6.brk, lineWidth: 1)
                    }
            }
    }

    // `.ac-steps` — condensed to a single rollup line while a decision is open,
    // so the question is what the eye lands on.
    @ViewBuilder
    private var steps: some View {
        if channel.decision != nil {
            let blocked = channel.steps.first { $0.state == .blocked }?.text ?? "Waiting on you"
            let doneCount = channel.steps.filter { $0.state == .done }.count
            HStack(alignment: .center, spacing: 9) {
                FleetStepTick(state: .now)
                (
                    Text(blocked).foregroundColor(FleetV6.fg)
                        + Text(" · \(doneCount) steps done").foregroundColor(FleetV6.fg4)
                )
                .font(FleetV6.mono(11.5))
            }
        } else {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(channel.steps) { step in
                    HStack(alignment: .center, spacing: 9) {
                        FleetStepTick(state: step.state)
                        Text(step.text)
                            .font(FleetV6.mono(11.5))
                            .foregroundStyle(stepColor(step.state))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func stepColor(_ state: FleetStepState) -> Color {
        switch state {
        case .done:    return FleetV6.fg4
        case .now:     return FleetV6.fg
        case .blocked: return FleetV6.fg
        case .queued:  return FleetV6.fg3
        }
    }

    // `.ac-out`
    private var outputNote: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("›").foregroundStyle(FleetV6.fg4)
            Text(channel.output)
                .foregroundStyle(FleetV6.fg3)
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(FleetV6.mono(11))
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(FleetWellFill(radius: 4))
    }

    // `.ac-done`
    private var resolvedNote: some View {
        HStack(alignment: .top, spacing: 7) {
            Text("✓")
            Text(channel.output)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(FleetV6.mono(11))
        .foregroundStyle(FleetV6.green)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(FleetV6.green.opacity(0.07))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(FleetV6.green.opacity(0.3), lineWidth: 1)
                }
        }
    }

    // `.ac-btns`
    private var actionButtons: some View {
        HStack(spacing: 8) {
            FleetConsoleButton(
                symbol: "checkmark.circle",
                title: "Approve",
                tint: FleetV6.green,
                isEnabled: enabledActions.contains(.approve),
                action: onApprove
            )
            FleetConsoleButton(
                symbol: "slider.horizontal.3",
                title: "Steer",
                isEnabled: enabledActions.contains(.steer),
                action: onSteer
            )
            FleetConsoleButton(
                symbol: "text.alignleft",
                title: "Recap",
                isEnabled: enabledActions.contains(.recap),
                action: onRecap
            )
        }
    }

    // `.ac-stats`
    private var stats: some View {
        HStack(spacing: 0) {
            statPair("CPU", channel.cpu.map { "\($0)%" })
            Spacer(minLength: 6)
            statPair("MEM", channel.mem.map { "\($0)%" })
            Spacer(minLength: 6)
            statPair("NET", channel.latency)
            Spacer(minLength: 6)
            Text(channel.deviceName.uppercased())
                .font(FleetV6.mono(9.5, .medium))
                .tracking(0.95)
                .foregroundStyle(FleetV6.fg4)
                .lineLimit(1)
        }
        .padding(.top, 8)
        .overlay(alignment: .top) { FleetDottedRule() }
    }

    private func statPair(_ key: String, _ value: String?) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(FleetV6.mono(9.5, .medium))
                .tracking(0.95)
                .foregroundStyle(FleetV6.fg4)
            Text(value ?? "—")
                .font(FleetV6.mono(9.5))
                .monospacedDigit()
                .foregroundStyle(FleetV6.fg2)
        }
    }
}

// MARK: - Decision

/// `.ac-ask` — the inline decision. Answer it here; don't go look for it.
struct FleetDecisionCard: View {
    let decision: FleetDecision
    let queuePosition: Int?
    let queueCount: Int
    let nextBlockerLabel: String?
    let onChoose: (Int) -> Void
    let onDefer: () -> Void

    private var queueLabel: String {
        guard let queuePosition, queueCount > 0 else { return "NEEDS YOU" }
        return "NEEDS YOU · \(queuePosition) OF \(queueCount)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                FleetDot(color: FleetV6.amber, size: 5, glow: true)
                Text(queueLabel)
                    .font(FleetV6.mono(8.5, .medium))
                    .tracking(1.7)
                    .foregroundStyle(FleetV6.fg4)
            }
            .padding(.bottom, 6)

            // The one serif in the design — the question reads as a sentence,
            // not as instrumentation.
            Text(decision.question)
                .font(FleetV6.serif(14.5))
                .foregroundStyle(FleetV6.fg)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 7) {
                ForEach(Array(decision.options.enumerated()), id: \.element.id) { index, option in
                    FleetDecisionRow(option: option) { onChoose(index) }
                }
            }
            .padding(.top, 10)

            HStack {
                Button(action: onDefer) {
                    Text("ASK ME LATER")
                        .font(FleetV6.mono(9, .medium))
                        .tracking(1.08)
                        .foregroundStyle(FleetV6.fg4)
                }
                .buttonStyle(.plain)
                Spacer()
                if let nextBlockerLabel {
                    Text("NEXT → \(nextBlockerLabel)")
                        .font(FleetV6.mono(9, .medium))
                        .tracking(1.08)
                        .foregroundStyle(FleetV6.fg4)
                }
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 12)
        .padding(.top, 11)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(FleetWellFill(radius: 6))
    }
}

/// `.ask-opt` — a keycap-faced row: letter, label, verb.
private struct FleetDecisionRow: View {
    let option: FleetDecisionOption
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Text(option.key)
                    .font(FleetV6.mono(9.5))
                    .foregroundStyle(FleetV6.fg3)
                    .frame(width: 17, height: 17)
                    .background {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.white.opacity(0.03))
                            .overlay {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(FleetV6.brk, lineWidth: 1)
                            }
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(FleetV6.mono(12, .medium))
                        .tracking(0.24)
                        .foregroundStyle(FleetV6.fg)
                    if !option.detail.isEmpty {
                        Text(option.detail)
                            .font(FleetV6.mono(10))
                            .foregroundStyle(FleetV6.fg4)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(option.verb)
                    .font(FleetV6.mono(9, .medium))
                    .tracking(1.08)
                    .foregroundStyle(FleetV6.fg4)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background { FleetKeycapBackground(radius: 6) }
            .contentShape(Rectangle())
        }
        .buttonStyle(FleetPressStyle())
        .accessibilityLabel("\(option.title). \(option.detail)")
        .accessibilityHint(option.verb)
    }
}

// MARK: - Pieces

/// `.mh` — every card's head: title left, state right, dotted rule under.
struct FleetCardHead<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailingContent: () -> Trailing

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text(title)
                    .font(FleetV6.mono(12.5, .medium))
                    .foregroundStyle(FleetV6.fg)
                Spacer(minLength: 6)
                trailingContent()
            }
            FleetDottedRule()
        }
        .padding(.bottom, 10)
    }
}

extension FleetCardHead where Trailing == Text {
    init(title: String, trailing: String, trailingColor: Color = FleetV6.fg4) {
        self.title = title
        self.trailingContent = {
            Text(trailing)
                .font(FleetV6.mono(10, .medium))
                .tracking(1)
                .foregroundStyle(trailingColor)
        }
    }
}

/// `.ac-step .tick` — done is a filled check, now is an open ring with a dot,
/// queued is an empty ring.
struct FleetStepTick: View {
    let state: FleetStepState

    var body: some View {
        ZStack {
            Circle()
                .fill(state == .done ? Color.white.opacity(0.06) : .clear)
                .overlay { Circle().strokeBorder(ringColor, lineWidth: 1) }
            switch state {
            case .done:
                Image(systemName: "checkmark")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(FleetV6.fg4)
            case .now, .blocked:
                Circle().fill(FleetV6.fg2).frame(width: 6, height: 6)
            case .queued:
                EmptyView()
            }
        }
        .frame(width: 12, height: 12)
    }

    private var ringColor: Color {
        switch state {
        case .done:            return Color.white.opacity(0.22)
        case .now, .blocked:   return Color.white.opacity(0.5)
        case .queued:          return Color.white.opacity(0.18)
        }
    }
}

/// `.abtn`
struct FleetConsoleButton: View {
    let symbol: String
    let title: String
    var tint: Color = FleetV6.fg2
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 12, weight: .regular))
                Text(title).font(FleetV6.mono(11.5)).tracking(0.46)
            }
            .foregroundStyle(isEnabled ? tint : FleetV6.fg4)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background { FleetKeycapBackground(radius: 7) }
            .opacity(isEnabled ? 1 : 0.55)
            .contentShape(Rectangle())
        }
        .buttonStyle(FleetPressStyle())
        .disabled(!isEnabled)
    }
}

/// `--well-bg` used as a fill inside a card (the output note, the ask block).
struct FleetWellFill: ViewModifier {
    var radius: CGFloat

    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(FleetV6.wellBG)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.white.opacity(0.035)).frame(height: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
}

/// `:active { transform: translateY(1px) }` — every pressable face in the design
/// sinks by a point.
struct FleetPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed ? 1 : 0)
            .brightness(configuration.isPressed ? 0.04 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
