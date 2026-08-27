import SwiftUI

struct ActionSessionTimelineView: View {
    enum AnchorInteraction {
        case none
        case point
        case range
    }

    let currentTimeSeconds: Double
    let durationSeconds: Double
    let draftStartTimeSeconds: Double?
    let draftEndTimeSeconds: Double?
    let feedbackItems: [ActionSessionFeedbackDocument.Item]
    let timelineZoom: Double
    let windowStartTimeSeconds: Double
    let snapToTenth: Bool
    let anchorInteraction: AnchorInteraction
    let onSeek: (Double) -> Void
    let onWindowStartChange: (Double) -> Void
    let onCreatePointAnchor: (Double) -> Void
    let onCreateRangeAnchor: (Double, Double) -> Void

    private let markerAreaHeight: CGFloat = 74
    private let railHeight: CGFloat = 4
    private let railHitHeight: CGFloat = 30
    private let laneLabelWidth: CGFloat = 60
    private let laneGroupHeight: CGFloat = 22
    private let subLanesPerKind = 2

    @State private var dragStartX: CGFloat?
    @State private var dragCurrentX: CGFloat?
    @State private var navigatorDragOriginStart: Double?
    @State private var navigatorDragOriginX: CGFloat?

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let currentX = xPosition(for: currentTimeSeconds, width: width)
            let markerLayouts = markerLayouts(for: width)

            VStack(alignment: .leading, spacing: 12) {
                seekRail(width: width, currentX: currentX)
                if durationSeconds > 0 {
                    timeScale(width: width)
                }
                markerStrip(width: width, markerLayouts: markerLayouts)
                if durationSeconds > 0 {
                    windowNavigator(width: width)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: durationSeconds > 0 ? 162 : 122)
    }

    private func markerStrip(width: CGFloat, markerLayouts: [TimelineMarkerLayout]) -> some View {
        ZStack(alignment: .topLeading) {
            ActionChamferedShape(cornerCut: 3)
                .fill(StageHUDTheme.reviewPanelRaised)
                .overlay(
                    ActionChamferedShape(cornerCut: 3)
                        .stroke(StageHUDTheme.reviewStrokeSoft, lineWidth: 1)
                )

            laneGuides(width: width)

            ForEach(markerLayouts) { marker in
                Button {
                    onSeek(marker.item.startTimeSeconds)
                } label: {
                    markerView(marker)
                }
                .buttonStyle(.plain)
                .help(markerHelpText(marker.item))
                .offset(x: marker.originX, y: marker.y)
            }
        }
        .frame(width: width, height: markerAreaHeight)
    }

    private func laneGuides(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(MarkerKind.allCases, id: \.self) { kind in
                let top = laneTop(kind)

                Rectangle()
                    .fill(StageHUDTheme.reviewStrokeSoft.opacity(0.65))
                    .frame(width: max(width - laneLabelWidth - 10, 0), height: 1)
                    .offset(x: laneLabelWidth + 6, y: top + laneGroupHeight - 2)

                Text(kind.label.uppercased())
                    .font(ActionType.mono(10, weight: .semibold))
                    .foregroundStyle(StageHUDTheme.textMuted)
                    .frame(width: laneLabelWidth - 8, alignment: .leading)
                    .offset(x: 8, y: top + 3)
            }
        }
    }

    @ViewBuilder
    private func markerView(_ marker: TimelineMarkerLayout) -> some View {
        switch marker.kind {
        case .point:
            HStack(spacing: 4) {
                Image(systemName: "mappin.circle.fill")
                    .font(ActionIcon.micro)
                Text("\(marker.index + 1)")
                    .font(ActionType.mono(10, weight: .bold))
            }
            .foregroundStyle(marker.tint)
            .padding(.horizontal, 6)
            .frame(width: marker.width, height: 16)
            .background(StageHUDTheme.reviewPanel)
            .overlay(
                    ActionChamferedShape(cornerCut: 3)
                        .stroke(marker.tint.opacity(0.55), lineWidth: 1)
            )
            .clipShape(ActionChamferedShape(cornerCut: 3))
        case .range:
            HStack(spacing: 4) {
                Image(systemName: "rectangle.inset.filled")
                    .font(ActionIcon.micro)
                Text("\(marker.index + 1)")
                    .font(ActionType.mono(10, weight: .bold))
            }
            .foregroundStyle(marker.tint)
            .frame(width: marker.width, height: 16)
            .background(marker.tint.opacity(0.18))
            .overlay(
                    ActionChamferedShape(cornerCut: 3)
                        .stroke(marker.tint.opacity(0.68), lineWidth: 1)
            )
            .clipShape(ActionChamferedShape(cornerCut: 3))
        case .region:
            HStack(spacing: 4) {
                Image(systemName: "scope")
                    .font(ActionIcon.micro)
                Text("\(marker.index + 1)")
                    .font(ActionType.mono(10, weight: .bold))
            }
            .foregroundStyle(marker.tint)
            .padding(.horizontal, 6)
            .frame(width: marker.width, height: 16)
            .background(StageHUDTheme.reviewPanel)
            .overlay(
                    ActionChamferedShape(cornerCut: 3)
                        .stroke(marker.tint.opacity(0.6), lineWidth: 1)
            )
            .clipShape(ActionChamferedShape(cornerCut: 3))
        }
    }

    private func seekRail(width: CGFloat, currentX: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Timeline")
                    .font(ActionType.mono(10, weight: .semibold))
                    .foregroundStyle(StageHUDTheme.textMuted)
                Spacer()
                if durationSeconds > 0 {
                    Text(formattedTimeForRail(currentTimeSeconds))
                        .font(ActionType.mono(11, weight: .semibold))
                        .foregroundStyle(StageHUDTheme.textPrimary)
                } else {
                    Text("Duration pending")
                        .font(ActionType.mono(10, weight: .regular))
                        .foregroundStyle(StageHUDTheme.textMuted)
                }
            }

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(StageHUDTheme.reviewStrokeStrong.opacity(0.95))
                    .frame(height: railHeight)

                tickMarks(width: width)

                Capsule(style: .continuous)
                    .fill(StageHUDTheme.reviewAccent)
                    .frame(width: max(currentX, 2), height: railHeight)

                if let draftStartTimeSeconds {
                    draftOverlay(width: width, start: draftStartTimeSeconds, end: draftEndTimeSeconds)
                }

                if let dragRange = dragRange(width: width), anchorInteraction == .range {
                    Capsule(style: .continuous)
                        .fill(StageHUDTheme.reviewAccentMuted)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(StageHUDTheme.reviewAccent.opacity(0.8), lineWidth: 1)
                        )
                        .frame(width: max(dragRange.end - dragRange.start, 2), height: railHeight + 4)
                        .offset(x: dragRange.start, y: -2)
                }

                Circle()
                    .fill(StageHUDTheme.reviewPanelRaised)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Circle()
                            .stroke(StageHUDTheme.reviewAccent.opacity(0.72), lineWidth: 1.2)
                    )
                    .overlay(
                        Circle()
                            .fill(StageHUDTheme.reviewAccent)
                            .frame(width: 4, height: 4)
                    )
                    .shadow(color: StageHUDTheme.panelShadow.opacity(0.65), radius: 2, x: 0, y: 1)
                    .offset(x: min(max(currentX - 7, 0), max(width - 14, 0)), y: -4)
            }
        }
        .frame(width: width, height: railHitHeight, alignment: .topLeading)
        .contentShape(Rectangle())
        .highPriorityGesture(scrubGesture(width: width))
        .background(
            ActionChamferedShape(cornerCut: 3)
                .fill(StageHUDTheme.reviewPanelRaised.opacity(0.7))
        )
        .overlay(
            ActionChamferedShape(cornerCut: 3)
                .stroke(StageHUDTheme.reviewStrokeSoft, lineWidth: 1)
        )
    }

    private func timeScale(width: CGFloat) -> some View {
        let start = clampedWindowStartSeconds
        let middle = clampedWindowStartSeconds + (visibleDurationSeconds * 0.5)
        let end = min(clampedWindowStartSeconds + visibleDurationSeconds, durationSeconds)
        return HStack {
            Text(formattedTimeForRail(start))
            Spacer()
            Text(formattedTimeForRail(max(middle, 0)))
            Spacer()
            Text(formattedTimeForRail(max(end, 0)))
        }
        .font(ActionType.mono(10, weight: .medium))
        .foregroundStyle(StageHUDTheme.textMuted)
        .frame(width: width)
    }

    private func windowNavigator(width: CGFloat) -> some View {
        let maxStart = max(durationSeconds - visibleDurationSeconds, 0)
        let trackWidth = max(width, 1)
        let handleWidth = durationSeconds > 0
            ? max((visibleDurationSeconds / durationSeconds) * trackWidth, 24)
            : trackWidth
        let travel = max(trackWidth - handleWidth, 0)
        let progress = maxStart > 0 ? clampedWindowStartSeconds / maxStart : 0
        let handleX = CGFloat(progress) * travel

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Window Navigator")
                    .font(ActionType.mono(10, weight: .semibold))
                    .foregroundStyle(StageHUDTheme.textMuted)
                Spacer()
                Text("\(formattedTime(clampedWindowStartSeconds)) → \(formattedTime(min(clampedWindowStartSeconds + visibleDurationSeconds, durationSeconds)))")
                    .font(ActionType.mono(10, weight: .regular))
                    .foregroundStyle(StageHUDTheme.textMuted)
            }

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(StageHUDTheme.reviewStrokeSoft.opacity(0.8))
                    .frame(height: 12)

                Capsule(style: .continuous)
                    .fill(StageHUDTheme.reviewAccentMuted)
                    .frame(width: handleWidth, height: 12)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(StageHUDTheme.reviewAccent.opacity(0.65), lineWidth: 1)
                    )
                    .offset(x: handleX)
                    .highPriorityGesture(navigatorDragGesture(trackWidth: trackWidth, handleWidth: handleWidth))
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        guard maxStart > 0 else { return }
                        let ratio = max(0, min(Double(value.location.x / trackWidth), 1))
                        let centered = (ratio * durationSeconds) - (visibleDurationSeconds / 2)
                        onWindowStartChange(max(0, min(centered, maxStart)))
                    }
            )
        }
        .padding(.horizontal, 2)
    }

    private func tickMarks(width: CGFloat) -> some View {
        let tickCount = 12
        return HStack(spacing: 0) {
            ForEach(0...tickCount, id: \.self) { index in
                Rectangle()
                    .fill(StageHUDTheme.reviewPanel.opacity(index.isMultiple(of: 3) ? 0.55 : 0.32))
                    .frame(width: 1, height: index.isMultiple(of: 3) ? 11 : 7)
                if index < tickCount {
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(width: width, height: railHeight)
        .padding(.horizontal, 4)
    }

    private func scrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStartX == nil {
                    dragStartX = value.startLocation.x
                }
                dragCurrentX = value.location.x

                if anchorInteraction == .none || anchorInteraction == .point {
                    onSeek(quantized(seconds(for: value.location.x, width: width)))
                }
            }
            .onEnded { value in
                defer {
                    dragStartX = nil
                    dragCurrentX = nil
                }

                let endSeconds = quantized(seconds(for: value.location.x, width: width))
                let startX = dragStartX ?? value.startLocation.x
                let delta = abs(value.location.x - startX)

                switch anchorInteraction {
                case .none:
                    onSeek(endSeconds)
                case .point:
                    onSeek(endSeconds)
                    if delta <= 6 {
                        onCreatePointAnchor(endSeconds)
                    }
                case .range:
                    if delta <= 6 {
                        onSeek(endSeconds)
                    } else {
                        let startSeconds = quantized(seconds(for: min(startX, value.location.x), width: width))
                        let finalSeconds = quantized(seconds(for: max(startX, value.location.x), width: width))
                        onCreateRangeAnchor(startSeconds, finalSeconds)
                        onSeek(finalSeconds)
                    }
                }
            }
    }

    private func navigatorDragGesture(trackWidth: CGFloat, handleWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let maxStart = max(durationSeconds - visibleDurationSeconds, 0)
                guard maxStart > 0 else { return }

                if navigatorDragOriginStart == nil {
                    navigatorDragOriginStart = clampedWindowStartSeconds
                    navigatorDragOriginX = value.startLocation.x
                }

                let startX = navigatorDragOriginX ?? value.startLocation.x
                let deltaX = value.location.x - startX
                let travel = max(trackWidth - handleWidth, 1)
                let deltaRatio = Double(deltaX / travel)
                let deltaSeconds = deltaRatio * maxStart
                let baseline = navigatorDragOriginStart ?? clampedWindowStartSeconds
                let next = max(0, min(baseline + deltaSeconds, maxStart))
                onWindowStartChange(next)
            }
            .onEnded { _ in
                navigatorDragOriginStart = nil
                navigatorDragOriginX = nil
            }
    }

    @ViewBuilder
    private func draftOverlay(width: CGFloat, start: Double, end: Double?) -> some View {
        let startX = xPosition(for: start, width: width)
        if let end {
            let endX = xPosition(for: end, width: width)
            Capsule(style: .continuous)
                .fill(StageHUDTheme.reviewAccentMuted)
                .frame(width: max(endX - startX, 2), height: railHeight + 2)
                .offset(x: startX, y: -1)
        } else {
            Rectangle()
                .fill(StageHUDTheme.reviewAccent.opacity(0.82))
                .frame(width: 2, height: railHeight + 4)
                .offset(x: max(0, min(startX, width - 2)), y: -2)
        }
    }

    private func markerLayouts(for width: CGFloat) -> [TimelineMarkerLayout] {
        let sorted = feedbackItems.sorted { lhs, rhs in
            lhs.startTimeSeconds < rhs.startTimeSeconds
        }

        let plotWidth = max(width - laneLabelWidth - 10, 40)
        var lanePositions: [MarkerKind: [CGFloat]] = Dictionary(uniqueKeysWithValues: MarkerKind.allCases.map { kind in
            (kind, Array(repeating: -CGFloat.infinity, count: subLanesPerKind))
        })
        let minimumGap = max(plotWidth * 0.08, 56)

        return sorted.enumerated().compactMap { index, item in
            let kind = markerKind(for: item)
            let startNormalized = normalizedUnclamped(item.startTimeSeconds)
            let endNormalized = item.endTimeSeconds.map(normalizedUnclamped)

            let isVisible: Bool
            if let endNormalized {
                isVisible = max(startNormalized, endNormalized) >= 0 && min(startNormalized, endNormalized) <= 1
            } else {
                isVisible = startNormalized >= -0.01 && startNormalized <= 1.01
            }
            guard isVisible else {
                return nil
            }

            let startX = max(0, min(plotWidth, xPosition(for: item.startTimeSeconds, width: plotWidth)))
            let rawEndX = item.endTimeSeconds.map { xPosition(for: $0, width: plotWidth) }
            let endX = rawEndX.map { max(0, min(plotWidth, $0)) }

            let referenceX = max(0, min(plotWidth, min(startX, endX ?? startX)))
            var lanes = lanePositions[kind] ?? Array(repeating: -CGFloat.infinity, count: subLanesPerKind)
            let subLane = firstAvailableLane(for: referenceX, lanePositions: lanes, minimumGap: minimumGap)
            lanes[subLane] = referenceX
            lanePositions[kind] = lanes

            let itemWidth: CGFloat
            let itemOriginX: CGFloat
            if let endX {
                let left = min(startX, endX)
                let right = max(startX, endX)
                itemWidth = max(14, right - left)
                itemOriginX = laneLabelWidth + 6 + max(0, min(left, plotWidth - itemWidth))
            } else {
                itemWidth = kind == .region ? 42 : 34
                itemOriginX = laneLabelWidth + 6 + max(0, min(startX - (itemWidth / 2), plotWidth - itemWidth))
            }

            return TimelineMarkerLayout(
                id: item.id,
                index: index,
                kind: kind,
                originX: itemOriginX,
                y: laneTop(kind) + 4 + CGFloat(subLane) * 10,
                width: itemWidth,
                item: item,
                tint: markerTint(kind)
            )
        }
    }

    private func firstAvailableLane(for x: CGFloat, lanePositions: [CGFloat], minimumGap: CGFloat) -> Int {
        if let lane = lanePositions.firstIndex(where: { x - $0 >= minimumGap }) {
            return lane
        }

        return lanePositions.enumerated().min(by: { lhs, rhs in
            lhs.element < rhs.element
        })?.offset ?? 0
    }

    private func markerHelpText(_ item: ActionSessionFeedbackDocument.Item) -> String {
        let prefix: String
        if let endTimeSeconds = item.endTimeSeconds {
            prefix = "\(formattedTime(item.startTimeSeconds))-\(formattedTime(endTimeSeconds))"
        } else {
            prefix = formattedTime(item.startTimeSeconds)
        }
        return "\(prefix) • \(item.instruction)"
    }

    private func dragRange(width: CGFloat) -> (start: CGFloat, end: CGFloat)? {
        guard let dragStartX, let dragCurrentX else {
            return nil
        }

        let start = max(0, min(width, min(dragStartX, dragCurrentX)))
        let end = max(0, min(width, max(dragStartX, dragCurrentX)))
        return (start, end)
    }

    private var visibleDurationSeconds: Double {
        let zoom = max(1, timelineZoom)
        return max(durationSeconds / zoom, 1)
    }

    private var clampedWindowStartSeconds: Double {
        max(0, min(windowStartTimeSeconds, max(durationSeconds - visibleDurationSeconds, 0)))
    }

    private func normalized(_ seconds: Double) -> Double {
        guard durationSeconds > 0 else {
            return 0
        }
        return max(0, min((seconds - clampedWindowStartSeconds) / visibleDurationSeconds, 1))
    }

    private func normalizedUnclamped(_ seconds: Double) -> Double {
        guard durationSeconds > 0 else {
            return 0
        }
        return (seconds - clampedWindowStartSeconds) / visibleDurationSeconds
    }

    private func seconds(for x: CGFloat, width: CGFloat) -> Double {
        guard durationSeconds > 0 else {
            return 0
        }
        let clampedX = max(0, min(x, width))
        let ratio = Double(clampedX / width)
        return clampedWindowStartSeconds + (ratio * visibleDurationSeconds)
    }

    private func xPosition(for seconds: Double, width: CGFloat) -> CGFloat {
        CGFloat(normalized(seconds)) * width
    }

    private func formattedTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else {
            return "00:00.0"
        }
        let minutes = Int(seconds) / 60
        let wholeSeconds = Int(seconds) % 60
        let tenths = Int((seconds * 10).rounded(.down)) % 10
        return String(format: "%02d:%02d.%01d", minutes, wholeSeconds, tenths)
    }

    private func formattedTimeForRail(_ seconds: Double) -> String {
        if durationSeconds < 10 {
            return String(format: "%.1fs", seconds)
        }
        return formattedTime(seconds)
    }

    private func quantized(_ seconds: Double) -> Double {
        guard snapToTenth else {
            return seconds
        }
        return (seconds * 10).rounded() / 10
    }

    private var interactionHint: String {
        switch anchorInteraction {
        case .none:
            return "Click or drag to seek."
        case .point:
            return "Click to place a point anchor."
        case .range:
            return "Drag to define an in/out anchor range."
        }
    }

    private func markerKind(for item: ActionSessionFeedbackDocument.Item) -> MarkerKind {
        if item.region != nil {
            return .region
        }
        if item.endTimeSeconds != nil {
            return .range
        }
        return .point
    }

    private func markerTint(_ kind: MarkerKind) -> Color {
        switch kind {
        case .point:
            return StageHUDTheme.reviewAccent
        case .range:
            return StageHUDTheme.runOk
        case .region:
            return StageHUDTheme.accentPaused
        }
    }

    private func laneTop(_ kind: MarkerKind) -> CGFloat {
        CGFloat(kind.rawValue) * laneGroupHeight + 2
    }
}

private struct TimelineMarkerLayout: Identifiable {
    let id: String
    let index: Int
    let kind: MarkerKind
    let originX: CGFloat
    let y: CGFloat
    let width: CGFloat
    let item: ActionSessionFeedbackDocument.Item
    let tint: Color
}

private enum MarkerKind: Int, CaseIterable {
    case point = 0
    case range = 1
    case region = 2

    var label: String {
        switch self {
        case .point:
            return "Point"
        case .range:
            return "Range"
        case .region:
            return "Region"
        }
    }
}
