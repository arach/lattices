import SwiftUI
import AppKit

// MARK: - Screen Map View (Standalone)

struct ScreenMapView: View {
    @ObservedObject var controller: ScreenMapController
    @ObservedObject private var daemon = DaemonServer.shared
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

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if let editor = controller.editor {
                    layerSidebar(editor: editor)
                    Rectangle()
                        .fill(Palette.border)
                        .frame(width: 0.5)
                }
                VStack(spacing: 0) {
                    screenMapCanvas(editor: controller.editor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    actionShelf
                }
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
                controller.objectWillChange.send()
            } label: {
                displayToolbarPill(name: "All", isActive: editor.focusedDisplayIndex == nil)
            }
            .buttonStyle(.plain)

            ForEach(Array(editor.spatialDisplayOrder.enumerated()), id: \.element.index) { spatialPos, disp in
                let isActive = editor.focusedDisplayIndex == disp.index
                Button {
                    editor.focusDisplay(disp.index)
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

                if let focused = editor.focusedDisplay {
                    Text("·")
                        .foregroundColor(Palette.textMuted)
                    Text(focused.label)
                        .font(Typo.mono(8))
                        .foregroundColor(Palette.textMuted)
                        .lineLimit(1)
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
                        let layerWindows = layerWindowsForTree(editor: editor, layer: layer)

                        VStack(spacing: 0) {
                            layerTreeHeader(label: fullName ?? displayName,
                                            count: layerWindows.count,
                                            isActive: isActive,
                                            color: color) {
                                if NSEvent.modifierFlags.contains(.command) {
                                    editor.toggleLayerSelection(layer)
                                } else {
                                    editor.selectLayer(layer)
                                }
                                controller.objectWillChange.send()
                            }

                            // Window children (shown when layer is active)
                            if isActive && !editor.isShowingAll {
                                VStack(spacing: 0) {
                                    ForEach(layerWindows) { win in
                                        let isSelected = controller.selectedWindowIds.contains(win.id)
                                        Button {
                                            if NSEvent.modifierFlags.contains(.command) {
                                                controller.toggleSelection(win.id)
                                            } else {
                                                controller.selectSingle(win.id)
                                            }
                                        } label: {
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
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.leading, 4)
                                .padding(.top, 2)
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 8)
            sidebarMiniMap(editor: editor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(width: 180)
    }

    private func layerWindowsForTree(editor: ScreenMapEditorState, layer: Int) -> [ScreenMapWindowEntry] {
        var wins = editor.windows.filter { $0.layer == layer }
        if let dIdx = editor.focusedDisplayIndex {
            wins = wins.filter { $0.displayIndex == dIdx }
        }
        return wins.sorted { $0.zIndex < $1.zIndex }
    }

    private func layerTreeHeader(label: String, count: Int, isActive: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? color.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                if let focused = editor?.focusedDisplay {
                    return focused.cgRect
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
                cacheGeometry(editor: editor, fitScale: fitScale, scale: effScale,
                              offsetX: centerX, offsetY: centerY,
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
                cacheGeometry(editor: editor, fitScale: newFitScale, scale: newEffScale,
                              offsetX: newCX, offsetY: newCY,
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

            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(Palette.running.opacity(0.5))
                        .frame(width: 18, height: 18)
                    Text("\(editor.spatialNumber(for: focused.index))")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                Text(focused.label)
                    .font(Typo.monoBold(11))
                    .foregroundColor(Palette.running.opacity(0.7))
                    .lineLimit(1)
                Text("\(Int(focused.cgRect.width))×\(Int(focused.cgRect.height))")
                    .font(Typo.mono(9))
                    .foregroundColor(Color.white.opacity(0.25))
            }
            .padding(.top, 6)
            .padding(.leading, 8)
        }
        .frame(width: mapW, height: mapH)
    }

    private func multiDisplayBackgrounds(displays: [DisplayGeometry], editor: ScreenMapEditorState?, effScale: CGFloat, bboxOrigin: CGPoint) -> some View {
        ForEach(displays, id: \.index) { disp in
            let dx = (disp.cgRect.origin.x - bboxOrigin.x) * effScale
            let dy = (disp.cgRect.origin.y - bboxOrigin.y) * effScale
            let dw = disp.cgRect.width * effScale
            let dh = disp.cgRect.height * effScale
            let resLabel = "\(Int(disp.cgRect.width))×\(Int(disp.cgRect.height))"
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

                VStack {
                    HStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.4))
                                .frame(width: 18, height: 18)
                            Text("\(editor?.spatialNumber(for: disp.index) ?? (disp.index + 1))")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.black)
                        }
                        Text(disp.label)
                            .font(Typo.monoBold(11))
                            .foregroundColor(Color.white.opacity(0.65))
                            .lineLimit(1)
                        Spacer()
                        Text(resLabel)
                            .font(Typo.mono(9))
                            .foregroundColor(Color.white.opacity(0.35))
                    }
                    .padding(.top, bezel + 6)
                    .padding(.horizontal, bezel + 6)
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

            if let disp = displays.first {
                HStack(spacing: 6) {
                    Text(disp.label)
                        .font(Typo.monoBold(11))
                        .foregroundColor(Color.white.opacity(0.4))
                        .lineLimit(1)
                    Text("\(Int(disp.cgRect.width))×\(Int(disp.cgRect.height))")
                        .font(Typo.mono(9))
                        .foregroundColor(Color.white.opacity(0.25))
                }
                .padding(.top, 6)
                .padding(.leading, 8)
            }
        }
        .frame(width: mapW, height: mapH)
    }

    // MARK: - Window Tile

    @ViewBuilder
    private func windowTile(win: ScreenMapWindowEntry, editor: ScreenMapEditorState?, scale: CGFloat, bboxOrigin: CGPoint = .zero) -> some View {
        let f = win.editedFrame
        let x = (f.origin.x - bboxOrigin.x) * scale
        let y = (f.origin.y - bboxOrigin.y) * scale
        let w = max(f.width * scale, 4)
        let h = max(f.height * scale, 4)
        let isSelected = controller.selectedWindowIds.contains(win.id)
        let isDragging = editor?.draggingWindowId == win.id
        let isInActiveLayer = editor?.isLayerSelected(win.layer) ?? true
        let winLayerColor = Self.layerColor(for: win.layer)

        let fillColor = isSelected
            ? Palette.running.opacity(0.18)
            : win.hasEdits ? Color.orange.opacity(0.12) : Palette.surface.opacity(0.7)
        let borderColor = isSelected
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
                        .strokeBorder(borderColor, lineWidth: isSelected ? 1.5 : 0.5)
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
                                Text("\(Int(win.originalFrame.width))x\(Int(win.originalFrame.height))")
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

                        if h > 50, let session = Self.extractLatticeSession(from: win.title) {
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
        .onHover { isHovering in
            hoveredWindowId = isHovering ? win.id : (hoveredWindowId == win.id ? nil : hoveredWindowId)
        }
        .offset(x: x, y: y)
        .opacity(isInActiveLayer ? 1.0 : 0.3)
        .shadow(color: isDragging ? Palette.running.opacity(0.4) : .clear,
                radius: isDragging ? 6 : 0)
    }

    // MARK: - Action Shelf

    private static let shelfGreen = Color(red: 0.18, green: 0.82, blue: 0.48)

    private var actionShelf: some View {
        let actions: [(key: String, label: String, action: () -> Void)] = [
            ("d", "spread", { [controller] in controller.smartSpreadLayer() }),
            ("e", "expose", { [controller] in controller.exposeLayer() }),
            ("t", "tile", { [controller] in controller.tileLayer() }),
            ("g", "distribute", { [controller] in controller.distributeVisible() }),
            ("c", "merge", { [controller] in controller.consolidateLayers() }),
            ("f", "flatten", { [controller] in controller.flattenLayers() }),
            ("v", "preview", { [controller] in controller.previewLayer() }),
        ]

        return VStack(spacing: 0) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)
            shelfButtonRow(actions)

            // Zoom indicator row
            if let editor = controller.editor,
               (editor.zoomLevel != 1.0 || editor.panOffset != .zero) {
                Rectangle().fill(Color.white.opacity(0.04)).frame(height: 0.5)
                Button {
                    editor.resetZoomPan()
                    controller.flash("Fit all")
                } label: {
                    HStack(spacing: 6) {
                        Text("\(Int(editor.zoomLevel * 100))%")
                            .font(Typo.monoBold(9))
                            .foregroundColor(Palette.textDim)
                        Text("0")
                            .font(Typo.monoBold(8))
                            .foregroundColor(Self.shelfGreen)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 2).fill(Self.shelfGreen.opacity(0.15)))
                        Text("fit all")
                            .font(Typo.mono(8))
                            .foregroundColor(Palette.textDim)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
            }

            // Ref badge row
            if let editor = controller.editor, let ref = editor.lastActionRef {
                Rectangle().fill(Color.white.opacity(0.04)).frame(height: 0.5)
                Button {
                    if let json = editor.actionLog.lastEntryJSON() {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(json, forType: .string)
                        controller.flash("Copied \(ref) to clipboard")
                    }
                } label: {
                    Text(ref)
                        .font(Typo.monoBold(9))
                        .foregroundColor(Self.shelfGreen)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
            }
        }
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Footer Bar

    // MARK: - Status Bar

    private var footerBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Palette.borderLit).frame(height: 0.5)
            HStack(spacing: 0) {
                // Left: server health
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
                }

                // Center: pending edits status
                Spacer()
                if let editor = controller.editor {
                    if editor.pendingEditCount > 0 {
                        chordHint(key: "↩", label: "\(editor.pendingEditCount) pending")
                    }
                    if editor.isPreviewing {
                        HStack(spacing: 4) {
                            Image(systemName: "eye")
                                .font(.system(size: 9))
                            Text("Preview")
                                .font(Typo.monoBold(9))
                        }
                        .foregroundColor(Color.purple)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.purple.opacity(0.12))
                        )
                    }
                }
                Spacer()

                // Right: logs + docs + settings
                HStack(spacing: 10) {
                    statusBarButton(icon: "text.alignleft", label: "Logs") {
                        DiagnosticWindow.shared.toggle()
                    }
                    statusBarButton(icon: "book", label: "Docs") {
                        if let url = URL(string: "https://lattice.arach.dev/docs") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    statusBarButton(icon: "gearshape", label: "Settings") {
                        SettingsWindow.open(prefs: Preferences.shared, scanner: ProjectScanner.shared)
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

    private func shelfButtonRow(_ actions: [(key: String, label: String, action: () -> Void)]) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(actions.enumerated()), id: \.offset) { _, item in
                let isHovered = hoveredShelfAction == item.key
                Button(action: item.action) {
                    HStack(spacing: 5) {
                        Text(item.key)
                            .font(Typo.monoBold(9))
                            .foregroundColor(Self.shelfGreen)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Self.shelfGreen.opacity(0.10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 3)
                                            .strokeBorder(Self.shelfGreen.opacity(0.2), lineWidth: 0.5)
                                    )
                            )
                        Text(item.label)
                            .font(Typo.mono(9))
                            .foregroundColor(isHovered ? Palette.text : Palette.textDim)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isHovered ? Palette.surfaceHov : Palette.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(isHovered ? Palette.borderLit : Palette.border, lineWidth: 0.5)
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { h in
                    hoveredShelfAction = h ? item.key : (hoveredShelfAction == item.key ? nil : hoveredShelfAction)
                    if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
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

        if displays.count > 1 {
            let union: CGRect = {
                var u = displays[0].cgRect
                for d in displays.dropFirst() { u = u.union(d.cgRect) }
                return u
            }()
            let miniW: CGFloat = 164
            let miniH: CGFloat = miniW * (union.height / max(union.width, 1))
            let scale = miniW / max(union.width, 1)

            VStack(spacing: 4) {
                ZStack(alignment: .topLeading) {
                    ForEach(displays, id: \.index) { disp in
                        let isFocused = editor.focusedDisplayIndex == disp.index
                        let dx = (disp.cgRect.origin.x - union.origin.x) * scale
                        let dy = (disp.cgRect.origin.y - union.origin.y) * scale
                        let dw = disp.cgRect.width * scale
                        let dh = disp.cgRect.height * scale

                        Button {
                            editor.focusDisplay(disp.index)
                            controller.objectWillChange.send()
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(isFocused ? Palette.running.opacity(0.15) : Color.white.opacity(0.06))
                                RoundedRectangle(cornerRadius: 2)
                                    .strokeBorder(isFocused ? Palette.running.opacity(0.7) : Color.white.opacity(0.15), lineWidth: isFocused ? 1.5 : 0.5)
                                Text("\(editor.spatialNumber(for: disp.index))")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundColor(isFocused ? Palette.running : Color.white.opacity(0.35))
                            }
                            .frame(width: dw, height: dh)
                        }
                        .buttonStyle(.plain)
                        .offset(x: dx, y: dy)
                    }
                }
                .frame(width: miniW, height: miniH)
                .clipped()

                Button {
                    editor.focusDisplay(nil)
                    controller.objectWillChange.send()
                } label: {
                    Text("ALL")
                        .font(Typo.monoBold(7))
                        .foregroundColor(editor.focusedDisplayIndex == nil ? Palette.running : Palette.textDim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
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

    private func cacheGeometry(editor: ScreenMapEditorState?, fitScale: CGFloat? = nil, scale: CGFloat,
                               offsetX: CGFloat, offsetY: CGFloat,
                               screenSize: CGSize, bboxOrigin: CGPoint = .zero) {
        if let fs = fitScale { editor?.fitScale = fs }
        editor?.scale = scale
        editor?.mapOrigin = CGPoint(x: offsetX, y: offsetY)
        editor?.screenSize = screenSize
        editor?.bboxOrigin = bboxOrigin
    }

    // MARK: - Layer Colors

    private static let layerColors: [Color] = [
        .green, .cyan, .orange, .purple, .pink, .yellow, .mint, .indigo
    ]

    private static func layerColor(for layer: Int) -> Color {
        layerColors[layer % layerColors.count]
    }

    private static func inferTileIcon(for win: ScreenMapWindowEntry, displays: [DisplayGeometry]) -> String? {
        guard let disp = displays.first(where: { $0.index == win.displayIndex }) else { return nil }
        let screenW = disp.cgRect.width
        let screenH = disp.cgRect.height
        let relX = win.originalFrame.origin.x - disp.cgRect.origin.x
        let relY = win.originalFrame.origin.y - disp.cgRect.origin.y
        let winW = win.originalFrame.width
        let winH = win.originalFrame.height
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

    private static func extractLatticeSession(from title: String) -> String? {
        guard let range = title.range(of: #"\[lattice:([^\]]+)\]"#, options: .regularExpression) else { return nil }
        let match = String(title[range])
        return String(match.dropFirst(8).dropLast(1))
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
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let consumed = controller.handleKey(event.keyCode, modifiers: event.modifierFlags)
            return consumed ? nil : event
        }
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

            if let hitId = hoveredWindowId {
                screenMapClickWindowId = hitId
                screenMapClickPoint = event.locationInWindow
            } else {
                screenMapClickWindowId = nil
            }
            return event
        }

        mouseDragMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { event in
            guard let hitId = screenMapClickWindowId,
                  let editor = controller.editor else { return event }
            let dx = event.locationInWindow.x - screenMapClickPoint.x
            let dy = event.locationInWindow.y - screenMapClickPoint.y
            guard sqrt(dx * dx + dy * dy) >= dragThreshold else { return event }

            if editor.draggingWindowId != hitId {
                editor.draggingWindowId = hitId
                if let idx = editor.windows.firstIndex(where: { $0.id == hitId }) {
                    editor.dragStartFrame = editor.windows[idx].editedFrame
                }
                controller.selectSingle(hitId)
            }

            let effScale = editor.effectiveScale
            guard let startFrame = editor.dragStartFrame,
                  effScale > 0,
                  let idx = editor.windows.firstIndex(where: { $0.id == hitId }) else { return event }
            let screenDx = dx / effScale
            let screenDy = -dy / effScale
            editor.windows[idx].editedFrame.origin = CGPoint(
                x: startFrame.origin.x + screenDx,
                y: startFrame.origin.y + screenDy
            )
            editor.objectWillChange.send()
            controller.objectWillChange.send()
            return nil
        }

        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { event in
            if screenMapClickWindowId != nil {
                if let editor = controller.editor, editor.draggingWindowId != nil {
                    editor.draggingWindowId = nil
                    editor.dragStartFrame = nil
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

                editor.zoomLevel = newZoom
                editor.panOffset = CGPoint(x: newPanX, y: newPanY)
                editor.objectWillChange.send()
                controller.objectWillChange.send()
            } else {
                editor.panOffset = CGPoint(
                    x: editor.panOffset.x + event.scrollingDeltaX,
                    y: editor.panOffset.y - event.scrollingDeltaY
                )
                editor.objectWillChange.send()
                controller.objectWillChange.send()
            }
            return nil
        }
    }

    private func removeMouseMonitors() {
        if let m = mouseDownMonitor { NSEvent.removeMonitor(m); mouseDownMonitor = nil }
        if let m = mouseDragMonitor { NSEvent.removeMonitor(m); mouseDragMonitor = nil }
        if let m = mouseUpMonitor { NSEvent.removeMonitor(m); mouseUpMonitor = nil }
        if let m = rightClickMonitor { NSEvent.removeMonitor(m); rightClickMonitor = nil }
        if let m = scrollWheelMonitor { NSEvent.removeMonitor(m); scrollWheelMonitor = nil }
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
            let f = win.editedFrame
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

        for layer in editor.effectiveLayers where layer != currentLayer {
            let count = editor.effectiveWindowCount(for: layer)
            let item = NSMenuItem(title: "Move to Layer \(layer) (\(count) windows)", action: nil, keyEquivalent: "")
            item.representedObject = ScreenMapLayerMenuAction(windowId: windowId, targetLayer: layer, editor: editor, controller: controller)
            item.action = #selector(ScreenMapLayerMenuTarget.performLayerMove(_:))
            item.target = ScreenMapLayerMenuTarget.shared
            menu.addItem(item)
        }

        let newLayerItem = NSMenuItem(title: "Move to New Layer", action: nil, keyEquivalent: "")
        newLayerItem.representedObject = ScreenMapLayerMenuAction(windowId: windowId, targetLayer: editor.layerCount, editor: editor, controller: controller)
        newLayerItem.action = #selector(ScreenMapLayerMenuTarget.performLayerMove(_:))
        newLayerItem.target = ScreenMapLayerMenuTarget.shared
        menu.addItem(newLayerItem)

        menu.popUp(positioning: nil, at: point, in: window.contentView)
    }
}

// MARK: - Context Menu Helpers

struct ScreenMapLayerMenuAction {
    let windowId: UInt32
    let targetLayer: Int
    let editor: ScreenMapEditorState
    let controller: ScreenMapController
}

final class ScreenMapLayerMenuTarget: NSObject {
    static let shared = ScreenMapLayerMenuTarget()

    @objc func performLayerMove(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? ScreenMapLayerMenuAction else { return }
        action.editor.reassignLayer(windowId: action.windowId, toLayer: action.targetLayer, fitToAvailable: true)
        action.controller.objectWillChange.send()
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
                let f = win.editedFrame
                let x = f.origin.x - screenCGOrigin.x
                let y = f.origin.y - screenCGOrigin.y
                let w = f.width
                let h = f.height
                let color = Self.layerColors[win.layer % Self.layerColors.count]

                ZStack(alignment: .topLeading) {
                    if let nsImage = captures[win.id] {
                        Image(nsImage: nsImage)
                            .resizable()
                            .frame(width: w, height: h)
                            .cornerRadius(6)
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(color.opacity(0.15))
                    }
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(color.opacity(0.7), lineWidth: 2)
                    Text(win.app)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(color.opacity(0.85))
                        .cornerRadius(4)
                        .padding(6)
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
