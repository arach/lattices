import SwiftUI

// MARK: - Apply sequence (progressive grid placement)

enum ScreenMapApplyStepStatus: Equatable {
    case pending
    case active
    case done
}

struct ScreenMapApplyStep: Identifiable, Equatable {
    let id: UInt32
    let app: String
    let title: String
    var status: ScreenMapApplyStepStatus
}

/// Live state for a multi-window apply — drives the action rail and per-tile shimmer.
final class ScreenMapApplySequence: ObservableObject {
    @Published private(set) var steps: [ScreenMapApplyStep]
    @Published private(set) var phaseLabel: String
    let label: String

    init(label: String, windows: [(wid: UInt32, app: String, title: String)]) {
        self.label = label
        self.phaseLabel = "Preparing…"
        self.steps = windows.map {
            ScreenMapApplyStep(id: $0.wid, app: $0.app, title: $0.title, status: .pending)
        }
    }

    func setPhase(_ text: String) {
        phaseLabel = text
    }

    var total: Int { steps.count }
    var completedCount: Int { steps.filter { $0.status == .done }.count }
    var isFinished: Bool { completedCount == total }

    func status(for wid: UInt32) -> ScreenMapApplyStepStatus? {
        steps.first(where: { $0.id == wid })?.status
    }

    func begin(wid: UInt32) {
        phaseLabel = "Placing…"
        for i in steps.indices where steps[i].status == .active {
            steps[i].status = .done
        }
        guard let idx = steps.firstIndex(where: { $0.id == wid }) else { return }
        steps[idx].status = .active
    }

    func finishAll() {
        phaseLabel = "Done"
        for i in steps.indices {
            steps[i].status = .done
        }
    }

    func complete(wid: UInt32) {
        guard let idx = steps.firstIndex(where: { $0.id == wid }) else { return }
        steps[idx].status = .done
    }

    /// The tail of the queue — what's left plus the active step.
    var trail: [ScreenMapApplyStep] {
        let active = steps.filter { $0.status == .active }
        let pending = steps.filter { $0.status == .pending }
        return active + pending.prefix(5)
    }
}

// MARK: - Tile overlay

struct ScreenMapApplyTileOverlay: View {
    let status: ScreenMapApplyStepStatus

    var body: some View {
        GeometryReader { geo in
            let shape = RoundedRectangle(cornerRadius: 2)
            ZStack {
                switch status {
                case .pending:
                    shape
                        .strokeBorder(Palette.running.opacity(0.35), lineWidth: 1)
                        .background(shape.fill(Palette.running.opacity(0.06)))
                case .active:
                    shape
                        .fill(Palette.running.opacity(0.12))
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        let phase = CGFloat(t.truncatingRemainder(dividingBy: 1.1) / 1.1)
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Palette.running.opacity(0.45),
                                Color.clear,
                            ],
                            startPoint: UnitPoint(x: phase - 0.35, y: 0),
                            endPoint: UnitPoint(x: phase + 0.35, y: 1)
                        )
                        .mask(shape)
                    }
                    shape.strokeBorder(Palette.running.opacity(0.85), lineWidth: 1.25)
                case .done:
                    shape
                        .fill(Palette.running.opacity(0.22))
                        .overlay(
                            shape.strokeBorder(Palette.running.opacity(0.55), lineWidth: 0.75)
                        )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Action rail

struct ScreenMapApplySequenceRail: View {
    @ObservedObject var sequence: ScreenMapApplySequence

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.split.3x3")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Palette.running)
                VStack(alignment: .leading, spacing: 1) {
                    Text(sequence.label)
                        .font(Typo.monoBold(10))
                        .foregroundColor(Palette.text)
                    Text(sequence.phaseLabel)
                        .font(Typo.mono(8))
                        .foregroundColor(Palette.textMuted)
                }
                Spacer(minLength: 8)
                Text("\(sequence.completedCount)/\(sequence.total)")
                    .font(Typo.monoBold(10))
                    .foregroundColor(Palette.running)
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(sequence.trail) { step in
                    HStack(spacing: 6) {
                        stepIcon(step.status)
                        Text(step.app)
                            .font(Typo.mono(9))
                            .foregroundColor(step.status == .pending ? Palette.textDim : Palette.text)
                            .lineLimit(1)
                        if !step.title.isEmpty {
                            Text(step.title)
                                .font(Typo.mono(8))
                                .foregroundColor(Palette.textMuted)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.62))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Palette.running.opacity(0.28), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .frame(maxWidth: 320, alignment: .leading)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func stepIcon(_ status: ScreenMapApplyStepStatus) -> some View {
        switch status {
        case .pending:
            Circle()
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                .frame(width: 7, height: 7)
        case .active:
            Circle()
                .fill(Palette.running)
                .frame(width: 7, height: 7)
                .shadow(color: Palette.running.opacity(0.6), radius: 3)
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(Palette.running)
                .frame(width: 7, height: 7)
        }
    }
}