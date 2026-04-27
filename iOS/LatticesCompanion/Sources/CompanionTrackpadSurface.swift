import DeckKit
import SwiftUI

struct CompanionTrackpadSurface: View {
    private enum InteractionMode: String, CaseIterable, Identifiable {
        case pointer
        case scroll

        var id: String { rawValue }

        var title: String {
            switch self {
            case .pointer:
                return "Pointer"
            case .scroll:
                return "Scroll"
            }
        }
    }

    let state: DeckTrackpadState
    let sendEvent: (DeckTrackpadEvent, Double, Double) -> Void

    @State private var interactionMode: InteractionMode = .pointer
    @State private var dragLocked = false
    @State private var lastLocation: CGPoint?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TRACKPAD")
                        .font(LatsFont.mono(9, weight: .bold))
                        .foregroundStyle(LatsPalette.textFaint)
                        .tracking(1.5)

                    Text(state.statusTitle)
                        .font(LatsFont.mono(14, weight: .semibold))
                        .foregroundStyle(LatsPalette.text)

                    if let detail = state.statusDetail, !detail.isEmpty {
                        Text(detail)
                            .font(LatsFont.mono(11))
                            .foregroundStyle(LatsPalette.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()

                Picker("Trackpad mode", selection: $interactionMode) {
                    ForEach(InteractionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .disabled(!state.isAvailable || !state.isEnabled)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(LatsPalette.bgEdge)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(state.isAvailable ? LatsPalette.hairline2 : LatsPalette.red.opacity(0.45), lineWidth: 1)
                    )

                trackpadGrid

                VStack(spacing: 8) {
                    Image(systemName: dragLocked ? "cursorarrow.motionlines.click" : "cursorarrow.motionlines")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(LatsPalette.green.opacity(0.8))

                    Text(interactionMode == .pointer ? "glide to move pointer" : "glide to scroll surface")
                        .font(LatsFont.mono(10, weight: .semibold))
                        .tracking(1.5)
                        .textCase(.uppercase)
                        .foregroundStyle(LatsPalette.textDim)

                    Text(dragLocked ? "drag lock active" : "tap · drag · pinch")
                        .font(LatsFont.mono(9))
                        .tracking(1)
                        .foregroundStyle(LatsPalette.textFaint)
                }
                .multilineTextAlignment(.center)
                .padding(20)
            }
            .frame(height: 240)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .gesture(trackpadGesture)
            .simultaneousGesture(
                TapGesture()
                    .onEnded {
                        guard state.isAvailable, state.isEnabled, !dragLocked else { return }
                        sendEvent(.click, 0, 0)
                    }
            )
            .allowsHitTesting(state.isAvailable && state.isEnabled)

            HStack(spacing: 10) {
                trackpadButton(title: "Click", icon: "cursorarrow.click", tint: .cyan.opacity(0.35), isActive: false) {
                    sendEvent(.click, 0, 0)
                }

                trackpadButton(title: "Right Click", icon: "cursorarrow.rays", tint: .white.opacity(0.12), isActive: false) {
                    sendEvent(.rightClick, 0, 0)
                }

                trackpadButton(
                    title: dragLocked ? "Release Drag" : "Drag Lock",
                    icon: dragLocked ? "lock.open.fill" : "lock.fill",
                    tint: .mint.opacity(0.28),
                    isActive: dragLocked
                ) {
                    toggleDragLock()
                }
            }
            .disabled(!state.isAvailable || !state.isEnabled)
        }
        .onDisappear {
            if dragLocked {
                sendEvent(.mouseUp, 0, 0)
                dragLocked = false
            }
        }
    }
}

private extension CompanionTrackpadSurface {
    var trackpadGrid: some View {
        GeometryReader { geometry in
            let size = geometry.size

            Path { path in
                let columnWidth = size.width / 6
                let rowHeight = size.height / 4

                for column in 1..<6 {
                    let x = CGFloat(column) * columnWidth
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }

                for row in 1..<4 {
                    let y = CGFloat(row) * rowHeight
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
            }
            .stroke(Color.white.opacity(0.06), style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
        }
        .padding(16)
    }

    var trackpadGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard state.isAvailable, state.isEnabled else { return }
                guard let previous = lastLocation else {
                    lastLocation = value.location
                    return
                }

                let dx = value.location.x - previous.x
                let dy = value.location.y - previous.y
                lastLocation = value.location

                guard abs(dx) > 0.2 || abs(dy) > 0.2 else { return }

                let scale = interactionMode == .pointer ? state.pointerScale : state.scrollScale
                let event: DeckTrackpadEvent
                if dragLocked {
                    event = .drag
                } else {
                    event = interactionMode == .pointer ? .move : .scroll
                }

                sendEvent(event, Double(dx) * scale, Double(dy) * scale)
            }
            .onEnded { _ in
                lastLocation = nil
            }
    }

    func toggleDragLock() {
        dragLocked.toggle()
        sendEvent(dragLocked ? .mouseDown : .mouseUp, 0, 0)
    }

    func trackpadButton(
        title: String,
        icon: String,
        tint: Color,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(LatsFont.mono(11, weight: .semibold))
                    .tracking(0.3)
            }
            .foregroundStyle(isActive ? tint : LatsPalette.textDim)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isActive ? tint.opacity(0.18) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isActive ? tint.opacity(0.5) : LatsPalette.hairline2, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
