import DeckKit
import SwiftUI

/// Inline voice panel — slots into the Home layout above the cloud strip
/// instead of taking over the screen. The dashboard stays visible above so
/// the user can see fleet state while dictating.
///
/// Renders nothing when there's nothing to say (idle, no transcript, no
/// response, no error, panel not explicitly opened). Hosting view controls
/// visibility via `isOpen` so an explicit FAB tap can pre-open the panel
/// before any state arrives from the Mac.
struct HomeVoicePanel: View {
    let voiceState: DeckVoiceState?
    let macLabel: String
    let isPerforming: Bool

    var onStart: () -> Void
    var onStop: () -> Void
    var onCancel: () -> Void
    var onClose: () -> Void
    var onRemediate: ((DeckRemediationAction) -> Void)? = nil

    private var phase: DeckVoicePhase { voiceState?.phase ?? .idle }
    private var error: DeckVoiceError? { voiceState?.error }

    private var transcript: String? {
        let raw = voiceState?.transcript?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (raw?.isEmpty == false) ? raw : nil
    }

    private var responseSummary: String? {
        let raw = voiceState?.responseSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else { return nil }
        if raw == "Transcribing..." || raw == "thinking..." { return nil }
        return raw
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                // Single round CTA — combines mic icon, phase indicator, and
                // start/stop action into one tap target. Color + glyph reflect
                // current phase; tapping advances the state.
                VoiceCTA(
                    phase: phase,
                    severity: error?.severity,
                    onTap: handlePrimaryTap
                )
                .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 8) {
                    headerRow

                    Text(caption)
                        .font(LatsFont.mono(11))
                        .tracking(0.4)
                        .foregroundStyle(LatsPalette.textDim)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let transcript {
                        transcriptInline(transcript)
                    }
                    if let responseSummary {
                        responseInline(responseSummary)
                    }
                    if let error {
                        errorInline(error)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(Color.black.opacity(0.32))
        .overlay(alignment: .top) {
            Rectangle().fill(LatsPalette.hairline2).frame(height: 1)
        }
    }

    // MARK: - Header — target label + close

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text(macLabel.lowercased())
                .font(LatsFont.mono(11))
                .tracking(0.5)
                .foregroundStyle(LatsPalette.textDim)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button(action: onClose) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LatsPalette.textDim)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close voice")
        }
    }

    // MARK: - Tap routing for the single CTA

    /// One button, three jobs depending on phase. Idle starts; listening stops;
    /// transcribing/reasoning/speaking cancels the in-flight turn. Errors with
    /// remediations route through the remediation handler instead.
    private func handlePrimaryTap() {
        if let err = error, let remediation = err.remediation {
            onRemediate?(remediation)
            return
        }
        switch phase {
        case .idle:
            onStart()
        case .listening:
            onStop()
        case .transcribing, .reasoning, .speaking:
            onCancel()
        }
    }

    // MARK: - Inline transcript / response / error

    private func transcriptInline(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("›")
                .font(LatsFont.mono(12, weight: .semibold))
                .foregroundStyle(LatsPalette.green.opacity(0.8))
            Text(text)
                .font(LatsFont.mono(12))
                .foregroundStyle(LatsPalette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
        }
    }

    private func responseInline(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(LatsPalette.green)
                .frame(width: 12)
            Text(text)
                .font(LatsFont.ui(12))
                .foregroundStyle(LatsPalette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func errorInline(_ err: DeckVoiceError) -> some View {
        let tint = severityTint(err.severity)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: severityIcon(err.code))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                Text(err.code.rawValue.uppercased())
                    .font(LatsFont.mono(9, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(tint)
                Spacer()
            }
            Text(err.message)
                .font(LatsFont.ui(12, weight: .medium))
                .foregroundStyle(LatsPalette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
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
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(tint.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(tint.opacity(0.4), lineWidth: 1))
    }

    // MARK: - Phase / severity helpers

    private var caption: String {
        if error != nil { return "voice paused — see status above" }
        switch phase {
        case .idle:         return "tap to dictate on \(macLabel)"
        case .listening:    return "listening on \(macLabel) — tap to stop"
        case .transcribing: return "transcribing…"
        case .reasoning:    return "matching intent…"
        case .speaking:     return "responding…"
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
        case .error,
             .blocked: return LatsPalette.red
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
        case .openVox:            return "Open Vox"
        case .openSystemSettings: return "Open settings"
        case .retryVoice:         return "Retry"
        case .openDiagnostics:    return "Open diagnostics"
        case .chooseTarget:       return "Pick target"
        }
    }

    private func remediationIcon(_ remediation: DeckRemediationAction) -> String {
        switch remediation {
        case .openVox:            return "waveform"
        case .openSystemSettings: return "gearshape"
        case .retryVoice:         return "arrow.clockwise"
        case .openDiagnostics:    return "stethoscope"
        case .chooseTarget:       return "scope"
        }
    }

    private func remediationTint(_ severity: DeckErrorSeverity) -> LatsTint {
        switch severity {
        case .info:    return .blue
        case .warning: return .amber
        case .error,
             .blocked: return .red
        }
    }
}

// MARK: - VoiceCTA — single round button that absorbs orb + phase pill + action

/// A round mic button whose color, glyph, and pulse animation reflect the
/// current voice phase. Replaces the old triple of orb + "READY" pill +
/// Start/Stop button with one tappable surface — the host wires its tap to
/// a phase-aware handler that starts, stops, or cancels as appropriate.
struct VoiceCTA: View {
    let phase: DeckVoicePhase
    let severity: DeckErrorSeverity?
    var onTap: () -> Void

    @State private var pulse: Bool = false

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Outer pulse ring — only animates while listening so the
                // CTA visually "hears."
                Circle()
                    .stroke(tint.opacity(0.45), lineWidth: 1.5)
                    .scaleEffect(pulse ? 1.18 : 1.0)
                    .opacity(pulse ? 0.0 : 0.85)
                    .animation(
                        isAnimating
                            ? .easeOut(duration: 1.4).repeatForever(autoreverses: false)
                            : .default,
                        value: pulse
                    )

                Circle().fill(tint.opacity(0.18))
                Circle().stroke(tint.opacity(0.55), lineWidth: 1)

                if isThinking {
                    ProgressView()
                        .tint(tint)
                        .scaleEffect(0.9)
                } else {
                    Image(systemName: glyph)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(tint)
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .onAppear { if isAnimating { pulse = true } }
        .onChange(of: phase) { _, _ in pulse = isAnimating }
        .accessibilityLabel(accessibilityLabel)
    }

    private var isAnimating: Bool { severity == nil && phase == .listening }
    private var isThinking: Bool {
        severity == nil && (phase == .transcribing || phase == .reasoning || phase == .speaking)
    }

    private var tint: Color {
        if let severity {
            switch severity {
            case .info:    return LatsPalette.blue
            case .warning: return LatsPalette.amber
            case .error,
                 .blocked: return LatsPalette.red
            }
        }
        switch phase {
        case .idle:         return LatsPalette.violet
        case .listening:    return LatsPalette.red
        case .transcribing: return LatsPalette.teal
        case .reasoning:    return LatsPalette.violet
        case .speaking:     return LatsPalette.blue
        }
    }

    private var glyph: String {
        if severity != nil { return "exclamationmark.triangle.fill" }
        switch phase {
        case .idle:      return "mic.fill"
        case .listening: return "stop.fill"
        default:         return "mic.fill"
        }
    }

    private var accessibilityLabel: String {
        if severity != nil { return "Resolve voice issue" }
        switch phase {
        case .idle:      return "Start dictation"
        case .listening: return "Stop dictation"
        default:         return "Cancel voice turn"
        }
    }
}

// MARK: - Previews

#Preview("Panel · listening") {
    LatsBackground {
        VStack {
            Spacer()
            HomeVoicePanel(
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
    }
    .preferredColorScheme(.dark)
}

#Preview("Panel · result") {
    LatsBackground {
        VStack {
            Spacer()
            HomeVoicePanel(
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
    }
    .preferredColorScheme(.dark)
}

#Preview("Panel · error") {
    LatsBackground {
        VStack {
            Spacer()
            HomeVoicePanel(
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
    }
    .preferredColorScheme(.dark)
}
