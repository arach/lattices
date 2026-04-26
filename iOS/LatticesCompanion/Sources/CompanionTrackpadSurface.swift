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
                VStack(alignment: .leading, spacing: 5) {
                    Text("TRACKPAD")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.62))
                        .tracking(1.3)

                    Text(state.statusTitle)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    if let detail = state.statusDetail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.74))
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
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.08), Color.white.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(state.isAvailable ? Color.white.opacity(0.14) : Color.red.opacity(0.28), lineWidth: 1)
                    )

                trackpadGrid

                VStack(spacing: 10) {
                    Image(systemName: dragLocked ? "cursorarrow.motionlines.click" : "cursorarrow.motionlines")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))

                    Text(interactionMode == .pointer ? "Glide to move the Mac pointer" : "Glide to scroll the frontmost surface")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(dragLocked ? "Drag lock is active." : "Tap below for click, right click, or drag lock.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.68))
                }
                .multilineTextAlignment(.center)
                .padding(20)
            }
            .frame(height: 240)
            .contentShape(RoundedRectangle(cornerRadius: 24))
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
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isActive ? tint.opacity(1.2) : tint)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isActive ? Color.white.opacity(0.28) : Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
