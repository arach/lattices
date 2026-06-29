# Pi Lattices Extension

`@arach/pi-lattices` is a Pi package that turns the Lattices daemon into
first-class Pi tools. It is implemented in `packages/pi-lattices/` and registers
strictly-prefixed `lattices_*` tools on Pi session start.

The extension preserves the Lattices runtime model:

- It calls the existing macOS-native daemon at `ws://127.0.0.1:9399`.
- It does not bundle or route through `cua-driver`.
- Run-backed computer-use tools keep Lattices `treatment` semantics.
- Mutation wrappers prefer `treatment: "stage"` unless the caller explicitly
  asks for `present` or `execute`.
- Daemon-down failures are tool results with guidance, not registration-time
  crashes.

## Install

From this repo during development:

```bash
pi install ./packages/pi-lattices --local
```

Published package form:

```bash
pi install npm:@arach/pi-lattices
```

Start Lattices before using the tools:

```bash
lattices app
```

## High-value tools

| Pi tool | Lattices method |
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
| `lattices_computer_window_state` | `computer.windowState` |
| `lattices_computer_element_action` | `computer.elementAction` |
| `lattices_window_focus` | `computer.focusWindow` |
| `lattices_window_place` | `window.place` |
| `lattices_capture_window` | `capture.screenshotWindow` |
| `lattices_computer_prepare` | `computer.prepare` |
| `lattices_computer_launch_app` | `computer.launchApp` |
| `lattices_computer_click` | `computer.click` |
| `lattices_computer_type_window_text` | `computer.typeWindowText` |
| `lattices_computer_type_text` | `computer.typeText` |
| `lattices_call` | caller-selected escape hatch |

Use `lattices_call` only when a method is not typed yet. It passes through the
requested daemon method and does not add an additional confirmation layer.

## Smoke/manual test path

Automated registration smoke:

```bash
node packages/pi-lattices/test/smoke.mjs
```

Daemon-down behavior:

```bash
bun run --cwd packages/pi-lattices smoke:no-daemon
```

Live status + safe staged call:

```bash
lattices app
bun run --cwd packages/pi-lattices smoke:live
```

The live smoke checks `daemon.status`, then stages a `computer.launchApp` run for
Finder with `capture: false`. Because the call uses `treatment: "stage"`, it
records intent without launching or focusing the app.
