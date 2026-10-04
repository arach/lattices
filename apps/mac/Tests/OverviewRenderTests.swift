import AppKit
import SwiftUI
import XCTest
@testable import Lattices

/// Renders Overview from fixtures to PNGs for design review: three
/// monitors and nine Spaces split 1 / 6 / 2, one Desktop with a dozen
/// windows, most of the rest empty, and nine layers, enough to overflow
/// the top bar's tabs.
/// Skipped unless OVERVIEW_RENDER_DIR names a folder. No live reads.
@MainActor
final class OverviewRenderTests: XCTestCase {
    func testActualLayerSubmenuActionSurvivesRefreshAndWritesOnlyFixture() throws {
        _ = NSApplication.shared
        let suite = "picker.fixture." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let model = OverviewModel(defaults: defaults, inputs: inputs())
        var calls = 0
        model.compositionAdder = { windows, id in
            calls += 1
            XCTAssertEqual(id, "lattices")
            let (layers, count) = WorkspaceManager.adding(windows, to: 0,
                in: [Layer(id: "lattices", label: "Lattices", projects: [])],
                live: windows, sources: .init())
            try JSONEncoder().encode(layers).write(to: file)
            return (count, "Lattices")
        }
        let menu = OverviewLayerMenu.make(model: model, row: try XCTUnwrap(model.projection.all[5]))
        let submenu = try XCTUnwrap(menu.items.first { $0.title == "Add to" }?.submenu)
        let item = try XCTUnwrap(submenu.items.firstIndex { $0.title == "Lattices" })
        model.clearSelection()
        model.update(inputs()) // Real refresh while the menu snapshot exists.
        submenu.performActionForItem(at: item) // AppKit's actual target/action, not direct addComposition.
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(model.compositionNotice, "Added 1 windows to Lattices")
        XCTAssertNil(model.actionError)
        let layers = try JSONDecoder().decode([Layer].self, from: Data(contentsOf: file))
        XCTAssertEqual(layers[0].projects.flatMap { $0.pins ?? [] }.map(\.wid), [5])
    }

    func testActualLayerSubmenuReportsStaleWindowAndWriteFailure() throws {
        _ = NSApplication.shared
        let suite = "picker.failure." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = OverviewModel(defaults: defaults, inputs: inputs())
        var calls = 0
        model.compositionAdder = { _, _ in
            calls += 1
            throw NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture write denied"])
        }
        let menu = OverviewLayerMenu.make(model: model, row: try XCTUnwrap(model.projection.all[5]))
        let submenu = try XCTUnwrap(menu.items.first { $0.title == "Add to" }?.submenu)
        let item = try XCTUnwrap(submenu.items.firstIndex { $0.title == "Lattices" })
        submenu.performActionForItem(at: item)
        XCTAssertEqual(model.actionError, "Fixture write denied")
        XCTAssertNil(model.compositionNotice)
        model.update(.init(windows: [], displays: [], main: .zero))
        submenu.performActionForItem(at: item)
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(model.actionError?.contains("no longer available") == true)
    }

    func testOverlayKeepsActualLayerButtonAndMenuCallbackWhenMapAnchorDisappears() throws {
        var selectedModel: OverviewModel?
        let (host, window, cleanup) = self.host(width: 1590, height: 688, sidebar: false) { model in
            model.select(5)
            selectedModel = model
        }
        defer { cleanup(); _ = window }
        let model = try XCTUnwrap(selectedModel)
        func picker(in view: NSView) -> NSButton? {
            if let button = view as? NSButton, button.title == "Layer ▾" { return button }
            return view.subviews.lazy.compactMap { picker(in: $0) }.first
        }
        let button = try XCTUnwrap(picker(in: host))
        let coordinator = try XCTUnwrap(button.target as? OverviewLayerPicker.Coordinator)
        let menu = coordinator.make()
        let submenu = try XCTUnwrap(menu.items.first { $0.title == "Add to" }?.submenu)
        let item = try XCTUnwrap(submenu.items.firstIndex { $0.title == "Lattices" })
        var calls = 0
        model.compositionAdder = { _, _ in calls += 1; return (1, "Lattices") }

        model.chooseDesktop(21) // The selected window no longer has a map anchor.
        model.update(inputs())
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(model.focusedWid, 5)
        XCTAssertTrue(picker(in: host) === button, "refresh must not replace the menu's owning NSButton")
        submenu.performActionForItem(at: item)
        XCTAssertEqual(calls, 1)
        XCTAssertNil(model.actionError)
    }

    private func window(_ wid: UInt32, _ app: String, _ title: String, space: Int?, _ frame: CGRect,
                        hidden: Bool = false) -> WindowEntry {
        WindowEntry(
            wid: wid, app: app, pid: Int32(wid) + 100, title: title,
            frame: WindowFrame(x: frame.minX, y: frame.minY, w: frame.width, h: frame.height),
            spaceIds: space.map { [$0] } ?? [], isOnScreen: false, latticesSession: nil,
            zIndex: Int(wid), appHidden: hidden
        )
    }

    private func inputs() -> OverviewProjection.Inputs {
        let left = CGRect(x: -2560, y: 0, width: 2560, height: 1440)
        let main = CGRect(x: 0, y: 0, width: 3440, height: 1440)
        let laptop = CGRect(x: 3440, y: 300, width: 1512, height: 982)
        let displays = [
            OverviewDisplay(index: 0, name: "LG UltraFine", bounds: left, desktops: [1], currentSpaceId: 1, displayId: 1),
            OverviewDisplay(index: 1, name: "Studio", bounds: main, desktops: [4, 5, 6, 20, 21, 22], currentSpaceId: 4, displayId: 2),
            OverviewDisplay(index: 2, name: "Built-in Retina", bounds: laptop, desktops: [8],
                            currentSpaceId: 8, spaceIds: [8, 9], displayId: 3),
        ]
        func m(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }
        let windows = [
            window(1, "Ghostty", "lattices: swift build", space: 4, m(0, 25, 1720, 1415)),
            window(2, "ChatGPT", "Overview layout review", space: 4, m(1720, 25, 1720, 700)),
            window(3, "Zed", "OverviewDesk.swift — lattices", space: 4, m(1720, 725, 1720, 715)),
            window(4, "Ghostty", "tideline: bun dev", space: 4, m(200, 200, 1200, 800)),
            window(5, "Safari", "SwiftUI LazyVGrid — Apple Developer", space: 4, m(600, 120, 1600, 1100)),
            window(6, "Slack", "#lattices", space: 4, m(2400, 100, 900, 900)),
            window(7, "Finder", "Overview", space: 4, m(900, 600, 800, 500)),
            window(8, "Notes", "Overview critique", space: 4, m(2900, 900, 500, 500)),
            window(9, "Chrome", "localhost:5173 — tideline", space: 4, m(300, 300, 1800, 1000)),
            window(10, "Xcode", "Lattices — OverviewView.swift", space: 4, m(100, 50, 2200, 1350)),
            window(11, "Mail", "Inbox", space: 4, m(1400, 100, 1000, 700), hidden: true),
            window(12, "Ghostty", "scout: tail", space: 1, m(-2560, 25, 1280, 1415)),
            window(13, "Linear", "LAT-312 Overview", space: 1, m(-1280, 25, 1280, 1415)),
            window(14, "Figma", "Overview — Map Table", space: 5, m(200, 100, 2400, 1200)),
            window(15, "Spotify", "Daily Mix 2", space: 8, m(3500, 330, 1000, 700)),
            window(16, "Messages", "Messages", space: 8, m(4200, 330, 700, 900)),
            window(17, "Keynote", "Roadmap", space: 9, laptop),
            window(18, "Preview", "spec.pdf", space: nil, m(0, 0, 900, 1100)),
            window(19, "TextEdit", "Untitled", space: nil, m(0, 0, 700, 500)),
        ]
        let layers = [
            LayerOverview(index: 0, id: "lattices", label: "Lattices", layout: "auto", isActive: false, entries: [
                .init(index: 0, name: "Ghostty", pattern: "lattices", windows: [
                    .init(wid: 1, app: "Ghostty", title: "lattices: swift build", spot: .at(.here), spaceIds: [4],
                          frame: m(0, 25, 1720, 1415), tier: .pin),
                ], missing: nil),
                .init(index: 1, name: "ChatGPT", pattern: nil, windows: [
                    .init(wid: 2, app: "ChatGPT", title: "Overview layout review", spot: .at(.here), spaceIds: [4],
                          frame: m(1720, 25, 1720, 700), tier: .app),
                ], missing: nil),
                .init(index: 2, name: "Devin", pattern: nil, windows: [], missing: .notOpen),
                .init(index: 3, name: "Chrome", pattern: "lattices", windows: [], missing: .noWindow),
            ]),
            LayerOverview(index: 1, id: "talkie", label: "Talkie", layout: nil, isActive: true, entries: [
                .init(index: 0, name: "Xcode", pattern: nil, windows: [], missing: .notOpen),
            ]),
        ] + ["Scout", "Hudson design", "Tideline", "Voice agents", "Action browser", "Reading", "Personal"]
            .enumerated().map { offset, label in
                LayerOverview(index: offset + 2, id: label.lowercased(), label: label, layout: nil, isActive: false, entries: [])
            }
        return OverviewProjection.Inputs(
            windows: windows, layers: layers, displays: displays, main: main,
            tucked: ["lattices": [3]], extras: ["lattices": [9]],
            appType: { ["Ghostty": .terminal, "Zed": .editor, "Xcode": .editor, "Safari": .browser, "Chrome": .browser][$0] ?? .other }
        )
    }

    /// Overview from fixtures in an offscreen window, never ordered in.
    /// `top` drops the page that far down its window, as the shell's title
    /// bar and rounded stage do, which can land it between pixels.
    private func host(width: CGFloat, height: CGFloat, sidebar: Bool, top: CGFloat = 0,
                      configure: (OverviewModel) -> Void = { _ in }) -> (NSHostingView<AnyView>, NSWindow, () -> Void) {
        let suite = "overview.render.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let model = OverviewModel(defaults: defaults, actions: RenderActions(), inputs: inputs())
        model.chooseMembershipLayer("lattices")
        model.membershipShown = sidebar
        configure(model)

        let view = OverviewView(model: model, controller: ScreenMapController(), live: false)
            .frame(width: width, height: height - top)
            .padding(.top, top)
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: AnyView(view))
        host.frame = CGRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
        return (host, window, { defaults.removePersistentDomain(forName: suite) })
    }

    /// A bitmap of the view at `scale` pixels per point.
    private func snapshot(_ host: NSView, scale: CGFloat = 1) throws -> NSBitmapImageRep {
        let size = host.bounds.size
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }

    private func render(_ name: String, width: CGFloat, height: CGFloat, sidebar: Bool, scale: CGFloat = 1,
                        top: CGFloat = 0, configure: (OverviewModel) -> Void = { _ in }) throws {
        guard let dir = ProcessInfo.processInfo.environment["OVERVIEW_RENDER_DIR"] else {
            throw XCTSkip("Set OVERVIEW_RENDER_DIR to render")
        }
        let (host, window, cleanup) = self.host(width: width, height: height, sidebar: sidebar, top: top, configure: configure)
        defer { cleanup(); _ = window }
        let rep = try snapshot(host, scale: scale)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap(scrollViews(in:))
    }

    /// The sidebar's long list scrolls on its own at any width: a wheel
    /// moves a list that overflows.
    private func assertListsScroll(width: CGFloat, file: StaticString = #filePath, line: UInt = #line) throws {
        let (host, window, cleanup) = self.host(width: width, height: 380, sidebar: true)
        defer { cleanup(); _ = window }
        let overflowing = scrollViews(in: host).filter { scroll in
            guard let doc = scroll.documentView else { return false }
            return doc.frame.height > scroll.contentView.bounds.height + 20
        }
        XCTAssertFalse(overflowing.isEmpty, "no list overflows at \(width)", file: file, line: line)
        for scroll in overflowing {
            let before = scroll.contentView.bounds.origin.y
            let wheel = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                              wheel1: -80, wheel2: 0, wheel3: 0))
            scroll.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: wheel)))
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            XCTAssertNotEqual(scroll.contentView.bounds.origin.y, before, "a list didn't scroll at \(width)", file: file, line: line)
        }
    }

    /// The list is a panel over the stage, not a column beside it: with it
    /// open, everything clear of it draws exactly as with it closed.
    private func assertPanelOverlays(width: CGFloat, height: CGFloat, file: StaticString = #filePath, line: UInt = #line) throws {
        func pixels(_ sidebar: Bool) throws -> NSBitmapImageRep {
            let (host, window, cleanup) = self.host(width: width, height: height, sidebar: sidebar)
            defer { cleanup(); _ = window }
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            return rep
        }
        let closed = try pixels(false), open = try pixels(true)
        XCTAssertEqual(closed.pixelsWide, open.pixelsWide, file: file, line: line)
        // Clear of the panel, its shadow and the toggle it lights.
        let scale = CGFloat(closed.pixelsWide) / width
        let clear = Int((width - 360) * scale)
        var differing = 0
        for y in stride(from: 0, to: closed.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: clear, by: 2) where closed.colorAt(x: x, y: y) != open.colorAt(x: x, y: y) {
                differing += 1
            }
        }
        XCTAssertEqual(differing, 0, "opening the list moved the stage at \(width)", file: file, line: line)
    }

    private func assertSelectionOverlay(width: CGFloat, height: CGFloat,
                                        file: StaticString = #filePath, line: UInt = #line) throws {
        func pixels(selected: Bool, error: Bool) throws -> NSBitmapImageRep {
            let (host, window, cleanup) = self.host(width: width, height: height, sidebar: false) { model in
                if selected { model.select(15) }
                if error { model.rejectMove("Fixture failure. Original position restored.") }
            }
            defer { cleanup(); _ = window }
            return try snapshot(host)
        }
        let plain = try pixels(selected: false, error: false)
        for state in [(true, false), (true, true)] {
            let overlay = try pixels(selected: state.0, error: state.1)
            var differing = 0
            // Inside the left display map, below the floating controls and
            // above the tray. The right-hand selected window is elsewhere.
            for y in stride(from: 165, to: Int(height - OverviewTray.height - OverviewStage.hintHeight - 92), by: 2) {
                for x in stride(from: 240, to: min(380, Int(width * 0.38)), by: 2) {
                    if plain.colorAt(x: x, y: y) != overlay.colorAt(x: x, y: y) { differing += 1 }
                }
            }
            XCTAssertEqual(differing, 0, "selection or failure shifted the map", file: file, line: line)
        }
    }

    func testSelectionAndFailureOverlayWide() throws { try assertSelectionOverlay(width: 1590, height: 688) }
    func testSelectionAndFailureOverlayLaptop() throws { try assertSelectionOverlay(width: 1110, height: 648) }

    func testPanelOverlaysWide() throws { try assertPanelOverlays(width: 1590, height: 688) }
    func testPanelOverlaysLaptop() throws { try assertPanelOverlays(width: 1110, height: 648) }

    func testListsScrollWide() throws { try assertListsScroll(width: 1760) }
    func testListsScrollNarrow() throws { try assertListsScroll(width: 900) }

    // The content area inside the app shell: a 48 + 120 point rail, a 46
    // point title bar and a 26 point status bar around Overview.
    func testPanelToggleUsesIndexScopeAndWindowCount() {
        let suite = "overview.panel-count." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = OverviewModel(defaults: defaults, actions: RenderActions(), inputs: inputs())
        let rows = model.indexFixtureRows
        XCTAssertEqual(OverviewWorkingList.name(model), "All windows")
        XCTAssertEqual(OverviewWorkingList.count(model), Set(rows.flatMap(\.windows)).count)
        model.chooseIndex(["lattices"], rows: rows)
        XCTAssertEqual(OverviewWorkingList.name(model), "Lattices")
        XCTAssertEqual(OverviewWorkingList.count(model), rows.first { $0.id == "lattices" }?.count)
        let ids = Array(rows.prefix(2).map(\.id))
        model.chooseIndex(ids, rows: rows)
        XCTAssertEqual(OverviewWorkingList.name(model), rows.prefix(2).map(\.label).joined(separator: " + "))
        XCTAssertEqual(OverviewWorkingList.count(model), Set(rows.prefix(2).flatMap(\.windows)).count)
    }

    func testDeskIndexAll() throws { try render("desk-index-all", width: 1590, height: 688, sidebar: false) }
    func testDeskIndexLayer() throws {
        try render("desk-index-layer", width: 1590, height: 688, sidebar: false) { model in
            model.chooseIndex(["lattices"], rows: model.indexFixtureRows)
        }
    }
    func testDeskIndexMulti() throws {
        try render("desk-index-multi", width: 1590, height: 688, sidebar: false) { model in
            model.chooseIndex(Array(model.indexFixtureRows.prefix(2).map(\.id)), rows: model.indexFixtureRows)
        }
    }
    func testDeskIndexNarrow() throws { try render("desk-index-narrow", width: 1110, height: 648, sidebar: false) }

    func testWide() throws { try render("wide", width: 1590, height: 688, sidebar: false) }
    func testWide2x() throws { try render("wide@2x", width: 1590, height: 688, sidebar: false, scale: 2) }
    func testWideShell2x() throws { try render("wide-shell@2x", width: 1590, height: 688, sidebar: false, scale: 2, top: 46.25) }
    func testLaptopSidebar2x() throws {
        try render("laptop-sidebar@2x", width: 1110, height: 648, sidebar: true, scale: 2) { model in
            model.select(4)
        }
    }
    func testWideSidebar() throws { try render("wide-sidebar", width: 1590, height: 688, sidebar: true) }
    func testLaptop() throws { try render("laptop", width: 1110, height: 648, sidebar: false) }


    func testTrayCrispEvidence() throws {
        guard let dir = ProcessInfo.processInfo.environment["OVERVIEW_RENDER_DIR"] else { throw XCTSkip("Set OVERVIEW_RENDER_DIR") }
        let phase = ProcessInfo.processInfo.environment["OVERVIEW_EVIDENCE_PHASE"] ?? "after"
        let suite = "tray.evidence." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = OverviewModel(defaults: defaults, actions: RenderActions(), inputs: inputs())
        for scale: CGFloat in [1, 2] {
            let host = NSHostingView(rootView: OverviewTray(model: model).background(Palette.bg)
                .environment(\.colorScheme, .dark).environment(\.displayScale, scale))
            host.frame = CGRect(x: 0, y: 0, width: 1378, height: OverviewTray.height)
            let window = OverviewEvidenceWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.evidenceScale = scale
            window.appearance = NSAppearance(named: .darkAqua); window.contentView = host
            host.layoutSubtreeIfNeeded()
            func setScale(_ view: NSView) {
                view.layer?.contentsScale = scale
                view.needsDisplay = true
                for child in view.subviews { setScale(child) }
            }
            setScale(host)
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            XCTAssertEqual(window.backingScaleFactor, scale)
            let bitmap = try snapshot(host, scale: scale)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("tray-\(phase)-\(Int(scale))x.png"))
            let crop = try XCTUnwrap(bitmap.cgImage?.cropping(to: CGRect(x: 0, y: 0, width: 440 * scale, height: 90 * scale)))
            let data = try XCTUnwrap(NSBitmapImageRep(cgImage: crop).representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("crisp-\(phase)-\(Int(scale))x.png"))
            _ = window
        }
    }

    func testDeskPassEvidence() throws {
        try render("desk-toolbar-strip", width: 1590, height: 688, sidebar: false) { $0.select(2) }
        try render("desk-pinned-display", width: 1590, height: 688, sidebar: false) { $0.pinDisplay(2); $0.select(2) }
        try render("desk-hidden-display", width: 1590, height: 688, sidebar: false) { $0.hideDisplay(2) }
        guard let dir = ProcessInfo.processInfo.environment["OVERVIEW_RENDER_DIR"] else { throw XCTSkip("Set OVERVIEW_RENDER_DIR") }
        let suite = "desk.snap-render." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = OverviewModel(defaults: defaults, actions: RenderActions(), inputs: inputs())
        let monitor = try XCTUnwrap(model.projection.desk.first { $0.display.displayId == 2 })
        let space = try XCTUnwrap(monitor.spaces.first)
        let size = CGSize(width: 700, height: 320)
        let view = OverviewMap(model: model, display: monitor.display, space: space, size: size, quiet: false)
            .modifier(OverviewScreenDrop(model: model, display: monitor.display, spaceId: space.spaceId, mapSize: size, preview: .left))
            .padding(20).background(Palette.bg).environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 740, height: 360)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua); window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let png = try XCTUnwrap(snapshot(host).representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("desk-screen-snap-hover.png"))
        _ = window
    }

    func testDeskDragSourceHonorsFrontmostTileAndToolbarShield() {
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        let window = NSWindow(contentRect: root.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = root
        let back = OverviewImmediateDragSource.Source(frame: root.bounds)
        let front = OverviewImmediateDragSource.Source(frame: root.bounds)
        root.addSubview(back); root.addSubview(front)
        let point = CGPoint(x: 100, y: 100)
        XCTAssertTrue(OverviewImmediateDragSource.Source.frontmost(in: root, windowPoint: point) === front)
        let shield = OverviewDragShield.Shield(frame: root.bounds)
        root.addSubview(shield)
        XCTAssertTrue(OverviewImmediateDragSource.Source.frontmost(in: root, windowPoint: point) === shield)
        shield.isHidden = true
        XCTAssertTrue(OverviewImmediateDragSource.Source.frontmost(in: root, windowPoint: point) === front)
        front.isHidden = true
        XCTAssertTrue(OverviewImmediateDragSource.Source.frontmost(in: root, windowPoint: point) === back)
    }

    func testDeskNativeRowArmsDragWithoutLongPress() throws {
        let suite = "desk.source." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = OverviewModel(defaults: defaults, actions: RenderActions(), inputs: inputs())
        let row = try XCTUnwrap(model.projection.all[1])
        let host = NSHostingView(rootView: OverviewDeskRow(model: model, row: row, showsUnknown: false))
        host.frame = CGRect(x: 0, y: 0, width: 500, height: 40)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        func source(_ view: NSView) -> OverviewImmediateDragSource.Source? {
            (view as? OverviewImmediateDragSource.Source) ?? view.subviews.lazy.compactMap(source).first
        }
        let native = try XCTUnwrap(source(host))
        let point = native.convert(CGPoint(x: native.bounds.midX, y: native.bounds.midY), to: nil)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        _ = native.observe(event)
        XCTAssertEqual(native.payload?.windows, [1], "An ordinary row mouse-down must arm the native drag source")
    }

    func testDragPassEvidence() throws {
        guard let dir = ProcessInfo.processInfo.environment["OVERVIEW_RENDER_DIR"] else {
            throw XCTSkip("Set OVERVIEW_RENDER_DIR to render")
        }
        let suite = "drag.render." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = OverviewModel(defaults: defaults, actions: RenderActions(), inputs: inputs())
        model.receiveMembership(.init(session: model.membershipDragSession, windows: [1, 9], sourceLayer: "lattices", move: true), into: "__new_layer__")
        let draft = try XCTUnwrap(model.composition)
        let drag = OverviewMembershipDrag(session: model.membershipDragSession, windows: [1, 9], sourceLayer: "lattices", move: true)
        func capture<V: View>(_ name: String, _ view: V, _ size: CGSize) throws {
            let host = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
            host.frame = CGRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            let png = try XCTUnwrap(snapshot(host).representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
            _ = window
        }
        try capture("drag-new-layer-hover", OverviewLayerIndex(rows: model.indexFixtureRows, selected: [],
            readAt: Date(), live: false, activeDrag: drag, previewDropTarget: "__new_layer__", choose: { _, _ in }), CGSize(width: 236, height: 500))
        try capture("drag-prefilled-sheet", OverviewComposeSheet(draft: draft, create: { _ in
            XCTFail("No live create in render"); return false
        }), CGSize(width: 628, height: 460))
        model.chooseIndex(["lattices"], rows: model.indexFixtureRows)
        try capture("drag-desktop-hover", OverviewDesktopStrip(model: model, previewSpace: model.projection.displays.first(where: { $0.desktops.count > 1 })?.desktops[1]), CGSize(width: 1200, height: 90))
    }

    func testComposeDragHover() throws {
        guard let dir = ProcessInfo.processInfo.environment["OVERVIEW_RENDER_DIR"] else {
            throw XCTSkip("Set OVERVIEW_RENDER_DIR to render")
        }
        let rows = [LayerIndexState.Row(id: "talkie", label: "Talkie", windows: [1]),
                    .init(id: "__unassigned__", label: "Unassigned", windows: [])]
        let view = OverviewLayerIndex(rows: rows, selected: [], readAt: Date(), live: false,
                                      previewDropTarget: "talkie", choose: { _, _ in })
            .frame(width: 212, height: 440).environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 212, height: 440)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let png = try XCTUnwrap(snapshot(host).representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("compose-drag-hover.png"))
        _ = window
    }

    func testComposeToolbarSurvivesUnplacedSelection() throws {
        try render("compose-unplaced-toolbar", width: 1590, height: 688, sidebar: true) { model in
            model.select(18)
            model.chooseDesktop(21)
            XCTAssertEqual(model.focusedWid, 18)
        }
    }
    func testComposeSelectionFooter() throws {
        try render("compose-multi-footer", width: 1590, height: 688, sidebar: true) { model in
            model.select(1)
            model.toggle(9)
        }
    }

    func testComposeSheetPreview() throws {
        guard let dir = ProcessInfo.processInfo.environment["OVERVIEW_RENDER_DIR"] else {
            throw XCTSkip("Set OVERVIEW_RENDER_DIR to render")
        }
        var draft = OverviewComposition(windows: inputs().windows.filter { [UInt32(1), 9].contains($0.wid) })
        draft.name = "Chrome + terminal"
        let view = OverviewComposeSheet(draft: draft, create: { _ in
            XCTFail("Render must never create a layer"); return false
        }).environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 628, height: 420)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let png = try XCTUnwrap(snapshot(host).representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("compose-new-layer-sheet.png"))
        _ = window
    }
    func testLaptopSidebar() throws { try render("laptop-sidebar", width: 1110, height: 648, sidebar: true) }
    func testWideFullWindow() throws { try render("wide-full", width: 1760, height: 760, sidebar: false) }
    func testWideLayerSidebar() throws {
        try render("wide-layer-sidebar", width: 1590, height: 688, sidebar: true) { model in
            model.chooseLayer("lattices")
        }
    }
    func testWideLayerDesktop() throws {
        try render("wide-layer-desktop", width: 1590, height: 688, sidebar: true) { model in
            model.chooseLayer("lattices")
            model.chooseDesktop(4)
            model.select(1)
            model.toggle(2)
        }
    }
    func testWideEmptyLayer() throws {
        try render("wide-empty-layer", width: 1590, height: 688, sidebar: true) { model in
            model.chooseLayer("talkie")
        }
    }
    func testLaptopLayer() throws {
        try render("laptop-layer", width: 1110, height: 648, sidebar: false) { model in
            model.chooseLayer("lattices")
        }
    }
    func testLaptopDesktop() throws {
        try render("laptop-desktop", width: 1110, height: 648, sidebar: true) { model in
            model.chooseDesktop(5)
            model.select(14)
        }
    }
    func testWideScopedSelected() throws {
        try render("wide-scoped", width: 1590, height: 688, sidebar: false) { model in
            model.chooseDesktop(4)
            model.select(5)
            model.toggle(3)
        }
    }
    /// A mostly empty Desktop on the monitor with six of them.
    func testWideEmptyDesktop() throws {
        try render("wide-empty-desktop", width: 1590, height: 688, sidebar: false) { model in
            model.chooseDesktop(21)
        }
    }
    /// The laptop's Desktop 1, beside two other monitors' Desktop 1s.
    func testLaptopRepeatedDesktopName() throws {
        try render("laptop-repeated-d1", width: 1110, height: 648, sidebar: false) { model in
            model.chooseDesktop(8)
        }
    }
    func testLaptopEmptyLayer() throws {
        try render("laptop-empty-layer", width: 1110, height: 648, sidebar: false) { model in
            model.chooseLayer("talkie")
        }
    }
}

private struct RenderActions: OverviewActions {
    func distribute(_ windows: [(wid: UInt32, pid: Int32)], displayId: UInt32, shape: [Int]?) {}
    func focus(wid: UInt32, pid: Int32) {}
    func place(wid: UInt32, pid: Int32, position: TilePosition, displayId: UInt32) {}
    func moveToSpace(wid: UInt32, pid: Int32, spaceId: Int, displayId: UInt32, completion: @escaping (String?) -> Void) {}
    func saveLayer(_ plan: LayerEditPlan) throws {}
    func rearrange(layerId: String) throws {}
}

/// Offscreen native density fixture, including NSScrollView-backed content.
private final class OverviewEvidenceWindow: NSWindow {
    var evidenceScale: CGFloat = 1
    override var backingScaleFactor: CGFloat { evidenceScale }
}
