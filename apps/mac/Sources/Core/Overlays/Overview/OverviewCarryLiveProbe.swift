import AppKit
import SwiftUI
import HudsonObservability

/// Explicit, dev-only acceptance probe. The caller creates ONE uniquely named
/// TextEdit document. All live actions are restricted to that exact window ID.
/// Never starts inventory, layer persistence, or the daemon.
final class OverviewCarryLiveProbe {
    static var retained: OverviewCarryLiveProbe?
    var fixture = OverviewDragFixture()
    var wid: UInt32 = 0
    var pid: Int32 = 0
    var title = ""
    var display: OverviewDisplay!
    var initial: [DisplaySpaces] = []
    var original = 0
    var next = 0
    var phase = 0
    var results: [[String: Any]] = []
    let suite = "overview.carry-probe." + UUID().uuidString

    static func start() {
        HudLoggerSinks.install(LatticesLogDiskSink.shared)
        let probe = OverviewCarryLiveProbe(); retained = probe
        probe.prepare()
    }
    func prepare() {
        guard CGPreflightPostEventAccess(), AXIsProcessTrusted(),
              let index = CommandLine.arguments.firstIndex(of: "--overview-carry-live"),
              CommandLine.arguments.indices.contains(index + 1) else { finish("Missing explicit live-test document or existing permissions"); return }
        let file = URL(fileURLWithPath: CommandLine.arguments[index + 1]).standardizedFileURL.resolvingSymlinksInPath()
        guard (file.path.hasPrefix("/private/tmp/") || file.path.hasPrefix("/tmp/")), file.lastPathComponent.hasPrefix("lattices-carry-test"), FileManager.default.fileExists(atPath: file.path) else { finish("Unsafe test document path: \(file.path); exists=\(FileManager.default.fileExists(atPath: file.path))"); return }
        title = file.lastPathComponent
        guard let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]],
              let window = windows.first(where: { ($0[kCGWindowOwnerName as String] as? String) == "TextEdit" && ($0[kCGWindowName as String] as? String) == title }),
              let id = window[kCGWindowNumber as String] as? UInt32,
              let owner = window[kCGWindowOwnerPID as String] as? Int32 else { finish("Unique test TextEdit window not found"); return }
        wid = id; pid = owner
        initial = WindowTiler.getDisplaySpaces()
        guard let main = WindowTiler.displaySpaces(forDisplayID: CGMainDisplayID(), in: initial),
              let currentIndex = main.spaces.firstIndex(where: { $0.id == main.currentSpaceId }),
              main.spaces.indices.contains(currentIndex + 1),
              WindowTiler.getSpacesForWindow(wid) == [main.currentSpaceId],
              let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == CGMainDisplayID() }) else { finish("Test window must be on main display's current ordinary desktop, with a next desktop"); return }
        original = main.currentSpaceId; next = main.spaces[currentIndex + 1].id
        let bounds = DisplayGeometryMapper.topLeftFrame(screen.frame, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
        display = OverviewDisplay(index: main.displayIndex, name: screen.localizedName, bounds: bounds, desktops: main.spaces.map(\.id), currentSpaceId: original, displayId: CGMainDisplayID())
        guard let entry = entry(), bounds.contains(CGPoint(x: entry.frame.x + entry.frame.w / 2, y: entry.frame.y + entry.frame.h / 2)) else { finish("Test window is not on main display"); return }
        if CommandLine.arguments.contains("--overview-carry-inspect-only") {
            DispatchQueue.global(qos: .userInitiated).async {
                WindowSpaceCarry.inspectOnly(wid: self.wid)
                DispatchQueue.main.async { self.finish(nil) }
            }
            return
        }
        let actions = RestrictedActions(wid: wid, pid: pid, allowedSpaces: [original, next])
        fixture.model = OverviewModel(defaults: UserDefaults(suiteName: suite)!, actions: actions,
            inputs: .init(windows: [entry], displays: [display], main: bounds))
        fixture.model.restoreDisplay(display.displayId)
        fixture.model.compositionAdder = { _, _ in throw NSError(domain: "LiveProbe", code: 1) }
        fixture.model.compositionCreator = { _ in false }
        fixture.root = NSHostingView(rootView: OverviewView(model: fixture.model, controller: ScreenMapController(), live: false, fixtureInteractions: true).environment(\.colorScheme, .dark))
        fixture.window = NSWindow(contentRect: CGRect(x: screen.frame.minX + 60, y: screen.frame.minY + 80, width: min(1050, screen.frame.width - 120), height: min(650, screen.frame.height - 160)), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        fixture.window.title = "Lattices — bounded live carry test"
        fixture.window.contentView = fixture.root
        fixture.window.collectionBehavior = [.canJoinAllSpaces, .transient]
        NSApp.setActivationPolicy(.regular)
        fixture.window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        OverviewDragProbe.log("LIVE test-only wid=\(wid) pid=\(pid) source=\(original) next=\(next) initialViews=\(initial.map { $0.currentSpaceId })")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.run() }
    }
    func entry() -> WindowEntry? {
        guard let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, wid) as? [[String: Any]],
              let info = list.first, info[kCGWindowName as String] as? String == title,
              let b = info[kCGWindowBounds as String] as? [String: Any],
              let frame = CGRect(dictionaryRepresentation: b as CFDictionary) else { return nil }
        return WindowEntry(wid: wid, app: "TextEdit", pid: pid, title: title, frame: .init(x: frame.minX, y: frame.minY, w: frame.width, h: frame.height), spaceIds: WindowTiler.getSpacesForWindow(wid), isOnScreen: info[kCGWindowIsOnscreen as String] as? Bool ?? false, latticesSession: nil, zIndex: 0)
    }
    func run() {
        guard phase < 2 else { finish(nil); return }
        // One read-only inventory sweep lets the production runtime resolve wid.
        DesktopModel.shared.refreshNow()
        let targetSpace = phase == 0 ? next : original
        OverviewDragProbe.current = phase == 0 ? "live-out-thumbnail" : "live-back-map"
        guard let entry = entry() else { finish("Test window disappeared"); return }
        fixture.model.update(.init(windows: [entry], displays: [display], main: display.bounds))
        fixture.model.clearSelection(); fixture.root.layoutSubtreeIfNeeded()
        let views = fixture.descendants(fixture.root)
        let marker = "\(phase == 0 ? "thumb" : "screen"):\(display.displayId):\(targetSpace)"
        guard let source = views.compactMap({ $0 as? OverviewImmediateDragSource.Source }).first(where: { $0.wid == wid && !$0.visibleRect.isEmpty }),
              let target = views.compactMap({ $0 as? OverviewProbeMark.Mark }).first(where: { $0.id == marker }) else { finish("Source or destination missing: \(marker)"); return }
        fixture.window.makeKeyAndOrderFront(nil); fixture.window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        let from = fixture.point(source), to = fixture.point(target, fraction: .init(x: 0.3, y: 0.45))
        let front = OverviewImmediateDragSource.Source.frontmost(in: fixture.root, windowPoint: source.convert(CGPoint(x: source.bounds.midX, y: source.bounds.midY), to: nil))
        OverviewDragProbe.log("frontmost-is-source=\(front === source) postAccess=\(CGPreflightPostEventAccess())")
        OverviewDragProbe.log("input-window=\(fixture.window.windowNumber) key=\(fixture.window.isKeyWindow) appActive=\(NSApp.isActive) source=\(source.frame)")
        let capture = Process(); capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-l", String(fixture.window.windowNumber), OverviewDragProbe.folder!.appendingPathComponent("live-\(phase).png").path]
        try? capture.run()
        OverviewDragProbe.log("CGEvent wid=\(wid) from=\(from) to=\(to) target=\(targetSpace)")
        DispatchQueue.global(qos: .userInitiated).async {
            func post(_ type: CGEventType, _ point: CGPoint) {
                let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)!
                event.setIntegerValueField(.mouseEventClickState, value: 1); event.post(tap: .cghidEventTap)
            }
            Thread.sleep(forTimeInterval: 0.8)
            post(.mouseMoved, from); Thread.sleep(forTimeInterval: 0.2)
            DiagnosticLog.shared.info("probe mouse actual=\(String(describing: CGEvent(source: nil)?.location)) requested=\(from)")
            post(.leftMouseDown, from); Thread.sleep(forTimeInterval: 0.15)
            for i in 1...35 {
                let t = CGFloat(i) / 35
                post(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
                Thread.sleep(forTimeInterval: 0.035)
            }
            Thread.sleep(forTimeInterval: 0.4); post(.leftMouseUp, to)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.check(targetSpace, remaining: 45) }
        }
    }
    func check(_ target: Int, remaining: Int) {
        if !fixture.model.moving.isEmpty, remaining > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.check(target, remaining: remaining - 1) }; return
        }
        let spaces = WindowTiler.getSpacesForWindow(wid)
        let views = WindowTiler.getDisplaySpaces()
        let stayed = initial.allSatisfy { start in views.first { $0.displayId == start.displayId }?.currentSpaceId == start.currentSpaceId }
        let decoded = OverviewDragProbe.events.contains { $0.hasPrefix(OverviewDragProbe.current + ": decoded-payload") }
        let passed = decoded && spaces == [target] && stayed && fixture.model.moving.isEmpty
        let result: [String: Any] = ["phase": phase, "wid": wid, "target": target, "spaces": spaces, "viewsUnchanged": stayed, "passed": passed, "receipt": fixture.model.actionError ?? fixture.model.compositionNotice ?? "none"]
        results.append(result); OverviewDragProbe.log("LIVE result=\(result)")
        if !passed { finish("Live drop did not verify; no automatic retry"); return }
        phase += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.run() }
    }
    func finish(_ error: String?) {
        // A failure must not leave the user's desktop view changed.
        let starts = initial
        DispatchQueue.global(qos: .userInitiated).async {
            for start in starts where WindowTiler.getDisplaySpaces().first(where: { $0.displayId == start.displayId })?.currentSpaceId != start.currentSpaceId {
                _ = WindowTiler.switchToSpace(spaceId: start.currentSpaceId)
            }
            DispatchQueue.main.async {
                let result: [String: Any] = ["passed": error == nil && self.results.count == 2, "error": error ?? "", "results": self.results, "wid": self.wid, "spacesAtEnd": self.wid == 0 ? [] : WindowTiler.getSpacesForWindow(self.wid)]
                if let folder = OverviewDragProbe.folder, let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: folder.appendingPathComponent("result.json")) }
                UserDefaults.standard.removePersistentDomain(forName: self.suite)
                exit(error == nil ? 0 : 1)
            }
        }
    }
    private struct RestrictedActions: OverviewActions {
        let wid: UInt32
        let pid: Int32
        let allowedSpaces: Set<Int>
        let live = LiveOverviewActions()
        func moveToSpace(wid: UInt32, pid: Int32, spaceId: Int, displayId: UInt32, completion: @escaping (String?) -> Void) {
            guard wid == self.wid, pid == self.pid, allowedSpaces.contains(spaceId), displayId == CGMainDisplayID() else { completion("Live probe rejected an unowned window or destination"); return }
            live.moveToSpace(wid: wid, pid: pid, spaceId: spaceId, displayId: displayId, completion: completion)
        }
        func moveAndPlace(wid: UInt32, pid: Int32, destination: OverviewMoveDestination, snap: OverviewSnap, completion: @escaping (String?) -> Void) {
            guard wid == self.wid, pid == self.pid, allowedSpaces.contains(destination.spaceId), destination.displayId == CGMainDisplayID() else { completion("Live probe rejected an unowned window or destination"); return }
            live.moveAndPlace(wid: wid, pid: pid, destination: destination, snap: snap, completion: completion)
        }
        func focus(wid: UInt32, pid: Int32) {}
        func place(wid: UInt32, pid: Int32, position: TilePosition, displayId: UInt32) {}
        func distribute(_ windows: [(wid: UInt32, pid: Int32)], displayId: UInt32, shape: [Int]?) {}
        func saveLayer(_ plan: LayerEditPlan) throws { throw NSError(domain: "LiveProbe", code: 1) }
        func rearrange(layerId: String) throws { throw NSError(domain: "LiveProbe", code: 1) }
    }
}
