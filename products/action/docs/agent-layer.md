# Agent layer

An agent layer lets Action drive an app without taking the user's screen.

`action.layer.open` moves the app's windows onto a private virtual display that sits off in a corner of the display arrangement. The user does not see that display. A small floating picture-in-picture panel on the user's screen streams it.

```json
{ "bundleId": "com.apple.calculator", "width": 1280, "height": 800, "pip": true }
```

## What it does

- Creates a `CGVirtualDisplay` and moves the subject app's windows onto it. The original frame of each window is recorded.
- `windowId` (the `kCGWindowNumber`) or `windowTitle` (a case-insensitive substring) moves only the matching windows. Use it to borrow one window of an app the user is also in, such as a browser.
- Starts one ScreenCaptureKit stream on the layer display and keeps it running for the layer's life. The viewer, snapshots and recordings all come off that stream (see [Feed](#feed)).
- Shows the PiP viewer unless `pip` is `false`.
- Writes a state file: display id, global bounds (top-left origin, points), PiP state, and the moved windows with their original frames.
- Keeps one layer at a time. Opening a second layer closes the first, so its windows go back before the new app moves.

## Blink acts

While a layer is up, `action.act.execute` routes these acts as blink acts:

| Act | Host command | When |
|---|---|---|
| `click` with a point | `blink-click` | the point is on the layer display |
| `type` | `blink-type` | no accessibility label path applies |
| `press-key` | `blink-key` | always |

Accessibility comes first. A target with a bundle id and label is pressed or set through accessibility and never blinks. `blink-click` hit-tests its point before it touches the pointer: if the element there is a button, checkbox, radio, pop-up, menu item, disclosure triangle, link or tab that takes `AXPress`, it is pressed and the result says `via=ax`. A text field, text area, combo box or search field there is focused through accessibility instead of clicked into. Nothing moves and focus does not change.

`blink-type` works the same way. It inserts the text at the caret of the app's focused text field through accessibility (`via=ax`), and only borrows focus for keystrokes (`via=keys`) when the field doesn't take it, is secure, or a `delayMs` cadence is requested. Web fields usually take keystrokes. When the field's value is readable, the blink holds focus until the text shows up in it (`via=keys verified`), because a web view consumes keys in its own content process after the app's main loop has already drained. `press-key` has no accessibility equivalent and always borrows focus.

The pointer is the fallback: no pressable element at the point, a requested `holdMs`, or `--pointer` on the host command. A pointer blink saves the cursor position and the frontmost app, clicks, and restores both within tens of milliseconds. Its result says `via=pointer`.

`type` and `press-key` land in the app's focused window. If that window is off the layer, the blink raises the app's layer window first, without activating the app, and refuses if focus still isn't on the layer. Keystrokes never reach a window on the user's screen.

`type` and `press-key` target `input.bundleId` or `input.pid` if given, else the layer's app. Accessibility paths (`press-accessibility-element`, `set-accessibility-value`) do not change. Drag and scroll do not blink. A click outside the layer display uses `click-point`.

Blink acts report the `blink` tier. A background drive lease allows them. They do not show the pointer-focus countdown.

## Feed

The layer captures its own display, not the subject app. A stream that targets an app makes macOS badge that app's windows as shared, and the badge is drawn into the window, so it would show in every frame. The framing to the subject's windows happens downstream, by crop. The stream only delivers frames when something on the layer changes, so an idle layer costs next to nothing.

- **Viewer.** The PiP grows out of the screen corner on its first frame and frames the subject's windows, following them as they move and resize. Hovering shows a × that hides it; the layer keeps running. `layer pip` / `action.layer.pip` brings it back.
- **Snapshot.** `layer snapshot` / `action.layer.snapshot` writes a PNG from the latest frame: the subject's windows by default, one window with `windowId`, or the whole layer with `full`. Nothing is captured on request, so it answers in tens of milliseconds. `unchangedMs` is how long the layer has been still, not how stale the picture is.
- **Recording.** `layer record start|stop` / `action.layer.record` adds a recording output to the running stream, so the take starts on the next frame. It records the whole layer display at its native size. One take at a time; closing the layer finishes a take in progress.

Requests go through `control.request.json` next to the state file and a `SIGUSR2`; the reply lands in `control.reply.json`.

## Lifetime

`action.layer.close` is the intended teardown. It creates the stop file and waits for the layer to put the windows back and exit. If the layer does not exit, Action sends `SIGTERM`.

The layer also tears down when its owner dies:

- **MCP.** The layer watches the MCP server (`--parent-pid`) and restores the windows if the server exits.
- **CLI.** The CLI exits once the layer is up, so the layer is detached. Run `layer close` to take it down.

`layer status` reports the live layer. If the recorded process is gone, status removes the stale files and reports the layer as inactive.

State lives in `~/Library/Application Support/Action/agent-layer/`.

## Surfaces

- MCP: `action.layer.open`, `action.layer.close`, `action.layer.status`, `action.layer.pip`, `action.layer.snapshot`, `action.layer.record`
- CLI: `bun packages/cli/src/main.ts layer open|close|status|pip|snapshot|record`

## Requirements and limits

- The feed needs Screen Recording for Action. Without it the layer still works (windows move, blink acts land), but there is no viewer, snapshot or recording; the layer's `layer.log` says `feed failed`. Recording needs macOS 15.
- The display touches the bottom-right-most display only at its corner. A pointer pushed exactly through that corner can still cross onto it.
- A pointer blink click on another app activates that app for a moment before focus goes back. The menu bar can flicker for that moment.
- Blink acts refuse targets that aren't on an agent layer: a point off the layer, or an app with no window on it. `--any-display` lifts that for tests.
- If the layer process is killed with `SIGKILL`, the display goes with it and macOS moves its windows to the main display rather than to where they were.
