# @arach/pi-lattices

Pi extension that exposes the local Lattices macOS daemon as typed `lattices_*`
tools. It wraps Lattices' existing WebSocket API at `ws://127.0.0.1:9399`; it
does **not** bundle `cua-driver`, replace the Lattices daemon, or enable browser
automation.

## Requirements

- macOS with Lattices installed from this repo.
- The Lattices menu bar app running so the daemon is available:

```bash
lattices app
```

If the daemon is not reachable, every tool returns a friendly Pi tool error with
this startup command instead of throwing during tool registration.

## Install

Local development from the Lattices repo:

```bash
pi install ./packages/pi-lattices --local
```

After the package is published:

```bash
pi install npm:@arach/pi-lattices
```

Restart Pi after installing so the extension can register tools on session start.

## Tools

All tools use the `lattices_` prefix.

### Read/discovery

| Tool | Daemon method |
| --- | --- |
| `lattices_status` | `daemon.status` |
| `lattices_api_schema` | `api.schema` |
| `lattices_windows_list` | `windows.list` |
| `lattices_windows_search` | `windows.search` |
| `lattices_window_get` | `windows.get` |
| `lattices_runs_list` | `runs.list` |
| `lattices_runs_get` | `runs.get` |
| `lattices_ocr_snapshot` | `ocr.snapshot` |
| `lattices_ocr_search` | `ocr.search` |

### Mutations / computer use

| Tool | Daemon method | Safety note |
| --- | --- | --- |
| `lattices_computer_window_state` | `computer.windowState` | `mode: "ax"` inspects only; `both`, `screenshot`, or `capture: true` create run artifacts. |
| `lattices_computer_element_action` | `computer.elementAction` | Defaults to `treatment: "stage"`; pass `execute` to perform AXPress/showMenu. |
| `lattices_computer_type_element` | `computer.typeElement` | Defaults to `treatment: "stage"`; pass `execute` to set or append AXValue text. |
| `lattices_computer_set_value` | `computer.setValue` | Defaults to `treatment: "stage"`; pass `execute` to replace AXValue. |
| `lattices_computer_press_key` | `computer.pressKey` | Defaults to `treatment: "stage"`; pass `execute` with an explicit target to press. |
| `lattices_computer_hotkey` | `computer.hotkey` | Defaults to `treatment: "stage"`; pass `execute` with an explicit target to send. |
| `lattices_window_focus` | `computer.focusWindow` | Defaults to `treatment: "stage"`; pass `present` or `execute` to focus. |
| `lattices_window_place` | `window.place` | Returns the daemon action receipt. |
| `lattices_capture_window` | `capture.screenshotWindow` | Creates a run artifact. |
| `lattices_computer_prepare` | `computer.prepare` | Stages/observes a terminal target. |
| `lattices_computer_launch_app` | `computer.launchApp` | Defaults to `treatment: "stage"`; pass `present` or `execute` to launch/focus. |
| `lattices_computer_click` | `computer.click` | Defaults to `treatment: "stage"`; pass `execute` to click. |
| `lattices_computer_type_window_text` | `computer.typeWindowText` | Defaults to `treatment: "stage"`; pass `execute` to insert text. |
| `lattices_computer_type_text` | `computer.typeText` | Defaults to `treatment: "stage"`; pass `execute` to insert text. |
| `lattices_call` | caller-selected | Escape hatch; prefer typed tools first. |

The default `source` for run-backed tools is `pi-lattices` unless the caller
passes a more specific `source`.

`lattices_call` intentionally does not add an extra safety layer; it is for
daemon methods that are not yet typed here. Prefer typed tools for actions and
keep destructive daemon methods out of normal prompts.

## Smoke checks

Registration only:

```bash
node packages/pi-lattices/test/smoke.mjs
```

Graceful daemon-down behavior (uses an intentionally unreachable port):

```bash
bun run --cwd packages/pi-lattices smoke:no-daemon
```

Live status + safe staged action:

```bash
lattices app
bun run --cwd packages/pi-lattices smoke:live
```

The live smoke calls `lattices_status`, then stages `computer.launchApp` for
Finder with `capture: false`; it does not launch or focus Finder because the
`treatment` is `stage`.

## Configuration

By default the extension connects to `ws://127.0.0.1:9399`. For tests or custom
setups, override with environment variables before starting Pi:

```bash
export LATTICES_DAEMON_HOST=127.0.0.1
export LATTICES_DAEMON_PORT=9399
export LATTICES_DAEMON_TIMEOUT_MS=3000
```

## Phase 2 direction

`computer.windowState` is now exposed as `lattices_computer_window_state` for
AX inspection and optional run-backed screenshot artifacts. `computer.elementAction`
adds element-id AXPress/showMenu/focus, and `computer.typeElement` /
`computer.setValue` add element-id AXValue insertion while keeping treatment,
run, and artifact semantics in the daemon.
