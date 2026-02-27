import AppKit
import CoreGraphics

final class DesktopModel: ObservableObject {
    static let shared = DesktopModel()

    @Published private(set) var windows: [UInt32: WindowEntry] = [:]
    private var timer: Timer?

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
        Array(windows.values).sorted { $0.wid < $1.wid }
    }

    func windowForSession(_ session: String) -> WindowEntry? {
        let tag = Terminal.windowTag(for: session)
        return windows.values.first { $0.title.contains(tag) }
    }

    // MARK: - Polling

    func poll() {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return }

        var fresh: [UInt32: WindowEntry] = [:]

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
            let isOnScreen = info[kCGWindowIsOnscreen as String] as? Bool ?? true

            // Skip non-standard layers (menus, overlays)
            guard layer == 0 else { continue }

            let frame = WindowFrame(
                x: Double(rect.origin.x),
                y: Double(rect.origin.y),
                w: Double(rect.width),
                h: Double(rect.height)
            )

            let spaceIds = WindowTiler.getSpacesForWindow(wid)

            // Extract lattice session tag from title: [lattice:session-name]
            var latticeSession: String?
            if let range = title.range(of: #"\[lattice:([^\]]+)\]"#, options: .regularExpression) {
                let match = String(title[range])
                latticeSession = String(match.dropFirst(8).dropLast(1)) // drop "[lattice:" and "]"
            }

            fresh[wid] = WindowEntry(
                wid: wid,
                app: ownerName,
                pid: pid,
                title: title,
                frame: frame,
                spaceIds: spaceIds,
                isOnScreen: isOnScreen,
                latticeSession: latticeSession
            )
        }

        // Diff
        let oldKeys = Set(windows.keys)
        let newKeys = Set(fresh.keys)
        let added = Array(newKeys.subtracting(oldKeys))
        let removed = Array(oldKeys.subtracting(newKeys))

        let changed = added.count > 0 || removed.count > 0 || windowsContentChanged(old: windows, new: fresh)

        DispatchQueue.main.async {
            self.windows = fresh
        }

        if changed {
            EventBus.shared.post(.windowsChanged(
                windows: Array(fresh.values),
                added: added,
                removed: removed
            ))
        }
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
