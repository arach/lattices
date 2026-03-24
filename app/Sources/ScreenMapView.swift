import SwiftUI
import AppKit

// MARK: - Screen Map View (Standalone)

struct ScreenMapView: View {
    @ObservedObject var controller: ScreenMapController
    var onNavigate: ((AppPage) -> Void)? = nil
    @ObservedObject private var daemon = DaemonServer.shared
    @ObservedObject private var handsOff = HandsOffSession.shared
    @ObservedObject private var diagnosticLog = DiagnosticLog.shared
    @StateObject private var piChat = PiChatSession.shared
    @State private var eventMonitor: Any?
    @State private var mouseDownMonitor: Any?
    @State private var mouseDragMonitor: Any?
    @State private var mouseUpMonitor: Any?
    @State private var rightClickMonitor: Any?
    @State private var scrollWheelMonitor: Any?
    @State private var screenMapCanvasOrigin: CGPoint = .zero
    @State private var screenMapCanvasSize: CGSize = .zero
    @State private var screenMapTitleBarHeight: CGFloat = 0  // reserved for coordinate math
    @State private var screenMapClickWindowId: UInt32? = nil
    @State private var screenMapClickPoint: NSPoint = .zero
    @State private var hoveredWindowId: UInt32?
    @State private var hoveredShelfAction: String?
    @State private var dropTargetLayer: Int?
    @State private var layerRowFrames: [Int: CGRect] = [:]
    @State private var sidebarDragWindowId: UInt32? = nil
    @State private var sidebarDragOffset: CGSize = .zero
    @State private var expandedLayers: Set<Int> = []
    @State private var mouseMovedMonitor: Any?
    @State private var sidebarWidth: CGFloat = 180
    @State private var isDraggingSidebar: Bool = false
    @State private var inspectorWidth: CGFloat = 280
    @State private var isDraggingInspector: Bool = false
    @FocusState private var isSearchFieldFocused: Bool
    @State private var searchHoveredDisplayIndex: Int? = nil
    @State private var canvasTransitionOffset: CGFloat = 0
    @State private var canvasTransitionOpacity: Double = 1.0
    @State private var isSpaceHeld: Bool = false
    @State private var spaceDragStart: NSPoint? = nil
    @State private var spaceDragPanStart: CGPoint = .zero
    @State private var flagsMonitor: Any?
    @State private var searchOverlayFrame: CGRect = .zero

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if let editor = controller.editor {
                    layerSidebar(editor: editor)
                    panelResizeHandle(isActive: $isDraggingSidebar, width: $sidebarWidth,
                                      range: 140...320, edge: .trailing)
                }
                ZStack {
                    VStack(spacing: 0) {
                        canvasHeaderBezel
                        screenMapCanvas(editor: controller.editor)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .offset(x: canvasTransitionOffset)
                    .opacity(canvasTransitionOpacity)
                    .onChange(of: controller.displayTransition) { direction in
                        guard direction != .none else { return }
                        let slideDistance: CGFloat = direction == .right ? -60 : 60
                        // Start from opposite side
                        canvasTransitionOffset = -slideDistance
                        canvasTransitionOpacity = 0.3
                        withAnimation(.easeOut(duration: 0.2)) {
                            canvasTransitionOffset = 0
                            canvasTransitionOpacity = 1.0
                        }
                    }
                    if controller.isSearchActive, let editor = controller.editor {
                        floatingSearchOverlay(editor: editor)
                    }
                    // Viewport controls — bottom-right corner of canvas
                    if let editor = controller.editor {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                canvasViewportDock(editor: editor)
                                    .padding(10)
                            }
                        }
                    }
                }
                if let editor = controller.editor {
                    panelResizeHandle(isActive: $isDraggingInspector, width: $inspectorWidth,
                                      range: 220...480, edge: .leading)
                    inspectorPane(editor: editor)
                }
            }
            if piChat.isVisible {
                PiChatDock(session: piChat)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            footerBar
        }
        .background(Palette.bg)
        .overlay(flashOverlay)
        .onAppear {
            installKeyHandler()
            installMouseMonitors()
        }
        .onDisappear {
            removeKeyHandler()
            removeMouseMonitors()
        }
        .onChange(of: controller.editor?.isPreviewing) { isPreviewing in
            handlePreviewChange(isPreviewing: isPreviewing ?? false)
        }
    }

    // MARK: - Display Toolbar (floating in canvas)

    private func displayToolbar(editor: ScreenMapEditorState) -> some View {
        HStack(spacing: 4) {
            Button {
                editor.cyclePreviousDisplay()
                controller.focusViewportPreset(editor.activeViewportPreset ?? .main, flashView: false)
                controller.flash(editor.focusedDisplay?.label ?? "All displays")
                controller.objectWillChange.send()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(Palette.textDim)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                editor.focusDisplay(nil)
                controller.focusViewportPreset(editor.activeViewportPreset ?? .main, flashView: false)
                controller.objectWillChange.send()
            } label: {
                displayToolbarPill(name: "All", isActive: editor.focusedDisplayIndex == nil)
            }
            .buttonStyle(.plain)

            ForEach(Array(editor.spatialDisplayOrder.enumerated()), id: \.element.index) { spatialPos, disp in
                let isActive = editor.focusedDisplayIndex == disp.index
                Button {
                    editor.focusDisplay(disp.index)
                    controller.focusViewportPreset(editor.activeViewportPreset ?? .main, flashView: false)
                    controller.objectWillChange.send()
                } label: {
                    displayToolbarPill(
                        badge: spatialPos + 1,
                        name: disp.label,
                        isActive: isActive
                    )
                }
                .buttonStyle(.plain)
            }

            Button {
                editor.cycleNextDisplay()
                controller.focusViewportPreset(editor.activeViewportPreset ?? .main, flashView: false)
                controller.flash(editor.focusedDisplay?.label ?? "All displays")
                controller.objectWillChange.send()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(Palette.textDim)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.65))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }

    private func displayToolbarPill(badge: Int? = nil, name: String, isActive: Bool) -> some View {
        HStack(spacing: 4) {
            if let badge = badge {
                ZStack {
                    Circle()
                        .fill(isActive ? Palette.running.opacity(0.5) : Color.white.opacity(0.25))
                        .frame(width: 14, height: 14)
                    Text("\(badge)")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(isActive ? .white : .black)
                }
            }
            Text(name)
                .font(Typo.monoBold(8))
                .foregroundColor(isActive ? Palette.text : Palette.textDim)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isActive ? Palette.running.opacity(0.15) : Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(isActive ? Palette.running.opacity(0.4) : Color.clear, lineWidth: 0.5)
        )
    }

    // MARK: - Canvas Header Bezel

    private var canvasHeaderBezel: some View {
        HStack(spacing: 6) {
            if let editor = controller.editor {
                if let focused = editor.focusedDisplay {
                    Circle().fill(Palette.running.opacity(0.4)).frame(width: 6, height: 6)
                    Text(focused.label).font(Typo.monoBold(9)).foregroundColor(Palette.textDim).lineLimit(1)
                    Text("\(Int(focused.cgRect.width))×\(Int(focused.cgRect.height))").font(Typo.mono(8)).foregroundColor(Palette.textMuted)
                } else {
                    Text("All Displays").font(Typo.monoBold(9)).foregroundColor(Palette.textDim)
                    Text("\(editor.displays.count) monitors").font(Typo.mono(8)).foregroundColor(Palette.textMuted)
                }
                Spacer()
                Text("\(editor.focusedVisibleWindows.count) windows").font(Typo.mono(8)).foregroundColor(Palette.textMuted)
            } else { Text("Canvas"); Spacer() }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Color(red: 0.08, green: 0.08, blue: 0.09))
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.border).frame(height: 0.5) }
    }

    // MARK: - Panel Resize Handle

    enum PanelEdge { case trailing, leading }

    private func panelResizeHandle(isActive: Binding<Bool>, width: Binding<CGFloat>,
                                    range: ClosedRange<CGFloat>, edge: PanelEdge) -> some View {
        Rectangle()
            .fill(isActive.wrappedValue ? Palette.running.opacity(0.3) : Palette.border)
            .frame(width: isActive.wrappedValue ? 2 : 0.5)
            .contentShape(Rectangle().inset(by: -3))
            .onHover { h in if h { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        isActive.wrappedValue = true
                        let delta = edge == .trailing ? value.translation.width : -value.translation.width
                        let newWidth = width.wrappedValue + delta
                        width.wrappedValue = max(range.lowerBound, min(range.upperBound, newWidth))
                    }
                    .onEnded { _ in isActive.wrappedValue = false }
            )
    }

    // MARK: - Inspector Pane

    private func inspectorPane(editor: ScreenMapEditorState) -> some View {
        let selectedWindows = editor.windows.filter { controller.selectedWindowIds.contains($0.id) }

        return VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("INSPECTOR")
                        .font(Typo.monoBold(9))
                        .foregroundColor(Palette.textMuted)

                    inspectorCanvasContextCard(editor: editor, selectedCount: selectedWindows.count)

                    if selectedWindows.isEmpty {
                        VStack(spacing: 8) {
                            Text("No Selection")
                                .font(Typo.monoBold(10))
                                .foregroundColor(Palette.textDim)
                            Text("Click a window on the canvas to inspect.")
                                .font(Typo.mono(9))
                                .foregroundColor(Palette.textMuted)
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                    }

                    ForEach(selectedWindows) { win in
                        inspectorWindowCard(win: win, editor: editor)
                    }
                }
                .padding(8)
            }

            // Pinned action tray at bottom
            inspectorActionTray(editor: editor)
        }
        .frame(width: inspectorWidth)
    }

    private func inspectorCanvasContextCard(editor: ScreenMapEditorState, selectedCount: Int) -> some View {
        let viewport = editor.viewportWorldRect
        let world = editor.canvasWorldBounds
        let scope = editor.focusedDisplay.map { "\(editor.spatialNumber(for: $0.index)). \($0.label)" } ?? "All Displays"
        let layers = editor.selectedLayers.isEmpty
            ? "All Layers"
            : editor.selectedLayers.sorted().map { editor.layerDisplayName(for: $0) }.joined(separator: ", ")

        return VStack(alignment: .leading, spacing: 4) {
            inspectorRow(label: "Scope", value: scope)
            inspectorRow(label: "Layers", value: layers)
            inspectorRow(label: "View", value: "\(Int(viewport.midX)), \(Int(viewport.midY)) · \(Int(viewport.width))×\(Int(viewport.height))")
            inspectorRow(label: "World", value: "\(Int(world.width))×\(Int(world.height))")
            inspectorRow(label: "Select", value: "\(selectedCount) window\(selectedCount == 1 ? "" : "s")")
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.25))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Inspector Window Card

    private func inspectorWindowCard(win: ScreenMapWindowEntry, editor: ScreenMapEditorState) -> some View {
        let desktopEntry = DesktopModel.shared.windows[UInt32(win.id)]
        let ocrText = OcrModel.shared.results[UInt32(win.id)]?.fullText
        let layerTag = DesktopModel.shared.windowLayerTags[UInt32(win.id)]

        return VStack(alignment: .leading, spacing: 8) {
            // Header: app + visibility
            HStack(spacing: 5) {
                Circle()
                    .fill(Self.layerColor(for: win.layer))
                    .frame(width: 6, height: 6)
                Text(win.app)
                    .font(Typo.monoBold(11))
                    .foregroundColor(Palette.text)
                    .lineLimit(1)
                Spacer()
                if desktopEntry?.isOnScreen == true {
                    Text("visible")
                        .font(Typo.monoBold(7))
                        .foregroundColor(Palette.running)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Palette.running.opacity(0.1))
                        )
                }
            }

            // Title
            if !win.title.isEmpty {
                Text(win.title)
                    .font(Typo.mono(10))
                    .foregroundColor(Palette.textDim)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }

            // Identity
            HStack(spacing: 10) {
                inspectorLabel(label: "wid", value: "\(win.id)")
                if let entry = desktopEntry {
                    inspectorLabel(label: "pid", value: "\(entry.pid)")
                }
            }

            // Layout info
            VStack(alignment: .leading, spacing: 3) {
                inspectorRow(label: "Layer", value: editor.layerDisplayName(for: win.layer))
                if let tag = layerTag {
                    inspectorRow(label: "Tag", value: tag)
                }
                inspectorRow(label: "Display", value: {
                    if let disp = editor.displays.first(where: { $0.index == win.displayIndex }) {
                        return "\(editor.spatialNumber(for: disp.index)). \(disp.label)"
                    }
                    return "Display \(win.displayIndex)"
                }())
                inspectorRow(label: "Size",
                             value: "\(Int(win.virtualFrame.width))×\(Int(win.virtualFrame.height))")
                inspectorRow(label: "Position",
                             value: "(\(Int(win.virtualFrame.origin.x)), \(Int(win.virtualFrame.origin.y)))")
                inspectorRow(label: "Z-Index", value: "\(win.zIndex)")
                if win.hasEdits {
                    inspectorRow(label: "Original",
                                 value: "\(Int(win.originalFrame.width))×\(Int(win.originalFrame.height))")
                }
                if let entry = desktopEntry, !entry.spaceIds.isEmpty {
                    inspectorRow(label: "Spaces", value: entry.spaceIds.map(String.init).joined(separator: ", "))
                }
            }

            // Session
            if let session = desktopEntry?.latticesSession {
                HStack(spacing: 4) {
                    Text("session")
                        .font(Typo.monoBold(8))
                        .foregroundColor(Palette.textMuted)
                    Text(session)
                        .font(Typo.mono(9))
                        .foregroundColor(Palette.running)
                        .lineLimit(1)
                }
            }

            if win.hasEdits {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 5, height: 5)
                    Text("Modified")
                        .font(Typo.monoBold(8))
                        .foregroundColor(Color.orange)
                }
            }

            // OCR snippet
            if let ocr = ocrText, !ocr.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SCREEN TEXT")
                        .font(Typo.monoBold(8))
                        .foregroundColor(Palette.textMuted)
                    Text(String(ocr.prefix(400)))
                        .font(Typo.mono(8))
                        .foregroundColor(Palette.textMuted)
                        .lineLimit(8)
                        .textSelection(.enabled)
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Palette.bg.opacity(0.5))
                )
            }

            // Window actions — contextual to this card
            if let entry = desktopEntry {
                windowCardActions(wid: UInt32(win.id), entry: entry)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Palette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Palette.border, lineWidth: 0.5)
                )
        )
    }

    private func windowCardActions(wid: UInt32, entry: WindowEntry) -> some View {
        let actions: [(key: String, label: String, action: () -> Void)] = [
            ("f", "focus", { [controller] in
                controller.focusWindowOnScreen(wid)
            }),
            ("h", "highlight", {
                WindowTiler.highlightWindowById(wid: wid)
            }),
            ("←", "tile left", {
                WindowTiler.focusWindow(wid: wid, pid: entry.pid)
                WindowTiler.tileWindowById(wid: wid, pid: entry.pid, to: .left)
            }),
            ("→", "tile right", {
                WindowTiler.focusWindow(wid: wid, pid: entry.pid)
                WindowTiler.tileWindowById(wid: wid, pid: entry.pid, to: .right)
            }),
            ("m", "maximize", {
                WindowTiler.focusWindow(wid: wid, pid: entry.pid)
                WindowTiler.tileWindowById(wid: wid, pid: entry.pid, to: .maximize)
            }),
            ("r", "rescan", {
                OcrModel.shared.scanSingle(wid: wid)
            }),
            ("c", "copy info", { [controller] in
                let info = [
                    "wid: \(wid)",
                    "app: \(entry.app)",
                    "title: \(entry.title)",
                    "pid: \(entry.pid)",
                    "frame: \(Int(entry.frame.x)),\(Int(entry.frame.y)) \(Int(entry.frame.w))×\(Int(entry.frame.h))",
                    entry.latticesSession.map { "session: \($0)" },
                    DesktopModel.shared.windowLayerTags[wid].map { "layer: \($0)" },
                ].compactMap { $0 }.joined(separator: "\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(info, forType: .string)
                controller.flash("Copied")
            }),
        ]

        let columns = [GridItem(.flexible()), GridItem(.flexible())]

        return VStack(spacing: 0) {
            Rectangle().fill(Palette.border).frame(height: 0.5)
                .padding(.horizontal, -10)
                .padding(.top, 4)

            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(Array(actions.enumerated()), id: \.offset) { _, item in
                    let isHov = hoveredShelfAction == "w_\(wid)_\(item.label)"
                    Button(action: item.action) {
                        HStack(spacing: 4) {
                            Text(item.key)
                                .font(.system(size: 8))
                                .foregroundColor(Self.shelfGreen)
                                .frame(width: 14)
                            Text(item.label)
                                .font(Typo.mono(8))
                                .foregroundColor(isHov ? Palette.text : Palette.textDim)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isHov ? Palette.surfaceHov : Palette.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(isHov ? Palette.borderLit : Palette.border, lineWidth: 0.5)
                                )
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { h in
                        let key = "w_\(wid)_\(item.label)"
                        hoveredShelfAction = h ? key : (hoveredShelfAction == key ? nil : hoveredShelfAction)
                    }
                }
            }
            .padding(.top, 6)
        }
    }

    private func inspectorLabel(label: String, value: String) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(Typo.monoBold(8))
                .foregroundColor(Palette.textMuted)
            Text(value)
                .font(Typo.mono(9))
                .foregroundColor(Palette.textDim)
        }
    }

    // MARK: - Floating Search Overlay

    private func floatingSearchOverlay(editor: ScreenMapEditorState) -> some View {
        let results = editor.searchFilteredWindows
        let groups = editor.searchResultsByDisplay
        let highlightIdx = max(0, min(controller.searchHighlightIndex, results.count - 1))
        let terms = editor.searchTerms

        return VStack(spacing: 0) {
            Spacer().frame(height: 60)

            VStack(spacing: 0) {
                // Search field
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Self.shelfGreen)
                    TextField("Search windows…", text: Binding(
                        get: { editor.windowSearchQuery },
                        set: { newValue in
                            editor.windowSearchQuery = newValue
                            controller.searchHighlightIndex = 0
                        }
                    ))
                    .textFieldStyle(.plain)
                    .font(Typo.mono(14))
                    .foregroundColor(Palette.text)
                    .focused($isSearchFieldFocused)
                    if !editor.windowSearchQuery.isEmpty {
                        Text("\(results.count)")
                            .font(Typo.monoBold(10))
                            .foregroundColor(Palette.textMuted)
                        Button {
                            editor.windowSearchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(Palette.textMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                // Results: side-by-side columns per display
                if !groups.isEmpty {
                    Rectangle().fill(Palette.border).frame(height: 0.5)
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(groups.indices, id: \.self) { groupIdx in
                            let group = groups[groupIdx]
                            if groupIdx > 0 {
                                Rectangle().fill(Palette.border).frame(width: 0.5)
                            }
                            VStack(spacing: 0) {
                                // Display header with hover → mini-map highlight
                                searchDisplayHeader(
                                    spatialNumber: group.spatialNumber,
                                    label: group.label,
                                    matchCount: group.windows.count,
                                    isHovered: searchHoveredDisplayIndex == group.displayIndex
                                )
                                .onHover { hovering in
                                    searchHoveredDisplayIndex = hovering ? group.displayIndex : nil
                                }

                                // Window list for this display
                                ScrollView(.vertical, showsIndicators: false) {
                                    VStack(spacing: 2) {
                                        ForEach(Array(group.windows.enumerated()), id: \.element.id) { _, win in
                                            let flatIdx = flatIndex(for: win, in: groups)
                                            let isHighlighted = flatIdx == highlightIdx
                                            searchResultRow(win: win, editor: editor, terms: terms, isHighlighted: isHighlighted)
                                                .onTapGesture {
                                                    controller.selectSingle(win.id)
                                                    if editor.searchHasDirectHit {
                                                        controller.closeSearch()
                                                    }
                                                }
                                        }
                                    }
                                    .padding(4)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(maxHeight: 280)
                } else if !editor.windowSearchQuery.isEmpty {
                    Rectangle().fill(Palette.border).frame(height: 0.5)
                    Text("No matches")
                        .font(Typo.mono(11))
                        .foregroundColor(Palette.textMuted)
                        .padding(.vertical, 12)
                }

                // Keyboard hints
                Rectangle().fill(Palette.border).frame(height: 0.5)
                HStack(spacing: 8) {
                    searchHint("↑↓", label: "nav")
                    searchHint("↩", label: "select")
                    searchHint("⌘↩", label: "show")
                    searchHint("esc", label: "close")
                    if terms.count > 1 {
                        Spacer()
                        Text("\(terms.count) terms")
                            .font(Typo.mono(7))
                            .foregroundColor(Palette.textMuted)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(red: 0.1, green: 0.1, blue: 0.11))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Self.shelfGreen.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: Self.shelfGreen.opacity(0.15), radius: 20)
                    .shadow(color: Color.black.opacity(0.5), radius: 30)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .frame(width: groups.count > 1 ? 600 : 500)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: SearchOverlayFrameKey.self,
                                            value: geo.frame(in: .global))
                }
            )
            .onPreferenceChange(SearchOverlayFrameKey.self) { frame in
                searchOverlayFrame = frame
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isSearchFieldFocused = true
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.3))
        .contentShape(Rectangle())
        .onTapGesture {
            controller.closeSearch()
        }
    }

    /// Compute flat index of a window within the grouped results (for highlight tracking)
    private func flatIndex(
        for win: ScreenMapWindowEntry,
        in groups: [(displayIndex: Int, spatialNumber: Int, label: String, windows: [ScreenMapWindowEntry])]
    ) -> Int {
        var idx = 0
        for group in groups {
            for w in group.windows {
                if w.id == win.id { return idx }
                idx += 1
            }
        }
        return 0
    }

    /// Display section header within search results
    private func searchDisplayHeader(spatialNumber: Int, label: String, matchCount: Int, isHovered: Bool = false) -> some View {
        HStack(spacing: 6) {
            Text("\(spatialNumber)")
                .font(Typo.monoBold(8))
                .foregroundColor(isHovered ? Palette.bg : Palette.bg)
                .frame(width: 14, height: 14)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isHovered ? Self.shelfGreen : Palette.textMuted)
                )
            Text(label)
                .font(Typo.mono(9))
                .foregroundColor(isHovered ? Palette.text : Palette.textMuted)
                .lineLimit(1)
            Spacer()
            Text("\(matchCount)")
                .font(Typo.monoBold(8))
                .foregroundColor(isHovered ? Self.shelfGreen : Palette.textMuted)
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .background(isHovered ? Self.shelfGreen.opacity(0.06) : Color.clear)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    private func searchResultRow(win: ScreenMapWindowEntry, editor: ScreenMapEditorState, terms: [String], isHighlighted: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Self.layerColor(for: win.layer))
                .frame(width: 5, height: 5)
            VStack(alignment: .leading, spacing: 1) {
                highlightedText(win.app, terms: terms, baseFont: Typo.monoBold(9),
                                baseColor: isHighlighted ? Palette.text : Palette.textDim)
                    .lineLimit(1)
                if !win.title.isEmpty {
                    highlightedText(win.title, terms: terms, baseFont: Typo.mono(8),
                                    baseColor: Palette.textMuted)
                        .lineLimit(1)
                }
            }
            Spacer()
            if isHighlighted {
                Button {
                    controller.focusWindowOnScreen(win.id)
                } label: {
                    Image(systemName: "macwindow.and.cursorarrow")
                        .font(.system(size: 8))
                        .foregroundColor(Self.shelfGreen)
                        .padding(3)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Self.shelfGreen.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
                .help("Show on screen (⌘↩)")
            }
            Text(editor.layerDisplayName(for: win.layer))
                .font(Typo.mono(7))
                .foregroundColor(Palette.textMuted)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Self.layerColor(for: win.layer).opacity(0.15))
                )
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHighlighted ? Self.shelfGreen.opacity(0.12) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(isHighlighted ? Self.shelfGreen.opacity(0.3) : Color.clear, lineWidth: 0.5)
                )
        )
        .contentShape(Rectangle())
        .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
    }

    /// Highlight matching search terms within text
    private func highlightedText(_ text: String, terms: [String], baseFont: Font, baseColor: Color) -> Text {
        guard !terms.isEmpty else {
            return Text(text).font(baseFont).foregroundColor(baseColor)
        }
        let lower = text.lowercased()
        // Build set of character offsets that match any term
        var matchSet = IndexSet()
        for term in terms {
            var searchStart = lower.startIndex
            while searchStart < lower.endIndex,
                  let range = lower.range(of: term, range: searchStart..<lower.endIndex) {
                let startOffset = lower.distance(from: lower.startIndex, to: range.lowerBound)
                let length = lower.distance(from: range.lowerBound, to: range.upperBound)
                matchSet.insert(integersIn: startOffset..<(startOffset + length))
                searchStart = range.upperBound
            }
        }
        // Convert to segments
        var result = Text("")
        var i = 0
        let chars = Array(text)
        while i < chars.count {
            let isMatch = matchSet.contains(i)
            var j = i + 1
            while j < chars.count && matchSet.contains(j) == isMatch { j += 1 }
            let segment = String(chars[i..<j])
            if isMatch {
                result = result + Text(segment).font(baseFont).foregroundColor(Self.shelfGreen)
            } else {
                result = result + Text(segment).font(baseFont).foregroundColor(baseColor)
            }
            i = j
        }
        return result
    }

    private func footerHint(_ key: String, label: String) -> some View {
        HStack(spacing: 2) {
            Text(key)
                .font(Typo.monoBold(8))
                .foregroundColor(Palette.textDim)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Palette.border, lineWidth: 0.5)
                )
            Text(label)
                .font(Typo.mono(8))
                .foregroundColor(Palette.textMuted)
        }
    }

    private func searchHint(_ key: String, label: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(Typo.monoBold(7))
                .foregroundColor(Palette.textDim)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Palette.border, lineWidth: 0.5)
                )
            Text(label)
                .font(Typo.mono(7))
                .foregroundColor(Palette.textMuted)
        }
    }

    // MARK: - Inspector Bottom Rail

    private func inspectorActionTray(editor: ScreenMapEditorState) -> some View {
        let actions: [(key: String, label: String, action: () -> Void)] = [
            ("s", "spread", { [controller] in controller.smartSpreadLayer() }),
            ("e", "expose", { [controller] in controller.exposeLayer() }),
            ("t", "tile", { [controller] in controller.tileLayer() }),
            ("d", "distrib", { [controller] in controller.distributeVisible() }),
            ("g", "grow", { [controller] in controller.fitAvailableSpace() }),
            ("m", "project", { [controller] in controller.materializeViewport() }),
            ("c", "merge", { [controller] in controller.consolidateLayers() }),
            ("f", "flatten", { [controller] in controller.flattenLayers() }),
            ("v", "preview", { [controller] in controller.previewLayer() }),
        ]

        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        let editCount = editor.pendingEditCount
        let isZoomed = editor.zoomLevel != 1.0 || editor.panOffset != .zero

        return VStack(spacing: 0) {
            // Contextual commands area (fixed slot, always reserved)
            Rectangle().fill(Palette.border).frame(height: 0.5)
            VStack(spacing: 0) {
                if editor.isTilingMode {
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Text("TILE")
                                .font(Typo.monoBold(9))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 3).fill(Self.shelfGreen))
                            Spacer()
                            Text("esc cancel")
                                .font(Typo.mono(7))
                                .foregroundColor(Palette.textMuted)
                        }
                        HStack(spacing: 3) {
                            ForEach(["←", "→", "↑", "↓"], id: \.self) { key in
                                Text(key)
                                    .font(Typo.monoBold(8))
                                    .foregroundColor(Palette.textDim)
                                    .padding(.horizontal, 3)
                                    .padding(.vertical, 1)
                                    .background(RoundedRectangle(cornerRadius: 2).fill(Palette.surface))
                                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Palette.border, lineWidth: 0.5))
                            }
                            Text("1-7")
                                .font(Typo.monoBold(8))
                                .foregroundColor(Palette.textDim)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 2).fill(Palette.surface))
                                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Palette.border, lineWidth: 0.5))
                            Text("c")
                                .font(Typo.monoBold(8))
                                .foregroundColor(Palette.textDim)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 2).fill(Palette.surface))
                                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Palette.border, lineWidth: 0.5))
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                }
                if editCount > 0 {
                    Button {
                        controller.applyEditsFromButton()
                    } label: {
                        HStack(spacing: 6) {
                            Text("↩")
                                .font(Typo.monoBold(10))
                                .foregroundColor(Self.shelfGreen)
                            Text("Apply \(editCount) \(editCount == 1 ? "edit" : "edits")")
                                .font(Typo.monoBold(9))
                                .foregroundColor(Self.shelfGreen)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                }
                if isZoomed {
                    Button {
                        controller.focusViewportPreset(.overview)
                    } label: {
                        HStack(spacing: 4) {
                            Text("r")
                                .font(Typo.monoBold(8))
                                .foregroundColor(Self.shelfGreen)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 2).fill(Self.shelfGreen.opacity(0.15)))
                            Text("fit all")
                                .font(Typo.mono(8))
                                .foregroundColor(Palette.textDim)
                            Spacer()
                            Text("\(Int(editor.zoomLevel * 100))%")
                                .font(Typo.mono(8))
                                .foregroundColor(Palette.textMuted)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                }
                if let ref = editor.lastActionRef {
                    Button {
                        if let json = editor.actionLog.lastEntryJSON() {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(json, forType: .string)
                            controller.flash("Copied \(ref)")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(ref)
                                .font(Typo.monoBold(8))
                                .foregroundColor(Self.shelfGreen.opacity(0.6))
                            Spacer()
                            Text("copy")
                                .font(Typo.mono(7))
                                .foregroundColor(Palette.textMuted)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color(red: 0.05, green: 0.05, blue: 0.06))

            // Actions grid (always pinned at bottom)
            Rectangle().fill(Palette.border).frame(height: 0.5)

            Text("ACTIONS")
                .font(Typo.monoBold(8))
                .foregroundColor(Palette.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 4)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(actions.enumerated()), id: \.offset) { _, item in
                    let isHovered = hoveredShelfAction == item.key
                    Button(action: item.action) {
                        HStack(spacing: 4) {
                            Text(item.key)
                                .font(Typo.monoBold(8))
                                .foregroundColor(Self.shelfGreen)
                                .frame(width: 14)
                            Text(item.label)
                                .font(Typo.mono(8))
                                .foregroundColor(isHovered ? Palette.text : Palette.textDim)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isHovered ? Palette.surfaceHov : Palette.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(isHovered ? Palette.borderLit : Palette.border, lineWidth: 0.5)
                                )
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { h in
                        hoveredShelfAction = h ? item.key : (hoveredShelfAction == item.key ? nil : hoveredShelfAction)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 4)

            Rectangle().fill(Palette.border).frame(height: 0.5)
            inspectorVoiceTray

            Rectangle().fill(Palette.border).frame(height: 0.5)
            inspectorLogTray
        }
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
    }

    private var inspectorVoiceStateLabel: String {
        switch handsOff.state {
        case .idle: return handsOff.lastTranscript == nil ? "ready" : "idle"
        case .connecting: return "connecting"
        case .listening: return "listening"
        case .thinking: return "thinking"
        }
    }

    private var inspectorVoiceColor: Color {
        switch handsOff.state {
        case .idle: return Palette.textMuted.opacity(0.55)
        case .connecting: return Palette.detach
        case .listening: return Palette.running
        case .thinking: return Palette.detach
        }
    }

    private var visibleDiagnosticEntries: [DiagnosticLog.Entry] {
        let entries = diagnosticLog.entries
        let tail = 8
        if entries.count <= tail { return entries }
        return Array(entries.suffix(tail))
    }

    private var inspectorVoiceTray: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("VOICE")
                    .font(Typo.monoBold(8))
                    .foregroundColor(Palette.textMuted)
                Spacer()
                Circle()
                    .fill(inspectorVoiceColor)
                    .frame(width: 6, height: 6)
                Text(inspectorVoiceStateLabel)
                    .font(Typo.mono(8))
                    .foregroundColor(inspectorVoiceColor)
                Text("V")
                    .font(Typo.monoBold(7))
                    .foregroundColor(Palette.textDim)
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
            }

            if let transcript = handsOff.lastTranscript, !transcript.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("heard")
                        .font(Typo.mono(7))
                        .foregroundColor(Palette.textMuted)
                    Text(transcript)
                        .font(Typo.mono(8))
                        .foregroundColor(Palette.text)
                        .lineLimit(2)
                }
            } else {
                Text("Voice activity will show up here. Press V to talk.")
                    .font(Typo.mono(8))
                    .foregroundColor(Palette.textMuted)
                    .lineLimit(2)
            }

            if let response = handsOff.lastResponse, !response.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("response")
                        .font(Typo.mono(7))
                        .foregroundColor(Palette.textMuted)
                    Text(response)
                        .font(Typo.mono(8))
                        .foregroundColor(Palette.textDim)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    private var inspectorLogTray: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("LOGS")
                    .font(Typo.monoBold(8))
                    .foregroundColor(Palette.textMuted)
                Spacer()
                if !visibleDiagnosticEntries.isEmpty {
                    Button("copy") {
                        let text = visibleDiagnosticEntries.map { entry in
                            "\(Self.inspectorLogTimeFormatter.string(from: entry.time)) \(entry.icon) \(entry.message)"
                        }.joined(separator: "\n")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        controller.flash("Copied logs")
                    }
                    .font(Typo.mono(7))
                    .foregroundColor(Palette.textMuted)
                    .buttonStyle(.plain)
                }
                Button("open") {
                    DiagnosticWindow.shared.toggle()
                }
                .font(Typo.mono(7))
                .foregroundColor(Palette.textMuted)
                .buttonStyle(.plain)
            }

            if visibleDiagnosticEntries.isEmpty {
                Text("Waiting for diagnostic activity.")
                    .font(Typo.mono(8))
                    .foregroundColor(Palette.textMuted)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(visibleDiagnosticEntries) { entry in
                        HStack(alignment: .top, spacing: 6) {
                            Text(Self.inspectorLogTimeFormatter.string(from: entry.time))
                                .font(Typo.mono(7))
                                .foregroundColor(Palette.textMuted)
                                .frame(width: 52, alignment: .leading)
                            Text(entry.icon)
                                .font(Typo.monoBold(7))
                                .foregroundColor(inspectorLogColor(entry.level))
                                .frame(width: 8, alignment: .leading)
                            Text(entry.message)
                                .font(Typo.mono(8))
                                .foregroundColor(inspectorLogColor(entry.level))
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inspectorLogColor(_ level: DiagnosticLog.Entry.Level) -> Color {
        switch level {
        case .info: return Palette.textDim
        case .success: return Palette.running
        case .warning: return Palette.detach
        case .error: return Palette.kill
        }
    }

    private func inspectorRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label)
                .font(Typo.mono(8))
                .foregroundColor(Palette.textMuted)
                .frame(width: 52, alignment: .leading)
            Text(value)
                .font(Typo.mono(8))
                .foregroundColor(Palette.textDim)
                .lineLimit(2)
        }
    }

    // MARK: - Canvas Context Badge

    private var canvasContextBadge: some View {
        HStack(spacing: 6) {
            if let editor = controller.editor {
                let layerColor = editor.activeLayer != nil
                    ? Self.layerColor(for: editor.activeLayer!)
                    : Palette.running

                Circle()
                    .fill(layerColor)
                    .frame(width: 6, height: 6)

                Text(editor.layerLabel)
                    .font(Typo.monoBold(9))
                    .foregroundColor(layerColor)

                Text("·")
                    .foregroundColor(Palette.textMuted)

                Text("\(editor.focusedVisibleWindows.count) windows")
                    .font(Typo.mono(9))
                    .foregroundColor(Palette.textDim)

                Text("·")
                    .foregroundColor(Palette.textMuted)

                Text(editor.viewportPresetSummary.uppercased())
                    .font(Typo.monoBold(8))
                    .foregroundColor(Palette.textMuted)

                if let focused = editor.focusedDisplay {
                    Text("·")
                        .foregroundColor(Palette.textMuted)
                    Text(focused.label)
                        .font(Typo.mono(8))
                        .foregroundColor(Palette.textMuted)
                        .lineLimit(1)
                }

                let editCount = editor.windows.filter { $0.hasEdits }.count
                if editCount > 0 {
                    Text("·")
                        .foregroundColor(Palette.textMuted)
                    Text("\(editCount) pending")
                        .font(Typo.mono(8))
                        .foregroundColor(Color.orange.opacity(0.8))
                        .onTapGesture { controller.applyEditsFromButton() }
                        .onHover { hovering in
                            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                        }
                }

                if let ref = editor.lastActionRef {
                    Text("·")
                        .foregroundColor(Palette.textMuted)
                    Text(ref)
                        .font(Typo.monoBold(8))
                        .foregroundColor(Self.shelfGreen.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
        .padding(10)
    }

    // MARK: - Layer Sidebar

    private func layerSidebar(editor: ScreenMapEditorState) -> some View {
        let layers = editor.effectiveLayers

        return VStack(spacing: 0) {
            // Header
            HStack {
                Text("LAYERS")
                    .font(Typo.monoBold(9))
                    .foregroundColor(Palette.textMuted)
                Spacer()
                if editor.effectiveLayerCount > 1 {
                    Button(action: { controller.consolidateLayers() }) {
                        Image(systemName: "arrow.triangle.merge")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(Palette.textDim)
                    }
                    .buttonStyle(.plain)
                    .help("Defrag layers (c)")
                }
            }
            .padding(.bottom, 8)

            // "All" row
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    layerTreeHeader(
                        label: "All",
                        count: editor.focusedDisplayIndex != nil
                            ? editor.windows.filter { $0.displayIndex == editor.focusedDisplayIndex! }.count
                            : editor.windows.count,
                        isActive: editor.isShowingAll,
                        color: Palette.running
                    ) {
                        editor.selectLayer(nil)
                        controller.objectWillChange.send()
                    }

                    // Per-layer tree nodes
                    ForEach(layers, id: \.self) { layer in
                        let displayName = editor.layerDisplayName(for: layer)
                        let fullName = editor.layerNames[layer]
                        let color = Self.layerColor(for: layer)
                        let isActive = editor.isLayerSelected(layer)
                        let isDropTarget = dropTargetLayer == layer
                        let layerWindows = layerWindowsForTree(editor: editor, layer: layer)

                        VStack(spacing: 0) {
                            layerTreeHeader(label: fullName ?? displayName,
                                            count: layerWindows.count,
                                            isActive: isActive,
                                            color: color,
                                            isExpandable: true,
                                            isExpanded: expandedLayers.contains(layer),
                                            onToggleExpand: {
                                                if expandedLayers.contains(layer) {
                                                    expandedLayers.remove(layer)
                                                } else {
                                                    expandedLayers.insert(layer)
                                                }
                                            }) {
                                if NSEvent.modifierFlags.contains(.command) {
                                    editor.toggleLayerSelection(layer)
                                } else {
                                    editor.selectLayer(layer)
                                }
                                // Auto-expand on selection
                                expandedLayers.insert(layer)
                                controller.objectWillChange.send()
                            }

                            // Window children (shown when layer is expanded)
                            if expandedLayers.contains(layer) {
                                VStack(spacing: 0) {
                                    ForEach(layerWindows) { win in
                                        let isSelected = controller.selectedWindowIds.contains(win.id)
                                        let isDragging = sidebarDragWindowId == win.id
                                        HStack(spacing: 4) {
                                            Rectangle()
                                                .fill(color.opacity(0.4))
                                                .frame(width: 1, height: 12)
                                                .padding(.leading, 8)
                                            Text(win.app)
                                                .font(Typo.mono(8))
                                                .foregroundColor(isSelected ? Palette.running : Palette.textDim)
                                                .lineLimit(1)
                                            Spacer()
                                            if win.hasEdits {
                                                Circle()
                                                    .fill(Color.orange)
                                                    .frame(width: 4, height: 4)
                                            }
                                        }
                                        .padding(.vertical, 2)
                                        .padding(.horizontal, 4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(isSelected ? Palette.running.opacity(0.08) : Color.clear)
                                        )
                                        .contentShape(Rectangle())
                                        .opacity(isDragging ? 0.4 : 1.0)
                                        .offset(isDragging ? sidebarDragOffset : .zero)
                                        .zIndex(isDragging ? 10 : 0)
                                        .gesture(
                                            DragGesture(minimumDistance: 4, coordinateSpace: .named("layerSidebar"))
                                                .onChanged { value in
                                                    sidebarDragWindowId = win.id
                                                    sidebarDragOffset = value.translation
                                                    controller.selectSingle(win.id)
                                                    // Hit-test layer rows
                                                    let pt = value.location
                                                    var hit: Int? = nil
                                                    for (l, frame) in layerRowFrames {
                                                        if l != layer && frame.contains(pt) {
                                                            hit = l
                                                            break
                                                        }
                                                    }
                                                    dropTargetLayer = hit
                                                }
                                                .onEnded { _ in
                                                    if let targetLayer = dropTargetLayer {
                                                        editor.reassignLayer(windowId: win.id, toLayer: targetLayer, fitToAvailable: true)
                                                        controller.flash("Moved to L\(targetLayer)")
                                                        controller.objectWillChange.send()
                                                    }
                                                    sidebarDragWindowId = nil
                                                    sidebarDragOffset = .zero
                                                    dropTargetLayer = nil
                                                }
                                        )
                                        .onTapGesture {
                                            if NSEvent.modifierFlags.contains(.command) {
                                                controller.toggleSelection(win.id)
                                            } else {
                                                controller.selectSingle(win.id)
                                            }
                                        }
                                    }
                                }
                                .padding(.leading, 4)
                                .padding(.top, 2)
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(isDropTarget ? Palette.running : Color.clear, lineWidth: 1.5)
                        )
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(key: LayerRowFrameKey.self,
                                    value: [layer: geo.frame(in: .named("layerSidebar"))])
                            }
                        )
                    }
                }
            }
            .coordinateSpace(name: "layerSidebar")

            Spacer(minLength: 8)
            canvasExplorer(editor: editor)
            Spacer(minLength: 8)
            sidebarMiniMap(editor: editor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(width: sidebarWidth)
        .onPreferenceChange(LayerRowFrameKey.self) { layerRowFrames = $0 }
    }

    private func layerWindowsForTree(editor: ScreenMapEditorState, layer: Int) -> [ScreenMapWindowEntry] {
        var wins = editor.windows.filter { $0.layer == layer }
        if let dIdx = editor.focusedDisplayIndex {
            wins = wins.filter { $0.displayIndex == dIdx }
        }
        return wins.sorted { $0.zIndex < $1.zIndex }
    }

    private func layerTreeHeader(label: String, count: Int, isActive: Bool, color: Color,
                                   isExpandable: Bool = false, isExpanded: Bool = false,
                                   onToggleExpand: (() -> Void)? = nil,
                                   action: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            if isExpandable {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(Palette.textMuted)
                    .frame(width: 16, height: 16)
                    .onTapGesture { onToggleExpand?() }
            }
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(label)
                    .font(Typo.monoBold(9))
                    .lineLimit(1)
                Spacer()
                Text("\(count)")
                    .font(Typo.mono(8))
                    .foregroundColor(isActive ? Palette.text.opacity(0.7) : Palette.textMuted)
            }
            .foregroundColor(isActive ? Palette.text : Palette.textDim)
        }
        .padding(.leading, isExpandable ? 0 : 16)
        .padding(.trailing, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? color.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { action() }
    }

    // MARK: - Canvas

    private func screenMapCanvas(editor: ScreenMapEditorState?) -> some View {
        let isFocused = editor?.focusedDisplayIndex != nil
        let allWindows = isFocused ? (editor?.focusedVisibleWindows ?? []) : (editor?.visibleWindows ?? [])
        let displays = editor?.displays ?? []
        let zoomLevel = editor?.zoomLevel ?? 1.0
        let panOffset = editor?.panOffset ?? .zero

        return GeometryReader { geo in
            let availW = geo.size.width - 24
            let availH = geo.size.height - 16

            let bboxPad: CGFloat = (!isFocused && displays.count > 1) ? 40 : 0
            let bbox: CGRect = {
                if let editor {
                    return editor.canvasWorldBounds
                }
                guard !displays.isEmpty else {
                    let s = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
                    return CGRect(origin: .zero, size: s.size)
                }
                var union = displays[0].cgRect
                for d in displays.dropFirst() { union = union.union(d.cgRect) }
                return union.insetBy(dx: -bboxPad, dy: -bboxPad)
            }()
            let bboxOriginPt = bbox.origin
            let screenW = bbox.width
            let screenH = bbox.height

            let fitScale = min(availW / screenW, availH / screenH)
            let effScale = fitScale * zoomLevel
            let mapW = screenW * effScale
            let mapH = screenH * effScale
            let centerX = (geo.size.width - mapW) / 2
            let centerY = (geo.size.height - mapH) / 2

            ZStack(alignment: .topLeading) {
                // Per-display background rectangles
                if isFocused, let focused = editor?.focusedDisplay, let editor = editor {
                    focusedDisplayBackground(focused: focused, editor: editor, mapW: mapW, mapH: mapH)
                } else if displays.count > 1 {
                    multiDisplayBackgrounds(displays: displays, editor: editor, effScale: effScale, bboxOrigin: bboxOriginPt)
                } else {
                    singleDisplayBackground(displays: displays, mapW: mapW, mapH: mapH)
                }

                // Ghost outlines for edited windows
                ForEach(allWindows.filter(\.hasEdits)) { win in
                    let f = win.originalFrame
                    let x = (f.origin.x - bboxOriginPt.x) * effScale
                    let y = (f.origin.y - bboxOriginPt.y) * effScale
                    let w = max(f.width * effScale, 4)
                    let h = max(f.height * effScale, 4)

                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundColor(Palette.textMuted.opacity(0.4))
                        .frame(width: w, height: h)
                        .offset(x: x, y: y)
                }

                // Live windows back-to-front
                ForEach(Array(allWindows.sorted(by: { $0.zIndex > $1.zIndex }).enumerated()), id: \.element.id) { _, win in
                    windowTile(win: win, editor: editor, scale: effScale, bboxOrigin: bboxOriginPt)
                }
            }
            .frame(width: mapW, height: mapH)
            .offset(x: centerX + panOffset.x, y: centerY + panOffset.y)
            .onAppear {
                syncCanvasGeometry(editor: editor, fitScale: fitScale, scale: effScale,
                                   offsetX: centerX, offsetY: centerY,
                                   viewportSize: CGSize(width: max(geo.size.width - 16, 1), height: max(geo.size.height - 16, 1)),
                                   screenSize: CGSize(width: screenW, height: screenH),
                                   bboxOrigin: bboxOriginPt)
            }
            .onChange(of: geo.size) { _ in
                let newFitScale = min((geo.size.width - 24) / screenW, (geo.size.height - 16) / screenH)
                let newEffScale = newFitScale * zoomLevel
                let newMapW = screenW * newEffScale
                let newMapH = screenH * newEffScale
                let newCX = (geo.size.width - newMapW) / 2
                let newCY = (geo.size.height - newMapH) / 2
                syncCanvasGeometry(editor: editor, fitScale: newFitScale, scale: newEffScale,
                                   offsetX: newCX, offsetY: newCY,
                                   viewportSize: CGSize(width: max(geo.size.width - 16, 1), height: max(geo.size.height - 16, 1)),
                                   screenSize: CGSize(width: screenW, height: screenH),
                                   bboxOrigin: bboxOriginPt)
            }
            .onChange(of: bbox) { _ in
                syncCanvasGeometry(editor: editor, fitScale: fitScale, scale: effScale,
                                   offsetX: centerX, offsetY: centerY,
                                   viewportSize: CGSize(width: max(geo.size.width - 16, 1), height: max(geo.size.height - 16, 1)),
                                   screenSize: CGSize(width: screenW, height: screenH),
                                   bboxOrigin: bboxOriginPt)
            }
            .onChange(of: zoomLevel) { _ in
                syncCanvasGeometry(editor: editor, fitScale: fitScale, scale: effScale,
                                   offsetX: centerX, offsetY: centerY,
                                   viewportSize: CGSize(width: max(geo.size.width - 16, 1), height: max(geo.size.height - 16, 1)),
                                   screenSize: CGSize(width: screenW, height: screenH),
                                   bboxOrigin: bboxOriginPt)
            }
            .onChange(of: editor?.canvasNavigationRevision ?? 0) { _ in
                syncCanvasGeometry(editor: editor, fitScale: fitScale, scale: effScale,
                                   offsetX: centerX, offsetY: centerY,
                                   viewportSize: CGSize(width: max(geo.size.width - 16, 1), height: max(geo.size.height - 16, 1)),
                                   screenSize: CGSize(width: screenW, height: screenH),
                                   bboxOrigin: bboxOriginPt)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.25))
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                Canvas { context, size in
                    let spacing: CGFloat = 20
                    let dotColor = Color.white.opacity(0.04)
                    for x in stride(from: spacing, to: size.width, by: spacing) {
                        for y in stride(from: spacing, to: size.height, by: spacing) {
                            context.fill(
                                Path(ellipseIn: CGRect(x: x - 0.5, y: y - 0.5, width: 1, height: 1)),
                                with: .color(dotColor)
                            )
                        }
                    }
                }
            }
        )
        .overlay(alignment: .top) {
            if let editor = controller.editor, editor.displays.count > 1 {
                displayToolbar(editor: editor)
                    .padding(.top, 8)
            }
        }
        .overlay(alignment: .bottomLeading) {
            canvasContextBadge
        }
        .overlay(
            GeometryReader { geo in
                Color.clear.onAppear {
                    let frame = geo.frame(in: .global)
                    screenMapCanvasOrigin = frame.origin
                    screenMapCanvasSize = frame.size
                }
                .onChange(of: geo.frame(in: .global)) { newFrame in
                    screenMapCanvasOrigin = newFrame.origin
                    screenMapCanvasSize = newFrame.size
                }
            }
        )
    }

    // MARK: - Display Backgrounds

    private func focusedDisplayBackground(focused: DisplayGeometry, editor: ScreenMapEditorState, mapW: CGFloat, mapH: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Palette.bg.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Palette.running.opacity(0.3), lineWidth: 1)
                )
                .contentShape(Rectangle())
                .onTapGesture { controller.clearSelection() }
        }
        .frame(width: mapW, height: mapH)
    }

    private func multiDisplayBackgrounds(displays: [DisplayGeometry], editor: ScreenMapEditorState?, effScale: CGFloat, bboxOrigin: CGPoint) -> some View {
        ForEach(displays, id: \.index) { disp in
            let dx = (disp.cgRect.origin.x - bboxOrigin.x) * effScale
            let dy = (disp.cgRect.origin.y - bboxOrigin.y) * effScale
            let dw = disp.cgRect.width * effScale
            let dh = disp.cgRect.height * effScale
            let bezel: CGFloat = 3

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1.5)
                    )
                RoundedRectangle(cornerRadius: 5)
                    .fill(Palette.bg.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Color.black.opacity(0.4), lineWidth: 0.5)
                    )
                    .padding(bezel)

                // Display number badge (top-left corner)
                VStack {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.3))
                                .frame(width: 16, height: 16)
                            Text("\(editor?.spatialNumber(for: disp.index) ?? (disp.index + 1))")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(.black)
                        }
                        .padding(.top, bezel + 4)
                        .padding(.leading, bezel + 4)
                        Spacer()
                    }
                    Spacer()
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                editor?.focusDisplay(disp.index)
                controller.objectWillChange.send()
            }
            .frame(width: dw, height: dh)
            .offset(x: dx, y: dy)
        }
    }

    private func singleDisplayBackground(displays: [DisplayGeometry], mapW: CGFloat, mapH: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Palette.bg.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Palette.border, lineWidth: 0.5)
                )
                .contentShape(Rectangle())
                .onTapGesture { controller.clearSelection() }

        }
        .frame(width: mapW, height: mapH)
    }

    // MARK: - Window Tile

    @ViewBuilder
    private func windowTile(win: ScreenMapWindowEntry, editor: ScreenMapEditorState?, scale: CGFloat, bboxOrigin: CGPoint = .zero) -> some View {
        let f = win.virtualFrame
        let x = (f.origin.x - bboxOrigin.x) * scale
        let y = (f.origin.y - bboxOrigin.y) * scale
        let w = max(f.width * scale, 4)
        let h = max(f.height * scale, 4)
        let isSelected = controller.selectedWindowIds.contains(win.id)
        let isDragging = editor?.draggingWindowId == win.id
        let isInActiveLayer = editor?.isLayerSelected(win.layer) ?? true
        let winLayerColor = Self.layerColor(for: win.layer)
        let isSearchHighlighted = controller.searchHighlightedWindowId == win.id

        let fillColor = isSearchHighlighted
            ? Self.shelfGreen.opacity(0.2)
            : isSelected
            ? Palette.running.opacity(0.18)
            : win.hasEdits ? Color.orange.opacity(0.12) : Palette.surface.opacity(0.7)
        let borderColor = isSearchHighlighted
            ? Self.shelfGreen.opacity(0.8)
            : isSelected
            ? Palette.running.opacity(0.8)
            : win.hasEdits ? Color.orange.opacity(0.6) : Palette.border.opacity(0.6)

        Button {
            if NSEvent.modifierFlags.contains(.command) {
                controller.toggleSelection(win.id)
            } else {
                controller.selectSingle(win.id)
            }
        } label: {
            RoundedRectangle(cornerRadius: 2)
                .fill(fillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(borderColor, lineWidth: isSearchHighlighted ? 2 : isSelected ? 1.5 : 0.5)
                )
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(winLayerColor)
                        .frame(width: 2)
                }
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .overlay {
                    ZStack {
                        VStack(spacing: 1) {
                            Text(win.app)
                                .font(Typo.monoBold(max(7, min(10, h * 0.15))))
                                .foregroundColor(isSelected ? Palette.running : Palette.text)
                                .lineLimit(1)
                            if h > 30 {
                                Text(win.title)
                                    .font(Typo.mono(max(6, min(8, h * 0.1))))
                                    .foregroundColor(Palette.textDim)
                                    .lineLimit(1)
                            }
                            if h > 50 {
                                Text("\(Int(win.virtualFrame.width))x\(Int(win.virtualFrame.height))")
                                    .font(Typo.mono(6))
                                    .foregroundColor(Palette.textMuted)
                            }
                        }
                        .padding(.leading, 4)
                        .padding(2)

                        if h > 40, let tileIcon = Self.inferTileIcon(for: win, displays: editor?.displays ?? []) {
                            VStack {
                                HStack {
                                    Spacer()
                                    Image(systemName: tileIcon)
                                        .font(.system(size: 6))
                                        .foregroundColor(Color.white.opacity(0.3))
                                        .padding(2)
                                }
                                Spacer()
                            }
                        }

                        if h > 50, let session = Self.extractLatticesSession(from: win.title) {
                            VStack {
                                Spacer()
                                HStack {
                                    Text("[\(session)]")
                                        .font(Typo.mono(6))
                                        .foregroundColor(Palette.running.opacity(0.7))
                                        .lineLimit(1)
                                        .padding(.leading, 4)
                                        .padding(.bottom, 2)
                                    Spacer()
                                }
                            }
                        }
                    }
                }
        }
        .buttonStyle(.plain)
        .frame(width: w, height: h)
        .overlay {
            if isSelected && w > 30 && h > 20 {
                resizeHandles(width: w, height: h)
            }
        }
        .onHover { isHovering in
            hoveredWindowId = isHovering ? win.id : (hoveredWindowId == win.id ? nil : hoveredWindowId)
        }
        .overlay {
            if isSearchHighlighted {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(Self.shelfGreen.opacity(0.6), lineWidth: 2)
                    .shadow(color: Self.shelfGreen.opacity(0.5), radius: 6)
            }
        }
        .offset(x: x, y: y)
        .opacity(isInActiveLayer ? 1.0 : 0.3)
        .shadow(color: isDragging ? Palette.running.opacity(0.4) : .clear,
                radius: isDragging ? 6 : 0)
    }

    @ViewBuilder
    private func resizeHandles(width w: CGFloat, height h: CGFloat) -> some View {
        let dotSize: CGFloat = 5
        let barW: CGFloat = 8
        let barH: CGFloat = 3
        let handleColor = Palette.running.opacity(0.7)
        let halfDot = dotSize / 2

        ZStack {
            // Corner dots
            Circle().fill(handleColor).frame(width: dotSize, height: dotSize)
                .position(x: halfDot, y: halfDot)
            Circle().fill(handleColor).frame(width: dotSize, height: dotSize)
                .position(x: w - halfDot, y: halfDot)
            Circle().fill(handleColor).frame(width: dotSize, height: dotSize)
                .position(x: halfDot, y: h - halfDot)
            Circle().fill(handleColor).frame(width: dotSize, height: dotSize)
                .position(x: w - halfDot, y: h - halfDot)

            // Edge midpoint bars
            if w > 50 {
                RoundedRectangle(cornerRadius: 1).fill(handleColor)
                    .frame(width: barW, height: barH)
                    .position(x: w / 2, y: 1.5)
                RoundedRectangle(cornerRadius: 1).fill(handleColor)
                    .frame(width: barW, height: barH)
                    .position(x: w / 2, y: h - 1.5)
            }
            if h > 40 {
                RoundedRectangle(cornerRadius: 1).fill(handleColor)
                    .frame(width: barH, height: barW)
                    .position(x: 1.5, y: h / 2)
                RoundedRectangle(cornerRadius: 1).fill(handleColor)
                    .frame(width: barH, height: barW)
                    .position(x: w - 1.5, y: h / 2)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Canvas Viewport Controls

    private func canvasViewportDock(editor: ScreenMapEditorState) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(ScreenMapViewportPreset.allCases) { preset in
                    canvasViewportPresetPill(preset, isActive: editor.activeViewportPreset == preset)
                }
            }
            canvasZoomControls(editor: editor)
        }
    }

    private func canvasViewportPresetPill(_ preset: ScreenMapViewportPreset, isActive: Bool) -> some View {
        Button {
            controller.focusViewportPreset(preset)
        } label: {
            HStack(spacing: 4) {
                Text(preset.keyHint)
                    .font(Typo.monoBold(8))
                    .foregroundColor(isActive ? Color.black : Palette.textDim)
                Text(preset.shortLabel)
                    .font(Typo.monoBold(8))
                    .foregroundColor(isActive ? Color.black : Palette.text)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isActive ? Self.shelfGreen.opacity(0.95) : Color(red: 0.1, green: 0.1, blue: 0.11).opacity(0.88))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(isActive ? Self.shelfGreen.opacity(0.95) : Palette.border, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func canvasZoomControls(editor: ScreenMapEditorState) -> some View {
        let pct = Int(editor.zoomLevel * 100)
        return HStack(spacing: 0) {
            Button {
                let newZoom = max(ScreenMapEditorState.minZoom, editor.zoomLevel - 0.25)
                editor.activeViewportPreset = nil
                editor.zoomLevel = newZoom
                editor.objectWillChange.send()
                controller.objectWillChange.send()
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 9, weight: .medium))
                    .frame(width: 22, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle().fill(Palette.border).frame(width: 0.5, height: 12)

            Button {
                controller.focusViewportPreset(.overview)
            } label: {
                Text("\(pct)%")
                    .font(Typo.mono(9))
                    .frame(width: 40, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle().fill(Palette.border).frame(width: 0.5, height: 12)

            Button {
                let newZoom = min(ScreenMapEditorState.maxZoom, editor.zoomLevel + 0.25)
                editor.activeViewportPreset = nil
                editor.zoomLevel = newZoom
                editor.objectWillChange.send()
                controller.objectWillChange.send()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .medium))
                    .frame(width: 22, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .foregroundColor(Palette.textMuted)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(red: 0.1, green: 0.1, blue: 0.11).opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Palette.border, lineWidth: 0.5)
                )
        )
    }

    private static let shelfGreen = Color(red: 0.18, green: 0.82, blue: 0.48)

    // MARK: - Canvas Status Bar

    private var canvasStatusBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.white.opacity(0.04)).frame(height: 0.5)
            HStack(spacing: 6) {
                if let editor = controller.editor {
                    let layerColor = editor.activeLayer != nil
                        ? Self.layerColor(for: editor.activeLayer!)
                        : Palette.running
                    Circle().fill(layerColor).frame(width: 5, height: 5)
                    Text(editor.layerLabel)
                        .font(Typo.monoBold(8))
                        .foregroundColor(layerColor)
                    Text("·").foregroundColor(Palette.textMuted).font(Typo.mono(7))
                    Text("\(editor.focusedVisibleWindows.count) windows")
                        .font(Typo.mono(8))
                        .foregroundColor(Palette.textDim)
                    if let focused = editor.focusedDisplay {
                        Text("·").foregroundColor(Palette.textMuted).font(Typo.mono(7))
                        Text(focused.label)
                            .font(Typo.mono(8))
                            .foregroundColor(Palette.textMuted)
                            .lineLimit(1)
                    }
                    Spacer()
                    let editCount = editor.windows.filter { $0.hasEdits }.count
                    if editCount > 0 {
                        Text("\(editCount) pending")
                            .font(Typo.mono(7))
                            .foregroundColor(Color.orange.opacity(0.7))
                    }
                    if let ref = editor.lastActionRef {
                        Text(ref)
                            .font(Typo.monoBold(8))
                            .foregroundColor(Self.shelfGreen.opacity(0.6))
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .background(Color(red: 0.08, green: 0.08, blue: 0.09))
    }

    // MARK: - Footer Bar

    // MARK: - Status Bar

    private var footerBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Palette.borderLit).frame(height: 0.5)
            HStack(spacing: 0) {
                // Left: server health + settings
                HStack(spacing: 6) {
                    Circle()
                        .fill(daemon.isListening ? Palette.running : Palette.kill)
                        .frame(width: 6, height: 6)
                    if daemon.isListening {
                        Text("Serving")
                            .font(Typo.monoBold(9))
                            .foregroundColor(Palette.running.opacity(0.8))
                        Text(":9399")
                            .font(Typo.mono(9))
                            .foregroundColor(Palette.textMuted)
                        if daemon.clientCount > 0 {
                            Text("·")
                                .foregroundColor(Palette.textMuted)
                            Text("\(daemon.clientCount) client\(daemon.clientCount == 1 ? "" : "s")")
                                .font(Typo.mono(9))
                                .foregroundColor(Palette.textDim)
                        }
                    } else {
                        Text("Offline")
                            .font(Typo.monoBold(9))
                            .foregroundColor(Palette.kill.opacity(0.7))
                    }

                    Text("·").foregroundColor(Palette.textMuted)

                    statusBarButton(icon: "gearshape", label: "Settings") {
                        onNavigate?(.settings)
                    }
                }

                Spacer()
                if let editor = controller.editor {
                    if editor.pendingEditCount > 0 {
                        Button {
                            controller.applyEditsFromButton()
                        } label: {
                            HStack(spacing: 4) {
                                Text("↩")
                                    .font(Typo.monoBold(9))
                                    .foregroundColor(Self.shelfGreen)
                                Text("\(editor.pendingEditCount) pending")
                                    .font(Typo.monoBold(9))
                                    .foregroundColor(Color.orange.opacity(0.8))
                            }
                        }
                        .buttonStyle(.plain)
                        .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                    }
                    if let ref = editor.lastActionRef {
                        Text(ref)
                            .font(Typo.monoBold(8))
                            .foregroundColor(Self.shelfGreen.opacity(0.6))
                    }
                }
                Spacer()

                // Quick keyboard hints
                HStack(spacing: 6) {
                    if !controller.selectedWindowIds.isEmpty {
                        footerHint("⌘↩", label: "show")
                    }
                    footerHint("/", label: "search")
                    footerHint("q", label: "quit")
                }
                .padding(.trailing, 8)

                // Right: docs + logs
                HStack(spacing: 10) {
                    statusBarButton(icon: "terminal", label: piChat.isVisible ? "Hide Pi" : "Pi") {
                        withAnimation(.easeOut(duration: 0.16)) {
                            piChat.toggleVisibility()
                        }
                    }
                    statusBarButton(icon: "book", label: "Docs") {
                        onNavigate?(.docs)
                    }
                    statusBarButton(icon: "text.alignleft", label: "Logs") {
                        DiagnosticWindow.shared.toggle()
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .background(Color(red: 0.08, green: 0.08, blue: 0.09))
    }

    private func statusBarButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                Text(label)
                    .font(Typo.mono(9))
            }
            .foregroundColor(Palette.textMuted)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
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

    // MARK: - Sidebar Mini-Map

    @ViewBuilder
    private func sidebarMiniMap(editor: ScreenMapEditorState) -> some View {
        let displays = editor.displays
        let windows = editor.focusedDisplayIndex != nil ? editor.focusedVisibleWindows : editor.visibleWindows
        let world = editor.canvasWorldBounds
        let viewport = editor.viewportWorldRect
        let miniW: CGFloat = sidebarWidth - 28
        let miniH: CGFloat = 118
        let scaleW = miniW / max(world.width, 1)
        let scaleH = miniH / max(world.height, 1)
        let scale = min(scaleW, scaleH)
        let drawW = world.width * scale
        let drawH = world.height * scale
        let offsetX = (miniW - drawW) / 2
        let offsetY = (miniH - drawH) / 2

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("MAP")
                    .font(Typo.monoBold(8))
                    .foregroundColor(Palette.textMuted)
                Spacer()
                Text("drag to pan")
                    .font(Typo.mono(7))
                    .foregroundColor(Palette.textMuted)
            }

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.28))

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Palette.bg.opacity(0.35))
                        .frame(width: drawW, height: drawH)
                        .offset(x: offsetX, y: offsetY)

                    ForEach(displays, id: \.index) { disp in
                        let dx = (disp.cgRect.origin.x - world.origin.x) * scale + offsetX
                        let dy = (disp.cgRect.origin.y - world.origin.y) * scale + offsetY
                        let dw = disp.cgRect.width * scale
                        let dh = disp.cgRect.height * scale
                        let isFocused = editor.focusedDisplayIndex == nil || editor.focusedDisplayIndex == disp.index

                        RoundedRectangle(cornerRadius: 3)
                            .fill(isFocused ? Color.white.opacity(0.05) : Color.white.opacity(0.02))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .strokeBorder(
                                        editor.focusedDisplayIndex == disp.index ? Palette.running.opacity(0.55) : Color.white.opacity(0.12),
                                        lineWidth: editor.focusedDisplayIndex == disp.index ? 1 : 0.5
                                    )
                            )
                            .frame(width: max(dw, 12), height: max(dh, 12))
                            .offset(x: dx, y: dy)
                    }

                    ForEach(Array(windows.sorted(by: { $0.zIndex > $1.zIndex }).enumerated()), id: \.element.id) { _, win in
                        let rect = win.virtualFrame
                        let x = (rect.origin.x - world.origin.x) * scale + offsetX
                        let y = (rect.origin.y - world.origin.y) * scale + offsetY
                        let w = max(rect.width * scale, 2)
                        let h = max(rect.height * scale, 2)
                        let isSelected = controller.selectedWindowIds.contains(win.id)

                        RoundedRectangle(cornerRadius: 1.5)
                            .fill((isSelected ? Palette.running : Self.layerColor(for: win.layer)).opacity(isSelected ? 0.35 : 0.18))
                            .overlay(
                                RoundedRectangle(cornerRadius: 1.5)
                                    .strokeBorder(isSelected ? Palette.running.opacity(0.85) : Color.white.opacity(0.12), lineWidth: isSelected ? 1 : 0.5)
                            )
                            .frame(width: w, height: h)
                            .offset(x: x, y: y)
                    }

                    let viewportX = (viewport.origin.x - world.origin.x) * scale + offsetX
                    let viewportY = (viewport.origin.y - world.origin.y) * scale + offsetY
                    let viewportW = max(viewport.width * scale, 12)
                    let viewportH = max(viewport.height * scale, 12)

                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Palette.running.opacity(0.9), lineWidth: 1.25)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Palette.running.opacity(0.08))
                        )
                        .frame(width: viewportW, height: viewportH)
                        .offset(x: viewportX, y: viewportY)
                }
            }
            .frame(width: miniW, height: miniH)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let localX = min(max(value.location.x - offsetX, 0), drawW)
                        let localY = min(max(value.location.y - offsetY, 0), drawH)
                        let worldPoint = CGPoint(
                            x: world.origin.x + localX / max(scale, 0.0001),
                            y: world.origin.y + localY / max(scale, 0.0001)
                        )
                        controller.recenterViewport(at: worldPoint)
                    }
            )

            HStack(spacing: 6) {
                mapScopePill("ALL", isActive: editor.focusedDisplayIndex == nil) {
                    controller.focusCanvas(on: editor.canvasWorldBounds, focusDisplay: nil, zoomToFit: true)
                }
                ForEach(editor.spatialDisplayOrder, id: \.index) { disp in
                    mapScopePill("\(editor.spatialNumber(for: disp.index))", isActive: editor.focusedDisplayIndex == disp.index) {
                        controller.focusCanvas(
                            on: editor.canvasExplorerRegions.first(where: { $0.kind == .display && $0.displayIndex == disp.index })?.rect ?? disp.cgRect,
                            focusDisplay: disp.index,
                            zoomToFit: true
                        )
                    }
                }
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
    }

    private func canvasExplorer(editor: ScreenMapEditorState) -> some View {
        let regions = editor.canvasExplorerRegions

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("EXPLORER")
                    .font(Typo.monoBold(8))
                    .foregroundColor(Palette.textMuted)
                Spacer()
                if let viewport = controller.editor?.viewportWorldRect {
                    Text("\(Int(viewport.midX)),\(Int(viewport.midY))")
                        .font(Typo.mono(7))
                        .foregroundColor(Palette.textMuted)
                }
            }

            ForEach(regions.prefix(8)) { region in
                canvasExplorerRow(region: region)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
    }

    private func canvasExplorerRow(region: ScreenMapCanvasRegion) -> some View {
        let tint: Color = {
            switch region.kind {
            case .overview: return Palette.running
            case .display: return Color.blue.opacity(0.8)
            case .layer: return Self.layerColor(for: region.layer ?? 0)
            }
        }()

        return Button {
            controller.jumpToCanvasRegion(region)
            controller.flash(region.title)
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 1) {
                    Text(region.title)
                        .font(Typo.monoBold(8))
                        .foregroundColor(Palette.text)
                        .lineLimit(1)
                    Text(region.subtitle)
                        .font(Typo.mono(7))
                        .foregroundColor(Palette.textMuted)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(region.count)")
                    .font(Typo.mono(7))
                    .foregroundColor(Palette.textDim)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(tint.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(tint.opacity(0.18), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func mapScopePill(_ label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Typo.monoBold(7))
                .foregroundColor(isActive ? Palette.running : Palette.textDim)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isActive ? Palette.running.opacity(0.12) : Palette.surface.opacity(0.7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(isActive ? Palette.running.opacity(0.3) : Palette.border, lineWidth: 0.5)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Flash Overlay

    @ViewBuilder
    private var flashOverlay: some View {
        if let msg = controller.flashMessage {
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
            .animation(.easeOut(duration: 0.2), value: controller.flashMessage)
            .allowsHitTesting(false)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Palette.border)
            .frame(height: 0.5)
    }

    // MARK: - Helpers

    private func syncCanvasGeometry(editor: ScreenMapEditorState?, fitScale: CGFloat? = nil, scale: CGFloat,
                                    offsetX: CGFloat, offsetY: CGFloat,
                                    viewportSize: CGSize,
                                    screenSize: CGSize, bboxOrigin: CGPoint = .zero) {
        if let fs = fitScale { editor?.fitScale = fs }
        editor?.scale = scale
        editor?.mapOrigin = CGPoint(x: offsetX, y: offsetY)
        editor?.viewportSize = viewportSize
        editor?.screenSize = screenSize
        editor?.bboxOrigin = bboxOrigin
        controller.applyPendingCanvasNavigationIfNeeded()
    }

    // MARK: - Layer Colors

    private static let layerColors: [Color] = [
        .green, .cyan, .orange, .purple, .pink, .yellow, .mint, .indigo
    ]

    private static let inspectorLogTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static func layerColor(for layer: Int) -> Color {
        layerColors[layer % layerColors.count]
    }

    private static func inferTileIcon(for win: ScreenMapWindowEntry, displays: [DisplayGeometry]) -> String? {
        guard let disp = displays.first(where: { $0.index == win.displayIndex }) else { return nil }
        let screenW = disp.cgRect.width
        let screenH = disp.cgRect.height
        let relX = win.virtualFrame.origin.x - disp.cgRect.origin.x
        let relY = win.virtualFrame.origin.y - disp.cgRect.origin.y
        let winW = win.virtualFrame.width
        let winH = win.virtualFrame.height
        let tolerance: CGFloat = 30

        for pos in TilePosition.allCases {
            let (fx, fy, fw, fh) = pos.rect
            let expectedX = fx * screenW
            let expectedY = fy * screenH
            let expectedW = fw * screenW
            let expectedH = fh * screenH
            if abs(relX - expectedX) < tolerance && abs(relY - expectedY) < tolerance
                && abs(winW - expectedW) < tolerance && abs(winH - expectedH) < tolerance {
                return pos.icon
            }
        }
        return nil
    }

    private static func extractLatticesSession(from title: String) -> String? {
        guard let range = title.range(of: #"\[lattices:([^\]]+)\]"#, options: .regularExpression) else { return nil }
        let match = String(title[range])
        return String(match.dropFirst(9).dropLast(1))
    }

    // MARK: - Layer Preview

    private func handlePreviewChange(isPreviewing: Bool) {
        guard isPreviewing, let editor = controller.editor else { return }
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        let primaryHeight = screens.first?.frame.height ?? 0

        // Scope preview to the focused display's screen, or union of all
        let targetFrame: NSRect
        let cgOrigin: CGPoint
        if let focusedIdx = editor.focusedDisplayIndex, focusedIdx < screens.count {
            let screen = screens[focusedIdx]
            targetFrame = screen.frame
            cgOrigin = CGPoint(x: screen.frame.origin.x,
                               y: primaryHeight - screen.frame.maxY)
        } else {
            var union = screens[0].frame
            for screen in screens.dropFirst() { union = union.union(screen.frame) }
            targetFrame = union
            cgOrigin = CGPoint(x: union.origin.x,
                               y: primaryHeight - (union.origin.y + union.height))
        }

        let visible = editor.focusedVisibleWindows
        let label = editor.layerLabel
        let captures = controller.previewCaptures

        let overlay = ScreenMapPreviewOverlay(
            windows: visible, layerLabel: label, captures: captures,
            screenFrame: targetFrame,
            screenCGOrigin: cgOrigin
        )
        let hostingView = NSHostingView(rootView: overlay)
        controller.showPreviewWindow(contentView: hostingView, frame: targetFrame)
    }

    // MARK: - Key Handler

    private func installKeyHandler() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            // Only handle keys when our window is the key window
            guard let win = ScreenMapWindowController.shared.nsWindow,
                  win.isKeyWindow else { return event }
            if isEditableTextResponder(win.firstResponder) {
                return event
            }
            // Track space key for canvas drag-to-pan
            if event.keyCode == 49 && !controller.isSearchActive {
                if event.type == .keyDown && !event.isARepeat {
                    isSpaceHeld = true
                    NSCursor.openHand.push()
                    return nil
                } else if event.type == .keyUp {
                    isSpaceHeld = false
                    spaceDragStart = nil
                    NSCursor.pop()
                    return nil
                }
            }
            guard event.type == .keyDown else { return event }
            let consumed = controller.handleKey(event.keyCode, modifiers: event.modifierFlags)
            return consumed ? nil : event
        }
    }

    private func isEditableTextResponder(_ responder: NSResponder?) -> Bool {
        if let textView = responder as? NSTextView {
            return textView.isEditable || textView.isFieldEditor
        }

        if let textField = responder as? NSTextField {
            return textField.isEditable
        }

        guard let responder else { return false }
        let className = NSStringFromClass(type(of: responder))
        return className.contains("FieldEditor") || className.contains("TextView")
    }

    private func removeKeyHandler() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    // MARK: - Mouse Monitors

    private func installMouseMonitors() {
        let dragThreshold: CGFloat = 4

        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            guard let eventWindow = event.window,
                  eventWindow === ScreenMapWindowController.shared.nsWindow else { return event }

            // Space+click → begin canvas pan
            if isSpaceHeld, let editor = controller.editor {
                spaceDragStart = event.locationInWindow
                spaceDragPanStart = editor.panOffset
                NSCursor.closedHand.push()
                return nil
            }

            if let hitId = hoveredWindowId, let editor = controller.editor {
                screenMapClickWindowId = hitId
                screenMapClickPoint = event.locationInWindow
                let flippedPt = flippedScreenPoint(event)
                if let hit = screenMapHitTestWithRect(flippedScreenPt: flippedPt, editor: editor) {
                    editor.canvasDragMode = detectDragMode(mapPoint: hit.mapPoint, windowMapRect: hit.mapRect)
                } else {
                    editor.canvasDragMode = .move
                }
            } else {
                screenMapClickWindowId = nil
            }
            return event
        }

        mouseDragMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { event in
            // Space+drag → pan canvas
            if isSpaceHeld, let start = spaceDragStart, let editor = controller.editor {
                let dx = event.locationInWindow.x - start.x
                let dy = event.locationInWindow.y - start.y
                editor.activeViewportPreset = nil
                editor.panOffset = CGPoint(x: spaceDragPanStart.x + dx, y: spaceDragPanStart.y - dy)
                editor.objectWillChange.send()
                controller.objectWillChange.send()
                return nil
            }

            guard let hitId = screenMapClickWindowId,
                  let editor = controller.editor else { return event }
            let dx = event.locationInWindow.x - screenMapClickPoint.x
            let dy = event.locationInWindow.y - screenMapClickPoint.y
            guard sqrt(dx * dx + dy * dy) >= dragThreshold else { return event }

            if editor.draggingWindowId != hitId {
                editor.draggingWindowId = hitId
                if let idx = editor.windows.firstIndex(where: { $0.id == hitId }) {
                    editor.dragStartFrame = editor.windows[idx].virtualFrame
                }
                controller.selectSingle(hitId)
            }

            let effScale = editor.effectiveScale
            guard let startFrame = editor.dragStartFrame,
                  effScale > 0,
                  let idx = editor.windows.firstIndex(where: { $0.id == hitId }) else { return event }
            let screenDx = dx / effScale
            let screenDy = -dy / effScale  // CG coords: Y flipped
            let mode = editor.canvasDragMode
            let minW: CGFloat = 100
            let minH: CGFloat = 50

            var newFrame = startFrame

            switch mode {
            case .move:
                newFrame.origin.x = startFrame.origin.x + screenDx
                newFrame.origin.y = startFrame.origin.y + screenDy

            case .resizeRight:
                newFrame.size.width = max(minW, startFrame.width + screenDx)
            case .resizeLeft:
                let dw = min(screenDx, startFrame.width - minW)
                newFrame.origin.x = startFrame.origin.x + dw
                newFrame.size.width = startFrame.width - dw
            case .resizeBottom:
                newFrame.size.height = max(minH, startFrame.height + screenDy)
            case .resizeTop:
                let dh = min(screenDy, startFrame.height - minH)
                newFrame.origin.y = startFrame.origin.y + dh
                newFrame.size.height = startFrame.height - dh

            case .resizeTopLeft:
                let dw = min(screenDx, startFrame.width - minW)
                newFrame.origin.x = startFrame.origin.x + dw
                newFrame.size.width = startFrame.width - dw
                let dh = min(screenDy, startFrame.height - minH)
                newFrame.origin.y = startFrame.origin.y + dh
                newFrame.size.height = startFrame.height - dh
            case .resizeTopRight:
                newFrame.size.width = max(minW, startFrame.width + screenDx)
                let dh = min(screenDy, startFrame.height - minH)
                newFrame.origin.y = startFrame.origin.y + dh
                newFrame.size.height = startFrame.height - dh
            case .resizeBottomLeft:
                let dw = min(screenDx, startFrame.width - minW)
                newFrame.origin.x = startFrame.origin.x + dw
                newFrame.size.width = startFrame.width - dw
                newFrame.size.height = max(minH, startFrame.height + screenDy)
            case .resizeBottomRight:
                newFrame.size.width = max(minW, startFrame.width + screenDx)
                newFrame.size.height = max(minH, startFrame.height + screenDy)
            }

            editor.syncLayoutFrame(at: idx, to: newFrame)
            editor.objectWillChange.send()
            controller.objectWillChange.send()
            return nil
        }

        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { event in
            // End space+drag pan
            if spaceDragStart != nil {
                spaceDragStart = nil
                NSCursor.pop()  // pop closedHand, openHand remains
                return event
            }
            if screenMapClickWindowId != nil {
                if let editor = controller.editor, editor.draggingWindowId != nil {
                    editor.draggingWindowId = nil
                    editor.dragStartFrame = nil
                    editor.canvasDragMode = .move
                    editor.objectWillChange.send()
                }
                screenMapClickWindowId = nil
            }
            return event
        }

        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { event in
            guard let eventWindow = event.window,
                  eventWindow === ScreenMapWindowController.shared.nsWindow,
                  let editor = controller.editor else { return event }

            let flippedPt = flippedScreenPoint(event)
            let canvasRect = CGRect(origin: screenMapCanvasOrigin, size: screenMapCanvasSize)
            guard canvasRect.contains(flippedPt) else { return event }

            if let hitId = screenMapHitTest(flippedScreenPt: flippedPt, editor: editor) {
                if !controller.isSelected(hitId) {
                    controller.selectSingle(hitId)
                }
                showLayerContextMenu(for: hitId, at: event.locationInWindow, in: eventWindow, editor: editor)
                return nil
            }
            return event
        }

        scrollWheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard let eventWindow = event.window,
                  eventWindow === ScreenMapWindowController.shared.nsWindow,
                  let editor = controller.editor else { return event }

            // Let search overlay handle its own scroll
            if controller.isSearchActive {
                let screenPt = event.locationInWindow
                let windowPt = eventWindow.convertPoint(toScreen: screenPt)
                let flippedY = NSScreen.main.map { $0.frame.height - windowPt.y } ?? windowPt.y
                let testPt = CGPoint(x: windowPt.x, y: flippedY)
                if searchOverlayFrame.contains(testPt) {
                    return event  // pass to SwiftUI ScrollView
                }
            }

            let flippedPt = flippedScreenPoint(event)
            let canvasRect = CGRect(origin: screenMapCanvasOrigin, size: screenMapCanvasSize)
            guard canvasRect.contains(flippedPt) else { return event }

            let isZoom = event.modifierFlags.contains(.command) || !event.hasPreciseScrollingDeltas

            if isZoom {
                let zoomDelta: CGFloat = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.01 : event.scrollingDeltaY * 0.05
                let oldZoom = editor.zoomLevel
                let newZoom = max(ScreenMapEditorState.minZoom, min(ScreenMapEditorState.maxZoom, oldZoom + zoomDelta))
                guard newZoom != oldZoom else { return nil }

                let canvasLocal = CGPoint(
                    x: flippedPt.x - screenMapCanvasOrigin.x,
                    y: flippedPt.y - screenMapCanvasOrigin.y
                )
                let canvasCenterX = screenMapCanvasSize.width / 2
                let canvasCenterY = screenMapCanvasSize.height / 2
                let cursorFromCenter = CGPoint(
                    x: canvasLocal.x - canvasCenterX,
                    y: canvasLocal.y - canvasCenterY
                )

                let ratio = newZoom / oldZoom
                let newPanX = cursorFromCenter.x - ratio * (cursorFromCenter.x - editor.panOffset.x)
                let newPanY = cursorFromCenter.y - ratio * (cursorFromCenter.y - editor.panOffset.y)

                editor.activeViewportPreset = nil
                editor.zoomLevel = newZoom
                editor.panOffset = CGPoint(x: newPanX, y: newPanY)
                editor.objectWillChange.send()
                controller.objectWillChange.send()
            } else {
                editor.activeViewportPreset = nil
                editor.panOffset = CGPoint(
                    x: editor.panOffset.x + event.scrollingDeltaX,
                    y: editor.panOffset.y - event.scrollingDeltaY
                )
                editor.objectWillChange.send()
                controller.objectWillChange.send()
            }
            return nil
        }

        mouseMovedMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { event in
            guard let eventWindow = event.window,
                  eventWindow === ScreenMapWindowController.shared.nsWindow,
                  let editor = controller.editor else {
                resetCursorIfNeeded()
                return event
            }

            let flippedPt = flippedScreenPoint(event)
            let canvasRect = CGRect(origin: screenMapCanvasOrigin, size: screenMapCanvasSize)
            guard canvasRect.contains(flippedPt) else {
                resetCursorIfNeeded()
                return event
            }

            if let hit = screenMapHitTestWithRect(flippedScreenPt: flippedPt, editor: editor) {
                let mode = detectDragMode(mapPoint: hit.mapPoint, windowMapRect: hit.mapRect)
                if mode != editor.currentCursorMode {
                    if editor.currentCursorMode != .move { NSCursor.pop() }
                    editor.currentCursorMode = mode
                    switch mode {
                    case .resizeLeft, .resizeRight:
                        NSCursor.resizeLeftRight.push()
                    case .resizeTop, .resizeBottom:
                        NSCursor.resizeUpDown.push()
                    case .resizeTopLeft, .resizeTopRight, .resizeBottomLeft, .resizeBottomRight:
                        NSCursor.crosshair.push()
                    case .move:
                        break
                    }
                }
            } else {
                resetCursorIfNeeded()
            }
            return event
        }
    }

    private func resetCursorIfNeeded() {
        guard let editor = controller.editor else { return }
        if editor.currentCursorMode != .move {
            NSCursor.pop()
            editor.currentCursorMode = .move
        }
    }

    private func removeMouseMonitors() {
        if let m = mouseDownMonitor { NSEvent.removeMonitor(m); mouseDownMonitor = nil }
        if let m = mouseDragMonitor { NSEvent.removeMonitor(m); mouseDragMonitor = nil }
        if let m = mouseUpMonitor { NSEvent.removeMonitor(m); mouseUpMonitor = nil }
        if let m = rightClickMonitor { NSEvent.removeMonitor(m); rightClickMonitor = nil }
        if let m = scrollWheelMonitor { NSEvent.removeMonitor(m); scrollWheelMonitor = nil }
        if let m = mouseMovedMonitor { NSEvent.removeMonitor(m); mouseMovedMonitor = nil }
        resetCursorIfNeeded()
    }

    // MARK: - Hit Test / Coordinate Conversion

    private func screenMapHitTest(flippedScreenPt: CGPoint, editor: ScreenMapEditorState) -> UInt32? {
        let effScale = editor.effectiveScale
        let origin = editor.mapOrigin
        let panOffset = editor.panOffset
        guard effScale > 0 else { return nil }

        let canvasLocal = CGPoint(
            x: flippedScreenPt.x - screenMapCanvasOrigin.x,
            y: flippedScreenPt.y - screenMapCanvasOrigin.y
        )
        let mapPoint = CGPoint(
            x: canvasLocal.x - 8 - origin.x - panOffset.x,
            y: canvasLocal.y - 8 - origin.y - panOffset.y
        )

        let bboxOrig = editor.bboxOrigin
        let windowPool = editor.focusedDisplayIndex != nil ? editor.focusedVisibleWindows : editor.windows
        let sorted = windowPool.sorted(by: { $0.zIndex < $1.zIndex })
        for win in sorted {
            let f = win.virtualFrame
            let mapRect = CGRect(
                x: (f.origin.x - bboxOrig.x) * effScale,
                y: (f.origin.y - bboxOrig.y) * effScale,
                width: max(f.width * effScale, 4),
                height: max(f.height * effScale, 4)
            )
            if mapRect.contains(mapPoint) { return win.id }
        }
        return nil
    }

    private func screenMapHitTestWithRect(flippedScreenPt: CGPoint, editor: ScreenMapEditorState) -> (id: UInt32, mapRect: CGRect, mapPoint: CGPoint)? {
        let effScale = editor.effectiveScale
        let origin = editor.mapOrigin
        let panOff = editor.panOffset
        guard effScale > 0 else { return nil }

        let canvasLocal = CGPoint(
            x: flippedScreenPt.x - screenMapCanvasOrigin.x,
            y: flippedScreenPt.y - screenMapCanvasOrigin.y
        )
        let mapPoint = CGPoint(
            x: canvasLocal.x - 8 - origin.x - panOff.x,
            y: canvasLocal.y - 8 - origin.y - panOff.y
        )

        let bboxOrig = editor.bboxOrigin
        let windowPool = editor.focusedDisplayIndex != nil ? editor.focusedVisibleWindows : editor.windows
        let sorted = windowPool.sorted(by: { $0.zIndex < $1.zIndex })
        for win in sorted {
            let f = win.virtualFrame
            let mapRect = CGRect(
                x: (f.origin.x - bboxOrig.x) * effScale,
                y: (f.origin.y - bboxOrig.y) * effScale,
                width: max(f.width * effScale, 4),
                height: max(f.height * effScale, 4)
            )
            if mapRect.contains(mapPoint) { return (win.id, mapRect, mapPoint) }
        }
        return nil
    }

    private func detectDragMode(mapPoint: CGPoint, windowMapRect: CGRect) -> CanvasDragMode {
        let w = windowMapRect.width
        let h = windowMapRect.height
        let threshold = max(4, min(8, min(w, h) * 0.25))

        let nearLeft   = mapPoint.x - windowMapRect.minX < threshold
        let nearRight  = windowMapRect.maxX - mapPoint.x < threshold
        let nearTop    = mapPoint.y - windowMapRect.minY < threshold
        let nearBottom = windowMapRect.maxY - mapPoint.y < threshold

        // Corners take priority
        if nearTop && nearLeft     { return .resizeTopLeft }
        if nearTop && nearRight    { return .resizeTopRight }
        if nearBottom && nearLeft  { return .resizeBottomLeft }
        if nearBottom && nearRight { return .resizeBottomRight }

        // Edges
        if nearLeft   { return .resizeLeft }
        if nearRight  { return .resizeRight }
        if nearTop    { return .resizeTop }
        if nearBottom { return .resizeBottom }

        return .move
    }

    private func flippedScreenPoint(_ event: NSEvent) -> CGPoint {
        guard let nsWindow = event.window else { return .zero }
        let loc = event.locationInWindow
        let windowHeight = nsWindow.contentView?.frame.height ?? nsWindow.frame.height
        return CGPoint(x: loc.x, y: windowHeight - loc.y)
    }

    // MARK: - Context Menu

    private func showLayerContextMenu(for windowId: UInt32, at point: NSPoint, in window: NSWindow, editor: ScreenMapEditorState) {
        guard let winIdx = editor.windows.firstIndex(where: { $0.id == windowId }) else { return }
        let win = editor.windows[winIdx]
        let currentLayer = win.layer

        let menu = NSMenu()
        let header = NSMenuItem(title: "\(win.app) — Layer \(currentLayer)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        // Focus window on screen
        let focusItem = NSMenuItem(title: "Show on Screen  ⌘↩", action: nil, keyEquivalent: "")
        focusItem.representedObject = ScreenMapFocusMenuAction(windowId: windowId, controller: controller)
        focusItem.action = #selector(ScreenMapMenuTarget.performFocus(_:))
        focusItem.target = ScreenMapMenuTarget.shared
        menu.addItem(focusItem)

        menu.addItem(.separator())

        // Move to Layer → submenu
        let moveItem = NSMenuItem(title: "Move to Layer", action: nil, keyEquivalent: "")
        let layerSubmenu = NSMenu()

        for layer in editor.effectiveLayers where layer != currentLayer {
            let name = editor.layerDisplayName(for: layer)
            let count = editor.effectiveWindowCount(for: layer)
            let item = NSMenuItem(title: "\(name) (\(count) windows)", action: nil, keyEquivalent: "")
            item.representedObject = ScreenMapLayerMenuAction(windowId: windowId, targetLayer: layer, editor: editor, controller: controller)
            item.action = #selector(ScreenMapMenuTarget.performLayerMove(_:))
            item.target = ScreenMapMenuTarget.shared
            layerSubmenu.addItem(item)
        }

        layerSubmenu.addItem(.separator())
        let newLayerItem = NSMenuItem(title: "New Layer", action: nil, keyEquivalent: "")
        newLayerItem.representedObject = ScreenMapLayerMenuAction(windowId: windowId, targetLayer: editor.layerCount, editor: editor, controller: controller)
        newLayerItem.action = #selector(ScreenMapMenuTarget.performLayerMove(_:))
        newLayerItem.target = ScreenMapMenuTarget.shared
        layerSubmenu.addItem(newLayerItem)

        moveItem.submenu = layerSubmenu
        menu.addItem(moveItem)

        // Convert window coordinates to contentView coordinates for correct menu positioning
        let menuPoint: NSPoint
        if let contentView = window.contentView {
            menuPoint = contentView.convert(point, from: nil)
        } else {
            menuPoint = point
        }
        menu.popUp(positioning: nil, at: menuPoint, in: window.contentView)
    }
}

// MARK: - Context Menu Helpers

struct ScreenMapLayerMenuAction {
    let windowId: UInt32
    let targetLayer: Int
    let editor: ScreenMapEditorState
    let controller: ScreenMapController
}

struct ScreenMapFocusMenuAction {
    let windowId: UInt32
    let controller: ScreenMapController
}

final class ScreenMapMenuTarget: NSObject {
    static let shared = ScreenMapMenuTarget()

    @objc func performLayerMove(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? ScreenMapLayerMenuAction else { return }
        action.editor.reassignLayer(windowId: action.windowId, toLayer: action.targetLayer, fitToAvailable: true)
        action.controller.objectWillChange.send()
    }

    @objc func performFocus(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? ScreenMapFocusMenuAction else { return }
        action.controller.focusWindowOnScreen(action.windowId)
    }
}

// MARK: - Preview Overlay

struct ScreenMapPreviewOverlay: View {
    let windows: [ScreenMapWindowEntry]
    let layerLabel: String
    let captures: [UInt32: NSImage]
    let screenFrame: CGRect
    let screenCGOrigin: CGPoint

    private static let layerColors: [Color] = [
        .green, .cyan, .orange, .purple, .pink, .yellow, .mint, .indigo
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.88)

            ForEach(windows) { win in
                let f = win.virtualFrame
                let x = f.origin.x - screenCGOrigin.x
                let y = f.origin.y - screenCGOrigin.y
                let w = f.width
                let h = f.height
                let color = Self.layerColors[win.layer % Self.layerColors.count]

                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(color.opacity(0.12))
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(color.opacity(0.7), lineWidth: 2)

                    VStack(spacing: 4) {
                        Text(win.app)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        if !win.title.isEmpty && h > 60 {
                            Text(win.title)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                        if h > 40 {
                            Text("\(Int(w)) × \(Int(h))")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(color.opacity(0.7))
                        }
                        if win.hasEdits && h > 80 {
                            Text("L\(win.layer)")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(color.opacity(0.5))
                        }
                    }
                    .padding(8)
                }
                .shadow(color: color.opacity(0.3), radius: 8)
                .frame(width: w, height: h)
                .offset(x: x, y: y)
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text("\(layerLabel)  •  \(windows.count) windows  •  click or press any key to dismiss")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(8)
                        .padding(20)
                    Spacer()
                }
            }
        }
        .frame(width: screenFrame.width, height: screenFrame.height)
    }
}

// MARK: - Layer Row Frame Preference Key

private struct LayerRowFrameKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

// MARK: - Show on Screen Bezel

struct ShowOnScreenBezelView: View {
    let appName: String
    let windowTitle: String
    let displayName: String
    let displayNumber: Int
    let layerName: String
    let windowSize: String
    let windowsOnDisplay: Int
    let layersOnDisplay: Int
    let windowLocalFrame: CGRect  // NS coordinates relative to tight window
    let screenSize: CGSize        // tight window size (not full screen)
    let labelPlacement: LabelPlacement
    let flush: FlushEdges
    let windowSnapshot: NSImage?  // pre-captured window content for screenshot tools

    enum LabelPlacement { case below, above, right, left }

    /// Which edges of the window are flush with the screen boundary
    struct FlushEdges {
        let top: Bool
        let bottom: Bool
        let left: Bool
        let right: Bool
        static let none = FlushEdges(top: false, bottom: false, left: false, right: false)
    }

    // Inverted from OS appearance so bezel contrasts with desktop:
    // Dark mode desktop → light bezel, Light mode desktop → dark bezel
    @Environment(\.colorScheme) private var colorScheme

    private let accent = Color(red: 0.13, green: 0.62, blue: 0.38)

    private var bg: Color {
        colorScheme == .dark
            ? Color(red: 0.92, green: 0.92, blue: 0.93)
            : Color(red: 0.16, green: 0.16, blue: 0.18)
    }
    private var textPrimary: Color {
        colorScheme == .dark
            ? Color(red: 0.10, green: 0.10, blue: 0.12)
            : Color(red: 0.95, green: 0.95, blue: 0.97)
    }
    private var textSecondary: Color {
        colorScheme == .dark
            ? Color(red: 0.35, green: 0.35, blue: 0.38)
            : Color(red: 0.68, green: 0.68, blue: 0.72)
    }
    private var textTertiary: Color {
        colorScheme == .dark
            ? Color(red: 0.55, green: 0.55, blue: 0.58)
            : Color(red: 0.48, green: 0.48, blue: 0.52)
    }

    // ZStack uses top-left origin; convert from NS bottom-left
    private var winX: CGFloat { windowLocalFrame.origin.x }
    private var winY: CGFloat { screenSize.height - windowLocalFrame.origin.y - windowLocalFrame.height }
    private var winW: CGFloat { windowLocalFrame.width }
    private var winH: CGFloat { windowLocalFrame.height }

    // Frame dimensions
    private let edge: CGFloat = 5           // border thickness on non-flush edges
    private let shelfHeight: CGFloat = 40   // info shelf thickness
    private let cornerR: CGFloat = 10       // matches macOS window corners

    // Edge insets: 0 on flush edges, `edge` on free edges
    private var insetTop: CGFloat    { flush.top ? 0 : edge }
    private var insetBottom: CGFloat { flush.bottom ? 0 : edge }
    private var insetLeft: CGFloat   { flush.left ? 0 : edge }
    private var insetRight: CGFloat  { flush.right ? 0 : edge }

    // Corner radii: 0 if either adjacent edge is flush
    private var rTL: CGFloat { (flush.top || flush.left) ? 0 : cornerR }
    private var rTR: CGFloat { (flush.top || flush.right) ? 0 : cornerR }
    private var rBL: CGFloat { (flush.bottom || flush.left) ? 0 : cornerR }
    private var rBR: CGFloat { (flush.bottom || flush.right) ? 0 : cornerR }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            // Frame origin and size, accounting for flush edges and shelf placement
            let frameX = winX - insetLeft + shelfOffsetX
            let frameY = winY - insetTop + shelfOffsetY
            let frameW = winW + insetLeft + insetRight + shelfExtraW
            let frameH = winH + insetTop + insetBottom + shelfExtraH

            // Adjust corner radii for shelf side
            let finalTL = adjustedCornerRadius(rTL, forShelf: labelPlacement, corner: .topLeft)
            let finalTR = adjustedCornerRadius(rTR, forShelf: labelPlacement, corner: .topRight)
            let finalBL = adjustedCornerRadius(rBL, forShelf: labelPlacement, corner: .bottomLeft)
            let finalBR = adjustedCornerRadius(rBR, forShelf: labelPlacement, corner: .bottomRight)

            UnevenRoundedRectangle(
                topLeadingRadius: finalTL,
                bottomLeadingRadius: finalBL,
                bottomTrailingRadius: finalBR,
                topTrailingRadius: finalTR
            )
                .fill(bg)
                .frame(width: frameW, height: frameH)
                .offset(x: frameX, y: frameY)

            // Window snapshot — baked into the bezel so screenshot tools get the full composite
            if let snapshot = windowSnapshot {
                Image(nsImage: snapshot)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: winW, height: winH)
                    .clipped()
                    .offset(x: winX, y: winY)
            }

            // Shelf content
            switch labelPlacement {
            case .below:
                shelfContent
                    .frame(width: winW + insetLeft + insetRight - 8, height: shelfHeight - 4)
                    .offset(x: winX - insetLeft + 4, y: winY + winH + insetBottom)
            case .above:
                shelfContent
                    .frame(width: winW + insetLeft + insetRight - 8, height: shelfHeight - 4)
                    .offset(x: winX - insetLeft + 4, y: winY - insetTop - shelfHeight + 4)
            case .right:
                sideShelfContent
                    .frame(width: 190, height: winH + insetTop + insetBottom)
                    .offset(x: winX + winW + insetRight + 4, y: winY - insetTop)
            case .left:
                sideShelfContent
                    .frame(width: 190, height: winH + insetTop + insetBottom)
                    .offset(x: winX - insetLeft - 194, y: winY - insetTop)
            }
        }
        .frame(width: screenSize.width, height: screenSize.height)
    }

    // MARK: - Shelf geometry helpers

    /// How much extra width/height the shelf adds to the frame
    private var shelfExtraW: CGFloat {
        switch labelPlacement {
        case .below, .above: return 0
        case .right, .left: return 200
        }
    }
    private var shelfExtraH: CGFloat {
        switch labelPlacement {
        case .below, .above: return shelfHeight
        case .right, .left: return 0
        }
    }

    /// Offset the frame origin for shelf on top/left
    private var shelfOffsetX: CGFloat {
        labelPlacement == .left ? -200 : 0
    }
    private var shelfOffsetY: CGFloat {
        labelPlacement == .above ? -shelfHeight : 0
    }

    private enum Corner { case topLeft, topRight, bottomLeft, bottomRight }

    /// Ensure the shelf-side corners are rounded even if the window edge is flush there
    private func adjustedCornerRadius(_ base: CGFloat, forShelf shelf: LabelPlacement, corner: Corner) -> CGFloat {
        // The shelf extends outward from the window, so its outer corners should be rounded
        switch (shelf, corner) {
        case (.below, .bottomLeft), (.below, .bottomRight):
            return cornerR
        case (.above, .topLeft), (.above, .topRight):
            return cornerR
        case (.right, .topRight), (.right, .bottomRight):
            return cornerR
        case (.left, .topLeft), (.left, .bottomLeft):
            return cornerR
        default:
            return base
        }
    }

    // MARK: - Horizontal shelf (bottom / top)

    private var shelfContent: some View {
        HStack(spacing: 8) {
            // App name — distinctive rounded font
            Text(appName)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(textPrimary)
                .lineLimit(1)

            if !windowTitle.isEmpty {
                Text("·")
                    .foregroundColor(textTertiary)
                Text(windowTitle)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer()
            }

            bezelTag(layerName, color: accent)
            bezelTag(windowSize, color: textSecondary)

            // Display badge
            HStack(spacing: 3) {
                Image(systemName: "display")
                    .font(.system(size: 9))
                    .foregroundColor(textTertiary)
                Text("\(displayNumber)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(textSecondary)
            }
        }
        .padding(.horizontal, 10)
    }

    // MARK: - Side shelf (right)

    private var sideShelfContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(appName)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(textPrimary)
                .lineLimit(1)
            if !windowTitle.isEmpty {
                Text(windowTitle)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(textSecondary)
                    .lineLimit(2)
            }
            HStack(spacing: 6) {
                bezelTag(layerName, color: accent)
                bezelTag(windowSize, color: textSecondary)
            }
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "display")
                    .font(.system(size: 9))
                    .foregroundColor(textTertiary)
                Text("\(displayNumber)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(textSecondary)
                Text(displayName)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(8)
    }

    // MARK: - Helpers

    private func bezelTag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(color.opacity(0.15), lineWidth: 0.5)
                    )
            )
    }
}

// MARK: - Preference Keys

private struct SearchOverlayFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
