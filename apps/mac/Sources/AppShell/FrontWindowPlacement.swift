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

    static func fillOpenGridCell(columns: Int = 3, rows: Int = 2, source: String = "hotkey") {
        guard canPlace() else {
            NSSound.beep()
            return
        }

        DesktopModel.shared.forcePoll()

        guard let target = DesktopModel.shared.frontmostWindow(),
              target.app != "Lattices" else {
            NSSound.beep()
            DiagnosticLog.shared.warn("Fill open cell: no frontmost target window")
            return
        }

        let screen = WindowTiler.screenForWindowFrame(target.frame)
        guard let placement = bestOpenGridCell(columns: columns, rows: rows, target: target, screen: screen) else {
            NSSound.beep()
            DiagnosticLog.shared.warn("Fill open cell: no valid \(columns)x\(rows) placement")
            return
        }

        AppFeedback.shared.commitTactile()
        WindowTiler.tileWindowById(wid: target.wid, pid: target.pid, to: placement, on: screen)
        WindowTiler.highlightWindowById(wid: target.wid)
        DiagnosticLog.shared.success("Filled open \(columns)x\(rows) cell → \(placement.wireValue) (\(source))")
    }

    private static func bestOpenGridCell(columns: Int, rows: Int, target: WindowEntry, screen: NSScreen) -> PlacementSpec? {
        let windows = DesktopModel.shared.allWindows().filter { entry in
            entry.wid != target.wid &&
            entry.isOnScreen &&
            entry.app != "Lattices" &&
            entry.frame.w > 50 &&
            entry.frame.h > 50 &&
            WindowTiler.screenForWindowFrame(entry.frame) === screen
        }
        let targetRect = rect(for: target.frame)
        let targetCenter = CGPoint(x: targetRect.midX, y: targetRect.midY)

        var best: (placement: PlacementSpec, occupied: CGFloat, distance: CGFloat, order: Int)?
        for row in 0..<rows {
            for column in 0..<columns {
                guard let grid = GridPlacement(columns: columns, rows: rows, column: column, row: row) else { continue }
                let placement = PlacementSpec.grid(grid)
                let cellFrame = WindowTiler.tileFrame(for: placement, on: screen)
                let occupied = windows.reduce(CGFloat.zero) { total, entry in
                    total + overlapRatio(rect(for: entry.frame), cellFrame)
                }
                let distance = hypot(targetCenter.x - cellFrame.midX, targetCenter.y - cellFrame.midY)
                let candidate = (placement: placement, occupied: occupied, distance: distance, order: row * columns + column)
                if let current = best {
                    if candidate.occupied < current.occupied - 0.01 ||
                        (abs(candidate.occupied - current.occupied) <= 0.01 && candidate.distance < current.distance - 1) ||
                        (abs(candidate.occupied - current.occupied) <= 0.01 && abs(candidate.distance - current.distance) <= 1 && candidate.order < current.order) {
                        best = candidate
                    }
                } else {
                    best = candidate
                }
            }
        }
        return best?.placement
    }

    private static func rect(for frame: WindowFrame) -> CGRect {
        CGRect(x: frame.x, y: frame.y, width: frame.w, height: frame.h)
    }

    private static func overlapRatio(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, rhs.width > 0, rhs.height > 0 else { return 0 }
        return max(0, intersection.width * intersection.height) / (rhs.width * rhs.height)
    }
}

/// Quick Action: one-line **Move** row that expands to a placement grid.
///
/// Collapsed by default so the menu-bar popover stays compact. Tap the row to
/// unfold slots for the frontmost window; pick a cell to snap and (optionally)
/// dismiss the host surface.
struct FrontWindowPlacementGrid: View {
    var onPlaced: (() -> Void)? = nil
    /// Host can listen for expand/collapse to resize a fixed-size popover.
    var onExpandedChange: ((Bool) -> Void)? = nil

    @State private var expanded = false
    @State private var targetLabel: String?
    @State private var isHovered = false

    private let cells: [[TilePosition?]] = [
        [.topLeft, .top, .topRight],
        [.left, .maximize, .right],
        [.bottomLeft, .bottom, .bottomRight],
    ]

    private var targetSubtitle: String {
        if let targetLabel, !targetLabel.isEmpty {
            return targetLabel
        }
        return "Focus another app, then pick a slot"
    }

    var body: some View {
        VStack(spacing: 0) {
            headerRow

            if expanded {
                placementPanel
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onAppear { refreshTarget() }
        .onReceive(NotificationCenter.default.publisher(for: .latticesPopoverWillShow)) { _ in
            // Each open starts collapsed so the popover stays a short action list.
            if expanded {
                withAnimation(.easeOut(duration: 0.12)) {
                    expanded = false
                }
            }
            refreshTarget()
        }
        .onChange(of: expanded) { _, isOpen in
            onExpandedChange?(isOpen)
        }
    }

    private var headerRow: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                expanded.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Palette.running.opacity(isHovered || expanded ? 0.18 : 0.12))
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isHovered || expanded ? Palette.text : Palette.running)
                }
                .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Move")
                        .font(Typo.body(12))
                        .foregroundColor(isHovered || expanded ? Palette.text : Palette.textDim)
                        .lineLimit(1)

                    Text(targetSubtitle)
                        .font(Typo.mono(9))
                        .foregroundColor(Palette.textMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Palette.textMuted)
                    .frame(width: 16, height: 16)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovered || expanded ? Palette.surfaceHov : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(expanded ? "Hide placement grid" : "Position the frontmost window")
    }

    private var placementPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
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
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.surface.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 0.5)
                )
        )
    }

    private func refreshTarget() {
        targetLabel = FrontWindowPlacer.targetLabel()
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
