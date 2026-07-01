import AppKit
import SwiftUI

// MARK: - Front window placement (menu bar quick action)

enum FrontWindowPlacer {
    static func targetLabel() -> String? {
        if let win = DesktopModel.shared.frontmostWindow() {
            let title = win.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? win.app : "\(win.app) — \(title)"
        }
        if let app = NSWorkspace.shared.frontmostApplication?.localizedName,
           !LatticesRuntime.isLatticesBundleIdentifier(NSWorkspace.shared.frontmostApplication?.bundleIdentifier) {
            return app
        }
        return nil
    }

    static func canPlace() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        return !LatticesRuntime.isLatticesBundleIdentifier(app.bundleIdentifier)
    }

    static func place(_ position: TilePosition, source: String = "menuBar") {
        guard canPlace() else {
            NSSound.beep()
            return
        }
        AppFeedback.shared.commitTactile()
        WindowTiler.tileFrontmostViaAX(to: position)
        DiagnosticLog.shared.success("Placed front window → \(position.label) (\(source))")
    }
}

/// Compact 3×3 grid — tap a cell to snap the frontmost window there.
struct FrontWindowPlacementGrid: View {
    var onPlaced: (() -> Void)? = nil
    @State private var refreshToken = UUID()

    private let cells: [[TilePosition?]] = [
        [.topLeft, .top, .topRight],
        [.left, .maximize, .right],
        [.bottomLeft, .bottom, .bottomRight],
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "macwindow")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Palette.running)
                Text("Move front window")
                    .font(Typo.monoBold(10))
                    .foregroundColor(Palette.textMuted)
                Spacer()
            }

            if let label = FrontWindowPlacer.targetLabel() {
                Text(label)
                    .font(Typo.mono(9))
                    .foregroundColor(Palette.textDim)
                    .lineLimit(1)
            } else {
                Text("Focus another app, then pick a slot")
                    .font(Typo.mono(9))
                    .foregroundColor(Palette.textMuted)
            }

            VStack(spacing: 4) {
                ForEach(0..<cells.count, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(0..<cells[row].count, id: \.self) { col in
                            if let position = cells[row][col] {
                                placementCell(position)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 4) {
                placementPill(.center, label: "Center")
                placementPill(.leftThird, label: "⅓ L")
                placementPill(.centerThird, label: "⅓ C")
                placementPill(.rightThird, label: "⅓ R")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .id(refreshToken)
        .onAppear { refreshToken = UUID() }
        .onReceive(NotificationCenter.default.publisher(for: .latticesPopoverWillShow)) { _ in
            refreshToken = UUID()
        }
    }

    private func placementCell(_ position: TilePosition) -> some View {
        Button {
            FrontWindowPlacer.place(position)
            onPlaced?()
        } label: {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Palette.surface.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 0.5)
                )
                .overlay {
                    cellGlyph(position)
                }
                .frame(height: 28)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .help(position.label)
        .disabled(!FrontWindowPlacer.canPlace())
        .opacity(FrontWindowPlacer.canPlace() ? 1 : 0.45)
    }

    @ViewBuilder
    private func cellGlyph(_ position: TilePosition) -> some View {
        switch position {
        case .maximize:
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(Palette.running.opacity(0.7), lineWidth: 1.2)
                .padding(6)
        case .center:
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(Palette.textMuted, lineWidth: 1)
                .padding(9)
        default:
            GeometryReader { geo in
                let inset: CGFloat = 5
                let w = geo.size.width - inset * 2
                let h = geo.size.height - inset * 2
                RoundedRectangle(cornerRadius: 2)
                    .fill(Palette.running.opacity(0.35))
                    .frame(width: regionSize(w, h, position).width,
                           height: regionSize(w, h, position).height)
                    .position(regionCenter(w, h, position, inset: inset))
            }
        }
    }

    private func regionSize(_ w: CGFloat, _ h: CGFloat, _ position: TilePosition) -> CGSize {
        switch position {
        case .left, .right: return CGSize(width: w * 0.46, height: h)
        case .top, .bottom: return CGSize(width: w, height: h * 0.46)
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            return CGSize(width: w * 0.46, height: h * 0.46)
        default: return CGSize(width: w * 0.5, height: h * 0.5)
        }
    }

    private func regionCenter(_ w: CGFloat, _ h: CGFloat, _ position: TilePosition, inset: CGFloat) -> CGPoint {
        let cx = inset + w / 2
        let cy = inset + h / 2
        switch position {
        case .topLeft:     return CGPoint(x: inset + w * 0.27, y: inset + h * 0.27)
        case .top:         return CGPoint(x: cx, y: inset + h * 0.27)
        case .topRight:    return CGPoint(x: inset + w * 0.73, y: inset + h * 0.27)
        case .left:        return CGPoint(x: inset + w * 0.27, y: cy)
        case .right:       return CGPoint(x: inset + w * 0.73, y: cy)
        case .bottomLeft:  return CGPoint(x: inset + w * 0.27, y: inset + h * 0.73)
        case .bottom:      return CGPoint(x: cx, y: inset + h * 0.73)
        case .bottomRight: return CGPoint(x: inset + w * 0.73, y: inset + h * 0.73)
        default:           return CGPoint(x: cx, y: cy)
        }
    }

    private func placementPill(_ position: TilePosition, label: String) -> some View {
        Button {
            FrontWindowPlacer.place(position)
            onPlaced?()
        } label: {
            Text(label)
                .font(Typo.monoBold(8))
                .foregroundColor(Palette.textDim)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Palette.surface.opacity(0.7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(Palette.border, lineWidth: 0.5)
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(!FrontWindowPlacer.canPlace())
        .opacity(FrontWindowPlacer.canPlace() ? 1 : 0.45)
    }
}

enum FrontWindowPlacementMenu {
    static func attach(to menu: NSMenu) {
        let root = NSMenuItem(title: "Move Front Window", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let groups: [(String, [TilePosition])] = [
            ("Halves", [.left, .right, .top, .bottom]),
            ("Quarters", [.topLeft, .topRight, .bottomLeft, .bottomRight]),
            ("Other", [.maximize, .center, .leftThird, .centerThird, .rightThird]),
        ]
        for (index, group) in groups.enumerated() {
            if index > 0 { submenu.addItem(.separator()) }
            for position in group.1 {
                let item = NSMenuItem(title: position.label, action: #selector(MenuBarController.menuPlaceFrontWindow(_:)), keyEquivalent: "")
                item.target = MenuBarController.shared
                item.representedObject = position.rawValue
                submenu.addItem(item)
            }
        }

        root.submenu = submenu
        menu.addItem(root)
    }
}

extension MenuBarController {
    @objc func menuPlaceFrontWindow(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let position = TilePosition(rawValue: raw) else { return }
        FrontWindowPlacer.place(position, source: "menuBarContext")
    }
}