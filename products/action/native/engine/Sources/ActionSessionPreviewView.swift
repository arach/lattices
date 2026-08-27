import AVFoundation
import Foundation
import SwiftUI

struct ActionSessionPreviewView: View {
    private enum AnchorMode: String {
        case point = "Point"
        case range = "Range"
        case region = "Region"
        case draw = "Draw"
    }

    private enum FeedbackFilter: String, CaseIterable {
        case all = "All"
        case point = "Point"
        case range = "Range"
        case region = "Region"
    }

    private enum InspectorTab: String, CaseIterable {
        case compose = "Compose"
        case notes = "Notes"
        case exports = "Exports"
    }

    let session: ActionSessionSummary
    @ObservedObject var model: ActionLauncherViewModel

    @StateObject private var playback: ActionSessionPlaybackCoordinator
    @State private var feedbackDocument: ActionSessionFeedbackDocument
    @State private var draftInstruction = ""
    @State private var draftStartTimeSeconds: Double?
    @State private var draftEndTimeSeconds: Double?
    @State private var draftRegion: ActionSessionFeedbackDocument.Region?
    @State private var draftDrawing: ActionSessionFeedbackDocument.Drawing?
    @State private var dragStartPoint: CGPoint?
    @State private var dragCurrentPoint: CGPoint?
    @State private var drawingPreviewPoints: [CGPoint] = []
    @State private var isSelectingRegion = false
    @State private var isComposingFeedback = false
    @State private var anchorMode: AnchorMode = .point
    @State private var feedbackStatus = "No agent feedback yet"
    @State private var timelineZoom: Double = 1
    @State private var timelineWindowStartSeconds: Double = 0
    @State private var timelineSnapEnabled = true
    @State private var feedbackFilter: FeedbackFilter = .all
    @State private var feedbackSearch = ""
    @State private var inspectorTab: InspectorTab = .compose
    @State private var inspectorExpanded = false
    @FocusState private var noteEditorFocused: Bool
    private let surfaceRadius: CGFloat = 12
    private let cardRadius: CGFloat = 10

    init(session: ActionSessionSummary, model: ActionLauncherViewModel) {
        self.session = session
        self.model = model
        _playback = StateObject(wrappedValue: ActionSessionPlaybackCoordinator(url: session.videoURL))
        _feedbackDocument = State(initialValue: model.loadFeedback(for: session))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            playbackSurface
                .frame(maxWidth: .infinity, alignment: .topLeading)

            inspectorSidebar
        }
        .padding(12)
        .background(StageHUDTheme.reviewCanvas)
        .onDisappear {
            playback.pause()
        }
        .onChange(of: session.id) { _, _ in
            reloadSession()
        }
        .onChange(of: model.focusedFeedbackItemID) { _, _ in
            applyFocusedFeedbackIfNeeded()
        }
        .onChange(of: playback.currentTimeSeconds) { _, newValue in
            guard timelineMaxStart > 0 else {
                timelineWindowStartSeconds = 0
                return
            }
            let windowEnd = timelineWindowStartSeconds + timelineVisibleDuration
            if newValue < timelineWindowStartSeconds {
                timelineWindowStartSeconds = max(0, newValue - 0.6)
            } else if newValue > windowEnd {
                timelineWindowStartSeconds = max(0, min(timelineMaxStart, newValue - (timelineVisibleDuration * 0.7)))
            }
        }
        .onAppear {
            applyFocusedFeedbackIfNeeded()
        }
        .onExitCommand {
            handleEscape()
        }
        .focusable()
        .onKeyPress(characters: CharacterSet(charactersIn: "nN"), phases: .down) { _ in
            guard !noteEditorFocused else { return .ignored }
            openComposerFromKeyboard()
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "1234"), phases: .down) { press in
            guard !noteEditorFocused else { return .ignored }
            guard isComposingFeedback || inspectorExpanded else { return .ignored }
            switch press.characters {
            case "1":
                ensureComposerOpen()
                setAnchorMode(.point)
                return .handled
            case "2":
                ensureComposerOpen()
                setAnchorMode(.range)
                return .handled
            case "3":
                ensureComposerOpen()
                setAnchorMode(.region)
                return .handled
            case "4":
                ensureComposerOpen()
                setAnchorMode(.draw)
                return .handled
            default:
                return .ignored
            }
        }
        .onKeyPress(.return, phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            saveFeedback()
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: " "), phases: .down) { _ in
            guard !noteEditorFocused else { return .ignored }
            playback.togglePlayback()
            return .handled
        }
    }

    private func handleEscape() {
        if isSelectingRegion || dragStartPoint != nil || !drawingPreviewPoints.isEmpty {
            isSelectingRegion = false
            dragStartPoint = nil
            dragCurrentPoint = nil
            drawingPreviewPoints = []
            if anchorMode == .region || anchorMode == .draw {
                feedbackStatus = "Selection cancelled"
            }
            return
        }
        if isComposingFeedback {
            isComposingFeedback = false
            noteEditorFocused = false
            feedbackStatus = "Composer closed"
            return
        }
        if inspectorExpanded {
            inspectorExpanded = false
        }
    }

    private func openComposerFromKeyboard() {
        inspectorTab = .compose
        inspectorExpanded = true
        if !isComposingFeedback {
            toggleFeedbackComposer()
        } else {
            noteEditorFocused = true
        }
    }

    private var playbackSurface: some View {
        VStack(alignment: .leading, spacing: 0) {
            playerUtilityBar

            ZStack(alignment: .topLeading) {
                ActionInlinePlayerView(player: playback.player)
                    .allowsHitTesting(false)
                    .clipShape(RoundedRectangle(cornerRadius: surfaceRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: surfaceRadius, style: .continuous)
                            .stroke(StageHUDTheme.cardBorder, lineWidth: 1)
                    )

                playerStateOverlay
            }
            .frame(minHeight: 440, maxHeight: 560)
            .overlay(annotationOverlay.allowsHitTesting(true))
            .contextMenu {
                feedbackCreationMenu
            }

            playbackControlBar
            timelinePanel
        }
        .padding(14)
        .background(mainSurfaceBackground)
    }

    private var inspectorSidebar: some View {
        HStack(spacing: 10) {
            VStack(spacing: 8) {
                inspectorRailButton(.compose, systemImage: "plus.bubble")
                inspectorRailButton(.notes, systemImage: "text.bubble")
                inspectorRailButton(.exports, systemImage: "square.and.arrow.up")
            }
            .padding(8)
            .background(reviewCardBackground)

            if inspectorExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(inspectorTab.rawValue)
                            .font(ActionType.uiBodyStrong)
                            .foregroundStyle(StageHUDTheme.textMuted)
                        Spacer()
                        feedbackButton("Close", systemImage: "xmark", tone: .secondary) {
                            inspectorExpanded = false
                            if inspectorTab == .compose {
                                isComposingFeedback = false
                            }
                        }
                    }

                    inspectorContent
                }
                .frame(width: 340, alignment: .topLeading)
            }
        }
    }

    @ViewBuilder
    private var inspectorContent: some View {
        switch inspectorTab {
        case .compose:
            composerCard
        case .notes:
            savedFeedbackCard
        case .exports:
            exportsCard
        }
    }

    private var playerUtilityBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.displayTitle)
                    .font(ActionType.uiBodyStrong)
                    .foregroundStyle(StageHUDTheme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if isComposingFeedback {
                        statusPill(anchorMode.rawValue, accent: true)
                        Text(draftAnchorSummary)
                            .font(ActionType.uiCaption)
                            .foregroundStyle(StageHUDTheme.textSecondary)
                            .lineLimit(1)
                    } else {
                        Text("Space play  ·  N note  ·  1–4 anchors")
                            .font(ActionType.uiCaption)
                            .foregroundStyle(StageHUDTheme.textMuted)
                    }
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                topToolButton(
                    isComposingFeedback ? "Commenting" : "Comment",
                    systemImage: "plus.bubble",
                    tone: isComposingFeedback ? .primary : .secondary
                ) {
                    inspectorTab = .compose
                    if !inspectorExpanded || !isComposingFeedback {
                        toggleFeedbackComposer()
                    }
                }
                .keyboardShortcut("n", modifiers: [])
                topToolButton(
                    "Notes",
                    systemImage: "text.bubble",
                    tone: inspectorExpanded && inspectorTab == .notes ? .primary : .secondary
                ) {
                    inspectorTab = .notes
                    inspectorExpanded = true
                }
                topToolButton(
                    "Share",
                    systemImage: "square.and.arrow.up",
                    tone: inspectorExpanded && inspectorTab == .exports ? .primary : .secondary
                ) {
                    inspectorTab = .exports
                    inspectorExpanded = true
                }
                metadataChip("\(feedbackDocument.items.count)", emphasized: feedbackDocument.items.isEmpty == false)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(connectedBarBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(StageHUDTheme.reviewStrokeSoft)
                .frame(height: 1)
        }
    }

    private var playbackControlBar: some View {
        HStack(spacing: 18) {
            Text(playbackTimeSummary)
                .font(ActionType.uiCaptionStrong)
                .foregroundStyle(StageHUDTheme.textPrimary)

            Spacer()

            HStack(spacing: 8) {
                transportButton("Back", systemImage: "gobackward.5") { playback.skip(by: -5) }
                transportButton(
                    playback.isPlaying ? "Pause" : "Play",
                    systemImage: playback.isPlaying ? "pause.fill" : "play.fill",
                    tone: .primary,
                    action: playback.togglePlayback
                )
                transportButton("Stop", systemImage: "stop.fill") { playback.stop() }
                transportButton("Forward", systemImage: "goforward.5") { playback.skip(by: 5) }
            }

            Spacer()

            HStack(spacing: 8) {
                playbackRateButton(0.5)
                playbackRateButton(1)
                playbackRateButton(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(connectedBarBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(StageHUDTheme.reviewStrokeSoft)
                .frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(StageHUDTheme.reviewStrokeSoft)
                .frame(height: 1)
        }
    }

    private var timelinePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("TIMELINE")
                    .font(ActionType.mono(11, weight: .semibold))
                    .foregroundStyle(StageHUDTheme.textMuted)
                Text(modeStatusText)
                    .font(ActionType.monoCaption)
                    .foregroundStyle(StageHUDTheme.textSecondary)
                Spacer()
                Text(seekingHint)
                    .font(ActionType.mono(10, weight: .regular))
                    .foregroundStyle(StageHUDTheme.textMuted)
                if playback.durationSeconds > 0 {
                    Text("\(timelineDisplayTime(playback.currentTimeSeconds)) / \(timelineDisplayTime(playback.durationSeconds))")
                        .font(ActionType.mono(11, weight: .semibold))
                        .foregroundStyle(StageHUDTheme.textPrimary)
                }
                if isComposingFeedback {
                    statusPill(anchorMode.rawValue, accent: true)
                }
            }

            ActionSessionTimelineView(
                currentTimeSeconds: playback.currentTimeSeconds,
                durationSeconds: playback.durationSeconds,
                draftStartTimeSeconds: draftStartTimeSeconds,
                draftEndTimeSeconds: draftEndTimeSeconds,
                feedbackItems: feedbackDocument.items,
                timelineZoom: timelineZoom,
                windowStartTimeSeconds: timelineWindowStartSeconds,
                snapToTenth: timelineSnapEnabled,
                anchorInteraction: timelineAnchorInteraction,
                onSeek: { playback.seek(to: $0) },
                onWindowStartChange: { timelineWindowStartSeconds = max(0, min($0, timelineMaxStart)) },
                onCreatePointAnchor: setPointAnchor,
                onCreateRangeAnchor: setRangeAnchor
            )
            .contextMenu {
                feedbackCreationMenu
            }

            HStack(spacing: 8) {
                timelineZoomButton(1)
                timelineZoomButton(2)
                timelineZoomButton(4)
                feedbackButton(
                    timelineSnapEnabled ? "Snap 0.1s" : "Free",
                    systemImage: timelineSnapEnabled ? "dot.squareshape.split.2x2" : "line.3.horizontal.decrease",
                    tone: .secondary
                ) {
                    timelineSnapEnabled.toggle()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private var playerStateOverlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    if isComposingFeedback {
                        Text("Anchor: \(anchorMode.rawValue) • \(draftAnchorSummary)")
                            .font(ActionType.uiCaption)
                            .foregroundStyle(StageHUDTheme.overlayInk)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(StageHUDTheme.overlayScrim.opacity(0.36), in: Capsule())
                    }

                    if isSelectingRegion {
                        Text("Drag on the frame.")
                            .font(ActionType.uiCaption)
                            .foregroundStyle(StageHUDTheme.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(StageHUDTheme.accentPaused.opacity(0.28), in: Capsule())
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(StageHUDTheme.accentPaused.opacity(0.8), lineWidth: 1)
                            )
                    }
                }

                Spacer()

                statusLine(feedbackStatus)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(toolbarPlate)
            }
        }
        .padding(14)
    }

    private var connectedBarBackground: some View {
        Rectangle()
            .fill(StageHUDTheme.reviewPanel.opacity(0.96))
    }

    private var toolbarPlate: some View {
        Capsule(style: .continuous)
            .fill(StageHUDTheme.overlayScrim.opacity(0.34))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(StageHUDTheme.overlayHairline, lineWidth: 1)
            )
    }

    @ViewBuilder
    private var feedbackCreationMenu: some View {
        Button("Add Note at Current Time") {
            ensureComposerOpen()
            setAnchorMode(.point)
            setPointAnchor(playback.currentTimeSeconds)
            noteEditorFocused = true
        }
        Button("Start Range Here") {
            ensureComposerOpen()
            setAnchorMode(.range)
            draftStartTimeSeconds = playback.currentTimeSeconds
            draftEndTimeSeconds = nil
            feedbackStatus = "Range mode armed at current time"
            noteEditorFocused = true
        }
        Divider()
        Button("Highlight Region") {
            ensureComposerOpen()
            setAnchorMode(.region)
            noteEditorFocused = true
        }
        Button("Draw Markup") {
            ensureComposerOpen()
            setAnchorMode(.draw)
            noteEditorFocused = true
        }
        Divider()
        Button(playback.isPlaying ? "Pause Playback" : "Play Playback") {
            playback.togglePlayback()
        }
    }

    private var seekingHint: String {
        isComposingFeedback
            ? "Click or drag to seek, then leave a note."
            : "Click or drag to seek."
    }

    private var playbackTimeSummary: String {
        guard playback.durationSeconds > 0 else {
            return timelineDisplayTime(playback.currentTimeSeconds)
        }
        return "\(timelineDisplayTime(playback.currentTimeSeconds)) / \(timelineDisplayTime(playback.durationSeconds))"
    }

    private func playbackRateButton(_ value: Double) -> some View {
        feedbackButton(
            speedLabel(value),
            systemImage: nil,
            tone: abs(playback.playbackRate - value) < 0.01 ? .primary : .secondary
        ) {
            playback.setPlaybackRate(value)
            feedbackStatus = "Playback speed \(speedLabel(value))"
        }
    }

    private func topToolButton(_ title: String, systemImage: String, tone: StageHUDViewModel.ButtonTone, action: @escaping () -> Void) -> some View {
        feedbackButton(title, systemImage: systemImage, tone: tone, action: action)
    }

    private func speedLabel(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.001 {
            return "\(Int(value))x"
        }
        return String(format: "%.1fx", value)
    }

    private var annotationOverlay: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(activeOverlayItems) { item in
                    if let region = item.region {
                        let frame = denormalize(region, in: geometry.size)
                        spotlightOverlay(
                            frame: frame,
                            tint: item.id == model.focusedFeedbackItemID ? StageHUDTheme.reviewAccent.opacity(0.95) : StageHUDTheme.reviewAccent.opacity(0.82),
                            fillOpacity: item.id == model.focusedFeedbackItemID ? 0.20 : 0.11,
                            borderOpacity: 0.92,
                            label: item.id == model.focusedFeedbackItemID ? "Focused note" : "Note"
                        )
                        annotationPin(text: annotationIndexLabel(for: item))
                            .position(x: frame.maxX - 18, y: max(frame.minY + 12, 18))
                    } else {
                        annotationPin(text: annotationIndexLabel(for: item))
                            .position(x: geometry.size.width - 26, y: annotationPinY(for: item))
                    }

                    if let drawing = item.drawing {
                        drawingOverlay(
                            drawing,
                            in: geometry.size,
                            tint: item.id == model.focusedFeedbackItemID ? StageHUDTheme.reviewAccent : StageHUDTheme.accentPaused
                        )
                    }
                }

                if let draftRegion {
                    let frame = denormalize(draftRegion, in: geometry.size)
                    spotlightOverlay(
                        frame: frame,
                        tint: StageHUDTheme.accentPaused,
                        fillOpacity: 0.18,
                        borderOpacity: 0.98,
                        label: "Selected region"
                    )
                }

                if let draftDrawing, !draftDrawing.points.isEmpty {
                    drawingOverlay(draftDrawing, in: geometry.size, tint: StageHUDTheme.accentPaused)
                }

                if drawingPreviewPoints.count > 1 {
                    drawingPreviewOverlay(points: drawingPreviewPoints, tint: StageHUDTheme.accentRecording)
                }

                if let previewRect = previewDragRect(in: geometry.size) {
                    spotlightOverlay(
                        frame: previewRect,
                        tint: StageHUDTheme.accentRecording,
                        fillOpacity: 0.20,
                        borderOpacity: 1,
                        label: "Dragging"
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(annotationDragGesture(in: geometry.size))
        }
        .clipShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
    }

    private var draftAnchorSummary: String {
        var parts: [String] = []
        if let draftStartTimeSeconds {
            if let draftEndTimeSeconds {
                parts.append("\(formattedTime(draftStartTimeSeconds))-\(formattedTime(draftEndTimeSeconds))")
            } else {
                parts.append("@\(formattedTime(draftStartTimeSeconds))")
            }
        }
        if let draftRegion {
            parts.append("region \(Int(draftRegion.x * 100))%,\(Int(draftRegion.y * 100))%")
        }
        if let draftDrawing {
            parts.append("drawing \(draftDrawing.points.count) pts")
        }
        return parts.isEmpty ? "No anchors" : parts.joined(separator: " • ")
    }

    private var activeOverlayItems: [ActionSessionFeedbackDocument.Item] {
        let sorted = feedbackDocument.items.sorted { $0.startTimeSeconds < $1.startTimeSeconds }
        let focused = model.focusedFeedbackItemID.flatMap { focusedID in
            sorted.first(where: { $0.id == focusedID })
        }

        var visible = sorted.filter(isItemActiveAtCurrentTime)
        if let focused, visible.contains(where: { $0.id == focused.id }) == false {
            visible.insert(focused, at: 0)
        }
        return Array(visible.prefix(4))
    }

    private var reviewCardBackground: some View {
        RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
            .fill(StageHUDTheme.reviewPanel)
            .overlay(
                RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                    .stroke(StageHUDTheme.reviewStrokeSoft, lineWidth: 1)
            )
    }

    private var mainSurfaceBackground: some View {
        RoundedRectangle(cornerRadius: surfaceRadius, style: .continuous)
            .fill(StageHUDTheme.reviewPanelRaised)
            .overlay(
                RoundedRectangle(cornerRadius: surfaceRadius, style: .continuous)
                    .stroke(StageHUDTheme.reviewStrokeSoft, lineWidth: 1)
            )
    }

    private var composerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text("Compose")
                    .font(ActionType.uiBodyStrong)
                    .foregroundStyle(StageHUDTheme.textMuted)
                Spacer()
                statusPill(isComposingFeedback ? "Open" : "Closed", accent: isComposingFeedback)
                feedbackButton(
                    isComposingFeedback ? "Close" : "Open",
                    systemImage: isComposingFeedback ? "xmark.circle" : "plus.circle",
                    tone: isComposingFeedback ? .secondary : .primary,
                    action: toggleFeedbackComposer
                )
            }

            if isComposingFeedback {
                feedbackComposerBar
            } else {
                Text("Open Feedback to place anchors.")
                    .font(ActionType.uiCaption)
                    .foregroundStyle(StageHUDTheme.textSecondary)
                    .padding(.bottom, 2)
            }

            if isComposingFeedback {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(ActionIcon.small)
                        .foregroundStyle(StageHUDTheme.reviewAccent)
                    Text(draftAnchorSummary)
                        .font(ActionType.mono(11, weight: .medium))
                        .foregroundStyle(StageHUDTheme.textSecondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(StageHUDTheme.reviewAccentMuted)
                )
            }

            TextField("What should change here", text: $draftInstruction, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(4...7)
                .focused($noteEditorFocused)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(StageHUDTheme.reviewPanelRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(StageHUDTheme.reviewStrokeStrong, lineWidth: 1)
                )
                .opacity(isComposingFeedback ? 1 : 0.65)
                .disabled(!isComposingFeedback)

            HStack(spacing: 10) {
                feedbackButton("Save Note", systemImage: "square.and.arrow.down", tone: .primary, action: saveFeedback)
                    .keyboardShortcut(.return, modifiers: .command)
                feedbackButton("Clear Anchors", systemImage: "eraser", action: clearDraftAnchors)
                Spacer()
            }
            .opacity(isComposingFeedback ? 1 : 0.65)
            .allowsHitTesting(isComposingFeedback)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(reviewCardBackground)
    }

    private var exportsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Agent Exports")
                    .font(ActionType.mono(12, weight: .semibold))
                    .foregroundStyle(StageHUDTheme.textMuted)
                Spacer()
                statusPill(feedbackDocument.items.isEmpty ? "No Notes" : "Ready", accent: feedbackDocument.items.isEmpty == false)
            }

            Text("Export notes, or open the files.")
                .font(ActionType.uiBody)
                .foregroundStyle(StageHUDTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                feedbackButton("Copy Link", systemImage: "link", action: copyAgentFeedbackLink)
                feedbackButton("Copy MD", systemImage: "doc.plaintext", action: copyAgentFeedbackMarkdown)
                feedbackButton("Copy JSON", systemImage: "curlybraces", action: copyAgentFeedbackJSON)
            }
            HStack(spacing: 8) {
                feedbackButton("Open feedback.json", systemImage: "folder", action: { model.openSessionFeedback(session) })
                feedbackButton("Open MD", systemImage: "doc.text.magnifyingglass", action: openAgentFeedbackMarkdown)
            }
            .opacity(feedbackDocument.items.isEmpty ? 0.4 : 1)
            .allowsHitTesting(!feedbackDocument.items.isEmpty)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(reviewCardBackground)
    }

    private var savedFeedbackCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Saved Notes")
                    .font(ActionType.mono(12, weight: .semibold))
                    .foregroundStyle(StageHUDTheme.textMuted)
                Spacer()
                feedbackButton("Prev", systemImage: "chevron.up", tone: .secondary, action: focusPreviousFeedback)
                    .keyboardShortcut("[", modifiers: [])
                feedbackButton("Next", systemImage: "chevron.down", tone: .secondary, action: focusNextFeedback)
                    .keyboardShortcut("]", modifiers: [])
                statusPill("\(feedbackDocument.items.count)", accent: feedbackDocument.items.isEmpty == false)
            }

            HStack(spacing: 8) {
                ForEach(FeedbackFilter.allCases, id: \.self) { filter in
                    feedbackButton(
                        filter.rawValue,
                        systemImage: feedbackFilter == filter ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle",
                        tone: feedbackFilter == filter ? .primary : .secondary
                    ) {
                        feedbackFilter = filter
                    }
                }
            }

            TextField("Search notes…", text: $feedbackSearch)
                .textFieldStyle(.plain)
                .font(ActionType.uiBody)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(StageHUDTheme.reviewPanelRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(StageHUDTheme.reviewStrokeStrong, lineWidth: 1)
                )

            if filteredFeedbackItems.isEmpty {
                Text("Set an anchor, then save a note.")
                    .font(ActionType.uiBody)
                    .foregroundStyle(StageHUDTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if let focusedFeedbackItemID = model.focusedFeedbackItemID,
                   let focusedItem = filteredFeedbackItems.first(where: { $0.id == focusedFeedbackItemID }) {
                    HStack(spacing: 8) {
                        Image(systemName: "scope")
                            .font(ActionIcon.small)
                            .foregroundStyle(StageHUDTheme.reviewAccent)
                        Text("Focused: \(feedbackItemSummary(focusedItem))")
                            .font(ActionType.monoCaption)
                            .foregroundStyle(StageHUDTheme.textMuted)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(StageHUDTheme.reviewAccentMuted)
                    )
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(filteredFeedbackItems) { item in
                            feedbackItemRow(item)
                        }
                    }
                    .padding(.trailing, 2)
                }
                .frame(minHeight: 120, maxHeight: 380)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(reviewCardBackground)
    }

    private var timelineAnchorInteraction: ActionSessionTimelineView.AnchorInteraction {
        guard isComposingFeedback else {
            return .none
        }
        switch anchorMode {
        case .point:
            return .point
        case .range:
            return .range
        case .region, .draw:
            return .none
        }
    }

    private var feedbackComposerBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                anchorModeButton(.point)
                anchorModeButton(.range)
                anchorModeButton(.region)
                anchorModeButton(.draw)
                Spacer()
            }

            Text(composerHint)
                .font(ActionType.uiCaption)
                .foregroundStyle(StageHUDTheme.textSecondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(StageHUDTheme.reviewPanelRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(StageHUDTheme.reviewStrokeStrong, lineWidth: 1)
        )
    }

    private var composerHint: String {
        switch anchorMode {
        case .point:
            return "Stamp a time"
        case .range:
            return "Set an in/out range"
        case .region:
            return "Highlight a screen area"
        case .draw:
            return "Draw on the frame"
        }
    }

    private func anchorModeButton(_ mode: AnchorMode) -> some View {
        feedbackButton(
            mode.rawValue,
            tone: anchorMode == mode ? .primary : .secondary
        ) {
            setAnchorMode(mode)
        }
        .keyboardShortcut(
            mode == .point ? "1" : (mode == .range ? "2" : (mode == .region ? "3" : "4")),
            modifiers: [.command]
        )
    }

    private func feedbackButton(_ title: String, action: @escaping () -> Void) -> some View {
        feedbackButton(title, systemImage: nil, tone: .secondary, action: action)
    }

    private func inspectorRailButton(_ tab: InspectorTab, systemImage: String) -> some View {
        feedbackButton(
            "",
            systemImage: systemImage,
            tone: inspectorExpanded && inspectorTab == tab ? .primary : .secondary
        ) {
            if inspectorExpanded && inspectorTab == tab {
                inspectorExpanded = false
                if tab == .compose {
                    isComposingFeedback = false
                }
            } else {
                inspectorTab = tab
                inspectorExpanded = true
                if tab == .compose {
                    isComposingFeedback = true
                }
            }
        }
    }

    private func feedbackButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        feedbackButton(title, systemImage: systemImage, tone: .secondary, action: action)
    }

    private func feedbackButton(_ title: String, tone: StageHUDViewModel.ButtonTone, action: @escaping () -> Void) -> some View {
        feedbackButton(title, systemImage: nil, tone: tone, action: action)
    }

    private func feedbackButton(_ title: String, systemImage: String?, tone: StageHUDViewModel.ButtonTone, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(ActionIcon.small)
                }
                Text(title)
            }
        }
        .buttonStyle(ReviewSurfaceButtonStyle(tone: tone))
        .controlSize(.small)
    }

    private func transportButton(_ title: String, systemImage: String, tone: StageHUDViewModel.ButtonTone = .secondary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(ReviewSurfaceButtonStyle(tone: tone))
        .controlSize(.small)
    }

    private func transportButton(_ title: String, tone: StageHUDViewModel.ButtonTone = .secondary, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(ReviewSurfaceButtonStyle(tone: tone))
            .controlSize(.small)
    }

    private func statusPill(_ text: String, accent: Bool) -> some View {
        Text(text)
            .font(ActionType.mono(10, weight: .semibold))
            .foregroundStyle(accent ? StageHUDTheme.buttonPrimaryText : StageHUDTheme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(accent ? StageHUDTheme.reviewAccent : StageHUDTheme.reviewPanel)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(accent ? StageHUDTheme.reviewAccent : StageHUDTheme.reviewStrokeStrong, lineWidth: 1)
            )
    }

    private func statusLine(_ text: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(StageHUDTheme.reviewAccent.opacity(0.8))
                .frame(width: 6, height: 6)
            Text(text)
                .font(ActionType.monoCaption)
                .foregroundStyle(StageHUDTheme.textMuted)
                .lineLimit(1)
        }
    }

    private func metadataChip(_ text: String, emphasized: Bool = false) -> some View {
        Text(text)
            .font(ActionType.mono(10, weight: .semibold))
            .foregroundStyle(emphasized ? StageHUDTheme.reviewAccent : StageHUDTheme.textMuted)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(emphasized ? StageHUDTheme.reviewAccentMuted : StageHUDTheme.reviewPanel)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(emphasized ? StageHUDTheme.reviewAccent.opacity(0.5) : StageHUDTheme.reviewStrokeSoft, lineWidth: 1)
            )
    }

    private func feedbackItemRow(_ item: ActionSessionFeedbackDocument.Item) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(model.focusedFeedbackItemID == item.id ? StageHUDTheme.reviewAccent : StageHUDTheme.reviewStrokeStrong)
                    .frame(width: 4, height: 52)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        metadataChip(formattedTime(item.startTimeSeconds), emphasized: true)
                        if let endTimeSeconds = item.endTimeSeconds {
                            metadataChip(formattedTime(endTimeSeconds))
                        }
                        if item.region != nil {
                            metadataChip("Region")
                        }
                        if item.drawing != nil {
                            metadataChip("Draw")
                        }
                    }
                    Text(item.instruction)
                        .font(ActionType.uiBodyStrong)
                        .foregroundStyle(StageHUDTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    feedbackButton("Jump", systemImage: "scope") {
                        model.focusedFeedbackItemID = item.id
                        playback.seek(to: item.startTimeSeconds)
                    }

                    feedbackButton("Delete", systemImage: "trash") {
                        deleteFeedbackItem(item)
                    }
                }
            }

            if let region = item.region {
                Text("Region \(Int(region.x * 100))%, \(Int(region.y * 100))% • \(Int(region.width * 100)) x \(Int(region.height * 100))")
                    .font(ActionType.mono(10, weight: .regular))
                    .foregroundStyle(StageHUDTheme.textMuted)
            } else if let drawing = item.drawing {
                Text("Drawing • \(drawing.points.count) points")
                    .font(ActionType.mono(10, weight: .regular))
                    .foregroundStyle(StageHUDTheme.textMuted)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(model.focusedFeedbackItemID == item.id ? StageHUDTheme.reviewAccentMuted : StageHUDTheme.reviewPanelRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(model.focusedFeedbackItemID == item.id ? StageHUDTheme.reviewAccent.opacity(0.55) : StageHUDTheme.reviewStrokeStrong, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            model.focusedFeedbackItemID = item.id
            if let region = item.region {
                draftRegion = region
            }
            draftDrawing = item.drawing
            playback.seek(to: item.startTimeSeconds)
            feedbackStatus = "Focused feedback item"
        }
    }

    private func toggleFeedbackComposer() {
        isComposingFeedback.toggle()
        if isComposingFeedback {
            inspectorTab = .compose
            inspectorExpanded = true
            draftStartTimeSeconds = draftStartTimeSeconds ?? playback.currentTimeSeconds
            draftEndTimeSeconds = nil
            setAnchorMode(anchorMode)
            noteEditorFocused = true
            feedbackStatus = "Composer opened"
        } else {
            inspectorExpanded = false
            isSelectingRegion = false
            dragStartPoint = nil
            dragCurrentPoint = nil
            drawingPreviewPoints = []
            noteEditorFocused = false
            feedbackStatus = "Composer closed"
        }
    }

    private func setAnchorMode(_ mode: AnchorMode) {
        anchorMode = mode
        switch mode {
        case .point:
            isSelectingRegion = false
            dragStartPoint = nil
            dragCurrentPoint = nil
            drawingPreviewPoints = []
            feedbackStatus = "Point mode: click timeline to place anchor"
        case .range:
            isSelectingRegion = false
            dragStartPoint = nil
            dragCurrentPoint = nil
            drawingPreviewPoints = []
            feedbackStatus = "Range mode: drag timeline for in/out"
        case .region:
            isSelectingRegion = true
            drawingPreviewPoints = []
            draftDrawing = nil
            feedbackStatus = "Region mode: drag on video to highlight area"
        case .draw:
            isSelectingRegion = false
            dragStartPoint = nil
            dragCurrentPoint = nil
            draftRegion = nil
            feedbackStatus = "Draw mode: sketch directly on the video"
        }
    }

    private func setPointAnchor(_ seconds: Double) {
        guard isComposingFeedback else {
            return
        }
        draftStartTimeSeconds = seconds
        draftEndTimeSeconds = nil
        feedbackStatus = "Point anchor set at \(formattedTime(seconds))"
    }

    private func setRangeAnchor(_ startSeconds: Double, _ endSeconds: Double) {
        guard isComposingFeedback else {
            return
        }
        draftStartTimeSeconds = min(startSeconds, endSeconds)
        draftEndTimeSeconds = max(startSeconds, endSeconds)
        feedbackStatus = "Range anchor set"
    }

    private func clearDraftAnchors() {
        draftStartTimeSeconds = nil
        draftEndTimeSeconds = nil
        draftRegion = nil
        draftDrawing = nil
        dragStartPoint = nil
        dragCurrentPoint = nil
        drawingPreviewPoints = []
        isSelectingRegion = false
        feedbackStatus = "Cleared draft anchors"
    }

    private func markPointAtPlayhead() {
        ensureComposerOpen()
        draftStartTimeSeconds = playback.currentTimeSeconds
        draftEndTimeSeconds = nil
        feedbackStatus = "Marked point at \(formattedTime(playback.currentTimeSeconds))"
    }

    private func setInAtPlayhead() {
        ensureComposerOpen()
        let current = playback.currentTimeSeconds
        draftStartTimeSeconds = current
        if let end = draftEndTimeSeconds, end < current {
            draftEndTimeSeconds = nil
        }
        feedbackStatus = "Set in-point at \(formattedTime(current))"
    }

    private func setOutAtPlayhead() {
        ensureComposerOpen()
        let current = playback.currentTimeSeconds
        if draftStartTimeSeconds == nil {
            draftStartTimeSeconds = current
        }
        if let start = draftStartTimeSeconds, current < start {
            draftStartTimeSeconds = current
            draftEndTimeSeconds = start
        } else {
            draftEndTimeSeconds = current
        }
        feedbackStatus = "Set out-point at \(formattedTime(current))"
    }

    private func ensureComposerOpen() {
        if !isComposingFeedback {
            isComposingFeedback = true
            inspectorTab = .compose
            inspectorExpanded = true
            setAnchorMode(anchorMode)
            noteEditorFocused = false
        }
    }

    private func focusNextFeedback() {
        guard !filteredFeedbackItems.isEmpty else {
            return
        }
        if let currentID = model.focusedFeedbackItemID,
           let idx = filteredFeedbackItems.firstIndex(where: { $0.id == currentID }) {
            let nextIndex = min(idx + 1, filteredFeedbackItems.count - 1)
            focusFeedback(filteredFeedbackItems[nextIndex])
        } else {
            focusFeedback(filteredFeedbackItems[0])
        }
    }

    private func focusPreviousFeedback() {
        guard !filteredFeedbackItems.isEmpty else {
            return
        }
        if let currentID = model.focusedFeedbackItemID,
           let idx = filteredFeedbackItems.firstIndex(where: { $0.id == currentID }) {
            let previousIndex = max(idx - 1, 0)
            focusFeedback(filteredFeedbackItems[previousIndex])
        } else {
            focusFeedback(filteredFeedbackItems[0])
        }
    }

    private func focusFeedback(_ item: ActionSessionFeedbackDocument.Item) {
        inspectorTab = .notes
        inspectorExpanded = true
        model.focusedFeedbackItemID = item.id
        playback.seek(to: item.startTimeSeconds)
        if let region = item.region {
            draftRegion = region
        }
        draftDrawing = item.drawing
        feedbackStatus = "Focused feedback item"
    }

    private func saveFeedback() {
        let instruction = draftInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else {
            feedbackStatus = "Add an instruction first"
            return
        }

        let item = ActionSessionFeedbackDocument.Item(
            id: UUID().uuidString,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            startTimeSeconds: draftStartTimeSeconds ?? playback.currentTimeSeconds,
            endTimeSeconds: draftEndTimeSeconds,
            region: draftRegion,
            drawing: draftDrawing,
            instruction: instruction
        )

        var updated = feedbackDocument
        updated.items.insert(item, at: 0)

        do {
            try model.saveFeedback(updated, for: session)
            feedbackDocument = model.loadFeedback(for: session)
            model.focusedFeedbackItemID = item.id
            draftInstruction = ""
            draftStartTimeSeconds = item.startTimeSeconds
            draftEndTimeSeconds = item.endTimeSeconds
            draftRegion = item.region
            draftDrawing = item.drawing
            dragStartPoint = nil
            dragCurrentPoint = nil
            drawingPreviewPoints = []
            isSelectingRegion = false
            feedbackStatus = "Saved feedback.json + agent exports"
        } catch {
            feedbackStatus = "Save failed: \(error.localizedDescription)"
        }
    }

    private func copyAgentFeedbackMarkdown() {
        do {
            try model.copyAgentFeedbackMarkdown(session)
            feedbackStatus = "Copied agent-feedback.md"
        } catch {
            feedbackStatus = "Copy failed: \(error.localizedDescription)"
        }
    }

    private func copyAgentFeedbackJSON() {
        do {
            try model.copyAgentFeedbackJSON(session)
            feedbackStatus = "Copied agent-feedback.json"
        } catch {
            feedbackStatus = "Copy failed: \(error.localizedDescription)"
        }
    }

    private func copyAgentFeedbackLink() {
        do {
            try model.copyAgentFeedbackLink(session)
            feedbackStatus = "Copied compact session link"
        } catch {
            feedbackStatus = "Copy failed: \(error.localizedDescription)"
        }
    }

    private func openAgentFeedbackMarkdown() {
        do {
            try model.openAgentFeedbackMarkdown(session)
            feedbackStatus = "Opened agent-feedback.md"
        } catch {
            feedbackStatus = "Open failed: \(error.localizedDescription)"
        }
    }

    private func deleteFeedbackItem(_ item: ActionSessionFeedbackDocument.Item) {
        var updated = feedbackDocument
        updated.items.removeAll { $0.id == item.id }

        do {
            try model.saveFeedback(updated, for: session)
            feedbackDocument = model.loadFeedback(for: session)
            feedbackStatus = "Deleted feedback item"
        } catch {
            feedbackStatus = "Delete failed: \(error.localizedDescription)"
        }
    }

    private func reloadSession() {
        playback.load(url: session.videoURL)
        feedbackDocument = model.loadFeedback(for: session)
        draftInstruction = ""
        clearDraftAnchors()
        timelineWindowStartSeconds = 0
        timelineZoom = 1
        feedbackFilter = .all
        feedbackSearch = ""
        draftDrawing = nil
        drawingPreviewPoints = []
        feedbackStatus = feedbackDocument.items.isEmpty ? "No agent feedback yet" : "Loaded feedback.json"
        applyFocusedFeedbackIfNeeded()
    }

    private func applyFocusedFeedbackIfNeeded() {
        guard let focusedFeedbackItemID = model.focusedFeedbackItemID,
              let item = feedbackDocument.items.first(where: { $0.id == focusedFeedbackItemID }) else {
            return
        }
        playback.seek(to: item.startTimeSeconds)
        feedbackStatus = "Focused linked feedback item"
    }

    private func annotationDragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isComposingFeedback else {
                    return
                }
                switch anchorMode {
                case .region:
                    guard isSelectingRegion else { return }
                    if dragStartPoint == nil {
                        dragStartPoint = value.startLocation
                    }
                    dragCurrentPoint = value.location
                case .draw:
                    let bounded = boundedPoint(value.location, in: size)
                    if drawingPreviewPoints.isEmpty {
                        drawingPreviewPoints = [bounded]
                    } else if let last = drawingPreviewPoints.last,
                              hypot(last.x - bounded.x, last.y - bounded.y) >= 4 {
                        drawingPreviewPoints.append(bounded)
                    }
                case .point, .range:
                    return
                }
            }
            .onEnded { value in
                guard isComposingFeedback else {
                    return
                }

                switch anchorMode {
                case .region:
                    guard isSelectingRegion else { return }
                    draftRegion = normalizedRegion(from: value.startLocation, to: value.location, in: size)
                    dragStartPoint = nil
                    dragCurrentPoint = nil
                    isSelectingRegion = false
                    feedbackStatus = draftRegion == nil ? "Region too small" : "Highlighted region"
                case .draw:
                    draftDrawing = normalizedDrawing(from: drawingPreviewPoints, in: size)
                    drawingPreviewPoints = []
                    feedbackStatus = draftDrawing == nil ? "Drawing too small" : "Saved drawing markup"
                case .point, .range:
                    return
                }
            }
    }

    private func previewDragRect(in size: CGSize) -> CGRect? {
        guard let dragStartPoint, let dragCurrentPoint else {
            return nil
        }
        return normalizeRect(CGRect(
            x: min(dragStartPoint.x, dragCurrentPoint.x),
            y: min(dragStartPoint.y, dragCurrentPoint.y),
            width: abs(dragCurrentPoint.x - dragStartPoint.x),
            height: abs(dragCurrentPoint.y - dragStartPoint.y)
        ), in: size)
    }

    private func normalizedRegion(from start: CGPoint, to end: CGPoint, in size: CGSize) -> ActionSessionFeedbackDocument.Region? {
        let rect = normalizeRect(CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        ), in: size)

        guard rect.width >= 12, rect.height >= 12, size.width > 0, size.height > 0 else {
            return nil
        }

        return ActionSessionFeedbackDocument.Region(
            x: Double(rect.minX / size.width),
            y: Double(rect.minY / size.height),
            width: Double(rect.width / size.width),
            height: Double(rect.height / size.height)
        )
    }

    private func normalizeRect(_ rect: CGRect, in size: CGSize) -> CGRect {
        let originX = max(0, min(rect.minX, size.width))
        let originY = max(0, min(rect.minY, size.height))
        let maxWidth = max(0, size.width - originX)
        let maxHeight = max(0, size.height - originY)
        return CGRect(
            x: originX,
            y: originY,
            width: min(rect.width, maxWidth),
            height: min(rect.height, maxHeight)
        )
    }

    private func denormalize(_ region: ActionSessionFeedbackDocument.Region, in size: CGSize) -> CGRect {
        CGRect(
            x: Double(size.width) * region.x,
            y: Double(size.height) * region.y,
            width: Double(size.width) * region.width,
            height: Double(size.height) * region.height
        )
    }

    private func denormalize(_ drawing: ActionSessionFeedbackDocument.Drawing, in size: CGSize) -> [CGPoint] {
        drawing.points.map { point in
            CGPoint(x: point.x * size.width, y: point.y * size.height)
        }
    }

    private func feedbackItemSummary(_ item: ActionSessionFeedbackDocument.Item) -> String {
        var parts = [formattedTime(item.startTimeSeconds)]
        if let endTimeSeconds = item.endTimeSeconds {
            parts[0] += "-\(formattedTime(endTimeSeconds))"
        }
        if let region = item.region {
            parts.append("region \(Int(region.x * 100))%,\(Int(region.y * 100))% \(Int(region.width * 100))x\(Int(region.height * 100))")
        }
        if let drawing = item.drawing {
            parts.append("drawing \(drawing.points.count)pts")
        }
        return parts.joined(separator: " • ")
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

    private var filteredFeedbackItems: [ActionSessionFeedbackDocument.Item] {
        feedbackDocument.items.filter { item in
            let typeMatches: Bool
            switch feedbackFilter {
            case .all:
                typeMatches = true
            case .point:
                typeMatches = item.endTimeSeconds == nil && item.region == nil
            case .range:
                typeMatches = item.endTimeSeconds != nil
            case .region:
                typeMatches = item.region != nil
            }

            guard typeMatches else {
                return false
            }

            let query = feedbackSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !query.isEmpty else {
                return true
            }
            let haystack = "\(item.instruction) \(feedbackItemSummary(item))".lowercased()
            return haystack.contains(query)
        }
    }

    private var modeStatusText: String {
        if isComposingFeedback {
            return "Mode \(anchorMode.rawValue) active"
        }
        return "Use the timeline to review and jump"
    }

    private var timelineVisibleDuration: Double {
        guard playback.durationSeconds > 0 else {
            return 1
        }
        return max(playback.durationSeconds / max(timelineZoom, 1), 1)
    }

    private var timelineMaxStart: Double {
        max(playback.durationSeconds - timelineVisibleDuration, 0)
    }

    private func timelineZoomButton(_ value: Double) -> some View {
        feedbackButton(
            "\(Int(value))x",
            systemImage: value == timelineZoom ? "viewfinder.circle.fill" : "viewfinder.circle",
            tone: timelineZoom == value ? .primary : .secondary
        ) {
            timelineZoom = value
            timelineWindowStartSeconds = max(0, min(timelineWindowStartSeconds, timelineMaxStart))
            feedbackStatus = "Timeline zoom \(Int(value))x"
        }
    }

    private func timelineDisplayTime(_ seconds: Double) -> String {
        if playback.durationSeconds < 10 {
            return String(format: "%.1fs", seconds)
        }
        return formattedTime(seconds)
    }

    @ViewBuilder
    private func spotlightOverlay(
        frame: CGRect,
        tint: Color,
        fillOpacity: Double,
        borderOpacity: Double,
        label: String
    ) -> some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.26)
                .mask {
                    Rectangle()
                        .overlay(alignment: .center) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .frame(width: frame.width, height: frame.height)
                                .position(x: frame.midX, y: frame.midY)
                                .blendMode(.destinationOut)
                        }
                }

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(tint.opacity(fillOpacity))
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(tint.opacity(borderOpacity), style: StrokeStyle(lineWidth: 2, dash: [7, 4]))
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)

            Text(label)
                .font(ActionType.mono(10, weight: .semibold))
                .foregroundStyle(StageHUDTheme.overlayInk)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(tint.opacity(0.94), in: Capsule())
                .offset(x: frame.minX + 10, y: max(8, frame.minY - 12))
        }
    }

    @ViewBuilder
    private func drawingOverlay(_ drawing: ActionSessionFeedbackDocument.Drawing, in size: CGSize, tint: Color) -> some View {
        let points = denormalize(drawing, in: size)
        drawingPreviewOverlay(points: points, tint: tint)
    }

    @ViewBuilder
    private func drawingPreviewOverlay(points: [CGPoint], tint: Color) -> some View {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
        .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        .shadow(color: tint.opacity(0.25), radius: 2, x: 0, y: 1)
    }

    private func annotationPin(text: String) -> some View {
        Text(text)
            .font(ActionType.mono(10, weight: .bold))
            .foregroundStyle(StageHUDTheme.overlayInk)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(StageHUDTheme.reviewAccent, in: Capsule())
            .overlay(
                Capsule(style: .continuous)
                    .stroke(StageHUDTheme.overlayInk.opacity(0.2), lineWidth: 1)
            )
    }

    private func annotationIndexLabel(for item: ActionSessionFeedbackDocument.Item) -> String {
        guard let index = feedbackDocument.items.firstIndex(where: { $0.id == item.id }) else {
            return "N"
        }
        return "\(index + 1)"
    }

    private func annotationPinY(for item: ActionSessionFeedbackDocument.Item) -> CGFloat {
        let sorted = activeOverlayItems.map(\.id)
        let index = sorted.firstIndex(of: item.id) ?? 0
        return CGFloat(28 + index * 28)
    }

    private func isItemActiveAtCurrentTime(_ item: ActionSessionFeedbackDocument.Item) -> Bool {
        if let end = item.endTimeSeconds {
            return playback.currentTimeSeconds >= item.startTimeSeconds && playback.currentTimeSeconds <= end
        }
        return abs(playback.currentTimeSeconds - item.startTimeSeconds) <= 0.6
    }

    private func boundedPoint(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: max(0, min(point.x, size.width)),
            y: max(0, min(point.y, size.height))
        )
    }

    private func normalizedDrawing(from points: [CGPoint], in size: CGSize) -> ActionSessionFeedbackDocument.Drawing? {
        guard size.width > 0, size.height > 0, points.count > 1 else {
            return nil
        }

        let normalized = points.map { point in
            ActionSessionFeedbackDocument.Drawing.Point(
                x: max(0, min(Double(point.x / size.width), 1)),
                y: max(0, min(Double(point.y / size.height), 1))
            )
        }

        guard normalized.count > 1 else {
            return nil
        }

        return ActionSessionFeedbackDocument.Drawing(points: normalized)
    }
}

private struct ReviewSurfaceButtonStyle: ButtonStyle {
    let tone: StageHUDViewModel.ButtonTone

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ActionType.mono(11, weight: .semibold))
            .foregroundStyle(foregroundColor(configuration: configuration))
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .background(background(configuration: configuration))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(borderColor(configuration: configuration), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.93 : 1)
            .shadow(color: StageHUDTheme.panelShadow.opacity(configuration.isPressed ? 0.22 : 0.34), radius: 3, x: 0, y: 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private func background(configuration: Configuration) -> some View {
        Group {
            switch tone {
            case .primary:
                LinearGradient(
                    colors: [
                        StageHUDTheme.reviewAccent.opacity(configuration.isPressed ? 0.8 : 0.94),
                        StageHUDTheme.reviewAccent.opacity(configuration.isPressed ? 0.66 : 0.8),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            case .secondary:
                LinearGradient(
                    colors: [
                        StageHUDTheme.reviewPanelRaised.opacity(configuration.isPressed ? 0.82 : 0.94),
                        StageHUDTheme.reviewPanel.opacity(configuration.isPressed ? 0.76 : 0.9),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            case .destructive:
                Color(StageHUDTheme.accentRecording.opacity(configuration.isPressed ? 0.68 : 0.82))
            }
        }
    }

    private func foregroundColor(configuration: Configuration) -> Color {
        switch tone {
        case .primary:
            return StageHUDTheme.buttonPrimaryText.opacity(configuration.isPressed ? 0.86 : 1)
        case .secondary, .destructive:
            return StageHUDTheme.textPrimary.opacity(configuration.isPressed ? 0.85 : 1)
        }
    }

    private func borderColor(configuration: Configuration) -> Color {
        switch tone {
        case .primary:
            return StageHUDTheme.reviewAccent.opacity(configuration.isPressed ? 0.8 : 0.62)
        case .secondary:
            return StageHUDTheme.reviewStrokeStrong.opacity(configuration.isPressed ? 1 : 0.9)
        case .destructive:
            return StageHUDTheme.accentRecording.opacity(configuration.isPressed ? 0.75 : 0.6)
        }
    }
}
