import AppKit
import SwiftUI

// MARK: - Stage

/// Where the selected window says it is, for the capsule that rides it.
struct OverviewCapsuleAnchor {
    let bounds: Anchor<CGRect>
    /// A tray row rather than a window on a map.
    let inTray: Bool
}

struct OverviewCapsuleAnchorKey: PreferenceKey {
    static var defaultValue: [OverviewCapsuleAnchor] = []
    static func reduce(value: inout [OverviewCapsuleAnchor], nextValue: () -> [OverviewCapsuleAnchor]) {
        value.append(contentsOf: nextValue())
    }
}

/// Active displays fit the room; inactive ones wait in restorable chips.
/// The lead map keeps its Desktops; secondary maps stay compact. A map
/// shows its focused Desktop, or the one it's showing. Tapping a Desktop
/// focuses the list on it; tapping it again gives the whole list back.
/// Clicking a window selects it; nothing here moves one.
struct OverviewStage: View {
    @ObservedObject var model: OverviewModel

    static let headHeight: CGFloat = 26
    static let spacing: CGFloat = 8
    static let captionHeight: CGFloat = 12
    static let thumbGap: CGFloat = 6
    static let hintHeight: CGFloat = 34

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let visible = model.expandedMonitors
                let plan = OverviewMonitorLayout.plan(visible, in: geo.size, preferred: model.deskPreferences.pinned)
                ZStack(alignment: .topLeading) {
                    ForEach(visible) { monitor in
                        if let placement = plan.placements.first(where: { $0.id == monitor.id }) {
                            OverviewDisplayBlock(model: model, monitor: monitor,
                                mapSize: placement.map, thumbSize: placement.thumb,
                                quiet: model.workingRows.isEmpty, compact: placement.compact)
                                .frame(width: placement.frame.width, height: placement.frame.height, alignment: .topLeading)
                                .position(x: placement.frame.midX, y: placement.frame.midY)
                                .transition(.opacity)
                        }
                    }
                    if visible.isEmpty {
                        Text("No active displays · restore a display below")
                            .font(.system(size: 12)).foregroundStyle(Palette.textMuted)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .animation(reduceMotion || model.activeDrag != nil ? nil : .easeOut(duration: 0.18), value: plan)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)
            // Always reserve one chip row: collapsing a screen cannot first
            // resize the canvas and then trigger a second layout transition.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.collapsedMonitors) { monitor in
                        let hidden = model.deskPreferences.hidden.contains(monitor.display.displayId)
                        Button { model.restoreDisplay(monitor.display.displayId) } label: {
                            Label(monitor.display.name + " · " + (hidden ? "hidden" : model.inactiveReason(monitor.display) ?? "inactive"),
                                  systemImage: hidden ? "eye.slash" : "display")
                        }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.text)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(Palette.surface).clipShape(RoundedRectangle(cornerRadius: 5))
                            .help("Restore " + monitor.display.name)
                            .accessibilityLabel("Restore " + monitor.display.name)
                    }
                }
            }.frame(height: 32).padding(.horizontal, 16)
            Group {
                if let edit = model.editing {
                    OverviewDraftBar(model: model, edit: edit)
                } else {
                    OverviewHint(model: model)
                }
            }
            .frame(height: Self.hintHeight)
            .padding(.horizontal, 24)
        }
        .background(
            ZStack {
                OverviewStageGround()
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { model.clearSelection() }
            }
        )
    }
}

// MARK: - Display

/// One monitor: its name and size and what its map shows, the map, and
/// every Desktop it owns beneath it.
struct OverviewDisplayBlock: View {
    @ObservedObject var model: OverviewModel
    let monitor: OverviewDeskMonitor
    let mapSize: CGSize
    let thumbSize: CGSize
    /// Nothing anywhere is in scope; the stage says so once.
    let quiet: Bool
    var compact = false

    /// The focused Desktop if it's this monitor's, else the one it shows.
    private var viewed: OverviewDeskSpace? {
        if let id = model.scope.spaceId, let space = monitor.spaces.first(where: { $0.spaceId == id }) {
            return space
        }
        return monitor.spaces.first(where: \.isCurrent) ?? monitor.spaces.first
    }

    /// Another monitor's Desktop, or another monitor, has the focus.
    private var scopedOut: Bool { !monitor.inScope }

    var body: some View {
        VStack(alignment: .leading, spacing: OverviewStage.spacing) {
            head
                .frame(width: mapSize.width, height: OverviewStage.headHeight)
            if let viewed {
                OverviewMap(model: model, display: monitor.display, space: viewed, size: mapSize, quiet: quiet || scopedOut)
                    .modifier(OverviewScreenDrop(model: model, display: monitor.display, spaceId: viewed.spaceId, mapSize: mapSize))
            }
            if !compact { desktops }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(monitor.display.name)
    }

    private var head: some View {
        let b = monitor.display.bounds
        let state: String = {
            guard let viewed else { return "" }
            if let reason = model.inactiveReason(monitor.display) { return reason }
            if viewed.isCurrent { return "live · \(viewed.title)" }
            return "viewing \(viewed.desktop == nil ? "full screen" : viewed.title)"
        }()
        let name = Text(monitor.display.name)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(Palette.text)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            // The size only where there's room for it whole.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    name.fixedSize()
                    Text("\(Int(b.width))×\(Int(b.height))")
                        .font(.system(size: 11))
                        .foregroundColor(Palette.textMuted)
                        .fixedSize()
                }
                name.lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 6)
            if mapSize.width > 320 { Text(state)
                .font(.system(size: 11))
                .foregroundColor(viewed?.isCurrent == false ? Palette.text : Palette.textDim)
                .lineLimit(1)
                .fixedSize() }
            Button { model.pinDisplay(monitor.display.displayId) } label: {
                Image(systemName: model.deskPreferences.pinned == monitor.display.displayId ? "pin.fill" : "pin")
                    .frame(width: 24, height: 24)
            }.buttonStyle(.plain).help("Pin " + monitor.display.name)
                .accessibilityLabel("Pin " + monitor.display.name)
            Button { model.hideDisplay(monitor.display.displayId) } label: {
                Image(systemName: "eye.slash").frame(width: 24, height: 24)
            }.buttonStyle(.plain).help("Hide " + monitor.display.name)
                .accessibilityLabel("Hide " + monitor.display.name)
        }
    }

    // MARK: Desktops

    @ViewBuilder
    private var desktops: some View {
        let count = CGFloat(monitor.spaces.count)
        let row = HStack(alignment: .top, spacing: OverviewStage.thumbGap) {
            ForEach(monitor.spaces) { space in thumb(space) }
        }
        if thumbSize.width * count + OverviewStage.thumbGap * (count - 1) > mapSize.width + 1 {
            ScrollView(.horizontal, showsIndicators: false) { row }
                .frame(width: mapSize.width, alignment: .leading)
        } else {
            row
        }
    }

    /// A Desktop in miniature with its name and count. The dot marks the
    /// one this monitor shows; the ring, the focused one. Tapping focuses
    /// the list on it; tapping the focused one gives the whole list back.
    private func thumb(_ space: OverviewDeskSpace) -> some View {
        let focused = model.scope.spaceId == space.spaceId
        let count = space.rows.filter(\.inScope).count
        let state: String = space.isCurrent ? "showing" : (space.mapNote ?? "not showing")
        return Button {
            model.chooseDesktop(space.spaceId)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                OverviewMiniDesktop(model: model, display: monitor.display, space: space, size: thumbSize)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(focused ? Palette.text : Color.clear, lineWidth: 1.5)
                    )
                HStack(spacing: 4) {
                    if space.isCurrent {
                        Circle().fill(Palette.text).frame(width: 4, height: 4)
                    }
                    // Narrow thumbs keep just the number; help and
                    // accessibility still name the Desktop and monitor.
                    Text(thumbSize.width < 76 ? space.desktop.map { "\($0)" } ?? "FS" : space.title)
                        .font(.system(size: 11))
                        .foregroundColor(space.isCurrent || focused ? Palette.text : Palette.textMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 2)
                    Text(space.rows.isEmpty ? "–" : "\(space.rows.count)")
                        .font(.system(size: 11))
                        .foregroundColor(Palette.textMuted)
                        .fixedSize()
                }
                .frame(width: thumbSize.width, height: OverviewStage.captionHeight)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(focused ? "\(space.title) on \(monitor.display.name) · click for every Desktop" : "\(space.title) on \(monitor.display.name), \(state)")
        .accessibilityLabel("\(space.title) on \(monitor.display.name), \(state), \(count == 0 ? "nothing in scope" : "\(count) in scope")")
        .modifier(OverviewScreenDrop(model: model, display: monitor.display, spaceId: space.spaceId))
        .accessibilityHint(focused ? "Show every Desktop" : "Focus the list on this Desktop")
        .accessibilityAddTraits(focused ? .isSelected : [])
    }
}

// MARK: - Map

/// A monitor-shaped map of one Desktop: the listed windows at their frames,
/// what the list leaves out faintly behind them. Only the showing Desktop's
/// frames are live; any other says so across its top.
struct OverviewMap: View {
    @ObservedObject var model: OverviewModel
    let display: OverviewDisplay
    let space: OverviewDeskSpace
    let size: CGSize
    /// Don't say "nothing in scope" here: another monitor has the focus, or
    /// the stage says it once for all of them.
    let quiet: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.35))
            ForEach(context, id: \.wid) { tile in contextView(tile) }
            ForEach(tiles.reversed(), id: \.row.wid) { tile in tileView(tile) }
            if !quiet, !space.rows.contains(where: \.inScope) {
                Text("Nothing in scope here")
                    .font(.system(size: 11))
                    .foregroundColor(Palette.textMuted)
                    .frame(width: size.width, height: size.height)
                    .allowsHitTesting(false)
            }
            if !space.isCurrent {
                peekBar
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    space.isCurrent ? Palette.borderLit : Palette.textMuted,
                    style: StrokeStyle(lineWidth: OverviewChrome.stroke, dash: space.isCurrent ? [] : [4, 3])
                )
        )
    }

    /// Why this Desktop's windows can't be acted on, and the way back.
    private var peekBar: some View {
        let text = space.desktop == nil
            ? "Full-screen Space · drop on an ordinary Desktop instead."
            : "\(space.title) · last known positions"
        return HStack(spacing: 8) {
            Image(systemName: "eye")
                .font(.system(size: 9))
                .foregroundColor(Palette.textDim)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(Palette.textDim)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Palette.bg.opacity(0.92))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(OverviewChrome.edgeLit, lineWidth: OverviewChrome.stroke))
        )
        .padding(6)
        .frame(width: size.width, alignment: .leading)
    }

    // MARK: Windows

    private struct Tile {
        let row: OverviewRow
        let rect: CGRect
        let live: Bool
    }

    private func scaled(_ frame: CGRect) -> CGRect? {
        let bounds = display.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let sx: CGFloat = size.width / bounds.width
        let sy: CGFloat = size.height / bounds.height
        let rect = CGRect(
            x: (frame.minX - bounds.minX) * sx, y: (frame.minY - bounds.minY) * sy,
            width: frame.width * sx, height: frame.height * sy
        ).intersection(CGRect(origin: .zero, size: size))
        guard !rect.isNull, rect.width >= 3, rect.height >= 3 else { return nil }
        return rect.integral
    }

    private var tiles: [Tile] {
        space.rows.compactMap { (row: OverviewRow) -> Tile? in
            let live = space.drawsLive(row)
            if space.desktop == nil {
                return Tile(row: row, rect: CGRect(origin: .zero, size: size).insetBy(dx: 8, dy: 8), live: live)
            }
            guard let frame = row.frame, let rect = scaled(frame) else { return nil }
            return Tile(row: row, rect: rect.integral, live: live)
        }
    }

    /// A window: its app, then its title where there's room. Dashed where
    /// the frame is last known.
    private func tileView(_ tile: Tile) -> some View {
        let wid = tile.row.wid
        let selected = model.selection.contains(wid)
        let scoped = !(model.scope.layerIds ?? model.scope.layerId.map { [$0] } ?? []).isEmpty
        let member = scoped && tile.row.inScope
        let fill: Color = member ? Palette.running.opacity(0.16) : scoped ? Color.clear : selected ? Color.white.opacity(0.2) : (tile.live ? Color(white: 0.17) : Color.white.opacity(0.025))
        let ink: Color = selected ? Palette.text : Palette.textDim
        let showsApp = tile.rect.width > 36 && tile.rect.height > 15
        let showsTitle = !tile.row.title.isEmpty && tile.rect.width > 60 && tile.rect.height > 32
        let base = ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3).fill(fill)
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(
                    member ? Palette.running.opacity(0.65) : scoped ? Color.clear : selected ? Palette.text : Color.white.opacity(tile.live ? 0.28 : 0.3),
                    style: StrokeStyle(lineWidth: selected ? 1.5 : OverviewChrome.stroke, dash: tile.live ? [] : [4, 3])
                )
            if showsApp {
                VStack(alignment: .leading, spacing: 2) {
                    Text(scoped && !tile.row.inScope ? tile.row.title : tile.row.app)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(ink)
                        .lineLimit(1)
                    if showsTitle && (!scoped || tile.row.inScope) {
                        Text(tile.row.title)
                            .font(.system(size: 11))
                            .foregroundColor(selected ? Palette.text : Palette.textMuted)
                            .lineLimit(tile.rect.height > 60 ? 2 : 1)
                            .truncationMode(.tail)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.top, 5)
            }
        }
        .frame(width: tile.rect.width, height: tile.rect.height)
        .contentShape(Rectangle())
        .modifier(OverviewMembershipInteractions(model: model, wid: wid))
        .onTapGesture { OverviewDeskRow.pick(wid, model: model) }
        .simultaneousGesture(TapGesture(count: 2).onEnded { model.focus(wid) })
        .help(tile.row.title.isEmpty ? tile.row.app : "\(tile.row.app) — \(tile.row.title)")
        .anchorPreference(key: OverviewCapsuleAnchorKey.self, value: .bounds) { anchor in
            model.focusedWid == wid ? [OverviewCapsuleAnchor(bounds: anchor, inTray: false)] : []
        }
        return base
            .offset(x: tile.rect.minX, y: tile.rect.minY)
            .accessibilityElement()
            .accessibilityLabel("\(tile.row.app), \(tile.row.title.isEmpty ? "Untitled" : tile.row.title), \(tile.live ? "live" : "last known")")
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private struct Context {
        let wid: UInt32
        let rect: CGRect
    }

    /// Windows here that the list leaves out: a layer's non-members, or
    /// what search or kind hide. Faint, and never a target.
    private var context: [Context] {
        guard space.desktop != nil else { return [] }
        let listed = Set(model.projection.rows.map(\.wid))
        let rows: [OverviewRow] = model.projection.all.values.filter { row in
            !listed.contains(row.wid) && row.display == display.index && row.spaceId == space.spaceId
        }
        return rows.sorted { $0.wid > $1.wid }.compactMap { row in
            guard let frame = row.frame, let rect = scaled(frame) else { return nil }
            return Context(wid: row.wid, rect: rect)
        }
    }

    private func contextView(_ tile: Context) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.white.opacity(0.02))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.white.opacity(0.07), lineWidth: OverviewChrome.stroke))
            .frame(width: tile.rect.width, height: tile.rect.height)
            .offset(x: tile.rect.minX, y: tile.rect.minY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Empty scope

/// Nothing anywhere is in scope: what the scope is, and each way out. The
/// selection is kept.
struct OverviewEmptyScope: View {
    @ObservedObject var model: OverviewModel

    private var sentence: String {
        var parts: [String] = [model.scope.preset.map { $0.lowercased() } ?? "windows"]
        if let id = model.scope.layerId {
            parts.append("in " + (model.layers.first { $0.id == id }?.label ?? id))
        }
        if let id = model.scope.spaceId, let title = model.projection.desk.flatMap(\.spaces).first(where: { $0.spaceId == id })?.title {
            parts.append("on " + title)
        }
        if !model.scope.search.isEmpty { parts.append("matching “\(model.scope.search)”") }
        return "No \(parts.joined(separator: " ")). The scope only filters what you see; the selection is kept."
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("Nothing in scope")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Palette.text)
            Text(sentence)
                .font(.system(size: 11))
                .foregroundColor(Palette.textDim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                if model.scope.preset != nil {
                    Button("Clear kind") { model.scope.preset = nil }
                        .buttonStyle(.overview)
                }
                if !model.scope.search.isEmpty {
                    Button("Clear search") { model.scope.search = "" }
                        .buttonStyle(.overview)
                }
                if model.scope.spaceId != nil {
                    Button("Every Desktop") { model.chooseDesktop(nil) }
                        .buttonStyle(.overview)
                }
                if model.scope.layerId != nil {
                    Button("No layer") { model.chooseLayer(nil) }
                        .buttonStyle(.overview)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: 320)
        .overviewCard(radius: 9)
    }
}

// MARK: - Hint and draft

/// How to pick, the keys, and what the scope holds.
struct OverviewHint: View {
    @ObservedObject var model: OverviewModel

    var body: some View {
        let rows = model.workingRows
        let live = rows.filter { model.projection.placeExclusion($0.wid) == nil }.count
        HStack(spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    Text("Click to select · ⌘-click to add · double-click to focus")
                    Text("T · D · / · ↵")
                }
                Text("T · D · / · ↵")
            }
            .font(.system(size: 11))
            .foregroundColor(Palette.textMuted)
            .lineLimit(1)
            Spacer(minLength: 8)
            (Text("\(rows.count)").foregroundColor(Palette.text) + Text(" in scope · ")
                + Text("\(live)").foregroundColor(Palette.text) + Text(" can arrange · \(rows.count - live) elsewhere"))
                .font(.system(size: 11))
                .foregroundColor(Palette.textMuted)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// While a layer is being edited: what's changed and the way out. Saving
/// never arranges; only the active layer can be saved and arranged.
struct OverviewDraftBar: View {
    @ObservedObject var model: OverviewModel
    let edit: LayerEdit

    var body: some View {
        let name = model.layers.first { $0.id == edit.layerId }?.label ?? edit.layerId
        HStack(spacing: 8) {
            Image(systemName: "square.3.layers.3d")
                .font(.system(size: 10))
                .foregroundColor(Palette.textDim)
            Text("Editing ").font(.system(size: 11)).foregroundColor(Palette.textDim)
                + Text(name).font(.system(size: 11, weight: .medium)).foregroundColor(Palette.text)
            Text(edit.hasChanges ? "unsaved changes" : "no changes yet")
                .font(.system(size: 11))
                .foregroundColor(Palette.textMuted)
                .lineLimit(1)
            Spacer(minLength: 6)
            Button("Discard") { model.cancelEditing() }
                .buttonStyle(.overview(.quiet, height: 22))
            Button("Save") { model.saveLayer() }
                .buttonStyle(.overview(height: 22))
                .disabled(!edit.hasChanges)
                .help("Saves the layout and tucks. Doesn't move windows.")
            Button("Save & arrange") { model.saveAndRearrange() }
                .buttonStyle(.overview(height: 22))
                .disabled(!model.canRearrange)
                .help(model.canRearrange ? "Saves, then lays out the active layer's windows again" : "Only the active layer can be arranged")
        }
        .padding(.leading, 10)
        .padding(.trailing, 3)
        .frame(height: 28)
        .overviewCard(radius: 7)
    }
}

// MARK: - Tray

/// Below the maps: every listed window the maps don't show, grouped by
/// where it is, and the box that arranges the selection.
private struct OverviewTrayColumnDrop: ViewModifier {
    @ObservedObject var model: OverviewModel
    let group: OverviewTray.Group
    @ViewBuilder func body(content: Content) -> some View {
        if group.destination != nil, let display = group.display, let spaceId = group.spaceId {
            content.modifier(OverviewScreenDrop(model: model, display: display, spaceId: spaceId, targetKind: "tray"))
        } else {
            content
        }
    }
}

struct OverviewTray: View {
    @ObservedObject var model: OverviewModel

    static let height: CGFloat = 172

    struct Group: Identifiable {
        let id: String
        let title: String
        let detail: String
        let rows: [OverviewRow]
        let display: OverviewDisplay?
        let spaceId: Int?

        var destination: OverviewMoveDestination? {
            guard let display, let spaceId else { return nil }
            return OverviewWindowDrop.destination(on: display, spaceId: spaceId)
        }
    }

    /// Desktops the maps aren't showing, monitor by monitor, then the
    /// windows on no Space.
    var groups: [Group] {
        var out: [Group] = []
        for monitor in model.projection.desk {
            let viewed = model.scope.spaceId.flatMap { id in monitor.spaces.first { $0.spaceId == id } }
                ?? monitor.spaces.first(where: \.isCurrent)
            for space in monitor.spaces where space.spaceId != viewed?.spaceId && !space.rows.isEmpty {
                let state = space.isCurrent ? "live" : (space.mapNote ?? "not showing")
                out.append(Group(
                    id: "\(space.spaceId)", title: space.title,
                    detail: "\(monitor.display.name) · \(state)", rows: space.rows,
                    display: monitor.display, spaceId: space.spaceId
                ))
            }
        }
        if !model.projection.unplaced.isEmpty {
            out.append(Group(id: "unplaced", title: "Not on a Space", detail: "hidden · minimized", rows: model.projection.unplaced, display: nil, spaceId: nil))
        }
        return out
    }

    var body: some View {
        HStack(spacing: 0) {
            GeometryReader { geo in
                let groups = self.groups
                if groups.isEmpty {
                    Text("Every listed window is on a map")
                        .font(.system(size: 11))
                        .foregroundColor(Palette.textMuted)
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    let width = max(280, floor(geo.size.width / CGFloat(groups.count)))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(groups) { group in
                                groupView(group)
                                    .frame(width: width, height: geo.size.height, alignment: .topLeading)
                                    .overlay(alignment: .trailing) {
                                        Rectangle().fill(Palette.border).frame(width: 1)
                                    }
                                    .modifier(OverviewTrayColumnDrop(model: model, group: group))
                            }
                        }
                    }
                }
            }
            Rectangle().fill(Palette.border).frame(width: 1)
            OverviewArrangeBox(model: model)
        }
        .frame(height: Self.height)
    }

    private func groupView(_ group: Group) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(group.title.uppercased())
                    .font(Typo.monoBold(10))
                    .foregroundColor(Palette.textDim)
                    .lineLimit(1)
                    .fixedSize()
                Text(group.detail)
                    .font(Typo.mono(10))
                    .foregroundColor(Palette.textMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Text("\(group.rows.count)")
                    .font(Typo.mono(10))
                    .foregroundColor(Palette.textMuted)
            }
            .padding(.horizontal, 12)
            .frame(height: 18)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(group.rows) { row in chip(row, unplaced: group.id == "unplaced") }
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    /// A window: app, title, and why it isn't on a map where the group
    /// doesn't already say. Outside the Desktop focus, faint.
    private func chip(_ row: OverviewRow, unplaced: Bool) -> some View {
        let selected = model.selection.contains(row.wid)
        let why: String? = {
            if unplaced { return row.state.label.lowercased() }
            switch row.state {
            case .appHidden: return "hidden"
            case .parked: return "parked"
            default: return LayerOverviewDetail.tierLabel(row.tier)
            }
        }()
        return HStack(spacing: 8) {
            OverviewAppIcon(app: row.app, pid: row.pid)
                .frame(width: 18, height: 18)
            Text(row.app)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Palette.text)
                .lineLimit(1)
                .fixedSize()
            Text(row.title.isEmpty ? "Untitled" : row.title)
                .font(.system(size: 12))
                .foregroundColor(Palette.textDim)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if let why {
                Text(why)
                    .font(.system(size: 11))
                    .foregroundColor(Palette.textMuted)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 5).fill(selected ? Palette.surfaceHov : Color.clear))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(selected ? OverviewChrome.edgeOn : Color.clear, lineWidth: OverviewChrome.stroke)
        )
        .contentShape(Rectangle())
        .modifier(OverviewMembershipInteractions(model: model, wid: row.wid))
        .onTapGesture { OverviewDeskRow.pick(row.wid, model: model) }
        .simultaneousGesture(TapGesture(count: 2).onEnded { model.focus(row.wid) })
        .anchorPreference(key: OverviewCapsuleAnchorKey.self, value: .bounds) { anchor in
            model.focusedWid == row.wid ? [OverviewCapsuleAnchor(bounds: anchor, inTray: true)] : []
        }
        .help(row.title.isEmpty ? row.app : "\(row.app) — \(row.title)")
        .accessibilityElement()
        .accessibilityLabel("\(row.app), \(row.title.isEmpty ? "Untitled" : row.title), \(model.projection.location(of: row))")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Tile and distribute the selection, monitor by monitor, saying what's
/// left out and why; and the layer in scope, with the way to edit it.
/// Nothing here saves a layer.
struct OverviewArrangeBox: View {
    @ObservedObject var model: OverviewModel

    var body: some View {
        let tile = model.plan(.tile)
        let distribute = model.plan(.distribute)
        let names: [Int: String] = Dictionary(uniqueKeysWithValues: model.projection.displays.map { ($0.index, $0.name) })
        let split: String = tile.groups.isEmpty
            ? (model.selection.isEmpty ? "Select windows to arrange them" : "No live windows selected")
            : tile.groups.map { "\(names[$0.display] ?? "Display") \($0.windows.count)" }.joined(separator: " · ")
        let leftOut: String = tile.excluded.isEmpty
            ? "Only live windows on a showing Desktop move"
            : "Left out: \(tile.excludedSummary)"
        VStack(alignment: .leading, spacing: 7) {
            Text("ARRANGE SELECTION")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Palette.textDim)
            HStack(spacing: 8) {
                arrangeButton(tile, key: "T")
                arrangeButton(distribute, key: "D")
            }
            Text(split)
                .font(.system(size: 11))
                .foregroundColor(Palette.textDim)
                .lineLimit(1)
            Text(leftOut)
                .font(.system(size: 11))
                .foregroundColor(Palette.textMuted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            layerLine
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 300)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.015))
    }

    private func arrangeButton(_ plan: OverviewBulkPlan, key: String) -> some View {
        Button {
            model.run(plan)
        } label: {
            HStack(spacing: 6) {
                Text("\(plan.action.verb) \(plan.eligibleCount)")
                OverviewKeycap(key: key)
            }
        }
        .buttonStyle(.overview(fill: true))
        .disabled(!plan.isEnabled)
        .help(plan.excludedSummary.isEmpty ? plan.label : "\(plan.label). Left out: \(plan.excludedSummary)")
        .accessibilityLabel(plan.label)
    }

    @ViewBuilder
    private var layerLine: some View {
        if let ids = model.scope.layerIds, ids.count > 1 {
            Text(model.layers.filter { ids.contains($0.id) }.map(\.label).joined(separator: " + ") + " · \(ids.count) layers")
                .font(.system(size: 11)).foregroundColor(Palette.textDim).lineLimit(1)
        } else if let id = model.scope.layerId, let layer = model.layers.first(where: { $0.id == id }) {
            HStack(spacing: 6) {
                Image(systemName: "square.3.layers.3d")
                    .font(.system(size: 10))
                    .foregroundColor(Palette.textDim)
                Text(layer.label).font(.system(size: 11, weight: .medium)).foregroundColor(Palette.text)
                    + Text(layer.isActive ? " · active layer" : " · not active").font(.system(size: 11)).foregroundColor(Palette.textDim)
                Spacer(minLength: 4)
                if model.editing == nil {
                    Button("Edit layer") {
                        model.beginEditing(layer)
                        model.membershipShown = true
                    }
                    .buttonStyle(.overview(.quiet, height: 22))
                    .fixedSize()
                    .help("Edit the layout and tucks in the list")
                }
            }
            .lineLimit(1)
        }
    }
}


/// A Desktop in miniature: its windows as outlines at their frames, the
/// selected ones in ink. Only the showing Space has live frames; the rest
/// are last known or saved homes, drawn dashed. A full-screen Space is one
/// box.
struct OverviewMiniDesktop: View {
    @ObservedObject var model: OverviewModel
    let display: OverviewDisplay
    let space: OverviewDeskSpace
    let size: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.black.opacity(space.rows.isEmpty ? 0.18 : 0.35))
            ForEach(tiles.reversed(), id: \.wid) { tile in tileView(tile) }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(
                    space.isCurrent ? Palette.borderLit : Palette.border,
                    style: StrokeStyle(lineWidth: OverviewChrome.stroke, dash: space.isCurrent ? [] : [2, 1.5])
                )
        )
    }

    private struct Tile {
        let wid: UInt32
        let rect: CGRect
        let live: Bool
    }

    private var tiles: [Tile] {
        let bounds = display.bounds
        guard bounds.width > 0, bounds.height > 0 else { return [] }
        let map = CGRect(origin: .zero, size: size)
        let sx: CGFloat = size.width / bounds.width
        let sy: CGFloat = size.height / bounds.height
        return space.rows.compactMap { (row: OverviewRow) -> Tile? in
            let live = space.drawsLive(row)
            if space.desktop == nil {
                return Tile(wid: row.wid, rect: map.insetBy(dx: 2, dy: 2), live: live)
            }
            guard let frame = row.frame else { return nil }
            let scaled = CGRect(
                x: (frame.minX - bounds.minX) * sx, y: (frame.minY - bounds.minY) * sy,
                width: frame.width * sx, height: frame.height * sy
            )
            let rect = scaled.intersection(map)
            guard !rect.isNull, rect.width >= 2, rect.height >= 2 else { return nil }
            return Tile(wid: row.wid, rect: rect.integral, live: live)
        }
    }

    private func tileView(_ tile: Tile) -> some View {
        let selected = model.selection.contains(tile.wid)
        return RoundedRectangle(cornerRadius: 1.5)
            .fill(Color.white.opacity(selected ? 0.34 : (tile.live ? 0.1 : 0.03)))
            .overlay(
                RoundedRectangle(cornerRadius: 1.5)
                    .strokeBorder(
                        selected ? Palette.text : Color.white.opacity(tile.live ? 0.3 : 0.24),
                        style: StrokeStyle(lineWidth: OverviewChrome.stroke, dash: tile.live ? [] : [2, 1.5])
                    )
            )
            .frame(width: tile.rect.width, height: tile.rect.height)
            .offset(x: tile.rect.minX, y: tile.rect.minY)
    }
}

// MARK: - Rows

/// A window's row: app, title and what keeps it from showing. Its group
/// says which Desktop, so the row only adds what the group doesn't.
struct OverviewDeskRow: View {
    @ObservedObject var model: OverviewModel
    let row: OverviewRow
    /// Rows outside any Desktop say "minimized or closed" when their
    /// group doesn't.
    let showsUnknown: Bool

    /// Click selects; shift extends over the rows, ⌘ adds or removes.
    static func pick(_ wid: UInt32, model: OverviewModel) {
        let mods = NSEvent.modifierFlags
        if mods.contains(.shift) { model.extend(to: wid) }
        else if mods.contains(.command) { model.toggle(wid) }
        else { model.select(wid) }
    }

    var body: some View {
        let selected = model.selection.contains(row.wid)
        Button {
            Self.pick(row.wid, model: model)
        } label: {
            HStack(spacing: 8) {
                Text(row.app)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Palette.textDim)
                    .frame(width: 70, alignment: .leading)
                    .lineLimit(1)
                Text(row.title.isEmpty ? "Untitled" : row.title)
                    .font(.system(size: 11))
                    .foregroundColor(Palette.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 6)
                if let note {
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundColor(Palette.textMuted)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 4).fill(selected ? Palette.surfaceHov : Color.clear))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(selected ? OverviewChrome.edgeOn : Color.clear, lineWidth: OverviewChrome.stroke)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(row.app), \(row.title.isEmpty ? "Untitled" : row.title), \(model.projection.location(of: row))")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .modifier(OverviewMembershipInteractions(model: model, wid: row.wid))
        .accessibilityAction(named: selected ? "Remove from selection" : "Add to selection") { model.toggle(row.wid) }
    }

    private var note: String? {
        var parts: [String] = []
        if let tier = LayerOverviewDetail.tierLabel(row.tier) { parts.append(tier) }
        switch row.state {
        case .parked: parts.append("parked")
        case .appHidden: parts.append("hidden")
        case .unknown where showsUnknown: parts.append("minimized or closed")
        default: break
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Cache NSWorkspace icons by app identity, never decode an icon on each hover.
struct OverviewAppIcon: View {
    let app: String
    let pid: Int32
    private static var cache: [String: NSImage] = [:]
    private var icon: NSImage? {
        if let cached = Self.cache[app] { return cached }
        let running = NSRunningApplication(processIdentifier: pid)?.bundleURL
        let paths: [String] = (running.map { [$0.path] } ?? []) + ["/Applications", "/System/Applications", "/Applications/Utilities", NSHomeDirectory() + "/Applications"].map { "\($0)/\(app).app" }
        guard let path = paths.first(where: { FileManager.default.fileExists(atPath: $0) }) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: path)
        Self.cache[app] = image
        return image
    }
    var body: some View {
        if let icon { Image(nsImage: icon).resizable().interpolation(.high).accessibilityHidden(true) }
        else { Image(systemName: "app").font(.system(size: 16)).foregroundStyle(Palette.textDim).accessibilityHidden(true) }
    }
}
