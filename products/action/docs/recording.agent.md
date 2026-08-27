# Recording (Agent)

## Status

- Region recording: working through app-backed probe path
- App-window recording: working through app-backed probe path
- Success artifacts: `.mov` + `.finished`

## Control Flow

1. caller invokes `record-region` or `record-app-window`
2. host sends request to agent
3. agent calls [ActionRecordingProbeLauncher.swift](native/engine/CoreSources/ActionRecordingProbeLauncher.swift)
4. launcher runs `open -n Action.app --args recording-probe ...`
5. probe runner uses [RecordingProbeAppRunner.swift](native/engine/Sources/RecordingProbeAppRunner.swift)
6. probe uses `WindowRecorder` inside a real AppKit lifecycle

## Files To Read

- [ActionHostMain.swift](native/engine/Sources/ActionHostMain.swift)
- [ActionAgentRuntime.swift](native/engine/CoreSources/ActionAgentRuntime.swift)
- [ActionRecordingProbeLauncher.swift](native/engine/CoreSources/ActionRecordingProbeLauncher.swift)
- [RecordingProbeAppRunner.swift](native/engine/Sources/RecordingProbeAppRunner.swift)

## Debugging Rules

- Initial `"recording"` response is startup ack only.
- Finished marker is the completion signal.
- If present, `--debug-log` should be inspected before changing capture configuration.
- If recording fails again, validate lifecycle assumptions before tweaking `ScreenCaptureKit` settings.

## Invariants

- Recording implementation should stay app-backed until a safer replacement exists.
- Probe mode must remain available from the signed app bundle.
- App lifecycle correctness is a recording dependency, not an optional detail.
