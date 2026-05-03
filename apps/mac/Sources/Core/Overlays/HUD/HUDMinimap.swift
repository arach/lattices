import SwiftUI

// MARK: - HUDMinimap (expanded canvas-attached minimap)

struct HUDMinimap: View {
    @ObservedObject var state: HUDState
    @ObservedObject private var desktop = DesktopModel.shared
    var onDismiss: () -> Void
    let screenIndex: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 0) {
                Image(systemName: screenIndex == 0 ? "display" : "rectangle.on.rectangle")
                    .font(.system(size: 10))
                    .foregroundColor(Palette.textMuted)
                Text(screenIndex == 0 ? "Main" : "Display \(screenIndex + 1)")
                    .font(Typo.monoBold(10))
                    .foregroundColor(Palette.textMuted)
                    .padding(.leading, 4)

                Spacer()

                // Dock back into sidebar
                Button {
                    state.minimapMode = .docked
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Palette.textMuted)
                        .frame(width: 20, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Palette.surface)
                        )
                }
                .buttonStyle(.plain)
                .help("Dock map (M)")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Map canvas (larger in expanded mode)
            mapCanvas
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bg)
    }

    // MARK: - Map canvas

    private var mapCanvas: some View {
        GeometryReader { geo in
            let screens = NSScreen.screens
            let idx = clampedIndex
            if idx < screens.count {
                let screen = screens[idx]
                let sw = screen.frame.width
                let sh = screen.frame.height
                let canvasW = geo.size.width
                let canvasH = geo.size.height

                let scaleX = canvasW / sw
                let scaleY = canvasH / sh
                let scale = min(scaleX, scaleY)
                let drawW = sw * scale
                let drawH = sh * scale
                let offsetX = (canvasW - drawW) / 2
                let offsetY = (canvasH - drawH) / 2

                let origin = screenCGOrigin(screen)
                let wins = windowsOnScreen(idx)

                ZStack(alignment: .topLeading) {
                    // Screen background
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Palette.surface.opacity(0.4))
                        .frame(width: drawW, height: drawH)
                        .offset(x: offsetX, y: offsetY)

                    // Windows (back-to-front)
                    ForEach(wins.reversed()) { win in
                        let rx = (CGFloat(win.frame.x) - origin.x) * scale + offsetX
                        let ry = (CGFloat(win.frame.y) - origin.y) * scale + offsetY
                        let rw = CGFloat(win.frame.w) * scale
                        let rh = CGFloat(win.frame.h) * scale
                        let isSelected = state.selectedItem == .window(win)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(appColor(win.app).opacity(isSelected ? 0.5 : 0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .strokeBorder(
                                        isSelected ? Palette.running : appColor(win.app).opacity(0.35),
                                        lineWidth: isSelected ? 1.5 : 0.5
                                    )
                            )
                            .overlay(
                                Group {
                                    if rw > 30 && rh > 18 {
                                        VStack(spacing: 1) {
                                            Text(String(win.app.prefix(1)))
                                                .font(Typo.geistMonoBold(max(7, min(11, rh * 0.3))))
                                                .foregroundColor(appColor(win.app).opacity(isSelected ? 1.0 : 0.5))
                                            if rh > 30 && rw > 50 {
                                                Text(win.title.prefix(12).description)
                                                    .font(Typo.mono(max(5, min(7, rh * 0.12))))
                                                    .foregroundColor(Palette.textDim.opacity(0.6))
                                                    .lineLimit(1)
                                            }
                                        }
                                    }
                                }
                            )
                            .frame(width: max(rw, 4), height: max(rh, 3))
                            .offset(x: rx, y: ry)
                            .onTapGesture {
                                state.selectedItem = .window(win)
                                state.focus = .list
                                if let flatIdx = state.flatItems.firstIndex(of: .window(win)) {
                                    state.selectedIndex = flatIdx
                                }
                            }
                    }
                }
                .frame(width: canvasW, height: canvasH)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - Helpers

    private var clampedIndex: Int {
        min(screenIndex, NSScreen.screens.count - 1)
    }

    private func screenCGOrigin(_ screen: NSScreen) -> (x: CGFloat, y: CGFloat) {
        let primaryH = NSScreen.screens.first?.frame.height ?? 900
        return (screen.frame.origin.x, primaryH - screen.frame.origin.y - screen.frame.height)
    }

    private func windowsOnScreen(_ screenIdx: Int) -> [WindowEntry] {
        let screens = NSScreen.screens
        guard screenIdx < screens.count else { return [] }
        let screen = screens[screenIdx]
        let origin = screenCGOrigin(screen)
        let sw = Double(screen.frame.width)
        let sh = Double(screen.frame.height)

        return desktop.allWindows().filter { win in
            let cx = win.frame.x + win.frame.w / 2
            let cy = win.frame.y + win.frame.h / 2
            return cx >= Double(origin.x) && cx < Double(origin.x) + sw &&
                   cy >= Double(origin.y) && cy < Double(origin.y) + sh &&
                   win.app != "Lattices"
        }
    }

    private func appColor(_ app: String) -> Color {
        if ["iTerm2", "Terminal", "WezTerm", "Alacritty", "kitty"].contains(app) {
            return Palette.running
        }
        if ["Google Chrome", "Safari", "Arc", "Firefox", "Brave Browser"].contains(app) {
            return Color.blue
        }
        if ["Xcode", "Visual Studio Code", "Cursor", "Zed"].contains(app) {
            return Color.purple
        }
        if app.localizedCaseInsensitiveContains("Claude") || app.localizedCaseInsensitiveContains("Codex") {
            return Color.orange
        }
        return Palette.textMuted
    }
}
