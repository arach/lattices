# Lattices ↔ Hudson Overlay: Alignment Guidance

Guidance from the Lattices side for Hudson Overlay (`/Users/art/dev/hudson-notch`):
notch notifications + Scout-style agent tail + a Lattices-like screen overlay where
agents get stable placements, quick show/hide/toggle, and small action shortcuts.

Written in response to a Scout consult. TL;DR at the bottom.

## First, a correction on sources

- **`LatticesOverlayChrome.swift` does not exist in the Lattices repo.** The real
  files to read are:
  - `apps/mac/Sources/Core/Overlays/ScreenOverlayCanvasController.swift` — the
    click-through per-screen canvas substrate (LAT-002).
  - `apps/mac/Sources/Core/Overlays/ScreenOverlayActorHUDController.swift` — actor
    hover HUD (WKWebView) plumbing.
  - `apps/mac/Sources/Core/Daemon/LatticesApi.swift` (~line 988+) — the
    `overlay.actor.*` daemon methods.
  - `docs/api.md` (§ Overlay UI, ~line 972+) — the shipped agent-facing contract.
  - `docs/proposals/LAT-002-shared-overlay-canvas.md`, `docs/proposals/LAT-004-interactive-overlay-actors.md`.

## The key mental model: Lattices has TWO separate "placement" systems

They are intentionally decoupled. Choosing the wrong one is the main pitfall.

### System A — Window tiling / layers (moves *real OS windows*)

- **What it is:** arranging foreign application windows (by `wid`) into a grid.
- **Grammar:** `PlacementSpec` / `GridPlacement` — `left`, `top-right`,
  `grid:4x4:0,0`, spans like `grid:4x4:0,0-1,1`. Operates in global AppKit/CoreGraphics
  coordinates and drives windows through the Accessibility API.
- **Session layers** (`workspace.json`): launch-and-tile contexts. Switching raises,
  launches-if-absent, and tiles a set of real windows. `layer.switch`, hotkeys ⌥1–9.
- **Studio layers** (`~/.lattices/layers.json`): rule-backed. A `match` array
  (app/title/session/space clauses) resolves *which existing desktop windows* belong
  to a layer, then recalls/scopes them.
- **Altitude:** heavyweight desktop-window management. AX, CGWindow, Spaces, multi-monitor.

### System B — Overlay canvas + actors (draws *app-owned UI*)

- **What it is:** one transparent, **click-through**, always-on-top window per display.
  Features publish lightweight visual layers into it. It never owns input semantics or
  action dispatch (explicit LAT-002 non-goal).
- **Passive layers** (`overlay.publish`): `toast`, `label`, `highlight`, `pet`. Declarative,
  value-type snapshots with `id`, `owner`, screen target, `zIndex`, `opacity`, payload
  enum, optional `ttlMs`. Rendered synchronously; no callbacks into features during draw.
- **Actors** (`overlay.actor.*`): a small *persistent* desktop object with a stable `id`,
  renderer (`sprite`), state, screen-local position, app-owned easing, and **selective
  hit-testing** (only actor/surface/button bounds capture input; everything else passes
  through). Persistent by default (`ttlMs: 0`, `dismissible: false`).
- **Altitude:** ambient, contextual, app-owned visuals in screen-local coordinates. No AX.

## Which one should Hudson's agent-placement model mirror?

**Mirror System B (overlay canvas + actor semantics). Do NOT mirror System A
(tile values / session layers).**

Hudson agents are notch notifications, an agent tail, and overlay chips — they are
*app-owned visual objects*, not foreign OS windows you're tiling. So:

- **"stable placements"** → actor `id` + anchored/pinned `position`, persistent
  (`ttlMs: 0`). This is exactly `overlay.actor.publish`. It is **not** a tile value.
- **"quick show/hide/toggle"** → this is `overlay.actor.visibility`
  (`show` / `hide` / `toggle` / `status`), the daemon twin of the app's **Hyper+B**
  park shortcut. This is the single closest existing primitive to what Hudson wants —
  it toggles the whole actor *layer's visibility without destroying actor ids/state*.
- **"small action shortcuts"** → actor click-activation (`targetApp` / `targetBundleId` /
  `targetAppPath`) is shipped; richer **action surfaces / click callbacks are still
  *planned* (LAT-004 phase 4), not shipped.** Don't build on them as if they exist.

Only reach into System A if Hudson genuinely needs to move *real* application windows
(e.g. "tile these three app windows around the notch"). Reusing the `grid:CxR:c,r`
grammar there would be sensible — but that's a different feature from agent placement.

## What to reuse conceptually vs. how to couple

**Reuse the *designs*, keep your own *contract*, bridge later.**

- **ScreenOverlayCanvas substrate — reuse the design.** One per-screen click-through
  window; features publish declarative, `Equatable` value snapshots (stable id, owner,
  screen target, z-index, opacity, payload enum, expiry); centralized coordinate/Y-flip
  handling; passive-by-default; boring failure. This is the correct substrate for a notch
  overlay. Adopt the shape; you don't need our code.
- **Actor semantics — reuse the model.** Stable-id desktop object, persistent by default,
  app-owned motion, selective hit-testing, visibility-toggle (park, don't destroy),
  dismiss-surface-not-actor. This is *the* model for "represent an agent on the desktop."
- **Coupling posture — small product-facing contract now, bridge adapter later.** Do not
  hard-depend on the Lattices daemon API yet, because:
  - action surfaces / event callbacks aren't shipped;
  - the contract is still evolving — actor scoping (global vs per-Space), pinned-position
    persistence (per-display vs per-Space vs global), and event routing (broadcast vs
    caller-routed) are literally **open questions** in LAT-004;
  - Hudson has product-specific needs (notch geometry, agent tail) Lattices doesn't model.

  Define Hudson's own thin contract whose verbs line up with ours
  (`publish` / `moveTo` / `visibility` / `clear` + `state`), so a later adapter can map
  Hudson → `overlay.actor.*` (or vice-versa) without reshaping either side.

## Pitfalls to avoid duplicating (hard-won here)

1. **Don't conflate the two coordinate/ownership worlds.** Tiling = foreign windows,
   `wid`, AX, global coords. Canvas = app-owned sprites, screen-local coords, no AX.
   Keep agent placement entirely in the canvas/actor world.
2. **Passive by default; input capture must be surgical.** The canvas is click-through;
   only actor/surface/button *bounds* hit-test, return `nil` everywhere else so desktop
   clicks pass through. Input capture must never cover the whole screen, and the app
   should not *activate* for a mere hover/click. Get this wrong and the overlay becomes a
   click-eating menace — it's the #1 thing to nail.
3. **Never let actions depend on rendering.** Overlay failure is boring: if the canvas
   can't draw, notification/agent logic still runs. Decouple semantics from visuals — your
   notch notifications must fire even if overlay rendering fails.
4. **Don't API-spam motion/position.** We learned WebSocket per-frame position updates are
   too chunky. Callers send *target + durationMs + easing*; the renderer owns interpolation
   at display cadence. Same for the agent tail: publish state *transitions*, not per-pixel
   updates.
5. **Dismiss ≠ delete; hide ≠ destroy.** Dismissal clears the *surface/message*, not the
   actor. Park/hide preserves ids and positions. Model show/hide/toggle as *visibility* so
   "stable placements" actually survive a toggle.
6. **Declarative value snapshots, not live view refs.** Layers/actors are plain Equatable
   payloads the canvas renders synchronously — no calling back into feature controllers
   during draw; coalesce rapid updates per run loop.
7. **"Layers" is overloaded — pick your meaning.** In Lattices it means three different
   things: `workspace.json` launch-and-tile layers, Studio rule-backed layers
   (`layers.json`), and ScreenOverlayCanvas *visual* layer snapshots. For Hudson agent
   placement you want the **third**. Don't import the word without disambiguating.
8. **Don't assume the unsettled parts are settled.** Spaces scoping, pinned-position
   persistence, and event routing are open on our side. If Hudson needs answers, decide
   independently rather than coupling to a contract that may still move.

## TL;DR

- **Mirror the overlay canvas + `overlay.actor.*` model, not tile values / session layers.**
  Agents are app-owned overlay objects, not tiled OS windows.
- Your "stable placement / show-hide-toggle / actions" map to
  `overlay.actor.publish` + `overlay.actor.visibility` + actor click-activation
  (action *surfaces* are planned, not shipped).
- **Align conceptually, keep a thin Hudson-owned contract, bridge to `overlay.actor.*`
  later.** The API is still evolving (open questions on Spaces scoping, pinned position,
  event routing) — don't hard-depend yet.
- Biggest pitfalls: conflating the tiling world with the canvas world; letting input
  capture or the app-activation escape the actor's bounds; and letting actions depend on
  rendering.
- Read `ScreenOverlayCanvasController.swift`, `LatticesApi.swift` (`overlay.actor.*`),
  and `docs/api.md` § Overlay UI — not `LatticesOverlayChrome.swift`, which doesn't exist.
