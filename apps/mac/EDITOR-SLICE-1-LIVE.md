# Slice 1 live acceptance — stopped at launch safety gate

Tested source: `42406079`, branch `feat/editor-host-slice-1`, worktree
`/Users/arach/dev/lattices-editor-host-slice-1`. Preflight began
2026-10-02 02:38 UTC (October 1, Toronto).

## Result

**Live acceptance is pending, not passed.** The dev build/install is authorized,
but opening the Editor requires an app handover outside the permitted actions.
No app was launched or quit, no windows were manipulated, and no permissions,
LaunchAgent, release installation, or Lattices configuration were changed.
No screenshots were taken: there was no authorized running Editor to capture.
The existing release process was left running, not replaced with the dev app.

## Launch blockers (source evidence, not observed Editor bugs)

1. The release app was already running: PID `93605`, executable
   `/Applications/Lattices.app/Contents/MacOS/Lattices`.
   `apps/mac/Sources/AppShell/AppDelegate.swift:30-37` refuses a second Lattices
   process. `apps/mac/Sources/Core/Input/AppInputLease.swift:11-13` treats both
   release and dev bundle IDs as peers.
2. `bin/lattices-dev:337-339` would quit the existing app when launching dev;
   `bin/lattices-dev:324-326` targets both bundle IDs and all Lattices processes.
   That handover was not authorized, so neither `launch` nor `restart` was run.
3. A normal dev launch calls `LayerStage.shared.restoreParked(reason: "launch")`
   at `apps/mac/Sources/AppShell/AppDelegate.swift:78`. Quit and signal handling
   also call it at lines 166 and 157. The implementation at
   `apps/mac/Sources/Core/Workspace/LayerStage.swift:479-489` can restore window
   positions and persist staging state. That conflicts with the explicit ban on
   staging, moving windows, and configuration writes. No bypass was added and
   no staging function or `keepRebinds` was invoked.

Arach must authorize a safe app handover and a side-effect-free acceptance
startup path (or explicitly revise the startup restrictions) before proceeding.
Stopping the release app alone does not resolve the normal dev startup effects.

## Acceptance checklist

| Check | Status | Evidence |
|---|---|---|
| 1. Menu opens Editor; panels; Terminal hidden; hide Chat reflows | **Pending** | Not launched due to safety gate |
| 2. Preview matches native membership | **Pending** | No simultaneous live projection; no mismatch assessment possible |
| 3. Row↔Source selection; duplicate ambiguity | **Pending** | No UI interaction. Read-only inspection found 8 layers and no duplicate whole-project entries within a layer; live duplicate case unavailable |
| 4. Reopen preserves layout; narrow stacks without overwriting wide layout | **Pending** | No window opened/resized/closed |
| 5. No flash or blank page; WebKit console clean | **Pending** | No Editor page or console session exists; static code is not evidence of a clean console |
| 6. workspace.json mtime and SHA-256 identical | **Pass** | mtime_ns `1790863638274089681`; SHA-256 `08371da3319997e03e858a71a55a736e77f421403078d8eca252082a728a3edc`; identical before/after |

## External assign — human step still required

Do not alter files to manufacture an event. Once the safe launch gate is
resolved, Arach should keep Editor visible and manually assign one currently
unassigned, existing window to an existing layer using the everyday menu-bar
assignment UI. Watch Source, Preview and History for the same change within
about a second, without reload or flicker.

**Exact verified fallback in this revision:** focus the existing window intended
for the *already active* layer, then press **⌘⌥T** once. Do not switch or activate
a layer first. `HotkeyBootstrap.swift:57` invokes
`LayerEditing.swift:181-198`, which adds that window to the current layer and
shows the bezel. This is an intentional human config write, not an action taken
by this test. It belongs after the no-write checksum checkpoint. The source
review did not locate a standalone menu-bar item named Assign in this revision;
its precise menu path remains unverified rather than invented here.

## Build and evidence

- Command: `bin/lattices-dev build` (not `install`, `launch` or `restart`).
- Log: `/tmp/lattices-editor-slice-1/live/dev-build.log`.
- Requested dev destination: `~/Applications/dev/Lattices/Lattices.app`.
- Build/install result: **passed**, exit 0. Installed dev bundle identity
  `dev.lattices.app.dev`, source revision `42406079`, verified from Info.plist.
  The app was not launched. Existing compiler warnings were emitted.
- Build identity and workspace before/after records: `EditorSlice1LiveEvidence/`.
- No changes were made to the implementation under test.
