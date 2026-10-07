---
name: action
description: Drive native macOS surfaces with Action. Use when observing the screen, resolving targets, clicking or typing through Action.app, working an app off the user's screen on the agent layer, recording a capture, or choosing between Action-owned Chrome and the user's regular browser.
compatibility: Requires macOS with Action.app and the Action MCP server.
metadata:
  author: arach
  homepage: https://lattices.dev/action
---

# Action

Action is native computer-use. Action.app owns AppKit, permissions, and
recording. Agents drive it through MCP. Do not reimplement capture or
accessibility.

When this skill is invoked, observe first, then act. Show the user what you
saw. Do not claim a recording finished until the finished marker or
`action.record.status` says it did.

Workspace tiling and tmux sessions belong to the `lattices` skill. Spatial
notes belong to `blink`.

## Prerequisite

```text
action.health
```

If health fails, build and launch Action.app from `products/action`, then
start MCP:

```bash
bun --cwd products/action native:doctor
bun --cwd products/action mcp
```

`ACTION_ROOT` must be the Action product root (`…/products/action`), not the
Lattices repository root.

## Drive loop

1. Call `action.driver.identify` once when the connection does not already
   name the agent.
2. Call `action.drive.begin` with an agent identity and a short task.
   Background is the supported drive mode.
3. Pass the returned `leaseId` to observe and act calls.
4. Call `action.drive.note` before each beat so the supervision HUD shows
   the current step.
5. Call `action.drive.aim` to move the synthetic cursor and highlight a
   region, then act.
6. Prefer `action.observe.snapshot` and `action.resolve.target` before
   `action.act.execute`.
7. Call `action.drive.release` when the work ends.

`action.drive.play` runs a named list of beats (note, aim, wait, act) as
one sequence. `action.stage.set` declares a color drape plus the windows
that sit on it. Never write the desktop picture.

## Agent layer

The agent layer is a private virtual display off in a corner of the
arrangement. `action.layer.open` moves an app's windows onto it, and the
user watches through a small PiP. Acts on the layer run as blinks: the
pointer and the frontmost app come straight back.

| The user… | Work |
| --- | --- |
| keeps working while you act, or says "don't touch my screen" | On the layer |
| is using the app you need (one Safari window, one Chrome window) | On the layer, borrowing that window with `windowId` or `windowTitle` |
| wants a page read or driven through the DOM | On the layer with `{ browser: true }`, then `action.layer.js` |
| points at something in front of them ("this dialog") | On their screen: snapshot, resolve, act |
| wants to watch it happen, or asks for a staged take | On their screen, with `action.stage.set` and `action.record.start` |

```text
action.layer.open      { bundleId, url? } | { browser: true, url } | { bundleId, windowTitle }
action.layer.snapshot  look first
action.layer.click     { x, y } in that snapshot, or { label }
action.layer.type / press / drag / scroll / go
action.layer.close     { outcome, summary }
```

The layer is one drive: `open` begins the lease and `close` releases it.
Use `action.layer.snapshot` and the `action.layer.*` primitives on it, not
`action.observe.snapshot`. One layer at a time; opening another closes the
first. `action.layer.record` records a take of the layer itself.

The operator owns the PiP. A paused layer refuses acts: wait. A layer
taken over is gone and its windows are back: stop, tell the user, close it
to acknowledge, and open another only if they ask. If the user can't see
the work, `action.layer.pip` brings the viewer back.

Close the layer when the work ends. Windows go back where they were;
windows the app opened on the layer are closed.

## Observe, resolve, act

Inspection:

```text
action.health
action.session.create
action.observe.snapshot
action.artifacts.list
```

Target-first input:

```text
action.observe.snapshot
action.resolve.target
action.act.execute
action.observe.snapshot
```

Prefer semantic, AX, or text queries over coordinates. Use coordinates only
when Action cannot resolve the target another way.

## Recording

```text
action.session.create
action.record.start
action.record.status
action.record.stop
action.artifacts.list
```

`action.record.start` is an acknowledgement only. Completion is the `.mov`
file, the `.finished` marker, and `action.record.status`. Keep
`recordingId`, `outputPath`, `stopFile`, and `finishedFile` until the run
is complete.

## Which browser

| Surface | Control |
| --- | --- |
| The user's regular Chrome | Open-only with `browser_open { mode: "regular" }`. Then native Action: snapshot, resolve, act. |
| An Action-owned Chrome identity | DOM tools over CDP: snapshot, click, fill, resize, screenshot. |
| An Action identity seeded from a real profile | DOM tools on sites the user is already signed in to, after a domain-allowlisted cookie import. |
| Action's Chrome on the agent layer | `action.layer.open { browser: true }`: the same identities, off the user's screen, with `action.layer.go` and `action.layer.js`. |

Regular Chrome is not a DOM target. Chrome 136 and later ignore remote
debugging on the default profile. Seed an Action identity when the page
needs the user's login.

Action Browser remains a standalone plugin:

```bash
claude plugin marketplace add arach/lattices
claude plugin install action-browser@action --scope user
```

Cookie import requires `confirm: true` and a domain allowlist. Do not
submit purchases, publish, or delete without the user's authority.

## Live docs

1. https://lattices.dev/action
2. `products/action/docs/browser-profiles.md`
3. `products/action/docs/recording.md`
4. `products/action/docs/native-runtime.md`
5. `products/action/docs/agent-layer.md`
