import SwiftUI

struct SpeechPlaybackHUDView: View {
    @ObservedObject var queue: SpeechQueue

    var body: some View {
        let snapshot = queue.snapshot
        let job = snapshot.current
        let queuedCount = snapshot.queued.count

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                statusGlyph(for: job?.state)
                VStack(alignment: .leading, spacing: 2) {
                    Text(job?.text ?? "Speech idle")
                        .font(Typo.body(13))
                        .foregroundColor(Palette.text)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Text(statusLabel(job))
                            .font(Typo.monoBold(9))
                            .foregroundColor(statusColor(job?.state))
                            .tracking(0.6)
                        if let source = sourceLine(job?.source) {
                            Text(source)
                                .font(Typo.caption(10))
                                .foregroundColor(Palette.textDim)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if queuedCount > 0 {
                            Text("+\(queuedCount)")
                                .font(Typo.monoBold(9))
                                .foregroundColor(Palette.textMuted)
                        }
                    }
                }
            }

            if let failure = snapshot.failure ?? (job?.state == .failed ? job : nil),
               let error = failure.error, !error.isEmpty {
                HStack(alignment: .top) {
                    Text("Speech failed: \(error)")
                        .font(Typo.caption(11))
                        .foregroundColor(HUDChrome.rose)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    controlButton(systemName: "xmark", label: "Dismiss speech error", enabled: true) {
                        queue.dismissFailure()
                    }
                }
            }

            HStack(spacing: 10) {
                controlButton(
                    systemName: job?.state == .paused ? "play.fill" : "pause.fill",
                    label: job?.state == .paused ? "Resume speech" : "Pause speech",
                    enabled: job?.state == .playing || job?.state == .paused
                ) {
                    togglePause(job)
                }
                SpeechSeekBar(
                    progress: job?.progress ?? 0,
                    enabled: job?.state == .playing || job?.state == .paused
                ) { fraction in
                    seek(job, fraction: fraction)
                }
                .frame(height: 16)
                Text(timeLabel(job))
                    .font(Typo.mono(10))
                    .foregroundColor(Palette.textMuted)
                    .frame(width: 72, alignment: .trailing)
                controlButton(systemName: "forward.fill", label: "Next speech", enabled: queuedCount > 0 || jobIsSkippable(job)) {
                    _ = try? queue.next(jobId: job?.id)
                }
                controlButton(systemName: "stop.fill", label: "Stop speech", enabled: job != nil || queuedCount > 0) {
                    _ = try? queue.stop(jobId: job?.id)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: SpeechHUDPresentation.panelSize.width)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.clear)
                .background(HUDPanelBackground())
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(HUDChrome.glassStroke, lineWidth: 0.8)
        )
        .hudEdgeGlow(intensity: 0.7)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func statusGlyph(for state: SpeechJobState?) -> some View {
        Image(systemName: glyphName(state))
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(statusColor(state))
            .frame(width: 22)
    }

    private func glyphName(_ state: SpeechJobState?) -> String {
        switch state {
        case .playing: return "waveform"
        case .paused: return "pause.fill"
        case .generating: return "ellipsis"
        case .queued: return "text.alignleft"
        case .failed: return "exclamationmark.triangle.fill"
        case .completed: return "checkmark"
        case .cancelled: return "xmark"
        case .none: return "speaker.slash"
        }
    }

    private func statusColor(_ state: SpeechJobState?) -> Color {
        switch state {
        case .playing: return HUDChrome.cyan
        case .paused: return HUDChrome.amber
        case .generating, .queued: return Palette.textDim
        case .failed: return HUDChrome.rose
        case .completed: return Palette.running
        default: return Palette.textMuted
        }
    }

    private func statusLabel(_ job: SpeechJob?) -> String {
        guard let job else { return "IDLE" }
        return job.state.rawValue.uppercased()
    }

    private func sourceLine(_ source: SpeechSourceMetadata?) -> String? {
        guard let source else { return nil }
        let parts = [source.kind, source.label, source.taskId].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func timeLabel(_ job: SpeechJob?) -> String {
        guard let job, job.duration > 0 else { return "--:--" }
        return "\(format(job.currentTime))/\(format(job.duration))"
    }

    private func format(_ time: TimeInterval) -> String {
        let total = max(0, Int(time.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func jobIsSkippable(_ job: SpeechJob?) -> Bool {
        guard let job else { return false }
        switch job.state {
        case .queued, .generating, .playing, .paused:
            return true
        default:
            return false
        }
    }

    private func togglePause(_ job: SpeechJob?) {
        guard let job else { return }
        if job.state == .paused {
            _ = try? queue.resume(jobId: job.id)
        } else if job.state == .playing {
            _ = try? queue.pause(jobId: job.id)
        }
    }

    private func seek(_ job: SpeechJob?, fraction: Double) {
        guard let job, job.duration > 0 else { return }
        _ = try? queue.seek(seconds: job.duration * fraction, jobId: job.id)
    }

    private func controlButton(systemName: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(enabled ? Palette.text : Palette.textMuted)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(enabled ? 0.08 : 0.03))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
        .disabled(!enabled)
    }
}

struct SpeechSeekBar: View {
    var progress: Double
    var enabled: Bool
    var onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let clamped = min(max(progress, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.10))
                Capsule()
                    .fill(enabled ? HUDChrome.cyan : Palette.textMuted)
                    .frame(width: max(6, geo.size.width * CGFloat(clamped)))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Speech progress")
            .accessibilityValue("\(Int(clamped * 100)) percent")
            .accessibilityAdjustableAction { direction in
                guard enabled else { return }
                switch direction {
                case .increment: onSeek(min(clamped + 0.05, 1))
                case .decrement: onSeek(max(clamped - 0.05, 0))
                @unknown default: break
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard enabled, geo.size.width > 0 else { return }
                        onSeek(min(max(Double(value.location.x / geo.size.width), 0), 1))
                    }
            )
        }
    }
}
