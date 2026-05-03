import SwiftUI

/// Per-machine load gauges. Renders 3-4 vertical bar meters showing the
/// telemetry the daemon already publishes (CPU, GPU, memory, thermal).
/// Lives inside the machine card so the live signal sits next to the
/// thing it describes instead of in a detached status bar.
///
/// `compact` shrinks the bar dimensions so the cluster slots into the
/// body row of a target card without growing the card height. The
/// non-compact (full) form is for places with vertical room — e.g. a
/// dedicated telemetry detail view.
struct HomeMachineGauges: View {
    let metrics: HomeMachineMetrics
    /// Height of the bar fill area. Default is the standalone-view size;
    /// in-card uses pass a value tuned to the right-column height.
    var barHeight: CGFloat = 44

    var hasAnyValue: Bool {
        metrics.cpuPercent != nil
            || metrics.gpuPercent != nil
            || metrics.memoryPercent != nil
            || metrics.thermalPercent != nil
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            LatsGauge(label: "CPU", percent: metrics.cpuPercent, barHeight: barHeight)
            LatsGauge(label: "GPU", percent: metrics.gpuPercent, barHeight: barHeight)
            LatsGauge(label: "MEM", percent: metrics.memoryPercent, barHeight: barHeight)
            if metrics.thermalPercent != nil {
                LatsGauge(label: "THM", percent: metrics.thermalPercent, barHeight: barHeight)
            }
        }
        .fixedSize()
    }
}

// MARK: - Vertical gauge primitive

/// Vertical bar meter — value 0…100, color shifts green → amber → red as
/// load climbs past 65 / 85.
///
/// `barHeight` controls how tall the fill area is; bar width and surrounding
/// label/value sizes scale with it so the gauge stays readable from compact
/// in-card usage up to a dedicated telemetry panel.
struct LatsGauge: View {
    let label: String
    let percent: Double?
    var barHeight: CGFloat = 44

    private var barWidth: CGFloat  { barHeight >= 70 ? 16 : 14 }
    private var valueSize: CGFloat { barHeight >= 70 ? 10 : 9 }
    private var labelSize: CGFloat { barHeight >= 70 ? 8  : 7 }
    private var spacing:   CGFloat { barHeight >= 70 ? 4  : 3 }

    var body: some View {
        VStack(spacing: spacing) {
            valueText
            barTrack
            labelText
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var valueText: some View {
        Text(percent.map { "\(Int($0.rounded()))" } ?? "—")
            .font(LatsFont.mono(valueSize, weight: .semibold))
            .foregroundStyle(percent != nil ? LatsPalette.text : LatsPalette.textFaint)
            .monospacedDigit()
    }

    private var barTrack: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(LatsPalette.hairline2, lineWidth: 1)
                )

            if let p = percent {
                GeometryReader { geo in
                    let h = geo.size.height * CGFloat(min(max(p, 0), 100) / 100)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(loadTint(for: p))
                        .frame(height: max(h, 1))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(2)
                }
            }
        }
        .frame(width: barWidth, height: barHeight)
    }

    private var labelText: some View {
        Text(label)
            .font(LatsFont.mono(labelSize, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(LatsPalette.textFaint)
    }

    private func loadTint(for p: Double) -> Color {
        if p >= 85 { return LatsPalette.red }
        if p >= 65 { return LatsPalette.amber }
        return LatsPalette.green
    }

    private var accessibilityDescription: String {
        if let p = percent {
            return "\(label) \(Int(p.rounded())) percent"
        }
        return "\(label) unavailable"
    }
}

// MARK: - Previews

#Preview("Gauges · in-card column") {
    LatsBackground {
        HomeMachineGauges(
            metrics: HomeMachineMetrics(
                cpuPercent: 39,
                gpuPercent: 12,
                memoryPercent: 67,
                thermalPercent: 28
            ),
            barHeight: 80
        )
        .padding(20)
    }
    .preferredColorScheme(.dark)
}

#Preview("Gauges · standalone") {
    LatsBackground {
        HomeMachineGauges(
            metrics: HomeMachineMetrics(
                cpuPercent: 4,
                gpuPercent: 1,
                memoryPercent: 18,
                thermalPercent: 12
            )
        )
        .padding(20)
    }
    .preferredColorScheme(.dark)
}
