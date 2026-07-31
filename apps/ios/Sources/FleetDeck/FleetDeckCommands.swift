import DeckKit
import Foundation

extension FleetCommandSet {

    /// The design's four command sets, in its order — AGENT first, because this
    /// deck steers agents, not cursors.
    ///
    /// These are the *shape* of the bay, used when a Mac advertises no cockpit
    /// pages of its own (and by the design fixture). Tiles here carry no
    /// `actionID`: a live deck builds its sets from `snapshot.cockpit.pages`,
    /// which come with the bridge's real action IDs attached.
    static let canonical: [FleetCommandSet] = [
        FleetCommandSet(
            id: "agent",
            key: "AGENT",
            tiles: tiles([
                ("Run Agent", "spawn", "sparkles"),
                ("Steer", "redirect", "slider.horizontal.3"),
                ("Approve", "unblock", "checkmark.circle"),
                ("Reject", "redo", "xmark.circle"),
                ("Handoff", "pass work", "arrow.right.to.line"),
                ("Delegate", "fan out", "point.3.connected.trianglepath.dotted"),
                ("Summarize", "digest", "text.alignleft"),
                ("Stop", "halt", "stop.circle")
            ], prefix: "agent")
        ),
        FleetCommandSet(
            id: "review",
            key: "REVIEW",
            tiles: tiles([
                ("Open Diff", "inspect", "plusminus"),
                ("Run Tests", "suite", "testtube.2"),
                ("Browser Check", "see result", "globe"),
                ("Screenshot", "capture", "camera"),
                ("Logs", "stream", "list.bullet"),
                ("Commit", "git", "smallcircle.filled.circle"),
                ("Push", "ship", "arrow.up.to.line"),
                ("Revert", "undo", "arrow.uturn.backward")
            ], prefix: "review")
        ),
        FleetCommandSet(
            id: "window",
            key: "WINDOW",
            tiles: tiles([
                ("Focus App", "front", "scope"),
                ("Tile Left", "snap", "rectangle.lefthalf.inset.filled"),
                ("Tile Right", "snap", "rectangle.righthalf.inset.filled"),
                ("Fullscreen", "zoom", "arrow.up.left.and.arrow.down.right"),
                ("Center", "place", "rectangle.center.inset.filled"),
                ("Next Window", "cycle", "arrow.right.square"),
                ("Paste", "clip", "doc.on.clipboard"),
                ("Terminal", "shell", "terminal")
            ], prefix: "window")
        ),
        FleetCommandSet(
            id: "system",
            key: "SYSTEM",
            tiles: tiles([
                ("Lock", "secure", "lock"),
                ("Sleep", "idle", "moon"),
                ("Restart", "reboot", "arrow.clockwise"),
                ("Snapshot", "capture", "camera"),
                ("Sync", "push", "arrow.triangle.2.circlepath"),
                ("Mute", "silence", "speaker.slash"),
                ("Journal", "history", "list.bullet"),
                ("Clear", "reset", "xmark.circle")
            ], prefix: "system")
        )
    ]

    private static func tiles(_ raw: [(String, String, String)], prefix: String) -> [FleetCommandTile] {
        raw.enumerated().map { index, entry in
            FleetCommandTile(
                id: "\(prefix)-\(index)",
                title: entry.0,
                meta: "\(String(format: "%02d", index + 1)) · \(entry.1)",
                symbol: entry.2,
                actionID: nil
            )
        }
    }

    /// Build a set from a Mac's advertised cockpit page. The design's tile
    /// caption is `NN · hint`, so the tile's own subtitle is used when it has
    /// one and the index alone otherwise.
    init(page: DeckCockpitPage) {
        self.init(
            id: page.id,
            key: page.title.uppercased(),
            tiles: page.tiles.enumerated().map { index, tile in
                let hint = tile.subtitle?.lowercased() ?? tile.shortcutID.lowercased()
                return FleetCommandTile(
                    id: tile.id,
                    title: tile.title,
                    meta: "\(String(format: "%02d", index + 1)) · \(hint)",
                    symbol: tile.iconSystemName,
                    actionID: tile.actionID,
                    payload: tile.payload
                )
            }
        )
    }
}
