---
title: Embedded SDK
description: Embedding LatticesKit into host apps and Scout-owned helpers
order: 30
---

LatticesKit is the embeddable form of lattices. It is a Swift package that
host apps compile into their own process or into a helper app they own. The
important boundary is product ownership: users should grant permissions to the
host product, not to a separate Lattices runtime.

## Core principle

Lattices can provide the implementation for workspace capabilities without
owning the macOS trust boundary.

For Scout, that means LatticesKit can power session navigation, tmux control,
window management, Spaces switching, Accessibility inspection, screen capture,
and input helpers while macOS shows a Scout-owned app in Privacy & Security.

LatticesKit should not require users to install or trust `Lattices.app` just
because Scout wants to embed lattices capabilities.

## Ownership models

There are two supported embedding shapes.

### Main app owned

The host app links LatticesKit directly:

```text
Scout.app
└── links LatticesKit
```

macOS permissions belong to `Scout.app`. This is the simplest model when the
main app has the right lifecycle for global shortcuts, window observation, and
desktop control.

### Helper owned

The host ships a product-owned helper that links LatticesKit:

```text
Scout.app
└── Contents/Resources/Scout Workspace Helper.app
    └── links LatticesKit
```

macOS permissions belong to the helper. The main app talks to it through an
internal boundary such as XPC or an authenticated local channel.

This follows the useful part of Orca's `Orca Computer Use.app` pattern: a
bundled helper owns sensitive desktop permissions. The difference is that the
helper is Scout-owned, Scout-branded, and installed with Scout. Lattices remains
an implementation library inside that helper.

## Naming convention

Use helper names to explain the product trust boundary.

| Name | Meaning |
|------|---------|
| `Scout Helper` | General Scout-owned helper for product logic, menu bar lifecycle, or broad coordination |
| `Scout <domain> Helper` | Scout-owned helper for a specific embedded capability domain |
| `Lattices Helper` | Avoid. This makes Lattices look like the permission owner |

For a LatticesKit integration, good names are:

- `Scout Helper` when one broad helper owns all Scout desktop capabilities
- `Scout Workspace Helper` when the helper specifically owns workspace,
  session, tmux, window, and Spaces capabilities
- `Scout Computer Use Helper` only when the capability is intentionally framed
  as general app control rather than workspace management

The rule is: split helpers by trust boundary and lifecycle, not by library
boundary. Do not create one helper per embedded package unless the user-facing
permission story or blast radius truly improves.

## Permission ownership

The owner bundle must carry the macOS usage descriptions for the capabilities it
performs:

- `NSAccessibilityUsageDescription`
- `NSScreenCaptureUsageDescription`

Input Monitoring does not use the same Info.plist prompt shape, but the owner
bundle is still what macOS lists in Privacy & Security when the helper requests
or checks listen-event access.

LatticesKit provides APIs for status, readiness, settings links, and requests.
The host or helper provides the user experience around those APIs.

Example:

```swift
import LatticesKit

let lattices = Lattices()
let readiness = lattices.readiness(for: [.sessionNavigation, .windowManagement])

if let firstMissing = readiness.missing.first {
    lattices.permissions.request(firstMissing)
}
```

If this code runs in `Scout Workspace Helper.app`, TCC belongs to Scout
Workspace Helper. If it runs in `Scout.app`, TCC belongs to Scout.

## Suggested Scout shape

For Scout, the preferred default is a Scout-owned helper that embeds
LatticesKit:

```text
Scout.app
├── product UI and orchestration
└── Scout Workspace Helper.app
    ├── LatticesKit
    ├── Accessibility and Screen Recording usage strings
    ├── global hotkeys / Input Monitoring if needed
    ├── window discovery, focus, tiling, and Spaces switching
    ├── tmux session launch, restart, detach, and navigation
    └── AX snapshots and controlled input
```

The helper should expose a narrow command surface to Scout:

- capability and permission readiness
- session name, launch, sync, restart, detach, kill
- window list, resolve, focus, tile, place
- Accessibility snapshot
- input actions that Scout explicitly requests

The helper should not expose Lattices as a separate product identity. From the
user's perspective this is Scout doing workspace control.

## Relationship to the daemon

The existing Lattices daemon remains useful for the standalone app, CLI,
scripts, diagnostics, and external automation.

It is not the embedded SDK boundary.

Embedded hosts should prefer LatticesKit in-process or in a product-owned
helper. A daemon-backed client can still exist as an adapter for tools that
explicitly want to talk to a running Lattices app.

## Relationship to HudsonKit

HudsonKit hosts can make the same choice:

- link LatticesKit directly when the host app should own permissions
- ship a `Hudson Helper` or `Hudson Workspace Helper` when the capability needs
  a long-lived helper lifecycle

The reusable artifact is still LatticesKit. The permission owner should always
be the embedding product or its branded helper.
