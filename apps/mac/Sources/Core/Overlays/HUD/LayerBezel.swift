import AppKit
import SwiftUI

// MARK: - Layer Switch HUD

/// Brief interaction acknowledgement shared by layer and tab-group actions.
/// It uses the same restrained glass-and-signal language as Hyperspace instead
/// of introducing a separate editorial/serif treatment.
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
        let pillHeight: CGFloat = 52

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
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]

        var maxTextWidth: CGFloat = 0
        for label in allLabels {
            let size = (label as NSString).size(withAttributes: attrs)
            maxTextWidth = max(maxTextWidth, ceil(size.width))
        }

        // dots width: 7px per dot + 5px spacing
        let dotsWidth = CGFloat(total) * 6 + CGFloat(max(0, total - 1)) * 4
        // divider + spacing
        let dividerWidth: CGFloat = 1 + 10 * 2
        // horizontal padding
        let hPadding: CGFloat = 18 * 2

        let contentWidth = dotsWidth + dividerWidth + maxTextWidth + hPadding

        // Keep acknowledgements compact while avoiding width changes between
        // adjacent layers in the same workspace.
        let rawWidth = max(240, contentWidth)
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

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: label.localizedCaseInsensitiveContains("tab") ? "rectangle.stack.fill" : "square.stack.3d.up.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(HUDChrome.cyan)

            // Layer index dots
            HStack(spacing: 4) {
                ForEach(0..<total, id: \.self) { i in
                    Circle()
                        .fill(i == index ? HUDChrome.cyan : Color.white.opacity(0.20))
                        .frame(width: 6, height: 6)
                }
            }

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 1, height: 16)

            // Layer name
            Text(label)
                .font(Typo.heading(13))
                .foregroundStyle(Palette.text)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text("LATTICES")
                .font(Typo.monoBold(7))
                .tracking(1.0)
                .foregroundStyle(Palette.textDim)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [HUDChrome.baseTop, HUDChrome.baseBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(HUDChrome.cyan.opacity(0.32), lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.42), radius: 14, y: 7)
        .shadow(color: HUDChrome.cyan.opacity(0.10), radius: 10)
    }
}
