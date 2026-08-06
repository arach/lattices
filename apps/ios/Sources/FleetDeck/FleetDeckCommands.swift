import DeckKit
import Foundation

extension FleetCommandSet {

    /// The four core remote-control contexts shown when a Mac has not advertised
    /// a deck yet. Live tiles still come from the selected Mac.
    ///
    /// These are the *shape* of the bay, used when a Mac advertises no cockpit
    /// pages of its own (and by the design fixture). Tiles here carry no
    /// `actionID`: a live deck builds its sets from `snapshot.cockpit.pages`,
    /// which come with the bridge's real action IDs attached.
    static let canonical: [FleetCommandSet] = [
        FleetCommandSet(
            id: "command",
            key: "COMMAND",
            tiles: tiles([
                ("Desktop Preview", "see Mac", "display"),
                ("Paste Device", "clipboard", "rectangle.portrait.and.arrow.forward"),
                ("Previous App", "switch", "chevron.left.square"),
                ("Next App", "switch", "chevron.right.square"),
                ("Previous Window", "switch", "rectangle.on.rectangle"),
                ("Next Window", "switch", "rectangle.on.rectangle"),
                ("Find Mouse", "locate", "scope"),
                ("Summon Mouse", "center", "dot.scope")
            ], prefix: "command")
        ),
        FleetCommandSet(
            id: "dev",
            key: "DEV",
            tiles: tiles([
                ("Copy", "command C", "doc.on.doc"),
                ("Paste", "command V", "doc.on.clipboard"),
                ("Undo", "command Z", "arrow.uturn.backward"),
                ("Escape", "dismiss", "escape"),
                ("Enter", "return", "return"),
                ("Space", "input", "space"),
                ("Up", "navigate", "arrow.up"),
                ("Down", "navigate", "arrow.down")
            ], prefix: "dev")
        ),
        FleetCommandSet(
            id: "media",
            key: "MEDIA",
            tiles: tiles([
                ("Play / Pause", "space", "playpause"),
                ("Back", "seek", "gobackward"),
                ("Forward", "seek", "goforward"),
                ("Center", "place", "plus.rectangle.on.rectangle"),
                ("Maximize", "fill screen", "macwindow"),
                ("Grow", "resize", "plus.rectangle.fill.on.rectangle.fill"),
                ("Shrink", "resize", "minus.rectangle"),
                ("Escape", "dismiss", "escape")
            ], prefix: "media")
        ),
        FleetCommandSet(
            id: "windows",
            key: "WINDOWS",
            tiles: tiles([
                ("Top Left", "quarter", "rectangle.inset.topleft.filled"),
                ("Top Right", "quarter", "rectangle.inset.topright.filled"),
                ("Bottom Left", "quarter", "rectangle.inset.bottomleft.filled"),
                ("Bottom Right", "quarter", "rectangle.inset.bottomright.filled"),
                ("Left", "half", "rectangle.leadinghalf.filled"),
                ("Right", "half", "rectangle.trailinghalf.filled"),
                ("Maximize", "fill screen", "macwindow"),
                ("Optimize", "retile", "rectangle.3.group.fill")
            ], prefix: "windows")
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
            columns: max(1, page.columns),
            rows: page.rows,
            tiles: page.tiles.enumerated().map { index, tile in
                let hint = tile.subtitle?.lowercased() ?? tile.shortcutID.lowercased()
                return FleetCommandTile(
                    id: tile.id,
                    title: tile.title,
                    meta: "\(String(format: "%02d", index + 1)) · \(hint)",
                    symbol: tile.iconSystemName,
                    actionID: tile.actionID,
                    payload: tile.payload,
                    isEnabled: tile.isEnabled,
                    col: tile.col,
                    row: tile.row,
                    colSpan: max(1, tile.colSpan ?? 1),
                    rowSpan: max(1, tile.rowSpan ?? 1)
                )
            }
        )
    }
}
