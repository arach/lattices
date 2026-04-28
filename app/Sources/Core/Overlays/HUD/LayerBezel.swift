import AppKit
import SwiftUI

// MARK: - Layer Switch HUD

/// A notch-style pill that briefly shows the active layer name when switching.
final class LayerBezel {
    static let shared = LayerBezel()

    private var panel: NSPanel?
    private var dismissTimer: Timer?
    /// Cached pill width per layer count — stable once computed for a workspace
    private var cachedWidth: CGFloat?
    private var cachedLayerSignature: String?

    /// Show the layer bezel for a given layer label and index.
    func show(label: String, index: Int, total: Int, allLabels: [String]) {
        dismissTimer?.invalidate()

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let screenFrame = screen.frame

        let pillWidth = stableWidth(for: allLabels, total: total)
        let pillHeight: CGFloat = 64

        // Position: centered on screen, upper third
        let x = screenFrame.origin.x + (screenFrame.width - pillWidth) / 2
        let y = screenFrame.origin.y + screenFrame.height * 0.65

        let pillFrame = NSRect(x: x, y: y, width: pillWidth, height: pillHeight)

        let view = LayerBezelView(label: label, index: index, total: total)
        let hostingView = NSHostingView(rootView: view)

        if panel == nil {
            let p = NSPanel(
                contentRect: pillFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.isOpaque = false
            p.backgroundColor = .clear
            p.level = .statusBar
            p.hasShadow = false
            p.hidesOnDeactivate = false
            p.isReleasedWhenClosed = false
            p.isMovable = false
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            p.ignoresMouseEvents = true
            panel = p
        }

        guard let p = panel else { return }

        p.contentView = hostingView
        p.setFrame(pillFrame, display: false)
        p.alphaValue = 0
        p.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            p.animator().alphaValue = 1.0
        }

        dismissTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    func dismiss() {
        guard let p = panel, p.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            p.animator().alphaValue = 0
        }, completionHandler: {
            p.orderOut(nil)
        })
    }

    /// Invalidate cached width (call when workspace config changes)
    func invalidateCache() {
        cachedWidth = nil
        cachedLayerSignature = nil
    }

    // MARK: - Width Heuristics

    /// Compute a stable pill width based on the longest layer label.
    /// Cached so the pill never resizes between switches within the same workspace.
    private func stableWidth(for allLabels: [String], total: Int) -> CGFloat {
        let signature = allLabels.joined(separator: "|") + ":\(total)"
        if let cached = cachedWidth, cachedLayerSignature == signature {
            return cached
        }

        // Measure the widest label using the actual font
        let font = NSFont(name: "NewYork-RegularItalic", size: 24)
            ?? NSFont.systemFont(ofSize: 24, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]

        var maxTextWidth: CGFloat = 0
        for label in allLabels {
            let size = (label as NSString).size(withAttributes: attrs)
            maxTextWidth = max(maxTextWidth, ceil(size.width))
        }

        // dots width: 7px per dot + 5px spacing
        let dotsWidth = CGFloat(total) * 7 + CGFloat(max(0, total - 1)) * 5
        // divider + spacing
        let dividerWidth: CGFloat = 1 + 14 * 2
        // horizontal padding
        let hPadding: CGFloat = 36 * 2

        let contentWidth = dotsWidth + dividerWidth + maxTextWidth + hPadding

        // Minimum 360, round up to nearest 20 for visual stability
        let rawWidth = max(360, contentWidth)
        let width = ceil(rawWidth / 20) * 20

        cachedWidth = width
        cachedLayerSignature = signature
        return width
    }
}

// MARK: - Bezel View

struct LayerBezelView: View {
    let label: String
    let index: Int
    let total: Int

    private var layerFont: Font {
        // New York Italic — Apple's serif font
        if let descriptor = NSFontDescriptor(fontAttributes: [
            .family: "New York",
            .traits: [NSFontDescriptor.TraitKey.symbolic: NSFontDescriptor.SymbolicTraits.italic.rawValue]
        ]).withDesign(.serif) {
            return Font(NSFont(descriptor: descriptor, size: 24) ?? .systemFont(ofSize: 24))
        }
        return .system(size: 24, weight: .medium, design: .serif).italic()
    }

    var body: some View {
        HStack(spacing: 14) {
            // Layer index dots
            HStack(spacing: 5) {
                ForEach(0..<total, id: \.self) { i in
                    Circle()
                        .fill(i == index ? Color.white : Color.white.opacity(0.25))
                        .frame(width: 7, height: 7)
                }
            }

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 1, height: 20)

            // Layer name
            Text(label)
                .font(layerFont)
                .foregroundStyle(
                    .linearGradient(
                        colors: [.white, .white.opacity(0.85)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    .linearGradient(
                        colors: [.white.opacity(0.9), .white.opacity(0.22)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        )
        // Inner glow — top edge highlight
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    .linearGradient(
                        colors: [.white.opacity(0.08), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .allowsHitTesting(false)
        )
    }
}
