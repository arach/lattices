import XCTest
import CoreGraphics
import AppKit

// Private APIs (same as WindowTiler uses)
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

private let skyLight: UnsafeMutableRawPointer? = dlopen(
    "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)

private typealias SLSMainConnectionIDFunc = @convention(c) () -> Int32
private typealias SLSDisableUpdateFunc = @convention(c) (Int32) -> Int32
private typealias SLSReenableUpdateFunc = @convention(c) (Int32) -> Int32

private let _SLSMainConnectionID: SLSMainConnectionIDFunc? = {
    guard let sl = skyLight, let sym = dlsym(sl, "SLSMainConnectionID") else { return nil }
    return unsafeBitCast(sym, to: SLSMainConnectionIDFunc.self)
}()
private let _SLSDisableUpdate: SLSDisableUpdateFunc? = {
    guard let sl = skyLight, let sym = dlsym(sl, "SLSDisableUpdate") else { return nil }
    return unsafeBitCast(sym, to: SLSDisableUpdateFunc.self)
}()
private let _SLSReenableUpdate: SLSReenableUpdateFunc? = {
    guard let sl = skyLight, let sym = dlsym(sl, "SLSReenableUpdate") else { return nil }
    return unsafeBitCast(sym, to: SLSReenableUpdateFunc.self)
}()

/// Tile windows within the current Stage Manager stage.
/// Run ONE test at a time: swift test --filter StageTileTests/testMosaic
final class StageTileTests: XCTestCase {

    struct LiveWindow {
        let wid: UInt32
        let app: String
        let pid: Int32
        let title: String
        let bounds: CGRect
        let isOnScreen: Bool
    }

    func getRealWindows() -> [LiveWindow] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        let skip: Set<String> = [
            "Window Server", "Dock", "Control Center", "SystemUIServer",
            "Notification Center", "Spotlight", "WindowManager", "Lattices",
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

    func getActiveStage() -> [LiveWindow] {
        getRealWindows().filter { $0.isOnScreen && $0.bounds.width > 250 }
    }

    func detectStripWidth() -> CGFloat {
        let thumbnails = getRealWindows().filter {
            $0.isOnScreen && $0.bounds.width < 250 && $0.bounds.height < 250
            && $0.bounds.origin.x >= 0 && $0.bounds.origin.x < 300
        }
        if thumbnails.isEmpty { return 0 }
        let maxRight = thumbnails.map { $0.bounds.maxX }.max() ?? 0
        return maxRight + 12
    }

    func stageArea() -> CGRect {
        guard let screen = NSScreen.main else { return .zero }
        let visible = screen.visibleFrame
        let screenHeight = screen.frame.height
        let cgY = screenHeight - visible.origin.y - visible.height
        let strip = detectStripWidth()
        return CGRect(
            x: visible.origin.x + strip,
            y: cgY,
            width: visible.width - strip,
            height: visible.height
        )
    }

    func printStageState(label: String) {
        let active = getActiveStage()
        print("\n[\(label)] — \(active.count) windows")
        for w in active {
            print("  \(w.app) [\(w.wid)] \"\(w.title.prefix(40))\" — \(Int(w.bounds.origin.x)),\(Int(w.bounds.origin.y)) \(Int(w.bounds.width))x\(Int(w.bounds.height))")
        }
    }

    // MARK: - Batch tile (no app activation — avoids SM stage switches)

    func batchTile(_ moves: [(wid: UInt32, pid: Int32, frame: CGRect)]) {
        guard !moves.isEmpty else { return }

        var byPid: [Int32: [(wid: UInt32, target: CGRect)]] = [:]
        for move in moves {
            byPid[move.pid, default: []].append((wid: move.wid, target: move.frame))
        }

        // Freeze screen
        let cid = _SLSMainConnectionID?()
        if let cid { _ = _SLSDisableUpdate?(cid) }

        for (pid, windowMoves) in byPid {
            let appRef = AXUIElementCreateApplication(pid)
            AXUIElementSetAttributeValue(appRef, "AXEnhancedUserInterface" as CFString, false as CFTypeRef)

            var windowsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let axWindows = windowsRef as? [AXUIElement] else { continue }

            var axByWid: [UInt32: AXUIElement] = [:]
            for axWin in axWindows {
                var windowId: CGWindowID = 0
                if _AXUIElementGetWindow(axWin, &windowId) == .success {
                    axByWid[windowId] = axWin
                }
            }

            for wm in windowMoves {
                guard let axWin = axByWid[wm.wid] else { continue }

                var newSize = CGSize(width: wm.target.width, height: wm.target.height)
                var newPos = CGPoint(x: wm.target.origin.x, y: wm.target.origin.y)

                if let sv = AXValueCreate(.cgSize, &newSize) {
                    AXUIElementSetAttributeValue(axWin, kAXSizeAttribute as CFString, sv)
                }
                if let pv = AXValueCreate(.cgPoint, &newPos) {
                    AXUIElementSetAttributeValue(axWin, kAXPositionAttribute as CFString, pv)
                }
                if let sv = AXValueCreate(.cgSize, &newSize) {
                    AXUIElementSetAttributeValue(axWin, kAXSizeAttribute as CFString, sv)
                }

                AXUIElementPerformAction(axWin, kAXRaiseAction as CFString)
            }

            AXUIElementSetAttributeValue(appRef, "AXEnhancedUserInterface" as CFString, true as CFTypeRef)
            // NO app.activate() — just move windows in place without triggering SM
        }

        if let cid { _ = _SLSReenableUpdate?(cid) }
    }

    func gridShape(for count: Int) -> [Int] {
        switch count {
        case 1:  return [1]
        case 2:  return [2]
        case 3:  return [1, 2]
        case 4:  return [2, 2]
        case 5:  return [3, 2]
        case 6:  return [3, 3]
        default:
            let cols = Int(ceil(sqrt(Double(count) * 1.5)))
            var rows: [Int] = []
            var remaining = count
            while remaining > 0 {
                rows.append(min(cols, remaining))
                remaining -= cols
            }
            return rows
        }
    }

    // MARK: - Layouts (run one at a time)

    /// swift test --filter StageTileTests/testMosaic
    func testMosaic() throws {
        let smEnabled = UserDefaults(suiteName: "com.apple.WindowManager")?.bool(forKey: "GloballyEnabled") ?? false
        try XCTSkipUnless(smEnabled, "Stage Manager is OFF")

        let windows = getActiveStage()
        guard windows.count >= 2 else {
            print("Need >= 2 windows in active stage, got \(windows.count)")
            return
        }

        let area = stageArea()
        let gap: CGFloat = 6
        let shape = gridShape(for: windows.count)

        print("MOSAIC: \(windows.count) windows → \(shape)")
        printStageState(label: "BEFORE")

        var moves: [(wid: UInt32, pid: Int32, frame: CGRect)] = []
        var idx = 0
        let rows = shape.count
        let rowH = (area.height - gap * CGFloat(rows + 1)) / CGFloat(rows)

        for (row, cols) in shape.enumerated() {
            let colW = (area.width - gap * CGFloat(cols + 1)) / CGFloat(cols)
            for col in 0..<cols {
                guard idx < windows.count else { break }
                let win = windows[idx]
                moves.append((wid: win.wid, pid: win.pid, frame: CGRect(
                    x: area.origin.x + gap + CGFloat(col) * (colW + gap),
                    y: area.origin.y + gap + CGFloat(row) * (rowH + gap),
                    width: colW,
                    height: rowH
                )))
                idx += 1
            }
        }

        batchTile(moves)
        Thread.sleep(forTimeInterval: 0.3)
        printStageState(label: "AFTER")
    }

    /// swift test --filter StageTileTests/testMainSidebar
    func testMainSidebar() throws {
        let smEnabled = UserDefaults(suiteName: "com.apple.WindowManager")?.bool(forKey: "GloballyEnabled") ?? false
        try XCTSkipUnless(smEnabled, "Stage Manager is OFF")

        let windows = getActiveStage()
        guard windows.count >= 2 else { return }

        let area = stageArea()
        let gap: CGFloat = 6
        let mainW = (area.width - gap * 3) * 0.65
        let sideW = (area.width - gap * 3) * 0.35
        let sideCount = windows.count - 1
        let sideH = (area.height - gap * CGFloat(sideCount + 1)) / CGFloat(sideCount)

        print("MAIN + SIDEBAR: 1 main (65%) + \(sideCount) stacked")
        printStageState(label: "BEFORE")

        var moves: [(wid: UInt32, pid: Int32, frame: CGRect)] = []

        moves.append((wid: windows[0].wid, pid: windows[0].pid, frame: CGRect(
            x: area.origin.x + gap,
            y: area.origin.y + gap,
            width: mainW,
            height: area.height - gap * 2
        )))

        for i in 0..<sideCount {
            let win = windows[i + 1]
            moves.append((wid: win.wid, pid: win.pid, frame: CGRect(
                x: area.origin.x + gap * 2 + mainW,
                y: area.origin.y + gap + CGFloat(i) * (sideH + gap),
                width: sideW,
                height: sideH
            )))
        }

        batchTile(moves)
        Thread.sleep(forTimeInterval: 0.3)
        printStageState(label: "AFTER")
    }

    /// swift test --filter StageTileTests/testColumns
    func testColumns() throws {
        let smEnabled = UserDefaults(suiteName: "com.apple.WindowManager")?.bool(forKey: "GloballyEnabled") ?? false
        try XCTSkipUnless(smEnabled, "Stage Manager is OFF")

        let windows = getActiveStage()
        guard windows.count >= 2 else { return }

        let area = stageArea()
        let gap: CGFloat = 6
        let colW = (area.width - gap * CGFloat(windows.count + 1)) / CGFloat(windows.count)

        print("COLUMNS: \(windows.count) equal")
        printStageState(label: "BEFORE")

        let moves = windows.enumerated().map { (i, win) in
            (wid: win.wid, pid: win.pid, frame: CGRect(
                x: area.origin.x + gap + CGFloat(i) * (colW + gap),
                y: area.origin.y + gap,
                width: colW,
                height: area.height - gap * 2
            ))
        }

        batchTile(moves)
        Thread.sleep(forTimeInterval: 0.3)
        printStageState(label: "AFTER")
    }

    /// swift test --filter StageTileTests/testTallWide
    func testTallWide() throws {
        let smEnabled = UserDefaults(suiteName: "com.apple.WindowManager")?.bool(forKey: "GloballyEnabled") ?? false
        try XCTSkipUnless(smEnabled, "Stage Manager is OFF")

        let windows = getActiveStage()
        guard windows.count >= 2 else { return }

        let area = stageArea()
        let gap: CGFloat = 6

        // Terminal-like apps go tall on the left
        let terminalApps = Set(["iTerm2", "Terminal", "Alacritty", "kitty", "Warp"])
        let sorted = windows.sorted { a, b in
            let aT = terminalApps.contains(a.app)
            let bT = terminalApps.contains(b.app)
            if aT != bT { return aT }
            return a.wid < b.wid
        }

        let tallW = (area.width - gap * 3) * 0.45
        let wideW = (area.width - gap * 3) * 0.55
        let wideCount = sorted.count - 1
        let wideH = (area.height - gap * CGFloat(wideCount + 1)) / CGFloat(wideCount)

        print("TALL + WIDE: terminal left (45%), \(wideCount) stacked right (55%)")
        printStageState(label: "BEFORE")

        var moves: [(wid: UInt32, pid: Int32, frame: CGRect)] = []

        moves.append((wid: sorted[0].wid, pid: sorted[0].pid, frame: CGRect(
            x: area.origin.x + gap,
            y: area.origin.y + gap,
            width: tallW,
            height: area.height - gap * 2
        )))

        for i in 0..<wideCount {
            let win = sorted[i + 1]
            moves.append((wid: win.wid, pid: win.pid, frame: CGRect(
                x: area.origin.x + gap * 2 + tallW,
                y: area.origin.y + gap + CGFloat(i) * (wideH + gap),
                width: wideW,
                height: wideH
            )))
        }

        batchTile(moves)
        Thread.sleep(forTimeInterval: 0.3)
        printStageState(label: "AFTER")
    }
}
