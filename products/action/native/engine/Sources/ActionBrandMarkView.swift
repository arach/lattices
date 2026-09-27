import ActionCore
import SwiftUI

/// The tile the mark sits on — the same continuous-corner rounded rect the app
/// icon uses, so the chip in a header and the icon in the Dock are one mark.
struct ActionBrandTileShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(ActionBrandMark.tilePath(in: rect))
    }
}

/// The A, placed inside a tile the way the app icon places it — hand it the
/// tile's bounds and it works out its own inset.
struct ActionBrandLetterShape: Shape {
    func path(in rect: CGRect) -> Path {
        let mark = ActionBrandMark.markRect(inTile: rect, yAxis: .down)
        return Path(ActionBrandMark.letterPath(in: mark, yAxis: .down))
    }
}

/// The cursor, in the same tile-relative placement.
struct ActionBrandCursorShape: Shape {
    func path(in rect: CGRect) -> Path {
        let mark = ActionBrandMark.markRect(inTile: rect, yAxis: .down)
        return Path(ActionBrandMark.cursorPath(in: mark, yAxis: .down))
    }
}

/// Action's brand chip: the app icon, drawn live.
///
/// Same paper field, ink letter and cursor the `.icns` carries, so the chip in
/// a header and the icon in the Dock are one mark. The tile and the letter read
/// theme tokens rather than baked colours, so they follow a theme switch —
/// which the icon on disk cannot, and that is the one place the two are
/// allowed to drift. The cursor keeps the kit's colour on any paper, as the kit
/// does: the theme's coral means something is live, and a chip in a header is
/// not.
struct ActionBrandTile: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            ActionBrandTileShape()
                .fill(StageHUDTheme.hudPaper)
            ActionBrandLetterShape()
                .fill(StageHUDTheme.hudInk)
            ActionBrandCursorShape()
                .fill(Color(cgColor: ActionBrandMark.cursor))
        }
        .frame(width: size, height: size)
        .overlay(
            ActionBrandTileShape()
                .stroke(StageHUDTheme.hudInk.opacity(0.10), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }
}
