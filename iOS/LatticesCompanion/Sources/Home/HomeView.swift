import DeckKit
import SwiftUI

/// Lats Home — the passive single-pane-of-glass surface for the iPad.
///
/// Composed of independent sections:
///   - HomeTopBar       (chrome — fleet pills, agent count, settings)
///   - HomeTargetsRow   (adaptive cards: 1, 2, 3-4 Macs)
///   - HomeOverflowGrid (foreground machine "third monitor" tiles)
///   - HomeScenesGrid   (instant layout presets)
///   - HomeRoutinesList (agent recipes)
///   - HomeRecentTape   (cross-fleet activity)
///   - HomeSyncSection  (broadcast / fleet ops)
///   - HomeCloudStrip   (separate cloud aggregate)
///   - HomeBottomBar    (chrome — status, voice/cmd)
///
/// Zero state (no Macs paired) renders HomeZeroState instead.
///
/// Sections are independent and previewable on their own; this file just
/// composes them with the right paddings and spacings.
struct HomeView: View {
    let machines: [HomeMachine]
    let scenes: [HomeScene]
    let routines: [HomeRoutine]
    let recent: [HomeRecentEntry]
    let sync: [HomeSyncAction]
    let cloud: HomeCloudStatus
    let agentFeed: [HomeAgentFeedEntry]
    let terminal: [HomeTerminalLine]
    let calendar: [HomeCalendarEvent]
    let attention: [HomeAttentionItem]

    /// Bottom-bar telemetry. When `.empty` (default), the cluster hides itself
    /// while the rest of the bar (status / version / agent) still renders.
    var bottomTelemetry: HomeBottomTelemetry = .empty

    var onEnterDeck: ((HomeMachine) -> Void)? = nil
    var onScene: ((HomeScene) -> Void)? = nil
    var onRoutine: ((HomeRoutine) -> Void)? = nil
    var onBroadcast: ((HomeSyncAction, [HomeMachine]) -> Void)? = nil
    var onPair: (() -> Void)? = nil
    var onSettings: (() -> Void)? = nil

    // Voice (relay) — drive the active Mac's Vox capture from the iPad.
    var voiceState: DeckVoiceState? = nil
    var voiceMacLabel: String = "Mac"
    var isVoicePerforming: Bool = false
    var onVoiceStart: (() -> Void)? = nil
    var onVoiceStop: (() -> Void)? = nil
    var onVoiceCancel: (() -> Void)? = nil
    var onVoiceRemediate: ((DeckRemediationAction) -> Void)? = nil

    @State private var showingVoiceOverlay: Bool = false

    private var foregroundMachine: HomeMachine? {
        machines.first(where: { $0.isForeground })
    }

    private var agentsRunning: Int {
        machines.filter {
            if case .running = $0.agentState { return true }
            return false
        }.count
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if machines.isEmpty {
                    zeroStateLayout
                } else {
                    connectedLayout
                }
            }
            voiceTrigger
                .padding(.trailing, 18)
                .padding(.bottom, 70) // sit above the HomeBottomBar
        }
        .fullScreenCover(isPresented: $showingVoiceOverlay) {
            HomeVoiceOverlay(
                voiceState: voiceState,
                macLabel: voiceMacLabel,
                isPerforming: isVoicePerforming,
                onStart: { onVoiceStart?() },
                onStop:  { onVoiceStop?() },
                onCancel: {
                    onVoiceCancel?()
                    showingVoiceOverlay = false
                },
                onClose: { showingVoiceOverlay = false },
                onRemediate: { onVoiceRemediate?($0) }
            )
        }
        .onChange(of: voiceState?.phase) { _, newPhase in
            // Auto-close when the Mac finishes a successful turn (idle + result, no error).
            guard showingVoiceOverlay,
                  newPhase == .idle,
                  voiceState?.error == nil,
                  let summary = voiceState?.responseSummary,
                  !summary.isEmpty,
                  summary != "Transcribing...",
                  summary != "thinking..."
            else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(1400))
                if voiceState?.phase == .idle && voiceState?.error == nil {
                    showingVoiceOverlay = false
                }
            }
        }
    }

    private var voiceTrigger: some View {
        Button {
            onVoiceStart?()
            showingVoiceOverlay = true
        } label: {
            Image(systemName: "mic.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(LatsPalette.text)
                .frame(width: 52, height: 52)
                .background(
                    Circle().fill(LatsPalette.violet.opacity(0.22))
                )
                .overlay(
                    Circle().stroke(LatsPalette.violet.opacity(0.6), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start voice on \(voiceMacLabel)")
    }

    private var foregroundAgentState: HomeAgentState {
        foregroundMachine?.agentState ?? .idle
    }

    private var zeroStateLayout: some View {
        VStack(spacing: 0) {
            HomeTopBar(machines: machines, agentsRunning: 0, onSettings: onSettings)
            HomeZeroState(onPair: onPair, onSettings: onSettings)
            HomeBottomBar(telemetry: bottomTelemetry)
        }
    }

    private var connectedLayout: some View {
        VStack(spacing: 0) {
            HomeTopBar(
                machines: machines,
                agentsRunning: agentsRunning,
                onSettings: onSettings
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HomeTargetsRow(machines: machines, onEnterDeck: onEnterDeck)

                    HomeScenesGrid(scenes: scenes, onScene: onScene)

                    HomeRoutinesList(routines: routines, onRun: onRoutine)

                    HomeRecentTape(entries: recent)

                    HomeSyncSection(
                        actions: sync,
                        machines: machines,
                        onBroadcast: onBroadcast
                    )
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }

            HomeCloudStrip(cloud: cloud)
            HomeBottomBar(
                agentState: foregroundAgentState,
                telemetry: bottomTelemetry
            )
        }
    }
}

// MARK: - Previews

#Preview("Home · 4 machines") {
    LatsBackground(grid: false) {
        HomeView(
            machines:  HomeMock.fleetFour,
            scenes:    HomeMock.scenes,
            routines:  HomeMock.routines,
            recent:    HomeMock.recent,
            sync:      HomeMock.sync,
            cloud:     HomeMock.cloud,
            agentFeed: HomeMock.agentFeed,
            terminal:  HomeMock.terminal,
            calendar:  HomeMock.calendar,
            attention: HomeMock.attention
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Home · 2 machines") {
    LatsBackground {
        HomeView(
            machines:  HomeMock.fleetTwo,
            scenes:    HomeMock.scenes,
            routines:  HomeMock.routines,
            recent:    HomeMock.recent,
            sync:      HomeMock.sync,
            cloud:     HomeMock.cloud,
            agentFeed: HomeMock.agentFeed,
            terminal:  HomeMock.terminal,
            calendar:  HomeMock.calendar,
            attention: HomeMock.attention
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Home · 1 machine") {
    LatsBackground {
        HomeView(
            machines:  HomeMock.fleetOne,
            scenes:    HomeMock.scenes,
            routines:  HomeMock.routines,
            recent:    HomeMock.recent,
            sync:      HomeMock.sync,
            cloud:     HomeMock.cloud,
            agentFeed: HomeMock.agentFeed,
            terminal:  HomeMock.terminal,
            calendar:  HomeMock.calendar,
            attention: HomeMock.attention
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Home · zero state") {
    LatsBackground {
        HomeView(
            machines:  HomeMock.fleetEmpty,
            scenes:    HomeMock.scenes,
            routines:  HomeMock.routines,
            recent:    HomeMock.recent,
            sync:      HomeMock.sync,
            cloud:     HomeMock.cloud,
            agentFeed: HomeMock.agentFeed,
            terminal:  HomeMock.terminal,
            calendar:  HomeMock.calendar,
            attention: HomeMock.attention,
            onPair: {}
        )
    }
    .preferredColorScheme(.dark)
}
