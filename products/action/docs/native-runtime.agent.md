# Native Runtime (Agent)

## Ownership Model

### `Action.app`

Owns:

- AppKit lifecycle
- launcher UI
- WebKit windows
- menus and app identity
- recording probe mode

Primary files:

- [ActionHostMain.swift](native/engine/Sources/ActionHostMain.swift)
- [ActionLauncherController.swift](native/engine/Sources/ActionLauncherController.swift)
- [ActionLauncherViewModel.swift](native/engine/Sources/ActionLauncherViewModel.swift)

### Agent Runtime

Owns:

- WebSocket listener
- request dispatch
- automation method surface
- launching the recording probe

Primary files:

- [ActionAgentRuntime.swift](native/engine/CoreSources/ActionAgentRuntime.swift)
- [ActionAgentClient.swift](native/engine/CoreSources/ActionAgentClient.swift)
- [ActionAgentCommandBridge.swift](native/engine/Sources/ActionAgentCommandBridge.swift)

## Recording Rule

- Do not implement real recording directly in the headless agent path.
- Use [ActionRecordingProbeLauncher.swift](native/engine/CoreSources/ActionRecordingProbeLauncher.swift).
- The probe launches `Action.app` with `recording-probe` args.
- The probe runner performs the actual `WindowRecorder` call.

## WebKit Rule

- WebKit belongs to the app lifecycle.
- If a change touches browser windows, inspect the AppKit entry path before changing configuration.

## Debug Order

1. Confirm the signed app build exists.
2. Confirm whether the failure is app lifecycle, agent transport, or probe execution.
3. For recording, inspect `.mov`, `.finished`, and debug log together.
4. Do not trust initial `"recording"` replies as proof of completion.
