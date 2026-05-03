import XCTest
import CoreGraphics
import AppKit

/// Attempt to create stages by simulating drag gestures from the strip.
///
/// When a user drags a strip thumbnail into the center stage, SM joins them.
/// Can we replicate this with synthetic mouse events?
final class StageDragTests: XCTestCase {

    // MARK: - Helpers

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

    /// Find strip thumbnails (small onscreen windows on the left edge)
    func getStripThumbnails() -> [LiveWindow] {
        getRealWindows().filter {
            $0.isOnScreen && $0.bounds.width < 250 && $0.bounds.height < 250
            && $0.bounds.origin.x < 220 && $0.bounds.origin.x >= 0
        }
    }

    /// Find active stage windows (large onscreen windows)
    func getActiveStage() -> [LiveWindow] {
        getRealWindows().filter { $0.isOnScreen && $0.bounds.width > 250 }
    }

    func printStageState(label: String) {
        let active = getActiveStage()
        let strip = getStripThumbnails()
        print("\n[\(label)]")
        print("  Active: \(active.map { "\($0.app)(\($0.wid))" }.joined(separator: ", "))")
        print("  Strip: \(Set(strip.map(\.app)).sorted().joined(separator: ", "))")
    }

    // MARK: - Synthetic mouse event helpers

    /// Post a mouse event at a screen coordinate
    func postMouse(_ type: CGEventType, at point: CGPoint, button: CGMouseButton = .left) {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: button
        ) else { return }
        event.post(tap: .cghidEventTap)
    }

    /// Simulate a smooth drag from point A to point B
    func simulateDrag(from start: CGPoint, to end: CGPoint, steps: Int = 30, duration: TimeInterval = 0.4) {
        // Mouse down at start
        postMouse(.leftMouseDown, at: start)
        Thread.sleep(forTimeInterval: 0.05)

        // Interpolate drag path
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let x = start.x + (end.x - start.x) * t
            let y = start.y + (end.y - start.y) * t
            postMouse(.leftMouseDragged, at: CGPoint(x: x, y: y))
            Thread.sleep(forTimeInterval: duration / TimeInterval(steps))
        }

        // Mouse up at end
        postMouse(.leftMouseUp, at: end)
    }

    // MARK: - Approach 5: Drag strip thumbnail to center

    func testJoinByDragFromStrip() throws {
        let smEnabled = UserDefaults(suiteName: "com.apple.WindowManager")?.bool(forKey: "GloballyEnabled") ?? false
        try XCTSkipUnless(smEnabled, "Stage Manager is OFF")

        let thumbnails = getStripThumbnails()
        let active = getActiveStage()

        guard !thumbnails.isEmpty else {
            print("No strip thumbnails found")
            return
        }
        guard let anchor = active.first else {
            print("No active stage window")
            return
        }

        // Target specific apps: Chrome, iTerm2, Vox
        let activeApps = Set(active.map(\.app))
        let preferred = ["Google Chrome", "iTerm2", "Vox"]
        guard let thumb = thumbnails.first(where: { preferred.contains($0.app) && !activeApps.contains($0.app) })
              ?? thumbnails.first(where: { !activeApps.contains($0.app) }) else {
            print("No suitable strip thumbnail found")
            return
        }

        let thumbCenter = CGPoint(x: thumb.bounds.midX, y: thumb.bounds.midY)
        let stageCenter = CGPoint(x: anchor.bounds.midX, y: anchor.bounds.midY)

        print("Dragging \(thumb.app) thumbnail from strip (\(Int(thumbCenter.x)),\(Int(thumbCenter.y))) to center (\(Int(stageCenter.x)),\(Int(stageCenter.y)))")
        printStageState(label: "BEFORE")

        simulateDrag(from: thumbCenter, to: stageCenter, steps: 40, duration: 0.6)

        Thread.sleep(forTimeInterval: 0.8)
        printStageState(label: "After drag to center")

        let finalActive = getActiveStage()
        let finalApps = Set(finalActive.map(\.app))
        let joined = finalApps.contains(thumb.app) && activeApps.isSubset(of: finalApps)
        print("\nResult: \(thumb.app) joined stage? \(joined)")
        print("Active apps: \(finalApps.sorted())")
    }

    // MARK: - Approach 6: Drag thumbnail to top half (join zone)

    func testJoinByDragToTopHalf() throws {
        let smEnabled = UserDefaults(suiteName: "com.apple.WindowManager")?.bool(forKey: "GloballyEnabled") ?? false
        try XCTSkipUnless(smEnabled, "Stage Manager is OFF")

        let thumbnails = getStripThumbnails()
        let active = getActiveStage()

        guard !thumbnails.isEmpty, let anchor = active.first else { return }

        let activeApps = Set(active.map(\.app))
        let preferred6 = ["Google Chrome", "iTerm2", "Vox"]
        guard let thumb = thumbnails.first(where: { preferred6.contains($0.app) && !activeApps.contains($0.app) })
              ?? thumbnails.first(where: { !activeApps.contains($0.app) }) else { return }

        // SM has specific drop zones. Try dragging to the top half of the active
        // stage area — this might be the "join" zone vs "replace" zone.
        let thumbCenter = CGPoint(x: thumb.bounds.midX, y: thumb.bounds.midY)
        let topHalf = CGPoint(x: anchor.bounds.midX, y: anchor.bounds.origin.y + 100)

        print("Dragging \(thumb.app) to top-half of active area (\(Int(topHalf.x)),\(Int(topHalf.y)))")
        printStageState(label: "BEFORE")

        simulateDrag(from: thumbCenter, to: topHalf, steps: 50, duration: 0.8)

        Thread.sleep(forTimeInterval: 0.8)
        printStageState(label: "After drag to top half")

        let finalApps = Set(getActiveStage().map(\.app))
        let joined = finalApps.contains(thumb.app) && activeApps.isSubset(of: finalApps)
        print("\nResult: joined? \(joined) — active: \(finalApps.sorted())")
    }

    // MARK: - Approach 7: Long press on thumbnail, then drag

    func testJoinByLongPressDrag() throws {
        let smEnabled = UserDefaults(suiteName: "com.apple.WindowManager")?.bool(forKey: "GloballyEnabled") ?? false
        try XCTSkipUnless(smEnabled, "Stage Manager is OFF")

        let thumbnails = getStripThumbnails()
        let active = getActiveStage()

        guard !thumbnails.isEmpty, let anchor = active.first else { return }

        let activeApps = Set(active.map(\.app))
        let preferred7 = ["Google Chrome", "iTerm2", "Vox"]
        guard let thumb = thumbnails.first(where: { preferred7.contains($0.app) && !activeApps.contains($0.app) })
              ?? thumbnails.first(where: { !activeApps.contains($0.app) }) else { return }

        let thumbCenter = CGPoint(x: thumb.bounds.midX, y: thumb.bounds.midY)
        let stageCenter = CGPoint(x: anchor.bounds.midX, y: anchor.bounds.midY)

        print("Long-press + drag \(thumb.app) from strip to center")
        printStageState(label: "BEFORE")

        // Long press: mouse down + wait
        postMouse(.leftMouseDown, at: thumbCenter)
        Thread.sleep(forTimeInterval: 0.8) // Hold for long press recognition

        // Slow drag out of strip area
        let steps = 60
        let duration: TimeInterval = 1.0
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let x = thumbCenter.x + (stageCenter.x - thumbCenter.x) * t
            let y = thumbCenter.y + (stageCenter.y - thumbCenter.y) * t
            postMouse(.leftMouseDragged, at: CGPoint(x: x, y: y))
            Thread.sleep(forTimeInterval: duration / TimeInterval(steps))
        }

        // Hold at destination briefly
        Thread.sleep(forTimeInterval: 0.3)
        postMouse(.leftMouseUp, at: stageCenter)

        Thread.sleep(forTimeInterval: 1.0)
        printStageState(label: "After long-press drag")

        let finalApps = Set(getActiveStage().map(\.app))
        let joined = finalApps.contains(thumb.app) && activeApps.isSubset(of: finalApps)
        print("\nResult: joined? \(joined) — active: \(finalApps.sorted())")
    }

    // MARK: - Approach 8: Click thumbnail while holding Option key

    func testJoinByOptionClick() throws {
        let smEnabled = UserDefaults(suiteName: "com.apple.WindowManager")?.bool(forKey: "GloballyEnabled") ?? false
        try XCTSkipUnless(smEnabled, "Stage Manager is OFF")

        let thumbnails = getStripThumbnails()
        let active = getActiveStage()

        guard !thumbnails.isEmpty else { return }

        let activeApps = Set(active.map(\.app))
        let preferred8 = ["Google Chrome", "iTerm2", "Vox"]
        guard let thumb = thumbnails.first(where: { preferred8.contains($0.app) && !activeApps.contains($0.app) })
              ?? thumbnails.first(where: { !activeApps.contains($0.app) }) else { return }

        let thumbCenter = CGPoint(x: thumb.bounds.midX, y: thumb.bounds.midY)

        print("Option-clicking \(thumb.app) thumbnail at (\(Int(thumbCenter.x)),\(Int(thumbCenter.y)))")
        printStageState(label: "BEFORE")

        // Option + click on strip thumbnail
        guard let downEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: thumbCenter,
            mouseButton: .left
        ) else { return }
        downEvent.flags = .maskAlternate // Option key
        downEvent.post(tap: .cghidEventTap)

        Thread.sleep(forTimeInterval: 0.05)

        guard let upEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: thumbCenter,
            mouseButton: .left
        ) else { return }
        upEvent.flags = .maskAlternate
        upEvent.post(tap: .cghidEventTap)

        Thread.sleep(forTimeInterval: 0.8)
        printStageState(label: "After Option-click")

        let finalApps = Set(getActiveStage().map(\.app))
        let joined = finalApps.contains(thumb.app) && activeApps.isSubset(of: finalApps)
        print("\nResult: joined? \(joined) — active: \(finalApps.sorted())")
    }

    // MARK: - Approach 9: Shift-click (common modifier for "add to selection")

    func testJoinByShiftClick() throws {
        let smEnabled = UserDefaults(suiteName: "com.apple.WindowManager")?.bool(forKey: "GloballyEnabled") ?? false
        try XCTSkipUnless(smEnabled, "Stage Manager is OFF")

        let thumbnails = getStripThumbnails()
        let active = getActiveStage()

        guard !thumbnails.isEmpty else { return }

        let activeApps = Set(active.map(\.app))
        let preferred9 = ["Google Chrome", "iTerm2", "Vox"]
        guard let thumb = thumbnails.first(where: { preferred9.contains($0.app) && !activeApps.contains($0.app) })
              ?? thumbnails.first(where: { !activeApps.contains($0.app) }) else { return }

        let thumbCenter = CGPoint(x: thumb.bounds.midX, y: thumb.bounds.midY)

        print("Shift-clicking \(thumb.app) thumbnail")
        printStageState(label: "BEFORE")

        guard let downEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: thumbCenter,
            mouseButton: .left
        ) else { return }
        downEvent.flags = .maskShift
        downEvent.post(tap: .cghidEventTap)

        Thread.sleep(forTimeInterval: 0.05)

        guard let upEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: thumbCenter,
            mouseButton: .left
        ) else { return }
        upEvent.flags = .maskShift
        upEvent.post(tap: .cghidEventTap)

        Thread.sleep(forTimeInterval: 0.8)
        printStageState(label: "After Shift-click")

        let finalApps = Set(getActiveStage().map(\.app))
        let joined = finalApps.contains(thumb.app) && activeApps.isSubset(of: finalApps)
        print("\nResult: joined? \(joined) — active: \(finalApps.sorted())")
    }
}
