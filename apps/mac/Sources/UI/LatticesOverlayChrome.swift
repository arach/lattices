import SwiftUI

// MARK: - Metrics

/// Shared insets so the strip mark and corner watermark share one vertical axis.
enum LatticesOverlayMetrics {
    static let edgeInset: CGFloat = 16
    static let watermarkBottomInset: CGFloat = 14
}

// MARK: - Lattice grid

/// Faint dot lattice — signature background for overlay chrome.
struct LatticesLatticeGrid: View {
    var spacing: CGFloat = 22
    var dotSize: CGFloat = 1.2
    var opacity: Double = 0.05
    var tint: Color = Palette.running

    var body: some View {
        Canvas { context, size in
            let xStart = -spacing
            let yStart = -spacing
            for x in stride(from: xStart, through: size.width + spacing, by: spacing) {
                for y in stride(from: yStart, through: size.height + spacing, by: spacing) {
                    let rect = CGRect(x: x - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize)
                    context.fill(Path(ellipseIn: rect), with: .color(tint.opacity(opacity)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Watermark

/// Quiet corner mark — present but easy to ignore.
struct LatticesOverlayWatermark: View {
    var size: CGFloat = 56
    var opacity: Double = 0.07

    var body: some View {
        LatticesMark(size: size, tint: Palette.running, dimOpacity: 0.10)
            .opacity(opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Bottom-leading placement — left edge lines up with the strip header mark.
struct LatticesOverlayWatermarkPlacement: View {
    var body: some View {
        LatticesOverlayWatermark()
            .padding(.leading, LatticesOverlayMetrics.edgeInset)
            .padding(.bottom, LatticesOverlayMetrics.watermarkBottomInset)
    }
}

// MARK: - Strip chrome

/// Full-bleed intent strip: lattice under glass, green hairline on top.
struct LatticesOverlayStripBackground: View {
    var body: some View {
        ZStack(alignment: .top) {
            LatticesLatticeGrid(spacing: 20, opacity: 0.06)
            Rectangle()
                .fill(.ultraThinMaterial)
            LinearGradient(
                colors: [Palette.running.opacity(0.65), HUDChrome.cyan.opacity(0.35), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)
            Rectangle()
                .fill(Palette.borderLit)
                .frame(height: 1)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .allowsHitTesting(false)
    }
}

/// Compact strip header: L-mark + wordmark.
struct LatticesOverlayStripHeader: View {
    var mode: String
    var detail: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            LatticesMark(size: 14, tint: Palette.running, dimOpacity: 0.30)
            HStack(spacing: 5) {
                Text("lattices")
                    .font(Typo.monoBold(10))
                    .foregroundColor(Palette.text.opacity(0.92))
                    .tracking(0.35)
                Text("·")
                    .font(Typo.mono(9))
                    .foregroundColor(Palette.textMuted)
                Text(mode)
                    .font(Typo.monoBold(9))
                    .foregroundColor(Palette.running)
                    .tracking(0.5)
            }
            if let detail {
                Text(detail)
                    .font(Typo.mono(8.5))
                    .foregroundColor(Palette.textMuted)
            }
            Spacer(minLength: 0)
        }
    }
}