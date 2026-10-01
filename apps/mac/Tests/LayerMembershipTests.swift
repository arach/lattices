import XCTest
@testable import Lattices

final class LayerMembershipTests: XCTestCase {
    private func window(
        _ wid: UInt32, _ app: String, _ title: String, z: Int = 0, session: String? = nil, side: Double = 800
    ) -> WindowEntry {
        WindowEntry(
            wid: wid, app: app, pid: 1, title: title, frame: WindowFrame(x: 0, y: 0, w: side, h: side),
            spaceIds: [1], isOnScreen: true, latticesSession: session, zIndex: z
        )
    }

    private func app(_ app: String, title: String? = nil, pins: [LayerPin]? = nil) -> LayerProject {
        LayerProject(path: nil, group: nil, tile: nil, display: nil, app: app, title: title, url: nil, launch: nil, pins: pins)
    }

    /// An entry as ⌘⌥T saves it: pinned, and held by its pins alone.
    private func saved(_ app: String, title: String? = nil, pins: [LayerPin]) -> LayerProject {
        var entry = self.app(app, title: title, pins: pins)
        entry.saved = true
        return entry
    }

    private func pin(_ window: WindowEntry) -> LayerPin { LayerPin(window) }

    private func layer(_ id: String, _ projects: [LayerProject]) -> Layer {
        Layer(id: id, label: id, projects: projects)
    }

    private func resolve(_ layers: [Layer], _ windows: [WindowEntry], sources: LayerMembership.Sources = .init()) -> LayerMembership.Resolution {
        LayerMembership.resolve(layers, windows: windows, sources: sources)
    }

    private func wids(_ resolution: LayerMembership.Resolution, _ id: String) -> [UInt32] {
        resolution.members(of: id).map(\.entry.wid)
    }

    private func json(_ layers: [Layer]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return String(decoding: try encoder.encode(layers), as: UTF8.self)
    }

    // MARK: Resolving

    func testAMatchRuleTakesItsWindowFromABroaderAppEntry() {
        let layers = [
            layer("talkie", [app("Talkie")]),
            layer("agent", [LayerProject(clause: StudioLayerClause(appEquals: "Talkie Agent Dev"))]),
        ]
        let resolution = resolve(layers, [window(1, "Talkie", "Main"), window(2, "Talkie Agent Dev", "Console")])
        XCTAssertEqual(wids(resolution, "talkie"), [1])
        XCTAssertEqual(wids(resolution, "agent"), [2])
        XCTAssertEqual(resolution.owners[2], LayerMembership.Owner(layerId: "agent", project: 0))
    }

    func testAnAppOnlyRuleLeavesTitledEntriesTheirWindows() {
        let layers = [
            layer("chrome", [LayerProject(clause: StudioLayerClause(appEquals: "Google Chrome"))]),
            layer("lattices", [app("Google Chrome", title: "Lattices")]),
        ]
        let resolution = resolve(layers, [window(1, "Google Chrome", "Lattices — PR"), window(2, "Google Chrome", "Mail")])
        XCTAssertEqual(wids(resolution, "lattices"), [1])
        XCTAssertEqual(wids(resolution, "chrome"), [2])

        // A rule that also reads the title still beats the needle.
        let titled = [
            layer("chrome", [LayerProject(clause: StudioLayerClause(appEquals: "Google Chrome", titleContains: "PR"))]),
            layer("lattices", [app("Google Chrome", title: "Lattices")]),
        ]
        XCTAssertEqual(wids(resolve(titled, [window(1, "Google Chrome", "Lattices — PR")]), "chrome"), [1])
    }

    func testAnUntitledTabClaimsAsABareApp() {
        let group = TabGroup(id: "tools", label: "Tools", tabs: [
            TabGroupTab(path: nil, label: nil, app: "Figma", title: nil, url: nil, launch: nil),
        ])
        let layers = [
            layer("tools", [LayerProject(path: nil, group: "tools", tile: nil, display: nil, app: nil, title: nil, url: nil, launch: nil)]),
            layer("spec", [app("Figma", title: "Spec")]),
        ]
        let resolution = resolve(layers, [window(1, "Figma", "Spec — v2"), window(2, "Figma", "Icons")], sources: .init(group: { $0 == "tools" ? group : nil }))
        XCTAssertEqual(wids(resolution, "spec"), [1])
        XCTAssertEqual(wids(resolution, "tools"), [2])
    }

    func testAnEntryMadeFromOneWindowLeavesItsTwin() {
        let moved = window(1, "Ghostty", "mini: talkie"), twin = window(2, "Ghostty", "mini: talkie")
        let layers = [
            layer("fab", [saved("Ghostty", title: "mini: talkie", pins: [pin(moved)])]),
            layer("talkie", [app("Ghostty", title: "mini: talkie")]),
        ]
        let resolution = resolve(layers, [moved, twin])
        XCTAssertEqual(wids(resolution, "fab"), [1])
        XCTAssertEqual(wids(resolution, "talkie"), [2])
    }

    func testASavedEntryHoldsByItsPinAlone() {
        let moved = window(1, "Ghostty", "mini: talkie"), twin = window(2, "Ghostty", "mini: talkie")
        let layers = [
            layer("talkie", [app("Ghostty", title: "talkie")]),
            layer("fab", [saved("Ghostty", title: "mini: talkie", pins: [pin(moved)])]),
        ]
        XCTAssertTrue(layers[1].projects[0].isSaved)
        let resolution = resolve(layers, [moved, twin])
        XCTAssertEqual(wids(resolution, "fab"), [1])
        XCTAssertEqual(wids(resolution, "talkie"), [2])
    }

    func testMovingOneTwinLeavesTheOtherToItsRule() {
        let moved = window(1, "Ghostty", "mini: talkie"), twin = window(2, "Ghostty", "mini: talkie")
        let before = [layer("talkie", [app("Ghostty", title: "talkie")]), layer("fab", [app("Zed")])]
        let (after, outcome) = WorkspaceManager.moving(moved, from: 0, to: 1, in: before, live: [moved, twin], sources: .init())
        XCTAssertEqual(outcome, .moved)
        XCTAssertEqual(after[0].projects.map(\.title), ["talkie"])
        let resolution = resolve(after, [moved, twin])
        XCTAssertEqual(wids(resolution, "fab"), [1])
        XCTAssertEqual(wids(resolution, "talkie"), [2])
    }

    func testAPinAddedToAWrittenEntryKeepsItsRule() {
        let mini = window(1, "Ghostty", "mini: talkie"), arts = window(2, "Ghostty", "arts: talkie")
        let before = [layer("talkie", [app("Ghostty", title: "talkie")])]
        let (after, added) = WorkspaceManager.adding([mini], to: 0, in: before, live: [mini, arts], sources: .init())
        XCTAssertEqual(added, 0)
        XCTAssertEqual(after[0].projects[0].pins, [pin(mini)])
        XCTAssertFalse(after[0].projects[0].isSaved)
        XCTAssertEqual(Set(wids(resolve(after, [mini, arts]), "talkie")), [1, 2])
    }

    func testAPinOnAWrittenEntryOfTheSameTitleLeavesTheRuleBe() throws {
        let pinned = window(1, "Ghostty", "mini: talkie"), twin = window(2, "Ghostty", "mini: talkie")
        let before = [layer("talkie", [app("Ghostty", title: "mini: talkie")])]
        let (after, added) = WorkspaceManager.adding([pinned], to: 0, in: before, live: [pinned, twin], sources: plain)
        XCTAssertEqual(added, 0)
        XCTAssertEqual(after[0].projects[0].pins, [pin(pinned)])
        XCTAssertFalse(after[0].projects[0].isSaved)
        XCTAssertEqual(Set(wids(resolve(after, [pinned, twin]), "talkie")), [1, 2])

        // The pinned window closes while Ghostty runs on: the pin goes, the rule stays.
        let closed = resolve(after, [twin], sources: .init(isRunning: { $0 == 1 }))
        XCTAssertEqual(closed.closed, [LayerMembership.Closed(layer: 0, project: 0, pin: 0)])
        let kept = WorkspaceManager.keeping(closed, in: after)
        XCTAssertEqual(try json(kept), try json(before))
        XCTAssertEqual(wids(resolve(kept, [twin]), "talkie"), [2])
    }

    func testEditingASavedEntrysRuleMakesItWritten() {
        let moved = window(1, "Ghostty", "mini: talkie"), twin = window(2, "Ghostty", "mini: talkie")
        var entry = saved("Ghostty", title: "mini: talkie", pins: [pin(moved)])
        entry.setClause(StudioLayerClause(app: "Ghostty", titleContains: "mini: talkie"))
        XCTAssertFalse(entry.isSaved)
        XCTAssertEqual(Set(wids(resolve([layer("fab", [entry])], [moved, twin]), "fab")), [1, 2])
    }

    func testTheMoreSpecificNeedleWinsWhateverTheOrder() {
        let broad = layer("browse", [app("Safari")])
        let docs = layer("docs", [app("Safari", title: "Docs")])
        let windows = [window(1, "Safari", "Docs — Swift"), window(2, "Safari", "News")]
        for layers in [[broad, docs], [docs, broad]] {
            let resolution = resolve(layers, windows)
            XCTAssertEqual(wids(resolution, "browse"), [2])
            XCTAssertEqual(wids(resolution, "docs"), [1])
        }
        // App alone: the longer app name.
        let code = [layer("code", [app("Code")]), layer("vscode", [app("Visual Studio Code")])]
        XCTAssertEqual(wids(resolve(code, [window(3, "Visual Studio Code", "main.swift")]), "vscode"), [3])
    }

    func testTiesGoToTheEarlierLayerThenEntry() {
        let layers = [layer("a", [app("Notes"), app("Notes")]), layer("b", [app("Notes")])]
        let resolution = resolve(layers, [window(1, "Notes", "Todo")])
        XCTAssertEqual(resolution.owners[1], LayerMembership.Owner(layerId: "a", project: 0))
        XCTAssertEqual(wids(resolution, "b"), [])
    }

    func testAPinBeatsANeedle() {
        let docs = window(1, "Safari", "Docs")
        let layers = [
            layer("docs", [app("Safari", title: "Docs")]),
            layer("reading", [app("Safari", title: "Old", pins: [LayerPin(wid: 1, app: "Safari", title: "Old")])]),
        ]
        let resolution = resolve(layers, [docs])
        XCTAssertEqual(wids(resolution, "docs"), [])
        XCTAssertEqual(wids(resolution, "reading"), [1])
        XCTAssertEqual(resolution.pinned, [1])
        XCTAssertEqual(resolution.rebound, [])
    }

    func testADeadPinRebindsByExactAppAndTitle() {
        let layers = [layer("docs", [app("Safari", title: "Gone", pins: [LayerPin(wid: 99, app: "Safari", title: "Docs")])])]
        let windows = [
            window(3, "Safari Technology Preview", "Docs", z: 0),
            window(4, "Safari", "Docs 2", z: 1),
            window(5, "Safari", "Docs", z: 2),
        ]
        let resolution = resolve(layers, windows)
        XCTAssertEqual(wids(resolution, "docs"), [5])
        XCTAssertEqual(resolution.rebound, [LayerMembership.Rebind(layer: 0, project: 0, pin: 0, wid: 5, pid: 1)])
        XCTAssertEqual(resolution.pinned, [5])
    }

    func testADeadPinLeavesAWindowAnotherPinHolds() {
        let layers = [
            layer("docs", [app("Zed", pins: [LayerPin(wid: 99, app: "Safari", title: "Docs")])]),
            layer("reading", [app("Notes", pins: [LayerPin(wid: 5, app: "Safari", title: "Docs")])]),
        ]
        let resolution = resolve(layers, [window(5, "Safari", "Docs")])
        XCTAssertEqual(wids(resolution, "reading"), [5])
        XCTAssertEqual(wids(resolution, "docs"), [])
        XCTAssertEqual(resolution.rebound, [])
    }

    func testAPinWhoseWindowClosedWhileItsAppRunsIsClosed() {
        let twin = window(2, "Ghostty", "mini: talkie")
        let layers = [layer("fab", [saved("Ghostty", title: "mini: talkie", pins: [LayerPin(wid: 1, app: "Ghostty", title: "mini: talkie", pid: 1)])])]
        let running = LayerMembership.Sources(isRunning: { $0 == 1 })
        let resolution = resolve(layers, [twin], sources: running)
        XCTAssertEqual(wids(resolution, "fab"), [])
        XCTAssertEqual(resolution.rebound, [])
        XCTAssertEqual(resolution.closed, [LayerMembership.Closed(layer: 0, project: 0, pin: 0)])
        // Dropped, it takes the saved entry it leaves holding nothing.
        XCTAssertEqual(WorkspaceManager.keeping(resolution, in: layers)[0].projects.count, 0)

        // A hidden app's window can drop out of the inventory: it waits.
        var hidden = twin
        hidden.appHidden = true
        XCTAssertEqual(resolve(layers, [hidden], sources: running).closed, [])
    }

    func testAPinRebindsOnceItsAppQuitButNotToAnotherLayersWindow() {
        let fab = layer("fab", [saved("Ghostty", title: "mini: talkie", pins: [LayerPin(wid: 1, app: "Ghostty", title: "mini: talkie", pid: 7)])])
        let quit = LayerMembership.Sources(isRunning: { _ in false })
        let relaunched = window(3, "Ghostty", "mini: talkie")
        let resolution = resolve([fab], [relaunched], sources: quit)
        XCTAssertEqual(resolution.rebound, [LayerMembership.Rebind(layer: 0, project: 0, pin: 0, wid: 3, pid: 1)])
        XCTAssertEqual(
            WorkspaceManager.keeping(resolution, in: [fab])[0].projects[0].pins,
            [LayerPin(wid: 3, app: "Ghostty", title: "mini: talkie", pid: 1)]
        )

        // Another layer's rule holds it: the pin leaves it be.
        let held = resolve([layer("talkie", [app("Ghostty", title: "talkie")]), fab], [relaunched], sources: quit)
        XCTAssertEqual(held.rebound, [])
        XCTAssertEqual(wids(held, "talkie"), [3])
    }

    func testAPinWithoutAPidTakesOnlyAWindowNoOtherLayerReads() {
        let fab = layer("fab", [app("Zed", pins: [LayerPin(wid: 1, app: "Ghostty", title: "mini: talkie")])])
        let relaunched = window(3, "Ghostty", "mini: talkie")
        XCTAssertEqual(resolve([layer("shell", [app("Ghostty")]), fab], [relaunched]).rebound, [])
        XCTAssertEqual(resolve([fab], [relaunched]).rebound.map(\.wid), [3])
    }

    func testAPinOnAWidAnotherAppNowHasLetsGo() {
        let layers = [layer("notes", [app("Zed", pins: [LayerPin(wid: 5, app: "Notes", title: "Todo")])])]
        let resolution = resolve(layers, [window(5, "Safari", "Docs")])
        XCTAssertEqual(wids(resolution, "notes"), [])
        XCTAssertNil(resolution.owners[5])
    }

    func testGroupAndPathEntriesStillResolve() {
        let api = "/tmp/lattices-tests/api", web = "/tmp/lattices-tests/web"
        let group = TabGroup(id: "stack", label: "Stack", tabs: [
            TabGroupTab(path: api, label: nil, app: nil, title: nil, url: nil, launch: nil),
            TabGroupTab(path: nil, label: nil, app: "Figma", title: "Spec", url: nil, launch: nil),
        ])
        let sources = LayerMembership.Sources(
            group: { $0 == "stack" ? group : nil },
            projectWindows: { $0 == web ? [LayerProject(path: nil, group: nil, tile: nil, display: 2, app: "Xcode", title: "Web", url: nil, launch: nil)] : [] }
        )
        let layers = [
            layer("stack", [LayerProject(path: nil, group: "stack", tile: nil, display: nil, app: nil, title: nil, url: nil, launch: nil)]),
            layer("web", [LayerProject(path: web, group: nil, tile: "left", display: nil, app: nil, title: nil, url: nil, launch: nil)]),
        ]
        let windows = [
            window(1, "Terminal", "zsh", session: WorkspaceManager.sessionName(for: api)),
            window(2, "Figma", "Spec — v2"),
            window(3, "iTerm2", "zsh", session: WorkspaceManager.sessionName(for: web)),
            window(4, "Xcode", "Web.xcodeproj"),
            window(5, "Xcode", "Other.xcodeproj"),
        ]
        let resolution = resolve(layers, windows, sources: sources)
        XCTAssertEqual(Set(wids(resolution, "stack")), [1, 2])
        XCTAssertEqual(Set(wids(resolution, "web")), [3, 4])
        XCTAssertTrue(resolution.members(of: "web").allSatisfy(\.placed))
        XCTAssertNil(resolution.owners[5])
    }

    func testALaunchOnlyEntryMatchesNothing() {
        let launcher = LayerProject(path: nil, group: nil, tile: nil, display: nil, app: nil, title: nil, url: "https://slack.com", launch: "Slack")
        XCTAssertEqual(wids(resolve([layer("chat", [launcher])], [window(1, "Slack", "general")]), "chat"), [])
    }

    func testOnlyContentWindowsAreHeld() {
        let resolution = resolve([layer("browse", [app("Safari")])], [window(1, "Safari", "Docs"), window(2, "Safari", "Palette", side: 60)])
        XCTAssertEqual(wids(resolution, "browse"), [1])
    }

    func testMembersRunInEntryOrderFrontToBack() {
        let windows = [window(1, "Notes", "Todo", z: 0), window(2, "Safari", "Back", z: 2), window(3, "Safari", "Front", z: 1)]
        let resolution = resolve([layer("desk", [app("Safari"), app("Notes")])], windows)
        XCTAssertEqual(wids(resolution, "desk"), [3, 2, 1])
        XCTAssertEqual(resolution.members(of: "desk").map(\.project), [0, 0, 1])
    }

    func testTheSameWindowIsNeverInTwoLayers() {
        let docs = window(1, "Safari", "Docs")
        let layers = [
            layer("a", [app("Safari"), app("Notes")]),
            layer("b", [app("Safari", title: "Docs"), LayerProject(clause: StudioLayerClause(appRegex: "^Saf"))]),
            layer("c", [app("Notes", pins: [pin(window(2, "Notes", "Todo"))])]),
            layer("d", [app("Safari", title: "Doc")]),
        ]
        let windows = [docs, window(2, "Notes", "Todo"), window(3, "Safari", "News"), window(4, "Notes", "Ideas")]
        let resolution = resolve(layers, windows)
        let all = layers.flatMap { wids(resolution, $0.id) }
        XCTAssertEqual(all.count, Set(all).count)
        XCTAssertEqual(Set(all), [1, 2, 3, 4])
        for layer in layers {
            for member in resolution.members(of: layer.id) {
                XCTAssertEqual(resolution.owners[member.entry.wid], LayerMembership.Owner(layerId: layer.id, project: member.project))
            }
        }
        // The title beats the app-only rule, which claims as its app
        // needle; the pin beats the bare app.
        XCTAssertEqual(resolution.owners[1]?.layerId, "b")
        XCTAssertEqual(resolution.owners[3]?.layerId, "a")
        XCTAssertEqual(resolution.owners[2]?.layerId, "c")
        XCTAssertEqual(resolution.owners[4]?.layerId, "a")
    }

    // MARK: Pins on disk

    func testAnEntryWithoutPinsReadsAndWritesAsBefore() throws {
        let old = #"{"app":"Safari","title":"Docs","tile":"left"}"#
        let entry = try JSONDecoder().decode(LayerProject.self, from: Data(old.utf8))
        XCTAssertNil(entry.pins)
        let written = String(decoding: try JSONEncoder().encode(entry), as: UTF8.self)
        XCTAssertFalse(written.contains("pins"))

        let pinned = app("Safari", title: "Docs", pins: [LayerPin(wid: 7, app: "Safari", title: "Docs")])
        let back = try JSONDecoder().decode(LayerProject.self, from: JSONEncoder().encode(pinned))
        XCTAssertEqual(back.pins, [LayerPin(wid: 7, app: "Safari", title: "Docs")])
    }

    func testOnlyASavedEntryWritesSaved() throws {
        let saved = WorkspaceManager.creating(label: "docs", windows: [window(1, "Safari", "Docs")], in: [])[0].projects[0]
        XCTAssertTrue(saved.isSaved)
        XCTAssertTrue(String(decoding: try JSONEncoder().encode(saved), as: UTF8.self).contains(#""saved":true"#))

        // A pinned entry from before `saved` was kept reads as written.
        let old = #"{"app":"Safari","title":"Docs","pins":[{"wid":7,"app":"Safari","title":"Docs"}]}"#
        let entry = try JSONDecoder().decode(LayerProject.self, from: Data(old.utf8))
        XCTAssertFalse(entry.isSaved)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(entry), as: UTF8.self).contains("saved"))
    }

    func testAPinWithoutAPidReadsAndWritesWithoutOne() throws {
        let old = try JSONDecoder().decode(LayerPin.self, from: Data(#"{"wid":7,"app":"Safari","title":"Docs"}"#.utf8))
        XCTAssertNil(old.pid)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(old), as: UTF8.self).contains("pid"))
        let kept = LayerPin(wid: 7, app: "Safari", title: "Docs", pid: 812)
        XCTAssertEqual(try JSONDecoder().decode(LayerPin.self, from: JSONEncoder().encode(kept)), kept)
    }

    // MARK: Edits

    private let plain = LayerMembership.Sources()

    func testCreatingPinsEachWindowAndTakesItFromOtherLayers() throws {
        let docs = window(1, "Safari", "Docs"), todo = window(2, "Notes", "Todo")
        // A written entry keeps its rule; a saved one goes with its pin.
        let before = [layer("safari", [app("Safari", title: "Doc", pins: [pin(docs)]), saved("Safari", title: "Docs", pins: [pin(docs)])])]
        let after = WorkspaceManager.creating(label: "Safari", windows: [docs, todo, docs], tiles: [2: "left"], in: before)
        XCTAssertEqual(after.map(\.id), ["safari", "safari-2"])
        XCTAssertEqual(after[1].projects.map(\.pins), [[pin(docs)], [pin(todo)]])
        XCTAssertEqual(after[1].projects.map(\.tile), [nil, "left"])
        XCTAssertEqual(after[0].projects.map(\.title), ["Doc"])
        XCTAssertNil(after[0].projects[0].pins)
        XCTAssertEqual(wids(resolve(after, [docs, todo]), "safari-2"), [1, 2])
    }

    func testAddingAWindowTheLayerHoldsPinsItWithoutANewEntry() throws {
        let docs = window(1, "Safari", "Docs")
        let before = [layer("browse", [app("Safari")])]
        let (after, added) = WorkspaceManager.adding([docs], to: 0, in: before, live: [docs], sources: plain)
        XCTAssertEqual(added, 0)
        XCTAssertEqual(after[0].projects.map(\.pins), [[pin(docs)]])
        let again = WorkspaceManager.adding([docs], to: 0, in: after, live: [docs], sources: plain)
        XCTAssertEqual(again.added, 0)
        XCTAssertEqual(try json(again.layers), try json(after))
    }

    func testAddingAWindowADeadPinFindsRebindsThatPin() {
        let desk = window(5, "Ghostty", "mini: fab · desk")
        let before = [layer("fab", [app("Ghostty", title: "mini: fab · old", pins: [LayerPin(wid: 99, app: "Ghostty", title: "mini: fab · desk")])])]
        let (after, added) = WorkspaceManager.adding([desk], to: 0, in: before, live: [desk], sources: plain)
        XCTAssertEqual(added, 0)
        XCTAssertEqual(after[0].projects.map(\.pins), [[LayerPin(wid: 5, app: "Ghostty", title: "mini: fab · desk", pid: 1)]])

        // Asked for by hand, even while the pin's app runs on.
        let running = [layer("fab", [app("Ghostty", title: "mini: fab · old", pins: [LayerPin(wid: 99, app: "Ghostty", title: "mini: fab · desk", pid: 1)])])]
        let again = WorkspaceManager.adding([desk], to: 0, in: running, live: [desk], sources: .init(isRunning: { _ in true }))
        XCTAssertEqual(again.added, 0)
        XCTAssertEqual(again.layers[0].projects.map(\.pins), [[LayerPin(wid: 5, app: "Ghostty", title: "mini: fab · desk", pid: 1)]])
    }

    func testAWindowWithOnlyAnAXTitleIsSavedByIt() {
        var untitled = window(1, "Ghostty", "")
        untitled.fullTitle = "mini: talkie"
        let after = WorkspaceManager.creating(label: "talkie", windows: [untitled], in: [])
        XCTAssertEqual(after[0].projects.map(\.title), ["mini: talkie"])
        XCTAssertEqual(after[0].projects[0].pins, [LayerPin(wid: 1, app: "Ghostty", title: "mini: talkie", pid: 1)])
    }

    func testRemovingDropsAnEntryItsPinAloneHeld() {
        let drifted = window(1, "Safari", "Something else now")
        let before = [layer("docs", [saved("Safari", title: "Docs", pins: [LayerPin(wid: 1, app: "Safari", title: "Docs")])])]
        let (after, removed) = WorkspaceManager.removing(1, from: 0, in: before, live: [drifted], sources: plain)
        XCTAssertTrue(removed)
        XCTAssertEqual(after[0].projects.count, 0)
    }

    func testRemovingDropsASavedEntryItsTwinWouldKeep() {
        let docs = window(1, "Safari", "Docs"), twin = window(2, "Safari", "Docs")
        let before = [layer("docs", [saved("Safari", title: "Docs", pins: [pin(docs)])])]
        let (after, removed) = WorkspaceManager.removing(1, from: 0, in: before, live: [docs, twin], sources: plain)
        XCTAssertTrue(removed)
        XCTAssertEqual(after[0].projects.count, 0)
    }

    func testASavedEntryGoesWithItsLastPin() {
        let docs = window(1, "Safari", "Docs"), twin = window(2, "Safari", "Docs")
        let before = [layer("a", [saved("Safari", title: "Docs", pins: [pin(docs)])]), layer("b", [app("Notes")])]
        let (after, _) = WorkspaceManager.adding([docs], to: 1, in: before, live: [docs, twin], sources: plain)
        XCTAssertEqual(after[0].projects.count, 0)
        XCTAssertNil(resolve(after, [docs, twin]).owners[2])
    }

    func testRemovingLeavesABroaderEntryHoldingIt() {
        let docs = window(1, "Safari", "Docs"), news = window(2, "Safari", "News")
        let before = [layer("browse", [app("Safari"), app("Safari", title: "Docs", pins: [pin(docs)])])]
        let (after, removed) = WorkspaceManager.removing(1, from: 0, in: before, live: [docs, news], sources: plain)
        XCTAssertFalse(removed)
        XCTAssertEqual(after[0].projects.map(\.app), ["Safari"])
        XCTAssertEqual(after[0].projects.map(\.title), [nil])
    }

    func testMovingPutsAPinnedWindowInTheOtherLayer() {
        let docs = window(1, "Safari", "Renamed")
        let before = [
            layer("a", [saved("Safari", title: "Docs", pins: [LayerPin(wid: 1, app: "Safari", title: "Docs")])]),
            layer("b", [app("Notes")]),
        ]
        let (after, outcome) = WorkspaceManager.moving(docs, from: 0, to: 1, in: before, live: [docs], sources: plain)
        XCTAssertEqual(outcome, .moved)
        XCTAssertEqual(after[0].projects.count, 0)
        XCTAssertEqual(after[1].projects.count, 2)
        let resolution = resolve(after, [docs])
        XCTAssertEqual(wids(resolution, "b"), [1])
        XCTAssertEqual(resolution.pinned, [1])
    }

    func testMovingOutOfABroaderEntryStillMovesIt() {
        let docs = window(1, "Safari", "Docs")
        let news = window(2, "Safari", "News")
        let before = [layer("a", [app("Safari")]), layer("b", [app("Notes")])]
        let (after, outcome) = WorkspaceManager.moving(docs, from: 0, to: 1, in: before, live: [docs, news], sources: plain)
        // The bare Safari entry stays for News; the pin in b outranks it.
        XCTAssertEqual(outcome, .moved)
        XCTAssertEqual(after[0].projects.count, 1)
        let resolution = resolve(after, [docs, news])
        XCTAssertEqual(wids(resolution, "a"), [2])
        XCTAssertEqual(wids(resolution, "b"), [1])
    }

    /// The edits of `layer-roundtrip.sh`, as values: create two layers over
    /// the same windows, add twice, take one out, delete both.
    func testTheEditRoundTripLeavesTheLayersAsTheyWere() throws {
        let docs = window(1, "Safari", "Docs"), todo = window(2, "Notes", "Todo")
        let live = [docs, todo]
        let before = [layer("work", [app("Xcode"), app("Terminal", title: "api")])]

        var all = WorkspaceManager.creating(label: "zz-a", windows: [docs, todo], in: before)
        all = WorkspaceManager.creating(label: "zz-b", windows: [docs], tiles: [1: "left"], in: all)
        // The entry zz-a saved for Docs goes with its pin.
        XCTAssertEqual(all.suffix(2).map(\.projects.count), [1, 1])

        var added: Int
        (all, added) = WorkspaceManager.adding([todo], to: 2, in: all, live: live, sources: plain)
        XCTAssertEqual(added, 1)
        let again = WorkspaceManager.adding([todo], to: 2, in: all, live: live, sources: plain)
        XCTAssertEqual(again.added, 0)
        XCTAssertEqual(try json(again.layers), try json(all))

        var removed: Bool
        (all, removed) = WorkspaceManager.removing(2, from: 1, in: all, live: live, sources: plain)
        XCTAssertTrue(removed)
        XCTAssertEqual(all.suffix(2).map(\.projects.count), [0, 2])

        all.removeLast(2)
        XCTAssertEqual(try json(all), try json(before))
    }

    /// The edits of `layer-step4.sh`: create, add, rename, take out, delete.
    func testTheAssignRoundTripLeavesTheLayersAsTheyWere() throws {
        let docs = window(1, "Safari", "Docs"), todo = window(2, "Notes", "Todo")
        let before = [layer("work", [app("Xcode")])]
        var all = WorkspaceManager.creating(label: "zz-a", windows: [docs], in: before)
        (all, _) = WorkspaceManager.adding([todo], to: 1, in: all, live: [docs, todo], sources: plain)
        all[1].label = "zz-a-edited"
        var removed: Bool
        (all, removed) = WorkspaceManager.removing(2, from: 1, in: all, live: [docs, todo], sources: plain)
        XCTAssertTrue(removed)
        XCTAssertEqual(all[1].projects.count, 1)
        all.remove(at: 1)
        XCTAssertEqual(try json(all), try json(before))
    }
}
