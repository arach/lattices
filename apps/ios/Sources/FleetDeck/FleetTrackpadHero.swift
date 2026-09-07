import DeckKit
import SwiftUI

// MARK: - Trackpad hero
//
// The deck's physical center: a trackpad the size of the job. It carries the
// frontmost window's thumbnail so you can see what your finger is about to
// move, and three modes — pointer, scroll, and drag window. Drag window is
// direct manipulation: touch grabs the frontmost window wherever it is and
// slides it by your finger's delta; no aiming at a title bar.

enum FleetTrackpadMode: String, CaseIterable {
    case pointer = "Pointer"
    case scroll = "Scroll"
    case dragWindow = "Drag window"
}

struct FleetTrackpadHero: View {
    let channel: FleetChannel?
    let onTrackpad: (DeckTrackpadEvent, Double, Double) -> Void
    let onWindowDrag: (Double, Double) -> Void

    @State private var mode: FleetTrackpadMode = .pointer
    @State private var crosshair: CGPoint?
    @State private var lastPoint: CGPoint?
    /// Finger translation while a window drag is live — drives the ghost.
    @State private var windowDragOffset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                FleetV6.wellBG

                ForEach(Array(brackets.enumerated()), id: \.offset) { _, alignment in
                    Color.clear.overlay(alignment: alignment) {
                        FleetHeroBracket(alignment: alignment)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }
                }

                Text("TRACKPAD")
                    .font(DeckTheme.caption())
                    .tracking(4.2)
                    .foregroundStyle(FleetV6.fg3)

                if let crosshair, mode != .dragWindow {
                    Rectangle().fill(FleetV6.crosshair)
                        .frame(width: 1)
                        .position(x: crosshair.x, y: proxy.size.height / 2)
                    Rectangle().fill(FleetV6.crosshair)
                        .frame(height: 1)
                        .position(x: proxy.size.width / 2, y: crosshair.y)
                }

                windowThumb(in: proxy.size)

                modePicker
                    .position(x: proxy.size.width / 2, y: proxy.size.height - 22)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .onTapGesture {
                if mode == .pointer { onTrackpad(.click, 0, 0) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: FleetV6.M.panelRadius, style: .continuous))
        .accessibilityLabel("Trackpad")
    }

    // MARK: Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                crosshair = value.location
                let dx = lastPoint.map { value.location.x - $0.x } ?? 0
                let dy = lastPoint.map { value.location.y - $0.y } ?? 0
                lastPoint = value.location

                switch mode {
                case .pointer:
                    onTrackpad(.move, dx, dy)
                case .scroll:
                    onTrackpad(.scroll, dx, dy)
                case .dragWindow:
                    windowDragOffset = value.translation
                    guard dx != 0 || dy != 0 else { return }
                    onWindowDrag(dx, dy)
                }
            }
            .onEnded { _ in
                crosshair = nil
                lastPoint = nil
                windowDragOffset = .zero
            }
    }

    // MARK: Window thumb

    /// The frontmost window rides on the pad. In drag mode it follows your
    /// finger and leaves a dashed ghost where it started — the same read as
    /// the study.
    @ViewBuilder
    private func windowThumb(in size: CGSize) -> some View {
        if let channel {
            let thumbSize = CGSize(width: min(300, size.width * 0.44), height: 86)
            let home = CGPoint(x: size.width / 2, y: 16 + thumbSize.height / 2)
            let dragging = mode == .dragWindow && windowDragOffset != .zero

            ZStack {
                if dragging {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .foregroundStyle(FleetV6.amber)
                        .frame(width: thumbSize.width, height: thumbSize.height)
                        .position(home)
                }

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 5) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle().fill(DeckTheme.hairlineStrong).frame(width: 7, height: 7)
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)

                    Divider().overlay(DeckTheme.hairline)

                    VStack(alignment: .leading, spacing: 5) {
                        ForEach([0.82, 0.64, 0.71], id: \.self) { fraction in
                            Capsule()
                                .fill(DeckTheme.hairline)
                                .frame(width: max(20, (thumbSize.width - 18) * fraction), height: 4)
                        }
                    }
                    .padding(9)
                }
                .frame(width: thumbSize.width, height: thumbSize.height, alignment: .topLeading)
                .background(FleetV6.cardBG)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(DeckTheme.hairlineStrong, lineWidth: 1)
                }
                .overlay(alignment: .bottomLeading) {
                    Text("\(channel.appName) — \(channel.fileName)")
                        .font(DeckTheme.caption())
                        .foregroundStyle(FleetV6.fg2)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(FleetV6.heroBG)
                        .clipShape(Capsule())
                        .overlay { Capsule().strokeBorder(DeckTheme.hairline, lineWidth: 1) }
                        .padding(6)
                }
                .position(
                    x: home.x + (dragging ? windowDragOffset.width : 0),
                    y: home.y + (dragging ? windowDragOffset.height : 0)
                )

                if dragging {
                    Text("dragging — \(channel.appName)")
                        .font(DeckTheme.caption())
                        .foregroundStyle(FleetV6.amber)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(DeckTheme.accent.opacity(0.14))
                        .clipShape(Capsule())
                        .overlay { Capsule().strokeBorder(FleetV6.amber, lineWidth: 1) }
                        .position(
                            x: min(size.width - 90, home.x + windowDragOffset.width + thumbSize.width / 2 + 80),
                            y: home.y + windowDragOffset.height
                        )
                }
            }
        }
    }

    // MARK: Modes

    private var modePicker: some View {
        HStack(spacing: 8) {
            ForEach(FleetTrackpadMode.allCases, id: \.self) { candidate in
                Button {
                    DeckTactileFeedback.shared.buttonPop()
                    mode = candidate
                } label: {
                    Text(candidate.rawValue)
                        .font(DeckTheme.caption())
                        .foregroundStyle(mode == candidate ? FleetV6.fg : FleetV6.fg2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(mode == candidate ? FleetV6.keycap : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var brackets: [Alignment] { [.topLeading, .topTrailing, .bottomLeading, .bottomTrailing] }
}

/// A 13pt corner bracket, open toward the middle of the pad.
private struct FleetHeroBracket: View {
    let alignment: Alignment

    private let size: CGFloat = 13
    private let weight: CGFloat = 1.5

    var body: some View {
        ZStack(alignment: alignment) {
            Color.clear.frame(width: size, height: size)
            Rectangle().fill(DeckTheme.hairlineStrong).frame(width: size, height: weight)
            Rectangle().fill(DeckTheme.hairlineStrong).frame(width: weight, height: size)
        }
        .frame(width: size, height: size)
    }
}
