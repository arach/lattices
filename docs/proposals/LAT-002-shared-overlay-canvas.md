# LAT-002: Shared Per-Screen Overlay Canvas

## Status

Partially implemented.

The shared canvas primitive exists in `ScreenOverlayCanvasController`, and drag-snap zones now publish `snapZones` layers into it. Mouse gesture visuals, passive hotkey hints, and broader overlay consolidation are still pending.

This document proposes a shared, click-through, per-screen overlay canvas for Lattices. The canvas would provide one persistent visual layer per display that features can draw into without each feature creating its own overlay window stack.

## Summary

Lattices already has several overlay-like systems:

- `HUDController` prebuilds HUD panels, keeps them ordered, and toggles visibility with alpha.
- `WindowDragSnapController` creates full-screen snap-zone panels per screen as needed.
- `MouseGestureController` creates transient gesture overlay panels for gesture trails and results.
- `MouseFinder`, `WindowTiler`, and Screen Map have their own small overlay and highlight mechanisms.

These are useful, but they are still separate surfaces. Each one owns its own window lifecycle, z-order behavior, coordinate mapping, visibility rules, and cleanup. That makes every new ambient visual feature slightly more expensive than it should be.

The proposed primitive is a `ScreenOverlayCanvas`: one transparent, click-through, always-on-top window per screen, owned by a central controller. Features publish lightweight visual layers into that canvas. The canvas stays passive by default and never becomes the place where input semantics or actions are decided.

## Why Now

Recent exploration of Clicky's macOS overlay approach highlighted a simpler mental model: create one full-screen transparent window per display, make it click-through, and draw small dynamic UI elements inside it. The visible object can be tiny and contextual, but the rendering surface is stable and screen-sized.

That model maps well to several Lattices ideas:

- snap drag target areas
- passive hotkey information
- layer and workspace hints
- mouse gesture trails
- focus and target highlights
- command-mode affordances
- window-map annotations

Lattices already has the hard parts in pieces. The value is in unifying the canvas primitive so features stop reinventing overlay windows.

## Current State

### HUD

`apps/mac/Sources/Core/Overlays/HUD/HUDController.swift` already uses a warm, persistent model:

1. Panels are prebuilt.
2. Panels stay ordered in the window server.
3. Hidden state is mostly `alphaValue = 0`.
4. Showing the HUD is an immediate alpha flip plus focus handling.
5. Data refresh happens after first paint.

This makes the HUD feel fast. But the HUD is a set of segmented panels: top, bottom, left, right, preview, and minimap panels. It is interactive and cockpit-like, not a general screen canvas.

### Drag Snap

`apps/mac/Sources/Core/Desktop/WindowDragSnapController.swift` creates `WindowSnapOverlayPanel` instances keyed by screen. Each panel covers a whole screen, ignores mouse events, joins all Spaces, and draws snap zones into an `NSView`.

This is very close to the proposed canvas, but it is owned by drag snap and only exists for that feature's model.

### Mouse Gestures

`apps/mac/Sources/Core/Input/MouseGestureController.swift` creates a `MouseGestureOverlay` for a gesture session. It draws path feedback, recognition feedback, and completion labels. It is intentionally close to the input/action fast path, but its rendering should remain decorative.

### Overlay Shells

`apps/mac/Sources/Core/Overlays/OverlayPanelShell.swift` helps normal panel-based surfaces, but it is optimized for discrete overlay panels, not full-screen passive visual layers.

## Proposal

Create a shared `ScreenOverlayCanvasController` responsible for one click-through overlay window per `NSScreen`.

The controller should provide:

- stable full-screen transparent windows, one per display
- local coordinate mapping for each screen
- feature-scoped visual layer registration
- cheap show/hide/update calls
- deterministic z-order within the canvas
- automatic screen-change reconciliation
- explicit cleanup when features end

The overlay windows should be:

- borderless
- transparent
- non-activating
- click-through
- not key or main windows
- able to join all Spaces
- available in fullscreen auxiliary contexts where practical
- high enough level for passive visual feedback, but configurable if a surface needs a lower level

Conceptually:

```swift
@MainActor
final class ScreenOverlayCanvasController {
    static let shared = ScreenOverlayCanvasController()

    func warmUp()
    func reconcileScreens()
    func publishLayer(_ layer: ScreenOverlayLayerSnapshot)
    func removeLayer(id: ScreenOverlayLayerID)
    func removeLayers(owner: ScreenOverlayOwner)
}
```

The first implementation can be AppKit-first: an `NSPanel` or `NSWindow` per screen hosting a custom `NSView` that draws layer snapshots. SwiftUI hosting can come later for feature surfaces that benefit from it, but the lowest-level canvas should stay simple.

## Non-Goals

This proposal does not make the shared canvas interactive.

Clickable UI should remain in separate panels or app windows. The shared canvas is for passive visual information and transient affordances. This keeps it safe: it should never steal clicks, focus, keyboard input, or app activation.

This proposal also does not move action dispatch into the canvas. Features decide behavior elsewhere and publish visual state into the canvas.

## Layer Model

Layers should be declarative snapshots, not live feature-owned views by default.

Good examples:

- `snapZones`: trigger rects, hovered zone, preview rect
- `gestureTrail`: path points, recognized shape, result label
- `focusHighlight`: screen rect, color, pulse style, timeout
- `hotkeyHints`: compact labels and positions
- `layerStatus`: current layer, running sessions, stale sessions

Each snapshot should include:

- stable layer id
- owner
- target screen id, or all screens
- z-index within the canvas
- visibility/opacity
- payload enum
- optional expiry

Example shape:

```swift
struct ScreenOverlayLayerSnapshot: Equatable {
    let id: ScreenOverlayLayerID
    let owner: ScreenOverlayOwner
    let screen: ScreenOverlayScreenTarget
    let zIndex: Int
    let opacity: CGFloat
    let payload: ScreenOverlayPayload
    let expiresAt: Date?
}

enum ScreenOverlayPayload: Equatable {
    case snapZones(SnapZoneOverlayPayload)
    case gestureTrail(GestureTrailOverlayPayload)
    case highlight(HighlightOverlayPayload)
    case hotkeyHints(HotkeyHintOverlayPayload)
}
```

This is intentionally plain. The canvas can render it synchronously without asking feature controllers for more state.

## Coordinate Rules

The canvas should make coordinate handling boring:

- external feature APIs accept global AppKit screen coordinates unless explicitly documented otherwise
- each screen view receives local coordinates derived from its `NSScreen.frame`
- Y-axis conversion is centralized
- screen identity uses `NSScreenNumber` when available
- all features use the same screen id helper

This matters because Lattices currently touches AppKit, CoreGraphics, AX, and ScreenCaptureKit coordinate systems. A shared canvas should reduce the number of local conversions.

## Snap Drag Migration

Snap drag is the best first adopter.

Today, `WindowDragSnapController` already computes:

- trigger rects
- visible label rects
- preview rects
- hovered zone
- screen grouping

Instead of owning `WindowSnapOverlayPanel`, it can publish a `snapZones` layer:

1. Drag begins and modifier mode is active.
2. Controller resolves zones as it does today.
3. Controller publishes `snapZones` snapshots grouped by screen.
4. Mouse movement updates the hovered zone and preview rect.
5. Mouse up removes the layer and dispatches tiling as today.

The drag-snap action path should not change.

## HUD Relationship

The HUD should not be moved wholesale onto the shared canvas.

The HUD is interactive: search, selection, keyboard focus, previews, sidebars. It should remain panel-based. But the shared canvas can support HUD-adjacent passive information:

- pre-HUD hotkey hints
- layer status while a modifier is held
- ambient screen map outlines
- tile target previews before full HUD activation
- “what will happen if I drop here” hints

Think of the canvas as the quiet always-ready visual substrate. The HUD remains the cockpit.

## Mouse Gesture Relationship

Mouse gesture recognition and event suppression must remain outside the canvas.

The gesture controller can publish trail snapshots and completion markers to the canvas, but:

- event tap callbacks still decide pass-through vs swallow
- shape recognition stays in the gesture pipeline
- action dispatch stays native and immediate
- visual renderer failure cannot affect action behavior

This dovetails with `LAT-001`: gesture visuals become consumers of semantic snapshots, not owners of recognition state.

## Hotkey Overlay Mode

A high-value use case is a passive hotkey layer.

When the user holds a configured modifier chord, Lattices could fade in lightweight context:

- current layer
- active project/session names
- snap zones
- mouse gesture affordances
- focused window identity
- available drop targets
- voice or command-mode status

This would feel different from opening the HUD. It is not a modal command surface. It is a heads-up layer that answers, “what can I do right now?”

If the user releases the chord, the layer fades away. If the user continues into an action, the relevant feature can take over and update its layer.

## Window Level

The canvas should probably start at a high but conservative level.

Existing snap overlays use `CGWindowLevelForKey(.maximumWindow)`. Clicky uses `.screenSaver`. Both work, but they should not become an accidental default for every future surface.

The canvas controller should centralize this decision and document it. A first version can use the level already proven by snap overlays, then adjust after testing with:

- Terminal.app
- iTerm2
- browser fullscreen
- Stage Manager
- fullscreen Spaces
- mission control edge cases

## Performance Rules

The canvas should be safe to keep warm:

- no polling when no layers are visible
- no timers inside the canvas unless a visible layer requires animation
- no filesystem reads during drawing
- no network access
- no feature callbacks during draw
- coalesce rapid updates per run loop
- keep payloads small and value-like

Animations should be bounded and cancelable. Expiring layers should clean themselves up even if a feature forgets to remove them.

## Failure Model

Overlay failure should be boring.

If the canvas cannot create a window, the feature should still run without visuals.

If one screen fails, other screens should continue.

If a payload cannot be rendered, the canvas should skip that layer and log a diagnostic.

If screen topology changes, the controller should reconcile windows and drop or remap stale screen-targeted layers.

The shared canvas must not:

- block input
- steal focus
- leave opaque windows stuck on screen
- make actions depend on rendering
- crash if a feature publishes malformed or stale visual state

## Implementation Plan

### Phase 1: Canvas Primitive

- Add `ScreenOverlayCanvasController`.
- Add a simple `ScreenOverlayWindow` or `ScreenOverlayPanel`.
- Add screen identity and coordinate helpers.
- Add a minimal `ScreenOverlayView` that can render `highlight` and `snapZones` payloads.
- Warm up windows at app launch, hidden and click-through.

### Phase 2: Drag Snap Adoption

- Replace `WindowSnapOverlayPanel` ownership with canvas snapshots.
- Keep existing snap-zone geometry and tiling behavior.
- Verify multi-monitor drag, fullscreen Spaces, and modifier toggling.
- Remove old snap overlay panel code after parity.

### Phase 3: Gesture Visual Adoption

- Publish gesture path snapshots from `MouseGestureController`.
- Move native gesture trail drawing into the canvas renderer.
- Keep recognition/action dispatch untouched.
- Align with `LAT-001` renderer hooks.

### Phase 4: Passive Hotkey Layer

- Add a read-only modifier watcher for a passive “show context” chord.
- Publish layer/session/window hints into the canvas.
- Fade in/out quickly without activating Lattices.
- Keep interactive HUD activation separate.

### Phase 5: Consolidation

- Identify duplicate overlay/highlight windows that can become canvas payloads.
- Keep interactive panels on `OverlayPanelShell`.
- Document which surfaces should use the canvas and which should remain separate.

## Acceptance Criteria

- One shared controller owns screen-sized click-through overlay windows.
- Snap zones render through the shared canvas with no behavior regression.
- Canvas rendering survives multiple monitors and screen changes.
- Visual layers can be added/removed by owner id.
- Hidden canvas windows do not intercept clicks or focus.
- Drag snap still tiles correctly when visual rendering is disabled.
- Mouse gestures can publish visual feedback without action dispatch depending on it.
- Diagnostics make canvas creation, screen reconciliation, and render failures understandable.

## Open Questions

- Should the base window level match current snap overlays or use a lower default?
- Should the canvas use one `NSView` renderer first, or host SwiftUI layers from the start?
- How should expiry be modeled: controller-owned timers, per-layer deadlines, or both?
- Should passive hotkey overlays live in the app config or user workspace config?
- How much of `MouseFinder` and window highlight feedback should migrate to the canvas?

## References

- `apps/mac/Sources/Core/Overlays/HUD/HUDController.swift`
- `apps/mac/Sources/Core/Desktop/WindowDragSnapController.swift`
- `apps/mac/Sources/Core/Input/MouseGestureController.swift`
- `apps/mac/Sources/Core/Overlays/OverlayPanelShell.swift`
- `docs/proposals/LAT-001-gesture-visual-customization.md`
