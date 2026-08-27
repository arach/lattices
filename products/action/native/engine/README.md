# Native Engine

The native layer is the core of the current product.

It builds the signed `Action.app` bundle, the local `ActionAgent` helper, and the native command surfaces used for capture, permissions, WebKit, and guided review flows.

## Native Pieces

- `ActionHost` — the real AppKit app bundle
- `ActionAgent` — the local background automation service
- `ActionAgentCLI` — a thin native client that talks to the agent over WebSocket

This split is deliberate:

- AppKit and WebKit need a clean UI lifecycle
- capture and recording need lifecycle-safe native execution
- the local agent needs a durable orchestration process

## Build

From the repo root:

```bash
bun run native:app:build
```

Or directly:

```bash
native/engine/scripts/build-app.sh
```

The built bundle lands at:

`native/dist/Action.app`

## Health Check

Use the doctor wrapper before debugging anything capture-related:

```bash
bun run native:doctor
```

It:

- builds if needed
- signs the app
- verifies the signature
- reports Accessibility and Screen Recording status

## Native Commands

App host:

```bash
native/engine/scripts/run-app-host.sh status
```

Agent:

```bash
native/engine/scripts/run-agent.sh --port 4319
```

Agent CLI:

```bash
native/engine/scripts/run-agent-cli.sh status
native/engine/scripts/run-agent-cli.sh ping
native/engine/scripts/run-agent-cli.sh permissions.snapshot
```

## What The Native Layer Owns

- AppKit lifecycle
- launcher window and menus
- embedded WebKit surfaces
- permission UX
- ScreenCaptureKit capture and recording probe lifecycle
- native overlays / HUD
- window management and app activation

## Important Architectural Rule

Do not collapse the app and agent back into one fake headless runtime.

The current stability comes from keeping:

- UI-owned lifecycle in `Action.app`
- orchestration / transport in the local agent
- recording execution in lifecycle-safe probe mode

## Relevant Files

- `native/engine/Sources/ActionHostMain.swift`
- `native/engine/Sources/ActionLauncherController.swift`
- `native/engine/Sources/ActionLauncherViewModel.swift`
- `native/engine/CoreSources/ActionAgentRuntime.swift`
- `native/engine/Sources/RecordingProbeAppRunner.swift`
