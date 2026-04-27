import DeckKit
import SwiftUI

/// Full-screen voice modal. Renders the active relay session: phase, live
/// transcript, response, and (when present) a structured `DeckVoiceError`
/// with a remediation button. iPad never owns the mic — it's a status mirror
/// for the Mac that's actually listening.
///
/// Presented as `.fullScreenCover` from `HomeView` when the user taps the
/// voice button in `HomeBottomBar`. Auto-dismisses ~1.4s after the Mac
/// returns to `idle` with a successful `responseSummary`; sticks around when
/// there's an error so the user can read + retry.
struct HomeVoiceOverlay: View {
    let voiceState: DeckVoiceState?
    let macLabel: String
    let isPerforming: Bool

    var onStart: () -> Void
    var onStop: () -> Void
    var onCancel: () -> Void
    var onClose: () -> Void
    var onRemediate: ((DeckRemediationAction) -> Void)? = nil

    private var phase: DeckVoicePhase {
        voiceState?.phase ?? .idle
    }

    private var transcript: String? {
        let raw = voiceState?.transcript?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (raw?.isEmpty == false) ? raw : nil
    }

    private var responseSummary: String? {
        let raw = voiceState?.responseSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else { return nil }
        // The Mac uses these as transient state markers; don't parrot them.
        if raw == "Transcribing..." || raw == "thinking..." { return nil }
        return raw
    }

    private var error: DeckVoiceError? { voiceState?.error }

    var body: some View {
        LatsBackground {
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                hero
                Spacer(minLength: 0)
                bodySection
                Spacer(minLength: 0)
                bottomBar
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LatsPalette.violet)

            Text("VOICE")
                .font(LatsFont.mono(11, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(LatsPalette.text)

            Text("·").foregroundStyle(LatsPalette.textFaint)

            Text(macLabel)
                .font(LatsFont.mono(11))
                .tracking(0.6)
                .foregroundStyle(LatsPalette.textDim)
                .lineLimit(1)

            Spacer(minLength: 8)

            phasePill

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LatsPalette.textDim)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Color.black.opacity(0.28))
        .overlay(alignment: .bottom) {
            Rectangle().fill(LatsPalette.hairline).frame(height: 1)
        }
    }

    private var phasePill: some View {
        HStack(spacing: 5) {
            Circle().fill(phaseTint).frame(width: 6, height: 6)
            Text(phaseLabel)
                .font(LatsFont.mono(9, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(phaseTint)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4).fill(phaseTint.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4).stroke(phaseTint.opacity(0.4), lineWidth: 1)
        )
        .fixedSize()
    }

    // MARK: - Hero (animated voice glyph)

    private var hero: some View {
        VStack(spacing: 18) {
            VoiceOrb(phase: phase, severity: error?.severity)
                .frame(width: 168, height: 168)

            Text(heroCaption)
                .font(LatsFont.mono(11))
                .tracking(0.6)
                .foregroundStyle(LatsPalette.textDim)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
    }

    private var heroCaption: String {
        if error != nil { return "voice paused — see status below" }
        switch phase {
        case .idle:         return "tap start to dictate on \(macLabel)"
        case .listening:    return "listening on \(macLabel) — tap stop when done"
        case .transcribing: return "transcribing…"
        case .reasoning:    return "matching intent…"
        case .speaking:     return "responding…"
        }
    }

    // MARK: - Body — transcript, response, error

    @ViewBuilder
    private var bodySection: some View {
        VStack(spacing: 12) {
            if let error {
                errorCard(error)
            }

            if let transcript {
                transcriptCard(transcript)
            }

            if let responseSummary {
                responseCard(responseSummary)
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: 620)
    }

    private func transcriptCard(_ text: String) -> some View {
        LatsCard(padding: 14, radius: 8) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(LatsPalette.green).frame(width: 5, height: 5)
                    Text("TRANSCRIPT")
                        .font(LatsFont.mono(9, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(LatsPalette.textFaint)
                    Spacer()
                }
                Text(text)
                    .font(LatsFont.mono(13))
                    .foregroundStyle(LatsPalette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    private func responseCard(_ text: String) -> some View {
        LatsCard(padding: 14, radius: 8) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(LatsPalette.green)
                    Text("RESULT")
                        .font(LatsFont.mono(9, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(LatsPalette.textFaint)
                    Spacer()
                }
                Text(text)
                    .font(LatsFont.ui(13))
                    .foregroundStyle(LatsPalette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func errorCard(_ err: DeckVoiceError) -> some View {
        let tint = severityTint(err.severity)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: severityIcon(err.code))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)

                Text(err.code.rawValue.uppercased())
                    .font(LatsFont.mono(10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(tint)

                Spacer()

                Text(err.severity.rawValue.uppercased())
                    .font(LatsFont.mono(9, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(tint.opacity(0.8))
            }

            Text(err.message)
                .font(LatsFont.ui(13, weight: .medium))
                .foregroundStyle(LatsPalette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)

            if let owner = err.owner {
                Text("owner · \(owner)")
                    .font(LatsFont.mono(10))
                    .foregroundStyle(LatsPalette.textDim)
            }

            if let remediation = err.remediation {
                LatsButton(
                    title: remediationLabel(remediation),
                    icon: remediationIcon(remediation),
                    style: .primary(remediationTint(err.severity))
                ) {
                    onRemediate?(remediation)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8).stroke(tint.opacity(0.45), lineWidth: 1)
        )
    }

    // MARK: - Bottom bar — primary action

    private var bottomBar: some View {
        HStack(spacing: 12) {
            switch phase {
            case .idle:
                LatsButton(title: "Start", icon: "mic.fill", style: .primary(.green), action: onStart)
                LatsButton(title: "Close", icon: "xmark", style: .ghost, action: onClose)

            case .listening:
                LatsButton(title: "Stop", icon: "stop.fill", style: .primary(.red), action: onStop)
                LatsButton(title: "Cancel", icon: "xmark", style: .ghost, action: onCancel)

            case .transcribing, .reasoning, .speaking:
                LatsButton(title: "Cancel", icon: "xmark", style: .ghost, action: onCancel)
            }

            Spacer(minLength: 0)

            if isPerforming {
                ProgressView().tint(LatsPalette.violet)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.30))
        .overlay(alignment: .top) {
            Rectangle().fill(LatsPalette.hairline2).frame(height: 1)
        }
    }

    // MARK: - Phase / severity / remediation helpers

    private var phaseLabel: String {
        switch phase {
        case .idle:         return "READY"
        case .listening:    return "LISTENING"
        case .transcribing: return "TRANSCRIBE"
        case .reasoning:    return "THINKING"
        case .speaking:     return "REPLYING"
        }
    }

    private var phaseTint: Color {
        if let err = error { return severityTint(err.severity) }
        switch phase {
        case .idle:         return LatsPalette.textDim
        case .listening:    return LatsPalette.green
        case .transcribing: return LatsPalette.teal
        case .reasoning:    return LatsPalette.violet
        case .speaking:     return LatsPalette.blue
        }
    }

    private func severityTint(_ severity: DeckErrorSeverity) -> Color {
        switch severity {
        case .info:    return LatsPalette.blue
        case .warning: return LatsPalette.amber
        case .error:   return LatsPalette.red
        case .blocked: return LatsPalette.red
        }
    }

    private func severityIcon(_ code: DeckVoiceErrorCode) -> String {
        switch code {
        case .micDenied:           return "mic.slash"
        case .accessibilityDenied: return "lock.shield"
        case .micBusy:             return "mic.badge.xmark"
        case .voxNotRunning,
             .voxLoading,
             .voxUnreachable:      return "waveform.badge.exclamationmark"
        case .daemonUnreachable,
             .network,
             .connectionLost:      return "wifi.exclamationmark"
        case .noActiveTarget:      return "scope"
        case .intentUnresolved:    return "questionmark.circle"
        case .actionFailed:        return "bolt.trianglebadge.exclamationmark"
        case .transcriptionFailed: return "waveform.slash"
        case .emptyTranscript:     return "ear"
        case .languageUnsupported: return "globe"
        }
    }

    private func remediationLabel(_ remediation: DeckRemediationAction) -> String {
        switch remediation {
        case .openVox:                  return "Open Vox"
        case .openSystemSettings:       return "Open settings"
        case .retryVoice:               return "Retry"
        case .openDiagnostics:          return "Open diagnostics"
        case .chooseTarget:             return "Pick target"
        }
    }

    private func remediationIcon(_ remediation: DeckRemediationAction) -> String {
        switch remediation {
        case .openVox:                  return "waveform"
        case .openSystemSettings:       return "gearshape"
        case .retryVoice:               return "arrow.clockwise"
        case .openDiagnostics:          return "stethoscope"
        case .chooseTarget:             return "scope"
        }
    }

    private func remediationTint(_ severity: DeckErrorSeverity) -> LatsTint {
        switch severity {
        case .info:    return .blue
        case .warning: return .amber
        case .error:   return .red
        case .blocked: return .red
        }
    }
}

// MARK: - Voice orb

private struct VoiceOrb: View {
    let phase: DeckVoicePhase
    let severity: DeckErrorSeverity?

    @State private var pulse: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(orbTint.opacity(0.18), lineWidth: 1)

            Circle()
                .stroke(orbTint.opacity(0.32), lineWidth: 1)
                .scaleEffect(pulse ? 1.15 : 0.92)
                .opacity(pulse ? 0.0 : 0.7)
                .animation(
                    isAnimating
                        ? .easeOut(duration: 1.6).repeatForever(autoreverses: false)
                        : .default,
                    value: pulse
                )

            Circle()
                .fill(orbTint.opacity(0.10))

            Image(systemName: orbIcon)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(orbTint)
        }
        .onAppear { if isAnimating { pulse = true } }
        .onChange(of: phase) { _, _ in pulse = isAnimating }
    }

    private var isAnimating: Bool {
        severity == nil && (phase == .listening || phase == .transcribing || phase == .reasoning || phase == .speaking)
    }

    private var orbTint: Color {
        if let severity {
            switch severity {
            case .info:    return LatsPalette.blue
            case .warning: return LatsPalette.amber
            case .error,
                 .blocked: return LatsPalette.red
            }
        }
        switch phase {
        case .idle:         return LatsPalette.textDim
        case .listening:    return LatsPalette.green
        case .transcribing: return LatsPalette.teal
        case .reasoning:    return LatsPalette.violet
        case .speaking:     return LatsPalette.blue
        }
    }

    private var orbIcon: String {
        if severity != nil { return "exclamationmark.triangle" }
        switch phase {
        case .idle:         return "mic"
        case .listening:    return "mic.fill"
        case .transcribing: return "waveform"
        case .reasoning:    return "sparkles"
        case .speaking:     return "speaker.wave.2"
        }
    }
}

// MARK: - Previews

#Preview("Idle") {
    HomeVoiceOverlay(
        voiceState: DeckVoiceState(phase: .idle, provider: "vox"),
        macLabel: "arach-laptop",
        isPerforming: false,
        onStart: {}, onStop: {}, onCancel: {}, onClose: {}
    )
}

#Preview("Listening") {
    HomeVoiceOverlay(
        voiceState: DeckVoiceState(
            phase: .listening,
            transcript: "tile chrome two-up right",
            provider: "vox"
        ),
        macLabel: "arach-laptop",
        isPerforming: false,
        onStart: {}, onStop: {}, onCancel: {}, onClose: {}
    )
}

#Preview("Result") {
    HomeVoiceOverlay(
        voiceState: DeckVoiceState(
            phase: .idle,
            transcript: "tile chrome two-up right",
            responseSummary: "Tiled 3 windows in two columns on display 1",
            provider: "vox"
        ),
        macLabel: "arach-laptop",
        isPerforming: false,
        onStart: {}, onStop: {}, onCancel: {}, onClose: {}
    )
}

#Preview("Error · mic_busy") {
    HomeVoiceOverlay(
        voiceState: DeckVoiceState(
            phase: .idle,
            provider: "vox",
            error: DeckVoiceError(
                code: .micBusy,
                severity: .warning,
                recoverable: true,
                retry: .userAction,
                source: .vox,
                owner: "Vox",
                message: "Mic in use by Vox — finish your memo first",
                remediation: .retryVoice
            )
        ),
        macLabel: "arach-laptop",
        isPerforming: false,
        onStart: {}, onStop: {}, onCancel: {}, onClose: {}
    )
}

#Preview("Error · vox_not_running") {
    HomeVoiceOverlay(
        voiceState: DeckVoiceState(
            phase: .idle,
            provider: "vox",
            error: DeckVoiceError(
                code: .voxNotRunning,
                severity: .error,
                recoverable: true,
                retry: .afterLaunch,
                source: .mac,
                message: "Vox offline — start it to dictate",
                remediation: .openVox
            )
        ),
        macLabel: "arach-laptop",
        isPerforming: false,
        onStart: {}, onStop: {}, onCancel: {}, onClose: {}
    )
}
