# LAT-012: One API, domain namespaces, embedded companions

Status: Proposed, 2026-09-23. Partially supersedes [LAT-011](LAT-011-companion-app-architecture.md)
(distribution and discovery); LAT-011's runtime boundaries (ports, tokens,
reservations, credentials) stand.

## Summary

Lattices is a framework for operating a workspace, with parity between the user
and agents. Every capability is addressed as `lattices.<domain>.<verb>`:

```
lattices.windows.tile(wid, "left")
lattices.canvas.pin(note, at: "top-right")
lattices.computer.click(target)
lattices.voice.say("Build finished")
```

The companion apps (Blink, Action, Speech) remain separate processes, but they are
the backends and user-facing surfaces for domains. They are not separate APIs.
Agents, skills, the CLI and MCP only ever see domains.

## Naming rules

1. **The domain is a noun and the method is a verb.** One verb per call. A call
   carries its domain and never a compound verb such as `act_execute`.
2. **Domains are plural where they name a collection**: `windows`, `spaces`,
   `layers`, `sessions`, `terminals`. Mass nouns stay singular: `canvas`,
   `computer`, `voice`, `ocr`, `capture`, `focus`.
3. **Verbs are lowerCamel**, and each is a single verb where possible:
   `tile`, `focus`, `say`, `pin`, `click`. A sub-noun is fine when the domain
   owns a collection (`mouse.shortcuts.set`).
4. **Surface forms** of one name:

| Surface | Form | Example |
| --- | --- | --- |
| SDK | `lattices.<domain>.<verb>(…)` | `lattices.voice.say("hi")` |
| CLI | `lattices <domain> <verb> …` | `lattices voice say "hi"` |
| Daemon RPC | `<domain>.<verb>` | `voice.say` |
| MCP | `<domain>_<verb>`. The server name supplies `lattices`, and MCP forbids dots. | `voice_say` |

## Domains

| Domain | Backend | Today |
| --- | --- | --- |
| `windows`, `spaces`, `layers`, `layout`, `sessions`, `terminals`, `tabStacks`, `projects`, `processes`, `focus`, `mouse`, `ocr`, `capture`, `runs`, `vision`, `deck`, `actions`, `intents`, `browser`, `settings`, `daemon`, `diagnostics`, `api` | Lattices (always present) | Mostly already `domain.verb`; see renames. |
| `canvas` | Blink.app for persistent pins and panels, plus the Lattices overlay canvas (LAT-002) for transient drawing | Blink has its own CLI only. The daemon has `overlay.*`. |
| `computer` | Lattices native (the existing `computer.*`) and Action.app (drive leases, recording, staging) | Two surfaces: the daemon's `computer.*` and Action's `action.*` MCP tools. |
| `voice` | Voice.app (renamed from Speech) for output, and Lattices for input (listen) | `voice.*` is input only. `speech.*` is forwarded to Speech.app. |

Install rule, for now: if you use a companion domain, install its app. A call to a
missing app returns a plain error that names the app. There are no fallbacks.

## Renames

The router keeps every old name as an alias that resolves to the new one.
`api.schema` and MCP advertise only new names. Aliases are one table in the
router and cost nothing else.

### Core normalization

| Old | New |
| --- | --- |
| `window.tile`, `window.focus`, `window.move`, `window.place`, `window.present`, `window.resolve` | `windows.tile`, `windows.focus`, `windows.move`, `windows.place`, `windows.present`, `windows.resolve` |
| `window.pick.start` | `windows.pick` |
| `window.assignLayer`, `window.removeLayer`, `window.layerMap` | `layers.assign`, `layers.unassign`, `layers.map` |
| `layer.activate`, `layer.switch` | `layers.activate`, `layers.switch` |
| `space.optimize` | `spaces.optimize` |
| `session.launch`, `session.kill`, `session.detach`, `session.restart`, `session.sync` | `sessions.launch`, `sessions.kill`, `sessions.detach`, `sessions.restart`, `sessions.sync` |
| `session.layers.*` | `sessions.layers.*` |
| `group.launch`, `group.kill` | `groups.launch`, `groups.kill` |
| `lattices.search` | `search.query`. The `lattices.` prefix is reserved for the SDK root. |
| `desktop.snapshot` | `spaces.snapshot` |
| `layout.distribute` | `layout.distribute` (unchanged) |

### `voice` (output merged in from Speech)

| Old (`speech.*`, forwarded) | New |
| --- | --- |
| `speech.enqueue` | `voice.say` |
| `speech.pause` / `resume` / `next` / `seek` | `voice.pause` / `voice.resume` / `voice.skip` / `voice.seek` |
| `speech.stop` | `voice.hush` (see open question 1) |
| `speech.voices` | `voice.voices` |
| `speech.status` | merged into `voice.status` |
| `speech.preferredVoice.*` | `voice.preferredVoice.*` |
| `speech.playback.reserve` | `voice.reserve` |
| `speech.changed` (event) | `voice.changed` |
| existing `voice.listen` / `stop` / `simulate` / `reconnect` | unchanged |

`DaemonServer` forwards the output verbs to Voice.app, as it forwards `speech.*`
today. The Voice.app RPC keeps accepting `speech.*` internally, so the companion
protocol does not have to change in step with the daemon.

### `computer` (Action folded in)

| Old (Action MCP, advertised) | New |
| --- | --- |
| `act_execute` | split by its `kind` into one verb each: click, type, press-key, drag, scroll, focus-window and open-app become `computer.click`, `computer.type`, `computer.press`, `computer.drag`, `computer.scroll`, `computer.focus` and `computer.open` |
| `observe_snapshot` / `observe_ocr` / `observe_vision` / `observe_ax` | `computer.observe` with `{ mode }`, or `computer.snapshot`, `computer.read`, `computer.look`, `computer.inspect` (open question 2) |
| `resolve_target` | `computer.resolve` |
| `drive_begin` / `drive_release` / `drive_status` | `computer.lease` / `computer.release` / `computer.status` |
| `drive_note` / `drive_aim` / `drive_play` | `computer.note` / `computer.aim` / `computer.play` |
| `record_start` / `record_stop` / `record_status` | `computer.record` / `computer.stopRecording` / `computer.recording` |
| `stage_set` / `stage_clear` / `stage_status` | `computer.stage` / `computer.unstage` / `computer.staged` |
| `session_create`, `driver_identify`, `artifacts_list`, `health` | `computer.session`, `computer.identify`, `runs.artifacts`, `computer.health` |

The existing daemon names `computer.typeText`, `computer.pressKey` and
`computer.rightClick` become `computer.type`, `computer.press` and
`computer.click { button: "right" }`, with aliases.

### `canvas`

| Source | New |
| --- | --- |
| Blink `show` / `rm` / `move` / `focus` / `ls` | `canvas.pin` / `canvas.unpin` / `canvas.move` / `canvas.focus` / `canvas.list` |
| Blink `desk`, `workspace` | `canvas.desks`, `canvas.workspace` |
| daemon `overlay.publish` / `overlay.clear` | `canvas.draw` / `canvas.clear` |
| daemon `overlay.actor.*` | `computer.cursor.*`. The synthetic cursor belongs to computer use. |

Blink gains a loopback RPC (the pattern Speech uses on 9397), and the daemon
forwards `canvas.*` pin verbs to it.

## Packaging: companions inside Lattices.app

```
Lattices.app/Contents/Helpers/
  Voice.app     dev.lattices.Speech   (bundle ID unchanged)
  Blink.app     dev.arach.blink
  Action.app    dev.lattices.Action
```

- **Bundle IDs do not change.** All three shipped on 2026-09-15, and TCC grants,
  preferences, Keychain approvals and the reservation token directory are keyed to
  them. Only the display name and executable change for Speech, which becomes Voice.
- **Discovery** checks the embedded helper first. A standalone copy in
  `/Applications` or `~/Applications` is ignored when an embedded one exists; the
  menu can offer to move it to the Trash.
- **Signing** goes inside out: sign each helper, then the Lattices bundle, with the
  same team (`2U83JFPW66`) and one notarization.
- **Lifecycle** is unchanged from LAT-011. Helpers are launched on demand or from
  the Apps menu, and quitting Lattices does not kill them.
- **Size:** Kokoro model data downloads on first use only if the embedded build
  turns out to be too large. Measure first.
- The per-product DMG workflows and the on-demand installer stay in place until
  the embedded build is released, and are removed after that.

## Phases

1. **Voice.** Rename Speech to Voice (display name, executable, strings), embed it
   in the Lattices build, add the `voice.*` output verbs with `speech.*` aliases,
   and fix the dark-mode text in the controls window.
2. **Router.** Add the alias table, apply the core normalization, update `api.schema`,
   the CLI, the SDK and `skills/lattices`.
3. **Computer.** Serve Action's tools as `computer_*` from the lattices MCP server
   (as a `computer` toolset), keep the Action server's old names behind
   `ACTION_MCP_TOOL_NAMES=legacy`, and embed Action.
4. **Canvas.** Add a Blink RPC, forward `canvas.*`, move `overlay.*`, and embed Blink.
5. **Docs and skills.** Merge `skills/speech`, `skills/action` and `skills/blink`
   into domain sections of one skill set, and update docs, llms.txt and the site.

## Open questions

1. `voice.stop` already means "stop listening". Should stopping speech be `voice.hush`,
   or should `voice.stop` stop whatever voice activity is running?
2. Should observe be one verb with a mode, or four verbs?
3. When Action is installed, do the daemon's native `computer.click` and similar
   route through Action, or do both implementations stay? This proposal keeps
   both and makes no routing decision.
