import CoreGraphics
import Foundation

public enum TerminalWindowQuery {
    public static func listTerminalWindows(
        apps: [TerminalApp] = TerminalApp.allCases,
        additionalAppNames: [String] = []
    ) -> [TerminalWindow] {
        let appNames = Set(apps.map(\.rawValue) + additionalAppNames)
        guard let list = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]]
        else { return [] }

        var windows: [TerminalWindow] = []
        var zIndex = 0

        for info in list {
            guard let wid = info[kCGWindowNumber as String] as? UInt32,
                  let ownerName = info[kCGWindowOwnerName as String] as? String,
                  appNames.contains(ownerName),
                  let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary
            else {
                zIndex += 1
                continue
            }

            var rect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict, &rect),
                  rect.width >= 50,
                  rect.height >= 50
            else {
                zIndex += 1
                continue
            }

            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 else {
                zIndex += 1
                continue
            }

            let title = info[kCGWindowName as String] as? String ?? ""
            let isOnScreen = info[kCGWindowIsOnscreen as String] as? Bool ?? false
            let bundleIdentifier = TerminalApp.named(ownerName)?.bundleIdentifier
            windows.append(TerminalWindow(
                wid: wid,
                app: ownerName,
                bundleIdentifier: bundleIdentifier,
                pid: pid,
                title: title,
                frame: TerminalFrame(
                    x: Double(rect.origin.x),
                    y: Double(rect.origin.y),
                    w: Double(rect.width),
                    h: Double(rect.height)
                ),
                isOnScreen: isOnScreen,
                latticesSession: LatticesTerminalTag.extractSessionName(from: title),
                axVerified: true,
                zIndex: zIndex
            ))
            zIndex += 1
        }

        return windows.sorted {
            if $0.zIndex != $1.zIndex { return $0.zIndex < $1.zIndex }
            return $0.wid < $1.wid
        }
    }
}
