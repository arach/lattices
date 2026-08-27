# API

This page documents the current local agent protocol for `action`.

The protocol is intentionally small right now. It is enough to support native
health checks, permissions, window control, screenshots, and recording.

Primary source:

- [ActionAgentProtocol.swift](native/engine/CoreSources/ActionAgentProtocol.swift)

## Transport

- Protocol: WebSocket
- Default host: `127.0.0.1`
- Default port: `4319`
- Listener scope: IPv4 loopback only (`127.0.0.1`)

`status` advertises `protocolVersion`, authentication mode, and the path to a
per-agent-launch capability-token file. The token file and its parent directory
are user-only (`0600` / `0700`). Attention-taking methods require both the
advertised protocol version and the current token on the same persistent
connection that owns their drive lease.
The connection receive side remains armed while requests execute so an
operation-scoped cancellation can arrive during a gesture; response writes are
serialized and remain correlated by request id.

## Request Shape

```json
{
  "id": "uuid-string",
  "method": "capture.recordRegion",
  "params": {
    "output": "/tmp/example.mov"
  }
}
```

Fields:

- `id`: request id, defaults to a UUID in native clients
- `method`: string name from `ActionAgentMethod`
- `params`: flat string map

## Response Shape

```json
{
  "id": "uuid-string",
  "ok": true,
  "result": {
    "status": "finished"
  },
  "error": null
}
```

Fields:

- `id`: mirrors request id
- `ok`: success flag
- `result`: optional flat string map
- `error`: optional error string

## Methods

| Method | Purpose | Key Params |
|---|---|---|
| `ping` | basic liveness check | none |
| `status` | server metadata and supported methods | none |
| `permissions.snapshot` | current permission state | none |
| `permissions.request` | request or prompt for permissions | none |
| `settings.openAccessibility` | open Accessibility settings pane | none |
| `settings.openScreenRecording` | open Screen Recording settings pane | none |
| `app.activate` | bring an app forward | `bundleId` |
| `drape` / `raise-window` / `window-order` | host commands behind `action.stage.set` | color, level, subjects, optional bounds |
| `window.setFrame` | move/resize an app window | `bundleId`, `x`, `y`, `width`, `height` |
| `window.getFrame` | inspect current app window frame | `bundleId` |
| `drive.begin` | acquire a connection-owned drive lease | `agent`, `task`; attention mode also requires approval, run/workspace scope, `workspace.drag-file`, `system-pointer`, protocol version, and auth token |
| `drive.touch` | renew a connection-owned drive lease | `leaseId` |
| `drive.release` | release a connection-owned drive lease | `leaseId`, `outcome` |
| `workspace.dragFile` | resolve and drag the exact run fixture into the exact Scout drop zone | lease/run/workspace ids, fixture URL, Finder/Scout window identities, destination AX identifier, display bounds, protocol version, auth token |
| `workspace.cancelOperation` | cancel one in-flight semantic operation without affecting other clients | exact `leaseId`, `operationId`, protocol version, auth token |
| `capture.recordAppWindow` | record a target app window | `bundleId`, `output`, optional `stopFile`, `finishedFile`, `debugLog` |
| `capture.recordRegion` | record a bounded region | `x`, `y`, `width`, `height`, `output`, optional `fps`, `scale`, `stopFile`, `finishedFile`, `debugLog` |
| `capture.screenshotAppWindow` | screenshot a target app window | `bundleId`, `output` |
| `capture.screenshotRegion` | screenshot a bounded region | `x`, `y`, `width`, `height`, `output` |
| `capture.screenshotScreen` | screenshot the main display | `output` |

## Recording Contract

Recording methods have a special lifecycle:

- startup success means the recording path was accepted
- actual completion is represented by the finished marker file
- for debugging, pass `debugLog`

This matters because recording is currently performed by launching a real
`Action.app` probe instance rather than keeping the full recording lifecycle
inside the headless agent process.

## Workspace drag contract

`workspace.dragFile` is intentionally not a generic coordinate drag. It rejects
unknown parameters and accepts no source point, destination point, duration,
command, or executable input. Action resolves exactly one Finder item by AXURL
inside exactly one titled Finder window, and exactly one run-scoped AX drop-zone
identifier inside exactly one titled `app.openscout.scout` window. All resolved
frames and points must be inside the supplied workspace-display bounds.

An explicitly approved attention `drive.begin` atomically acquires the global
`system-pointer` resource and grants one `workspace.drag-file` capability. The
capability is bound to the connection, workflow run, and workspace, and is
consumed before the gesture. Connection closure cancels only that connection's
leases. During interpolation Action checks the lease stop signal; cleanup always
attempts mouse-up and restoration of the operator's saved pointer position.
`workspace.cancelOperation` signals an operation-specific stop file; the same
operation id is checked on every interpolation step. Lease release or connection
closure also signals both the lease and operation stop paths.
