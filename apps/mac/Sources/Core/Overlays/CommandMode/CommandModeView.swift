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

enum CommandModePresentation {
    case panel
    case embedded
}

struct CommandModeView: View {
    @ObservedObject var state: CommandModeState
    var presentation: CommandModePresentation = .panel
    @State private var eventMonitor: Any?
    @State private var mouseDownMonitor: Any?
    @State private var mouseDragMonitor: Any?
    @State private var mouseUpMonitor: Any?
    @State private var panelOriginY: CGFloat = 0
    @State private var panelOriginX: CGFloat = 0
    @State private var hoveredWindowId: UInt32?
    @FocusState private var isSearchFieldFocused: Bool

    private var isDesktopInventory: Bool {
        state.phase == .desktopInventory
    }

    private var isEmbedded: Bool {
        presentation == .embedded
    }

    // Column widths for inventory table
    private static let lastSeenColW: CGFloat = 60
    private static let sizeColW: CGFloat = 80
    private static let tileColW: CGFloat = 60

    var body: some View {
        GeometryReader { geo in
            let availableWidth = max(geo.size.width, 580)
            let contentWidth = resolvedContentWidth(in: availableWidth)

            Group {
                if isEmbedded && isDesktopInventory {
                    embeddedInventoryPage(contentWidth: contentWidth)
                } else {
                    inventoryCard(contentWidth: contentWidth)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isEmbedded ? .topLeading : .top)
        }
        .onAppear { installKeyHandler(); installMouseMonitors() }
        .onDisappear { removeKeyHandler(); removeMouseMonitors() }
        .onChange(of: state.desktopMode) { mode in
            CommandModeWindow.shared.panelWindow?.isMovableByWindowBackground = true
        }
        .animation(.easeInOut(duration: 0.2), value: isDesktopInventory)
        .modifier(FocusRingSuppressor())
    }

    private func resolvedContentWidth(in availableWidth: CGFloat) -> CGFloat {
        if isDesktopInventory {
            if isEmbedded {
                return min(max(availableWidth - 24, 840), 1560)
            }

            let displayCount = CGFloat(max(1, state.filteredSnapshot?.displays.count ?? 1))
            let ideal = displayCount * 480 + CGFloat(max(0, Int(displayCount) - 1)) + 32
            let screenWidth = NSScreen.main?.visibleFrame.width ?? availableWidth
            return min(ideal, screenWidth * 0.92)
        }

        if isEmbedded {
            return min(720, max(availableWidth - 32, 580))
        }
        return 580
    }

    private func displayColumnWidth(for contentWidth: CGFloat) -> CGFloat {
        let count = CGFloat(max(1, state.filteredSnapshot?.displays.count ?? 1))
        let available = contentWidth - 32 - (count - 1) * 0.5
        return max(isEmbedded ? 400 : 360, (available / count).rounded(.down))
    }

    private func inventoryCard(contentWidth: CGFloat) -> some View {
        // The tab bar already labels this view as "Desktop Inventory" in embedded mode,
        // so suppress the redundant in-card header there. Keep it in panel mode (where
        // the header doubles as the drag handle) and during the organize flow (where
        // it carries badges).
        let suppressHeader = isEmbedded && isDesktopInventory && !state.isOrganizeFlow

        return VStack(spacing: 0) {
            if !suppressHeader {
                header
                divider
            }
            if isDesktopInventory && state.desktopMode == .gridPreview {
                gridPreviewContent
            } else if isDesktopInventory {
                desktopInventoryContent(contentWidth: contentWidth)
            } else {
                inventoryGrid
            }
            if showsChordFooter {
                divider
                chordFooter
            }
        }
        .frame(width: contentWidth)
        .background(Palette.bg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.borderLit, lineWidth: 0.5)
        )
        .overlay(executingOverlay)
        .overlay(flashOverlay)
    }

    private func embeddedInventoryPage(contentWidth: CGFloat) -> some View {
        inventoryCard(contentWidth: contentWidth)
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(isDesktopInventory ? (state.isOrganizeFlow ? "ORGANIZE WINDOWS" : "DESKTOP INVENTORY") : "COMMAND MODE")
                .font(Typo.monoBold(11))
                .foregroundColor(Palette.text)

            if isDesktopInventory && state.isOrganizeFlow {
                bannerBadge("Current Space", tone: .neutral)
                if let appName = state.organizeSeedAppName, !appName.isEmpty {
                    bannerBadge(appName, tone: .accent)
                }
            }

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
                let items = state.inventory.items
                if items.isEmpty {
                    emptyState
                } else {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        inventoryRow(item)
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

    private func desktopInventoryContent(contentWidth: CGFloat) -> some View {
        Group {
            if isEmbedded {
                windowsPageContent
            } else {
                floatingPanelContent(contentWidth: contentWidth)
            }
        }
    }

    /// The Windows page (`AppPage.desktopInventory`, embedded in the app shell).
    /// Filters live in their own pane, an inspector pane stands in for the
    /// chord footer, and OCR matches render inline under their row instead of
    /// in a detached snippet list. See design/studio/.../shell/WindowsPanel.tsx
    /// and the "windows" exhibit's change ledger for the rationale.
    private var windowsPageContent: some View {
        VStack(spacing: 0) {
            if state.isOrganizeFlow {
                organizeBanner
                divider
            }

            HStack(spacing: 0) {
                filterSidebar
                Rectangle().fill(Palette.border).frame(width: 0.5)

                ZStack {
                    Group {
                        if let snapshot = state.filteredSnapshot, !snapshot.displays.isEmpty {
                            windowsMainList(snapshot: snapshot)
                        } else {
                            desktopEmptyState
                        }
                    }
                    marqueeOverlay
                }
                .coordinateSpace(name: "inventoryPanel")
                .background(inventoryPanelOriginTracker)
                .onPreferenceChange(WindowRowFrameKey.self) { frames in
                    state.rowFrames = frames
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Rectangle().fill(Palette.border).frame(width: 0.5)
                inspectorPane
            }
            .frame(maxHeight: .infinity)
        }
        .pageActions(windowsPageActions)
    }

    private var windowsPageActions: [PageAction] {
        [
            PageAction(id: "windows.copy", title: "Copy inventory", icon: "doc.on.doc") {
                state.copyInventoryToClipboard()
            },
            PageAction(
                id: "windows.tile",
                title: "Tile selection",
                icon: "rectangle.3.group",
                isPrimary: true,
                isEnabled: !state.selectedWindowIds.isEmpty
            ) {
                state.showAndDistributeSelected()
            },
        ]
    }

    /// The compact quick-access overlay (backtick toggle, `CommandModeWindow`).
    /// This keeps the original pill-filter + chord-footer layout — the Windows
    /// page redesign above targets the embedded `AppPage` surface, not this
    /// floating panel.
    private func floatingPanelContent(contentWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            if state.isOrganizeFlow {
                organizeBanner
                divider
            }

            if state.isSearching {
                searchBar
            } else {
                filterPillBar
            }
            divider

            ZStack {
                Group {
                    if let snapshot = state.filteredSnapshot, !snapshot.displays.isEmpty {
                        inventoryColumns(snapshot: snapshot, contentWidth: contentWidth)
                    } else {
                        desktopEmptyState
                    }
                }

                marqueeOverlay
            }
            .coordinateSpace(name: "inventoryPanel")
            .background(inventoryPanelOriginTracker)
            .onPreferenceChange(WindowRowFrameKey.self) { frames in
                state.rowFrames = frames
            }
            .frame(maxHeight: .infinity)
        }
    }

    /// Tracks the "inventoryPanel" coordinate space's global origin so mouse
    /// events (reported in window coordinates) can be converted to panel-local
    /// points for marquee selection. Shared by both layouts above.
    private var inventoryPanelOriginTracker: some View {
        GeometryReader { geo in
            Color.clear.onAppear {
                panelOriginY = geo.frame(in: .global).origin.y
                panelOriginX = geo.frame(in: .global).origin.x
            }
            .onChange(of: geo.frame(in: .global).origin.y) { newY in
                panelOriginY = newY
            }
            .onChange(of: geo.frame(in: .global).origin.x) { newX in
                panelOriginX = newX
            }
        }
    }

    private func inventoryColumns(snapshot: DesktopInventorySnapshot, contentWidth: CGFloat) -> some View {
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
                        .frame(width: displayColumnWidth(for: contentWidth))
                }
            }
        }
    }

    private var organizeBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Palette.running)
                Text(state.organizeSelectionSummary)
                    .font(Typo.monoBold(10))
                    .foregroundColor(Palette.text)
                Spacer()
                if state.selectedWindowIds.count > 1 {
                    bannerBadge("Ready", tone: .accent)
                } else {
                    bannerBadge("Add More", tone: .neutral)
                }
            }

            Text(state.organizeGuidance)
                .font(Typo.mono(10))
                .foregroundColor(Palette.textDim)
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Palette.running.opacity(0.06))
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
            inventoryStatsInline
            if isEmbedded {
                copyInventoryButton
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private var inventoryStatsInline: some View {
        let snapshot = state.filteredSnapshot ?? state.desktopSnapshot
        let displayCount = snapshot?.displays.count ?? 0
        let spaceCount = snapshot?.displays.reduce(0) { $0 + $1.spaces.count } ?? 0
        let windowCount = snapshot?.allWindows.count ?? 0

        return HStack(spacing: 10) {
            statInline(value: displayCount, label: "displays")
            statInline(value: spaceCount, label: "spaces")
            statInline(value: windowCount, label: "windows")
        }
    }

    private func statInline(value: Int, label: String) -> some View {
        HStack(spacing: 3) {
            Text("\(value)")
                .font(Typo.monoBold(10))
                .foregroundColor(Palette.text)
            Text(label)
                .font(Typo.mono(9))
                .foregroundColor(Palette.textMuted)
        }
    }

    private var copyInventoryButton: some View {
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
                RoundedRectangle(cornerRadius: 4)
                    .fill(Palette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Palette.border, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .help("Copy desktop inventory to clipboard")
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundColor(Palette.textDim)
            TextField("Search windows & content…", text: $state.searchQuery)
                .textFieldStyle(.plain)
                .font(Typo.mono(12))
                .foregroundColor(Palette.text)
                .focused($isSearchFieldFocused)
            if !state.searchQuery.isEmpty {
                let total = state.flatWindowList.count
                let ocrCount = state.ocrMatchSnippets.count
                Text(ocrCount > 0 ? "\(total) matches (\(ocrCount) by content)" : "\(total) matches")
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
                        if state.isFlatSorted {
                            columnHeaders
                            ForEach(state.sortedWindows(in: display)) { win in
                                inventoryRow(window: win, appLabel: win.appName)
                                ocrSnippetRow(for: win.id)
                                if state.isSelected(win.id), let path = win.inventoryPath {
                                    inventoryPathLabel(path)
                                }
                            }
                        } else {
                            ForEach(display.spaces) { space in
                                spaceHeader(space, display: display)
                                columnHeaders
                                ForEach(space.apps) { appGroup in
                                    appGroupRows(appGroup, dimmed: !space.isCurrent)
                                }
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
            Text(verbatim: "\(display.visibleFrame.w)×\(display.visibleFrame.h)")
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

    // MARK: - Windows Page — Filter Sidebar

    private static let filterSidebarWidth: CGFloat = 168
    private static let inspectorWidth: CGFloat = 248

    /// Displays, spaces, and apps as a scannable list with counts, instead of
    /// a pill strip fighting the toolbar for space.
    private var filterSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("FILTER")
                        .font(Typo.mono(8))
                        .foregroundColor(Palette.textMuted)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 2)

                    filterRow(.all, count: state.desktopSnapshot?.allWindows.count ?? 0)
                    ForEach(eligibleFilterPresets, id: \.rawValue) { preset in
                        filterRow(preset, count: presetCount(preset))
                    }
                }

                if let snapshot = state.desktopSnapshot, snapshot.displays.count > 1 {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("DISPLAYS")
                            .font(Typo.mono(8))
                            .foregroundColor(Palette.textMuted)
                            .padding(.horizontal, 8)
                            .padding(.bottom, 2)

                        ForEach(snapshot.displays) { display in
                            let count = display.spaces.reduce(0) { $0 + $1.apps.reduce(0) { $0 + $1.windows.count } }
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(display.isMain ? Palette.running : Palette.textMuted)
                                    .frame(width: 5, height: 5)
                                Text(display.name)
                                    .font(Typo.mono(10))
                                    .foregroundColor(Palette.textDim)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text("\(count)")
                                    .font(Typo.mono(9))
                                    .foregroundColor(Palette.textMuted)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                        }
                    }
                }

                if let snapshot = state.desktopSnapshot {
                    let allSpaces = snapshot.displays.flatMap(\.spaces)
                    if allSpaces.count > 1 {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("SPACES")
                                .font(Typo.mono(8))
                                .foregroundColor(Palette.textMuted)
                                .padding(.horizontal, 8)
                                .padding(.bottom, 2)

                            ForEach(allSpaces) { space in
                                let count = space.apps.reduce(0) { $0 + $1.windows.count }
                                HStack(spacing: 6) {
                                    Text("Space \(space.index)")
                                        .font(Typo.mono(10))
                                        .foregroundColor(space.isCurrent ? Palette.running : Palette.textDim)
                                    if space.isCurrent {
                                        Text("active")
                                            .font(Typo.mono(7))
                                            .foregroundColor(Palette.running.opacity(0.8))
                                            .padding(.horizontal, 3)
                                            .padding(.vertical, 1)
                                            .background(
                                                RoundedRectangle(cornerRadius: 2)
                                                    .fill(Palette.running.opacity(0.12))
                                            )
                                    }
                                    Spacer(minLength: 4)
                                    Text("\(count)")
                                        .font(Typo.mono(9))
                                        .foregroundColor(space.isCurrent ? Palette.text : Palette.textMuted)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                            }
                        }
                    }
                }
            }
            .padding(10)
        }
        .frame(width: Self.filterSidebarWidth)
        .background(Palette.surface.opacity(0.35))
    }

    /// Presets with at least one matching window earn a row.
    private var eligibleFilterPresets: [FilterPreset] {
        FilterPreset.allCases.filter { $0 != .all && presetCount($0) > 0 }
    }

    /// Counts are always against the full desktop, not the active filter —
    /// you should see the shape of the desktop before narrowing it.
    private func presetCount(_ preset: FilterPreset) -> Int {
        guard let snapshot = state.desktopSnapshot else { return 0 }
        switch preset {
        case .all:
            return snapshot.allWindows.count
        case .lattices:
            return snapshot.allWindows.filter(\.isLattices).count
        case .currentSpace:
            return snapshot.displays
                .flatMap { $0.spaces.filter(\.isCurrent) }
                .flatMap { $0.apps.flatMap(\.windows) }
                .count
        case .terminals, .editors, .browsers:
            guard let types = preset.appTypes else { return 0 }
            return snapshot.allWindows.filter { win in
                guard let name = win.appName else { return false }
                return types.contains(AppTypeClassifier.classify(name))
            }.count
        }
    }

    private func filterRow(_ preset: FilterPreset, count: Int) -> some View {
        let isActive = preset == .all ? state.activePreset == nil : state.activePreset == preset
        return Button {
            toggleFilter(preset)
        } label: {
            HStack(spacing: 6) {
                Text(preset.rawValue)
                    .font(Typo.mono(10))
                    .foregroundColor(isActive ? Palette.text : Palette.textDim)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)")
                    .font(Typo.mono(9))
                    .foregroundColor(isActive ? Palette.text.opacity(0.8) : Palette.textMuted)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isActive ? Palette.running.opacity(0.14) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleFilter(_ preset: FilterPreset) {
        if preset == .all {
            state.activePreset = nil
            return
        }
        if state.activePreset == preset {
            state.activePreset = nil
        } else {
            state.activePreset = preset
            state.clearSelection()
        }
    }

    // MARK: - Windows Page — Main List

    private func windowsMainList(snapshot: DesktopInventorySnapshot) -> some View {
        VStack(spacing: 0) {
            if state.isSearching {
                searchBar
                divider
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if state.isFlatSorted {
                            columnHeaders
                            ForEach(state.flatWindowList) { win in
                                inventoryRow(window: win, appLabel: win.appName)
                                ocrSnippetRow(for: win.id)
                                if state.isSelected(win.id), let path = win.inventoryPath {
                                    inventoryPathLabel(path)
                                }
                            }
                        } else {
                            columnHeaders
                            let populatedDisplays = snapshot.displays.filter { display in
                                display.spaces.contains { !$0.apps.isEmpty }
                            }
                            ForEach(populatedDisplays) { display in
                                if populatedDisplays.count > 1 {
                                    displayGroupHeader(display)
                                }
                                ForEach(display.spaces) { space in
                                    spaceHeader(space, display: display)
                                    ForEach(space.apps) { appGroup in
                                        appGroupRows(appGroup, dimmed: !space.isCurrent)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: state.selectedWindowIds) { newIds in
                    guard let id = newIds.first else { return }
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    /// Groups by display when more than one is present — the single-display
    /// case doesn't need a header repeating what's already implied.
    private func displayGroupHeader(_ display: DesktopInventorySnapshot.DisplayInfo) -> some View {
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
            Text(verbatim: "\(display.visibleFrame.w)×\(display.visibleFrame.h)")
                .font(Typo.mono(9))
                .foregroundColor(Palette.textDim)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    // MARK: - Windows Page — Inspector

    /// Stands in for the chord footer: selecting a window shows what Lattices
    /// knows about it beside the list, with the placement grid right there.
    /// The keyboard chords keep working — this just stops being the only way in.
    @ViewBuilder
    private var inspectorPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if state.selectedWindowIds.count > 1 {
                    inspectorMultiSelection
                } else if let window = inspectedWindow {
                    inspectorSingleWindow(window)
                } else {
                    inspectorEmptyState
                }
            }
            .padding(14)
        }
        .frame(width: Self.inspectorWidth)
        .background(Palette.surface.opacity(0.35))
    }

    private var inspectedWindow: DesktopInventorySnapshot.InventoryWindowInfo? {
        guard let id = state.selectedWindowId else { return nil }
        return state.flatWindowList.first { $0.id == id }
    }

    private var inspectorEmptyState: some View {
        VStack(spacing: 14) {
            Spacer().frame(height: 16)
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Palette.border, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .frame(width: 40, height: 40)
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 16))
                    .foregroundColor(Palette.textMuted)
            }
            VStack(spacing: 4) {
                Text("No Selection")
                    .font(Typo.monoBold(11))
                    .foregroundColor(Palette.textDim)
                Text("Select a window to inspect its frame, space, and placement.")
                    .font(Typo.mono(9))
                    .foregroundColor(Palette.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)

            Divider()
                .overlay(Palette.border)
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 6) {
                Text("KEYBOARD CONTROLS")
                    .font(Typo.mono(8))
                    .foregroundColor(Palette.textMuted)
                inspectorShortcutTip(key: "Double-click", label: "Focus window")
                inspectorShortcutTip(key: "Shift-click", label: "Range select")
                inspectorShortcutTip(key: "⌘-click", label: "Multi-select")
                inspectorShortcutTip(key: "⌘K", label: "Search")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func inspectorShortcutTip(key: String, label: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(Typo.mono(8))
                .foregroundColor(Palette.textDim)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Palette.surface)
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Palette.border, lineWidth: 0.5))
                )
            Text(label)
                .font(Typo.mono(9))
                .foregroundColor(Palette.textMuted)
            Spacer(minLength: 0)
        }
    }

    private func inspectorSingleWindow(_ window: DesktopInventorySnapshot.InventoryWindowInfo) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(window.isLattices ? Palette.running.opacity(0.25) : Palette.surfaceHov)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Text(String((window.appName ?? "?").prefix(1)).uppercased())
                            .font(Typo.monoBold(10))
                            .foregroundColor(window.isLattices ? Palette.running : Palette.textDim)
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(window.appName ?? "Unknown")
                        .font(Typo.monoBold(11))
                        .foregroundColor(window.isLattices ? Palette.running : Palette.text)
                    Text(windowTitle(window))
                        .font(Typo.mono(9))
                        .foregroundColor(Palette.textDim)
                        .lineLimit(2)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                if let display = displayName(for: window) {
                    inspectorMetric(label: "Display", value: display)
                }
                if let space = window.spaceIndex {
                    inspectorMetric(label: "Space", value: "\(space)")
                }
                inspectorMetric(
                    label: "Frame",
                    value: "\(Int(window.frame.x)),\(Int(window.frame.y))  \(sizeText(window.frame))"
                )
                inspectorMetric(label: "Tile", value: window.tilePosition?.label ?? "\u{2014}")
                inspectorMetric(label: "Session", value: window.latticesSession ?? "\u{2014}")
                inspectorMetric(label: "PID", value: "\(window.pid)")
            }

            inspectorPlacementGrid(current: window.tilePosition) { position in
                applyPlacement(position, to: window)
            }

            inspectorActions(for: window)
        }
    }

    private var inspectorMultiSelection: some View {
        let windows = state.flatWindowList.filter { state.selectedWindowIds.contains($0.id) }
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(windows.count) windows selected")
                    .font(Typo.monoBold(11))
                    .foregroundColor(Palette.text)
                if !state.selectedWindowSummaryText.isEmpty {
                    Text(state.selectedWindowSummaryText)
                        .font(Typo.mono(9))
                        .foregroundColor(Palette.textDim)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(windows.prefix(6)), id: \.id) { window in
                    HStack(spacing: 6) {
                        Text(window.appName ?? "Unknown")
                            .font(Typo.monoBold(9))
                            .foregroundColor(window.isLattices ? Palette.running : Palette.text)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(sizeText(window.frame))
                            .font(Typo.mono(9))
                            .foregroundColor(Palette.textMuted)
                    }
                }
                if windows.count > 6 {
                    Text("+\(windows.count - 6) more")
                        .font(Typo.mono(9))
                        .foregroundColor(Palette.textMuted)
                }
            }

            inspectorPlacementGrid(current: nil) { position in
                state.showAndDistributeSelected(in: .tile(position))
            }

            HStack(spacing: 6) {
                inspectorActionButton(icon: "eye", label: "Focus All") { state.focusAllSelected() }
                inspectorActionButton(icon: "sparkle", label: "Highlight") { state.highlightAllSelected() }
            }
        }
    }

    private func inspectorMetric(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label.uppercased())
                .font(Typo.mono(8))
                .foregroundColor(Palette.textMuted)
                .frame(width: 52, alignment: .leading)
            Text(value)
                .font(Typo.mono(9))
                .foregroundColor(Palette.text)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    private func displayName(for window: DesktopInventorySnapshot.InventoryWindowInfo) -> String? {
        state.filteredSnapshot?.displays.first { display in
            display.spaces.contains { $0.apps.contains { $0.windows.contains { $0.id == window.id } } }
        }?.name
    }

    /// The 3×3 "Move to" grid — the same primary positions the desktop
    /// inventory's tiling mode and context menu already offer.
    private static let placementGrid: [[TilePosition]] = [
        [.topLeft, .top, .topRight],
        [.left, .center, .right],
        [.bottomLeft, .bottom, .bottomRight],
    ]

    private func inspectorPlacementGrid(
        current: TilePosition?,
        apply: @escaping (TilePosition) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MOVE TO")
                .font(Typo.mono(9))
                .foregroundColor(Palette.textMuted)
            VStack(spacing: 3) {
                ForEach(Array(Self.placementGrid.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 3) {
                        ForEach(row) { position in
                            placementCell(position, isActive: current == position) {
                                apply(position)
                            }
                        }
                    }
                }
            }
        }
    }

    private func placementCell(_ position: TilePosition, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 3)
                .fill(isActive ? Palette.running.opacity(0.22) : Palette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(isActive ? Palette.running.opacity(0.55) : Palette.border, lineWidth: 0.5)
                )
                .frame(width: 26, height: 20)
        }
        .buttonStyle(.plain)
        .help(position.label)
    }

    /// Single-window placement goes straight through `WindowTiler`, matching
    /// the row context menu's "Tile Window" submenu.
    private func applyPlacement(_ position: TilePosition, to window: DesktopInventorySnapshot.InventoryWindowInfo) {
        WindowTiler.tileWindowById(wid: window.id, pid: window.pid, to: position)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            state.refreshDesktopInventory()
        }
    }

    private func inspectorActions(for window: DesktopInventorySnapshot.InventoryWindowInfo) -> some View {
        HStack(spacing: 6) {
            inspectorActionButton(icon: "eye", label: "Focus") {
                WindowTiler.navigateToWindowById(wid: window.id, pid: window.pid)
            }
            inspectorActionButton(icon: "sparkle", label: "Highlight") {
                WindowTiler.highlightWindowById(wid: window.id)
            }
        }
    }

    private func inspectorActionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9))
                Text(label).font(Typo.mono(9))
            }
            .foregroundColor(Palette.textDim)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Palette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Palette.border, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func spaceHeader(_ space: DesktopInventorySnapshot.SpaceGroup, display: DesktopInventorySnapshot.DisplayInfo) -> some View {
        HStack(spacing: 5) {
            Text("Space \(space.index)")
                .font(Typo.monoBold(10))
                .foregroundColor(space.isCurrent ? Palette.running : Palette.textDim)
            if space.isCurrent {
                Text("active")
                    .font(Typo.mono(8))
                    .foregroundColor(Palette.running.opacity(0.8))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Palette.running.opacity(0.12))
                    )
            }
            let windowCount = space.apps.reduce(0) { $0 + $1.windows.count }
            Text("· \(windowCount) window\(windowCount == 1 ? "" : "s")")
                .font(Typo.mono(9))
                .foregroundColor(Palette.textMuted)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 3)
    }

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            sortableHeader(.app, title: "APP / WINDOW")
                .frame(maxWidth: .infinity, alignment: .leading)
            sortableHeader(.lastSeen, title: "LAST SEEN", alignTrailing: true)
                .frame(width: Self.lastSeenColW, alignment: .trailing)
            sortableHeader(.size, title: "SIZE", alignTrailing: true)
                .frame(width: Self.sizeColW, alignment: .trailing)
                .padding(.leading, 8)
            sortableHeader(.tile, title: "TILE", alignTrailing: true)
                .frame(width: Self.tileColW, alignment: .trailing)
        }
        .font(Typo.mono(9))
        .foregroundColor(Palette.textMuted)
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
    }

    /// Clickable column header that sorts the table by `field`. Active column shows
    /// a direction indicator and brighter text; click again to flip direction; click
    /// a third time on the same column to return to grouped view.
    private func sortableHeader(
        _ field: InventorySortField,
        title: String,
        alignTrailing: Bool = false
    ) -> some View {
        let isActive = state.sortField == field
        let directionIcon = state.sortDirection == .asc ? "arrow.up" : "arrow.down"
        return Button {
            state.toggleSort(field)
        } label: {
            HStack(spacing: 3) {
                if alignTrailing { Spacer(minLength: 0) }
                Text(title)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if isActive {
                    Image(systemName: directionIcon)
                        .font(.system(size: 8))
                }
                if !alignTrailing { Spacer(minLength: 0) }
            }
            .foregroundColor(isActive ? Palette.text : Palette.textMuted)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Sort by \(title.lowercased())")
    }

    /// Compact relative-time label for a window's last interaction.
    /// "now", "12s", "3m", "1h", "2d", or a dash if never tracked this session.
    private func lastSeenText(for windowId: UInt32) -> String {
        guard let date = DesktopModel.shared.lastInteractionDate(for: windowId) else { return "\u{2014}" }
        let ago = Date().timeIntervalSince(date)
        if ago < 5 { return "now" }
        if ago < 60 { return "\(Int(ago))s" }
        if ago < 3_600 { return "\(Int(ago / 60))m" }
        if ago < 86_400 { return "\(Int(ago / 3_600))h" }
        return "\(Int(ago / 86_400))d"
    }

    /// Color emphasis for recency: brighter for fresh activity, dim for old.
    private func lastSeenColor(for windowId: UInt32, isSelected: Bool) -> Color {
        guard let date = DesktopModel.shared.lastInteractionDate(for: windowId) else {
            return Palette.textMuted
        }
        let ago = Date().timeIntervalSince(date)
        if ago < 300 { return Palette.running }   // < 5m: green
        if ago < 3_600 { return Palette.text }    // < 1h: bright
        if isSelected { return Palette.text }
        return Palette.textDim
    }

    private func appGroupRows(_ appGroup: DesktopInventorySnapshot.AppGroup, dimmed: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if appGroup.windows.count == 1, let win = appGroup.windows.first {
                inventoryRow(window: win, appLabel: appGroup.appName)
                ocrSnippetRow(for: win.id)
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
                    inventoryRow(window: win, appLabel: appGroup.appName, indented: true)
                    ocrSnippetRow(for: win.id)
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

    @ViewBuilder
    private func ocrSnippetRow(for windowId: UInt32) -> some View {
        if let snippet = state.ocrMatchSnippets[windowId] {
            HStack(spacing: 4) {
                Image(systemName: "text.magnifyingglass")
                    .font(.system(size: 7))
                    .foregroundColor(Palette.textMuted)
                Text(snippet)
                    .font(Typo.mono(9).italic())
                    .foregroundColor(Palette.textMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 1)
        }
    }

    private func cleanedWindowTitle(_ title: String, appName: String?, indented: Bool = false) -> String {
        guard let app = appName, !app.isEmpty else { return title.isEmpty ? "(untitled)" : title }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty { return "(untitled)" }
        // Case 1: Exact match "Activity Monitor" == "Activity Monitor"
        if trimmedTitle.caseInsensitiveCompare(app) == .orderedSame {
            return indented ? trimmedTitle : ""
        }
        // Case 2: Prefixed with app name e.g. "Tailscale Launch Failure" with app "Tailscale"
        if trimmedTitle.lowercased().hasPrefix(app.lowercased()) {
            var remainder = String(trimmedTitle.dropFirst(app.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if remainder.hasPrefix("—") || remainder.hasPrefix("-") || remainder.hasPrefix(":") || remainder.hasPrefix("·") {
                remainder = String(remainder.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !remainder.isEmpty {
                return remainder
            }
        }
        return trimmedTitle
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
                Group {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Palette.running)
                    } else {
                        Circle()
                            .fill(isLattices ? Palette.running : Palette.textDim.opacity(0.6))
                            .frame(width: 4, height: 4)
                            .padding(.horizontal, 2)
                    }
                }
                if let app = appLabel, !indented {
                    Text(app)
                        .font(Typo.monoBold(10))
                        .foregroundColor(isLattices ? Palette.running : Palette.text)
                }
                let cleanTitle = cleanedWindowTitle(windowTitle(window), appName: appLabel ?? window.appName, indented: indented)
                if !cleanTitle.isEmpty {
                    Text(cleanTitle)
                        .font(Typo.mono(10))
                        .foregroundColor(
                            isLattices
                                ? Palette.running.opacity(appLabel != nil && !isSelected && !indented ? 0.7 : 1.0)
                                : (isSelected ? Palette.text : Palette.textDim)
                        )
                        .lineLimit(1)
                }
                if isLattices, let session = window.latticesSession, appLabel == nil {
                    Text("[\(session)]")
                        .font(Typo.mono(9))
                        .foregroundColor(Palette.running.opacity(isSelected ? 1.0 : 0.6))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(lastSeenText(for: window.id))
                .font(Typo.mono(10))
                .foregroundColor(lastSeenColor(for: window.id, isSelected: isSelected))
                .frame(width: Self.lastSeenColW, alignment: .trailing)

            Text(sizeText(window.frame))
                .font(Typo.mono(10))
                .foregroundColor(isSelected ? Palette.text : Palette.textDim)
                .frame(width: Self.sizeColW, alignment: .trailing)
                .padding(.leading, 8)

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
        let moveTargets = WindowMoveMenuModel.resolveTargets(
            clicked: .init(wid: window.id, pid: window.pid),
            selection: selectedWindows.map { .init(wid: $0.id, pid: $0.pid) }
        )
        let moveModel = WindowMovementService.menuModel(windowFrame: window.frame, targets: moveTargets)

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

            if moveModel.isAvailable {
                Divider()

                WindowMovementMenuSection(
                    model: moveModel,
                    onMove: { display in moveSelection(moveModel.targets, to: display) }
                )
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

            ForEach(ArrangeLayout.allCases) { layout in
                Button {
                    state.arrangeSelected(as: layout)
                } label: {
                    Label("Arrange as \(layout.label) (\(selCount))", systemImage: layout.icon)
                }
                .disabled(!layout.supports(count: selCount))
            }

            Divider()

            Menu("Tile All (\(selCount))") {
                ForEach(TilePosition.allCases) { tile in
                    Button {
                        state.showAndDistributeSelected(in: .tile(tile))
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

            if moveModel.isAvailable {
                WindowMovementMenuSection(
                    model: moveModel,
                    onMove: { display in moveSelection(moveModel.targets, to: display) },
                    onPlace: { display, slot in placeWindow(moveModel.targets, on: display, slot: slot) }
                )

                Divider()
            }

            Menu("Tile Window") {
                ForEach(TilePosition.allCases) { tile in
                    Button {
                        WindowTiler.tileWindowById(wid: window.id, pid: window.pid, to: tile)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            state.refreshDesktopInventory()
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

    /// Immediate cross-monitor move through the canonical `window.move`
    /// engine; flashes a truthful receipt and refreshes the inventory while
    /// the selection (tracked by wid) survives the reload.
    private func moveSelection(_ targets: [WindowMoveMenuModel.Target], to display: WindowMoveMenuModel.Display) {
        WindowMovementService.moveTargets(targets, to: display) { outcome in
            state.flash(outcome.message)
            state.refreshDesktopInventory()
        }
    }

    private func placeWindow(_ targets: [WindowMoveMenuModel.Target], on display: WindowMoveMenuModel.Display, slot: TilePosition) {
        guard let target = targets.first else { return }
        WindowMovementService.placeTarget(target, on: display, slot: slot) { outcome in
            state.flash(outcome.message)
            state.refreshDesktopInventory()
        }
    }

    private func windowTitle(_ window: DesktopInventorySnapshot.InventoryWindowInfo) -> String {
        let title = window.title
        if title.isEmpty { return "(untitled)" }
        return title
    }

    private func sizeText(_ frame: WindowFrame) -> String {
        "\(Int(frame.w))×\(Int(frame.h))"
    }

    private var selectedWindows: [DesktopInventorySnapshot.InventoryWindowInfo] {
        state.flatWindowList.filter { state.selectedWindowIds.contains($0.id) }
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

    /// The Windows page replaces the browsing-mode chord legend with the
    /// inspector pane; the floating quick-access panel, the session chord
    /// view, and the transient tiling/grid-preview modes still need it. The
    /// restore banner is functional (not a hint legend), so it always shows.
    private var showsChordFooter: Bool {
        if state.savedPositions != nil { return true }
        if isEmbedded && isDesktopInventory && state.desktopMode == .browsing { return false }
        return true
    }

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

            if isEmbedded && isDesktopInventory && state.desktopMode == .browsing {
                // Windows page: the inspector pane covers browsing-mode
                // discoverability now — nothing else to say here.
                EmptyView()
            } else if isDesktopInventory && state.desktopMode == .gridPreview {
                // Grid preview hints
                HStack(spacing: 12) {
                    chordHint(key: "←→↑↓", label: "region")
                    chordHint(key: "1-7", label: "corners/thirds")
                    chordHint(key: "c", label: "center")
                    chordHint(key: "↩", label: "apply layout")
                    chordHint(key: "s", label: "apply layout")
                    chordHint(key: "esc", label: "cancel")
                    Spacer()
                    Text(state.gridPreviewRegionLabel.uppercased())
                        .font(Typo.mono(9))
                        .foregroundColor(Palette.textDim)
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
                    if state.isOrganizeFlow && state.selectedWindowIds.count > 1 {
                        chordHint(key: "d", label: "organize")
                    }
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
            } else if isDesktopInventory && state.isOrganizeFlow && state.selectedWindowIds.count > 1 {
                HStack(spacing: 12) {
                    chordHint(key: "d", label: "organize")
                    chordHint(key: "⌘-click", label: "add/remove")
                    chordHint(key: "⇧-click", label: "range")
                    chordHint(key: "↩", label: "front")
                    chordHint(key: "esc", label: "cancel")
                    Spacer()
                    Text("\(state.selectedWindowIds.count) selected")
                        .font(Typo.mono(9))
                        .foregroundColor(Palette.running)
                }
            } else if isDesktopInventory && state.isOrganizeFlow && !state.selectedWindowIds.isEmpty {
                HStack(spacing: 12) {
                    chordHint(key: "⌘-click", label: "add more")
                    chordHint(key: "d", label: "need 2+")
                    chordHint(key: "↩", label: "front")
                    chordHint(key: "esc", label: "cancel")
                    Spacer()
                    Text(state.organizeSelectionSummary)
                        .font(Typo.mono(9))
                        .foregroundColor(Palette.textDim)
                }
            } else if isDesktopInventory && state.isOrganizeFlow {
                HStack(spacing: 12) {
                    chordHint(key: "click", label: "select")
                    chordHint(key: "⌘-click", label: "add/remove")
                    chordHint(key: "/", label: "search")
                    chordHint(key: "esc", label: "cancel")
                    Spacer()
                }
            } else if isDesktopInventory && state.selectedWindowIds.count > 1 {
                // Multi-selection active
                HStack(spacing: 12) {
                    chordHint(key: "s", label: "grid preview")
                    chordHint(key: "d", label: "distribute")
                    chordHint(key: "s", label: "grid preview")
                    chordHint(key: "↩", label: "front")
                    chordHint(key: "t", label: "grid region")
                    chordHint(key: "f", label: "focus")
                    chordHint(key: "h", label: "highlight")
                    chordHint(key: "esc", label: "clear")
                    Spacer()
                    if !state.selectedWindowSummaryText.isEmpty {
                        Text(state.selectedWindowSummaryText)
                            .font(Typo.mono(9))
                            .foregroundColor(Palette.textDim)
                            .lineLimit(1)
                    }
                    Text("\(state.selectedWindowIds.count) selected")
                        .font(Typo.mono(9))
                        .foregroundColor(Palette.running)
                }
            } else if isDesktopInventory && !state.selectedWindowIds.isEmpty {
                // Single selection active — browsing hints with direct shortcuts
                HStack(spacing: 12) {
                    chordHint(key: "d", label: "organize")
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

    private enum BannerTone {
        case neutral
        case accent
    }

    private func bannerBadge(_ text: String, tone: BannerTone) -> some View {
        let foreground = tone == .accent ? Palette.running : Palette.textDim
        let fill = tone == .accent ? Palette.running.opacity(0.10) : Palette.surface
        let stroke = tone == .accent ? Palette.running.opacity(0.30) : Palette.border

        return Text(text)
            .font(Typo.mono(8))
            .foregroundColor(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(stroke, lineWidth: 0.5)
                    )
            )
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
                Text(state.gridPreviewRegionLabel.uppercased())
                    .font(Typo.mono(9))
                    .foregroundColor(Palette.textMuted)
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
            screenMap(windows: windows, shape: shape, placement: state.gridPreviewPlacement)
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
    private func screenMap(
        windows: [DesktopInventorySnapshot.InventoryWindowInfo],
        shape: [Int],
        placement: PlacementSpec?
    ) -> some View {
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

                if let placement {
                    let region = placement.fractions
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Palette.running.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                        .frame(width: mapW * region.2, height: mapH * region.3)
                        .offset(x: mapW * region.0, y: mapH * region.1)
                }

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
                let slots = computeMapSlots(
                    count: windows.count,
                    shape: shape,
                    mapW: mapW,
                    mapH: mapH,
                    region: placement?.fractions
                )
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
    private func computeMapSlots(
        count: Int,
        shape: [Int],
        mapW: CGFloat,
        mapH: CGFloat,
        region: (CGFloat, CGFloat, CGFloat, CGFloat)? = nil
    ) -> [CGRect] {
        let regionX = mapW * (region?.0 ?? 0)
        let regionY = mapH * (region?.1 ?? 0)
        let regionW = mapW * (region?.2 ?? 1)
        let regionH = mapH * (region?.3 ?? 1)
        let rowCount = shape.count
        let rowH = regionH / CGFloat(rowCount)
        var slots: [CGRect] = []
        for (row, cols) in shape.enumerated() {
            let colW = regionW / CGFloat(cols)
            let y = regionY + CGFloat(row) * rowH
            for col in 0..<cols {
                slots.append(CGRect(
                    x: regionX + CGFloat(col) * colW,
                    y: y,
                    width: colW,
                    height: rowH
                ))
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
            guard shouldHandleKeyEvent(event) else { return event }
            let consumed = state.handleKey(event.keyCode, modifiers: event.modifierFlags)
            return consumed ? nil : event
        }
    }

    private func shouldHandleKeyEvent(_ event: NSEvent) -> Bool {
        if isEmbedded {
            guard let window = ScreenMapWindowController.shared.nsWindow,
                  window.isKeyWindow else { return false }
            if let eventWindow = event.window {
                return eventWindow === window
            }
            return NSApp.keyWindow === window
        }

        guard let panel = CommandModeWindow.shared.panelWindow,
              panel.isKeyWindow else { return false }
        if let eventWindow = event.window {
            return eventWindow === panel
        }
        return NSApp.keyWindow === panel
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
        // Subtract the panel's global origin to get panel-local coordinates.
        // The Windows page layout puts a filter sidebar to the left of the
        // list, so the list no longer starts at the window's left edge —
        // panelOriginX corrects for that the same way panelOriginY does.
        let panelY = flippedY - panelOriginY
        let panelX = windowPoint.x - panelOriginX
        return CGPoint(x: panelX, y: panelY)
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
