import AppKit
import ObjectiveC.runtime

/// Globally suppresses AppKit's blue keyboard-focus ring.
///
/// Lattices is a chromeless, dark, menu-bar overlay app. The system focus ring —
/// drawn around whichever control is first responder (a `.plain` search field, a
/// nav-rail icon button, a list row, …) — reads as a stray little blue rectangle
/// that doesn't belong in any of our surfaces. `.textFieldStyle(.plain)` and the
/// per-window field-editor overrides only reach text fields; this rewrites
/// `NSView.focusRingType` to return `.none` for *every* view, so nothing anywhere
/// draws a ring. Idempotent — install once at launch.
enum AppFocusRingSuppressor {
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        let selector = #selector(getter: NSView.focusRingType)
        guard let method = class_getInstanceMethod(NSView.self, selector) else { return }
        let block: @convention(block) (NSView) -> NSFocusRingType = { _ in .none }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }
}
