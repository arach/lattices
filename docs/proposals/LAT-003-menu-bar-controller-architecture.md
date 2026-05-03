# LAT-003: Menu Bar Controller Architecture

## Status

Mostly implemented.

The menu bar, hotkey registration, daemon/service startup, workspace-inspector presentation, and activation-policy ownership have been extracted from `AppDelegate`. The optional `MenuBarPanelShell` remains deferred until a concrete menu-bar-adjacent panel needs it.

This document records a narrow architecture proposal for the Lattices menu bar surface. The product direction is deliberately conservative: keep the existing menu bar UX, which is already strong, and extract the architectural lessons that make future menu-adjacent surfaces easier to build.

## Summary

Lattices currently uses `NSStatusItem` directly from `AppDelegate`, with a cached `NSPopover`, a right-click context menu, prewarmed SwiftUI content, global hotkey setup, service startup, daemon boot, and onboarding checks all coordinated from the same launch object.

That works, and the visible menu bar experience should remain intact.

The improvement proposed here is structural:

- split menu bar ownership out of `AppDelegate`
- keep the current `NSPopover` for the main projects surface
- use custom `NSPanel` only for menu-bar-adjacent surfaces that need exact focus, positioning, or dismissal behavior
- keep activation policy updates centralized
- make app startup easier to reason about by moving hotkeys and services into small bootstrap components

The result should be less launch-time sprawl, not a new visual design.

## Why Now

Recent review of Clicky's menu bar implementation highlighted a useful pattern:

- `NSStatusItem` owns the menu bar icon
- a custom borderless `NSPanel` owns the transient control panel
- click-outside dismissal is explicit
- panel focus behavior is explicitly defined
- the app avoids standard popover chrome when it needs full control

Lattices does not need to copy that wholesale. Our `NSPopover` is a good fit for the main menu bar projects view, and it already gives us useful system behavior.

The lesson is more about ownership. Clicky's menu bar controller has one job. Lattices' `AppDelegate` currently has many.

## Current State

The relevant code is in `app/Sources/AppShell/AppDelegate.swift`.

Today, `AppDelegate` owns:

- app activation policy decisions
- status item creation
- menu bar icon drawing
- left-click popover toggling
- right-click context menu construction
- popover prewarming
- global hotkey registration
- command palette configuration
- drag snap, mouse gesture, keyboard remap startup
- layer hotkey registration
- tiling hotkey registration
- onboarding and permission checks
- daemon/model service startup
- updater checks
- debug launch flags

This is not a correctness problem by itself, but it makes the app entry point harder to change. Any new launch-time surface adds one more responsibility to a file that already coordinates too much.

## Non-Goals

This proposal does not redesign the menu bar UI.

This proposal does not replace the main menu bar `NSPopover` with a custom `NSPanel` by default.

This proposal does not change command palette, HUD, Screen Map, or daemon behavior.

This proposal does not alter the app's existing visual identity.

## Proposed Components

### 1. `MenuBarController`

Owns only menu bar behavior:

- create and retain `NSStatusItem`
- draw or load the status item icon
- route left-click and right-click behavior
- own the cached projects popover
- own the context menu
- expose `dismissPopover()`
- publish menu bar visibility state needed for activation policy

The existing popover behavior should move here almost unchanged:

- lazy `NSPopover` creation
- SwiftUI content prewarm
- `.transient` behavior
- dark appearance
- `latticesPopoverWillShow` notification

This keeps the UX stable while making ownership clearer.

### 2. `AppActivationCoordinator`

Owns activation policy decisions.

Today `AppDelegate.updateActivationPolicy()` checks a list of surfaces directly. That should become an explicit coordinator that asks registered surfaces whether they are visible.

Conceptually:

```swift
protocol AppVisibleSurface {
    var isVisibleForActivationPolicy: Bool { get }
}

final class AppActivationCoordinator {
    static let shared = AppActivationCoordinator()

    func register(_ surface: AppVisibleSurface)
    func refresh()
}
```

This avoids long hard-coded conditionals in `AppDelegate` as new windows are added.

### 3. `HotkeyBootstrap`

Owns global hotkey registration.

This includes:

- command palette
- unified window or Screen Map
- HUD
- voice command
- Hands Off
- mouse finder
- session layers
- tiling commands
- organize mode
- OmniSearch

The point is not to abstract the hotkeys away. The point is to isolate the big registration block into a component whose only job is binding actions to the existing controllers.

### 4. `AppServicesBootstrap`

Owns daemon and model startup:

- `OcrStore`
- `DesktopModel`
- `OcrModel`
- `TmuxModel`
- `ProcessModel`
- `LatticesApi`
- `DaemonServer`
- companion bridge
- agent pool

This keeps service startup grouped and timed without mixing it into menu bar construction.

### 5. Optional `MenuBarPanelShell`

Keep `NSPopover` for the current project list.

Add a small helper only if we introduce menu-bar-adjacent panels that need custom behavior:

- borderless `NSPanel`
- explicit click-outside dismissal
- non-activating or keyable variants
- manual positioning below the status item
- exact sizing around SwiftUI content

This helper should not replace `OverlayPanelShell`. It is specific to status-item anchored panels.

## Popover vs Panel Rule

Use the cached `NSPopover` when the surface is:

- anchored to the menu bar icon
- mostly standard transient menu behavior
- comfortable with popover sizing and dismissal semantics
- part of the existing projects/menu surface

Use a custom `NSPanel` when the surface needs:

- non-standard chrome
- unusual animation
- explicit click-outside rules
- custom focus behavior
- independent window level
- tighter control over multi-Space behavior

This is the main lesson from Clicky: use `NSPanel` where control matters. Do not replace a good `NSPopover` just to be clever.

## Suggested File Shape

```text
app/Sources/AppShell/
  AppDelegate.swift
  MenuBarController.swift
  AppActivationCoordinator.swift
  HotkeyBootstrap.swift
  AppServicesBootstrap.swift
  MenuBarPanelShell.swift      # optional, only when needed
```

`AppDelegate` should become a launch conductor:

1. set activation policy and appearance
2. create `MenuBarController`
3. register hotkeys
4. start input controllers
5. run onboarding or permission checks
6. start daemon services
7. process debug flags

It should not own the details of each of those systems.

## Migration Plan

### Phase 1: Extract `MenuBarController`

- Move status item creation.
- Move menu icon creation.
- Move context menu construction.
- Move cached popover creation.
- Keep existing public behavior and notifications.
- Route `MainView` dismissal through `MenuBarController` instead of reaching into `AppDelegate` if practical.

### Phase 2: Extract Hotkey Registration

- Move the global hotkey registration block into `HotkeyBootstrap`.
- Keep action closures identical.
- Keep controller singletons unchanged.
- Add small helper methods only where they improve readability.

### Phase 3: Extract Service Startup

- Move daemon/model startup into `AppServicesBootstrap`.
- Preserve existing startup order.
- Preserve diagnostic timing.
- Keep companion bridge preference behavior unchanged.

### Phase 4: Activation Policy Cleanup

- Introduce `AppActivationCoordinator`.
- Register visible surfaces.
- Remove the long hard-coded visibility conditional from `AppDelegate`.
- Keep the current `.accessory` to `.regular` behavior.

### Phase 5: Add `MenuBarPanelShell` Only If Needed

- Do not add this during initial extraction unless a concrete menu-bar panel needs it.
- If added, keep it separate from the main popover.
- Document why that surface needs panel behavior.

## Acceptance Criteria

- Main menu bar popover looks and behaves the same.
- Right-click menu behaves the same.
- First popover open remains prewarmed and fast.
- App activation policy behavior is unchanged.
- Hotkeys continue to register and fire as before.
- Daemon and model startup order is unchanged.
- `AppDelegate` is materially smaller and easier to scan.
- No new custom panel replaces the existing popover without a concrete need.

## Risks

The main risk is accidental behavior drift around activation policy and popover focus. The migration should be done in small steps and tested manually after each extraction.

The second risk is over-abstraction. These components should be plain controllers, not a framework. The goal is named ownership, not ceremony.

## Testing Notes

Manual testing should cover:

- left-click menu bar toggle
- right-click context menu
- popover dismiss by outside click
- popover dismiss from project actions
- command palette hotkey
- HUD hotkey
- Screen Map hotkey
- voice command hotkey
- app activation policy returning to accessory mode when surfaces close
- launch with `--diagnostics`
- launch with `--screen-map`

## References

- `app/Sources/AppShell/AppDelegate.swift`
- `app/Sources/AppShell/MainView.swift`
- `app/Sources/Core/Overlays/OverlayPanelShell.swift`
- `/Users/art/dev/ext/clicky/leanring-buddy/MenuBarPanelManager.swift`
