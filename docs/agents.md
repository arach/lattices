---
title: Agent Guide
description: Canonical contracts for agents using docs URLs, CLI, voice, and the daemon API
order: 6
---

Lattices exposes the same execution model through four surfaces:

- **Docs URLs** for discovery and citation
- **CLI** for shell-based agents
- **Daemon API** for typed programmatic control
- **Voice / hands-off / HUD** as clients of the same execution layer

The rule is simple: agents should learn the **canonical action model**
first, then choose the transport that fits the environment.

## Canonical mutations

These are the preferred action identifiers:

| Action | Purpose | Preferred surface |
|--------|---------|-------------------|
| `window.place` | Place a window or session using a typed placement spec | Daemon API |
| `layer.activate` | Bring up a workspace layer with explicit activation mode | Daemon API |
| `space.optimize` | Rebalance a set of windows using an explicit scope and strategy | Daemon API |

Compatibility wrappers still exist:

| Legacy method | Canonical equivalent |
|---------------|----------------------|
| `window.tile` | `window.place` |
| `layer.switch` | `layer.activate` with `mode=launch` |
| `layout.distribute` | `space.optimize` with `scope=visible`, `strategy=balanced` |

## Discoverability

Agents should use these paths in order:

1. **API schema**: `lattices call api.schema`
2. **Daemon reference**: [/docs/api](/docs/api)
3. **Agent guide**: [/docs/agents](/docs/agents)
4. **Voice model**: [/docs/voice](/docs/voice)
5. **Concepts / config**: [/docs/concepts](/docs/concepts), [/docs/config](/docs/config)

Useful CLI discovery commands:

```bash
lattices help
lattices call api.schema
lattices voice intents
```

## Placement contract

At the boundary, placements may be strings for convenience.
Inside the daemon, the canonical contract is typed.

String shorthand:

```json
{ "placement": "top-right" }
{ "placement": "grid:3x2:2,0" }
```

Typed placement objects:

```json
{ "placement": { "kind": "tile", "value": "top-third" } }
{ "placement": { "kind": "grid", "columns": 3, "rows": 2, "column": 2, "row": 0 } }
{ "placement": { "kind": "fractions", "x": 0.5, "y": 0, "w": 0.5, "h": 1 } }
```

This lets voice stay natural while the executor stays explicit.

## Choosing a surface

Use the **daemon API** when you need:

- typed receipts and traces
- explicit targeting by `wid`, `session`, or `app`
- composition across layers, windows, and optimization

Use the **CLI** when you need:

- one-shot shell execution
- quick discovery from inside an agent terminal
- compatibility with environments that already have `lattices`

Use **docs URLs** when an agent needs:

- a citeable contract
- a stable page to open in a browser or pass to another agent
- quick onboarding without reading source

## Examples

Node.js:

```js
import { daemonCall } from '@lattices/cli'

await daemonCall('session.launch', { path: '/Users/you/dev/frontend' })
await daemonCall('window.place', {
  session: 'frontend-a1b2c3',
  placement: { kind: 'tile', value: 'left' }
})
await daemonCall('layer.activate', { name: 'review', mode: 'launch' })
await daemonCall('space.optimize', { scope: 'visible', strategy: 'balanced' })
```

CLI:

```bash
lattices call api.schema
lattices call window.place '{"session":"frontend-a1b2c3","placement":"left"}'
lattices call layer.activate '{"name":"review","mode":"launch"}'
lattices call space.optimize '{"scope":"visible","strategy":"balanced"}'
```

## Receipts and traceability

Mutating daemon calls should return structured receipts when possible.
The important fields for agents are:

- resolved target
- resolved placement / scope / mode
- affected window IDs
- trace entries explaining why the daemon chose that path

This is what keeps voice, hands-off, and scripted execution scrutable.

## Voice and hands-off

Voice is not a separate execution system. It should compile into the
same canonical actions:

- "put Terminal in the upper third" → `window.place`
- "bring up review" → `layer.activate`
- "make this nice" → `space.optimize`

That keeps the interaction layer flexible while the executor stays
predictable.

## Assistant intelligence boundary

Assistant planning lives in TypeScript where possible:

- `bin/assistant-intelligence.ts` owns the intent catalog, prompt assembly,
  local rule planner, desktop snapshot formatting, and plan normalization.
- `bin/handsoff-worker.ts` and `bin/handsoff-infer.ts` call that module before
  falling back to model inference.
- Swift should remain the macOS execution layer: hotkeys, windows, AX/CG,
  SkyLight, panels, and visual feedback.

Use `lattices assistant plan <text> --json` to inspect the TS planner without
launching the app or mutating the desktop.
