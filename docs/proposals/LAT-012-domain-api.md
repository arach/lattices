# LAT-012: One API, domain namespaces, embedded helpers

Status: Proposed, 2026-09-23. Partially supersedes [LAT-011](LAT-011-companion-app-architecture.md)
(distribution and discovery). LAT-011's runtime boundaries still stand: ports,
tokens, leases and credentials.

## Summary

Lattices is a framework for operating a workspace, with parity between the user
and agents. Every capability is addressed as `lattices.<domain>.<verb>`:

```
lattices.windows.tile(wid, "left")
lattices.canvas.pin(note, at: "top-right")
lattices.computer.click(target)
lattices.voice.say("Build finished")
```

Some verbs are served by helpers (Voice, Blink, Action), which are separate
processes embedded in Lattices.app. Agents, skills, the CLI and MCP never see
helpers, only domains.

## Glossary

| Use | Meaning |
| --- | --- |
| **domain** | An API namespace agents see, such as `voice` or `windows`. |
| **verb** | One method on a domain, such as `say` or `tile`. |
| **backend** | The process that serves a verb: the daemon itself, or a helper. |
| **helper** | An app embedded in `Lattices.app/Contents/Helpers`: Voice, Blink or Action. It has its own process, bundle ID and settings window. |
| **daemon** | The Lattices process that hosts the router and the native backends. |
| **router** | The daemon layer that resolves a name, applies aliases, and dispatches to a backend. |
| **surface** | One projection of a name: SDK, CLI, daemon RPC or MCP. |

**Retired:**
- *companion* becomes helper.
- *product*, *module* and *engine* become helper or backend.
- *overlay* becomes canvas.
- *Speech* becomes Voice. The name survives only in the frozen bundle ID `dev.lattices.Speech`.
- Action's *drive* and *stage* vocabulary maps to verbs, as listed below.
- *app* now means only Lattices.app itself, or a third-party app the user runs.

## Naming rules

1. **The domain is one lowercase noun, and the method is a verb.** One verb per
   call, and never a compound verb such as `act_execute`.
2. **Domains are plural where they name a collection**: `windows`, `spaces`,
   `layers`, `sessions`, `tabs`, `apps`, `artifacts`. Mass nouns stay singular:
   `canvas`, `computer`, `voice`, `capture`.
3. **Read verbs** are `status`, `list`, `get` and `search`. Every domain that has
   state answers `status`; there is no separate `health`, `recording` or `staged`.
4. **Sub-nouns only name a collection the domain owns**: `mouse.shortcuts.set`,
   `canvas.notes.create`, `sessions.layers.list`.
5. **Exclusive access is always `lease` and `release`**, in every domain.
6. **Surface forms.** MCP turns every dot after the domain into `_`, because MCP
   forbids dots, and the server name supplies `lattices`.

| Surface | Form | Example |
| --- | --- | --- |
| SDK | `lattices.<domain>.<verb>(…)` | `lattices.mouse.shortcuts.set(…)` |
| CLI | `lattices <domain> <verb> …` | `lattices mouse shortcuts set …` |
| Daemon RPC | `<domain>.<verb>` | `mouse.shortcuts.set` |
| MCP | `<domain>_<verb>` | `mouse_shortcuts_set` |

## Which do I call?

| I want to… | Call |
| --- | --- |
| See what is on screen right now | `computer.observe({ mode })`, where mode is `snapshot`, `ax`, `ocr` or `vision` |
| Search what has been on screen before | `ocr.search` |
| Find a window by name or project | `windows.search` |
| Bring a window forward | `windows.focus` |
| Open an app | `apps.open` |
| Click or type somewhere | `computer.click`, `computer.type` |
| Save a screenshot or recording | `capture.screenshot`, `capture.record` |
| Put something on the screen for the user | `canvas.pin` for something that stays, `canvas.draw` for something transient |
| Say something out loud | `voice.say` |
| Work in a browser page | `browser.*`. The agent's own Chrome is the default target; see open question 3. |

`mouse.*` is the user's physical pointer (find it, summon it, its shortcuts).
The agent's synthetic cursor is `computer.aim`.

## Domains and backends

The backend is chosen per verb, not per domain. If a verb's helper is not
installed, the call fails with `helper_not_installed`, names the helper, and
gives the fix: "Lattices › Apps › Install Voice". There are no fallbacks.

| Domain | Verbs | Backend |
| --- | --- | --- |
| `windows` | list, get, preview, search, tile, focus, move, place, present, resolve, pick | daemon |
| `spaces` | list, optimize | daemon |
| `layers` | list, activate, switch, assign, unassign, map | daemon |
| `layout` | distribute | daemon |
| `desktop` | snapshot (front window, layer, displays, sessions, permissions) | daemon |
| `sessions` | launch, kill, detach, restart, sync, `layers.*` | daemon |
| `groups` | launch, kill | daemon |
| `tabs` | list, stack, add, select, layout, unstack | daemon |
| `apps` | open | daemon |
| `projects`, `processes`, `terminals`, `tmux` | list, scan, tree, search, capture, … (unchanged) | daemon |
| `mouse` | find, summon, `shortcuts.*` | daemon |
| `ocr` | search, history, recent, scan. This is the index of past screen text. Live reading is `computer.observe`. | daemon |
| `capture` | screenshot, record, stop, status, stage, unstage | daemon now; Action's recording is folded in during phase 3 |
| `artifacts` | list, analyze, zoom | daemon |
| `runs` | create, list, get. A run is a receipt plus an artifact directory for one piece of agent work. | daemon |
| `computer` | observe, resolve, click, type, press, drag, scroll, aim, note, play, verify, lease, release, status | daemon now; the Action helper from phase 3 |
| `canvas` | draw, clear, `actors.*` | daemon (the LAT-002 overlay canvas) |
| `canvas` | pin, unpin, move, focus, list, `notes.*`, `workspaces.*` | Blink helper |
| `voice` | say, stop, pause, resume, skip, seek, list, use, lease, release | Voice helper |
| `voice` | listen, stopListening, simulate, reconnect, status | daemon (`status` also reports the Voice helper) |
| `browser` | open, tabs, snapshot, click, fill, screenshot, console, close, profiles, … | Action helper (agent's own Chrome) |
| `intents`, `history` | see open question 2 | daemon |
| `deck` | manifest, snapshot, perform. The iPad cockpit's state and actions. | daemon |
| `search`, `assistant`, `handsoff`, `settings`, `daemon`, `diagnostics`, `api` | unchanged | daemon |

## Renames

The router keeps each old name as an alias for its new name. `api.schema` and MCP
advertise only new names. There is one exception, listed under breaking changes.

### Core

| Old | New |
| --- | --- |
| `window.tile/focus/move/place/present/resolve` | `windows.tile/focus/move/place/present/resolve` |
| `window.pick.start` | `windows.pick` |
| `window.assignLayer`, `window.removeLayer`, `window.layerMap` | `layers.assign`, `layers.unassign`, `layers.map` |
| `layer.activate`, `layer.switch` | `layers.activate`, `layers.switch` |
| `space.optimize` | `spaces.optimize` |
| `session.*`, `session.layers.*` | `sessions.*`, `sessions.layers.*` |
| `group.launch/kill` | `groups.launch/kill` |
| `tabStacks.create/delete` and the rest of `tabStacks.*` | `tabs.stack/unstack` and `tabs.*` |
| `lattices.search` | `search.query`. The `lattices.` prefix is reserved for the SDK root. |
| `focus.*` (Focus Mode) | see open question 1 |

### voice

| Old | New |
| --- | --- |
| `speech.enqueue` | `voice.say` |
| `speech.stop` / `pause` / `resume` / `next` / `seek` | `voice.stop` / `pause` / `resume` / `skip` / `seek` |
| `speech.voices` | `voice.list` |
| `speech.preferredVoice.set` | `voice.use`. The preferred voice is reported in `voice.status`. |
| `speech.status` | merged into `voice.status` |
| `speech.playback.reserve` | `voice.lease`, plus `voice.release`. A lease still ends when its connection closes. |
| `speech.changed` (event) | `voice.changed` |
| `voice.stop` (stop listening) | `voice.stopListening`. **Breaking**: see below. |

The daemon forwards output verbs to the Voice helper. The helper's own RPC keeps
accepting `speech.*`, so the daemon and helper protocols can change independently.

### computer, capture and apps (daemon `computer.*` and Action merged)

| Old | New |
| --- | --- |
| Action `act_execute` with kind click / type / press-key / drag / scroll | `computer.click` / `type` / `press` / `drag` / `scroll` |
| Action `act_execute` with kind focus-window, and `computer.focusWindow` | `windows.focus` |
| Action `act_execute` with kind open-app, and `computer.launchApp` | `apps.open` |
| `computer.doubleClick`, `computer.rightClick` | `computer.click({ count: 2 })`, `computer.click({ button: "right" })` |
| `computer.typeText`, `computer.typeWindowText`, `computer.typeElement`, `computer.setValue` | `computer.type`, with the target given as a point, window or element |
| `computer.pressKey`, `computer.hotkey` | `computer.press` |
| `computer.elementAction` | `computer.click` on an element target; other AX actions use `computer.click({ action })` |
| Action `observe_snapshot/ocr/vision/ax`, `computer.windowState`, `ocr.snapshot`, `vision.analyzeWindow` | `computer.observe({ mode })` |
| Action `resolve_target`, `computer.prepare` | `computer.resolve` |
| Action `drive_begin/release/status`, `session_create`, `driver_identify` | `computer.lease` (identity and task go in its arguments) / `computer.release` / `computer.status` |
| Action `drive_aim`, `computer.magicCursor`, `computer.showCursor` | `computer.aim` |
| Action `drive_note`, `drive_play` | `computer.note`, `computer.play` |
| Action `health` | `computer.status` |
| Action `record_start/stop/status`, `capture.recordWindow/Region`, `capture.stopRecording` | `capture.record` / `capture.stop` / `capture.status` |
| `capture.screenshotWindow/Region/Display` | `capture.screenshot({ target })` |
| Action `stage_set/clear/status` | `capture.stage` / `capture.unstage` / `capture.status` |
| Action `artifacts_list`, `runs.artifacts` | `artifacts.list` |
| `vision.analyzeArtifact`, `capture.zoomArtifact` | `artifacts.analyze`, `artifacts.zoom` |
| `computer.demoScout`, `computer.demoTerminal` | removed from the API; they become scripts |

### canvas

Provisional until Blink has an RPC (phase 4):

| Old | New |
| --- | --- |
| `overlay.publish`, `overlay.clear` | `canvas.draw`, `canvas.clear` |
| `overlay.actor.publish/moveTo/visibility/hud` | `canvas.actors.put/move/show/attach` |
| Blink `show` / `rm` / `desk open` / `desk move` / `ls` | `canvas.pin` / `canvas.unpin` / `canvas.focus` / `canvas.move` / `canvas.list` |
| Blink `new` / `cat` / `write` / `append` / `search` | `canvas.notes.create/get/write/append/search` |
| Blink `workspace init` / `workspace notes` | `canvas.workspaces.create` / `canvas.workspaces.list` |

## Breaking changes

- **`voice.stop` changes meaning.** It used to stop listening; now it stops
  speaking. There is no alias. The daemon has no in-repo RPC callers (the Swift
  code already calls `stopListening()`); `lattices voice stop` and the voice docs
  are updated in the same change. For one release, a `voice.stop` call made while
  listening and not speaking returns a hint pointing to `voice.stopListening`.

## Packaging: helpers inside Lattices.app

```
Lattices.app/Contents/Helpers/
  Voice.app     dev.lattices.Speech   (bundle ID frozen)
  Blink.app     dev.arach.blink
  Action.app    dev.lattices.Action   (no longer shipped on its own)
```

- **Bundle IDs do not change.** All three shipped on 2026-09-15, and TCC grants,
  preferences, Keychain approvals and the lease token directory are keyed to them.
- **Discovery** prefers the embedded helper and ignores standalone copies in
  `/Applications` or `~/Applications`. The Apps menu can offer to move them to the Trash.
- **Signing** goes inside out: each helper first, then Lattices.app, under team
  `2U83JFPW66`, with one notarization.
- **Lifecycle** follows LAT-011. Helpers launch on demand or from the Apps menu,
  and quitting Lattices does not kill them.
- **Size:** Kokoro data downloads on first use only if the embedded build turns
  out to be too large. Measure first.
- **Action stops shipping on its own.** Its DMG, MCP server, plugins and
  `lattices.dev/action` are retired after phase 3, once `lattices mcp` serves
  `computer_*`, `capture_*` and `browser_*`. The per-helper DMG workflows and the
  installer are removed once the embedded build ships.

## Phases

1. **Voice.** Rename Speech to Voice (display name, executable, strings, skill),
   embed it, add the `voice.*` output verbs, rename `voice.stop` to
   `voice.stopListening`, and fix the dark-mode text in the controls window.
2. **Router.** Add the alias table, apply the core renames, and update
   `api.schema`, the CLI, the SDK and `skills/lattices`.
3. **Computer.** Audit the daemon's `computer.*` against Action one verb at a time,
   port daemon-only verbs into Action, make Action the backend, serve
   `computer_*` / `capture_*` / `browser_*` from `lattices mcp`, embed Action, and
   retire the standalone product.
4. **Canvas.** Add a Blink RPC, forward the Blink verbs, move `overlay.*`, and embed Blink.
5. **Docs and skills.** One skill with a section per domain; update docs,
   llms.txt and the site.

## Decisions (2026-09-23)

- `voice.stop` stops speaking; `voice.stopListening` stops listening.
- Observe is one verb with a mode.
- `canvas` is one domain: Blink's persistent pins and notes, plus the overlay canvas.
- Action stops shipping as its own product. Its native code becomes the only backend
  for `computer.*`, and the daemon's duplicates are removed as they are ported.
- Helper bundle IDs are frozen.

## Open questions

1. **Focus Mode** (`focus.enter/exit/toggle/status`) collides with `windows.focus`.
   It needs its own domain noun, for example `solo.enter`.
2. **`actions` and `intents`.** `actions.execute` runs a canonical workspace
   mutation and returns a receipt with undo; `intents.execute` runs a structured
   intent from voice or an agent. A domain named `actions` next to the retired
   Action product will confuse people. Proposal: `intents.run` and `intents.list`,
   and `history.list` and `history.undo` for receipts, with `actions.execute`
   folded into `intents.run`.
3. **`browser` target.** The daemon's `browser.*` reads the user's own browser
   through Accessibility (JavaScript only with `allowAutomation`), while Action's
   `browser_*` drives the agent's own Chrome through the DOM. Proposal: one
   `browser` domain with `target: "agent"` (the default) or `"user"`.
