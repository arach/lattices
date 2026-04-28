import AppKit
import ApplicationServices
import CoreGraphics

final class DesktopModel: ObservableObject {
    static let shared = DesktopModel()

    /// System helper processes that should never appear in search results or window lists.
    /// These are XPC services, agents, and background helpers — not user-facing apps.
    private static let systemHelperProcesses: Set<String> = [
        // Apple system helpers
        "CredentialsProviderExtensionHost",
        "AuthenticationServicesAgent",
        "SafariPasswordExtension",
        "com.apple.WebKit.WebAuthn",
        "SharedWebCredentialRunner",
        "ViewBridgeAuxiliary",
        "universalaccessd",
        "CoreServicesUIAgent",
        "UserNotificationCenter",
        "AutoFillPanelService",
        "AutoFill",
        "CoreLocationAgent",
        "SecurityAgent",
        "coreautha",
        "coreauth",
        "talagent",
        "CommCenter",
        "AXVisualSupportAgent",
        "SystemUIServer",
        "Dock",
        "Window Server",
        "WindowManager",
        "NotificationCenter",
        "ControlCenter",
        "Spotlight",
        "Keychain Access",
        "loginwindow",
        "ScreenSaverEngine",
        "SoftwareUpdateNotificationManager",
        "WiFiAgent",
        "pboard",
        "storeuid",
        // Third-party helpers
        "CursorUIViewService",
        "Electron Helper",
        "Google Chrome Helper",
    ]

    /// Suffixes that indicate a helper/service process, not a user-facing app
    private static let helperSuffixes = ["Service", "Agent", "Helper", "Extension", "Daemon", "XPCService"]

    /// Real apps that happen to match helper suffixes — don't filter these
    private static let knownRealApps: Set<String> = [
        "Finder",
        "Activity Monitor",
    ]

    @Published private(set) var windows: [UInt32: WindowEntry] = [:]
    @Published private(set) var interactionDates: [UInt32: Date] = [:]
    /// In-memory layer tags: wid → layer id (e.g. "lattices", "vox", "hudson")
    private(set) var windowLayerTags: [UInt32: String] = [:]
    private var timer: Timer?
    private var lastFrontmostWid: UInt32?

    func start(interval: TimeInterval = 1.5) {
        guard timer == nil else { return }
        DiagnosticLog.shared.info("DesktopModel: starting (interval=\(interval)s)")
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func allWindows() -> [WindowEntry] {
        Array(windows.values).sorted { $0.zIndex < $1.zIndex }
    }

    func frontmostWindow() -> WindowEntry? {
        windows.values.min { $0.zIndex < $1.zIndex }
    }

    func lastInteractionDate(for wid: UInt32) -> Date? {
        interactionDates[wid]
    }

    func markInteraction(wid: UInt32, at date: Date = Date()) {
        DispatchQueue.main.async {
            self.interactionDates[wid] = date
        }
    }

    func markInteraction(wids: [UInt32], at date: Date = Date()) {
        guard !wids.isEmpty else { return }
        let unique = Set(wids)
        DispatchQueue.main.async {
            for wid in unique {
                self.interactionDates[wid] = date
            }
        }
    }

    func windowForSession(_ session: String) -> WindowEntry? {
        SessionWindowLocator.cachedWindow(forSession: session, in: windows)
    }

    /// Assign a layer tag to a window (in-memory only)
    func assignLayer(wid: UInt32, layerId: String) {
        windowLayerTags[wid] = layerId
    }

    /// Remove layer tag from a window
    func removeLayerTag(wid: UInt32) {
        windowLayerTags.removeValue(forKey: wid)
    }

    /// Clear all layer tags
    func clearLayerTags() {
        windowLayerTags.removeAll()
    }

    /// Find a window by app name and optional title substring (case-insensitive)
    func windowForApp(app: String, title: String?) -> WindowEntry? {
        let matches = windows.values.filter {
            $0.app.localizedCaseInsensitiveContains(app)
        }
        if let title {
            return matches.first { $0.title.localizedCaseInsensitiveContains(title) }
        }
        return matches.first
    }

    // MARK: - Polling

    private var lastPollTime: Date = .distantPast
    private static let minPollInterval: TimeInterval = 1.0

    /// Poll only if stale. Call `forcePoll()` to bypass the freshness check.
    func poll() {
        let now = Date()
        guard now.timeIntervalSince(lastPollTime) >= Self.minPollInterval else { return }
        lastPollTime = now
        performPoll()
    }

    /// Force a poll regardless of freshness — use sparingly.
    func forcePoll() {
        lastPollTime = Date()
        performPoll()
    }

    private func performPoll() {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return }

        var fresh: [UInt32: WindowEntry] = [:]
        var zCounter = 0

        for info in list {
            guard let wid = info[kCGWindowNumber as String] as? UInt32,
                  let ownerName = info[kCGWindowOwnerName as String] as? String,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary
            else { continue }

            // Skip tiny windows (menu extras, status items)
            var rect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict, &rect),
                  rect.width >= 50, rect.height >= 50 else { continue }

            let title = info[kCGWindowName as String] as? String ?? ""
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            let isOnScreen = info[kCGWindowIsOnscreen as String] as? Bool ?? false

            // Skip non-standard layers (menus, overlays)
            guard layer == 0 else { continue }

            // Skip system helper processes (autofill, credential providers, etc.)
            if Self.systemHelperProcesses.contains(ownerName) { continue }

            // Skip processes whose name ends with common helper suffixes
            // (e.g. "CursorUIViewService", "AutoFillPanelService", "SecurityAgent")
            // but not known real apps that happen to have these words
            let isHelperByName = Self.helperSuffixes.contains(where: { ownerName.hasSuffix($0) })
                && !Self.knownRealApps.contains(ownerName)
            if isHelperByName { continue }

            // Skip windows with no title from processes containing "com.apple."
            if ownerName.hasPrefix("com.apple.") && title.isEmpty { continue }

            let frame = WindowFrame(
                x: Double(rect.origin.x),
                y: Double(rect.origin.y),
                w: Double(rect.width),
                h: Double(rect.height)
            )

            let spaceIds = WindowTiler.getSpacesForWindow(wid)

            let latticesSession = SessionWindowLocator.extractSessionName(from: title)

            var entry = WindowEntry(
                wid: wid,
                app: ownerName,
                pid: pid,
                title: title,
                frame: frame,
                spaceIds: spaceIds,
                isOnScreen: isOnScreen,
                latticesSession: latticesSession
            )
            entry.zIndex = zCounter
            zCounter += 1
            fresh[wid] = entry
        }

        // AX reconciliation: check which CG windows actually exist in Accessibility
        reconcileWithAX(&fresh)

        // Diff
        let oldKeys = Set(windows.keys)
        let newKeys = Set(fresh.keys)
        let added = Array(newKeys.subtracting(oldKeys))
        let removed = Array(oldKeys.subtracting(newKeys))

        let changed = added.count > 0 || removed.count > 0 || windowsContentChanged(old: windows, new: fresh)
        let frontmostWid = fresh.values.min(by: { $0.zIndex < $1.zIndex })?.wid
        let markFrontmost = frontmostWid != nil && frontmostWid != lastFrontmostWid
        let interactionTime = Date()

        DispatchQueue.main.async {
            var interactions = self.interactionDates.filter { fresh[$0.key] != nil }
            if markFrontmost, let frontmostWid {
                interactions[frontmostWid] = interactionTime
            }
            // Only publish if something actually changed — avoids unnecessary SwiftUI re-renders
            if changed || markFrontmost {
                self.windows = fresh
                self.interactionDates = interactions
            }
            self.lastFrontmostWid = frontmostWid
        }

        if changed {
            EventBus.shared.post(.windowsChanged(
                windows: Array(fresh.values),
                added: added,
                removed: removed
            ))
        }
    }

    private func reconcileWithAX(_ fresh: inout [UInt32: WindowEntry]) {
        // Get currently active Space IDs — AX only returns windows on these
        let currentSpaceIds = Set(WindowTiler.getDisplaySpaces().map(\.currentSpaceId))
        guard !currentSpaceIds.isEmpty else { return }

        // Group CG windows by PID — only titled windows on current Spaces
        var byPid: [Int32: [UInt32]] = [:]
        for (wid, entry) in fresh where !entry.title.isEmpty {
            let onCurrentSpace = entry.spaceIds.contains { currentSpaceIds.contains($0) }
            if onCurrentSpace {
                byPid[entry.pid, default: []].append(wid)
            }
        }

        for (pid, wids) in byPid {
            let axApp = AXUIElementCreateApplication(pid)

            // Set a timeout so unresponsive apps (video calls, etc.) don't block the poll
            AXUIElementSetMessagingTimeout(axApp, 0.3)

            var axWindowsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &axWindowsRef) == .success,
                  let axWindows = axWindowsRef as? [AXUIElement] else { continue }

            // Collect AX window titles
            var axTitles: [String] = []
            for axWin in axWindows {
                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWin, kAXTitleAttribute as CFString, &titleRef)
                if let title = titleRef as? String, !title.isEmpty {
                    axTitles.append(title)
                }
            }

            // Mark CG windows that have no matching AX title.
            // AX titles often have suffixes like " - Google Chrome - Profile"
            // so check if any AX title starts with the CG title (stripped of emoji).
            for wid in wids {
                guard let entry = fresh[wid], !entry.title.isEmpty else { continue }
                let cgClean = stripForMatch(entry.title)
                let matched = axTitles.contains { axTitle in
                    let axClean = stripForMatch(axTitle)
                    return axClean.hasPrefix(cgClean) || axClean.contains(cgClean) || cgClean.hasPrefix(axClean)
                }
                if !matched {
                    fresh[wid]?.axVerified = false
                }
            }
        }
    }

    private func stripForMatch(_ text: String) -> String {
        // Remove emoji and non-ASCII symbols, lowercase, collapse whitespace
        let scalar = text.unicodeScalars.filter { scalar in
            scalar.isASCII || CharacterSet.letters.contains(scalar)
        }
        return String(scalar).lowercased()
            .split(separator: " ").joined(separator: " ")
    }

    private func windowsContentChanged(old: [UInt32: WindowEntry], new: [UInt32: WindowEntry]) -> Bool {
        // Quick check: if titles or frames changed for any existing window
        for (wid, newEntry) in new {
            guard let oldEntry = old[wid] else { continue }
            if oldEntry.title != newEntry.title || oldEntry.frame != newEntry.frame {
                return true
            }
        }
        return false
    }
}
