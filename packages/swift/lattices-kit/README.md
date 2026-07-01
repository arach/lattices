# LatticesKit

Swift SDK for embedding Lattices workspace control into macOS apps such as
Scout or HudsonKit-based hosts.

LatticesKit is an in-process embed. The host app imports a Swift package and
directly owns the macOS permissions it needs: Accessibility, Screen Recording,
Input Monitoring, SkyLight Space switching, keyboard/mouse events, and tmux
process integration. Users grant the host app, not a separate Lattices runtime.

The package also contains a daemon-backed adapter for existing automation and
debugging surfaces, but app integrations should start with `Lattices`.

## Host App Boundary

LatticesKit does not ship a separate permission-owning helper for the embedded
path. The host app should include the relevant usage descriptions in its own
bundle:

- `NSAccessibilityUsageDescription`
- `NSScreenCaptureUsageDescription`

Input Monitoring is checked and requested with IOKit for hosts that register
or observe global shortcuts. LatticesKit opens the matching System Settings pane
when macOS requires the user to finish the grant manually.

See [Embedded SDK](../../../docs/embedded-sdk.md) for the host-owned helper
model, including `Scout Helper` and `Scout Workspace Helper` naming guidance.

## Add The Package

```swift
.package(path: "/Users/art/dev/lattices/packages/swift/lattices-kit")
```

```swift
.product(name: "LatticesKit", package: "lattices-kit")
```

## Scout Example

```swift
import LatticesKit

let lattices = Lattices()

let readiness = lattices.readiness(for: [.sessionNavigation, .computerUse])
if let firstMissing = readiness.missing.first {
    lattices.permissions.request(firstMissing)
}

let session = lattices.sessionName(for: "/Users/art/dev/lattices")
try lattices.sessions.launch(path: "/Users/art/dev/lattices")
try lattices.windows.focus(session: session)
try lattices.windows.tile(.session(session), position: .right)
```

## HudsonKit Example

```swift
import LatticesKit

let lattices = Lattices()

let terminals = lattices.windows.list().filter { $0.app == "iTerm2" || $0.app == "Terminal" }
for window in terminals.prefix(2) {
    try lattices.windows.tile(.window(window.wid), position: .left)
}

try lattices.input.hotkey("cmd+shift+m")
```

## Capability Groups

- `lattices.permissions`: check/request TCC readiness for the host app and open the right System Settings pane.
- `lattices.windows`: list CG windows, parse `[lattices:<session>]` title tags, focus across Spaces, and tile/place with AX.
- `lattices.tmux`: compute canonical session names, inspect sessions/panes, and run scoped tmux commands.
- `lattices.sessions`: create lattices tmux sessions from `.lattices.json`, restart panes, kill, and detach.
- `lattices.accessibility`: inspect AX trees from the host process.
- `lattices.input`: post shortcuts, clicks, and paste text from the host process.

The SDK also exposes `handle(_:)` and `dispatch(method:params:)` for hosts
that want to route commands through their own UI, agent protocol, or plugin
surface without opening a localhost port.

The embedded package keeps the session-name contract identical to the CLI:
`<basename>-<sha256-6chars>`, computed from the absolute standardized path.

## Optional Daemon Adapter

`LatticesClient` is still available when you explicitly want to talk to a
running Lattices app/daemon, for example in scripts, diagnostics, or external
control tools. Do not use this path for Scout/HudsonKit embedding when the
goal is host-owned TCC:

```swift
let lattices = LatticesClient()
let schema = try await lattices.apiSchema()
let result = try await lattices.call("api.schema")
```
