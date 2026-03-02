import SwiftUI
import AppKit

// MARK: - Row Frame PreferenceKey

struct WindowRowFrameKey: PreferenceKey {
    static var defaultValue: [UInt32: CGRect] = [:]
    static func reduce(value: inout [UInt32: CGRect], nextValue: () -> [UInt32: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

// MARK: - Focus Ring Suppressor

private struct FocusRingSuppressor: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14, *) {
            content.focusEffectDisabled()
        } else {
            content
        }
    }
}

struct CommandModeView: View {
    @ObservedObject var state: CommandModeState
    @State private var eventMonitor: Any?
    @State private var mouseDownMonitor: Any?
    @State private var mouseDragMonitor: Any?
    @State private var mouseUpMonitor: Any?
    @State private var panelOriginY: CGFloat = 0
    @State private var hoveredWindowId: UInt32?
    @FocusState private var isSearchFieldFocused: Bool

    private var isDesktopInventory: Bool {
        state.phase == .desktopInventory
    }

    // Column widths for inventory table
    private static let sizeColW: CGFloat = 80
    private static let tileColW: CGFloat = 60

    private var displayColumnWidth: CGFloat {
        let count = CGFloat(max(1, state.filteredSnapshot?.displays.count ?? 1))
        let available = panelWidth - 32 - (count - 1) * 0.5
        return max(360, (available / count).rounded(.down))
    }

    private var panelWidth: CGFloat {
        if isDesktopInventory {
            let displayCount = max(1, state.filteredSnapshot?.displays.count ?? 1)
            let ideal = CGFloat(displayCount) * 480 + CGFloat(displayCount - 1) + 32
            let screenWidth = NSScreen.main?.visibleFrame.width ?? 1920
            return min(ideal, screenWidth * 0.92)
        }
        return 580
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            divider
            if isDesktopInventory && state.desktopMode == .gridPreview {
                gridPreviewContent
            } else if isDesktopInventory {
                desktopInventoryContent
            } else {
                inventoryGrid
            }
            divider
            chordFooter
        }
        .frame(width: panelWidth)
        .background(Palette.bg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.borderLit, lineWidth: 0.5)
        )
        .overlay(executingOverlay)
        .overlay(flashOverlay)
        .onAppear { installKeyHandler(); installMouseMonitors() }
        .onDisappear { removeKeyHandler(); removeMouseMonitors() }
        .onChange(of: state.desktopMode) { mode in
            CommandModeWindow.shared.panelWindow?.isMovableByWindowBackground = true
        }
        .animation(.easeInOut(duration: 0.2), value: isDesktopInventory)
        .modifier(FocusRingSuppressor())
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(isDesktopInventory ? "DESKTOP INVENTORY" : "COMMAND MODE")
                .font(Typo.monoBold(11))
                .foregroundColor(Palette.text)

            if isDesktopInventory {
                Button(action: { state.copyInventoryToClipboard() }) {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9))
                        Text("Copy")
                            .font(Typo.mono(9))
                    }
                    .foregroundColor(Palette.textDim)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Palette.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .strokeBorder(Palette.border, lineWidth: 0.5)
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if let layer = state.inventory.activeLayer {
                HStack(spacing: 4) {
                    Text("Layer: \(layer)")
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.running)

                    Text("[\(state.inventory.layerCount > 0 ? "\(WorkspaceManager.shared.activeLayerIndex + 1)/\(state.inventory.layerCount)" : "—")]")
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.textMuted)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Palette.running.opacity(0.10))
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { _ in
                    CommandModeWindow.shared.panelWindow?.performDrag(with: NSApp.currentEvent!)
                }
        )
    }

    // MARK: - Inventory Grid

    private var inventoryGrid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                let grouped = groupedItems
                if grouped.isEmpty {
                    emptyState
                } else {
                    ForEach(grouped, id: \.0) { section, items in
                        sectionHeader(section)
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            inventoryRow(item)
                        }
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .frame(minHeight: 160, maxHeight: 240)
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            Text("No sessions found")
                .font(Typo.mono(11))
                .foregroundColor(Palette.textMuted)
            Spacer()
        }
        .padding(.vertical, 24)
    }

    // MARK: - Desktop Inventory Content

    private var desktopInventoryContent: some View {
        VStack(spacing: 0) {
            if state.isSearching {
                searchBar
            } else {
                filterPillBar
            }
            divider

            ZStack {
                Group {
                    if let snapshot = state.filteredSnapshot, !snapshot.displays.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 0) {
                                let total = snapshot.displays.count
                                ForEach(Array(snapshot.displays.enumerated()), id: \.element.id) { idx, display in
                                    if idx > 0 {
                                        Rectangle()
                                            .fill(Palette.border)
                                            .frame(width: 0.5)
                                    }
                                    displayColumn(display, index: idx, total: total)
                                        .frame(width: displayColumnWidth)
                                }
                            }
                        }
                    } else {
                        desktopEmptyState
                    }
                }

                marqueeOverlay
            }
            .coordinateSpace(name: "inventoryPanel")
            .background(
                GeometryReader { geo in
                    Color.clear.onAppear {
                        panelOriginY = geo.frame(in: .global).origin.y
                    }
                    .onChange(of: geo.frame(in: .global).origin.y) { newY in
                        panelOriginY = newY
                    }
                }
            )
            .onPreferenceChange(WindowRowFrameKey.self) { frames in
                state.rowFrames = frames
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var filterPillBar: some View {
        HStack(spacing: 6) {
            ForEach(FilterPreset.allCases, id: \.rawValue) { preset in
                let isActive = state.activePreset == preset
                Button {
                    if isActive {
                        state.activePreset = nil
                    } else {
                        state.activePreset = preset
                        state.clearSelection()
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(preset.rawValue)
                            .font(Typo.mono(9))
                        if let idx = preset.keyIndex {
                            Text("\(idx)")
                                .font(Typo.mono(8))
                                .foregroundColor(isActive ? Palette.text.opacity(0.7) : Palette.textMuted)
                        }
                    }
                    .foregroundColor(isActive ? Palette.text : Palette.textDim)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isActive ? Palette.running.opacity(0.2) : Palette.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(isActive ? Palette.running.opacity(0.4) : Palette.border, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundColor(Palette.textDim)
            TextField("Search windows...", text: $state.searchQuery)
                .textFieldStyle(.plain)
                .font(Typo.mono(12))
                .foregroundColor(Palette.text)
                .focused($isSearchFieldFocused)
            if !state.searchQuery.isEmpty {
                Text("\(state.flatWindowList.count) matches")
                    .font(Typo.mono(9))
                    .foregroundColor(Palette.textMuted)
            }
            Button(action: { state.deactivateSearch() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Palette.textDim)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFieldFocused = true
            }
        }
    }

    private func displayColumn(_ display: DesktopInventorySnapshot.DisplayInfo, index: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            displayHeader(display, index: index, total: total)
            divider

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(display.spaces) { space in
                            spaceHeader(space, display: display)
                            columnHeaders
                            ForEach(space.apps) { appGroup in
                                appGroupRows(appGroup, dimmed: !space.isCurrent)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: state.selectedWindowIds) { newIds in
                    // Only scroll if the selected window is in this display
                    guard let id = newIds.first else { return }
                    let displayWindows = display.spaces.flatMap { $0.apps.flatMap { $0.windows } }
                    if displayWindows.contains(where: { $0.id == id }) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private var desktopEmptyState: some View {
        HStack {
            Spacer()
            if state.isSearching && !state.searchQuery.isEmpty {
                Text("No matches for \"\(state.searchQuery)\"")
                    .font(Typo.mono(11))
                    .foregroundColor(Palette.textMuted)
            } else {
                Text("No windows found")
                    .font(Typo.mono(11))
                    .foregroundColor(Palette.textMuted)
            }
            Spacer()
        }
        .padding(.vertical, 24)
    }

    private func positionLabel(index: Int, total: Int) -> String {
        if total == 2 { return index == 0 ? "Left" : "Right" }
        if total == 3 { return ["Left", "Center", "Right"][index] }
        return "\(index + 1) of \(total)"
    }

    private func displayHeader(_ display: DesktopInventorySnapshot.DisplayInfo, index: Int, total: Int) -> some View {
        HStack(spacing: 6) {
            Text(display.name)
                .font(Typo.monoBold(11))
                .foregroundColor(Palette.text)
            if display.isMain {
                Text("main")
                    .font(Typo.mono(8))
                    .foregroundColor(Palette.running.opacity(0.7))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Palette.running.opacity(0.10))
                    )
            }
            if total > 1 {
                Text(positionLabel(index: index, total: total))
                    .font(Typo.mono(9))
                    .foregroundColor(Palette.textDim)
            }
            Text("\(display.visibleFrame.w)×\(display.visibleFrame.h)")
                .font(Typo.mono(9))
                .foregroundColor(Palette.textDim)
            Spacer()
            Text("\(display.spaceCount) space\(display.spaceCount == 1 ? "" : "s")")
                .font(Typo.mono(9))
                .foregroundColor(Palette.textMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func spaceHeader(_ space: DesktopInventorySnapshot.SpaceGroup, display: DesktopInventorySnapshot.DisplayInfo) -> some View {
        HStack(spacing: 5) {
            Text("Space \(space.index)")
                .font(Typo.monoBold(10))
                .foregroundColor(space.isCurrent ? Palette.running : Palette.textDim)
            if space.isCurrent {
                Text("active")
                    .font(Typo.mono(8))
                    .foregroundColor(Palette.running.opacity(0.7))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Palette.running.opacity(0.10))
                    )
            }
            Spacer()
            let windowCount = space.apps.reduce(0) { $0 + $1.windows.count }
            Text("\(windowCount)")
                .font(Typo.mono(9))
                .foregroundColor(Palette.textMuted)
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            Text("APP / WINDOW")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("SIZE")
                .frame(width: Self.sizeColW, alignment: .leading)
            Text("TILE")
                .frame(width: Self.tileColW, alignment: .trailing)
        }
        .font(Typo.mono(9))
        .foregroundColor(Palette.textMuted)
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
    }

    private func appGroupRows(_ appGroup: DesktopInventorySnapshot.AppGroup, dimmed: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if appGroup.windows.count == 1, let win = appGroup.windows.first {
                inventoryRow(window: win, appLabel: appGroup.appName)
                if state.isSelected(win.id), let path = win.inventoryPath {
                    inventoryPathLabel(path)
                }
            } else {
                Text(appGroup.appName)
                    .font(Typo.monoBold(10))
                    .foregroundColor(dimmed ? Palette.textDim : Palette.text)
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                    .padding(.bottom, 1)
                ForEach(appGroup.windows) { win in
                    inventoryRow(window: win, indented: true)
                    if state.isSelected(win.id), let path = win.inventoryPath {
                        inventoryPathLabel(path)
                    }
                }
            }
        }
        .opacity(dimmed ? 0.6 : 1.0)
    }

    private func inventoryPathLabel(_ path: InventoryPath) -> some View {
        Text(path.description)
            .font(Typo.mono(8))
            .foregroundColor(Palette.textMuted)
            .padding(.horizontal, 28)
            .padding(.vertical, 2)
    }

    /// Unified inventory row — handles both single-app rows (with appLabel) and
    /// sub-rows under a multi-window app header (with indented).
    private func inventoryRow(
        window: DesktopInventorySnapshot.InventoryWindowInfo,
        appLabel: String? = nil,
        indented: Bool = false
    ) -> some View {
        let isSelected = state.isSelected(window.id)
        let isHovered = hoveredWindowId == window.id
        let isLattices = window.isLattices

        return HStack(spacing: 0) {
            HStack(spacing: 4) {
                if indented {
                    Spacer().frame(width: 8)
                }
                Text(isLattices ? "●" : "•")
                    .font(.system(size: 7))
                    .foregroundColor(isLattices ? Palette.running : (isSelected ? Palette.text : Palette.textDim))
                if let app = appLabel {
                    Text(app)
                        .font(Typo.monoBold(10))
                        .foregroundColor(isLattices ? Palette.running : Palette.text)
                }
                Text(windowTitle(window))
                    .font(Typo.mono(10))
                    .foregroundColor(
                        isLattices
                            ? Palette.running.opacity(appLabel != nil && !isSelected ? 0.7 : 1.0)
                            : (isSelected ? Palette.text : Palette.textDim)
                    )
                    .lineLimit(1)
                if isLattices, let session = window.latticesSession, appLabel == nil {
                    Text("[\(session)]")
                        .font(Typo.mono(9))
                        .foregroundColor(Palette.running.opacity(isSelected ? 1.0 : 0.6))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(sizeText(window.frame))
                .font(Typo.mono(10))
                .foregroundColor(isSelected ? Palette.text : Palette.textDim)
                .frame(width: Self.sizeColW, alignment: .leading)

            Text(window.tilePosition?.label ?? "\u{2014}")
                .font(Typo.mono(10))
                .foregroundColor(window.tilePosition != nil ? (isSelected ? Palette.text : Palette.textDim) : Palette.textMuted)
                .frame(width: Self.tileColW, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Palette.surface : (isHovered ? Palette.surface.opacity(0.5) : Color.clear))
                .padding(.horizontal, 6)
        )
        .overlay(
            isSelected ?
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Palette.borderLit, lineWidth: 0.5)
                    .padding(.horizontal, 6)
                : nil
        )
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: WindowRowFrameKey.self,
                    value: [window.id: geo.frame(in: .named("inventoryPanel"))]
                )
            }
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            WindowTiler.navigateToWindowById(wid: window.id, pid: window.pid)
        }
        .onTapGesture(count: 1) {
            let mods = NSEvent.modifierFlags
            if mods.contains(.shift) {
                state.selectRange(to: window.id)
            } else if mods.contains(.command) {
                state.toggleSelection(window.id)
            } else {
                state.selectSingle(window.id)
            }
        }
        .contextMenu { windowContextMenu(for: window) }
        .onHover { hovering in hoveredWindowId = hovering ? window.id : nil }
        .id(window.id)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func windowContextMenu(for window: DesktopInventorySnapshot.InventoryWindowInfo) -> some View {
        let multiSelected = state.selectedWindowIds.count > 1 && state.isSelected(window.id)
        let selCount = state.selectedWindowIds.count

        if multiSelected {
            // Multi-select context menu
            Button {
                state.showAndDistributeSelected()
            } label: {
                Label("Show & Distribute (\(selCount))", systemImage: "rectangle.3.group")
            }

            Button {
                state.showAllSelected()
            } label: {
                Label("Show All (\(selCount))", systemImage: "macwindow.on.rectangle")
            }

            Button {
                state.distributeSelected()
            } label: {
                Label("Distribute (\(selCount))", systemImage: "rectangle.split.3x1")
            }

            Divider()

            Button {
                state.focusAllSelected()
            } label: {
                Label("Focus All (\(selCount))", systemImage: "eye")
            }

            Button {
                state.highlightAllSelected()
            } label: {
                Label("Highlight All (\(selCount))", systemImage: "sparkle")
            }

            Divider()

            Menu("Tile All (\(selCount))") {
                ForEach(TilePosition.allCases) { tile in
                    Button {
                        let windows = state.flatWindowList.filter { state.selectedWindowIds.contains($0.id) }
                        for (i, win) in windows.enumerated() {
                            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.1) {
                                WindowTiler.tileWindowById(wid: win.id, pid: win.pid, to: tile)
                            }
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 + Double(windows.count) * 0.1) {
                            state.desktopSnapshot = nil
                        }
                    } label: {
                        Label(tile.label, systemImage: tile.icon)
                    }
                }
            }

            Divider()

            Button {
                state.clearSelection()
            } label: {
                Label("Deselect All", systemImage: "xmark.circle")
            }
        } else {
            // Single window context menu
            Button {
                WindowTiler.navigateToWindowById(wid: window.id, pid: window.pid)
            } label: {
                Label("Bring to Front", systemImage: "macwindow")
            }

            Button {
                WindowTiler.highlightWindowById(wid: window.id)
            } label: {
                Label("Highlight", systemImage: "sparkle")
            }

            Divider()

            Menu("Tile Window") {
                ForEach(TilePosition.allCases) { tile in
                    Button {
                        WindowTiler.tileWindowById(wid: window.id, pid: window.pid, to: tile)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            state.desktopSnapshot = nil
                        }
                    } label: {
                        Label(tile.label, systemImage: tile.icon)
                    }
                }
            }

            Divider()

            Button {
                let info: String
                if let path = window.inventoryPath {
                    info = path.description
                } else {
                    let app = window.appName ?? "Unknown"
                    let title = window.title.isEmpty ? "(untitled)" : window.title
                    info = "[\(app)] \(title) wid=\(window.id)"
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(info, forType: .string)
            } label: {
                Label("Copy Info", systemImage: "doc.on.doc")
            }
        }
    }

    private func windowTitle(_ window: DesktopInventorySnapshot.InventoryWindowInfo) -> String {
        let title = window.title
        if title.isEmpty { return "(untitled)" }
        if title.count > 30 {
            return String(title.prefix(27)) + "..."
        }
        return title
    }

    private func sizeText(_ frame: WindowFrame) -> String {
        "\(Int(frame.w))×\(Int(frame.h))"
    }

    /// Group items by their group label
    private var groupedItems: [(String, [CommandModeInventory.Item])] {
        var result: [(String, [CommandModeInventory.Item])] = []
        var seen = Set<String>()
        for item in state.inventory.items {
            if !seen.contains(item.group) {
                seen.insert(item.group)
                result.append((item.group, state.inventory.items.filter { $0.group == item.group }))
            }
        }
        return result
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Typo.mono(9))
            .foregroundColor(Palette.textMuted)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private func inventoryRow(_ item: CommandModeInventory.Item) -> some View {
        HStack(spacing: 0) {
            // Name
            Text(item.name)
                .font(Typo.mono(11))
                .foregroundColor(statusColor(item.status))
                .lineLimit(1)
                .frame(width: 160, alignment: .leading)

            // Pane count
            Text(item.paneCount > 0 ? "\(item.paneCount) pane\(item.paneCount == 1 ? "" : "s")" : "—")
                .font(Typo.mono(10))
                .foregroundColor(Palette.textDim)
                .frame(width: 70, alignment: .leading)

            // Status dot + label
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor(item.status))
                    .frame(width: 5, height: 5)
                Text(statusLabel(item.status))
                    .font(Typo.mono(10))
                    .foregroundColor(statusColor(item.status))
            }
            .frame(width: 80, alignment: .leading)

            // Tile hint
            Text(item.tileHint ?? "\u{2014}")
                .font(Typo.mono(10))
                .foregroundColor(Palette.textMuted)
                .frame(width: 60, alignment: .leading)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
    }

    private func statusColor(_ status: CommandModeInventory.Status) -> Color {
        switch status {
        case .running: return Palette.running
        case .attached: return Palette.running
        case .stopped: return Palette.textMuted
        }
    }

    private func statusLabel(_ status: CommandModeInventory.Status) -> String {
        switch status {
        case .running: return "running"
        case .attached: return "attached"
        case .stopped: return "stopped"
        }
    }

    // MARK: - Chord Footer

    private var chordFooter: some View {
        VStack(spacing: 4) {
            // Restore banner — shown when positions are saved
            if isDesktopInventory && state.savedPositions != nil {
                HStack(spacing: 10) {
                    Text("Layout changed")
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.text)
                    Spacer()
                    Button {
                        state.restorePositions()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 9))
                            Text("Restore")
                                .font(Typo.mono(9))
                        }
                        .foregroundColor(Palette.text)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Palette.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(Palette.border, lineWidth: 0.5)
                                )
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        state.discardSavedPositions()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9))
                            Text("Keep")
                                .font(Typo.mono(9))
                        }
                        .foregroundColor(Palette.running)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Palette.running.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(Palette.running.opacity(0.3), lineWidth: 0.5)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Palette.running.opacity(0.05))
                divider
            }

            if isDesktopInventory && state.desktopMode == .gridPreview {
                // Grid preview hints
                HStack(spacing: 12) {
                    chordHint(key: "↩", label: "apply layout")
                    chordHint(key: "s", label: "apply layout")
                    chordHint(key: "esc", label: "cancel")
                    Spacer()
                    let shape = state.gridPreviewShape
                    Text(shape.map(String.init).joined(separator: " + "))
                        .font(Typo.monoBold(9))
                        .foregroundColor(Palette.running)
                }
            } else if isDesktopInventory && state.isSearching {
                // Search mode hints
                HStack(spacing: 12) {
                    chordHint(key: "↩", label: "select & front")
                    chordHint(key: "⌘A", label: "select all")
                    chordHint(key: "⇧↑↓", label: "multi-select")
                    if !state.selectedWindowIds.isEmpty {
                        chordHint(key: "t", label: "tile")
                    }
                    chordHint(key: "esc", label: "exit search")
                    Spacer()
                    if state.selectedWindowIds.count > 1 {
                        Text("\(state.selectedWindowIds.count) selected")
                            .font(Typo.mono(9))
                            .foregroundColor(Palette.running)
                    }
                }
            } else if isDesktopInventory && state.desktopMode == .tiling {
                // Tiling sub-mode hints
                HStack(spacing: 12) {
                    if state.selectedWindowIds.count == 2 {
                        chordHint(key: "←→", label: "split L/R")
                    } else {
                        chordHint(key: "←", label: "left")
                        chordHint(key: "→", label: "right")
                    }
                    chordHint(key: "↑", label: "top")
                    chordHint(key: "↓", label: "bottom")
                    chordHint(key: "⇧↑", label: "max")
                    chordHint(key: "1-4", label: "quad")
                    chordHint(key: "5-7", label: "thirds")
                    chordHint(key: "c", label: "center")
                    if state.selectedWindowIds.count >= 2 {
                        chordHint(key: "d", label: "distribute")
                    }
                    chordHint(key: "esc", label: "back")
                    Spacer()
                    if state.selectedWindowIds.count > 1 {
                        Text("\(state.selectedWindowIds.count) windows")
                            .font(Typo.mono(9))
                            .foregroundColor(Palette.running)
                    }
                }
            } else if isDesktopInventory && state.selectedWindowIds.count > 1 {
                // Multi-selection active
                HStack(spacing: 12) {
                    chordHint(key: "s", label: "show")
                    chordHint(key: "↩", label: "front")
                    chordHint(key: "t", label: "tile")
                    chordHint(key: "f", label: "focus")
                    chordHint(key: "h", label: "highlight")
                    chordHint(key: "esc", label: "clear")
                    Spacer()
                    Text("\(state.selectedWindowIds.count) selected")
                        .font(Typo.mono(9))
                        .foregroundColor(Palette.running)
                }
            } else if isDesktopInventory && !state.selectedWindowIds.isEmpty {
                // Single selection active — browsing hints with direct shortcuts
                HStack(spacing: 12) {
                    chordHint(key: "s", label: "show")
                    chordHint(key: "↩", label: "front")
                    chordHint(key: "f", label: "focus+close")
                    chordHint(key: "t", label: "tile")
                    chordHint(key: "h", label: "highlight")
                    chordHint(key: "esc", label: "deselect")
                    Spacer()
                }
            } else if isDesktopInventory {
                // No selection — browsing hints
                HStack(spacing: 12) {
                    chordHint(key: "↑↓", label: "navigate")
                    chordHint(key: "←→", label: "display")
                    chordHint(key: "m", label: "map")
                    chordHint(key: "/", label: "search")
                    chordHint(key: "`", label: "chords")
                    chordHint(key: "esc", label: "back")
                    Spacer()
                }
            } else {
                // First row: action chords
                HStack(spacing: 12) {
                    chordHint(key: "`", label: "desktop")
                    ForEach(state.chords.prefix(3), id: \.key) { chord in
                        chordHint(key: chord.key, label: chord.label)
                    }
                    Spacer()
                }

                // Second row: layer chords + utility
                HStack(spacing: 12) {
                    ForEach(state.chords.dropFirst(3), id: \.key) { chord in
                        chordHint(key: chord.key, label: chord.label)
                    }
                    chordHint(key: "esc", label: "dismiss")
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Palette.surface.opacity(0.4))
    }

    private func chordHint(key: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(Typo.mono(9))
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

    private func actionButton(key: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(key)
                    .font(Typo.mono(9))
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
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.001))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    // MARK: - Executing Overlay

    @ViewBuilder
    private var executingOverlay: some View {
        if case .executing(let label) = state.phase {
            ZStack {
                Palette.bg.opacity(0.85)
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Palette.running)
                    Text(label)
                        .font(Typo.monoBold(13))
                        .foregroundColor(Palette.running)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .transition(.opacity)
        }
    }

    // MARK: - Flash Overlay

    @ViewBuilder
    private var flashOverlay: some View {
        if let msg = state.flashMessage {
            VStack {
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.3.group")
                        .font(.system(size: 11))
                    Text(msg)
                        .font(Typo.monoBold(11))
                }
                .foregroundColor(Palette.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Palette.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Palette.running.opacity(0.3), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
                )
                .padding(.bottom, 60)
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .animation(.easeOut(duration: 0.2), value: state.flashMessage)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Divider

    private var divider: some View {
        Rectangle()
            .fill(Palette.border)
            .frame(height: 0.5)
    }

    // MARK: - Grid Preview

    private var gridPreviewContent: some View {
        let windows = state.gridPreviewWindows
        let shape = state.gridPreviewShape
        let gridDesc = shape.map(String.init).joined(separator: " + ")

        return VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("LAYOUT PREVIEW")
                    .font(Typo.monoBold(10))
                    .foregroundColor(Palette.textDim)
                Text(gridDesc)
                    .font(Typo.monoBold(10))
                    .foregroundColor(Palette.running)
                Spacer()
                Text("\(windows.count) window\(windows.count == 1 ? "" : "s")")
                    .font(Typo.mono(9))
                    .foregroundColor(Palette.textMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            divider

            // Screen map: current positions (dimmed) + target grid (bright)
            screenMap(windows: windows, shape: shape)
                .frame(height: 160)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            divider

            // Grid cells with window details
            VStack(spacing: 2) {
                ForEach(Array(shape.enumerated()), id: \.offset) { rowIdx, colCount in
                    HStack(spacing: 2) {
                        ForEach(0..<colCount, id: \.self) { colIdx in
                            let idx = shape[0..<rowIdx].reduce(0, +) + colIdx
                            if idx < windows.count {
                                gridCell(windows[idx], index: idx + 1)
                            }
                        }
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }


    // MARK: - Grid Preview Screen Map

    /// Miniature proportional map of the screen showing current window positions and target grid slots
    private func screenMap(windows: [DesktopInventorySnapshot.InventoryWindowInfo], shape: [Int]) -> some View {
        GeometryReader { geo in
            let availW = geo.size.width
            let availH = geo.size.height

            // Get screen dimensions from snapshot
            let display = state.filteredSnapshot?.displays.first
            let screenW = CGFloat(display?.visibleFrame.w ?? 3440)
            let screenH = CGFloat(display?.visibleFrame.h ?? 1440)

            // Scale to fit
            let scaleX = availW / screenW
            let scaleY = availH / screenH
            let scale = min(scaleX, scaleY)
            let mapW = screenW * scale
            let mapH = screenH * scale
            let offsetX = (availW - mapW) / 2
            let offsetY = (availH - mapH) / 2

            ZStack(alignment: .topLeading) {
                // Screen background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Palette.bg.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Palette.border, lineWidth: 0.5)
                    )
                    .frame(width: mapW, height: mapH)

                // Current positions (dimmed)
                ForEach(Array(windows.enumerated()), id: \.element.id) { idx, win in
                    let f = win.frame
                    let x = CGFloat(f.x) * scale
                    let y = CGFloat(f.y) * scale
                    let w = max(CGFloat(f.w) * scale, 2)
                    let h = max(CGFloat(f.h) * scale, 2)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(Palette.textMuted.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .strokeBorder(Palette.textMuted.opacity(0.3), lineWidth: 0.5)
                        )
                        .frame(width: w, height: h)
                        .offset(x: x, y: y)
                }

                // Target grid slots (bright)
                let slots = computeMapSlots(count: windows.count, shape: shape, mapW: mapW, mapH: mapH)
                ForEach(Array(slots.enumerated()), id: \.offset) { idx, slot in
                    let win = idx < windows.count ? windows[idx] : nil
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Palette.running.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .strokeBorder(Palette.running.opacity(0.5), lineWidth: 1)
                        )
                        .overlay {
                            VStack(spacing: 1) {
                                Text("\(idx + 1)")
                                    .font(Typo.monoBold(9))
                                    .foregroundColor(Palette.running)
                                if let win = win {
                                    Text(win.appName ?? "")
                                        .font(Typo.mono(7))
                                        .foregroundColor(Palette.running.opacity(0.7))
                                        .lineLimit(1)
                                }
                            }
                        }
                        .frame(width: slot.width - 2, height: slot.height - 2)
                        .offset(x: slot.origin.x + 1, y: slot.origin.y + 1)
                }
            }
            .offset(x: offsetX, y: offsetY)
        }
    }

    /// Compute grid slots scaled to the mini map dimensions
    private func computeMapSlots(count: Int, shape: [Int], mapW: CGFloat, mapH: CGFloat) -> [CGRect] {
        let rowCount = shape.count
        let rowH = mapH / CGFloat(rowCount)
        var slots: [CGRect] = []
        for (row, cols) in shape.enumerated() {
            let colW = mapW / CGFloat(cols)
            let y = CGFloat(row) * rowH
            for col in 0..<cols {
                slots.append(CGRect(x: CGFloat(col) * colW, y: y, width: colW, height: rowH))
            }
        }
        return slots
    }

    private func gridCell(_ window: DesktopInventorySnapshot.InventoryWindowInfo, index: Int) -> some View {
        VStack(spacing: 3) {
            // App name
            Text(window.appName ?? "Unknown")
                .font(Typo.monoBold(10))
                .foregroundColor(window.isLattices ? Palette.running : Palette.text)
                .lineLimit(1)

            // Window title
            Text(windowTitle(window))
                .font(Typo.mono(9))
                .foregroundColor(Palette.textDim)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            // Size
            Text(sizeText(window.frame))
                .font(Typo.mono(8))
                .foregroundColor(Palette.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(window.isLattices ? Palette.running.opacity(0.3) : Palette.border, lineWidth: 0.5)
        )
        .overlay(alignment: .topLeading) {
            Text("\(index)")
                .font(Typo.mono(8))
                .foregroundColor(Palette.textMuted)
                .padding(4)
        }
    }

    // MARK: - Marquee Overlay

    @ViewBuilder
    private var marqueeOverlay: some View {
        if state.isDragging {
            let rect = state.marqueeRect
            Rectangle()
                .fill(Palette.running.opacity(0.08))
                .overlay(
                    Rectangle()
                        .strokeBorder(Palette.running.opacity(0.4), lineWidth: 1)
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Key Handler

    private func installKeyHandler() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard state.phase == .inventory || state.phase == .desktopInventory else { return event }
            let consumed = state.handleKey(event.keyCode, modifiers: event.modifierFlags)
            return consumed ? nil : event
        }
    }

    // MARK: - Mouse Monitors (marquee drag + screen map drag)

    private func installMouseMonitors() {
        let dragThreshold: CGFloat = 4

        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            guard let eventWindow = event.window,
                  eventWindow === CommandModeWindow.shared.panelWindow else { return event }
            guard state.phase == .desktopInventory else { return event }

            state.dragStartPoint = event.locationInWindow
            return event
        }

        mouseDragMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { event in
            guard state.phase == .desktopInventory else { return event }

            guard let startPt = state.dragStartPoint else { return event }

            let currentPt = event.locationInWindow

            if !state.isDragging {
                // Check threshold before starting drag
                let dx = currentPt.x - startPt.x
                let dy = currentPt.y - startPt.y
                let dist = sqrt(dx * dx + dy * dy)
                guard dist >= dragThreshold else { return event }

                // Convert NSEvent bottom-left → SwiftUI top-left in inventoryPanel space
                let additive = event.modifierFlags.contains(.command)
                let swiftUIStart = convertToPanel(startPt, event: event)
                state.beginDrag(at: swiftUIStart, additive: additive)
            }

            let swiftUICurrent = convertToPanel(currentPt, event: event)
            state.updateDrag(to: swiftUICurrent)

            return nil  // consume to prevent ScrollView scrolling during drag
        }

        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { event in
            if state.isDragging {
                state.endDrag()
            }
            state.dragStartPoint = nil
            return event
        }

    }



    /// Convert NSEvent window coordinates (bottom-left origin) to SwiftUI inventoryPanel coordinates (top-left origin)
    private func convertToPanel(_ windowPoint: NSPoint, event: NSEvent) -> CGPoint {
        guard let nsWindow = event.window else { return .zero }
        // Convert to screen coordinates
        let screenPoint = nsWindow.convertPoint(toScreen: windowPoint)
        // Convert to SwiftUI top-left: screen Y is bottom-up, SwiftUI Y is top-down
        let screenHeight = NSScreen.main?.frame.height ?? 0
        let flippedY = screenHeight - screenPoint.y
        // Subtract the panel's global origin to get panel-local coordinates
        let panelY = flippedY - panelOriginY
        // X is relative to window — we need global X minus panel X
        // For simplicity, use the window point X directly since the panel fills the window width
        return CGPoint(x: windowPoint.x, y: panelY)
    }

    /// Convert NSEvent to flipped window-local coordinates (Y=0 at top of window content)
    /// This matches SwiftUI GeometryReader's `.global` coordinate space inside NSHostingView
    private func flippedScreenPoint(_ event: NSEvent) -> CGPoint {
        guard let nsWindow = event.window else { return .zero }
        let loc = event.locationInWindow  // bottom-left origin
        let windowHeight = nsWindow.contentView?.frame.height ?? nsWindow.frame.height
        return CGPoint(x: loc.x, y: windowHeight - loc.y)
    }

    private func removeMouseMonitors() {
        if let m = mouseDownMonitor { NSEvent.removeMonitor(m); mouseDownMonitor = nil }
        if let m = mouseDragMonitor { NSEvent.removeMonitor(m); mouseDragMonitor = nil }
        if let m = mouseUpMonitor { NSEvent.removeMonitor(m); mouseUpMonitor = nil }
    }

    // Clear hover when leaving desktop inventory
    private func clearDesktopState() {
        hoveredWindowId = nil
    }

    private func removeKeyHandler() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

