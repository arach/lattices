import AppKit
import ApplicationServices

/// Virtual layers. A switch hides the apps the new layer doesn't use (⌘H)
/// and parks the other windows of the apps it does use in the main screen's
/// bottom-right corner, AeroSpace-style: macOS keeps a sliver showing and
/// the rest sits off-screen. Each layer remembers what else it had showing,
/// per desktop, and gets it back on return.
///
/// Only the main screen (the one layers tile onto) takes part, and only the
/// desktop it's showing. An app with windows on another display or desktop
/// is parked rather than hidden, so those stay put. Everything happens at
/// the switch; nothing watches in between.
///
/// Parked frames are written to `~/.lattices/layer-stage.json` so a window
/// can't be stranded in the corner: quitting puts them back, and after a
/// crash the next launch does.
///
/// Not every app lets a window go off-screen: standard Cocoa windows
/// constrain an AX move to the visible frame, so "parking" one just piles it
/// in the corner. Each park is read back, and a window that didn't go past
/// the edge is put straight back and left showing.
final class LayerStage {
    static let shared = LayerStage()

    struct ParkedWindow: Codable, Equatable {
        let wid: UInt32
        let pid: Int32
        let app: String
        let title: String
        /// Where the window was before it was parked (CG, top-left origin).
        let frame: WindowFrame
    }

    struct Outcome {
        var parked = 0
        var unparked = 0
        /// Parked windows AX couldn't reach, and untracked ones in the park
        /// corner: they sit on a desktop that isn't showing.
        var stillParked = 0
        /// Windows whose app kept them on screen: put back where they were.
        var refused = 0
        /// Untracked windows found in the park corner and brought back.
        var rescued = 0
        var hidden: [String] = []
        var unhidden: [String] = []

        var summary: String {
            "parked \(parked), unparked \(unparked), still parked \(stillParked), "
                + "refused \(refused), rescued \(rescued), "
                + "hid [\(hidden.joined(separator: ", "))], unhid [\(unhidden.joined(separator: ", "))]"
        }
    }

    struct Status {
        let parked: [ParkedWindow]
        let hiddenApps: [String]
    }

    private struct State: Codable {
        var parked: [ParkedWindow] = []
        /// Apps a switch hid. Show All unhides these and leaves the apps the
        /// user hid alone.
        var hiddenPids: [Int32] = []
        /// "layer@space" → the windows that layer had showing on that
        /// desktop, beyond its own entries, when it was last left.
        var scenes: [String: [UInt32]] = [:]
    }

    /// macOS keeps a parked window's top strip on screen; a window this close
    /// to the right edge is still where a switch put it.
    private static let parkedSlack: CGFloat = 40
    /// Same bar as `DesktopModel.isPlaceableTarget`, minus `isOnScreen`, so a
    /// hidden app's windows can be parked before it reappears.
    private static let minSide: Double = 120

    private let lock = NSLock()
    private var state: State
    private let statePath: String

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        statePath = (home as NSString).appendingPathComponent(".lattices/layer-stage.json")
        state = Self.load(from: statePath) ?? State()
    }

    // MARK: - Status

    func status() -> Status {
        lock.lock(); defer { lock.unlock() }
        pruneLocked(Stage.mainBounds)
        persistLocked()
        let hidden = state.hiddenPids.compactMap { pid -> String? in
            guard let app = NSRunningApplication(processIdentifier: pid), app.isHidden else { return nil }
            return app.localizedName ?? "pid \(pid)"
        }
        return Status(parked: state.parked, hiddenApps: hidden)
    }

    // MARK: - Switch

    /// Stage a switch from `outgoing` to `incoming`.
    ///
    /// Remembers what `outgoing` had showing, puts away everything on stage
    /// that `incoming` doesn't use, and brings back what `incoming` had
    /// showing when it was left. `members` maps each layer id to every
    /// window its entries match; a window another layer claims never joins
    /// this layer's scene.
    @discardableResult
    func stage(
        outgoing: Layer?,
        incoming: Layer,
        members: [String: Set<UInt32>],
        windows: [WindowEntry]
    ) -> Outcome {
        var outcome = Outcome()
        guard let stage = Stage.current() else {
            DiagnosticLog.shared.info("LayerStage: the main screen isn't showing a desktop — leaving windows alone")
            return outcome
        }

        lock.lock()
        defer {
            persistLocked()
            lock.unlock()
        }

        pruneLocked(stage.bounds)
        let parkedWids = Set(state.parked.map(\.wid))
        let byWid = Dictionary(windows.map { ($0.wid, $0) }, uniquingKeysWith: { first, _ in first })
        let onStage = windows.filter { Self.isStageable($0) && stage.contains($0) }
        let showing = onStage.filter { $0.isOnScreen && !parkedWids.contains($0.wid) }

        // 1. What the outgoing layer had showing, beyond its own entries.
        if let outgoing {
            let own = members[outgoing.id] ?? []
            let claimed = Self.union(members, except: outgoing.id)
            state.scenes[stage.sceneKey(outgoing)] = showing.map(\.wid).filter {
                !own.contains($0) && !claimed.contains($0)
            }
        }

        // 2. What the incoming layer shows: its entries plus its scene, on
        //    desktops that are showing. Other desktops are never reached into.
        let own = members[incoming.id] ?? []
        let claimed = Self.union(members, except: incoming.id)
        let scene = (state.scenes[stage.sceneKey(incoming)] ?? []).filter { !claimed.contains($0) }
        let targets = own.union(scene).filter { wid in
            byWid[wid].map { DesktopModel.isOnCurrentSpace($0, current: stage.currentSpaceIds) } ?? false
        }
        let targetPids = Set(targets.compactMap { byWid[$0]?.pid })

        // 3. Put away what's showing and not wanted. An app with nothing
        //    wanted and nothing elsewhere is hidden outright; otherwise its
        //    windows are parked one by one. The frontmost app goes last, so
        //    each hide hands focus to an app that's staying.
        var toPark: [WindowEntry] = []
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let away = Dictionary(grouping: showing.filter { !targets.contains($0.wid) }, by: \.pid)
            .sorted { ($0.key == frontmost ? 1 : 0) < ($1.key == frontmost ? 1 : 0) }
        for (pid, strays) in away {
            guard let app = Self.stageableApp(pid) else { continue }
            let keepsWindowsElsewhere = windows.contains {
                $0.pid == pid && Self.isStageable($0) && stage.isElsewhere($0)
            }
            let hide = app.activationPolicy == .regular && !targetPids.contains(pid) && !keepsWindowsElsewhere
            if hide, app.hide() {
                outcome.hidden.append(app.localizedName ?? strays[0].app)
                if !state.hiddenPids.contains(pid) { state.hiddenPids.append(pid) }
            } else {
                toPark.append(contentsOf: strays)
            }
        }

        // 4. Bring back what the layer had showing. Unpark before unhiding,
        //    so a hidden app's windows are already home when it reappears.
        let restored = Self.restore(state.parked.filter { targets.contains($0.wid) })
        outcome.unparked = restored.count
        state.parked.removeAll { restored.contains($0.wid) }

        // 5. Unhide the layer's apps, parking their other windows first so
        //    nothing flashes.
        let hiddenTargetApps = targetPids.compactMap { pid -> NSRunningApplication? in
            guard let app = NSRunningApplication(processIdentifier: pid), app.isHidden else { return nil }
            return app
        }
        for app in hiddenTargetApps {
            toPark.append(contentsOf: onStage.filter {
                $0.pid == app.processIdentifier && !targets.contains($0.wid) && !parkedWids.contains($0.wid)
            })
        }
        if stage.canPark {
            (outcome.parked, outcome.refused) = parkLocked(toPark, at: stage.parkOrigin)
        } else if !toPark.isEmpty {
            DiagnosticLog.shared.warn("LayerStage: a display sits past the main screen's bottom-right corner — not parking \(toPark.count) windows")
        }
        for app in hiddenTargetApps {
            app.unhide()
            outcome.unhidden.append(app.localizedName ?? "pid \(app.processIdentifier)")
            state.hiddenPids.removeAll { $0 == app.processIdentifier }
        }

        outcome.stillParked = state.parked.count
        DiagnosticLog.shared.info("LayerStage: \(outgoing?.id ?? "-") → \(incoming.id): \(outcome.summary)")
        return outcome
    }

    // MARK: - Show All

    /// Unpark every parked window, unhide every app a switch hid, and forget
    /// the layers' scenes. The escape hatch: it also brings back windows
    /// sitting in the park corner that the ledger lost, such as one an app
    /// reopened where it last saw it.
    @discardableResult
    func showAll() -> Outcome {
        lock.lock()
        defer {
            persistLocked()
            lock.unlock()
        }
        var outcome = Outcome()
        pruneLocked(Stage.mainBounds)
        let restored = Self.restore(state.parked)
        outcome.unparked = restored.count
        state.parked.removeAll { restored.contains($0.wid) }
        outcome.stillParked = state.parked.count
        let strays = Self.rescueStrays(tracked: Set(state.parked.map(\.wid)))
        outcome.rescued = strays.rescued
        outcome.stillParked += strays.found - strays.rescued
        for pid in state.hiddenPids {
            guard let app = NSRunningApplication(processIdentifier: pid), app.isHidden else { continue }
            app.unhide()
            outcome.unhidden.append(app.localizedName ?? "pid \(pid)")
        }
        state.hiddenPids.removeAll()
        state.scenes.removeAll()
        DiagnosticLog.shared.info("LayerStage: show all — \(outcome.summary)")
        return outcome
    }

    /// Put parked windows back where they were. Runs on quit (the SIGTERM
    /// path included) and at launch, after a crash. Hidden apps stay hidden:
    /// that's an ordinary macOS state, and ⌘-Tab brings them back.
    @discardableResult
    func restoreParked(reason: String) -> Int {
        guard AXIsProcessTrusted() else { return 0 }
        lock.lock()
        defer { lock.unlock() }
        guard !state.parked.isEmpty else { return 0 }
        pruneLocked(Stage.mainBounds)
        let restored = Self.restore(state.parked)
        state.parked.removeAll { restored.contains($0.wid) }
        persistLocked()
        DiagnosticLog.shared.info("LayerStage: restored \(restored.count) parked windows (\(reason)); \(state.parked.count) out of reach")
        return restored.count
    }

    // MARK: - Stage geometry

    /// The main screen, the desktop it's showing, and the other displays.
    private struct Stage {
        /// CG bounds (top-left origin).
        let bounds: CGRect
        let others: [CGRect]
        let spaceId: Int
        /// The desktop showing on every display.
        let currentSpaceIds: Set<Int>

        static var mainBounds: CGRect { CGDisplayBounds(CGMainDisplayID()) }

        static func current() -> Stage? {
            let main = CGMainDisplayID()
            let all = WindowTiler.getDisplaySpaces()
            guard let display = WindowTiler.displaySpaces(forDisplayID: main, in: all),
                  display.spaces.contains(where: { $0.id == display.currentSpaceId }) else {
                return nil
            }
            return Stage(
                bounds: CGDisplayBounds(main),
                others: otherDisplayBounds(),
                spaceId: display.currentSpaceId,
                currentSpaceIds: Set(all.map(\.currentSpaceId))
            )
        }

        /// Bottom-right corner, one point in. macOS clamps the rest and
        /// leaves a sliver showing.
        var parkOrigin: CGPoint { CGPoint(x: bounds.maxX - 1, y: bounds.maxY - 1) }

        /// Parked windows hang off the corner; with another display there
        /// they'd land on it instead.
        var canPark: Bool {
            let beyond = CGRect(x: bounds.maxX - 1, y: bounds.maxY - LayerStage.parkedSlack, width: 20_000, height: 20_000)
            return !others.contains { $0.intersects(beyond) }
        }

        func sceneKey(_ layer: Layer) -> String { "\(layer.id)@\(spaceId)" }

        /// On the main screen's desktop: centred on the main screen, or
        /// hanging off its bottom-right corner.
        func contains(_ entry: WindowEntry) -> Bool {
            guard entry.spaceIds.contains(spaceId) else { return false }
            let rect = CGRect(x: entry.frame.x, y: entry.frame.y, width: entry.frame.w, height: entry.frame.h)
            let centre = CGPoint(x: rect.midX, y: rect.midY)
            if bounds.contains(centre) { return true }
            if others.contains(where: { $0.contains(centre) }) { return false }
            return rect.minX >= bounds.maxX - LayerStage.parkedSlack || bounds.intersects(rect)
        }

        /// Showing on another display, or sitting on another desktop.
        func isElsewhere(_ entry: WindowEntry) -> Bool {
            if entry.isOnScreen { return !contains(entry) }
            return !entry.spaceIds.isEmpty && currentSpaceIds.isDisjoint(with: entry.spaceIds)
        }

        static func otherDisplayBounds() -> [CGRect] {
            let main = CGMainDisplayID()
            return activeDisplays().filter { $0 != main }.map { CGDisplayBounds($0) }
        }

        private static func activeDisplays() -> [CGDirectDisplayID] {
            var count: UInt32 = 0
            guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
            var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
            guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
            return Array(ids.prefix(Int(count)))
        }
    }

    // MARK: - Helpers

    private static func isStageable(_ entry: WindowEntry) -> Bool {
        entry.axVerified && !entry.title.isEmpty
            && entry.frame.w >= minSide && entry.frame.h >= minSide
            && entry.pid != getpid()
    }

    /// Regular apps are hidden or parked, accessory apps only parked.
    /// Background agents and Lattices' own apps are left alone.
    private static func stageableApp(_ pid: Int32) -> NSRunningApplication? {
        guard let app = NSRunningApplication(processIdentifier: pid),
              app.activationPolicy != .prohibited,
              !LatticesRuntime.isLatticesBundleIdentifier(app.bundleIdentifier) else { return nil }
        return app
    }

    private static func union(_ members: [String: Set<UInt32>], except id: String) -> Set<UInt32> {
        members.reduce(into: Set<UInt32>()) { result, pair in
            if pair.key != id { result.formUnion(pair.value) }
        }
    }

    /// Forget parked windows that closed, or that were dragged back by hand.
    private func pruneLocked(_ main: CGRect) {
        state.parked.removeAll { parked in
            guard let live = Self.liveWindow(parked.wid), live.pid == parked.pid else { return true }
            return live.frame.minX < main.maxX - Self.parkedSlack
        }
        state.hiddenPids.removeAll { NSRunningApplication(processIdentifier: $0) == nil }
    }

    /// Park windows at `origin`, keeping their size. The ledger is written
    /// before anything moves, so a crash mid-switch can't lose a window.
    /// Returns how many parked, and how many the app kept on screen; those
    /// go straight back to where they were.
    private func parkLocked(_ entries: [WindowEntry], at origin: CGPoint) -> (parked: Int, refused: Int) {
        let fresh = entries.filter { entry in !state.parked.contains { $0.wid == entry.wid } }
        guard !fresh.isEmpty else { return (0, 0) }
        state.parked.append(contentsOf: fresh.map {
            ParkedWindow(wid: $0.wid, pid: $0.pid, app: $0.app, title: $0.title, frame: $0.frame)
        })
        persistLocked()

        let byWid = Dictionary(fresh.map { ($0.wid, $0) }, uniquingKeysWith: { first, _ in first })
        var moved = Set<UInt32>()
        var refused = 0
        Self.withAXWindows(for: fresh.map { ($0.wid, $0.pid) }) { wid, axWindow in
            guard !Self.isMinimized(axWindow) else { return }
            var point = origin
            guard let value = AXValueCreate(.cgPoint, &point),
                  AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, value) == .success else { return }
            // A Cocoa window constrains the move to the screen; it lands in
            // the corner in full view. Put it back rather than lose it there.
            guard let landed = Self.position(of: axWindow), landed.x >= origin.x + 1 - Self.parkedSlack else {
                if let entry = byWid[wid] {
                    var home = CGPoint(x: entry.frame.x, y: entry.frame.y)
                    if let back = AXValueCreate(.cgPoint, &home) {
                        AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, back)
                    }
                }
                refused += 1
                return
            }
            moved.insert(wid)
        }
        let attempted = Set(fresh.map(\.wid))
        state.parked.removeAll { attempted.contains($0.wid) && !moved.contains($0.wid) }
        if refused > 0 {
            DiagnosticLog.shared.info("LayerStage: \(refused) windows stayed on screen when parked — left where they were")
        }
        return (moved.count, refused)
    }

    /// Bring back windows sitting in the main screen's park corner that
    /// aren't in the ledger. Centres each on the main screen, keeping its
    /// size. Only reaches desktops that are showing; the rest count as found
    /// but not rescued.
    private static func rescueStrays(tracked: Set<UInt32>) -> (found: Int, rescued: Int) {
        let bounds = Stage.mainBounds
        let others = Stage.otherDisplayBounds()
        let beyond = CGRect(x: bounds.maxX - parkedSlack, y: bounds.minY, width: 20_000, height: bounds.height)
        guard !others.contains(where: { $0.intersects(beyond) }) else {
            DiagnosticLog.shared.info("LayerStage: a display sits right of the main screen — not rescuing corner windows")
            return (0, 0)
        }
        guard let info = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return (0, 0) }
        var strays: [(wid: UInt32, pid: Int32, size: CGSize)] = []
        for window in info {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let wid = window[kCGWindowNumber as String] as? UInt32, !tracked.contains(wid),
                  let pid = window[kCGWindowOwnerPID as String] as? Int32, pid != getpid(),
                  stageableApp(pid) != nil,
                  let dict = window[kCGWindowBounds as String] as? NSDictionary else { continue }
            var rect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(dict, &rect),
                  rect.width >= minSide, rect.height >= minSide,
                  rect.minX >= bounds.maxX - parkedSlack, rect.minX < bounds.maxX,
                  rect.minY >= bounds.minY, rect.minY < bounds.maxY else { continue }
            strays.append((wid, pid, rect.size))
        }
        guard !strays.isEmpty else { return (0, 0) }
        let sizes = Dictionary(strays.map { ($0.wid, $0.size) }, uniquingKeysWith: { first, _ in first })
        var rescued = 0
        withAXWindows(for: strays.map { ($0.wid, $0.pid) }) { wid, axWindow in
            guard let size = sizes[wid] else { return }
            var point = CGPoint(
                x: bounds.midX - min(size.width, bounds.width) / 2,
                y: max(bounds.minY, bounds.midY - min(size.height, bounds.height) / 2)
            )
            guard let value = AXValueCreate(.cgPoint, &point),
                  AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, value) == .success else { return }
            rescued += 1
        }
        return (strays.count, rescued)
    }

    /// Move parked windows back to their saved frames. Returns the ones AX
    /// reached; a window on a desktop that isn't showing stays parked.
    private static func restore(_ parked: [ParkedWindow]) -> Set<UInt32> {
        guard !parked.isEmpty else { return [] }
        let byWid = Dictionary(parked.map { ($0.wid, $0) }, uniquingKeysWith: { first, _ in first })
        var restored = Set<UInt32>()
        withAXWindows(for: parked.map { ($0.wid, $0.pid) }) { wid, axWindow in
            guard let saved = byWid[wid] else { return }
            var point = CGPoint(x: saved.frame.x, y: saved.frame.y)
            var size = CGSize(width: saved.frame.w, height: saved.frame.h)
            guard let position = AXValueCreate(.cgPoint, &point),
                  AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, position) == .success else { return }
            // Size after position: in the corner, macOS may have squeezed it.
            if let value = AXValueCreate(.cgSize, &size) {
                AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, value)
            }
            restored.insert(wid)
        }
        return restored
    }

    /// Resolve AX windows by CGWindowID, one AX query per app. AX lists only
    /// the windows on desktops that are showing.
    private static func withAXWindows(
        for targets: [(wid: UInt32, pid: Int32)],
        _ body: (UInt32, AXUIElement) -> Void
    ) {
        for (pid, wanted) in Dictionary(grouping: targets, by: { $0.pid }) {
            let appRef = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appRef, 0.5)
            var windowsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let axWindows = windowsRef as? [AXUIElement] else { continue }

            // Enhanced UI makes Chrome and friends animate AX moves; switch
            // it off while moving, and put it back after.
            var enhancedRef: CFTypeRef?
            let enhanced = AXUIElementCopyAttributeValue(appRef, "AXEnhancedUserInterface" as CFString, &enhancedRef) == .success
                && (enhancedRef as? Bool) == true
            if enhanced {
                AXUIElementSetAttributeValue(appRef, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
            }
            defer {
                if enhanced {
                    AXUIElementSetAttributeValue(appRef, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
                }
            }

            let wids = Set(wanted.map(\.wid))
            for axWindow in axWindows {
                var wid: CGWindowID = 0
                guard _AXUIElementGetWindow(axWindow, &wid) == .success, wids.contains(wid) else { continue }
                body(wid, axWindow)
            }
        }
    }

    private static func position(of axWindow: AXUIElement) -> CGPoint? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(ref as! AXValue, .cgPoint, &point) ? point : nil
    }

    private static func isMinimized(_ axWindow: AXUIElement) -> Bool {
        var ref: CFTypeRef?
        return AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &ref) == .success
            && (ref as? Bool) == true
    }

    /// A window's owner and CG frame, or nil once it's gone.
    private static func liveWindow(_ wid: UInt32) -> (pid: Int32, frame: CGRect)? {
        guard let info = (CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(wid)) as? [[String: Any]])?.first,
              let pid = info[kCGWindowOwnerPID as String] as? Int32,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
        var rect = CGRect.zero
        guard CGRectMakeWithDictionaryRepresentation(bounds, &rect) else { return nil }
        return (pid, rect)
    }

    // MARK: - Persistence

    private static func load(from path: String) -> State? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONDecoder().decode(State.self, from: data)
    }

    private func persistLocked() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(state) else { return }
        let url = URL(fileURLWithPath: statePath)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
