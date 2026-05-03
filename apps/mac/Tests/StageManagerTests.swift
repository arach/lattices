import XCTest
import CoreGraphics
import AppKit

final class StageManagerTests: XCTestCase {

    // MARK: - Detection

    func testStageManagerEnabled() {
        let defaults = UserDefaults(suiteName: "com.apple.WindowManager")
        let enabled = defaults?.bool(forKey: "GloballyEnabled") ?? false
        print("Stage Manager enabled: \(enabled)")

        // Also read all known keys
        let keys = [
            "GloballyEnabled",
            "GloballyEnabledEver",
            "AutoHide",
            "AppWindowGroupingBehavior",
            "HideDesktop",
            "StageManagerHideWidgets",
            "EnableStandardClickToShowDesktop",
            "EnableTiledWindowMargins",
            "EnableTilingByEdgeDrag",
            "EnableTopTilingByEdgeDrag",
            "StandardHideDesktopIcons",
            "StandardHideWidgets",
        ]

        print("\n=== com.apple.WindowManager preferences ===")
        for key in keys {
            let val = defaults?.object(forKey: key)
            print("  \(key): \(val ?? "nil" as Any)")
        }

        // Not asserting true/false — just verifying we can read the domain
        XCTAssertNotNil(defaults, "Should be able to open com.apple.WindowManager domain")
    }

    // MARK: - Window Classification

    func testClassifyWindows() {
        let smEnabled = UserDefaults(suiteName: "com.apple.WindowManager")?.bool(forKey: "GloballyEnabled") ?? false

        guard smEnabled else {
            print("Stage Manager is OFF — skipping window classification")
            return
        }

        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            XCTFail("Could not get window list")
            return
        }

        var activeStage: [(wid: UInt32, app: String, title: String, bounds: CGRect)] = []
        var stripThumbnails: [(wid: UInt32, app: String, title: String, bounds: CGRect)] = []
        var hiddenStage: [(wid: UInt32, app: String, title: String, bounds: CGRect)] = []
        var gestureOverlays: [(wid: UInt32, bounds: CGRect)] = []
        var appIcons: [(wid: UInt32, bounds: CGRect)] = []

        let mainScreen = NSScreen.main!
        let stripMaxX: CGFloat = 220 // strip occupies roughly left 220px
        let thumbnailMaxSize: CGFloat = 250

        for info in windowList {
            guard let wid = info[kCGWindowNumber as String] as? UInt32,
                  let owner = info[kCGWindowOwnerName as String] as? String,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary
            else { continue }

            var rect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict, &rect) else { continue }

            let title = info[kCGWindowName as String] as? String ?? ""
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            let isOnScreen = info[kCGWindowIsOnscreen as String] as? Bool ?? false

            guard layer == 0 else { continue }
            guard rect.width >= 10, rect.height >= 10 else { continue }

            // WindowManager process windows (GBOs and app icons)
            if owner == "WindowManager" {
                if title == "Gesture Blocking Overlay" || title.isEmpty {
                    if rect.width <= 80 && rect.height <= 80 {
                        appIcons.append((wid: wid, bounds: rect))
                    } else {
                        gestureOverlays.append((wid: wid, bounds: rect))
                    }
                }
                continue
            }

            // Skip non-app processes
            let skipOwners: Set<String> = [
                "Window Server", "Dock", "Control Center", "SystemUIServer",
                "Notification Center", "Spotlight",
            ]
            if skipOwners.contains(owner) { continue }

            if !isOnScreen {
                // Hidden in another stage
                hiddenStage.append((wid: wid, app: owner, title: title, bounds: rect))
            } else if rect.width < thumbnailMaxSize && rect.height < thumbnailMaxSize
                        && rect.origin.x < stripMaxX {
                // Strip thumbnail
                stripThumbnails.append((wid: wid, app: owner, title: title, bounds: rect))
            } else if rect.width >= 50 && rect.height >= 50 {
                // Active stage window
                activeStage.append((wid: wid, app: owner, title: title, bounds: rect))
            }
        }

        print("\n=== Stage Manager Window Classification ===")
        print("Screen: \(Int(mainScreen.frame.width))x\(Int(mainScreen.frame.height))")

        print("\n--- Active Stage (\(activeStage.count) windows) ---")
        for w in activeStage {
            print("  [\(w.wid)] \(w.app) — \"\(w.title)\"")
            print("         bounds: \(Int(w.bounds.origin.x)),\(Int(w.bounds.origin.y)) \(Int(w.bounds.width))x\(Int(w.bounds.height))")
        }

        print("\n--- Strip Thumbnails (\(stripThumbnails.count) windows) ---")
        for w in stripThumbnails {
            print("  [\(w.wid)] \(w.app) — \"\(w.title)\"")
            print("         bounds: \(Int(w.bounds.origin.x)),\(Int(w.bounds.origin.y)) \(Int(w.bounds.width))x\(Int(w.bounds.height))")
        }

        print("\n--- Hidden in Other Stages (\(hiddenStage.count) windows) ---")
        for w in hiddenStage {
            print("  [\(w.wid)] \(w.app) — \"\(w.title)\"")
            print("         bounds: \(Int(w.bounds.origin.x)),\(Int(w.bounds.origin.y)) \(Int(w.bounds.width))x\(Int(w.bounds.height))")
        }

        print("\n--- Gesture Blocking Overlays (\(gestureOverlays.count)) ---")
        for g in gestureOverlays {
            print("  [\(g.wid)] bounds: \(Int(g.bounds.origin.x)),\(Int(g.bounds.origin.y)) \(Int(g.bounds.width))x\(Int(g.bounds.height))")
        }

        print("\n--- App Icons in Strip (\(appIcons.count)) ---")
        for a in appIcons {
            print("  [\(a.wid)] bounds: \(Int(a.bounds.origin.x)),\(Int(a.bounds.origin.y)) \(Int(a.bounds.width))x\(Int(a.bounds.height))")
        }

        // Try to correlate GBOs to strip thumbnails by proximity
        print("\n--- GBO ↔ Thumbnail Correlation ---")
        for gbo in gestureOverlays {
            let gboCenter = CGPoint(x: gbo.bounds.midX, y: gbo.bounds.midY)
            var closest: (wid: UInt32, app: String, dist: CGFloat) = (0, "", .greatestFiniteMagnitude)
            for thumb in stripThumbnails {
                let thumbCenter = CGPoint(x: thumb.bounds.midX, y: thumb.bounds.midY)
                let dist = hypot(gboCenter.x - thumbCenter.x, gboCenter.y - thumbCenter.y)
                if dist < closest.dist {
                    closest = (thumb.wid, thumb.app, dist)
                }
            }
            if closest.dist < 300 {
                print("  GBO [\(gbo.wid)] → Thumbnail [\(closest.wid)] \(closest.app) (dist: \(Int(closest.dist))px)")
            } else {
                print("  GBO [\(gbo.wid)] → no match (closest: \(Int(closest.dist))px)")
            }
        }
    }

    // MARK: - Stage Grouping Heuristic

    func testInferStageGroups() {
        let smEnabled = UserDefaults(suiteName: "com.apple.WindowManager")?.bool(forKey: "GloballyEnabled") ?? false

        guard smEnabled else {
            print("Stage Manager is OFF — skipping stage grouping")
            return
        }

        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            XCTFail("Could not get window list")
            return
        }

        // Stage Manager groups windows together. When "All at Once" is selected,
        // all windows from one app move together. We can infer groups by looking
        // at which offscreen windows share similar thumbnail strip positions.

        struct WinInfo {
            let wid: UInt32
            let app: String
            let title: String
            let bounds: CGRect
            let isOnScreen: Bool
            let pid: Int32
        }

        var appWindows: [String: [WinInfo]] = [:]
        let skipOwners: Set<String> = [
            "Window Server", "Dock", "Control Center", "SystemUIServer",
            "Notification Center", "Spotlight", "WindowManager",
        ]

        for info in windowList {
            guard let wid = info[kCGWindowNumber as String] as? UInt32,
                  let owner = info[kCGWindowOwnerName as String] as? String,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary
            else { continue }

            var rect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict, &rect) else { continue }
            let title = info[kCGWindowName as String] as? String ?? ""
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            let isOnScreen = info[kCGWindowIsOnscreen as String] as? Bool ?? false

            guard layer == 0, rect.width >= 50, rect.height >= 50 else { continue }
            guard !skipOwners.contains(owner) else { continue }

            let w = WinInfo(wid: wid, app: owner, title: title, bounds: rect,
                           isOnScreen: isOnScreen, pid: pid)
            appWindows[owner, default: []].append(w)
        }

        // Classify into stages
        var currentStageApps: Set<String> = []
        var otherStageApps: Set<String> = []

        for (app, wins) in appWindows {
            let hasOnScreen = wins.contains { $0.isOnScreen && $0.bounds.width > 250 }
            if hasOnScreen {
                currentStageApps.insert(app)
            } else {
                otherStageApps.insert(app)
            }
        }

        print("\n=== Inferred Stage Groups ===")
        print("\n🟢 Current Stage:")
        for app in currentStageApps.sorted() {
            let wins = appWindows[app]!.filter { $0.isOnScreen }
            print("  \(app) (\(wins.count) window\(wins.count == 1 ? "" : "s"))")
            for w in wins {
                print("    [\(w.wid)] \"\(w.title)\" — \(Int(w.bounds.width))x\(Int(w.bounds.height))")
            }
        }

        print("\n🔵 Other Stages:")
        for app in otherStageApps.sorted() {
            let wins = appWindows[app]!
            let onScreen = wins.filter { $0.isOnScreen }
            let offScreen = wins.filter { !$0.isOnScreen }
            print("  \(app) (\(offScreen.count) hidden, \(onScreen.count) thumbnail)")
            for w in offScreen.prefix(3) {
                print("    [\(w.wid)] \"\(w.title)\" — \(Int(w.bounds.width))x\(Int(w.bounds.height))")
            }
            if offScreen.count > 3 { print("    ... and \(offScreen.count - 3) more") }
        }
    }

    // MARK: - Preferences Change Detection

    func testStageManagerPrefsObservation() {
        // Test that we can observe preference changes via polling
        let defaults = UserDefaults(suiteName: "com.apple.WindowManager")
        let initial = defaults?.bool(forKey: "GloballyEnabled") ?? false
        print("Initial Stage Manager state: \(initial)")

        // Quick re-read to verify consistency
        let reread = defaults?.bool(forKey: "GloballyEnabled") ?? false
        XCTAssertEqual(initial, reread, "Preference should be stable across reads")

        // Read AppWindowGroupingBehavior
        let grouping = defaults?.integer(forKey: "AppWindowGroupingBehavior") ?? -1
        print("AppWindowGroupingBehavior: \(grouping) (\(grouping == 0 ? "All at Once" : grouping == 1 ? "One at a Time" : "unknown"))")

        let autoHide = defaults?.bool(forKey: "AutoHide") ?? false
        print("AutoHide (strip): \(autoHide)")
    }
}
