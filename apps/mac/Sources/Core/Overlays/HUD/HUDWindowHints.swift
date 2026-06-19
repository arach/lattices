import AppKit
import SwiftUI

// MARK: - Hint assignment (pure / testable)

/// Assigns a single keyboard-jump letter to each window in the HUD window list.
///
/// The HUD captures all keys while it's up, so window jumps are gated behind a
/// modifier (⌥). Letters are dealt in home-row-first order so the most recently
/// used windows (which sort to the top of the list) get the fastest keys.
/// `v` and `x` are omitted because the HUD already binds ⌥V (voice) and ⌥X
/// (experience).
enum HUDWindowHintAssigner {
    /// Home row → top row → bottom row, minus the reserved `v` / `x`.
    static let alphabet: [String] = "asdfghjklqwertyuiopzcbnm".map(String.init)

    /// `orderedWids` should be the window list in display order (front-to-back).
    static func assign(orderedWids: [UInt32]) -> [UInt32: String] {
        var map: [UInt32: String] = [:]
        for (index, wid) in orderedWids.enumerated() where index < alphabet.count {
            map[wid] = alphabet[index]
        }
        return map
    }
}

// MARK: - Badge view

/// A small HUD tile worn at a window's top-right corner: dark `baseTop/baseBottom`
/// gradient, a cyan signal rim + glow, and the jump letter in mono — the same
/// language as the rest of the HUD chrome.
struct HUDWindowHintBadge: View {
    let letter: String

    /// Transparent margin so the cyan glow / drop shadow aren't clipped by the
    /// tight panel bounds. Folded into the corner inset when positioning.
    static let glowMargin: CGFloat = 7

    var body: some View {
        HStack(spacing: 3) {
            Text("⌥")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(HUDChrome.cyan.opacity(0.62))
            Text(letter.uppercased())
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(HUDChrome.cyan)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [HUDChrome.baseTop, HUDChrome.baseBottom],
                        startPoint: .top, endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(HUDChrome.cyan.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: HUDChrome.cyan.opacity(0.30), radius: 6, y: 1)
        .shadow(color: Color.black.opacity(0.45), radius: 5, y: 2)
        .padding(Self.glowMargin)
        .fixedSize()
    }
}

// MARK: - Overlay manager

/// Manages one borderless, click-through panel per on-screen, unoccluded hinted
/// window, positioned at that window's top-right corner. Owned by `HUDController`.
final class HUDWindowHintBezels {
    private struct Bezel {
        let panel: NSPanel
        let hosting: NSHostingView<HUDWindowHintBadge>
    }

    /// Gap between the window's top-right corner and the badge tile (the badge's
    /// own `glowMargin` sits inside this, so the visible inset is a touch more).
    private static let cornerGap: CGFloat = 3

    private var bezels: [UInt32: Bezel] = [:]
    private var hiddenWids: Set<UInt32> = []
    private(set) var revealed = false

    /// Recompute badge positions + visibility for the current window set.
    /// - Parameters:
    ///   - hints: wid → letter mapping (from `HUDWindowHintAssigner`).
    ///   - windows: current desktop window table (`DesktopModel.shared.windows`).
    ///   - obscured: chrome panel frames (e.g. the sidebar) — badges landing
    ///     inside any of these are suppressed.
    func update(hints: [UInt32: String], windows: [UInt32: WindowEntry], obscuredBy obscured: [NSRect]) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 900
        let screenFrames = NSScreen.screens.map(\.frame)
        let allWindows = Array(windows.values)

        // Retire bezels for windows that dropped out of the hint set.
        for wid in Array(bezels.keys) where hints[wid] == nil { drop(wid) }

        var nextHidden: Set<UInt32> = []

        for (wid, letter) in hints {
            guard let window = windows[wid], window.isOnScreen else { drop(wid); continue }
            let frame = Self.appKitRect(for: window.frame, primaryHeight: primaryHeight)
            guard screenFrames.contains(where: { $0.intersects(frame) }) else { drop(wid); continue }

            let bezel = bezels[wid] ?? makeBezel()
            bezel.hosting.rootView = HUDWindowHintBadge(letter: letter)
            let size = bezel.hosting.fittingSize
            bezel.panel.setContentSize(size)

            // Top-right corner of the window.
            let originX = frame.maxX - Self.cornerGap - size.width
            let originY = frame.maxY - Self.cornerGap - size.height
            bezel.panel.setFrameOrigin(NSPoint(x: originX, y: originY))
            bezels[wid] = bezel

            // Badge centre (where the tile visually sits) for hit tests.
            let centerAppKit = NSPoint(x: originX + size.width / 2, y: originY + size.height / 2)
            let centerCG = CGPoint(x: centerAppKit.x, y: primaryHeight - centerAppKit.y)

            // Occluded: a window in front (smaller zIndex) covers the badge spot.
            let occluded = allWindows.contains { other in
                other.wid != wid && other.isOnScreen && other.zIndex < window.zIndex &&
                Self.cgRect(other.frame).contains(centerCG)
            }
            let underChrome = obscured.contains { $0.contains(centerAppKit) }
            if occluded || underChrome { nextHidden.insert(wid) }
        }

        hiddenWids = nextHidden
        applyVisibility()
    }

    func setRevealed(_ on: Bool) {
        revealed = on
        applyVisibility()
    }

    /// Tear down every panel (called when the HUD is fully dismissed).
    func clear() {
        revealed = false
        for bezel in bezels.values { bezel.panel.orderOut(nil) }
        bezels.removeAll()
        hiddenWids.removeAll()
    }

    // MARK: - Internals

    private func applyVisibility() {
        for (wid, bezel) in bezels {
            let shouldShow = revealed && !hiddenWids.contains(wid)
            bezel.panel.alphaValue = shouldShow ? 1 : 0
            if shouldShow { bezel.panel.orderFrontRegardless() }
        }
    }

    private func drop(_ wid: UInt32) {
        bezels[wid]?.panel.orderOut(nil)
        bezels[wid] = nil
    }

    private func makeBezel() -> Bezel {
        let hosting = NSHostingView(rootView: HUDWindowHintBadge(letter: ""))
        hosting.sizingOptions = []
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 48, height: 32),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true   // click through to the window beneath
        panel.alphaValue = 0
        panel.sharingType = .readOnly
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = hosting
        return Bezel(panel: panel, hosting: hosting)
    }

    private static func cgRect(_ frame: WindowFrame) -> CGRect {
        CGRect(x: frame.x, y: frame.y, width: frame.w, height: frame.h)
    }

    /// Convert a CoreGraphics window frame (top-left origin, y-down, global) into
    /// an AppKit panel frame (bottom-left origin, y-up, global).
    private static func appKitRect(for frame: WindowFrame, primaryHeight: CGFloat) -> NSRect {
        NSRect(
            x: frame.x,
            y: primaryHeight - frame.y - frame.h,
            width: frame.w,
            height: frame.h
        )
    }
}
