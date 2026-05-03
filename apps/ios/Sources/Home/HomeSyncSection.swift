import SwiftUI

/// Broadcast / fleet operations: sync clipboard, mirror project, pull repos,
/// DND everywhere, snapshot layouts. The "fan out across paired devices"
/// affordance — a primary iPad superpower because expressing "do this on
/// every Mac" is awkward from any one Mac and natural from the device that
/// already sees them all.
///
/// Structure:
///   Header   — "Sync" + dim subtitle
///   Targets  — chip row, multi-select, defaults to all online machines
///   Actions  — one row per HomeSyncAction with a green BROADCAST button
///
/// Size budget: ~360-460pt for 5 actions.
struct HomeSyncSection: View {
    let actions: [HomeSyncAction]
    let machines: [HomeMachine]
    var onBroadcast: ((HomeSyncAction, [HomeMachine]) -> Void)? = nil

    @State private var selectedIDs: Set<String>

    init(
        actions: [HomeSyncAction],
        machines: [HomeMachine],
        onBroadcast: ((HomeSyncAction, [HomeMachine]) -> Void)? = nil
    ) {
        self.actions = actions
        self.machines = machines
        self.onBroadcast = onBroadcast
        // Default: every reachable machine selected. Offline machines stay
        // visible (and toggleable) but aren't included in the default fan-out.
        let defaults = machines
            .filter { $0.status != .offline }
            .map(\.id)
        _selectedIDs = State(initialValue: Set(defaults))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if actions.isEmpty {
                LatsCard(padding: 14) {
                    Text("no broadcast actions yet")
                        .font(LatsFont.mono(10))
                        .foregroundStyle(LatsPalette.textFaint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                targetsRow
                actionsList
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            LatsSectionLabel(text: "Sync")
            Spacer(minLength: 8)
            Text("fan out across paired devices")
                .font(LatsFont.mono(9))
                .tracking(0.8)
                .foregroundStyle(LatsPalette.textFaint)
        }
    }

    // MARK: - Targets chip row

    private var targetsRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("TARGETS")
                .font(LatsFont.mono(9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(LatsPalette.textFaint)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(machines) { machine in
                        TargetChip(
                            machine: machine,
                            isSelected: selectedIDs.contains(machine.id),
                            onTap: { toggle(machine) }
                        )
                    }
                }
            }

            Spacer(minLength: 4)

            Text("\(selectedCount) of \(machines.count) selected")
                .font(LatsFont.mono(9))
                .tracking(0.5)
                .foregroundStyle(LatsPalette.textFaint)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var selectedCount: Int {
        selectedIDs.intersection(machines.map(\.id)).count
    }

    private func toggle(_ machine: HomeMachine) {
        if selectedIDs.contains(machine.id) {
            selectedIDs.remove(machine.id)
        } else {
            selectedIDs.insert(machine.id)
        }
    }

    private var selectedMachines: [HomeMachine] {
        machines.filter { selectedIDs.contains($0.id) }
    }

    // MARK: - Actions list

    private var actionsList: some View {
        VStack(spacing: 8) {
            ForEach(actions) { action in
                HomeSyncRow(
                    action: action,
                    canBroadcast: !selectedMachines.isEmpty,
                    onBroadcast: { onBroadcast?(action, selectedMachines) }
                )
            }
        }
    }
}

// MARK: - Target chip

private struct TargetChip: View {
    let machine: HomeMachine
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        let tint = machine.status.tint
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: machine.icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? tint : LatsPalette.textDim)
                Text(machine.name)
                    .font(LatsFont.mono(10, weight: isSelected ? .semibold : .regular))
                    .tracking(0.3)
                    .foregroundStyle(isSelected ? LatsPalette.text : LatsPalette.textDim)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                indicator(tint: tint)
            }
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? tint.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(
                        isSelected ? tint.opacity(0.45) : LatsPalette.hairline,
                        lineWidth: 1
                    )
            )
            .opacity(machine.status == .offline && !isSelected ? 0.6 : 1.0)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func indicator(tint: Color) -> some View {
        if isSelected {
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(tint)
        } else {
            Circle()
                .stroke(LatsPalette.hairline2, lineWidth: 1)
                .frame(width: 7, height: 7)
        }
    }
}

// MARK: - Action row

private struct HomeSyncRow: View {
    let action: HomeSyncAction
    let canBroadcast: Bool
    let onBroadcast: () -> Void

    var body: some View {
        LatsCard(padding: 12) {
            HStack(alignment: .center, spacing: 12) {
                iconTile

                VStack(alignment: .leading, spacing: 3) {
                    Text(action.title)
                        .font(LatsFont.ui(13, weight: .semibold))
                        .foregroundStyle(LatsPalette.text)
                        .lineLimit(1)
                    Text(action.subtitle)
                        .font(LatsFont.mono(10))
                        .foregroundStyle(LatsPalette.textDim)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 8)

                if let hotkey = action.hotkey {
                    HotkeyPill(text: hotkey)
                }

                LatsButton(
                    title: "BROADCAST",
                    icon: "arrow.up.right",
                    style: .primary(.green),
                    action: onBroadcast
                )
                .opacity(canBroadcast ? 1.0 : 0.5)
                .disabled(!canBroadcast)
            }
        }
    }

    private var iconTile: some View {
        let tint = LatsPalette.blue
        return ZStack {
            RoundedRectangle(cornerRadius: 7).fill(tint.opacity(0.15))
            Image(systemName: action.icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint)
        }
        .frame(width: 36, height: 36)
        .overlay(
            RoundedRectangle(cornerRadius: 7).stroke(tint.opacity(0.35), lineWidth: 1)
        )
    }
}

// MARK: - Hotkey pill

private struct HotkeyPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(LatsFont.mono(9, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(LatsPalette.textDim)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3).stroke(LatsPalette.hairline2, lineWidth: 1)
            )
            .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Preview

#Preview {
    LatsBackground {
        ScrollView {
            HomeSyncSection(
                actions: HomeMock.sync,
                machines: HomeMock.fleetFour
            ) { action, targets in
                print("broadcast", action.title, "→", targets.map(\.name))
            }
            .padding(14)
        }
    }
    .preferredColorScheme(.dark)
}
