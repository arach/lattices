import SwiftUI
import HudsonUI

// Lattices message markdown now renders through HudsonUI's shared
// `HudMarkdownView` — the block parser + renderer that originated here (ported
// from OpenScout's MessageMarkupParser/CommsMessageMarkup) was donated upstream
// into HudsonUI so Lattices and OpenScout share one themed renderer instead of
// each maintaining a drifting copy. This thin adapter keeps existing call sites
// stable and maps Lattices' content sizing onto the shared component.

struct PiChatMarkdownView: View {
    let text: String
    var style: PiChatStyle = .workspace

    var body: some View {
        HudMarkdownView(text: text, contentSize: style.bodySize)
    }
}
