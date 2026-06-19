# LatticesTerminalKit

`LatticesTerminalKit` is the reusable Swift terminal-inventory slice of
lattices. It is designed for native hosts such as Scout that should embed the
same macOS probes directly instead of talking to the lattices daemon or CLI.

## V1 Scope

The first slice inventories:

- Apple Terminal
- iTerm2
- Ghostty

It intentionally stays read-oriented. Focus and placement actions can build on
the returned handles later, but the v1 contract is an observed terminal
projection, not a canonical session or message store.

## Import

The product lives in the repo's reusable Swift package:

```swift
import LatticesTerminalKit

let snapshot = TerminalInventory.snapshot()
```

For bounded tmux pane context:

```swift
let snapshot = TerminalInventory.snapshot(options: .init(
    includePaneContent: true,
    paneContentLineLimit: 120
))
```

## Snapshot Shape

`TerminalInventorySnapshot` contains:

- `snapshotId`
- `observedAt`
- `terminals`
- `tmuxSessions`
- `terminalTabs`
- `terminalWindows`

Each `TerminalInstance` includes:

- identity: `stableKey`, `tty`, app name, bundle id, app pid
- terminal UI: window id/title, tab index/title, terminal session id
- process context: interesting process rows, shell pid, cwd, cwd source
- tmux context: session and pane id
- harness detection: `detectedHarnesses` for Claude and Codex signals
- action preparation: `focusHandle`, `placementHandle`, `capabilities`
- trust metadata: `provenance` with confidence for tty/cwd/window/tmux/harness
- optional inspection: bounded `paneCapture`

## Join Strategy

The kit joins by TTY first.

Inputs:

- process table from `ps`
- cwd lookup from batched `lsof`
- tmux sessions and panes
- AppleScript tab probes for Terminal and iTerm2
- CG window inventory for Terminal, iTerm2, and Ghostty

Window resolution order:

1. lattices title tag: `[lattices:<session>]`
2. app window index from Terminal/iTerm2 tab probes
3. CG owner process tree TTY, used especially for Ghostty

Ghostty is expected to be window-level in v1. The kit does not synthesize stable
tab ids from titles or z-order.

## Notes For Scout

CG window IDs are useful but volatile. Consumers should pair them with
`stableKey`, app pid, bundle id, tty, and tmux pane identity where available.

Pane capture is opt-in and ephemeral. It should be treated as drill-down context,
not as durable chat or terminal history.
