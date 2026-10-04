import AppKit
import SwiftUI

/// Opt-in dev-only, isolated input fixture. Never starts the daemon or live inventory.
enum OverviewDragProbe {
    static var enabled = false
    static var events: [String] = []
    static var current = ""
    static var folder: URL?
    static func log(_ event: String) {
        DiagnosticLog.shared.info("OverviewDrag: \(current) \(event)")
        guard enabled else { return }
        events.append(current + ": " + event)
        if let folder { try? events.joined(separator: "\n").write(to: folder.appendingPathComponent("trace.log"), atomically: true, encoding: .utf8) }
    }
}

struct OverviewProbeMark: NSViewRepresentable {
    let id: String
    final class Mark: NSView { var id = ""; override func hitTest(_ point: NSPoint) -> NSView? { nil } }
    func makeNSView(context: Context) -> Mark { let v = Mark(); v.id = id; return v }
    func updateNSView(_ view: Mark, context: Context) { view.id = id }
}

final class OverviewDragFixture {
    static var retained: OverviewDragFixture?
    static var requested: Bool { CommandLine.arguments.contains("--overview-drag-fixture") }
    var window: NSWindow!
    var model: OverviewModel!
    var root: NSView!
    var results: [String: Bool] = [:]
    let names = ["screen", "thumb", "layer", "new", "cancel", "outside"]
    let suite = "overview.input-fixture." + UUID().uuidString
    static func start() -> Bool {
        guard requested else { return false }
        guard Bundle.main.bundleIdentifier == "dev.lattices.app.dev",
              let i = CommandLine.arguments.firstIndex(of: "--overview-drag-fixture"),
              CommandLine.arguments.indices.contains(i + 1) else { exit(2) }
        let path = URL(fileURLWithPath: CommandLine.arguments[i + 1]).standardizedFileURL.resolvingSymlinksInPath()
        // A dedicated temporary directory is mandatory, never the real workspace.
        guard path.path.hasPrefix("/private/tmp/") || path.path.hasPrefix("/tmp/") else { exit(2) }
        try? FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        OverviewDragProbe.folder = path; OverviewDragProbe.enabled = true
        if CommandLine.arguments.contains("--overview-carry-live") { OverviewCarryLiveProbe.start(); return true }
        let instance = OverviewDragFixture(); retained = instance; instance.startWindow()
        return true
    }
    func startWindow() {
        OverviewDragProbe.log("postAccess=\(CGPreflightPostEventAccess())")
        guard CGPreflightPostEventAccess() else { finish(error: "CGEvent posting permission missing for dev app"); return }
        let bounds = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let windows = [WindowEntry(wid: 900001, app: "TextEdit", pid: 999999, title: "Fixture draggable window",
            frame: .init(x: 0, y: 0, w: 500, h: 400), spaceIds: [2], isOnScreen: false, latticesSession: nil, zIndex: 0)]
        let layer = LayerOverview(index: 0, id: "fixture-layer", label: "Fixture layer", layout: "auto", isActive: false, entries: [])
        let defaults = UserDefaults(suiteName: suite)!
        model = OverviewModel(defaults: defaults, actions: FixtureActions(), inputs: .init(windows: windows, layers: [layer], displays: [
            .init(index: 0, name: "Fixture display", bounds: bounds, desktops: [1, 2], currentSpaceId: 1, displayId: 900)], main: bounds))
        model.restoreDisplay(900)
        model.compositionAdder = { windows, _ in
            let layers = WorkspaceManager.creating(label: "Fixture layer", windows: windows, in: [])
            try JSONEncoder().encode(layers).write(to: OverviewDragProbe.folder!.appendingPathComponent("workspace.json"), options: .atomic)
            OverviewDragProbe.log("membership-saved"); return (windows.count, "Fixture layer")
        }
        model.compositionCreator = { _ in OverviewDragProbe.log("create-blocked"); return false }
        ScreenMapWindowController.shared.probeOverview = model
        ScreenMapWindowController.shared.showScreenMapOverview()
        window = ScreenMapWindowController.shared.nsWindow
        root = window.contentView
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.run(0) }
    }

    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    func point(_ view: NSView, fraction: CGPoint = .init(x: 0.5, y: 0.5)) -> CGPoint {
        let local = CGPoint(x: view.bounds.width * fraction.x, y: view.bounds.height * fraction.y)
        let p = window.convertPoint(toScreen: view.convert(local, to: nil))
        return CGPoint(x: p.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - p.y)
    }
    func run(_ index: Int) {
        guard index < names.count else { finish(error: nil); return }
        let name = names[index]; OverviewDragProbe.current = name
        model.composition = nil; model.clearSelection(); root.layoutSubtreeIfNeeded()
        let views = descendants(root)
        if index == 0 {
            for view in views where !view.registeredDraggedTypes.isEmpty {
                OverviewDragProbe.log("registered \(type(of: view)): " + view.registeredDraggedTypes.map(\.rawValue).joined(separator: ","))
            }
        }
        guard let source = views.compactMap({ $0 as? OverviewImmediateDragSource.Source }).first(where: { $0.wid == 900001 && !$0.visibleRect.isEmpty }),
              let target = views.compactMap({ $0 as? OverviewProbeMark.Mark }).first(where: { $0.id == ["screen": "screen:900:1", "thumb": "thumb:900:1", "layer": "layer:fixture-layer", "new": "layer:__new_layer__", "cancel": "screen:900:1", "outside": "screen:900:1"][name] }) else {
            finish(error: "Fixture target missing: " + name); return
        }
        let from = point(source)
        let to = name == "outside" ? point(root, fraction: .init(x: 0.01, y: 0.05)) : point(target, fraction: .init(x: 0.3, y: 0.45))
        OverviewDragProbe.log("CGEvent from=\(from) to=\(to)")
        DispatchQueue.global(qos: .userInitiated).async {
            func post(_ type: CGEventType, _ p: CGPoint) {
                let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)!
                event.setIntegerValueField(.mouseEventClickState, value: 1)
                event.post(tap: .cghidEventTap)
            }
            post(.mouseMoved, from); Thread.sleep(forTimeInterval: 0.2)
            DiagnosticLog.shared.info("probe mouse actual=\(String(describing: CGEvent(source: nil)?.location)) requested=\(from)")
            post(.leftMouseDown, from); Thread.sleep(forTimeInterval: 0.15)
            for step in 1...35 {
                let t = CGFloat(step) / 35
                post(.leftMouseDragged, .init(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
                Thread.sleep(forTimeInterval: 0.035)
            }
            Thread.sleep(forTimeInterval: 0.4)
            if name == "cancel" {
                CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)?.post(tap: .cghidEventTap)
                Thread.sleep(forTimeInterval: 0.1)
                CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false)?.post(tap: .cghidEventTap)
            }
            post(.leftMouseUp, to)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                let lines = OverviewDragProbe.events.filter { $0.hasPrefix(name + ":") }
                let decoded = lines.filter { $0.contains("decoded-payload") }.count
                if name == "cancel" || name == "outside" {
                    self.results[name] = decoded == 0 && lines.contains { $0.contains("pointer-reject") }
                } else {
                    let receipts = lines.filter { $0.contains(name == "layer" ? "membership-saved" : "verified-fake-relocation") }.count
                    self.results[name] = decoded == 1 && (name == "new" ? self.model.composition != nil : receipts == 1)
                }
                self.run(index + 1)
            }
        }
    }
    func finish(error: String?) {
        let value: [String: Any] = ["passed": error == nil && results.count == names.count && results.values.allSatisfy { $0 }, "results": results, "error": error ?? ""]
        if let folder = OverviewDragProbe.folder, let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: folder.appendingPathComponent("result.json")) }
        UserDefaults.standard.removePersistentDomain(forName: suite)
        exit((value["passed"] as? Bool) == true ? 0 : 1)
    }
    private struct FixtureActions: OverviewActions {
        func fake(_ space: Int, snap: OverviewSnap?, completion: (String?) -> Void) {
            var state = WindowRelocation.Snapshot(frame: CGRect(x: 0, y: 0, width: 500, height: 400), displayId: "fixture", spaceIds: [2])
            let f = snap?.fractions ?? CGRect(x: 0, y: 0, width: 500.0 / 1200, height: 0.5)
            let target = CGRect(x: f.minX * 1200, y: f.minY * 800, width: f.width * 1200, height: f.height * 800)
            let environment = WindowRelocation.Environment(displays: { [.init(id: "fixture", index: 0, currentSpaceId: 1, spaceIds: [1, 2])] }, snapshot: { state }, moveSpace: { state = .init(frame: state.frame, displayId: "fixture", spaceIds: [$0]); return nil }, moveFrame: { state = .init(frame: $0, displayId: "fixture", spaceIds: [1]) }, wait: { _ in state })
            let result = WindowRelocation.execute(from: state, to: .init(displayId: "fixture", spaceId: space, frame: target), tolerance: 6, environment: environment)
            if result.verified { OverviewDragProbe.log("verified-fake-relocation") }
            completion(result.failure)
        }
        func moveToSpace(wid: UInt32, pid: Int32, spaceId: Int, displayId: UInt32, completion: @escaping (String?) -> Void) { fake(spaceId, snap: nil, completion: completion) }
        func moveAndPlace(wid: UInt32, pid: Int32, destination: OverviewMoveDestination, snap: OverviewSnap, completion: @escaping (String?) -> Void) { fake(destination.spaceId, snap: snap, completion: completion) }
        func focus(wid: UInt32, pid: Int32) {}
        func place(wid: UInt32, pid: Int32, position: TilePosition, displayId: UInt32) {}
        func distribute(_ windows: [(wid: UInt32, pid: Int32)], displayId: UInt32, shape: [Int]?) {}
        func saveLayer(_ plan: LayerEditPlan) throws {}
        func rearrange(layerId: String) throws {}
    }
}
