import SwiftUI

/// Agent recipes — multi-step, may pause, may need watching. Distinct from
/// scenes (instant). Each row: play affordance, name, step preview, last
/// run, AGENT badge if agentic.
///
/// Size budget: ~280-380pt for ~4 rows.
struct HomeRoutinesList: View {
    let routines: [HomeRoutine]
    var onRun: ((HomeRoutine) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                LatsSectionLabel(text: "Routines")
                Spacer(minLength: 8)
                Text("multi-step · agent-assisted")
                    .font(LatsFont.mono(9))
                    .tracking(0.8)
                    .foregroundStyle(LatsPalette.textFaint)
            }

            if routines.isEmpty {
                LatsCard(padding: 14) {
                    Text("no routines yet")
                        .font(LatsFont.mono(10))
                        .foregroundStyle(LatsPalette.textFaint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(routines) { routine in
                        HomeRoutineRow(routine: routine, onRun: onRun)
                    }
                }
            }
        }
    }
}

private struct HomeRoutineRow: View {
    let routine: HomeRoutine
    var onRun: ((HomeRoutine) -> Void)?

    var body: some View {
        LatsCard(padding: 12) {
            HStack(alignment: .top, spacing: 12) {
                PlayAffordance { onRun?(routine) }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(routine.name)
                            .font(LatsFont.ui(13, weight: .semibold))
                            .foregroundStyle(LatsPalette.text)
                            .lineLimit(1)

                        if routine.isAgentic {
                            LatsBadge(text: "Agent", tint: LatsPalette.violet, dot: true)
                        }

                        Spacer(minLength: 8)

                        if let lastRun = routine.lastRun {
                            Text("last · \(lastRun)")
                                .font(LatsFont.mono(9))
                                .tracking(0.4)
                                .foregroundStyle(LatsPalette.textFaint)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(routine.stepPreview)
                            .font(LatsFont.mono(10))
                            .foregroundStyle(LatsPalette.textDim)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if let hotkey = routine.hotkey {
                            HotkeyPill(text: hotkey)
                        }
                    }
                }
            }
        }
    }
}

private struct PlayAffordance: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(LatsPalette.green.opacity(0.15))
                Circle()
                    .stroke(LatsPalette.green.opacity(0.45), lineWidth: 1)
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LatsPalette.green)
                    .offset(x: 1)
            }
            .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
    }
}

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

#Preview {
    LatsBackground {
        ScrollView {
            HomeRoutinesList(routines: HomeMock.routines) { routine in
                print("run", routine.name)
            }
            .padding(14)
        }
    }
    .preferredColorScheme(.dark)
}
