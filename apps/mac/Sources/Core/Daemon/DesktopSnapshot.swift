import Foundation

/// One-call situational awareness for agents. Does not recapture windows or OCR.
enum DesktopSnapshot {
    static func build(includeOffscreen: Bool = false) -> JSON {
        let desktop = DesktopModel.shared
        let windows = desktop.allWindows().filter { includeOffscreen || $0.isOnScreen }
        let front = desktop.frontmostWindow()
        let focusedId = desktop.focusedWindow()?.wid
        let displays = Encoders.displays()
        let currentSpaceId = currentSpaceId(for: front, displays: displays)

        var obj: [String: JSON] = [
            "displays": displays,
            "currentSpaceId": currentSpaceId.map { .int($0) } ?? .null,
            "windows": .array(windows.map { Encoders.snapshotWindow($0, focusedWid: focusedId) }),
            "sessions": .array(TmuxModel.shared.sessions.map { session in
                .object([
                    "name": .string(session.name),
                    "attached": .bool(session.attached),
                    "windowCount": .int(session.windowCount),
                ])
            }),
            "permissions": PermissionChecker.shared.snapshotJSON(),
        ]

        if let front {
            obj["frontmost"] = Encoders.frontmost(front)
        } else {
            obj["frontmost"] = .null
        }

        if let layer = WorkspaceManager.shared.activeLayer {
            obj["activeLayer"] = .object([
                "id": .string(layer.id),
                "index": .int(WorkspaceManager.shared.activeLayerIndex),
            ])
        } else {
            obj["activeLayer"] = .null
        }

        return .object(obj)
    }

    private static func currentSpaceId(for front: WindowEntry?, displays: JSON) -> Int? {
        guard case .array(let items) = displays else { return nil }
        if let spaceId = front?.spaceIds.first {
            return spaceId
        }
        guard case .object(let first) = items.first else { return nil }
        return first["currentSpaceId"]?.intValue
    }
}
