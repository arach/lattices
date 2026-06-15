# Hyperspace — Drag & Drop ("Intent Layer")

Status: design agreed 2026-06-14. Implements & evolves
`feedback_hyperspace_design_philosophy` (fake until commit, calm, WYSIWYG).

## Concept

Hyperspace gains a persistent **intent layer**: the top ~1/3 of the survey,
split into three sections — **Layers · Lattice · Spaces**. The exposé
window-grid fills the bottom ~2/3. You drag a window thumbnail *up* into the
intent layer and drop it on a target. Drops **stage** intent; **nothing real
moves until Enter**. **Esc** discards the plan and leaves the mode.

```
┌───────────────────────── INTENT  (top third) ─────────────────────────┐
│  LAYERS (tag-map, piles)  │   LATTICE  ½ ⅓ ¼ ▦   │      SPACES          │
│  [Dev] [Comms] [Docs] ＋  │   ┌──┬──┐ resolution  │   ▢1  ▢2  ▢3  ＋      │
│                           │   ├──┼──┤ via mods     │   (drop = move)      │
├────────────────────────────────────────────────────────────────────────┤
│            EXPOSÉ — grouped window lattice  (bottom two-thirds)           │
└──────────────────────────────────────────────────────────────────────────┘
```

## Model: orthogonal axes (not one destination)

A staged intent for a window has three **independent** axes:

```
struct StagedIntent {
    var layers: Set<LayerID>     // MULTI — non-exclusive tag-map
    var location: PlacementSpec? // single — where on this screen
    var space: SpaceID?          // single — which macOS Space
}
stagedIntents: [wid: StagedIntent]
```

- **Layers are non-exclusive** — a window can be dropped into any number of
  piles. Maps cleanly to `StudioLayer` (rule-backed: one window can match many
  rules). Dropping into a pile adds membership; dropping again removes it.
- **Location** and **Space** are single-valued (re-drop replaces).
- A window with an empty intent stays exactly where it is (= un-picked today).
- **Enter** commits every axis of every staged window at once. **Esc** discards.

The existing keyboard pluck (`pickOrder` → balanced grid) is preserved as a
fast path; it becomes one way of staging a location. Drag is additive, never a
replacement for the keyboard model.

## Sections

### Layers (left) — piles
Each layer is a **pile** of its members' thumbnails (screenshot-forward, on
brand). Multi-membership reads for free: the same thumbnail appears in several
piles; hovering a window glows every pile it belongs to. `＋` pile = new layer
seeded from the dropped window. **Fallback:** collapse piles to compact labeled
chips beyond ~6–8 layers. Commit via `StudioLayerStore` rule authoring (the
existing ⌘L path).

### Lattice (middle) — granularity by modifier
A live grid preview mirroring screen proportions. Resolution while dragging:

| modifier | grid |
|----------|------|
| (none)   | quarters 2×2 |
| ⇧        | halves |
| ⌥        | thirds |
| ⌘        | fine grid (4×4 — the placement target) |

Plus a segmented `½ ⅓ ¼ ▦` selector for mouse-only users. Drop on a cell →
stage `location`. Commit via `WindowTiler.tileWindowById(wid:pid:fractions:on:)`
animated by `RealWindowAnimator`.

### Spaces (right)
Strip of Spaces from `getDisplaySpaces()`. Drop → stage `space`. Commit via
`WindowTiler.moveViaCGS` / `window.move {spaceId}`. **Known gremlin:** the
private CGS APIs are flaky; treat as best-effort, build last.

## Interaction

1. **Grab** a tile → screenshot ghost follows the cursor; the source slot keeps
   a **placeholder** (the lattice never reflows mid-drag — anti-destabilizing).
2. **Drag up** into intent → the section under the cursor highlights; over the
   lattice section the current-resolution grid appears.
3. **Drop** → set the staged axis, dock a marker (pile card / grid marker /
   space chip), badge the source tile (`▦ ¼`, `L:Dev`, `→ 2`).
4. **Cluster drag** (bonus): grab a whole cluster box → stage all its windows to
   one target at once.
5. **Enter** commits the plan + exits. **Esc** discards + exits. Keyboard
   pluck/gather still works alongside.

## Phasing

- **Phase 0 — staging model. ✅ DONE (2026-06-14).** `StagedIntent`
  (orthogonal axes) + `stagedIntents` on `MotionPanel`; `commitStagedIntents(on:)`
  wired into `gatherInPlace()` (location axis live, layer/space stubbed). Dormant
  until the drag UI populates it; existing pluck/gather untouched. Build-verified.
- **Phase 1 — drag → location. ✅ DONE (2026-06-14).** Persistent top-third intent
  band (Layers stub · Lattice live · Spaces stub). One `DragGesture` per tile (min
  0) does both: a near-zero move = pluck (tap), a real drag lifts a screenshot ghost
  while the source tile hollows to a dashed placeholder (no reflow). Lattice section
  = `½ ⅓ ¼ ▦` selector with live modifier override (⇧ halves · ⌥ thirds · ⌘ fine) and
  a drop grid mirroring screen aspect; the hovered cell lights. Drop → stage
  `location` (badge "¼ 1,0" on the tile); gather commits via `tileWindowById`.
  Staged-location windows are excluded from the balanced gather grid. Drag state
  lives on `MotionPanel` (survives rebuilds; rebuilds suppressed mid-drag) and is
  screen-scoped. Build-verified.
- **Phase 2 — drag → layer. ✅ v1 DONE (2026-06-14).** Layers stub replaced by live
  drop piles from `StudioLayerStore` (member thumbnails + match count) plus a `＋`
  pile. Dragging a tile onto a pile toggles a staged join (`StagedIntent.layers`,
  multi-membership); onto `＋` stages a fresh layer (`StagedIntent.newLayer`). Piles
  hit-test via `LayerFrameKey` (root space), light under the cursor, and stay tinted
  while holding a staged join; the tile badges layer count ("L2") alongside any staged
  location. Commit on gather: `addAppToLayer` appends an app clause to each staged
  layer (rule-backed, coarse — like `saveFromPluck`); `＋` seeds one new layer from all
  its windows. Esc-safe (nothing written until gather). Build-verified.
  **Polish (2026-06-14):** drop "landing" beat (`DropPulse` token on the drag model
  fires an expanding ring at the released cell/pile, survives the post-drop rebuild);
  active-section highlight (the Lattice/Layers card lights while the cursor is over it
  mid-drag, so you see which axis you're committing); a live resolution readout next
  to `½ ⅓ ¼ ▦` ("⌘ fine", "quarters", …); and a plan-summary pill under the band
  ("▦ N placed · ▢ M tagged · ⏎ commit · esc discard"). Build-verified.
  **Fixes/evidence (2026-06-14):** (1) Enter-to-confirm sometimes fell on the floor —
  a click/drag on a survey screen-panel (`canBecomeKey == false`) could leave the app
  with *no* key window. Fixed with a `.leftMouseUp` monitor that re-claims key on the
  next runloop turn. (2) Standing evidence of the plan now lives in the band itself:
  staged locations draw as translucent app-tinted footprints in the Lattice preview at
  their true fractional rects (resolution-agnostic), and layer piles carry a "＋N"
  staged-join badge — not just the per-tile badges + transient pulse.
  **Band reshape + hybrid piles (2026-06-14):** Spaces deferred (its behaviour wasn't
  clear yet) → the band is now just Layers + Lattice, splitting the width evenly. Layer
  piles became the **hybrid** design: a compact, tactile *deep stack* at rest (top window
  crisp, two more peeking with depth/shadow; name + count + ＋N), and a floating **roster
  card** (name · rule from `StudioLayer.summary` · live member thumbnails · count · ＋N)
  that reveals on plain mouse-hover (`inspectLayer`/`inspectScreen`) or while it's the
  drop target. The roster is rendered at body level (above the survey) anchored to the
  pile's reported frame, so revealing it never reflows the row. Build-verified.
  **Layer = screen-map (2026-06-14):** the deep-stack/roster-strip didn't show *what a
  layer looks like*, so a layer is now rendered as a **mini screen-map** — its member
  windows drawn as app-tinted rects at their real (screen-relative, top-origin) positions
  (`LayerMember.frac` via `MotionPanel.axRect(of:)` + `frac(of:in:)`). Compact map at rest;
  the floating card expands it to a big map (member thumbnails filled in). Busy layers (10+
  windows) read fine — they're just small rects. **Cheap per-monitor scoping:** each screen's
  band shows the layer's members *on that display* (`layerPiles(on:)` filters by `entry(_:isOn:)`);
  same global layer can appear on both monitors showing its slice. Selector uses true mini-grid
  icons (2×1/3×1/2×2/4×4) instead of the ambiguous ▦. Build-verified.
  **Band = 3 slots: Layers · Preview · Grid (2026-06-14).** The big reorg. Instead of each axis
  rendering its own preview (a projection over the survey, a window-in-cell), the band has a
  dominant **middle Preview canvas** — one well-established screen-map that renders the current
  intent: a hovered/selected *layer's* formation, else the *staged-location plan* + the live
  placement of whatever you're dragging onto the **Grid** (right, now just drop-target cells +
  the resolution selector). **Layers** (left) is the selectable pile list. Drops still land on
  Layers/Grid; the Preview is display-only (`previewCanvas`/`zoneRect`). Removed the full-survey
  projection and the in-cell/over-grid staged markers — all consolidated into the middle.
  **→ Preview became an ephemeral PiP (2026-06-14).** A fixed middle slot is dead weight when
  idle (disruptive). So the band is back to **two control slots — Layers · Grid** — and the
  preview is an **ephemeral PiP** (`previewPiP`/`shouldShowPreview`): a small lit panel that
  blooms top-centre under the band *only* while hovering/selecting a layer or dragging onto the
  grid, and fades out otherwise.
  **→ Settled: dedicated slot, never empty (2026-06-14).** The PiP didn't read as a PiP and
  still felt wrong; the call was to **dedicate a slot in the top row** after all. The reason the
  fixed slot felt disruptive before was the *empty* state — fixed by making it **never empty**:
  the Preview's default content is the **current layout of this display** (every on-screen window
  as a faint `baseline` zone via `currentLayout(on:)`), with **staged** moves drawn bright at
  their targets, the **live** drop highlighted while dragging, and a hovered layer's formation
  overriding it. So band = three slots again — Layers · Preview · Grid — but the Preview always
  reads as useful (`previewCanvas` + `ZoneStyle` baseline/staged/live).
  **→ Settle on land, highlight in the survey (2026-06-14).** Two refinements after testing:
  (1) *Preview only updates on landed, not on hover-while-dragging* — the mid-drag live cell
  felt disruptive (it chased the cursor). `rosterPileID` now returns nil whenever `drag.isActive`,
  and `previewCanvas` dropped the `.live` drop cell; during a drag the Preview holds steady on
  baseline + the staged plan, and only changes when a drop *lands*. (2) *Previewing a layer now
  highlights it in the bottom survey* — idle-hovering a pile dims every survey tile except that
  layer's windows (`highlightWids` from the hovered pile's members; in-layer tiles get an on-brand
  ring + glow, the rest fade to 0.26). Also hardened confirm: a `.keyDown` local monitor catches
  Enter/Esc even when a survey screen-panel (`canBecomeKey == false`) or nothing holds key, so
  confirm/cancel can't fall on the floor (alongside the mouseUp key-reclaim).
  **→ Mouse exit + desktop-layer projection (2026-06-14).** (1) A mouse-driven **✕ exit** button
  (top-right, above the gear) — there was no trackpad way out before (only Enter/Esc). It just
  *closes* the survey keeping what's on screen (`ExposeView.onExit` → the panel's `onExit`); Esc
  stays the explicit discard/revert. (2) **Layer preview now projects onto the desktop layer
  itself** (`layerProjection`): idle-hovering a pile projects that layer *life-size* into the
  desktop area below the band — its windows as lit, app-tinted cards (image + title) at their real
  screen-relative fracs on a screen-proportioned stage, the survey sunk behind a scrim, captioned
  with the layer name + on-display count. The middle Preview still says "what's in here"; this says
  "here's how it sits on your screen." Display-only (`allowsHitTesting(false)`), fades on hover via
  the body's `rosterPileID` animation. Coexists with the in-survey dim/highlight underneath.
  **→ Right-click a window → life-size placement stage (2026-06-14).** A mouse-only twin of
  drag → Grid. Secondary-click any survey tile (`RightClickCatcher`, an `NSViewRepresentable`
  that claims *only* right-clicks via the `NSApp.currentEvent`/`hitTest` trick so left taps/drags
  still reach the tile's DragGesture) → `drag.beginPlacing(wid)`. A modal `placementStage` blooms
  over the desktop area: the screen with its current windows faint for context, a clickable **grid
  of the active resolution**, and the picked window drawn as a bright ghost that **previews into
  each cell as you hover** (`placementGhost` at the hovered cell's frac). Click a cell →
  `commitPlacement` → same `onDrop`/`handleDrop` staging path (badge + plan + pulse). A compact
  res selector in the caption (binds `drag.baseRes`); click-away or Esc cancels (Esc closes the
  stage before it exits the mode — handled in both `keyDown` and the key monitor). State lives on
  `HyperspaceDrag` (`placeWid`/`placeScreen`/`placeCell`), screen-scoped.
  **→ Correction: right-click = a menu, not an action (2026-06-14).** Firing the placement stage
  straight off a right-click was surprising — right-click should *offer options*. Replaced the
  `RightClickCatcher` with a native `.contextMenu` (`tileMenu`): quick tile presets (Left/Right/
  Top/Bottom half, Quarter ▸, Maximize) that **stage** immediately via `stagePlacement` → `onDrop`,
  an **Add to Layer ▸** submenu (`onDropLayer`), pluck/unpluck, and a single **"Place…"** item that
  opens the life-size stage as a deliberate visual pick. The stage code (`placementStage` et al.) is
  unchanged — just gated behind the menu now. `RightClickCatcher` removed.
  **→ Simplify: the survey IS the preview (2026-06-14).** It had grown three preview systems
  (middle Preview canvas, life-size desktop projection, Place stage) all answering "what will this
  do?" — too much. Collapsed to one principle: Hyperspace is already a screenshot layer on top of
  the desktop, so the survey itself is the preview, shown once. **Removed** the middle Preview slot
  (`previewSection`/`previewCanvas`/`previewSubtitle`) → band is now **two slots: Layers · Grid**.
  **Removed** the desktop projection (`layerProjection`/`projectionCard`/`projectionCaption`).
  **Kept** the one in-context preview: hover a layer → its windows light in the survey, the rest dim
  (`highlightWids`). **Kept** the right-click menu (`tileMenu`, full — presets + Quarter ▸ + Maximize
  + Add to Layer ▸ + pluck + a "Place…" item) and **kept** the Place stage, but **resized** it: it
  now reserves margins + caption height *before* fitting the screen-proportioned stage, so the
  "screen" always sits fully inside the monitor with air (was overflowing/awkward). `zoneRect`/
  `ZoneStyle`/`currentLayout` retained (the Place stage still uses them).
  **→ Place = full-screen overlay (2026-06-14).** The windowed Place stage clipped at the bottom and
  the preview felt too big. Reworked into a **full-screen overlay**: drop the `bandHeight` padding +
  `.ignoresSafeArea()` so it covers the whole monitor; the stage is the screen at true proportions
  (only an 18px inset for the rounded edge) so the grid maps 1:1 to real placement — big, can't-miss
  targets you click wherever you want it. Backdrop bumped to **0.86 opacity** (near-opaque, lit
  gradient). Grid cells got wider gaps + bigger radius. The window ghost (`placementGhost`) is now
  restrained — subdued screenshot (~0.42 armed) + glowing app-tint border, not a dominating card.
  Chrome (badge, gear/✕, plan pill) hides while `drag.isPlacing` so the stage owns the screen.
  **→ Fix size mismatch: preview uses visibleFrame (2026-06-14).** Windows tile into
  `screen.visibleFrame` (`WindowTiler.tileFrame`), but the preview built its aspect + grid from the
  full `screen.frame` — so cells were taller/offset vs where windows actually land, and the faint
  context windows left a menu-bar gap at the top. `MotionPanel.axRect(of:)` and both `screenAspect`
  args now use `visibleFrame`, so the stage proportions, grid cells, baseline footprints, and layer
  mini-maps are all 1:1 with real placement.
  **→ Fix bottom row behind the Dock (2026-06-14).** The full-screen stage was centred in the full
  `frame`, so the bottom grid row fell behind the Dock and the top under the menu bar ("bottom tile
  ends outside the viewport"). Now the backdrop still fills the monitor, but the stage is placed
  inside the **usable region** via `MotionPanel.usableInset(of:)` (frame→visibleFrame edges, passed
  as `ExposeView.usableInset`) and `.position(usable.midX, usable.midY)` — every cell sits fully on
  screen.
  **→ Place = a framed miniature monitor showing the future (2026-06-14).** The full-screen stage was
  the worst of both: faint transparency (not pretty), still leaked off-screen, and the immersive
  takeover felt like a bug ("why am I here?"). Reworked per direction into a **miniature of this
  monitor** — `monitorVessel`: a bezel (+chin, brand dot) framing a screen, centred at ~52%×56% of
  the display, floating in a **heavy 0.9 scrim** that swallows the desktop. A contained, illustrated
  control — can't leak, reads as deliberate. The screen shows the **projected future layout**, not
  the live desktop: unchanged windows as faint footprints, **staged moves bright at their new spots**
  (`stagedPlan` reused), and the window being placed tracking the hovered section (resting at its
  staged target if any). Sections (`placementGrid`) clearly delineated; click commits. `usableInset`
  now unused by Place (kept on `ExposeView` for now).
  **→ Vessel polish: opacity + centering (2026-06-14).** Scrim 0.9→**0.96** (survey no longer ghosts
  through), the monitor's **screen fill is now opaque** (was a translucent gradient that let the
  desktop show through), and the caption moved from a VStack above the monitor to an `.overlay(.top)`
  so the **monitor sits at true screen centre** (the caption was pushing it low).
  **→ Ghost is section-sized, not window-sized (2026-06-14).** At rest the ghost was drawn at the
  window's *current* frac, so a big window looked larger than every section ("why is it bigger than
  the spots?"). Now `placementGhost` draws the bright preview *only while hovering a section*, exactly
  section-sized (its real future size); at rest it's a quiet dashed outline at the window's current/
  projected spot (identity + origin, clearly not a target).
  **→ Fix screenshot aspect overflow (2026-06-14).** The window screenshot overflowed its zone
  (width-led, height ran past) because `.clipShape` was applied to the `aspectRatio(.fill)` *image*,
  which scales up to cover — so the clip happened on the already-overflowed image. Fixed in `zoneRect`
  and `placementGhost` by clipping the *framed container* (ZStack → `.frame(zone)` → `.clipShape`),
  the same pattern the survey tiles use — confining the fill to the zone in both dimensions.
  **→ Create-new-layer flow ✅ (2026-06-14).** Tapping the ＋ pile opens `NewLayerPanel` (new file
  `Core/Overlays/Motion/NewLayerPanel.swift`) — its *own* key NSPanel (level +2, full-screen scrim +
  centred vessel) because the survey's screen-panels can't become key, so a hosted TextField wouldn't
  take input. The form: an auto-focused **name** field (smart default from plucked apps), a **Defined
  by** row of toggleable app chips (thumbnail + count; plucked apps preselected), a live "matches N
  windows" readout, and Create/Cancel. Create → `StudioLayerStore.add(name:match:)` with the selected
  apps as OR'd clauses, then `rebuildExposeView`. Wiring on `MotionPanel`: `presentNewLayer()` seeds
  candidates from `surveyMembers`/`pickOrderByScreen`; `ignoreResign=true` while open (so making the
  panel key doesn't exit Hyperspace); the `.keyDown` monitor stands down while `newLayerPanel != nil`;
  `finishNewLayer()` reclaims key. Drag-onto-＋ quick auto-named path still works.
  **Remaining (v2):** **drag-a-window-*out* of a layer to remove it** — deferred because
  rule-backed layers can't drop one window without an *exclusion / explicit-membership*
  model (staged joins already un-stage on re-drop; existing rule-matched members are the
  hard case). Deeper per-monitor: give `StudioLayer` a real display affinity (own list per
  monitor) vs today's cheap view-filter. Plus cluster-box drag, compact-chip fallback,
  hover-a-window-glows-its-piles. **Create-new-layer flow:** the ＋ pile stages `newLayer`
  and commits via `saveFromPluck` (auto-named), but a real authoring flow (name it, choose
  what defines it) is still TODO. Optional flourish: hover could *move* real survey tiles
  into the layer's formation (vs the middle-canvas preview). Also open: drop a window directly
  onto the middle Preview at a freeform position; click-to-pin a layer in the Preview.
- **Phase 3 — drag → space.** Spaces strip + CGS commit. Hairy; isolated last. The band
  reserves room for it (currently a 2-way split); restore the `stubSection` when built.

## Files

- `apps/mac/Sources/Core/Overlays/Motion/WindowMotionMode.swift` — controller,
  `ExposeView`, state, key handling, the new intent band.
- `apps/mac/Sources/Core/Overlays/Motion/RealWindowAnimator.swift` — commit
  animation.
- `apps/mac/Sources/Core/Desktop/WindowTiler.swift` — location + space commit.
- `StudioLayerStore` — layer commit.

No overlap with the command-bar work (`Core/Overlays/CommandBar/`).
```
```
