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

// MARK: - Live tab chrome

/// Compact app-level tool palette hovering over a live group. It deliberately
/// avoids the silhouette of native window chrome: the underlying app keeps its
/// complete title bar and geometry, while Lattices presents grouping actions.
struct HUDLiveTabChrome: View {
    let group: LiveTabGroup
    private let store = LiveTabGroupStore.shared
    @State private var draggingMemberID: UInt32?
    @State private var dragTranslation: CGSize = .zero

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.50))
                Text(group.name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .frame(minWidth: 92, maxWidth: 130, minHeight: 29, alignment: .leading)

            Rectangle()
                .fill(Color.white.opacity(0.09))
                .frame(width: 1, height: 17)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: 4) {
                    ForEach(Array(group.members.enumerated()), id: \.element.id) { index, member in
                        tab(member, index: index)
                    }
                }
                .padding(.leading, 7)
                .padding(.trailing, 5)
            }

            Rectangle()
                .fill(Color.white.opacity(0.09))
                .frame(width: 1, height: 17)

            HStack(spacing: 2) {
                modeButton
                Button {
                    store.delete(id: group.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.34))
                        .frame(width: 27, height: 27)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Ungroup \(group.name)")
                .accessibilityLabel("Ungroup \(group.name)")
            }
            .padding(.horizontal, 5)
        }
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(railGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.38), radius: 9, y: 4)
    }

    private var railGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.13, green: 0.15, blue: 0.17),
                Color(red: 0.10, green: 0.12, blue: 0.14),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func tab(_ member: LiveTabMember, index: Int) -> some View {
        let selected = index == group.selectedIndex
        let isDragging = draggingMemberID == member.id
        let helpText = "Show \(member.app): \(member.label)"
        let accessibilityText = "\(member.app) tab, \(member.label)" + (selected ? ", selected" : "")
        let dragX = isDragging ? max(-12, min(12, dragTranslation.width * 0.12)) : 0
        let dragY = isDragging ? max(-3, min(3, dragTranslation.height * 0.08)) : 0
        let tabFace = AnyView(HStack(spacing: 7) {
            Image(systemName: icon(for: member.app))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(selected ? HUDChrome.cyan : Color.white.opacity(0.30))
            Text(displayName(for: member.app))
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(selected ? Color.white.opacity(0.94) : Color.white.opacity(0.48))
        .padding(.horizontal, 11)
        .frame(minWidth: 92, maxWidth: 124, minHeight: 28, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected ? Color.white.opacity(0.11) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(selected ? HUDChrome.cyan.opacity(0.28) : Color.clear, lineWidth: 0.7)
                )
        )
        )
        return tabFace
        .contentShape(Rectangle())
        .offset(x: dragX, y: dragY)
        .scaleEffect(isDragging ? 1.025 : 1)
        .shadow(color: isDragging ? Color.black.opacity(0.35) : .clear, radius: 4, y: 2)
        .zIndex(isDragging ? 10 : 0)
        .onTapGesture {
            store.select(groupID: group.id, index: index)
        }
        .gesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .global)
                .onChanged { value in
                    draggingMemberID = member.id
                    dragTranslation = value.translation
                }
                .onEnded { value in
                    let shouldDetach = abs(value.translation.height) >= 22
                        || abs(value.translation.width) >= 72
                    draggingMemberID = nil
                    dragTranslation = .zero
                    if shouldDetach {
                        store.detach(
                            groupID: group.id,
                            windowID: member.id,
                            at: NSEvent.mouseLocation
                        )
                    }
                }
        )
        .help(helpText)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { store.select(groupID: group.id, index: index) }
    }

    private var modeButton: some View {
        Button {
            store.toggleLayout(id: group.id)
        } label: {
            Image(systemName: group.isExpanded ? "rectangle.stack.fill" : "square.grid.2x2")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(group.isExpanded ? Color.black.opacity(0.78) : Color.white.opacity(0.42))
                .frame(width: 29, height: 27)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(group.isExpanded ? Color.white.opacity(0.86) : Color.white.opacity(0.035))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Color.white.opacity(group.isExpanded ? 0.18 : 0.07), lineWidth: 0.6)
                        )
                )
        }
        .buttonStyle(.plain)
        .help(group.isExpanded ? "Stack these windows as tabs" : "Show these tabs in a grid")
        .accessibilityLabel(group.isExpanded ? "Stack tabs" : "Show tab grid")
    }

    private func icon(for app: String) -> String {
        let value = app.lowercased()
        if value.contains("terminal") || value.contains("iterm") || value.contains("warp") { return "terminal.fill" }
        if value.contains("chrome") || value.contains("safari") || value.contains("firefox") || value.contains("arc") { return "globe" }
        if value.contains("xcode") || value.contains("code") || value.contains("cursor") || value.contains("zed") {
            return "chevron.left.forwardslash.chevron.right"
        }
        return "macwindow"
    }

    private func displayName(for app: String) -> String {
        let value = app.lowercased()
        if value.contains("chrome") { return "Chrome" }
        if value.contains("iterm") { return "iTerm" }
        if value == "terminal" || value.contains("terminal.app") { return "Terminal" }
        if value.contains("visual studio code") { return "Code" }
        return app
    }
}

/// A click-through guide showing which native window belongs to the Lattices
/// rail. It deliberately avoids a filled chassis or complete window outline:
/// Lattices owns the grouping relationship, while each app remains visibly native.
private struct HUDLiveTabGroupGuide: View {
    var body: some View {
        ZStack {
            corner
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            corner
                .rotationEffect(.degrees(90))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            corner
                .rotationEffect(.degrees(-90))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            corner
                .rotationEffect(.degrees(180))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .padding(4)
    }

    private var corner: some View {
        ZStack(alignment: .topLeading) {
            Color.white.opacity(0.18).frame(width: 18, height: 1)
            Color.white.opacity(0.18).frame(width: 1, height: 18)
        }
        .frame(width: 18, height: 18)
    }
}

/// Owns one interactive floating tool palette per live group. The palette sits
/// over the native window without changing its frame; a separate click-through
/// corner guide communicates membership without imitating window chrome.
final class HUDLiveTabChromes {
    private struct Chrome {
        let panel: NSPanel
        let hosting: NSHostingView<HUDLiveTabChrome>
        let framePanel: NSPanel
    }

    private var chromes: [String: Chrome] = [:]
    private var visibleGroupIDs: Set<String> = []
    private var framedGroupIDs: Set<String> = []
    private var anchorWindowIDs: [String: UInt32] = [:]
    private(set) var revealed = false

    func update(groups: [LiveTabGroup], windows: [UInt32: WindowEntry], obscuredBy obscured: [NSRect]) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 900
        let groupIDs = Set(groups.map(\.id))
        for id in Array(chromes.keys) where !groupIDs.contains(id) { drop(id) }

        var nextVisible: Set<String> = []
        var nextFramed: Set<String> = []
        for group in groups {
            guard !group.members.isEmpty else { continue }
            let selected = min(group.selectedIndex, group.members.count - 1)
            let orderedMembers = [group.members[selected]] + group.members.enumerated()
                .filter { $0.offset != selected }
                .map(\.element)
            guard let anchor = orderedMembers.compactMap({ windows[$0.id] }).first(where: \.isOnScreen) else { continue }

            let anchorFrame = Self.appKitRect(for: anchor.frame, primaryHeight: primaryHeight)
            let compositeFrame: NSRect
            let windowFrame: NSRect
            if group.isExpanded {
                compositeFrame = anchorFrame
                windowFrame = anchorFrame
            } else {
                // Anchor the guide to the group's intended tile rather than a
                // transient native-window measurement. The palette does not
                // reserve layout space inside that tile.
                let base = WindowTiler.tileFrame(for: group.placement, on: group.screen)
                compositeFrame = NSRect(
                    x: base.minX,
                    y: primaryHeight - base.maxY,
                    width: base.width,
                    height: base.height
                )
                windowFrame = NSRect(
                    x: compositeFrame.minX,
                    y: compositeFrame.minY,
                    width: compositeFrame.width,
                    height: compositeFrame.height
                )
            }
            var minX = windowFrame.minX
            var maxX = windowFrame.maxX
            var top = windowFrame.maxY - 6

            for frame in obscured where frame.intersects(windowFrame) {
                if frame.maxX > minX, frame.midX <= windowFrame.midX { minX = max(minX, frame.maxX + 7) }
                if frame.minX < maxX, frame.midX > windowFrame.midX { maxX = min(maxX, frame.minX - 7) }
                let crossesWindowCenter = frame.minX <= windowFrame.midX && frame.maxX >= windowFrame.midX
                if crossesWindowCenter, frame.minY < top, frame.maxY >= top { top = frame.minY - 4 }
            }

            let availableWidth = maxX - minX - 20
            guard availableWidth >= 300 else { continue }
            let preferredWidth = CGFloat(168 + group.members.count * 98)
            let width = min(availableWidth, min(620, max(340, preferredWidth)))
            let centeredX = windowFrame.midX - width / 2
            let x = min(max(centeredX, minX + 10), maxX - width - 10)
            let chrome = chromes[group.id] ?? makeChrome(group: group)
            anchorWindowIDs[group.id] = anchor.wid
            chrome.hosting.rootView = HUDLiveTabChrome(group: group)
            chrome.panel.setFrame(NSRect(x: x, y: top - 38, width: width, height: 38), display: true)
            if group.isExpanded {
                chrome.framePanel.alphaValue = 0
                chrome.framePanel.orderOut(nil)
            } else {
                chrome.framePanel.setFrame(
                    compositeFrame,
                    display: true
                )
                nextFramed.insert(group.id)
            }
            chromes[group.id] = chrome
            nextVisible.insert(group.id)
        }

        visibleGroupIDs = nextVisible
        framedGroupIDs = nextFramed
        applyVisibility()
    }

    func setRevealed(_ on: Bool) {
        revealed = on
        applyVisibility()
    }

    func contains(_ point: NSPoint) -> Bool {
        chromes.values.contains { $0.panel.alphaValue > 0.5 && $0.panel.frame.contains(point) }
    }

    func clear() {
        revealed = false
        for chrome in chromes.values {
            chrome.panel.orderOut(nil)
            chrome.framePanel.orderOut(nil)
        }
        chromes.removeAll()
        visibleGroupIDs.removeAll()
        framedGroupIDs.removeAll()
        anchorWindowIDs.removeAll()
    }

    private func applyVisibility() {
        for (id, chrome) in chromes {
            let shouldShow = revealed && visibleGroupIDs.contains(id)
            chrome.panel.alphaValue = shouldShow ? 1 : 0
            chrome.panel.ignoresMouseEvents = !shouldShow
            if shouldShow {
                // Keep the guide directly above its native app, with the
                // interactive rail directly above the guide. Other normal app
                // windows can still cover the entire group naturally.
                let relativeWindow = anchorWindowIDs[id].map(Int.init) ?? 0
                if framedGroupIDs.contains(id) {
                    chrome.framePanel.alphaValue = 1
                    chrome.framePanel.order(.above, relativeTo: relativeWindow)
                } else {
                    chrome.framePanel.alphaValue = 0
                    chrome.framePanel.orderOut(nil)
                }
                let railRelative = framedGroupIDs.contains(id)
                    ? chrome.framePanel.windowNumber
                    : relativeWindow
                chrome.panel.order(.above, relativeTo: railRelative)
            } else {
                chrome.framePanel.alphaValue = 0
                chrome.framePanel.orderOut(nil)
            }
        }
    }

    private func drop(_ id: String) {
        chromes[id]?.panel.orderOut(nil)
        chromes[id]?.framePanel.orderOut(nil)
        chromes[id] = nil
        framedGroupIDs.remove(id)
        anchorWindowIDs.removeValue(forKey: id)
    }

    private func makeChrome(group: LiveTabGroup) -> Chrome {
        let hosting = NSHostingView(rootView: HUDLiveTabChrome(group: group))
        hosting.sizingOptions = []
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 38),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .normal
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.alphaValue = 0
        panel.sharingType = .readOnly
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = hosting

        let frameHosting = NSHostingView(rootView: HUDLiveTabGroupGuide())
        frameHosting.sizingOptions = []
        let framePanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        framePanel.isOpaque = false
        framePanel.backgroundColor = .clear
        framePanel.level = .normal
        framePanel.hasShadow = false
        framePanel.hidesOnDeactivate = false
        framePanel.isReleasedWhenClosed = false
        framePanel.ignoresMouseEvents = true
        framePanel.alphaValue = 0
        framePanel.sharingType = .readOnly
        framePanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        framePanel.contentView = frameHosting

        return Chrome(panel: panel, hosting: hosting, framePanel: framePanel)
    }

    private static func appKitRect(for frame: WindowFrame, primaryHeight: CGFloat) -> NSRect {
        NSRect(x: frame.x, y: primaryHeight - frame.y - frame.h, width: frame.w, height: frame.h)
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
