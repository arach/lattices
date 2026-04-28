import SwiftUI

// MARK: - HUDLeftBar

struct HUDLeftBar: View {
    @ObservedObject var state: HUDState
    @ObservedObject private var scanner = ProjectScanner.shared
    @ObservedObject private var desktop = DesktopModel.shared
    @ObservedObject private var workspace = WorkspaceManager.shared
    @FocusState private var searchFieldFocused: Bool
    @State private var resizeStartWidth: CGFloat?
    @State private var isSearchHovered: Bool = false
    @State private var hoveredSectionKey: Int?
    @State private var hoveredItemID: String?
    @State private var hoveredLayerID: String?
    @State private var previewClearWorkItem: DispatchWorkItem?
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

    private var visibleItems: [HUDItem] {
        sections
            .filter { state.isSectionExpanded($0.key) }
            .flatMap(\.items)
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
            .sorted { lhs, rhs in
                let lhsDate = desktop.lastInteractionDate(for: lhs.wid) ?? .distantPast
                let rhsDate = desktop.lastInteractionDate(for: rhs.wid) ?? .distantPast
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
                return lhs.zIndex < rhs.zIndex
            }
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
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Palette.running)
                    Text("TILE MODE")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Palette.running)
                    Spacer()
                    Text("H/J/K/L to place · ⎋ done")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.42))
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
                    let items = visibleItems
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
        .background(Palette.bgSidebar)
        .overlay(alignment: .trailing) {
            resizeHandle
        }
        .onAppear { syncState() }
        .onChange(of: state.query) { _ in
            state.selectedIndex = 0
            syncState()
        }
        .onChange(of: state.expandedSections) { _ in
            syncState()
        }
        .onChange(of: state.focus) { focus in
            let shouldFocusSearch = focus == .search
            guard searchFieldFocused != shouldFocusSearch else { return }
            DispatchQueue.main.async {
                searchFieldFocused = shouldFocusSearch
            }
        }
        .onChange(of: searchFieldFocused) { isFocused in
            if isFocused {
                state.focus = .search
            } else if state.focus == .search {
                state.focus = .list
            }
        }
        .onReceive(scanner.objectWillChange) { _ in
            DispatchQueue.main.async { syncState() }
        }
        .onReceive(desktop.objectWillChange) { _ in
            DispatchQueue.main.async { syncState() }
        }
        .task {
            DispatchQueue.main.async {
                searchFieldFocused = state.focus == .search
            }
        }
    }

    /// Push flat items + section offsets to state so HUDController's key handler can use them
    private func syncState() {
        state.syncAutoSectionDefaults(hasRunningProjects: scanner.projects.contains(where: \.isRunning))
        let secs = sections
        var flat = [HUDItem]()
        var offsets = [Int: Int]()
        for sec in secs {
            guard state.isSectionExpanded(sec.key) else { continue }
            if !sec.items.isEmpty {
                offsets[sec.key] = flat.count
            }
            flat.append(contentsOf: sec.items)
        }
        state.flatItems = flat
        state.sectionOffsets = offsets
        state.reconcileSelection(with: flat)
    }

    private var resizeHandle: some View {
        ZStack {
            Color.clear
            VStack(spacing: 4) {
                Capsule()
                    .fill(Palette.borderLit.opacity(0.9))
                    .frame(width: 2, height: 28)
                Capsule()
                    .fill(Palette.border.opacity(0.9))
                    .frame(width: 2, height: 18)
            }
        }
        .frame(width: 10)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if resizeStartWidth == nil {
                        resizeStartWidth = state.leftSidebarWidth
                    }
                    let base = resizeStartWidth ?? state.leftSidebarWidth
                    state.setLeftSidebarWidth(base + value.translation.width)
                }
                .onEnded { _ in
                    resizeStartWidth = nil
                }
        )
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(state.focus == .search ? Palette.text : Palette.textMuted.opacity(0.85))

            ZStack(alignment: .leading) {
                if state.query.isEmpty {
                    Text(state.focus == .search ? "Type to search..." : "/ to search")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(Palette.textMuted)
                        .allowsHitTesting(false)
                }
                TextField("", text: $state.query)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Palette.text)
                    .textFieldStyle(.plain)
                    .focused($searchFieldFocused)
                    .onTapGesture {
                        state.focus = .search
                        searchFieldFocused = true
                    }
                    .onSubmit { activateSelected() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(searchBarBackground)
        .contentShape(Rectangle())
        .onTapGesture {
            state.focus = .search
            searchFieldFocused = true
        }
        .onHover { isHovering in
            isSearchHovered = isHovering
        }
    }

    // MARK: - Section

    @ViewBuilder
    private func sectionView(_ sec: SectionDef, proxy: ScrollViewProxy) -> some View {
        if !sec.items.isEmpty {
            let isExpanded = state.isSectionExpanded(sec.key)
            let isHovered = hoveredSectionKey == sec.key
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    state.toggleSection(sec.key)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(Palette.textMuted)
                            .frame(width: 10, alignment: .center)

                        Image(systemName: sec.icon)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Palette.textMuted)
                        Text(sec.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Palette.textMuted.opacity(0.9))
                        Text("\(sec.items.count)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Palette.textDim)
                        Spacer()
                        shortcutBadge("\(sec.key)")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isHovered ? Palette.surface.opacity(0.65) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onHover { isHovering in
                    hoveredSectionKey = isHovering ? sec.key : (hoveredSectionKey == sec.key ? nil : hoveredSectionKey)
                }

                if isExpanded {
                    ForEach(sec.items) { item in
                        itemRow(item)
                            .id(item.id)
                    }
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
        let subtitleText = subtitle(for: item)
        let isHovered = hoveredItemID == item.id
        let rowFill: Color = {
            if isTiled { return Palette.running.opacity(0.12) }
            if isMultiSelected { return Palette.surfaceHov.opacity(0.9) }
            if isSelected { return Palette.surfaceHov }
            if isHovered { return Palette.surface.opacity(0.92) }
            if state.selectedItem == item { return Palette.surface.opacity(0.8) }
            return Color.clear
        }()
        let rowStroke: Color = {
            if isTiled { return Palette.running.opacity(0.45) }
            if isMultiSelected { return Color.blue.opacity(0.25) }
            if isSelected { return Palette.borderLit }
            if isHovered { return Palette.border.opacity(0.9) }
            return Color.clear
        }()

        return Button {
            state.focus = .list
            guard let idx = visibleItems.firstIndex(of: item) else { return }

            let modifiers = NSEvent.modifierFlags.intersection([.shift, .command])
            if modifiers.contains(.shift) {
                state.selectRange(to: item, index: idx, in: visibleItems)
            } else if modifiers.contains(.command) {
                state.toggleSelection(item, index: idx, in: visibleItems)
            } else {
                state.selectSingle(item, index: idx)
                state.pinInspector(item, source: "row")
            }
        } label: {
            HStack(spacing: 10) {
                statusDot(for: item)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Palette.text)
                        .lineLimit(1)

                    if let subtitleText {
                        Text(subtitleText)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(Palette.textDim)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(rowFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(rowStroke, lineWidth: 0.5)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { isHovering in
            hoveredItemID = isHovering ? item.id : (hoveredItemID == item.id ? nil : hoveredItemID)
            if isHovering {
                previewClearWorkItem?.cancel()
                state.hoveredPreviewItem = item
                state.hoverPreviewAnchorScreenY = NSEvent.mouseLocation.y
                prefetchPreview(for: item)
            } else if state.hoveredPreviewItem == item {
                let hoveredItemID = item.id
                let clearWorkItem = DispatchWorkItem {
                    guard self.state.hoveredPreviewItem?.id == hoveredItemID,
                          !self.state.previewInteractionActive else { return }
                    self.state.hoveredPreviewItem = nil
                    self.state.hoverPreviewAnchorScreenY = nil
                }
                previewClearWorkItem = clearWorkItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: clearWorkItem)
            }
        }
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

    private func prefetchPreview(for item: HUDItem) {
        switch item {
        case .window(let window):
            WindowPreviewStore.shared.load(window: window)
        case .project(let project):
            guard project.isRunning,
                  let window = desktop.windowForSession(project.sessionName) else { return }
            WindowPreviewStore.shared.load(window: window)
        }
    }

    // MARK: - Layers section (at bottom)

    private func layersSection(_ layers: [Layer]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Palette.textMuted)
                Text("Layers")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Palette.textMuted.opacity(0.9))
                Text("\(layers.count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Palette.textDim)
                Spacer()
                shortcutBadge("[ ]")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            ForEach(Array(layers.enumerated()), id: \.element.id) { idx, layer in
                let isActive = idx == workspace.activeLayerIndex
                let counts = workspace.layerRunningCount(index: idx)
                let isHovered = hoveredLayerID == layer.id

                Button {
                    workspace.focusLayer(index: idx)
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(isActive ? Palette.running : Palette.textMuted.opacity(0.2))
                            .frame(width: 7, height: 7)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(layer.label)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(isActive ? Palette.text : Palette.textMuted)
                                .lineLimit(1)

                            Text("\(counts.running)/\(counts.total) projects")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(Palette.textDim)
                        }

                        Spacer()

                        Text("\(idx + 1)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
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
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(isActive ? Palette.running.opacity(0.06) : (isHovered ? Palette.surface.opacity(0.75) : Color.clear))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .strokeBorder(isActive ? Palette.running.opacity(0.2) : (isHovered ? Palette.border : Color.clear), lineWidth: 0.5)
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onHover { isHovering in
                    hoveredLayerID = isHovering ? layer.id : (hoveredLayerID == layer.id ? nil : hoveredLayerID)
                }
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
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Palette.textMuted)
                Text("Map")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Palette.textMuted.opacity(0.9))
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
                                            .font(.system(size: max(6, min(9, rh * 0.35)), weight: .semibold, design: .monospaced))
                                            .foregroundColor(appColor(win.app).opacity(isSelected ? 1.0 : 0.5))
                                    }
                                }
                            )
                            .frame(width: max(rw, 3), height: max(rh, 2))
                            .offset(x: rx, y: ry)
                            .onTapGesture {
                                state.focus = .list
                                if let flatIdx = visibleItems.firstIndex(of: .window(win)) {
                                    state.selectSingle(.window(win), index: flatIdx)
                                    state.pinnedItem = .window(win)
                                    state.hoveredPreviewItem = nil
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
        let selectedIDs = state.effectiveSelectionIDs
        let selectionCount = state.multiSelectionCount
        let selectedProjects = visibleItems.compactMap { item -> Project? in
            guard selectedIDs.contains(item.id), case .project(let project) = item else { return nil }
            return project
        }
        let selectedWindows = visibleItems.compactMap { item -> WindowEntry? in
            guard selectedIDs.contains(item.id), case .window(let window) = item else { return nil }
            return window
        }

        return HStack(spacing: 10) {
            if selectionCount > 1 {
                Text("\(selectionCount) selected")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.86))
                if !selectedWindows.isEmpty || !selectedProjects.isEmpty {
                    keyBadge("T", label: "Tile")
                }
                if !selectedProjects.isEmpty {
                    keyBadge("D", label: "Detach")
                } else if selectedWindows.count > 1 {
                    keyBadge("D", label: "Distrib")
                }
            }
            keyBadge("⇧↕", label: "Range")
            keyBadge("⌘", label: "Multi")
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
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
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
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
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
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Palette.textMuted)
        }
    }

    private func shortcutBadge(_ key: String) -> some View {
        Text(key)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundColor(Palette.textMuted)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Palette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Palette.border, lineWidth: 0.5)
                    )
            )
    }

    private var searchBarBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(
                state.focus == .search
                    ? Palette.surface.opacity(0.6)
                    : (isSearchHovered ? Palette.surface.opacity(0.3) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        state.focus == .search
                            ? Palette.borderLit
                            : (isSearchHovered ? Palette.border.opacity(0.85) : Color.clear),
                        lineWidth: 0.5
                    )
            )
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
            HandsOffSession.shared.playCachedCue(p.isRunning ? "Focused." : "Done.")
        case .window(let w):
            _ = WindowTiler.focusWindow(wid: w.wid, pid: w.pid)
            HandsOffSession.shared.playCachedCue("Focused.")
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
