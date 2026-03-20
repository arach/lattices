import XCTest
import CoreGraphics
import AppKit

/// Experiments: can we programmatically create a new stage by joining windows?
///
/// Stage Manager groups windows into stages. When a user drags a window from
/// the strip onto the center stage, it joins that stage. Can we replicate this
/// via AX, CGS, or simulated events?
final class StageJoinTests: XCTestCase {

    // MARK: - Helpers

    struct LiveWindow {
        let wid: UInt32
        let app: String
        let pid: Int32
        let title: String
        let bounds: CGRect
        let isOnScreen: Bool
    }

    /// Get all real app windows (layer 0, >= 50x50)
    func getRealWindows() -> [LiveWindow] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        let skip: Set<String> = [
            "Window Server", "Dock", "Control Center", "SystemUIServer",
            "Notification Center", "Spotlight", "WindowManager",
            "Lattices",
        ]

        return list.compactMap { info in
            guard let wid = info[kCGWindowNumber as String] as? UInt32,
                  let owner = info[kCGWindowOwnerName as String] as? String,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary
            else { return nil }

            var rect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict, &rect) else { return nil }
            let title = info[kCGWindowName as String] as? String ?? ""
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            let isOnScreen = info[kCGWindowIsOnscreen as String] as? Bool ?? false

            guard layer == 0, rect.width >= 50, rect.height >= 50 else { return nil }
            guard !skip.contains(owner) else { return nil }

            return LiveWindow(wid: wid, app: owner, pid: pid, title: title,
                            bounds: rect, isOnScreen: isOnScreen)
        }
    }

    /// Get AX window elements for a PID
    func getAXWindows(pid: Int32) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref) == .success,
              let windows = ref as? [AXUIElement] else { return [] }
        return windows
    }

    /// Move an AX window to a position
    func moveAXWindow(_ axWin: AXUIElement, to point: CGPoint) -> Bool {
        var p = point
        let posValue = AXValueCreate(.cgPoint, &p)!
        return AXUIElementSetAttributeValue(axWin, kAXPositionAttribute as CFString, posValue) == .success
    }

    /// Resize an AX window
    func resizeAXWindow(_ axWin: AXUIElement, to size: CGSize) -> Bool {
        var s = size
        let sizeValue = AXValueCreate(.cgSize, &s)!
        return AXUIElementSetAttributeValue(axWin, kAXSizeAttribute as CFString, sizeValue) == .success
    }

    /// Raise an AX window
    func raiseAXWindow(_ axWin: AXUIElement) -> Bool {
        AXUIElementPerformAction(axWin, kAXRaiseAction as CFString) == .success
    }

    /// Snapshot which windows are onscreen (active stage)
    func activeStageWids() -> Set<UInt32> {
        Set(getRealWindows().filter { $0.isOnScreen && $0.bounds.width > 250 }.map(\.wid))
    }

    /// Print stage state
    func printStageState(label: String) {
        let windows = getRealWindows()
        let active = windows.filter { $0.isOnScreen && $0.bounds.width > 250 }
        let strip = windows.filter { $0.isOnScreen && $0.bounds.width < 250 && $0.bounds.origin.x < 220 }
        print("\n[\(label)]")
        print("  Active stage: \(active.map { "\($0.app)(\($0.wid))" }.joined(separator: ", "))")
        print("  Strip: \(Set(strip.map(\.app)).sorted().joined(separator: ", "))")
    }

    // MARK: - Approach 1: Activate two apps rapidly

    func testJoinByActivation() throws {
        let smEnabled = UserDefaults(suiteName: "com.apple.WindowManager")?.bool(forKey: "GloballyEnabled") ?? false
        try XCTSkipUnless(smEnabled, "Stage Manager is OFF")

        let windows = getRealWindows()

        // Find two different apps that are NOT in the current stage
        let offscreenApps = Dictionary(grouping: windows.filter { !$0.isOnScreen && $0.bounds.width > 250 },
                                       by: \.app)
        let candidates = offscreenApps.keys.sorted()
        guard candidates.count >= 2 else {
            print("Need at least 2 offscreen apps, found: \(candidates)")
            return
        }

        let appA = candidates[0]
        let appB = candidates[1]
        let winA = offscreenApps[appA]!.first!
        let winB = offscreenApps[appB]!.first!

        print("Attempting to join \(appA) and \(appB) by rapid activation")
        printStageState(label: "BEFORE")

        // Activate app A
        let nsAppA = NSRunningApplication(processIdentifier: winA.pid)
        nsAppA?.activate()
        Thread.sleep(forTimeInterval: 0.3)

        printStageState(label: "After activating \(appA)")

        // Now immediately activate app B — does SM merge them?
        let nsAppB = NSRunningApplication(processIdentifier: winB.pid)
        nsAppB?.activate()
        Thread.sleep(forTimeInterval: 0.5)

        printStageState(label: "After activating \(appB)")

        // Check: are both apps in the active stage?
        let finalActive = getRealWindows().filter { $0.isOnScreen && $0.bounds.width > 250 }
        let activeApps = Set(finalActive.map(\.app))
        let joined = activeApps.contains(appA) && activeApps.contains(appB)
        print("\nResult: both apps in active stage? \(joined)")
        print("Active apps: \(activeApps.sorted())")
    }

    // MARK: - Approach 2: Move offscreen window into active stage area via AX

    func testJoinByAXMove() throws {
        let smEnabled = UserDefaults(suiteName: "com.apple.WindowManager")?.bool(forKey: "GloballyEnabled") ?? false
        try XCTSkipUnless(smEnabled, "Stage Manager is OFF")

        let windows = getRealWindows()

        // Find the active stage center
        let activeWindows = windows.filter { $0.isOnScreen && $0.bounds.width > 250 }
        guard let anchor = activeWindows.first else {
            print("No active stage window found")
            return
        }

        // Find an offscreen app to pull in
        let offscreen = windows.filter { !$0.isOnScreen && $0.bounds.width > 250 && $0.app != anchor.app }
        guard let target = offscreen.first else {
            print("No offscreen window to test with")
            return
        }

        print("Attempting to join \(target.app)[\(target.wid)] into \(anchor.app)'s stage via AX move")
        printStageState(label: "BEFORE")

        // Get AX window for target
        let axWindows = getAXWindows(pid: target.pid)
        guard let axWin = axWindows.first else {
            print("Could not get AX window for \(target.app)")
            return
        }

        // Move it right next to the anchor window
        let destPoint = CGPoint(x: anchor.bounds.origin.x + 50, y: anchor.bounds.origin.y + 50)
        let moved = moveAXWindow(axWin, to: destPoint)
        print("AX move result: \(moved)")

        // Raise it
        let raised = raiseAXWindow(axWin)
        print("AX raise result: \(raised)")

        Thread.sleep(forTimeInterval: 0.5)
        printStageState(label: "After AX move + raise")

        // Did it join the stage?
        let finalActive = getRealWindows().filter { $0.isOnScreen && $0.bounds.width > 250 }
        let activeApps = Set(finalActive.map(\.app))
        let joined = activeApps.contains(target.app) && activeApps.contains(anchor.app)
        print("\nResult: \(target.app) joined \(anchor.app)'s stage? \(joined)")
        print("Active apps: \(activeApps.sorted())")
    }

    // MARK: - Approach 3: AX move + activate target app (without switching stage)

    func testJoinByMoveAndActivate() throws {
        let smEnabled = UserDefaults(suiteName: "com.apple.WindowManager")?.bool(forKey: "GloballyEnabled") ?? false
        try XCTSkipUnless(smEnabled, "Stage Manager is OFF")

        let windows = getRealWindows()
        let activeWindows = windows.filter { $0.isOnScreen && $0.bounds.width > 250 }
        guard let anchor = activeWindows.first else { return }

        let offscreen = windows.filter { !$0.isOnScreen && $0.bounds.width > 250 && $0.app != anchor.app }
        guard let target = offscreen.first else { return }

        print("Attempting: move \(target.app) via AX, then activate it")
        printStageState(label: "BEFORE")

        // Step 1: Move target window into center area via AX
        let axWindows = getAXWindows(pid: target.pid)
        guard let axWin = axWindows.first else { return }

        let dest = CGPoint(x: anchor.bounds.midX, y: anchor.bounds.midY)
        _ = moveAXWindow(axWin, to: dest)
        _ = resizeAXWindow(axWin, to: CGSize(width: 800, height: 600))

        Thread.sleep(forTimeInterval: 0.2)

        // Step 2: Activate anchor app first (keep it in stage)
        NSRunningApplication(processIdentifier: anchor.pid)?.activate()
        Thread.sleep(forTimeInterval: 0.1)

        // Step 3: Raise the target window (without activate, to avoid stage switch)
        _ = raiseAXWindow(axWin)

        Thread.sleep(forTimeInterval: 0.5)
        printStageState(label: "After move + raise (no activate)")

        // Step 4: Now try activating both
        NSRunningApplication(processIdentifier: anchor.pid)?.activate()
        Thread.sleep(forTimeInterval: 0.1)
        // Use AX to set focused on target window
        AXUIElementSetAttributeValue(axWin, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(axWin, kAXMainAttribute as CFString, kCFBooleanTrue)

        Thread.sleep(forTimeInterval: 0.5)
        printStageState(label: "After setting focus+main on target")

        let finalActive = getRealWindows().filter { $0.isOnScreen && $0.bounds.width > 250 }
        let activeApps = Set(finalActive.map(\.app))
        let joined = activeApps.contains(target.app) && activeApps.contains(anchor.app)
        print("\nResult: joined? \(joined) — active apps: \(activeApps.sorted())")
    }

    // MARK: - Approach 4: CGS space manipulation — put both windows on same space

    func testJoinBySameSpace() throws {
        let smEnabled = UserDefaults(suiteName: "com.apple.WindowManager")?.bool(forKey: "GloballyEnabled") ?? false
        try XCTSkipUnless(smEnabled, "Stage Manager is OFF")

        // Load CGS functions
        typealias CGSConnectionID = UInt32
        typealias CGSMainConnectionIDFunc = @convention(c) () -> CGSConnectionID
        typealias CGSAddWindowsToSpacesFunc = @convention(c) (CGSConnectionID, CFArray, CFArray) -> Void
        typealias CGSGetActiveSpaceFunc = @convention(c) (CGSConnectionID) -> Int

        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let mainConnSym = dlsym(handle, "CGSMainConnectionID"),
              let addToSpacesSym = dlsym(handle, "CGSAddWindowsToSpaces"),
              let activeSpaceSym = dlsym(handle, "CGSGetActiveSpace")
        else {
            print("Could not load SkyLight functions")
            return
        }

        let CGSMainConnectionID = unsafeBitCast(mainConnSym, to: CGSMainConnectionIDFunc.self)
        let CGSAddWindowsToSpaces = unsafeBitCast(addToSpacesSym, to: CGSAddWindowsToSpacesFunc.self)
        let CGSGetActiveSpace = unsafeBitCast(activeSpaceSym, to: CGSGetActiveSpaceFunc.self)

        let cid = CGSMainConnectionID()
        let activeSpace = CGSGetActiveSpace(cid)
        print("Connection: \(cid), Active space: \(activeSpace)")

        let windows = getRealWindows()
        let activeWindows = windows.filter { $0.isOnScreen && $0.bounds.width > 250 }
        guard let anchor = activeWindows.first else { return }

        let offscreen = windows.filter { !$0.isOnScreen && $0.bounds.width > 250 && $0.app != anchor.app }
        guard let target = offscreen.first else { return }

        print("Attempting: add \(target.app)[\(target.wid)] to space \(activeSpace) via CGSAddWindowsToSpaces")
        printStageState(label: "BEFORE")

        // Add target window to active space
        let windowIDs = [target.wid] as CFArray
        let spaceIDs = [activeSpace] as CFArray
        CGSAddWindowsToSpaces(cid, windowIDs, spaceIDs)

        Thread.sleep(forTimeInterval: 0.5)
        printStageState(label: "After CGSAddWindowsToSpaces")

        // Also try raising it via AX
        let axWindows = getAXWindows(pid: target.pid)
        if let axWin = axWindows.first {
            _ = raiseAXWindow(axWin)
            Thread.sleep(forTimeInterval: 0.3)
            printStageState(label: "After raise")
        }

        let finalActive = getRealWindows().filter { $0.isOnScreen && $0.bounds.width > 250 }
        let activeApps = Set(finalActive.map(\.app))
        let joined = activeApps.contains(target.app) && activeApps.contains(anchor.app)
        print("\nResult: joined? \(joined) — active apps: \(activeApps.sorted())")

        dlclose(handle)
    }
}
