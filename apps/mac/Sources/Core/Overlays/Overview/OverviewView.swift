import AppKit
import SwiftUI

/// Overview: one page for every window. The scope column picks what to
/// browse, the canvas and list show it, and the inspector acts on the one
/// selection. Browsing never touches the desktop; only the inspector's
/// buttons and the canvas's tile and distribute keys do.
struct OverviewView: View {
    @ObservedObject var model: OverviewModel
    @ObservedObject var controller: ScreenMapController
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            scopeColumn
                .frame(width: 210)
            Divider().overlay(Palette.border)
            VStack(spacing: 0) {
                ScreenMapView(
                    controller: controller,
                    studioLayerScopeId: .constant(nil),
                    hosted: model.canvasHost,
                    onHostedCommand: { command in
                        switch command {
                        case .bulk(let action): model.run(model.plan(action))
                        case .monitor(let delta): model.stepMonitor(delta)
                        case .search: model.requestSearch()
                        }
                    },
                    onOutlineClick: { model.outlineClicked($0, extending: $1) }
                )
                .frame(minHeight: 240, maxHeight: .infinity)
                Divider().overlay(Palette.border)
                windowList
                    .frame(minHeight: 180, maxHeight: .infinity)
            }
            Divider().overlay(Palette.border)
            inspector
                .frame(width: 290)
        }
        .background(Palette.bg)
        .onAppear {
            model.start()
            model.attach(canvas: controller)
            controller.enter()
            controller.editor?.focusDisplay(model.scope.display, keepStack: true)
        }
        .onDisappear {
            model.detach(canvas: controller)
            model.stop()
        }
        .onChange(of: model.scope.display) { index in
            controller.editor?.focusDisplay(index, keepStack: true)
        }
    }

    // MARK: Scope column

    private var scopeColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TextField("Search windows", text: Binding(
                    get: { model.scope.search },
                    set: { model.scope.search = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .font(Typo.mono(10))
                .focused($searchFocused)
                .onChange(of: model.searchRequest) { _ in searchFocused = true }

                scopeSection("Monitor") {
                    scopeOption("All monitors", selected: model.scope.display == nil) {
                        model.scope.display = nil
                        model.scope.spaceId = nil
                    }
                    ForEach(model.displays, id: \.index) { display in
                        scopeOption(display.name, selected: model.scope.display == display.index) {
                            model.scope.display = display.index
                            model.scope.spaceId = nil
                        }
                    }
                }

                if let index = model.scope.display, let display = model.displays.first(where: { $0.index == index }) {
                    scopeSection("Space") {
                        scopeOption("Every Space", selected: model.scope.spaceId == nil) { model.scope.spaceId = nil }
                        ForEach(Array(display.desktops.enumerated()), id: \.element) { offset, space in
                            scopeOption(
                                "Desktop \(offset + 1)" + (space == display.currentSpaceId ? " · showing" : ""),
                                selected: model.scope.spaceId == space
                            ) { model.scope.spaceId = space }
                        }
                    }
                }

                scopeSection("Layer") {
                    scopeOption("All windows", selected: model.scope.layerId == nil) { model.scope.layerId = nil }
                    ForEach(model.layers, id: \.id) { layer in
                        scopeOption(layer.label + (layer.isActive ? " · active" : ""), selected: model.scope.layerId == layer.id) {
                            model.scope.layerId = layer.id
                        }
                    }
                }

                scopeSection("Kind") {
                    ForEach(FilterPreset.allCases, id: \.self) { preset in
                        let raw: String? = preset == .all ? nil : preset.rawValue
                        scopeOption(preset.rawValue, selected: model.scope.preset == raw) { model.scope.preset = raw }
                    }
                }
            }
            .padding(12)
        }
    }

    private func scopeSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(Typo.monoBold(8))
                .foregroundColor(Palette.textMuted)
                .padding(.bottom, 2)
            content()
        }
    }

    private func scopeOption(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Typo.mono(10))
                .foregroundColor(selected ? Palette.text : Palette.textDim)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 4).fill(selected ? Palette.surface : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: List

    private var windowList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.projection.counts.line)
                .font(Typo.mono(9))
                .foregroundColor(Palette.textMuted)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(model.projection.groups) { group in
                            Section {
                                ForEach(group.rows) { row in listRow(row).id(row.wid) }
                            } header: {
                                Text(group.title)
                                    .font(Typo.monoBold(9))
                                    .foregroundColor(group.inScope ? Palette.textDim : Palette.textMuted)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(Palette.bg)
                            }
                        }
                    }
                }
                .onChange(of: model.focusedWid) { wid in
                    if let wid { proxy.scrollTo(wid) }
                }
                // Show in scope: the row appears with the new scope, so scroll
                // once it's laid out, even if it was already focused.
                .onChange(of: model.revealRequest) { request in
                    guard let wid = request.wid else { return }
                    DispatchQueue.main.async { proxy.scrollTo(wid, anchor: .center) }
                }
            }
            // ↑ ↓ move through the rows; shift adds to the selection.
            .focusable()
            .onMoveCommand { direction in
                let extend = NSEvent.modifierFlags.contains(.shift)
                switch direction {
                case .up: model.step(-1, extend: extend)
                case .down: model.step(1, extend: extend)
                default: break
                }
            }
            .onExitCommand { model.clearSelection() }
        }
    }

    private func listRow(_ row: OverviewRow) -> some View {
        let selected = model.selection.contains(row.wid)
        return HStack(spacing: 0) {
            Button {
                let mods = NSEvent.modifierFlags
                if mods.contains(.shift) { model.extend(to: row.wid) }
                else if mods.contains(.command) { model.toggle(row.wid) }
                else { model.select(row.wid) }
            } label: {
                rowLabel(row)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(row.app), \(row.title.isEmpty ? "Untitled" : row.title), \(row.state.label)")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityAction(named: selected ? "Remove from selection" : "Add to selection") { model.toggle(row.wid) }
            if !row.inScope, row.state != .unknown {
                Button("Show") { model.showInScope(row.wid) }
                    .buttonStyle(.plain)
                    .font(Typo.monoBold(8))
                    .foregroundColor(Palette.textDim)
                    .padding(.leading, 8)
                    .help("Scope to this window's monitor and Space")
                    .accessibilityLabel("Show \(row.app) in scope")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .background(selected ? Palette.surface : Color.clear)
    }

    private func rowLabel(_ row: OverviewRow) -> some View {
        HStack(spacing: 8) {
            Text(row.app)
                .font(Typo.monoBold(9))
                .foregroundColor(row.inScope ? Palette.textDim : Palette.textMuted)
                .frame(width: 110, alignment: .leading)
                .lineLimit(1)
            Text(row.title.isEmpty ? "Untitled" : row.title)
                .font(Typo.mono(9))
                .foregroundColor(row.inScope ? Palette.text : Palette.textDim)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            if let tier = LayerOverviewDetail.tierLabel(row.tier) {
                Text(tier).font(Typo.mono(8)).foregroundColor(Palette.textMuted)
            }
            Text(row.state.label)
                .font(Typo.mono(8))
                .foregroundColor(Palette.textMuted)
        }
        .contentShape(Rectangle())
    }

    // MARK: Inspector

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                selectionSummary
                if let error = model.actionError { errorText(error) }
                if let wid = model.focusedWid, let row = model.projection.all[wid] {
                    windowDetail(row)
                }
                bulkActions
                if let id = model.scope.layerId, let layer = model.layers.first(where: { $0.id == id }) {
                    layerDetail(layer)
                }
            }
            .padding(12)
        }
    }

    private var selectionSummary: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(model.selection.isEmpty ? "No selection" : "\(model.selection.count) selected")
                    .font(Typo.monoBold(10))
                    .foregroundColor(Palette.text)
                Spacer()
                if !model.selection.isEmpty {
                    Button("Clear") { model.clearSelection() }
                        .buttonStyle(.plain)
                        .font(Typo.mono(9))
                        .foregroundColor(Palette.textDim)
                }
            }
            let outside = model.projection.outOfScopeSelection
            if !outside.isEmpty {
                Text("\(outside.count) outside this scope")
                    .font(Typo.mono(8))
                    .foregroundColor(Palette.textMuted)
                ForEach(outside, id: \.wid) { item in
                    outsideRow(item.wid, reason: item.reason)
                }
            }
        }
    }

    /// A selected window the scope hides: what it is, why, and the way back.
    private func outsideRow(_ wid: UInt32, reason: Exclusion) -> some View {
        let row = model.projection.all[wid]
        return HStack(spacing: 6) {
            Button { model.inspect(wid) } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.map { $0.title.isEmpty ? $0.app : $0.title } ?? "Closed window")
                        .font(Typo.mono(9))
                        .foregroundColor(Palette.textDim)
                        .lineLimit(1)
                    Text([row?.app, reason.label].compactMap { $0 }.joined(separator: " · "))
                        .font(Typo.mono(8))
                        .foregroundColor(Palette.textMuted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if OverviewView.canShow(reason) {
                Button("Show") { model.showInScope(wid) }
                    .buttonStyle(.plain)
                    .font(Typo.monoBold(8))
                    .foregroundColor(Palette.textDim)
                    .accessibilityLabel("Show \(row?.app ?? "window") in scope")
            }
        }
    }

    /// Show in scope finds every window a scope can hold; Spaces can't place
    /// unknown ones, and closed ones are gone.
    static func canShow(_ reason: Exclusion) -> Bool {
        reason != .unknown && reason != .gone
    }

    private func errorText(_ text: String) -> some View {
        Text(text)
            .font(Typo.mono(8))
            .foregroundColor(Palette.kill)
            .fixedSize(horizontal: false, vertical: true)
    }

    static func reasons(_ reasons: [Exclusion]) -> String {
        var order: [Exclusion] = []
        var counts: [Exclusion: Int] = [:]
        for reason in reasons {
            if counts[reason] == nil { order.append(reason) }
            counts[reason, default: 0] += 1
        }
        return order.map { "\(counts[$0]!) \($0.label)" }.joined(separator: ", ")
    }

    private func windowDetail(_ row: OverviewRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.title.isEmpty ? row.app : row.title)
                .font(Typo.monoBold(10))
                .foregroundColor(Palette.text)
                .lineLimit(2)
            Text([row.app, row.state.label, row.position.label].compactMap { $0 }.joined(separator: " · "))
                .font(Typo.mono(8))
                .foregroundColor(Palette.textMuted)
            HStack(spacing: 8) {
                Button("Focus") { model.focus(row.wid) }
                    .disabled(row.state == .unknown)
                if let reason = model.projection.outOfScopeSelection.first(where: { $0.wid == row.wid })?.reason,
                   Self.canShow(reason) {
                    Button("Show in scope") { model.showInScope(row.wid) }
                }
            }
            .font(Typo.mono(9))
            directActions(row)
        }
    }

    private static let placements: [TilePosition] = [.left, .right, .maximize, .center]

    /// One window, in place: tile it on its monitor, or carry it to another
    /// desktop there. Each says why when it can't.
    @ViewBuilder
    private func directActions(_ row: OverviewRow) -> some View {
        let placeBlock = model.projection.placeExclusion(row.wid)
        HStack(spacing: 6) {
            ForEach(Self.placements) { position in
                Button(position.label) { model.place(row.wid, at: position) }
                    .disabled(placeBlock != nil)
            }
        }
        .font(Typo.mono(9))
        .help(placeBlock.map { "Can't tile: \($0.label)" } ?? "Tile this window on its monitor")

        let targets = model.projection.moveTargets(for: row.wid)
        if model.moving.contains(row.wid) {
            Text("Moving…").font(Typo.mono(8)).foregroundColor(Palette.textMuted)
        } else if !targets.isEmpty {
            Menu("Move to desktop") {
                ForEach(targets, id: \.spaceId) { target in
                    Button("Desktop \(target.desktop)") { model.move(row.wid, toSpace: target.spaceId) }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .font(Typo.mono(9))
            .help("Carries the window through Mission Control; takes a few seconds")
        } else if let block = OverviewProjection.moveExclusion(row) {
            Text("Can't move: \(block.label)").font(Typo.mono(8)).foregroundColor(Palette.textMuted)
        }
    }

    private var bulkActions: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach([OverviewBulkAction.tile, .distribute], id: \.self) { action in
                let plan = model.plan(action)
                Button(plan.label) { model.run(plan) }
                    .disabled(!plan.isEnabled)
                    .font(Typo.mono(9))
                    .help(plan.excludedSummary.isEmpty ? "" : "Left out: \(plan.excludedSummary)")
            }
        }
    }

    // MARK: Layer

    @ViewBuilder
    private func layerDetail(_ layer: LayerOverview) -> some View {
        let rows = model.projection.rows
        VStack(alignment: .leading, spacing: 8) {
            LayerOverviewDetail(
                overview: layer,
                selected: model.selection,
                tucked: rows.filter { $0.role == .tucked },
                unclaimed: rows.filter { $0.role == .unclaimed },
                onSelect: { model.select($0) }
            )
            if let edit = model.editing, edit.layerId == layer.id {
                layerEditor(edit, layer: layer)
            } else {
                // A rearrange fails after the draft closed; say so here.
                if let error = model.editError { errorText(error) }
                Button("Edit layer") { model.beginEditing(layer) }
                    .font(Typo.mono(9))
            }
        }
    }

    private static let layouts: [(label: String, value: String?)] = [
        ("In place", nil), ("Auto", "auto"), ("Columns", "columns"), ("Main and stack", "master-stack"),
    ]

    private func layerEditor(_ edit: LayerEdit, layer: LayerOverview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Layout", selection: Binding(
                get: { edit.layout ?? "" },
                set: { model.editing?.layout = $0.isEmpty ? nil : $0 }
            )) {
                ForEach(Self.layouts, id: \.label) { option in
                    Text(option.label).tag(option.value ?? "")
                }
            }
            .font(Typo.mono(9))

            ForEach(layer.entries.flatMap(\.windows)) { window in
                Toggle(isOn: Binding(
                    get: { model.editing?.tucked.contains(window.wid) ?? false },
                    set: { on in
                        if on { model.editing?.tucked.insert(window.wid) } else { model.editing?.tucked.remove(window.wid) }
                    }
                )) {
                    Text("Tuck \(window.title.isEmpty ? window.app : window.title)")
                        .font(Typo.mono(8))
                        .lineLimit(1)
                }
                .toggleStyle(.checkbox)
            }

            if let error = model.editError { errorText(error) }

            HStack(spacing: 8) {
                Button("Cancel") { model.cancelEditing() }
                Button("Save layer") { model.saveLayer() }
                    .disabled(!edit.hasChanges)
                    .help("Saves the layout and tucks. Doesn't move windows.")
                if model.canRearrange {
                    Button("Save and rearrange") { model.saveAndRearrange() }
                        .help("Saves, then lays out the active layer's windows again")
                }
            }
            .font(Typo.mono(9))
        }
    }
}
