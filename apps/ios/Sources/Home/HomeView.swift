import DeckKit
import SwiftUI

/// Lats Home — the passive single-pane-of-glass surface for the iPad.
///
/// Composed of independent sections:
///   - HomeTopBar       (chrome — fleet pills, agent count, settings)
///   - HomeTargetsRow   (adaptive cards: 1, 2, 3-4 Macs)
///   - HomeScreensRow   (live per-host screen thumbnails)
///   - HomeActivityFeed (combined: attention + recent + agent narration)
///   - HomeVoicePanel   (inline voice — slides in above the cloud strip)
///   - HomeCloudStrip   (separate cloud aggregate)
///   - HomeBottomBar    (chrome — status, voice/cmd)
///
/// Zero state (no Macs paired) renders HomeZeroState instead.
///
/// Sections are independent and previewable on their own; this file just
/// composes them with the right paddings and spacings.
struct HomeView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let machines: [HomeMachine]
    let recent: [HomeRecentEntry]
    let cloud: HomeCloudStatus
    let agentFeed: [HomeAgentFeedEntry]
    let attention: [HomeAttentionItem]
    /// Live per-host screen thumbnails, keyed by machine ID. A host joins the
    /// Screens strip only once it has produced a frame.
    var screenPreviews: [String: UIImage] = [:]

    /// Bottom-bar telemetry. When `.empty` (default), the cluster hides itself
    /// while the rest of the bar (status / version / agent) still renders.
    var bottomTelemetry: HomeBottomTelemetry = .empty

    var onEnterDeck: ((HomeMachine) -> Void)? = nil
    /// Opens the multi-host deck. Only offered when there is more than one Mac.
    var onEnterFleet: (() -> Void)? = nil
    var onAddHost: (() -> Void)? = nil
    /// Toggle dictation on one specific host, from its roster card.
    var onMachineVoice: ((HomeMachine) -> Void)? = nil
    /// Unpaired Macs discovery can see right now. Surfaced on the add cell.
    var nearbyCandidateCount: Int = 0
    var onPair: (() -> Void)? = nil
    var onSettings: (() -> Void)? = nil

    // Voice (relay) — drive the active Mac's Vox capture from the iPad.
    var voiceState: DeckVoiceState? = nil
    var voiceMacLabel: String = "Mac"
    var isVoicePerforming: Bool = false
    var voiceTargetReachable: Bool = false
    /// Opens the voice panel without arming a microphone.
    var onVoiceOpen: ((HomeMachine?) -> Void)? = nil
    var onVoiceStart: (() -> Void)? = nil
    var onVoiceStop: (() -> Void)? = nil
    var onVoiceCancel: (() -> Void)? = nil
    var onVoiceRemediate: ((DeckRemediationAction) -> Void)? = nil

    /// Fleet roster for choosing which Mac receives voice commands.
    var voiceMachines: [HomeMachine] = []
    var voiceTargetMachineID: String? = nil
    var onSelectVoiceTarget: ((HomeMachine) -> Void)? = nil

    @Binding var voicePanelOpen: Bool
    /// Screen previews are on-demand: a live strip of every Mac's display
    /// fights the page for attention, so it stays off until asked for.
    @AppStorage("deck.home.showScreens") private var showScreens = false

    private var foregroundMachine: HomeMachine? {
        machines.first(where: { $0.isForeground })
    }

    private var agentsRunning: Int {
        machines.filter {
            if case .running = $0.agentState { return true }
            return false
        }.count
    }

    private var hasActiveVoiceSession: Bool {
        guard let phase = voiceState?.phase else { return false }
        return phase != .idle || voiceState?.error != nil
    }

    var body: some View {
        Group {
            if machines.isEmpty {
                zeroStateLayout
            } else {
                connectedLayout
            }
        }
        // Auto-open only for the Mac the user already picked — not because some
        // other host's snapshot happened to report voice activity.
        .onChange(of: voiceState?.phase) { _, newPhase in
            guard voiceTargetMachineID != nil else { return }
            if let newPhase, newPhase != .idle {
                voicePanelOpen = true
            }
        }
        .onChange(of: voiceState?.error?.code) { _, newCode in
            guard voiceTargetMachineID != nil else { return }
            if newCode != nil {
                voicePanelOpen = true
            }
        }
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
                onSettings: onSettings,
                onPillTap: onEnterDeck
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HomeTargetsRow(
                        machines: machines,
                        nearbyCandidateCount: nearbyCandidateCount,
                        screensVisible: $showScreens,
                        onEnterDeck: onEnterDeck,
                        onEnterFleet: onEnterFleet,
                        onAddHost: onAddHost,
                        onVoice: onMachineVoice
                    )
                    if showScreens {
                        HomeScreensRow(
                            machines: machines,
                            previews: screenPreviews,
                            onEnterDeck: onEnterDeck
                        )
                    }

                    HomeActivityFeed(
                        recent: recent,
                        agentFeed: agentFeed,
                        attention: attention
                    )

                }
                .padding(.horizontal, horizontalSizeClass == .compact ? 14 : 24)
                .padding(.vertical, horizontalSizeClass == .compact ? 12 : 18)
                .frame(maxWidth: .infinity)
            }

            if voicePanelOpen {
                HomeVoicePanel(
                    voiceState: voiceState,
                    macLabel: voiceMacLabel,
                    isPerforming: isVoicePerforming,
                    isTargetReachable: voiceTargetReachable,
                    machines: voiceMachines,
                    selectedMachineID: voiceTargetMachineID,
                    onSelectMachine: onSelectVoiceTarget,
                    onStart: { onVoiceStart?() },
                    onStop:  { onVoiceStop?() },
                    onCancel: {
                        onVoiceCancel?()
                        voicePanelOpen = false
                    },
                    onClose: {
                        // Dismissing the panel must not leave a microphone open
                        // on a machine you can no longer see. The chevron reads
                        // as "close voice" and used to close only the *panel* —
                        // capture kept running on the remote Mac with nothing on
                        // screen to say so, and no way back to a stop button
                        // except re-opening the panel.
                        //
                        // Only `.listening` holds the mic open; the later phases
                        // are the Mac thinking, and silently cancelling that
                        // would throw away a turn the user already spoke.
                        if voiceState?.phase == .listening { onVoiceStop?() }
                        voicePanelOpen = false
                    },
                    onRemediate: { onVoiceRemediate?($0) }
                )
                .padding(.horizontal, horizontalSizeClass == .compact ? 14 : 24)
                .padding(.bottom, DeckTheme.Space.x8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if cloud.agentsRunning > 0 || cloud.buildsQueued > 0 || cloud.lastDeployAgo != nil {
                HomeCloudStrip(cloud: cloud)
            }
            HomeBottomBar(
                agentState: foregroundAgentState,
                telemetry: bottomTelemetry,
                onCommand: foregroundMachine.map { machine in
                    { onEnterDeck?(machine) }
                },
                onVoice: {
                    if hasActiveVoiceSession {
                        voicePanelOpen = true
                    } else {
                        onVoiceOpen?(nil)
                    }
                }
            )
        }
        .animation(.easeInOut(duration: 0.22), value: voicePanelOpen)
    }
}

// MARK: - Previews

#Preview("Home · 4 machines") {
    LatsBackground(grid: false) {
        HomeView(
            machines:  HomeMock.fleetFour,
            recent:    HomeMock.recent,
            cloud:     HomeMock.cloud,
            agentFeed: HomeMock.agentFeed,
            attention: HomeMock.attention,
            voicePanelOpen: .constant(false)
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Home · 2 machines") {
    LatsBackground {
        HomeView(
            machines:  HomeMock.fleetTwo,
            recent:    HomeMock.recent,
            cloud:     HomeMock.cloud,
            agentFeed: HomeMock.agentFeed,
            attention: HomeMock.attention,
            voicePanelOpen: .constant(false)
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Home · 1 machine") {
    LatsBackground {
        HomeView(
            machines:  HomeMock.fleetOne,
            recent:    HomeMock.recent,
            cloud:     HomeMock.cloud,
            agentFeed: HomeMock.agentFeed,
            attention: HomeMock.attention,
            voicePanelOpen: .constant(false)
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Home · zero state") {
    LatsBackground {
        HomeView(
            machines:  HomeMock.fleetEmpty,
            recent:    HomeMock.recent,
            cloud:     HomeMock.cloud,
            agentFeed: HomeMock.agentFeed,
            attention: HomeMock.attention,
            onPair: {},
            voicePanelOpen: .constant(false)

        )
    }
    .preferredColorScheme(.dark)
}
