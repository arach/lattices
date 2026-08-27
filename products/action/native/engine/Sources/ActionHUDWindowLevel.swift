import AppKit

func actionHUDPanelLevel() -> NSWindow.Level {
    // Interactive, key-capable panels are clamped to the floating layer by
    // WindowServer. Use that supported level explicitly so paired overlays can
    // share the same layer and control their order deterministically.
    .floating
}
