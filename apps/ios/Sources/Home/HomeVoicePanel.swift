import DeckKit
import SwiftUI

/// Inline voice panel — slots into the Home layout above the cloud strip.
///
/// Flow: open panel → pick a Mac → tap mic to start. Nothing arms a host
/// microphone until both steps are deliberate.
struct HomeVoicePanel: View {
    let voiceState: DeckVoiceState?
    let macLabel: String
    let isPerforming: Bool
    var isTargetReachable: Bool = true
    var machines: [HomeMachine] = []
    var selectedMachineID: String? = nil
    var onSelectMachine: ((HomeMachine) -> Void)? = nil

    var onStart: () -> Void
    var onStop: () -> Void
    var onCancel: () -> Void
    var onClose: () -> Void
    var onRemediate: ((DeckRemediationAction) -> Void)? = nil

    private var phase: DeckVoicePhase { voiceState?.phase ?? .idle }
    private var error: DeckVoiceError? { voiceState?.error }
    private var hasSelectedTarget: Bool { selectedMachineID != nil }

    private var transcript: String? {
        let raw = voiceState?.transcript?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (raw?.isEmpty == false) ? raw : nil
    }

    private var responseSummary: String? {
        let raw = voiceState?.responseSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else { return nil }
        if DeckVoiceErrorMapper.isProgressMessage(raw) { return nil }
        return raw
    }

    var body: some View {
        FleetWell(radius: DeckTheme.radiusWell) {
            VStack(alignment: .leading, spacing: DeckTheme.Space.sectionGap) {
                headerRow

                targetSection

                HStack(alignment: .center, spacing: DeckTheme.Space.sectionGap) {
                    VoiceCTA(
                        phase: phase,
                        severity: error?.severity,
                        isEnabled: canTapMic,
                        onTap: handlePrimaryTap
                    )
                    .frame(width: 56, height: 56)

                    VStack(alignment: .leading, spacing: 6) {
                        if showsPhaseLabel {
                            Text(phaseLabel)
                                .font(DeckTheme.caption(.semibold))
                                .foregroundStyle(phaseChipForeground)
                        }

                        Text(caption)
                            .font(DeckTheme.secondary())
                            .foregroundStyle(DeckTheme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if transcript != nil || responseSummary != nil || error != nil {
                    VStack(alignment: .leading, spacing: DeckTheme.Space.x8) {
                        if let transcript {
                            speechBlock(label: "You said", text: transcript)
                        }
                        if let responseSummary {
                            speechBlock(label: "Result", text: responseSummary, highlighted: true)
                        }
                        if let error {
                            errorInline(error)
                        }
                    }
                }
            }
            .padding(.horizontal, DeckTheme.Space.wellPad)
            .padding(.vertical, DeckTheme.Space.cardPadV)
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .top, spacing: DeckTheme.Space.x8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Voice")
                    .font(DeckTheme.secondary(.semibold))
                    .foregroundStyle(DeckTheme.text)
                if hasSelectedTarget {
                    Text(macLabel)
                        .font(DeckTheme.caption())
                        .foregroundStyle(isTargetReachable ? DeckTheme.textSecondary : DeckTheme.accent)
                        .lineLimit(1)
                } else if machines.count > 1 {
                    Text("Pick a Mac, then tap the mic")
                        .font(DeckTheme.caption())
                        .foregroundStyle(DeckTheme.textTertiary)
                }
            }

            Spacer(minLength: 8)

            Button(action: onClose) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DeckTheme.textTertiary)
                    .frame(width: 36, height: 36)
                    .background(DeckTheme.control)
                    .clipShape(RoundedRectangle(cornerRadius: DeckTheme.radiusSmall, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: DeckTheme.radiusSmall, style: .continuous)
                            .strokeBorder(DeckTheme.hairline, lineWidth: 1)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close voice")
        }
    }

    private var targetSection: some View {
        Group {
            if machines.count > 1 {
                VStack(alignment: .leading, spacing: DeckTheme.Space.x8) {
                    Text("Speak to")
                        .font(DeckTheme.caption())
                        .foregroundStyle(DeckTheme.textTertiary)

                    if machines.isEmpty {
                        Text("No paired Macs are reachable right now.")
                            .font(DeckTheme.secondary())
                            .foregroundStyle(DeckTheme.textSecondary)
                    } else {
                        voiceTargetPicker
                    }
                }
            } else if let only = machines.first {
                HStack(spacing: 8) {
                    Image(systemName: only.isForeground ? "laptopcomputer" : "desktopcomputer")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DeckTheme.textTertiary)
                    Text(only.name)
                        .font(DeckTheme.caption(.medium))
                        .foregroundStyle(DeckTheme.textSecondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DeckTheme.control)
                .clipShape(RoundedRectangle(cornerRadius: DeckTheme.radiusCard, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: DeckTheme.radiusCard, style: .continuous)
                        .strokeBorder(DeckTheme.hairline, lineWidth: 1)
                }
            }
        }
    }

    private var voiceTargetPicker: some View {
        Group {
            if machines.count <= 2 {
                HStack(spacing: 8) {
                    ForEach(machines) { machine in
                        voiceTargetChip(for: machine)
                            .frame(maxWidth: .infinity)
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(machines) { machine in
                            voiceTargetChip(for: machine)
                        }
                    }
                }
            }
        }
    }

    private func voiceTargetChip(for machine: HomeMachine) -> some View {
        let selected = machine.id == selectedMachineID
        let reachable = machine.status != .offline
        return Button {
            DeckTactileFeedback.shared.rotaryTick()
            onSelectMachine?(machine)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: machine.isForeground ? "laptopcomputer" : "desktopcomputer")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(selected ? DeckTheme.text : DeckTheme.textTertiary)
                    .frame(width: 14, alignment: .center)

                Text(machine.name)
                    .font(DeckTheme.caption(.medium))
                    .foregroundStyle(selected ? DeckTheme.text : DeckTheme.textSecondary)
                    .lineLimit(1)

                if !reachable {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DeckTheme.textTertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: DeckTheme.radiusCard, style: .continuous)
                    .fill(selected ? DeckTheme.card : DeckTheme.control)
            }
            .overlay {
                RoundedRectangle(cornerRadius: DeckTheme.radiusCard, style: .continuous)
                    .strokeBorder(
                        selected ? DeckTheme.hairlineStrong : DeckTheme.hairline,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Speak to \(machine.name)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Tap routing

    private var canTapMic: Bool {
        if error != nil { return true }
        if phase == .idle {
            return hasSelectedTarget && isTargetReachable && !machines.isEmpty
        }
        return isTargetReachable
    }

    private func handlePrimaryTap() {
        if let err = error, let remediation = err.remediation {
            onRemediate?(remediation)
            return
        }
        switch phase {
        case .idle:
            guard hasSelectedTarget else { return }
            DeckTactileFeedback.shared.tilePress(isAccent: true)
            onStart()
        case .listening:
            DeckTactileFeedback.shared.buttonPop()
            onStop()
        case .transcribing, .reasoning, .speaking:
            DeckTactileFeedback.shared.buttonPop()
            onCancel()
        }
    }

    // MARK: - Content rows

    private func speechBlock(label: String, text: String, highlighted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(DeckTheme.caption())
                .foregroundStyle(DeckTheme.textTertiary)
            Text(text)
                .font(DeckTheme.body())
                .foregroundStyle(DeckTheme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .lineSpacing(2)
        }
        .padding(DeckTheme.Space.x12)
        .background(highlighted ? DeckTheme.accentFill : DeckTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: DeckTheme.radiusCard, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DeckTheme.radiusCard, style: .continuous)
                .strokeBorder(highlighted ? DeckTheme.accent.opacity(0.25) : DeckTheme.hairline, lineWidth: 1)
        }
    }

    private func errorInline(_ err: DeckVoiceError) -> some View {
        VStack(alignment: .leading, spacing: DeckTheme.Space.x8) {
            HStack(spacing: 8) {
                Image(systemName: severityIcon(err.code))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(severityTint(err.severity))
                Text(err.message)
                    .font(DeckTheme.secondary())
                    .foregroundStyle(DeckTheme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }
            if let remediation = err.remediation {
                Button {
                    DeckTactileFeedback.shared.tilePress(isAccent: true)
                    onRemediate?(remediation)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: remediationIcon(remediation))
                            .font(.system(size: 11, weight: .semibold))
                        Text(remediationLabel(remediation))
                            .font(DeckTheme.caption(.semibold))
                    }
                    .foregroundStyle(DeckTheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(DeckTheme.accentFill)
                    .clipShape(RoundedRectangle(cornerRadius: DeckTheme.radiusSmall, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: DeckTheme.radiusSmall, style: .continuous)
                            .strokeBorder(DeckTheme.accent.opacity(0.35), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DeckTheme.Space.x12)
        .background(DeckTheme.errorFill)
        .clipShape(RoundedRectangle(cornerRadius: DeckTheme.radiusCard, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DeckTheme.radiusCard, style: .continuous)
                .strokeBorder(DeckTheme.error.opacity(0.35), lineWidth: 1)
        }
    }

    // MARK: - Phase / severity helpers

    private var showsPhaseLabel: Bool {
        error != nil || phase != .idle || isPerforming || !hasSelectedTarget || (hasSelectedTarget && !isTargetReachable)
    }

    private var caption: String {
        if error != nil { return "Voice paused — see below" }
        if !hasSelectedTarget {
            return machines.count > 1
                ? "Choose which Mac should hear you, then tap the mic."
                : "Tap the mic when you're ready to speak."
        }
        if !isTargetReachable {
            return "Connecting to \(macLabel)… pick another Mac if this takes too long."
        }
        if isPerforming && phase == .idle {
            return "Connecting to voice runtime on \(macLabel)…"
        }
        if let status = voiceState?.statusLine, !status.isEmpty {
            return status
        }
        if let kind = voiceState?.turnKind, phase == .reasoning || phase == .speaking {
            switch kind {
            case .quick:
                return "Quick command on \(macLabel)…"
            case .standard:
                return "Working on \(macLabel)…"
            case .conversation:
                return "Thinking on \(macLabel)…"
            }
        }
        switch phase {
        case .idle:         return "Uses \(macLabel)'s microphone — nothing is recorded until you tap."
        case .listening:    return "Listening on \(macLabel). Tap again to send."
        case .transcribing: return "Understanding what you said…"
        case .reasoning:    return "Running on \(macLabel)…"
        case .speaking:     return "Speaking the reply…"
        }
    }

    private var phaseLabel: String {
        if error != nil { return "Paused" }
        if !hasSelectedTarget { return "Pick a Mac" }
        if !isTargetReachable { return "Connecting" }
        if isPerforming && phase == .idle { return "Connecting" }
        if let stage = voiceState?.turnStage {
            switch stage {
            case .acknowledging: return "Got it"
            case .understanding: return "Understanding"
            case .planning: return voiceState?.turnKind == .quick ? "Running" : "Planning"
            case .narrating: return "Speaking"
            case .executing: return voiceState?.turnKind == .quick ? "Running" : "Working"
            case .confirming: return "Done"
            }
        }
        switch phase {
        case .idle:         return "Ready"
        case .listening:    return "Listening"
        case .transcribing: return "Understanding"
        case .reasoning:    return "Working"
        case .speaking:     return "Speaking"
        }
    }

    private var phaseChipForeground: Color {
        if error != nil { return DeckTheme.error }
        if !hasSelectedTarget { return DeckTheme.textTertiary }
        if !isTargetReachable { return DeckTheme.accent }
        switch phase {
        case .idle:         return DeckTheme.textSecondary
        case .listening:    return DeckTheme.accent
        case .transcribing, .reasoning, .speaking: return DeckTheme.text
        }
    }

    private func severityTint(_ severity: DeckErrorSeverity) -> Color {
        switch severity {
        case .info:    return DeckTheme.textSecondary
        case .warning: return DeckTheme.accent
        case .error,
             .blocked: return DeckTheme.error
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
        case .openSystemSettings: return "Open Settings"
        case .retryVoice:         return "Retry"
        case .openDiagnostics:    return "Diagnostics"
        case .chooseTarget:       return "Pick Mac"
        }
    }

    private func remediationIcon(_ remediation: DeckRemediationAction) -> String {
        switch remediation {
        case .openVox:            return "waveform"
        case .openSystemSettings: return "gearshape"
        case .retryVoice:         return "arrow.clockwise"
        case .openDiagnostics:    return "stethoscope"
        case .chooseTarget:       return "laptopcomputer.and.arrow.down"
        }
    }
}

// MARK: - Voice CTA

struct VoiceCTA: View {
    let phase: DeckVoicePhase
    let severity: DeckErrorSeverity?
    var isEnabled: Bool = true
    var onTap: () -> Void

    @State private var pulse: Bool = false

    var body: some View {
        Button(action: onTap) {
            ZStack {
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

                Circle().fill(tint.opacity(isEnabled ? 0.18 : 0.08))
                Circle().stroke(tint.opacity(isEnabled ? 0.55 : 0.25), lineWidth: 1)

                if isThinking {
                    ProgressView()
                        .tint(tint)
                        .scaleEffect(0.9)
                } else {
                    Image(systemName: glyph)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(tint.opacity(isEnabled ? 1 : 0.45))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .contentShape(Circle())
        .onAppear { if isAnimating { pulse = true } }
        .onChange(of: phase) { _, _ in pulse = isAnimating }
        .accessibilityLabel(accessibilityLabel)
    }

    private var isAnimating: Bool { isEnabled && severity == nil && phase == .listening }
    private var isThinking: Bool {
        severity == nil && (phase == .transcribing || phase == .reasoning || phase == .speaking)
    }

    private var tint: Color {
        if !isEnabled { return DeckTheme.textTertiary }
        if let severity {
            switch severity {
            case .info:    return DeckTheme.textSecondary
            case .warning: return DeckTheme.accent
            case .error,
                 .blocked: return DeckTheme.error
            }
        }
        switch phase {
        case .idle:         return DeckTheme.accent
        case .listening:    return DeckTheme.accent
        case .transcribing: return DeckTheme.text
        case .reasoning:    return DeckTheme.text
        case .speaking:     return DeckTheme.textSecondary
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
        if !isEnabled { return "Select a Mac first" }
        if severity != nil { return "Resolve voice issue" }
        switch phase {
        case .idle:      return "Start dictation"
        case .listening: return "Stop dictation"
        default:         return "Cancel voice turn"
        }
    }
}
