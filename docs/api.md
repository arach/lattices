---
title: Agent API
description: WebSocket API reference for programmatic control of lattices
order: 5
---

The lattices menu bar app runs a WebSocket server on `ws://127.0.0.1:9399`.
35+ RPC methods and 5 real-time events.

## Quick start

1. Launch the server (it starts with the menu bar app):

```bash
lattices app
```

2. Check that it's running:

```bash
lattices daemon status
```

3. Call a method from Node.js:

```js
import { daemonCall } from '@lattices/cli'

const windows = await daemonCall('windows.list')
console.log(windows) // [{ wid, app, title, frame, ... }, ...]
```

Or from any language — it's a standard WebSocket:

```bash
# Plain websocat example
echo '{"id":"1","method":"daemon.status"}' | websocat ws://127.0.0.1:9399
```

## Wire protocol

lattices uses a JSON-RPC-style protocol over WebSocket on port **9399**.

### Request

```json
{
  "id": "unique-string",
  "method": "windows.list",
  "params": { "wid": 1234 }
}
```

| Field    | Type    | Required | Description                          |
|----------|---------|----------|--------------------------------------|
| `id`     | string  | yes      | Caller-chosen ID, echoed in response |
| `method` | string  | yes      | Method name (see below)              |
| `params` | object  | no       | Method-specific parameters           |

### Response

```json
{
  "id": "unique-string",
  "result": [ ... ],
  "error": null
}
```

| Field    | Type           | Description                                  |
|----------|----------------|----------------------------------------------|
| `id`     | string         | Echoed from request                          |
| `result` | any \| null    | Method return value (null on error)          |
| `error`  | string \| null | Error message (null on success)              |

### Errors

| Error           | Meaning                              |
|-----------------|--------------------------------------|
| Unknown method  | The `method` string is not recognized |
| Missing parameter | A required param was not provided   |
| Not found       | The referenced resource doesn't exist |

### Connection lifecycle

- The server starts when the menu bar app launches and stops when it quits.
- Connections are plain WebSocket. No handshake, no auth, no heartbeat.
- The Node.js `daemonCall()` client opens a fresh connection per call and
  closes it when the response arrives. For event subscriptions, hold the
  connection open (see [Reactive event pattern](#agent-integration)).
- If the server restarts (e.g. after `lattices app restart`), existing
  connections are dropped. Clients should reconnect and treat it as
  stateless. There is no session resumption.

## Node.js client

lattices ships a zero-dependency WebSocket client that works with
Node.js 18+. It handles connection, framing, and request/response
matching internally.

### `daemonCall(method, params?, timeoutMs?)`

Send an RPC call and await the response.

```js
import { daemonCall } from '@lattices/cli'

// Read-only
const status = await daemonCall('daemon.status')
const windows = await daemonCall('windows.list')
const win = await daemonCall('windows.get', { wid: 1234 })

// Mutations
await daemonCall('session.launch', { path: '/Users/you/dev/myapp' })
await daemonCall('window.place', {
  session: 'myapp-a1b2c3',
  placement: { kind: 'tile', value: 'left' }
})

// Custom timeout (default: 3000ms)
await daemonCall('projects.scan', null, 10000)
```

**Returns** the `result` field from the response.
**Throws** if the server returns an error, the connection fails, or the timeout is reached.

### `isDaemonRunning()`

Check if the server is reachable.

```js
import { isDaemonRunning } from '@lattices/cli'

if (await isDaemonRunning()) {
  console.log('daemon is up')
}
```

Returns `true` if `daemon.status` responds within 1 second.

## TypeScript SDK facade

The CLI is a human/debug surface. Product code and agents should prefer the
typed SDK facade, which validates params with Zod and calls the same daemon
methods directly.

```ts
import { cua } from '@lattices/sdk'

await cua.magicCursor({
  app: 'Scout',
  xRatio: 0.52,
  yRatio: 0.91,
  text: 'What are the most important docs in this project, and what would an agent say after reading them?',
  treatment: 'execute',
  trail: 'comet',
  motion: 'rush',
  trajectory: 'overshoot',
  glow: 'halo',
  idle: 'wiggle',
  edge: 'ripple',
})

await cua.click({
  app: 'Scout',
  xRatio: 0.74,
  yRatio: 0.95,
  transport: 'ax',
  axLabel: 'Send',
  noFocus: true,
  treatment: 'execute',
})
```

`@lattices/cli/cua` exposes the same CUA module for CLI-adjacent scripts, but
new app and agent code should use `@lattices/sdk` or `@lattices/sdk/cua` so the
import names the product surface instead of the CLI package.

### Error handling

`daemonCall` throws on errors — always wrap calls in try/catch:

```js
import { daemonCall } from '@lattices/cli'

try {
  await daemonCall('session.launch', { path: '/nonexistent' })
} catch (err) {
  // err.message is one of:
  //   "Not found"              — resource doesn't exist
  //   "Missing parameter: ..." — required param missing
  //   "Unknown method: ..."    — bad method name
  //   "Daemon request timed out" — no response within timeout
  //   ECONNREFUSED             — daemon not running
  console.error('Daemon error:', err.message)
}
```

---

## Runs And Capture

Runs are local executions that produce trace events and artifacts. Capture
methods write into the Lattices run store under
`~/Library/Application Support/Lattices/Runs/`.

| Method | Type | Description |
|--------|------|-------------|
| `runs.create` | write | Create a run record and artifact directory |
| `runs.list` | read | List recent runs |
| `runs.get` | read | Inspect one run, including artifacts and trace events |
| `runs.artifacts` | read | List artifacts for one run |
| `capture.screenshotWindow` | write | Capture a window screenshot as a run artifact |
| `capture.screenshotRegion` | write | Capture a screen region as a run artifact |
| `capture.zoomArtifact` | write | Crop and zoom an image artifact into a linked artifact |
| `vision.analyzeWindow` | write | Capture a window and run local OCR-based visual analysis |
| `vision.analyzeArtifact` | write | Analyze an existing image artifact or path with local OCR |
| `computer.prepare` | write | Resolve and optionally capture a terminal target without mutating it |
| `computer.windowState` | write | Inspect a target window's AX tree and optionally write screenshot/run artifacts |
| `computer.elementAction` | write | Stage or execute an AX action against a snapshot element id |
| `computer.typeElement` | write | Stage or execute AXValue text insertion against a snapshot element id |
| `computer.setValue` | write | Alias for replacing a snapshot element's AXValue |
| `computer.pressKey` | write | Stage or execute one key press against an explicit target window |
| `computer.hotkey` | write | Stage or execute a keyboard shortcut against an explicit target window |
| `computer.focusWindow` | write | Resolve, capture, focus, and verify a target window |
| `computer.showCursor` | write | Show a visible cursor appearance and record it as a run |
| `computer.launchApp` | write | Launch or focus a normal macOS app and record the run |
| `computer.typeWindowText` | write | Type or paste into a normal app window, optionally after a click |
| `computer.click` | write | Stage or execute a window-relative click target; prefers no-focus `AXPress` in auto/ax transport |
| `computer.doubleClick` | write | Stage or execute a pointer double-click target |
| `computer.rightClick` | write | Stage or execute a right-click/context-click target |
| `computer.scroll` | write | Stage or execute scroll wheel input |
| `computer.drag` | write | Stage or execute a pointer drag between two points |
| `computer.verify` | write | Verify OCR, AX, or artifact-change expectations |
| `computer.demoScout` | write | Scout warm-up run for memo/demo recording |
| `computer.typeText` | write | Insert text into a safe terminal using the least intrusive transport |
| `computer.demoTerminal` | write | Compatibility wrapper for a bounded terminal text action |
| `browser.getText` | read | Read visible browser text through Accessibility |
| `browser.queryDom` | read | Query DOM summaries with explicit browser automation consent |
| `browser.executeJavascript` | write | Stage or execute browser JavaScript with explicit consent |

#### `capture.screenshotWindow`

Capture a window as a PNG artifact. If no target is provided, Lattices captures
the frontmost non-Lattices window.

**Params**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `wid` | uint32 | no | Target CGWindowID |
| `session` | string | no | Target lattices session |
| `app` | string | no | Target app name |
| `title` | string | no | Optional title filter for `app`, or run title |
| `runId` | string | no | Existing run to append to |
| `source` | string | no | Calling surface label |
| `filename` | string | no | Optional artifact filename |

```js
await daemonCall('capture.screenshotWindow', { source: 'agent' })

await daemonCall('capture.screenshotWindow', {
  session: 'frontend-a1b2c3',
  filename: 'before-layout.png'
})
```

#### `capture.screenshotRegion`

Capture an explicit screen rectangle as a PNG artifact. If no rectangle is
provided, the endpoint resolves `wid`/`session`/`app`/frontmost target and
captures that window frame.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `x`, `y` | double | no | Region origin in screen coordinates |
| `width`, `height` | double | no | Region size |
| `w`, `h` | double | no | Size aliases |
| `wid`, `session`, `app`, `title` | target | no | Target window fallback |
| `runId`, `source`, `filename` | mixed | no | Standard run/artifact fields |

```js
await daemonCall('capture.screenshotRegion', {
  x: 120,
  y: 160,
  width: 640,
  height: 420,
  filename: 'composer-region.png'
})
```

#### `capture.zoomArtifact`

Crop and zoom an existing image artifact into a new PNG artifact on the same
run. Coordinates are image pixels; ratio fields are relative to the source
image.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `runId` | string | no | Run containing the artifact |
| `artifactId` | string | no | Source artifact id |
| `path` | string | no | Source image path fallback |
| `x`, `y`, `width`, `height` | double | no | Crop rectangle in image pixels |
| `xRatio`, `yRatio`, `widthRatio`, `heightRatio` | double | no | Crop rectangle as image ratios |
| `scale` | double | no | Zoom scale, default `2`, max `8` |
| `filename`, `source` | string | no | Output artifact metadata |

```js
await daemonCall('capture.zoomArtifact', {
  runId: 'run_...',
  artifactId: 'art_...',
  xRatio: 0.35,
  yRatio: 0.7,
  widthRatio: 0.3,
  heightRatio: 0.2,
  scale: 3
})
```

#### `vision.analyzeWindow` / `vision.analyzeArtifact`

Run explicit local OCR-based visual analysis. These endpoints do not call a
cloud vision model; they use the same on-device Vision OCR path as Lattices OCR
and return `fullText`, text blocks, a short answer, and optional `verified`
when `contains` or `notContains` is supplied.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `instruction` | string | yes | Question or analysis instruction |
| `wid`, `session`, `app`, `title` | target | no | Window target for `vision.analyzeWindow` |
| `runId`, `artifactId`, `path` | mixed | no | Artifact target for `vision.analyzeArtifact` |
| `contains`, `notContains` | string | no | Optional text expectation |
| `source` | string | no | Calling surface label |

```js
await daemonCall('vision.analyzeWindow', {
  app: 'Safari',
  instruction: 'Read the visible page heading',
  contains: 'Documentation'
})
```

CLI:

```bash
lattices capture window
lattices runs
lattices runs run_20260617-120000_a1b2c3
lattices terminals
lattices terminals --refresh
lattices computer prepare --text "# hello" --treatment stage
lattices call computer.windowState '{"app":"Finder","maxDepth":4}'
lattices call computer.pressKey '{"app":"Finder","key":"escape","treatment":"stage"}'
lattices call computer.hotkey '{"app":"Xcode","shortcut":"command+b","treatment":"stage"}'
lattices computer focus-window --wid 7258 --treatment present
lattices computer cursor --style marker --shape chevron --angle-deg -8 --label typing
lattices computer launch-app Scout
lattices computer scout --treatment present
lattices computer scout "Draft memo text" --execute
lattices computer type-window --app Scout --text "Draft memo text" --x-ratio .5 --y-ratio .86 --execute
lattices computer click --app Scout --x-ratio .5 --y-ratio .86 --execute
lattices cua click --app Scout --x-ratio .74 --y-ratio .95 --transport ax --ax-label Send --execute
lattices call computer.scroll '{"app":"Safari","direction":"down","amount":420,"treatment":"stage"}'
lattices call computer.drag '{"app":"Finder","fromXRatio":0.2,"fromYRatio":0.2,"toXRatio":0.7,"toYRatio":0.7,"treatment":"stage"}'
lattices call computer.doubleClick '{"app":"Finder","xRatio":0.5,"yRatio":0.5,"treatment":"stage"}'
lattices call computer.rightClick '{"app":"Finder","xRatio":0.5,"yRatio":0.5,"treatment":"stage"}'
lattices call computer.verify '{"app":"Safari","mode":"ocr","contains":"Docs"}'
lattices call capture.screenshotRegion '{"app":"Safari","filename":"safari-region.png"}'
lattices call vision.analyzeWindow '{"app":"Safari","instruction":"Read visible text"}'
lattices call browser.getText '{"app":"Safari"}'
lattices call browser.queryDom '{"app":"Safari","selector":"h1","allowAutomation":true}'
lattices computer type-text --text "# hello from lattices"
lattices computer demo-terminal --dry-run
```

---

#### Computer Action Treatments

Computer-use endpoints accept a `treatment` field that controls how intrusive
the action may be:

| Treatment | Behavior |
|-----------|----------|
| `observe` | Resolve target and record a run, without focus or input |
| `stage` | Resolve target and stage intent/artifacts, without focus or input |
| `present` | Focus or present the target, without input |
| `execute` | Perform the action after safety checks |

The legacy `dryRun: true` flag maps to `stage`.

#### `computer.prepare`

Resolve and score terminal candidates for a future computer-use action. This is
the least intrusive endpoint: by default it observes the target and captures an
artifact, but it does not focus or type.

**Params**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `wid` | uint32 | no | Specific terminal window id |
| `tty` | string | no | Specific terminal TTY |
| `app` | string | no | Preferred terminal app, such as `iTerm2` |
| `text` | string | no | Text to stage in the run trace |
| `treatment` | string | no | `observe`, `stage`, `present`, or `execute` |
| `capture` | bool | no | Capture target screenshot artifact. Defaults to `true` |
| `source` | string | no | Calling surface label |

```js
await daemonCall('computer.prepare', {
  text: '# review before typing',
  treatment: 'stage'
})
```

#### `computer.windowState`

Inspect a target window's Accessibility tree and return snapshot-local element
ids (`e1`, `e2`, ...), a flat `elements` list, and a compact `treeMarkdown`
view. `mode: "ax"` avoids Screen Recording. Use `mode: "both"` or
`capture: true` when you also want a screenshot artifact linked to a run. The
endpoint is classified as a write because those capture modes create run
artifacts.

**Params**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `wid` | uint32 | no | Target window id |
| `session` | string | no | Target lattices session |
| `app` | string | no | Target app name |
| `title` | string | no | Optional title substring for app target |
| `mode` | string | no | `ax` (default), `both`, or `screenshot` |
| `capture` | bool | no | Capture a screenshot artifact. Defaults true for `both`/`screenshot`, false for `ax` |
| `maxDepth` | int | no | Maximum AX tree depth. Defaults to `8`, max `14` |
| `maxElements` | int | no | Maximum elements returned. Defaults to `250`, max `1000` |
| `timeoutMs` | int | no | Traversal timeout. Defaults to `1200`, max `5000` |
| `source` | string | no | Calling surface label when capture creates a run |

```js
await daemonCall('computer.windowState', {
  app: 'Finder',
  maxDepth: 4,
  maxElements: 120
})

await daemonCall('computer.windowState', {
  wid: 7258,
  mode: 'both',
  source: 'agent'
})
```

#### `computer.elementAction`

Stage or execute an Accessibility action against an element returned by a recent
`computer.windowState` call. Snapshot element ids are intentionally local to the
daemon process and expire from the in-memory cache after a short window.

**Params**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `snapshotId` | string | yes | Snapshot id returned by `computer.windowState` |
| `elementId` | string | yes | Snapshot-local element id, such as `e4` |
| `action` | string | no | `press` (default), `showMenu`, or `focus` |
| `treatment` | string | no | `stage`, `present`, or `execute`. Defaults to `stage` |
| `dryRun` | bool | no | Stage without performing the action |
| `capture` | bool | no | Capture before/after artifacts. Defaults to `true` |
| `source` | string | no | Calling surface label |

```js
const state = await daemonCall('computer.windowState', {
  app: 'Calculator',
  maxDepth: 6
})

await daemonCall('computer.elementAction', {
  snapshotId: state.snapshotId,
  elementId: 'e7',
  action: 'press',
  treatment: 'execute'
})
```

#### `computer.typeElement` / `computer.setValue`

Stage or execute text/value insertion against an element returned by a recent
`computer.windowState` call. `computer.typeElement` accepts `text`;
`computer.setValue` accepts `value` and otherwise uses the same behavior. In
`stage`, Lattices records the intended value without changing the app.

**Params**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `snapshotId` | string | yes | Snapshot id returned by `computer.windowState` |
| `elementId` | string | yes | Snapshot-local element id, such as `e4` |
| `text` | string | yes for `typeElement` | Text to set or append |
| `value` | string | yes for `setValue` | Value to set or append |
| `append` | bool | no | Append to current `AXValue` instead of replacing it |
| `typeIntervalMs` | double | no | Per-character interval for typewriter-style AXValue updates |
| `treatment` | string | no | `stage`, `present`, or `execute`. Defaults to `stage` |
| `dryRun` | bool | no | Stage without setting `AXValue` |
| `capture` | bool | no | Capture before/after artifacts. Defaults to `true` |
| `source` | string | no | Calling surface label |

```js
const state = await daemonCall('computer.windowState', {
  app: 'Notes',
  maxDepth: 8
})

await daemonCall('computer.typeElement', {
  snapshotId: state.snapshotId,
  elementId: 'e12',
  text: 'Draft note',
  treatment: 'execute'
})
```

#### `computer.pressKey` / `computer.hotkey`

Stage or execute keyboard input. `computer.pressKey` sends one key, such as
`escape`, `enter`, `tab`, an arrow key, or a single character. `computer.hotkey`
sends a shortcut from either `shortcut: "command+shift+p"` or `key` plus
`modifiers`. Both default to `stage`; `execute` requires an explicit `wid`,
`app`, or `session` target unless `allowGlobal: true` is passed.

**Params**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `wid` | uint32 | no | Target window id |
| `session` | string | no | Target lattices session |
| `app` | string | no | Target app name |
| `title` | string | no | Optional title substring for app target |
| `key` | string | yes for `pressKey` | Key name or single character |
| `shortcut` | string | yes for `hotkey` without `key` | Shortcut shorthand, such as `command+shift+p` |
| `modifiers` | array/string | no | `command`, `option`, `control`, `shift` |
| `count` | int | no | Repeat count. Defaults to `1`, max `20` |
| `delayMs` | double | no | Delay between repeats. Defaults to `80` |
| `allowGlobal` | bool | no | Permit execute without target by posting to the focused system target |
| `treatment` | string | no | `stage`, `present`, or `execute` |
| `dryRun` | bool | no | Stage without posting keyboard input |
| `capture` | bool | no | Capture before/after artifacts when targeting a window |
| `source` | string | no | Calling surface label |

```js
await daemonCall('computer.pressKey', {
  app: 'Finder',
  key: 'escape',
  treatment: 'stage'
})

await daemonCall('computer.hotkey', {
  app: 'Xcode',
  shortcut: 'command+b',
  treatment: 'execute'
})
```

#### `computer.focusWindow`

Resolve a target window, optionally capture it, focus it, and verify the focused
window id. Use `treatment: 'observe'` or `stage` to plan without presenting.

**Params**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `wid` | uint32 | no | Target window id |
| `session` | string | no | Target lattices session |
| `app` | string | no | Target app name |
| `title` | string | no | Optional title substring for `app` |
| `treatment` | string | no | `observe`, `stage`, `present`, or `execute` |
| `dryRun` | bool | no | Stage without focusing |
| `capture` | bool | no | Capture before/after artifacts. Defaults to `true` |
| `source` | string | no | Calling surface label |

```js
await daemonCall('computer.focusWindow', {
  app: 'iTerm2',
  treatment: 'present'
})
```

#### `computer.showCursor`

Resolve the current cursor location and show a visible cursor appearance. This
is the cursor equivalent of a typing action: it records a run, cursor target,
appearance parameters, and trace events. Use `observe` or `stage` to plan
without showing anything.

**Params**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `x` | double | no | Screen x coordinate. Defaults to current cursor |
| `y` | double | no | Screen y coordinate. Defaults to current cursor |
| `treatment` | string | no | `observe`, `stage`, `present`, or `execute` |
| `style` | string | no | `spotlight`, `pulse`, or `marker` |
| `appearance` | string | no | Alias for `style` |
| `shape` | string | no | Marker shape: `chevron`, `facet`, `shard`, `wedge`, `prism`, or `notch` |
| `angleDeg` | double | no | Marker rotation in degrees. Positive rotates visually clockwise; default is `-8` for marker |
| `size` | string | no | Marker size: `small`, `regular`, or `large`. Defaults to Settings |
| `color` | string | no | `blue`, `green`, `amber`, `pink`, `red`, or `white` |
| `durationMs` | int | no | Appearance duration in milliseconds |
| `label` | string | no | Optional marker label |
| `dryRun` | bool | no | Stage without showing |
| `source` | string | no | Calling surface label |

```js
await daemonCall('computer.showCursor', {
  style: 'marker',
  shape: 'chevron',
  angleDeg: -8,
  size: 'regular',
  color: 'white',
  treatment: 'present'
})
```

#### `computer.launchApp`

Launch or focus a normal macOS app and record the result as a run. Use
`dryRun: true` or `treatment: 'stage'` to plan without launching.

**Params**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `app` | string | yes | App name, such as `Scout`, `Slack`, or `Notes` |
| `bundleId` | string | no | Bundle identifier fallback for precise launch |
| `path` | string | no | Explicit `.app` bundle path |
| `title` | string | no | Optional title substring for app window selection |
| `treatment` | string | no | `observe`, `stage`, `present`, or `execute` |
| `dryRun` | bool | no | Stage without launching |
| `capture` | bool | no | Capture the launched app window. Defaults to `true` outside dry-run |
| `source` | string | no | Calling surface label |

```js
await daemonCall('computer.launchApp', {
  app: 'Scout',
  treatment: 'present'
})
```

#### `computer.typeWindowText`

Focus a normal app window and insert text. If click coordinates are provided,
Lattices clicks that target before typing. Coordinates can be absolute screen
points (`x`, `y`) or ratios inside the target window (`xRatio`, `yRatio`).
For window ratios, `0,0` is the top-left of the window and `1,1` is the
bottom-right.

**Params**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `wid` | uint32 | no | Target window id |
| `app` | string | no | Target app name |
| `title` | string | no | Optional title substring for app target |
| `text` | string | yes | Text to insert |
| `enter` | bool | no | Press Enter after typing. Defaults to `false` |
| `send` | bool | no | Alias for `enter` in chat-style demos |
| `x`, `y` | double | no | Absolute click point before typing |
| `xRatio`, `yRatio` | double | no | Window-relative click point before typing |
| `treatment` | string | no | `observe`, `stage`, `present`, or `execute` |
| `dryRun` | bool | no | Stage without typing |
| `capture` | bool | no | Capture before/after artifacts. Defaults to `true` |
| `source` | string | no | Calling surface label |

```js
await daemonCall('computer.typeWindowText', {
  app: 'Scout',
  text: 'Draft memo text',
  xRatio: 0.5,
  yRatio: 0.86,
  treatment: 'execute'
})
```

#### `computer.click` / `computer.doubleClick` / `computer.rightClick`

Stage or execute a click target. `stage` records the target without clicking.
In `execute`, `transport: "auto"` prefers `AXPress` on the resolved accessibility
button/control before falling back to a pointer click. Use `transport: "ax"` or
`noFocus: true` when the action must not focus the app or move the hardware
pointer. `computer.doubleClick` forces two pointer clicks; `computer.rightClick`
forces the right button. When a window target is provided, ratios are relative to
that window.

**Params**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `wid` | uint32 | no | Target window id |
| `session` | string | no | Target lattices session |
| `app` | string | no | Target app name |
| `title` | string | no | Optional title substring for app target |
| `x`, `y` | double | no | Absolute click point |
| `xRatio`, `yRatio` | double | no | Window-relative click point |
| `button` | string | no | `left` or `right`; defaults to `left` |
| `count` | int | no | Pointer click count. Defaults to `1`, max `8` |
| `delayMs` | double | no | Delay between repeated pointer clicks |
| `transport` | string | no | `auto`, `ax`, or `pointer`; defaults to `auto` |
| `axLabel` | string | no | Optional AX text/title hint, such as `Send` |
| `noFocus` | bool | no | Require no-focus AX execution; disable pointer fallback |
| `treatment` | string | no | `stage`, `present`, or `execute` |
| `dryRun` | bool | no | Stage without clicking |
| `capture` | bool | no | Capture before/after artifacts when targeting a window |
| `source` | string | no | Calling surface label |

```js
await daemonCall('computer.click', {
  app: 'Scout',
  xRatio: 0.5,
  yRatio: 0.86,
  treatment: 'execute'
})

await daemonCall('computer.click', {
  app: 'Scout',
  xRatio: 0.74,
  yRatio: 0.95,
  transport: 'ax',
  axLabel: 'Send',
  noFocus: true,
  treatment: 'execute'
})
```

#### `computer.scroll` / `computer.drag`

Stage or execute richer pointer input while keeping the same run/capture model.
`computer.scroll` posts scroll wheel events at an absolute or window-relative
point. `computer.drag` interpolates a pointer drag from a start point to an end
point. Both default to `stage`.

**Scroll params**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `wid`, `session`, `app`, `title` | target | no | Target window/session/app |
| `x`, `y` | double | no | Absolute pointer point before scrolling |
| `xRatio`, `yRatio` | double | no | Window-relative pointer point |
| `direction` | string | no | `down` (default), `up`, `left`, or `right` |
| `amount` | double | no | Scroll amount when using `direction`; default `420` |
| `deltaX`, `deltaY` | double | no | Explicit scroll wheel deltas |
| `count` | int | no | Number of scroll events; default `1`, max `30` |
| `delayMs` | double | no | Delay between repeated events |
| `treatment`, `dryRun`, `capture`, `source` | mixed | no | Standard computer action fields |

**Drag params**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `wid`, `session`, `app`, `title` | target | no | Target window/session/app |
| `fromX`, `fromY` | double | no | Absolute drag start point |
| `toX`, `toY` | double | no | Absolute drag end point |
| `fromXRatio`, `fromYRatio` | double | no | Window-relative drag start point |
| `toXRatio`, `toYRatio` | double | no | Window-relative drag end point |
| `x`, `y`, `xRatio`, `yRatio` | double | no | Aliases for the drag end point |
| `button` | string | no | `left` or `right`; defaults to `left` |
| `durationMs` | double | no | Drag duration; default `360` |
| `steps` | int | no | Interpolated drag event count; default `18` |
| `treatment`, `dryRun`, `capture`, `source` | mixed | no | Standard computer action fields |

```js
await daemonCall('computer.scroll', {
  app: 'Safari',
  direction: 'down',
  amount: 420,
  treatment: 'execute'
})

await daemonCall('computer.drag', {
  app: 'Finder',
  fromXRatio: 0.2,
  fromYRatio: 0.2,
  toXRatio: 0.7,
  toYRatio: 0.7,
  treatment: 'stage'
})
```

#### `computer.verify`

Verify a post-action outcome using OCR, AX snapshot text/value, or artifact hash
comparison. OCR verification captures/analyzes the target when needed. AX
verification can use a `snapshotId`/`elementId` from `computer.windowState`.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `mode` | string | no | `ocr` (default), `ax`, or `artifactChanged` |
| `wid`, `session`, `app`, `title` | target | no | Window target |
| `snapshotId`, `elementId` | string | no | AX snapshot/element target |
| `runId`, `artifactId`, `path` | mixed | no | Image artifact target for OCR verification |
| `contains`, `expected` | string | no | Text that should be present |
| `notContains` | string | no | Text that should be absent |
| `beforeArtifactId`, `afterArtifactId` | string | no | Artifact ids for `artifactChanged` |
| `beforePath`, `afterPath` | string | no | Path fallback for `artifactChanged` |
| `source` | string | no | Calling surface label |

```js
await daemonCall('computer.verify', {
  app: 'Safari',
  mode: 'ocr',
  contains: 'Lattices'
})

const state = await daemonCall('computer.windowState', { app: 'Notes' })
await daemonCall('computer.verify', {
  mode: 'ax',
  snapshotId: state.snapshotId,
  elementId: 'e4',
  contains: 'Draft'
})
```

#### `browser.getText` / `browser.queryDom` / `browser.executeJavascript`

Browser primitives are intentionally gated. `browser.getText` reads visible text
through Accessibility and does not enable JavaScript automation. DOM querying
and arbitrary JavaScript use AppleScript browser automation and require
`allowAutomation: true`; JavaScript mutation also requires
`treatment: "execute"`.

Supported browser app names: `Safari`, `Google Chrome`, `Chrome`, `Brave
Browser`, `Microsoft Edge`, and `Arc`.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `wid`, `app`, `title` | target | no | Browser target |
| `selector` | string | yes for `queryDom` | CSS selector |
| `limit` | int | no | Max DOM nodes, default `20`, max `200` |
| `script` | string | yes for `executeJavascript` | JavaScript source |
| `allowAutomation` | bool | yes for DOM/execute | Explicit browser automation consent |
| `treatment` | string | no | `stage` (default) or `execute` for JavaScript |
| `source` | string | no | Calling surface label |

```js
await daemonCall('browser.getText', { app: 'Safari' })

await daemonCall('browser.queryDom', {
  app: 'Safari',
  selector: 'h1, main a',
  allowAutomation: true
})

await daemonCall('browser.executeJavascript', {
  app: 'Safari',
  script: 'document.title',
  treatment: 'execute',
  allowAutomation: true
})
```

#### `computer.demoScout`

Warm up a Scout memo/demo recording run. In `present` mode it launches or
focuses Scout and records a run without typing. In `execute` mode it can click
the likely composer area, type a draft, and optionally press Enter when
`enter` or `send` is true. Dry-run/stage mode does not capture by default, so it
works before Screen Recording permission is granted.

**Params**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `app` | string | no | Scout app name override. Defaults to `Scout` |
| `title` | string | no | Optional title substring for the Scout window |
| `text` | string | no | Draft text to type in `execute` mode |
| `enter` | bool | no | Press Enter after typing. Defaults to `false` |
| `send` | bool | no | Alias for `enter` |
| `click` | bool | no | Click the likely composer area before typing |
| `xRatio`, `yRatio` | double | no | Composer click point; defaults to `0.5`, `0.86` |
| `treatment` | string | no | `observe`, `stage`, `present`, or `execute` |
| `dryRun` | bool | no | Stage without launching or typing |
| `capture` | bool | no | Capture before/after artifacts. Defaults to `true` outside dry-run |
| `source` | string | no | Calling surface label |

```js
await daemonCall('computer.demoScout', { dryRun: true })

await daemonCall('computer.demoScout', {
  treatment: 'present',
  capture: false
})

await daemonCall('computer.demoScout', {
  text: 'Draft memo text',
  treatment: 'execute',
  send: false
})
```

#### `computer.typeText`

Resolve a terminal target and insert text after safety checks. Lattices prefers
the least intrusive available transport: tmux pane input when a tmux pane is
known, then target-pid key events/pasteboard insertion when window focus is
required. Enter is never pressed unless `enter: true` is provided.

**Params**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `wid` | uint32 | no | Specific terminal window id |
| `tty` | string | no | Specific terminal TTY |
| `app` | string | no | Preferred terminal app, such as `iTerm2` |
| `text` | string | yes | Text to insert |
| `enter` | bool | no | Press Enter after typing. Defaults to `false` |
| `treatment` | string | no | `observe`, `stage`, `present`, or `execute` |
| `transport` | string | no | `auto`, `tmux`, or `pasteboard`. Defaults to `auto` |
| `dryRun` | bool | no | Stage without typing |
| `capture` | bool | no | Capture before/after artifacts. Defaults to `true` |
| `source` | string | no | Calling surface label |

```js
await daemonCall('computer.typeText', {
  text: '# hello from lattices',
  transport: 'auto',
  enter: false
})
```

#### `computer.demoTerminal`

Compatibility endpoint for the original terminal demo. It follows the same
treatment, safety, capture, and transport rules as `computer.typeText`, but
provides a default text payload when `text` is omitted.

Run a bounded computer-use sequence against a terminal window:

1. synthesize and score terminal candidates
2. choose a safe shell-like terminal unless `wid` or `tty` is supplied
3. capture a `before` screenshot artifact
4. focus the terminal window
5. insert text without pressing Enter by default
6. capture an `after` screenshot artifact

**Params**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `wid` | uint32 | no | Specific terminal window id |
| `tty` | string | no | Specific terminal TTY |
| `app` | string | no | Preferred terminal app, such as `iTerm2` |
| `text` | string | no | Text to insert |
| `enter` | bool | no | Press Enter after typing. Defaults to `false` |
| `treatment` | string | no | `observe`, `stage`, `present`, or `execute` |
| `transport` | string | no | `auto`, `tmux`, or `pasteboard`. Defaults to `auto` |
| `dryRun` | bool | no | Plan and capture without typing |
| `capture` | bool | no | Capture before/after artifacts. Defaults to `true` |
| `source` | string | no | Calling surface label |

```js
await daemonCall('computer.demoTerminal', { dryRun: true })

await daemonCall('computer.demoTerminal', {
  app: 'iTerm2',
  text: '# hello from lattices',
  enter: false
})
```

---

## Overlay UI

The macOS app exposes a shared desktop overlay canvas for lightweight
agent-visible UI. Use `overlay.publish` for transient passive visuals,
and `overlay.actor.*` for persistent, movable actor surfaces.

Persistent actors are useful for representing agents or processes on the
desktop. Each actor has a stable `id`, can be moved independently through the
API, dragged by the user, hidden/restored with **Hyper+B**, and closed with
right-click. Click event callbacks and action surfaces are planned follow-on
capabilities.

| Method | Type | Description |
|--------|------|-------------|
| `overlay.publish` | write | Publish a transient toast, label, highlight, or pet layer |
| `overlay.clear` | write | Clear one overlay layer by id, or clear an owner namespace |
| `overlay.actor.publish` | write | Create or update a persistent generative overlay actor |
| `overlay.actor.moveTo` | write | Move an actor with app-owned easing |
| `overlay.actor.hud` | write | Attach, update, or clear a hover web HUD for an actor |
| `overlay.actor.visibility` | write | Show, hide, toggle, or inspect the sticky actor layer |

#### `overlay.publish`

Publish a transient layer on the screen overlay canvas.

**Params**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `kind` | string | yes | `toast`, `label`, `highlight`, or `pet` |
| `id` | string | no | Stable layer id; generated if omitted |
| `text` | string | no | Toast/label text or pet message fallback |
| `detail` | string | no | Secondary toast/label text |
| `message` | string | no | Pet message |
| `petId` | string | no | Bundled pet id from `apps/mac/Resources/Pets` |
| `state` | string | no | Pet animation state |
| `placement` | string | no | `top`, `bottom`, `center`, `cursor`, or `point` |
| `x`, `y` | double | no | Screen-local point for `point` placement |
| `w`, `h` | double | no | Highlight size |
| `ttlMs` | int | no | Time to live in milliseconds |
| `dismissible` | bool | no | Whether click-away dismissal removes the layer; defaults `true` |

Example:

```js
await daemonCall('overlay.publish', {
  kind: 'highlight',
  x: 160,
  y: 120,
  w: 480,
  h: 260,
  text: 'Needs review',
  style: 'warning',
  ttlMs: 3000
})
```

#### `overlay.actor.publish`

Create or update a generative overlay actor. Actors default to persistent:
omit `ttlMs` or pass `0`, and `dismissible` defaults to `false`.

**Params**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | no | Stable actor id; generated if omitted |
| `renderer` | string | no | `sprite` is currently supported |
| `asset` | string | no | Bundled sprite asset id, such as `scout-ranger` |
| `state` | string | no | Actor state or animation name |
| `name` | string | no | Actor display name |
| `message` | string | no | Attached message text |
| `targetApp` | string | no | App name to activate when the actor is clicked |
| `targetBundleId` | string | no | Bundle identifier to activate when the actor is clicked |
| `targetAppPath` | string | no | `.app` bundle path to open when the actor is clicked |
| `scale` | double | no | Actor scale multiplier |
| `labelHidden` | bool | no | Hide the actor label/message |
| `closeOnActivate` | bool | no | Remove the actor after activating its target app |
| `hudUrl` | string | no | URL to render in a transparent hover HUD web view |
| `hudHTML` | string | no | Inline HTML to render in a transparent hover HUD web view |
| `hudWidth` | double | no | Hover HUD width |
| `hudHeight` | double | no | Hover HUD height |
| `hudReadAccess` | string | no | Local folder a file-backed HUD may read |
| `placement` | string | no | `top`, `bottom`, `center`, `cursor`, or `point` |
| `x`, `y` | double | no | Screen-local point for `point` placement |
| `ttlMs` | int | no | Time to live; `0` means persistent |
| `dismissible` | bool | no | Whether click-away dismissal removes the actor |

Bundled sprite assets:

| Asset | Notes |
|-------|-------|
| `assistant-spark` | Animated states include `idle`, `run_right`, `run_left`, `waving`, `jumping`, `failed`, `waiting`, `running`, and `review` |
| `scout-ranger` | Bundled sprite asset with default frame fallback |

Example:

```js
await daemonCall('overlay.actor.publish', {
  id: 'agent-scout',
  renderer: 'sprite',
  asset: 'scout-ranger',
  state: 'waiting',
  name: 'Scout',
  message: 'Waiting for feedback',
  placement: 'point',
  x: 640,
  y: 320,
  ttlMs: 0
})
```

#### `overlay.actor.moveTo`

Move an actor with app-owned animation. The app interpolates position and
switches directional sprite states while moving.

**Params**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | yes | Actor id |
| `x`, `y` | double | yes | Target screen-local point |
| `durationMs` | int | no | Animation duration |
| `easing` | string | no | `linear`, `easeInOut`, or `spring` |

Example:

```js
await daemonCall('overlay.actor.moveTo', {
  id: 'agent-scout',
  x: 820,
  y: 280,
  durationMs: 800,
  easing: 'spring'
})
```

#### `overlay.actor.hud`

Attach a transparent, blurred hover HUD to an actor. The HUD is backed by a
native `WKWebView`, so apps can point it at a local static HTML dashboard or,
in development, a local URL.

**Params**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | yes | Actor id |
| `hudUrl` | string | no | URL or file path to render |
| `hudHTML` | string | no | Inline HTML to render instead of a URL |
| `hudTitle` | string | no | HUD title metadata |
| `hudWidth` | double | no | HUD width |
| `hudHeight` | double | no | HUD height |
| `hudReadAccess` | string | no | Local folder a file-backed HUD may read |
| `clear` | bool | no | Remove the actor HUD |

Example:

```js
await daemonCall('overlay.actor.hud', {
  id: 'switch-talkie',
  hudUrl: '/Users/you/dev/talkie/.lattices/hud/index.html',
  hudReadAccess: '/Users/you/Library/Application Support/Talkie/HUD',
  hudWidth: 380,
  hudHeight: 260
})
```

#### `overlay.actor.visibility`

Show, hide, toggle, or inspect the persistent actor layer without destroying
the actors. This is the daemon equivalent of the app's **Hyper+B** shortcut.

**Params**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `action` | string | no | `show`, `hide`, `toggle`, or `status` |
| `visible` | bool | no | Set layer visibility directly |
| `hidden` | bool | no | Set layer hidden state directly |
| `feedback` | bool | no | Show a short desktop feedback toast |

Example:

```js
await daemonCall('overlay.actor.visibility', { action: 'toggle' })
```

### Static HUD Manifests

Apps and projects can expose a local hover dashboard without running a web
server by publishing a static bundle at:

```txt
.lattices/hud/
  manifest.json
  index.html
  assets/
```

Minimal manifest:

```json
{
  "version": 1,
  "id": "talkie",
  "name": "Talkie",
  "bundleId": "com.usabletalkie.Talkie",
  "icon": "./assets/icon.png",
  "entry": "./index.html",
  "readAccess": "~/Library/Application Support/Talkie/HUD",
  "surface": { "width": 380, "height": 260 },
  "actor": {
    "labelHidden": true,
    "click": "activateApp"
  },
  "sources": [
    {
      "path": "~/Library/Application Support/Talkie/HUD/activity.jsonl",
      "format": "jsonl",
      "schema": "talkie.activity.v1",
      "presentation": "timeline"
    }
  ]
}
```

The CLI resolves this manifest into `overlay.actor.publish` with a file-backed
HUD URL. The macOS app loads `entry` through `WKWebView.loadFileURL`, allowing
read access to the HUD folder by default, or to the manifest's `readAccess`
folder when one is declared.

`sources` is descriptive metadata for app-owned state, logs, or event streams.
Lattices does not append to those logs. The app writes them in its normal
runtime location, and the custom HUD renderer decides how to present them.

Useful commands:

```bash
lattices hud register .lattices/hud/manifest.json --publish
lattices hud publish talkie
lattices hud sync
lattices hud discover ~/dev --register
```

For packaged apps, keep the renderer files in the app bundle and point mutable
sources at an app-owned folder such as `~/Library/Application Support/...`.

---

## System

| Method | Type | Description |
|--------|------|-------------|
| `deck.manifest` | read | Shared companion deck manifest |
| `deck.snapshot` | read | Current companion deck runtime snapshot |
| `deck.perform` | write | Perform a companion deck action |
| `daemon.status` | read | Health check and stats |
| `api.schema` | read | Full API schema for self-discovery |
| `diagnostics.list` | read | Recent diagnostic entries |

#### `deck.manifest`

Return the shared `DeckKit` manifest exposed by the macOS app. This is
the contract a future Lattices companion can consume to discover pages,
capabilities, and security mode.

**Params**: none

#### `deck.snapshot`

Return the current `DeckKit` runtime snapshot for the macOS host.

**Params**: none

**Returns**: a `DeckRuntimeSnapshot` object containing:

- `voice`
- `desktop`
- `switcher`
- `history`
- `questions`

#### `deck.perform`

Perform a `DeckKit` action against the running macOS host and return a
`DeckActionResult`.

**Params**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `pageID` | string | no | Deck page ID |
| `actionID` | string | yes | Deck action identifier |
| `payload` | object | no | Deck action payload |

Example:

```json
{
  "id": "1",
  "method": "deck.perform",
  "params": {
    "pageID": "layout",
    "actionID": "layout.optimize",
    "payload": {
      "strategy": "balanced",
      "region": "right"
    }
  }
}
```

#### `daemon.status`

Health check and basic stats.

**Params**: none

**Returns**:

```json
{
  "uptime": 3600.5,
  "clientCount": 2,
  "version": "1.0.0",
  "windowCount": 12,
  "tmuxSessionCount": 3
}
```

#### `api.schema`

Return the full API schema including version, models, and method definitions.
Useful for agent self-discovery.

**Params**: none

CLI shortcut:

```bash
lattices call api.schema
```

#### `diagnostics.list`

Return recent diagnostic log entries from the daemon.

**Params**:

| Field   | Type   | Required | Description                    |
|---------|--------|----------|--------------------------------|
| `limit` | number | no       | Max entries to return (default 50) |

---

## Mouse & Input

| Method | Type | Description |
|--------|------|-------------|
| `mouse.find` | read | Show a sonar pulse at the current cursor |
| `mouse.summon` | write | Move the cursor to a point or screen center |
| `mouse.shortcuts.get` | read | Return the live mouse shortcut config |
| `mouse.shortcuts.reload` | write | Reload `~/.lattices/mouse-shortcuts.json` without restarting |
| `mouse.shortcuts.set` | write | Replace the full mouse shortcut config and activate it |
| `mouse.shortcuts.upsert` | write | Create or replace one mouse shortcut rule and activate it |
| `mouse.shortcuts.remove` | write | Remove one mouse shortcut rule and activate the new config |
| `mouse.shortcuts.restoreDefaults` | write | Restore default mouse shortcuts |

Mouse shortcut rules are data. Prefer `shortcut.send` for hotkeys an agent can
define or change directly; do not add a named action unless the behavior cannot
be expressed as data.

Create or replace a gesture that sends Hyper+D:

```js
await daemonCall('mouse.shortcuts.upsert', {
  rule: {
    id: 'middle-up-voice',
    enabled: true,
    device: 'any',
    trigger: { button: 'middle', kind: 'drag', direction: 'up' },
    action: {
      type: 'shortcut.send',
      shortcut: {
        key: 'd',
        keyCode: 2,
        modifiers: ['control', 'option', 'shift', 'command']
      }
    }
  }
})
```

If an agent edits `~/.lattices/mouse-shortcuts.json` itself, refresh the running
app explicitly:

```js
await daemonCall('mouse.shortcuts.reload')
```

All write methods persist the config, checkpoint the previous version in
`~/.lattices/mouse-shortcuts.history/`, and update the active event-tap snapshot
immediately. No app restart is required.

Supported action types:

| Type | Purpose |
|------|---------|
| `shortcut.send` | Send a data-defined key or keyCode with modifiers |
| `app.activate` | Activate an app by name |
| `space.previous` | Switch to the previous macOS Space |
| `space.next` | Switch to the next macOS Space |
| `screenmap.toggle` | Open the Screen Map overview |
| `dictation.start` | Legacy alias that presses the configured Voice Command hotkey |

---

## Windows & Spaces

| Method | Type | Description |
|--------|------|-------------|
| `windows.list` | read | All visible windows |
| `windows.get` | read | Single window by ID |
| `windows.search` | read | Search windows by query |
| `spaces.list` | read | macOS display spaces |
| `window.place` | write | Place a window or session using a typed placement spec |
| `window.tile` | write | Compatibility wrapper for session tiling |
| `window.focus` | write | Focus a window / switch Spaces |
| `window.move` | write | Move a window to another Space |
| `window.assignLayer` | write | Tag a window to a layer |
| `window.removeLayer` | write | Remove a window's layer tag |
| `window.layerMap` | read | All window→layer assignments |
| `space.optimize` | write | Optimize a set of windows using an explicit scope and strategy |
| `layout.distribute` | write | Compatibility wrapper for visible-window balancing |

#### `windows.list`

List all visible windows tracked by the desktop model.

**Params**: none

**Returns**: array of window objects:

```json
[
  {
    "wid": 1234,
    "app": "Terminal",
    "pid": 5678,
    "title": "[lattices:myapp-a1b2c3] zsh",
    "frame": { "x": 0, "y": 25, "w": 960, "h": 1050 },
    "spaceIds": [1],
    "isOnScreen": true,
    "latticesSession": "myapp-a1b2c3",
    "layerTag": "web"
  }
]
```

The `latticesSession` field is present only on windows that belong to
a lattices session (matched via the `[lattices:name]` title tag).

The `layerTag` field is present when a window has been manually assigned
to a layer via `window.assignLayer`.

#### `windows.get`

Get a single window by its CGWindowID.

**Params**:

| Field | Type   | Required | Description       |
|-------|--------|----------|-------------------|
| `wid` | number | yes      | CGWindowID        |

**Returns**: a single window object (same shape as `windows.list` items).
**Errors**: `Not found` if the window ID doesn't exist.

#### `windows.search`

Search windows by text query across title, app name, session tags, and OCR content. Returns results with `matchSource` indicating how the match was found, and `ocrSnippet` for OCR matches.

**Params**:

| Field   | Type   | Required | Description                    |
|---------|--------|----------|--------------------------------|
| `query` | string | yes      | Search query (matches title, app, session, OCR text) |
| `ocr`   | boolean| no       | Include OCR text in search (default true) |
| `limit` | number | no       | Max results (default 50)       |

**Returns**: array of window objects with additional search fields:

```json
[
  {
    "wid": 265,
    "app": "iTerm2",
    "title": "✳ Claude Code",
    "matchSource": "ocr",
    "ocrSnippet": "…~/dev/vox StatusBarIconFolder…",
    "frame": { "x": 688, "y": 3, "w": 1720, "h": 720 },
    "isOnScreen": true
  }
]
```

`matchSource` values: `"title"`, `"app"`, `"session"`, `"ocr"`.

**CLI usage**:

```bash
# Basic search (uses windows.search)
lattices search vox

# Deep search — adds terminal tab/process inspection for ranking
lattices search vox --deep

# Same as --deep (all search sources)
lattices search vox --all

# Pipeable output
lattices search vox --wid
lattices search vox --json

# Search + focus + tile in one step
lattices place vox right
```

#### `spaces.list`

List macOS display spaces (virtual desktops).

**Params**: none

**Returns**: array of display objects:

```json
[
  {
    "displayIndex": 0,
    "displayId": "main",
    "currentSpaceId": 1,
    "spaces": [
      { "id": 1, "index": 0, "display": 0, "isCurrent": true },
      { "id": 2, "index": 1, "display": 0, "isCurrent": false }
    ]
  }
]
```

#### `window.place`

Canonical window placement mutation. Use this when an agent needs a
single, typed placement contract across voice, CLI, and daemon clients.

**Params**:

| Field       | Type            | Required | Description                              |
|-------------|-----------------|----------|------------------------------------------|
| `wid`       | number          | no       | Target window ID                          |
| `session`   | string          | no       | Target lattices session                   |
| `app`       | string          | no       | Target app name                           |
| `title`     | string          | no       | Optional title substring for app matching |
| `display`   | number          | no       | Target display index                      |
| `placement` | string \| object | yes     | Placement shorthand or typed object       |

Target resolution priority is `wid` → `session` → `app/title` → frontmost window.

**Placement strings**: `left`, `right`, `top`, `bottom`, `top-left`, `top-right`,
`bottom-left`, `bottom-right`, `left-third`, `center-third`, `right-third`,
`top-third`, `middle-third`, `bottom-third`, `left-quarter`, `right-quarter`,
`top-quarter`, `bottom-quarter`, `maximize`, `center`, `grid:CxR:C,R`, or
compact `CxR:C,R`. The canonical `grid:` form is 0-indexed; the compact form is
1-indexed for command entry.

**Typed placement examples**:

```json
{ "kind": "tile", "value": "top-right" }
{ "kind": "grid", "columns": 3, "rows": 2, "column": 2, "row": 0 }
{ "kind": "fractions", "x": 0.5, "y": 0, "w": 0.5, "h": 1 }
```

**Returns**: execution receipt including resolved target, placement, and trace.

#### `window.tile`

Compatibility wrapper for `window.place` when the target is a lattices
session window.

**Params**:

| Field      | Type   | Required | Description                             |
|------------|--------|----------|-----------------------------------------|
| `session`  | string | yes      | Session name                            |
| `position` | string | yes      | Placement shorthand or grid syntax      |

This method exists for compatibility. New integrations should prefer
`window.place`.

#### `window.focus`

Focus a window — bring it to front and switch Spaces if needed.

**Params** (one of):

| Field     | Type   | Required | Description                     |
|-----------|--------|----------|---------------------------------|
| `wid`     | number | no       | CGWindowID (any window)         |
| `session` | string | no       | Session name (lattices windows)  |

Provide either `wid` or `session`. If `wid` is given, it takes priority.

#### `window.move`

Move a session's window to a different macOS Space.

**Params**:

| Field     | Type   | Required | Description                |
|-----------|--------|----------|----------------------------|
| `session` | string | yes      | Session name               |
| `spaceId` | number | yes      | Target Space ID (from `spaces.list`) |

#### `window.assignLayer`

Manually tag a window to a layer. Tagged windows are raised and tiled
when that layer activates, even if they aren't declared in `workspace.json`.

**Params**:

| Field   | Type   | Required | Description                    |
|---------|--------|----------|--------------------------------|
| `wid`   | number | yes      | CGWindowID                     |
| `layer` | string | yes      | Layer ID to assign             |

#### `window.removeLayer`

Remove a window's layer tag.

**Params**:

| Field | Type   | Required | Description    |
|-------|--------|----------|----------------|
| `wid` | number | yes      | CGWindowID     |

#### `window.layerMap`

Return all current window→layer assignments.

**Params**: none

**Returns**:

```json
{
  "1234": "web",
  "5678": "mobile"
}
```

Keys are CGWindowIDs (as strings), values are layer IDs.

#### `space.optimize`

Canonical space-balancing mutation. Use this when the goal is to make
the current workspace coherent rather than placing one specific window.

**Params**:

| Field       | Type     | Required | Description                                         |
|-------------|----------|----------|-----------------------------------------------------|
| `scope`     | string   | no       | `visible`, `active-app`, `app`, or `selection`      |
| `strategy`  | string   | no       | `balanced` or `mosaic`                              |
| `app`       | string   | no       | App name for `app` scope                            |
| `title`     | string   | no       | Optional title substring for app matching           |
| `windowIds` | number[] | no       | Explicit window IDs for `selection` scope           |

If `windowIds` is provided, scope is inferred as `selection`.
If `app` is provided and `scope` is omitted, scope is inferred as `app`.

**Returns**: execution receipt including resolved scope, strategy,
affected window IDs, and trace.

#### `layout.distribute`

Compatibility wrapper for `space.optimize` with `scope=visible` and
`strategy=balanced`.

**Params**: none

---

## Sessions

| Method | Type | Description |
|--------|------|-------------|
| `tmux.sessions` | read | Lattices tmux sessions |
| `tmux.inventory` | read | All sessions including orphans |
| `session.launch` | write | Launch a project session |
| `session.kill` | write | Kill a session |
| `session.detach` | write | Detach clients from a session |
| `session.sync` | write | Reconcile session to config |
| `session.restart` | write | Restart a pane's process |

All session methods require tmux to be installed.

#### `tmux.sessions`

List tmux sessions that belong to lattices.

**Params**: none

**Returns**: array of session objects:

```json
[
  {
    "name": "myapp-a1b2c3",
    "windowCount": 1,
    "attached": true,
    "panes": [
      {
        "id": "%0",
        "windowIndex": 0,
        "windowName": "main",
        "title": "claude",
        "currentCommand": "claude",
        "pid": 9876,
        "isActive": true
      }
    ]
  }
]
```

#### `tmux.inventory`

List all tmux sessions including orphans (sessions not tracked by lattices).

**Params**: none

**Returns**:

```json
{
  "all": [ ... ],
  "orphans": [ ... ]
}
```

Both arrays contain session objects (same shape as `tmux.sessions`).

#### `session.launch`

Launch a new tmux session for a project. If a session already exists,
it will be reattached. The project must be in the scanned project list —
call `projects.list` to check, or `projects.scan` to refresh.

**Params**:

| Field  | Type   | Required | Description                      |
|--------|--------|----------|----------------------------------|
| `path` | string | yes      | Absolute path to project directory |

**Returns**: `{ "ok": true }`
**Errors**: `Not found` if the path isn't in the scanned project list.

#### `session.kill`

Kill a tmux session by name.

**Params**:

| Field  | Type   | Required | Description         |
|--------|--------|----------|---------------------|
| `name` | string | yes      | Session name        |

#### `session.detach`

Detach all clients from a session (keeps it running).

**Params**:

| Field  | Type   | Required | Description         |
|--------|--------|----------|---------------------|
| `name` | string | yes      | Session name        |

#### `session.sync`

Reconcile a running session to match its declared `.lattices.json` config.
Recreates missing panes, re-applies layout, restores labels, re-runs
commands in idle panes.

**Params**:

| Field  | Type   | Required | Description                      |
|--------|--------|----------|----------------------------------|
| `path` | string | yes      | Absolute path to project directory |

**Errors**: `Not found` if the path isn't in the project list.

#### `session.restart`

Restart a specific pane's process within a session.

**Params**:

| Field  | Type   | Required | Description                      |
|--------|--------|----------|----------------------------------|
| `path` | string | yes      | Absolute path to project directory |
| `pane` | string | no       | Pane name to restart (defaults to first pane) |

---

## Projects & Layers

| Method | Type | Description |
|--------|------|-------------|
| `projects.list` | read | Discovered projects |
| `projects.scan` | write | Re-scan project directory |
| `layers.list` | read | Workspace layers and active index |
| `layer.activate` | write | Activate a workspace layer using an explicit mode |
| `layer.switch` | write | Compatibility wrapper for launch-style layer activation |
| `group.launch` | write | Launch a tab group |
| `group.kill` | write | Kill a tab group |

#### `projects.list`

List all discovered projects.

**Params**: none

**Returns**: array of project objects:

```json
[
  {
    "path": "/Users/you/dev/myapp",
    "name": "myapp",
    "sessionName": "myapp-a1b2c3",
    "isRunning": true,
    "hasConfig": true,
    "paneCount": 2,
    "paneNames": ["claude", "server"],
    "devCommand": "pnpm dev",
    "packageManager": "pnpm"
  }
]
```

`devCommand` and `packageManager` are present only when detected.

#### `projects.scan`

Trigger a re-scan of the project directory. Useful after cloning a new
repo or adding a `.lattices.json` config.

**Params**: none

#### `layers.list`

List configured workspace layers and the active index.

**Params**: none

**Returns**:

```json
{
  "layers": [
    { "id": "web", "label": "Web", "index": 0, "projectCount": 2 },
    { "id": "mobile", "label": "Mobile", "index": 1, "projectCount": 2 }
  ],
  "active": 0
}
```

Returns empty `layers` array if no workspace config is loaded.

#### `layer.activate`

Canonical layer mutation. Use this when an agent wants an explicit
activation mode instead of implicit "switch" behavior.

**Params**:

| Field   | Type   | Required | Description                                 |
|---------|--------|----------|---------------------------------------------|
| `index` | number | no       | Layer index (0-based)                       |
| `name`  | string | no       | Layer ID or label                           |
| `mode`  | string | no       | `launch`, `focus`, or `retile`              |

Provide either `index` or `name`.

**Modes**:

- `launch` — bring up the layer, launching missing projects and retiling
- `focus` — raise the layer's windows in place
- `retile` — re-apply the layer layout without launch semantics

**Returns**: execution receipt including resolved layer, mode, and trace.

#### `layer.switch`

Compatibility wrapper for `layer.activate` with `mode=launch`.
It keeps the old semantics and still posts a `layer.switched` event.

#### `group.launch`

Launch a tab group session.

**Params**:

| Field | Type   | Required | Description      |
|-------|--------|----------|------------------|
| `id`  | string | yes      | Group ID         |

**Errors**: `Not found` if the group ID doesn't match any configured group.

#### `group.kill`

Kill a tab group session.

**Params**:

| Field | Type   | Required | Description      |
|-------|--------|----------|------------------|
| `id`  | string | yes      | Group ID         |

---

## Processes & Terminals

| Method | Type | Description |
|--------|------|-------------|
| `processes.list` | read | Running developer processes |
| `processes.tree` | read | Process tree from a PID |
| `terminals.list` | read | Terminal instances with processes |
| `terminals.search` | read | Search terminals by criteria |

#### `processes.list`

List running processes relevant to development (editors, servers, build tools).

**Params**:

| Field     | Type   | Required | Description                        |
|-----------|--------|----------|------------------------------------|
| `command` | string | no       | Filter by command name substring   |

**Returns**: array of process objects:

```json
[
  {
    "pid": 1234,
    "ppid": 567,
    "command": "node",
    "args": "server.js",
    "cwd": "/Users/you/dev/myapp",
    "tty": "/dev/ttys003",
    "tmuxSession": "myapp-a1b2c3",
    "tmuxPaneId": "%0"
  }
]
```

#### `processes.tree`

Get the process tree rooted at a given PID.

**Params**:

| Field | Type   | Required | Description   |
|-------|--------|----------|---------------|
| `pid` | number | yes      | Root PID      |

**Returns**: array of process objects (same shape as `processes.list`).

#### `terminals.list`

List all discovered terminal instances with their processes, tabs, and tmux associations.

**Params**:

| Field     | Type    | Required | Description                          |
|-----------|---------|----------|--------------------------------------|
| `refresh` | boolean | no       | Explicitly refresh terminal-tab metadata through terminal app scripting |

**Returns**: array of terminal instance objects:

```json
[
  {
    "tty": "/dev/ttys003",
    "app": "Terminal",
    "windowIndex": 0,
    "tabIndex": 0,
    "isActiveTab": true,
    "tabTitle": "myapp",
    "processes": [ ... ],
    "shellPid": 1234,
    "cwd": "/Users/you/dev/myapp",
    "tmuxSession": "myapp-a1b2c3",
    "tmuxPaneId": "%0",
    "hasClaude": true,
    "displayName": "Terminal — myapp"
  }
]
```

#### `terminals.search`

Search terminal instances by various criteria.

**Params**:

| Field      | Type    | Required | Description                          |
|------------|---------|----------|--------------------------------------|
| `command`  | string  | no       | Filter by command name substring     |
| `cwd`      | string  | no       | Filter by working directory substring |
| `app`      | string  | no       | Filter by terminal app name          |
| `session`  | string  | no       | Filter by tmux session name          |
| `hasClaude`| boolean | no       | Filter to only Claude-running TTYs   |

**Returns**: filtered array of terminal instance objects (same shape as `terminals.list`).

---

## OCR

| Method | Type | Description |
|--------|------|-------------|
| `ocr.snapshot` | read | Current OCR results for all visible windows |
| `ocr.search` | read | Full-text search across OCR history |
| `ocr.history` | read | OCR timeline for a specific window |
| `ocr.scan` | write | Trigger an immediate OCR scan |

See [Screen OCR](/docs/ocr) for configuration, scan schedules, and storage details.

#### `ocr.snapshot`

Get the current in-memory OCR results for all visible windows.

**Params**: none

**Returns**: array of OCR result objects:

```json
[
  {
    "wid": 1234,
    "app": "Terminal",
    "title": "zsh",
    "frame": { "x": 0, "y": 25, "w": 960, "h": 1050 },
    "fullText": "~/dev/myapp $ npm run dev\nready on port 3000",
    "blocks": [
      {
        "text": "~/dev/myapp $ npm run dev",
        "confidence": 0.95,
        "x": 0.02, "y": 0.05, "w": 0.6, "h": 0.04
      }
    ],
    "timestamp": 1709568000.0
  }
]
```

#### `ocr.search`

Full-text search across OCR history using SQLite FTS5.

**Params**:

| Field   | Type    | Required | Description                              |
|---------|---------|----------|------------------------------------------|
| `query` | string  | yes      | FTS5 search query                        |
| `app`   | string  | no       | Filter by application name               |
| `limit` | number  | no       | Max results (default 50)                 |
| `live`  | boolean | no       | Search live snapshot instead of history (default false) |

**FTS5 query examples**: `error`, `"build failed"`, `error OR warning`, `npm AND dev`, `react*`

#### `ocr.history`

Get the OCR timeline for a specific window, ordered by most recent first.

**Params**:

| Field   | Type   | Required | Description                |
|---------|--------|----------|----------------------------|
| `wid`   | number | yes      | CGWindowID                 |
| `limit` | number | no       | Max results (default 50)   |

#### `ocr.scan`

Trigger an immediate OCR scan of all visible windows, bypassing the
periodic timer. Results available via `ocr.snapshot` once complete;
an `ocr.scanComplete` event is broadcast to all clients.

**Params**: none

---

## Events

Events are pushed to all connected WebSocket clients when state changes.
They have no `id` field — listen for messages with an `event` field.

| Event | Trigger |
|-------|---------|
| `windows.changed` | Desktop window list changes |
| `tmux.changed` | Sessions created, killed, or modified |
| `layer.switched` | Active workspace layer changes |
| `ocr.scanComplete` | OCR scan cycle finishes |
| `processes.changed` | Developer processes start or stop |

#### `windows.changed`

```json
{ "event": "windows.changed", "data": { "windowCount": 12, "added": [1234], "removed": [5678] } }
```

#### `tmux.changed`

```json
{ "event": "tmux.changed", "data": { "sessionCount": 3, "sessions": ["myapp-a1b2c3"] } }
```

#### `layer.switched`

```json
{ "event": "layer.switched", "data": { "index": 1, "name": "mobile" } }
```

#### `ocr.scanComplete`

```json
{ "event": "ocr.scanComplete", "data": { "windowCount": 12, "totalBlocks": 342 } }
```

#### `processes.changed`

```json
{ "event": "processes.changed", "data": { "interestingCount": 5, "pids": [1234, 5678] } }
```

---

## Agent integration

### CLAUDE.md snippet

Add this to your project's `CLAUDE.md` so any AI agent working in the
project knows how to control the workspace:

```markdown
## Workspace Control

This project uses lattices for workspace management. The daemon API
is available at ws://127.0.0.1:9399.

### Search (find windows)
- Search by content: `daemonCall('windows.search', { query: 'myproject' })`
  Returns windows with `matchSource` ("title", "app", "session", "ocr") and `ocrSnippet`
- Search terminals: `daemonCall('terminals.search', {})` — tabs, cwds, processes
- CLI: `lattices search myproject`, `lattices search myproject --deep`, or `lattices search myproject --all` (same as `--deep`)

### Actions
- Focus a window: `daemonCall('window.focus', { wid: 1234 })`
- Place a window: `daemonCall('window.place', { session: 'name', placement: 'left' })`
- Launch a project: `daemonCall('session.launch', { path: '/absolute/path' })`
- Activate a layer: `daemonCall('layer.activate', { name: 'web', mode: 'launch' })`
- Optimize the workspace: `daemonCall('space.optimize', { scope: 'visible', strategy: 'balanced' })`
- CLI: `lattices place myproject left` (search + focus + tile in one step)

### Import
\```js
import { daemonCall } from '@lattices/cli'
\```
```

### Multi-agent orchestration

An orchestrator agent can set up the full workspace for sub-agents:

```js
import { daemonCall } from '@lattices/cli'

// Discover what's available
const projects = await daemonCall('projects.list')

// Launch the projects we need
await daemonCall('session.launch', { path: '/Users/you/dev/frontend' })
await daemonCall('session.launch', { path: '/Users/you/dev/api' })

// Tile them side by side
const sessions = await daemonCall('tmux.sessions')
const fe = sessions.find(s => s.name.startsWith('frontend'))
const api = sessions.find(s => s.name.startsWith('api'))

await daemonCall('window.place', { session: fe.name, placement: 'left' })
await daemonCall('window.place', { session: api.name, placement: 'right' })
```

### Reactive event pattern

Subscribe to events to react to workspace changes:

```js
import WebSocket from 'ws'

const ws = new WebSocket('ws://127.0.0.1:9399')

ws.on('message', (raw) => {
  const msg = JSON.parse(raw)

  if (msg.event === 'tmux.changed') {
    console.log('Sessions:', msg.data.sessions.join(', '))
  }

  if (msg.event === 'windows.changed') {
    console.log('Windows:', msg.data.windowCount, 'total')
  }

  if (msg.event === 'layer.switched') {
    console.log('Switched to layer', msg.data.index)
  }
})

// You can also send RPC calls on the same connection
ws.on('open', () => {
  ws.send(JSON.stringify({ id: '1', method: 'daemon.status' }))
})
```

### Health check before use

Always verify the daemon is running before making calls:

```js
import { isDaemonRunning, daemonCall } from '@lattices/cli'

if (!(await isDaemonRunning())) {
  console.error('lattices daemon is not running — start it with: lattices app')
  process.exit(1)
}

const status = await daemonCall('daemon.status')
console.log(`Daemon up for ${Math.round(status.uptime)}s, tracking ${status.windowCount} windows`)
```

### Pi extension

Pi users can install the `@arach/pi-lattices` package in
`packages/pi-lattices/` to expose the daemon as typed `lattices_*` tools:

```bash
pi install ./packages/pi-lattices --local
lattices app
```

The extension wraps the existing daemon and keeps Lattices' macOS-native
runtime, run artifacts, action receipts, and computer-use `treatment` semantics.
It does not bundle `cua-driver` or enable browser automation. See
[Pi Lattices Extension](/docs/pi-lattices) for the tool list and smoke checks.
