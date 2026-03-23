import SwiftUI

// MARK: - HUDLeftBar

struct HUDLeftBar: View {
    @ObservedObject var state: HUDState
    @ObservedObject private var scanner = ProjectScanner.shared
    @ObservedObject private var desktop = DesktopModel.shared
    @ObservedObject private var workspace = WorkspaceManager.shared
    var onDismiss: () -> Void

    // Section definitions: (number key, title, icon, items builder)
    private struct SectionDef {
        let key: Int        // number-key jump
        let title: String
        let icon: String
        let items: [HUDItem]
    }

    private var sections: [SectionDef] {
        [
            SectionDef(key: 1, title: "Projects", icon: "folder.fill", items: filteredProjects.map { .project($0) }),
            SectionDef(key: 2, title: "Windows",  icon: "macwindow",   items: filteredWindows.map { .window($0) }),
        ]
    }

    /// Flat list for keyboard nav — also synced to state for key handler
    private var allItems: [HUDItem] {
        sections.flatMap(\.items)
    }

    // MARK: - Filters

    private var filteredProjects: [Project] {
        let q = state.query.lowercased()
        if q.isEmpty { return scanner.projects }
        return scanner.projects.filter {
            $0.name.lowercased().contains(q) ||
            $0.paneSummary.lowercased().contains(q)
        }
    }

    /// All desktop windows, sorted by z-order (front-to-back)
    /// Filters out: Lattices itself, windows with no title, and windows whose title is just the app name
    private var filteredWindows: [WindowEntry] {
        let q = state.query.lowercased()
        return desktop.allWindows()
            .filter { $0.app != "Lattices" }
            .filter { !$0.title.isEmpty }
            .filter { $0.title != $0.app } // skip helper windows titled "Cursor", "Codex", etc.
            .filter { q.isEmpty || $0.title.lowercased().contains(q) || $0.app.lowercased().contains(q) }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            searchBar

            Rectangle().fill(Palette.border).frame(height: 0.5)

            // Tile mode banner
            if state.tileMode {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.split.2x2")
                        .font(.system(size: 11))
                        .foregroundColor(Palette.running)
                    Text("TILE MODE")
                        .font(Typo.monoBold(10))
                        .foregroundColor(Palette.running)
                    Spacer()
                    Text("H/J/K/L to place · ⎋ done")
                        .font(Typo.mono(9))
                        .foregroundColor(Palette.textMuted)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Palette.running.opacity(0.08))

                Rectangle().fill(Palette.running.opacity(0.3)).frame(height: 0.5)
            }

            // Scrollable sections
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Sections
                        ForEach(sections, id: \.key) { sec in
                            sectionView(sec, proxy: proxy)
                        }

                        // Layers (at bottom, scroll to find)
                        if let layers = workspace.config?.layers, !layers.isEmpty {
                            layersSection(layers)
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 10)
                }
                .onChange(of: state.selectedIndex) { _ in
                    let items = allItems
                    if let item = items[safe: state.selectedIndex] {
                        proxy.scrollTo(item.id, anchor: .center)
                    }
                }
            }

            Rectangle().fill(Palette.border).frame(height: 0.5)

            // Minimap (pinned at bottom, docked mode only)
            if state.minimapMode == .docked {
                minimapDocked
            }

            Rectangle().fill(Palette.border).frame(height: 0.5)

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bg)
        .onAppear { syncState() }
        .onChange(of: state.query) { _ in
            state.selectedIndex = 0
            syncState()
        }
        .onReceive(desktop.objectWillChange) { _ in
            DispatchQueue.main.async { syncState() }
        }
    }

    /// Push flat items + section offsets to state so HUDController's key handler can use them
    private func syncState() {
        let secs = sections
        var flat = [HUDItem]()
        var offsets = [Int: Int]()
        for sec in secs {
            if !sec.items.isEmpty {
                offsets[sec.key] = flat.count
            }
            flat.append(contentsOf: sec.items)
        }
        state.flatItems = flat
        state.sectionOffsets = offsets

        // Keep selection in bounds
        if flat.isEmpty {
            state.selectedItem = nil
            state.selectedIndex = 0
        } else if state.selectedIndex >= flat.count {
            state.selectedIndex = flat.count - 1
            state.selectedItem = flat[state.selectedIndex]
        } else if state.selectedItem == nil {
            state.selectedItem = flat[safe: state.selectedIndex]
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundColor(state.focus == .search ? Palette.text : Palette.textMuted)

            ZStack(alignment: .leading) {
                if state.query.isEmpty {
                    Text(state.focus == .search ? "Type to search..." : "/ to search")
                        .font(Typo.mono(13))
                        .foregroundColor(Palette.textMuted)
                }
                if state.focus == .search {
                    TextField("", text: $state.query)
                        .font(Typo.mono(13))
                        .foregroundColor(Palette.text)
                        .textFieldStyle(.plain)
                        .onSubmit { activateSelected() }
                }
            }

            if !state.query.isEmpty {
                Button {
                    state.query = ""
                    state.selectedIndex = 0
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Palette.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(state.focus == .search ? Palette.surface.opacity(0.5) : Color.clear)
    }

    // MARK: - Section

    @ViewBuilder
    private func sectionView(_ sec: SectionDef, proxy: ScrollViewProxy) -> some View {
        if !sec.items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    // Number badge for section jumping
                    Text("\(sec.key)")
                        .font(Typo.geistMonoBold(8))
                        .foregroundColor(Palette.textMuted)
                        .frame(width: 14, height: 14)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(Palette.border, lineWidth: 0.5)
                        )
                    Image(systemName: sec.icon)
                        .font(.system(size: 10))
                        .foregroundColor(Palette.textMuted)
                    Text(sec.title)
                        .font(Typo.monoBold(10))
                        .foregroundColor(Palette.textMuted)
                        .textCase(.uppercase)
                    Text("\(sec.items.count)")
                        .font(Typo.mono(9))
                        .foregroundColor(Palette.textDim)
                }
                .padding(.horizontal, 6)

                ForEach(sec.items) { item in
                    itemRow(item)
                        .id(item.id)
                }
            }
        }
    }

    // MARK: - Item row

    private func itemRow(_ item: HUDItem) -> some View {
        let isSelected = state.selectedItem == item && state.focus == .list
        let isMultiSelected = state.selectedItems.contains(item.id)
        let isTiled = state.tileMode && {
            if case .window(let w) = item { return state.tiledWindows.contains(w.wid) }
            return false
        }()

        return Button {
            state.selectedItem = item
            state.focus = .list
            if let idx = allItems.firstIndex(of: item) {
                state.selectedIndex = idx
            }
        } label: {
            HStack(spacing: 10) {
                statusDot(for: item)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(Typo.monoBold(12))
                        .foregroundColor(Palette.text)
                        .lineLimit(1)

                    if let sub = subtitle(for: item) {
                        Text(sub)
                            .font(Typo.mono(10))
                            .foregroundColor(Palette.textDim)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isTiled ? Palette.running.opacity(0.1) :
                          isMultiSelected ? Color.blue.opacity(0.12) :
                          (isSelected ? Palette.surfaceHov : (state.selectedItem == item ? Palette.surface : Color.clear)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(isTiled ? Palette.running.opacity(0.4) :
                                          isMultiSelected ? Color.blue.opacity(0.4) :
                                          (isSelected ? Palette.borderLit : Color.clear), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func statusDot(for item: HUDItem) -> some View {
        Circle()
            .fill(dotColor(for: item))
            .frame(width: 7, height: 7)
    }

    private func dotColor(for item: HUDItem) -> Color {
        switch item {
        case .project(let p): return p.isRunning ? Palette.running : Palette.textMuted.opacity(0.3)
        case .window:         return Palette.textDim
        }
    }

    private func subtitle(for item: HUDItem) -> String? {
        switch item {
        case .project(let p):
            return p.paneSummary.isEmpty ? nil : p.paneSummary
        case .window(let w):
            return w.app
        }
    }

    // MARK: - Layers section (at bottom)

    private func layersSection(_ layers: [Layer]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 10))
                    .foregroundColor(Palette.textMuted)
                Text("Layers")
                    .font(Typo.monoBold(10))
                    .foregroundColor(Palette.textMuted)
                    .textCase(.uppercase)
                Text("\(layers.count)")
                    .font(Typo.mono(9))
                    .foregroundColor(Palette.textDim)
                Spacer()
                HStack(spacing: 2) {
                    Text("[")
                        .font(Typo.geistMonoBold(8))
                        .foregroundColor(Palette.textMuted)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 2)
                                .strokeBorder(Palette.border, lineWidth: 0.5)
                        )
                    Text("]")
                        .font(Typo.geistMonoBold(8))
                        .foregroundColor(Palette.textMuted)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 2)
                                .strokeBorder(Palette.border, lineWidth: 0.5)
                        )
                    Text("cycle")
                        .font(Typo.mono(8))
                        .foregroundColor(Palette.textDim)
                }
            }
            .padding(.horizontal, 6)

            ForEach(Array(layers.enumerated()), id: \.element.id) { idx, layer in
                let isActive = idx == workspace.activeLayerIndex
                let counts = workspace.layerRunningCount(index: idx)

                Button {
                    workspace.focusLayer(index: idx)
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(isActive ? Palette.running : Palette.textMuted.opacity(0.2))
                            .frame(width: 7, height: 7)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(layer.label)
                                .font(Typo.monoBold(12))
                                .foregroundColor(isActive ? Palette.text : Palette.textMuted)
                                .lineLimit(1)

                            Text("\(counts.running)/\(counts.total) projects")
                                .font(Typo.mono(10))
                                .foregroundColor(Palette.textDim)
                        }

                        Spacer()

                        Text("\(idx + 1)")
                            .font(Typo.geistMonoBold(9))
                            .foregroundColor(isActive ? Palette.text : Palette.textDim)
                            .frame(width: 18, height: 18)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(isActive ? Palette.running.opacity(0.15) : Palette.surface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .strokeBorder(isActive ? Palette.running.opacity(0.3) : Palette.border, lineWidth: 0.5)
                                    )
                            )
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isActive ? Palette.running.opacity(0.06) : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(isActive ? Palette.running.opacity(0.2) : Color.clear, lineWidth: 0.5)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Docked minimap

    private var minimapDocked: some View {
        let screens = NSScreen.screens
        let screen: NSScreen? = screens.isEmpty ? nil : screens.first
        let mapWidth: CGFloat = 300 // full sidebar width minus padding
        let mapHeight: CGFloat = 140

        return VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 0) {
                Image(systemName: "map")
                    .font(.system(size: 9))
                    .foregroundColor(Palette.textMuted)
                Text("Map")
                    .font(Typo.monoBold(9))
                    .foregroundColor(Palette.textMuted)
                    .padding(.leading, 4)

                Spacer()

                // Expand out to canvas
                Button {
                    state.minimapMode = .expanded
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Palette.textMuted)
                        .frame(width: 18, height: 18)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Palette.surface)
                        )
                }
                .buttonStyle(.plain)
                .help("Expand map (M)")

                // Hide
                Button {
                    state.minimapMode = .hidden
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Palette.textMuted)
                        .frame(width: 18, height: 18)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Palette.surface)
                        )
                }
                .buttonStyle(.plain)
                .help("Hide map (M)")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            // Map canvas
            if let screen {
                let sw = screen.frame.width
                let sh = screen.frame.height
                let scaleX = mapWidth / sw
                let scaleY = mapHeight / sh
                let scale = min(scaleX, scaleY)
                let drawW = sw * scale
                let drawH = sh * scale
                let offsetX = (mapWidth - drawW) / 2
                let offsetY = (mapHeight - drawH) / 2
                let origin = screenCGOrigin(screen)
                let wins = windowsOnScreen(0)

                ZStack(alignment: .topLeading) {
                    // Screen background
                    RoundedRectangle(cornerRadius: 4)
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

                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(appColor(win.app).opacity(isSelected ? 0.5 : 0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 1.5)
                                    .strokeBorder(
                                        isSelected ? Palette.running : appColor(win.app).opacity(0.35),
                                        lineWidth: isSelected ? 1.5 : 0.5
                                    )
                            )
                            .overlay(
                                Group {
                                    if rw > 24 && rh > 14 {
                                        Text(String(win.app.prefix(1)))
                                            .font(Typo.geistMonoBold(max(6, min(9, rh * 0.35))))
                                            .foregroundColor(appColor(win.app).opacity(isSelected ? 1.0 : 0.5))
                                    }
                                }
                            )
                            .frame(width: max(rw, 3), height: max(rh, 2))
                            .offset(x: rx, y: ry)
                            .onTapGesture {
                                state.selectedItem = .window(win)
                                state.focus = .list
                                if let flatIdx = allItems.firstIndex(of: .window(win)) {
                                    state.selectedIndex = flatIdx
                                }
                            }
                    }
                }
                .frame(width: mapWidth, height: mapHeight)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Minimap helpers

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

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if !state.selectedItems.isEmpty {
                Text("\(state.selectedItems.count) selected")
                    .font(Typo.monoBold(9))
                    .foregroundColor(Color.blue)
                keyBadge("T", label: "Tile")
            }
            keyBadge("⇧↕", label: "Select")
            keyBadge("⇥", label: "Focus")
            keyBadge("↵", label: "Go")
            keyBadge("[ ]", label: "Layer")

            Spacer()

            if state.minimapMode != .docked {
                Button {
                    state.minimapMode = .docked
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "map")
                            .font(.system(size: 8))
                        Text("M")
                            .font(Typo.geistMonoBold(8))
                    }
                    .foregroundColor(state.minimapMode == .expanded ? Palette.running : Palette.textMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Palette.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .strokeBorder(state.minimapMode == .expanded ? Palette.running.opacity(0.3) : Palette.border, lineWidth: 0.5)
                            )
                    )
                }
                .buttonStyle(.plain)
                .help("Dock map (M)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private func keyBadge(_ key: String, label: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(Typo.geistMonoBold(8))
                .foregroundColor(Palette.text)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Palette.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(Palette.border, lineWidth: 0.5)
                        )
                )
            Text(label)
                .font(Typo.mono(9))
                .foregroundColor(Palette.textMuted)
        }
    }

    // MARK: - Actions

    private func activateSelected() {
        guard let item = state.selectedItem else { return }
        activate(item)
    }

    private func activate(_ item: HUDItem) {
        switch item {
        case .project(let p):
            SessionManager.launch(project: p)
        case .window(let w):
            _ = WindowTiler.focusWindow(wid: w.wid, pid: w.pid)
        }
        onDismiss()
    }
}

// MARK: - Safe array subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
