# Hudson Overlay: Recommended Next Steps (from the Lattices side)

Follow-up to `docs/hudson-overlay-alignment.md`. Hudson Overlay is becoming a small
standalone **paid** local desktop layer. Three surfaces: notch notifications, a
Scout-style agent tail/status view, and a Lattices-like screen overlay for agent
placements. Any app/agent sends local events via a small socket/CLI contract. First
paid wedge: **tail all agents** — status, notifications, lightweight talkback/action
shortcuts, stable per-agent placements. Calm, not goofy moving mascots.

Current Hudson state: SwiftPM accessory app; Unix socket event server + CLI; surfaces
`notch` / `agentTail` / `overlay`; agent context `id/name/workspace/service/placement/
visibility/shortcuts`; placement is a 3×3 enum (`topLeading`…`bottomTrailing`).

What I'd do if I held the Hudson side.

---

## Answers to the four questions

### 1. Vocabulary — keep your own; borrow the *actor placement* primitive, not tile/session vocab

**Keep your human product vocabulary (named slots). Do not mirror tile values or
session-layer vocabulary.** They solve a different problem:

- Lattices **tile** vocab (`left`, `grid:4x4:0,0`) describes *proportional rectangles a
  real window fills*. Your agents are small overlay objects that *dock at an anchor* —
  points, not rects. Wrong abstraction.
- **Session/Studio layers** are launch-and-tile / rule-match over *foreign OS windows by
  `wid`*. Irrelevant to overlay chips.

Your 3×3 enum is actually closer to Lattices **actor placement** (`placement: point|top|
bottom|center` + anchor + offset) than to tiling. So: keep the enum, but formalize it as a
resolver `slot → (anchor, normalizedPoint)`. That normalized anchor+point is your
**bridge unit** — it maps directly onto `overlay.actor.publish`'s anchor/x/y and onto
`GridPlacement.fractions` if you ever need rects. Vocabulary stays yours; geometry
contract lines up with Lattices for free.

One upgrade the wedge forces: a slot must hold **multiple** agents (many agents tail at
once). So evolve placement from "3×3 position" to **"slot (anchor lane) + order within
lane."** Dedicated slots = an agent *pinned* to a lane; everyone else flows into a default
lane the app packs calmly. This is the single most important placement change to make now.

### 2. Canvas — build your own; define an adapter seam; do NOT depend on Lattices at runtime

**Own your passive per-screen canvas. Put a `OverlaySink` protocol at the seam so a
Lattices backend can slot in later. Never a hard runtime dependency.**

- You're selling this. Coupling your core loop to another app's daemon lifecycle and an
  evolving API (`overlay.actor.*` still has open questions on Spaces scoping, pinned-
  position persistence, event routing) is unacceptable for a paid product.
- The canvas isn't much code: one click-through `NSPanel` per `NSScreen` + a value-snapshot
  renderer. You want control over notch geometry, calm packing, and your visual language.
- Define the seam both ways so the bridge is symmetric and opt-in:
  - `OverlaySink` (default = Hudson's own canvas; future `LatticesOverlaySink` maps
    publish/place/visibility → `overlay.actor.*`), and
  - because you already expose a socket/CLI, Lattices can equally be a *client* that feeds
    agent events into Hudson's tail.
  Default: Hudson hosts. Bridge is an adapter, never a dependency.

### 3. First implementation — contract first, then the tail (wedge), then calm placements

The wedge is the **agent tail**, not the fancy overlay. Ship the tail as a real
interactive panel; keep the click-through canvas for phase 2. (Lattices' own lesson:
interactive stuff lives in a real panel; only passive visuals go on the click-through
canvas.)

Design so Lattices-compat is a later adapter, not a rewrite. Compat comes from three
things, all cheap to establish now: **(a) verb-aligned contract, (b) normalized
anchor+point geometry, (c) the `OverlaySink` seam.**

### 4. Mistakes / overbuilds to avoid right now

- **No mascots / sprite animation system.** You said calm — skip motion, easing, an
  animator entirely. Static chips. (Drop Lattices' `OverlayActorAnimator` idea outright.)
- **Don't build the interactive hit-testing canvas first.** The tail (a normal panel)
  delivers the wedge with zero click-through-canvas complexity. Add the passive canvas
  second; make it interactive only if chip-level actions are truly needed — and even then
  prefer putting actions in the tail row.
- **Don't leak rendering into the contract.** Callers send *intent* (agent state, slot,
  notification, action list). The app owns pixels, z-order, packing. This is the #1
  discipline — the same "don't API-spam frames/positions" lesson Lattices learned.
- **Don't hard-depend on Lattices**, and don't adopt its tile grammar as your public
  vocabulary.
- **Don't overmodel geometry.** No `grid:CxR` spans, fractional rects, or multi-monitor
  span logic. Named slots + lanes is enough; the grid grammar is System A's job (real
  windows), not yours.
- **One source of truth.** A single `AgentStore` keyed by id feeds all three surfaces;
  notch/tail/overlay are pure projections. Two stores = drift.
- **Surfaces degrade independently.** Notch notifications must fire even if the overlay
  canvas is down; actions must never depend on rendering.
- **No Spaces/multi-Space machinery now.** Current-Space, all-displays. Pick simple
  defaults (placement persisted per display) and move on — Lattices left these as open
  questions; you don't need to solve them to ship.
- **Don't design licensing into the core yet.** Ship the wedge.

---

## The contract (sharpen this first — it's your real product API)

Newline-delimited JSON over the Unix socket, versioned envelope. Verbs deliberately
line up with `overlay.actor.*` so a bridge is a rename, not a redesign:

| Hudson event            | Meaning                                  | Lattices analog             |
|-------------------------|------------------------------------------|-----------------------------|
| `agent.upsert`          | register/update an agent (full context)  | `overlay.actor.publish`     |
| `agent.status`          | status + last line transition            | `overlay.actor.setState`    |
| `agent.notify`          | a notification (severity, actions)       | actor message / `overlay.publish` |
| `agent.place`           | assign agent to a slot/lane              | `overlay.actor.moveTo`      |
| `overlay.visibility`    | show/hide/toggle the whole layer         | `overlay.actor.visibility`  |
| `agent.clear`           | remove an agent                          | `overlay.actor.clear`       |
| `agent.action` (→ out)  | user clicked a declared shortcut         | `overlay.actor.actionSelected` |

```jsonc
// inbound
{"v":1,"type":"agent.upsert","agent":{"id":"scout-1","name":"Scout","workspace":"lattices",
  "service":"claude-code","status":"working","slot":"topTrailing","pinned":true,"visible":true,
  "shortcuts":[{"id":"open","label":"Open PR"},{"id":"approve","label":"Approve","style":"primary"}]}}
{"v":1,"type":"agent.status","id":"scout-1","status":"waiting","line":"Needs review on #31"}
{"v":1,"type":"agent.notify","id":"scout-1","surface":"notch","title":"Review?","body":"PR #31",
  "severity":"decision","actions":[{"id":"open","label":"Open PR"}]}
{"v":1,"type":"agent.place","id":"scout-1","slot":"topTrailing"}
{"v":1,"type":"overlay.visibility","action":"toggle"}
{"v":1,"type":"agent.clear","id":"scout-1"}
// outbound (emitted back to the caller that owns the agent)
{"v":1,"type":"agent.action","id":"scout-1","actionId":"approve"}
```

Status is a small closed set: `idle | working | waiting | blocked | done | failed`.
CLI is a thin wrapper (`hudson agent upsert|status|place|clear`, `hudson notify`,
`hudson overlay toggle`) plus a language-agnostic escape hatch
(`hudson emit '<json>'` / `nc -U ~/.hudson/hudson.sock`).

---

## Phased plan

### Phase 0 — Contract & core (do first; cheapest, unblocks integrators)
- Version the envelope (`v:1`). Single `AgentStore` keyed by id = source of truth;
  surfaces are projections.
- Lock the verb set above. Status enum closed. Document socket + CLI. This is the hardest
  thing to change once agents integrate — get it right before the UI.
- Add the `OverlaySink` protocol seam (default impl no-op/logging) even before the canvas.

### Phase 1 — Agent tail (the paid wedge)
- Interactive panel: every known agent with status dot, name, workspace/service, last
  line, "waiting-for-you" badge; keyboard nav; click focuses the agent's target app.
- Declared `shortcuts` render as row actions; click emits `agent.action` back over the
  socket (routed to the owning caller, not broadcast).
- Notch notifications driven by `agent.notify` (severity → style); notch + tail share the
  `AgentStore`.
- Global show/hide/toggle for the whole Hudson layer (hotkey + `overlay.visibility`).
- Sellable on its own: "one calm place to see and talk back to all your agents."

### Phase 2 — Overlay placements (calm, static)
- Your own passive per-screen click-through canvas. Small **static** agent chips docked to
  named slots; slots are lanes that stack calmly.
- `slot → (anchor, normalizedPoint)` resolver = the bridge unit. Persist per-agent slot +
  pin per display.
- Show/hide/toggle parks chips (visibility), never destroys agent state.
- No motion, no mascots, no whole-screen input capture.

### Phase 3 — Selective interaction + Lattices bridge (only if needed)
- If chips need direct actions: selective hit-testing — only chip/button bounds capture
  input, return `nil` everywhere else, don't activate the app on hover. Copy LAT-004's
  discipline exactly.
- Ship `LatticesOverlaySink`: map upsert/place/visibility/clear → `overlay.actor.*` so
  Hudson chips can optionally render through Lattices' canvas, and/or Lattices agents can
  appear in Hudson's tail. Opt-in, symmetric, still not a hard dependency.

---

## TL;DR
1. **Keep your slot vocabulary**; formalize `slot → (anchor, normalizedPoint)` as the
   bridge unit; evolve placement to **slot + lane order** so a slot holds many agents.
2. **Build your own canvas**, hide it behind an `OverlaySink` seam; no runtime Lattices
   dependency.
3. **Contract first → agent tail (wedge) as a real panel → calm static overlay chips →
   optional Lattices bridge.** Compat = verb-aligned contract + normalized geometry +
   the sink seam.
4. Avoid: mascots/animation, interactive canvas before the tail, rendering concerns in the
   contract, two agent stores, surfaces that can't degrade independently, Spaces machinery.
