# Component Extraction Roadmap

This note turns a codebase review into an incremental component plan for `lattices`.

The goal is not to rewrite the app around a new architecture in one move. The goal is to extract a few reusable primitives that make future features cheaper:

- a cmdcmd-style visual window or session switcher
- one shared action model across hotkeys, palette, voice, daemon, and companion
- less duplicated window lookup, space lookup, and preview logic

## Why this exists

Three pressure points showed up repeatedly:

1. `WindowTiler.swift` acts like several libraries at once.
2. action definitions exist in multiple parallel forms.
3. overlay and panel shells are repeatedly rebuilt per surface.

The result is that new UX surfaces often have to re-solve the same problems:

- how to find a target window
- how to map a user intent to a canonical action
- how to show a floating interactive surface
- how to capture and render previews

## Current duplication seams

### 1. Window and session lookup

The same session-tagged window matching idea appears in multiple places:

- `DesktopModel.windowForSession(...)`
- tag parsing during desktop polling
- CG window lookup paths in `WindowTiler`
- AX window lookup paths in `WindowTiler`

This is the strongest candidate for a single reusable locator.

### 2. Space topology and window membership

Display-space maps, current-space discovery, and window-space membership are rebuilt in several flows instead of being queried from one read model.

This makes space-aware features harder than they need to be:

- move window to space
- present window on the current space
- show where a session already lives
- build a visual desktop map

### 3. Window presentation and motion

`tile`, `present`, `batchMoveAndRaiseWindows`, and related paths all contain their own versions of:

- resolve target
- move or resize
- raise
- activate app
- mark interaction

That sequencing should be owned by one operation layer.

### 4. Preview capture and preview rendering

The codebase already has useful preview pieces, but they live in separate pockets:

- `WindowPreviewStore` in `HUDRightBar.swift`
- preview placeholder and preview card variants in HUD
- separate preview capture in `ScreenMapState.swift`

This is a strong signal that preview should become its own reusable subsystem.

### 5. Action definitions

Action and intent metadata currently live in several places:

- `HotkeyStore.swift`
- `PaletteCommand.swift`
- `IntentEngine.swift`
- `Intents/LatticeIntent.swift`
- `LatticesApi.swift`

The sharpest duplication is that `IntentEngine.swift` and `Intents/LatticeIntent.swift` each define their own intent schema.

### 6. Overlay and panel shells

There is already a useful shared primitive for normal app windows in `AppWindowShell.swift`, but overlay surfaces still rebuild similar shell code:

- `CommandPaletteWindow.swift`
- `OmniSearchWindow.swift`
- `VoiceCommandWindow.swift`
- `LauncherHUD.swift`

The repeated shell concerns are:

- `NSPanel` setup
- blur and rounded-mask container setup
- screen placement
- activation and dismissal behavior
- event monitor lifecycle

## Proposed reusable components

This is the target component map.

### Desktop substrate

#### `SessionWindowLocator`

Responsibility:

- resolve a lattices session, title tag, app target, or explicit window id into a canonical window target
- try fast cache lookup first
- fall back through CG and AX in one place

Why:

- removes repeated session-tag matching logic
- gives palette, daemon, voice, HUD, and future switchers the same targeting rules

#### `SpaceTopologySnapshot`

Responsibility:

- expose a single read model for displays, spaces, current space, and window-to-space membership

Why:

- prevents repeated recomputation of display-space facts
- makes space-aware UIs easier to build

#### `WindowPresenter`

Responsibility:

- own the canonical move, resize, raise, activate, and interaction-marking flow
- support both single-window and batched operations

Why:

- centralizes the side-effect sequence
- makes future planners and higher-level actions less fragile

#### `WindowPreviewProvider`

Responsibility:

- capture, cache, and serve still previews or live previews for windows
- separate capture policy from UI rendering

Why:

- avoids HUD and Screen Map each inventing preview behavior
- directly supports a visual selector or session fan-out

### Action substrate

#### `ActionRegistry`

Responsibility:

- define canonical verbs once
- own parameter metadata, user-facing labels, phrase templates, and execution hooks

Minimal shape:

```swift
enum ActionID: String {
    case openPalette
    case openSearch
    case focusWindow
    case placeWindow
    case launchProject
    case switchLayer
    case killSession
    case refreshProjects
}

struct ActionParam {
    let name: String
    let type: ActionParamType
    let required: Bool
    let values: [String]?
}

struct ActionDef {
    let id: ActionID
    let title: String
    let params: [ActionParam]
    let hotkey: HotkeyMeta?
    let palette: PaletteMeta?
    let phrases: [String]
    let run: (ActionContext) throws -> JSON
}
```

Why:

- one action identity across hotkeys, palette, voice, daemon, and companion
- palette rows become runtime bindings of a verb to a target, not bespoke actions

#### `ActionContext`

Responsibility:

- carry structured arguments plus source information like `hotkey`, `palette`, `voice-local`, `daemon`, or `companion`

Why:

- makes execution and logging more consistent

### Overlay substrate

#### `OverlayPanelShell`

Responsibility:

- build a reusable floating `NSPanel` shell from configuration
- own blur or plain background, corner radius, window level, collection behavior, and hosting setup

Why:

- extracts the shared Spotlight-style panel construction path

#### `OverlayPlacement`

Responsibility:

- centralize placement policies like centered, spotlight offset, top-center, or mouse-screen placement

Why:

- removes repeated `visibleFrame` math

#### `OverlayLifecycleController`

Responsibility:

- own local event monitors, Escape dismissal, deactivate behavior, and cleanup

Why:

- reduces panel-specific lifecycle glue

### UI primitives

#### `WindowPreviewCard`

Responsibility:

- render a window preview, loading state, and unavailable state consistently

Why:

- low-risk first UI extraction
- immediately reduces duplicated HUD preview rendering

## Recommended extraction order

The sequence below favors leverage without taking unnecessary risk.

### Slice 1: `WindowPreviewCard`

Extract the repeated preview body and placeholder logic from HUD into a shared SwiftUI component.

Why first:

- UI-only
- already duplicated
- does not disturb CGS, AX, or window mutation paths

### Slice 2: `OverlayPanelShell`

Extract the shared panel-construction path from `CommandPaletteWindow` and `OmniSearchWindow`.

Why second:

- those two surfaces are the cleanest near-duplicates
- builds a reusable shell for a future visual selector

### Slice 3: unify intent schema

Remove the parallel intent-definition structures by expanding or reusing the types in `Intents/LatticeIntent.swift` and pointing them at existing execution handlers.

Why third:

- high leverage
- removes one entire duplicate definition system
- proves the registry shape before migrating hotkeys or palette

### Slice 4: `SessionWindowLocator`

Centralize session-tagged lookup across DesktopModel and WindowTiler.

Why fourth:

- strongest desktop duplication seam
- unlocks cleaner action execution and better future switcher targeting

### Slice 5: `SpaceTopologySnapshot`

Create one query layer for display and space topology.

Why fifth:

- stabilizes space-aware features before touching more motion logic

### Slice 6: `WindowPresenter`

Unify move, resize, raise, activate, and interaction-marking flows.

Why sixth:

- this is higher risk because it sits directly on side effects
- it is safer after lookup and topology are centralized

### Slice 7: `WindowPreviewProvider`

Lift preview capture and caching out of HUD-specific code and reconcile it with Screen Map preview capture.

Why seventh:

- more useful after overlay shell and preview card exist
- becomes the substrate for a visual window or session chooser

## Features this should unlock

Once the components above exist, the app can add new surfaces with much less bespoke code.

### cmdcmd-style visual switcher

Use:

- `OverlayPanelShell`
- `OverlayPlacement`
- `SessionWindowLocator`
- `WindowPreviewProvider`
- `WindowPresenter`

Possible behavior:

- fan out lattices sessions or all windows
- show live or cached previews
- focus, tile, move to space, or close from one surface

### Shared action surfaces

Use:

- `ActionRegistry`
- `ActionContext`

Possible behavior:

- define `placeWindow` once
- trigger it from voice, hotkey, palette, daemon, or companion
- keep labels and phrases aligned across surfaces

### Stronger planning and preview

Use:

- `ActionRegistry`
- `WindowPresenter`
- `SpaceTopologySnapshot`

Possible behavior:

- preview a multi-window action before applying it
- build transactional-feeling UI around batched movement

## Things not to do yet

- do not rewrite `WindowTiler.swift` in one shot
- do not migrate every overlay surface onto one abstraction immediately
- do not force the palette to become purely registry-generated before the action model is proven

The safer path is:

1. extract small reusable pieces
2. move one production surface onto them
3. verify behavior
4. repeat

## Summary

The strongest architectural opportunity here is not one big framework. It is three small substrates:

- desktop targeting and motion
- action definition and routing
- overlay panel construction

If those become reusable, `lattices` gets a much cleaner path to new features without making every new surface solve the same desktop and execution problems again.
