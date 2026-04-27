import SwiftUI

/// Top chrome for Home. Carries product mark, fleet pills, agent activity,
/// settings. Tapping the pills row opens an inline accordion strip with
/// per-machine focused app + last-action data.
///
/// Size budget: ~40pt collapsed, ~120pt expanded.
struct HomeTopBar: View {
    let machines: [HomeMachine]
    var agentsRunning: Int = 0
    var onSettings: (() -> Void)? = nil
    var onPillTap: ((HomeMachine) -> Void)? = nil

    @State private var isExpanded: Bool = false

    private var orderedMachines: [HomeMachine] {
        machines.sorted { lhs, rhs in
            statusRank(lhs.status) < statusRank(rhs.status)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            collapsedBar
            if isExpanded {
                expandedStrip
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity
                        )
                    )
            }
        }
        .background(Color.black.opacity(isExpanded ? 0.28 : 0.22))
        .overlay(alignment: .bottom) {
            Rectangle().fill(LatsPalette.hairline).frame(height: 1)
        }
    }

    // MARK: - Collapsed row

    private var collapsedBar: some View {
        HStack(spacing: 12) {
            productMark

            // Pills sit between the mark and the trailing slot. Tapping anywhere
            // in this region toggles the accordion — pills themselves still
            // forward to onPillTap so the parent can route to the Deck.
            pillsRow

            Spacer(minLength: 6)

            if agentsRunning > 0 {
                agentBadge
            }

            disclosure
            settingsButton
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
    }

    private var productMark: some View {
        HStack(spacing: 8) {
            Text("LATS")
                .font(LatsFont.mono(11, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(LatsPalette.text)
            Text("·").foregroundStyle(LatsPalette.textFaint)
            Text("home")
                .font(LatsFont.mono(11))
                .tracking(1)
                .foregroundStyle(LatsPalette.textDim)
        }
        .fixedSize()
    }

    private var pillsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(orderedMachines) { machine in
                    Button {
                        onPillTap?(machine)
                    } label: {
                        FleetPill(machine: machine)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                isExpanded.toggle()
            }
        }
    }

    private var agentBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(LatsPalette.violet)
                .frame(width: 5, height: 5)
            Text("\(agentsRunning) agents")
                .font(LatsFont.mono(9, weight: .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
        }
        .foregroundStyle(LatsPalette.violet)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(LatsPalette.violet.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(LatsPalette.violet.opacity(0.34), lineWidth: 1)
        )
    }

    private var disclosure: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                isExpanded.toggle()
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(LatsPalette.textDim)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(isExpanded ? 0.05 : 0))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Collapse fleet detail" : "Expand fleet detail")
    }

    private var settingsButton: some View {
        Button { onSettings?() } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LatsPalette.textDim)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(LatsPalette.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .opacity(onSettings == nil ? 0.5 : 1)
        .disabled(onSettings == nil)
        .accessibilityLabel("Settings")
    }

    // MARK: - Expanded strip

    private var expandedStrip: some View {
        VStack(spacing: 0) {
            Rectangle().fill(LatsPalette.hairline).frame(height: 1)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(orderedMachines) { machine in
                        FleetDetailCell(machine: machine)
                            .onTapGesture { onPillTap?(machine) }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }

    // MARK: - Helpers

    private func statusRank(_ status: HomeMachineStatus) -> Int {
        switch status {
        case .active: return 0
        case .online: return 1
        case .standby: return 2
        case .offline: return 3
        }
    }
}

// MARK: - Pill

private struct FleetPill: View {
    let machine: HomeMachine

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(machine.status.tint)
                .frame(width: 6, height: 6)
            Text(machine.name)
                .font(LatsFont.mono(10, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(textColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(fillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(strokeColor, lineWidth: 1)
        )
        .fixedSize()
    }

    private var textColor: Color {
        machine.status == .offline ? LatsPalette.textFaint : LatsPalette.text
    }

    private var fillColor: Color {
        machine.status == .offline
            ? Color.white.opacity(0.025)
            : machine.status.tint.opacity(0.10)
    }

    private var strokeColor: Color {
        machine.status == .offline
            ? LatsPalette.hairline
            : machine.status.tint.opacity(0.32)
    }
}

// MARK: - Expanded cell

private struct FleetDetailCell: View {
    let machine: HomeMachine

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(machine.status.tint).frame(width: 6, height: 6)
                Text(machine.name)
                    .font(LatsFont.mono(10, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(LatsPalette.text)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                Image(systemName: focusIcon)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(LatsPalette.textFaint)
                Text(focusLabel)
                    .font(LatsFont.mono(10))
                    .foregroundStyle(focusColor)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(LatsPalette.textFaint)
                Text(actionLabel)
                    .font(LatsFont.mono(10))
                    .foregroundStyle(LatsPalette.textDim)
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
        .contentShape(Rectangle())
    }

    private var focusIcon: String {
        machine.focusedApp == nil ? "moon.zzz" : "app.dashed"
    }

    private var focusLabel: String {
        machine.focusedApp ?? "—"
    }

    private var focusColor: Color {
        machine.focusedApp == nil ? LatsPalette.textFaint : LatsPalette.text
    }

    private var actionLabel: String {
        switch (machine.lastAction, machine.lastActionAgo) {
        case let (.some(action), .some(ago)): return "\(action) · \(ago)"
        case let (.some(action), .none):      return action
        case let (.none, .some(ago)):         return ago
        default:                              return "no recent action"
        }
    }
}

// MARK: - Previews

#Preview("4 machines · agents") {
    LatsBackground {
        VStack(spacing: 0) {
            HomeTopBar(machines: HomeMock.fleetFour, agentsRunning: 2, onSettings: {})
            Spacer()
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("2 machines · no agents") {
    LatsBackground {
        VStack(spacing: 0) {
            HomeTopBar(machines: HomeMock.fleetTwo, agentsRunning: 0, onSettings: {})
            Spacer()
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("1 machine · no settings") {
    LatsBackground {
        VStack(spacing: 0) {
            HomeTopBar(machines: HomeMock.fleetOne, agentsRunning: 1)
            Spacer()
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Empty fleet") {
    LatsBackground {
        VStack(spacing: 0) {
            HomeTopBar(machines: HomeMock.fleetEmpty, agentsRunning: 0, onSettings: {})
            Spacer()
        }
    }
    .preferredColorScheme(.dark)
}
