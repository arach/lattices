# Recording

Recording is the most important runtime path in this project.

This page documents how it currently works and what assumptions should remain
true while the product is still being hardened.

## What Is Stable Right Now

The native recording path now succeeds for:

- bounded region recording
- app-window recording

The successful path produces:

- a `.mov` file
- a `.finished` marker file
- an optional debug log if `--debug-log` is supplied

## The Key Discovery

The main recording bug was not just a bad capture configuration.

The deeper issue was lifecycle ownership:

- `ScreenCaptureKit` recording was unreliable or crash-prone when hosted from the
  wrong runtime path
- a minimal real AppKit app lifecycle succeeded with the same capture logic

That is why the current solution uses a dedicated `recording-probe` mode inside
`Action.app`.

## Current Recording Path

For a region recording request:

1. host command accepts the request
2. host sends a recording method to the local agent
3. agent launches `Action.app` with `recording-probe`
4. probe runner creates a tiny AppKit window and starts recording
5. recording continues until the stop file appears
6. probe writes the finished marker and exits

Core files:

- [ActionRecordingProbeLauncher.swift](native/engine/CoreSources/ActionRecordingProbeLauncher.swift)
- [RecordingProbeAppRunner.swift](native/engine/Sources/RecordingProbeAppRunner.swift)
- [ActionHostMain.swift](native/engine/Sources/ActionHostMain.swift)

## Testing Recording

The wrapper script is:

```bash
bun run native:test:record
```

For lower-level testing, `run-app-host.sh` can call recording commands
directly.

## Important Caveat

The initial CLI reply usually means:

`recording started successfully`

It does **not** mean:

`recording completed successfully`

Completion is represented by the finished marker file.

## What To Preserve

- real AppKit lifecycle for actual recording work
- stop-file and finished-file based orchestration
- debug-log passthrough for probe runs
- clean app/agent separation even if the app is doing the final recording work

## What To Avoid

- pushing real recording back into a plain headless lifecycle
- assuming a WebSocket ack is equivalent to a completed recording
- removing the probe path before a better lifecycle-safe replacement exists
