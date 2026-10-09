# Agent layer

An agent layer lets Action drive an app without taking the user's screen.

`action.layer.open` moves the app's windows onto a private virtual display that sits off in a corner of the display arrangement. The user does not see that display. A small floating picture-in-picture panel on the user's screen streams it.

```json
{ "bundleId": "com.apple.calculator", "width": 1280, "height": 800, "pip": true }
```

The app doesn't have to be running or have a window. Pass `url` to start on a page:

```json
{ "bundleId": "com.apple.Safari", "url": "news.ycombinator.com" }
```

## What it does

- Creates a `CGVirtualDisplay` and moves the subject app's windows onto it. The original frame of each window is recorded.
- `windowId` (the `kCGWindowNumber`) or `windowTitle` (a case-insensitive substring) moves only the matching windows. Use it to borrow one window of an app the user is also in, such as a browser.
- Starts one ScreenCaptureKit stream on the layer display and keeps it running for the layer's life. The viewer, snapshots and recordings all come off that stream (see [Feed](#feed)).
- Launches the subject in the background if it isn't running, and asks an app with no windows for one (the reopen a Dock click sends). Nothing comes to the front.
- `url` (a URL, a bare host read as `https`, or a file path) opens in the subject without activating it, once its windows are on the layer. It needs `bundleId` or `pid`, and can't be combined with `windowId` or `windowTitle`.
- Adopts windows the subject opens while the layer is up, such as a `cmd+n` window, a pop-up, or an `open-app` with `input.url`. They move onto the layer as they appear, cascaded. A layer that borrowed one window by `windowId` or `windowTitle` adopts nothing more.
- Shows the PiP viewer unless `pip` is `false`.
- Writes a state file: display id, global bounds (top-left origin, points), PiP state, and the moved windows with their original frames.
- Keeps one layer at a time. Opening a second layer closes the first, so its windows go back before the new app moves.

## Primitives

The layer's own tools are the short way to work it. Look, then act on what you saw:

```
action.layer.open     { bundleId: "com.apple.Safari", url: "news.ycombinator.com" }
action.layer.snapshot {}                                  → p.png, 950×560
action.layer.click    { x: 475, y: 196 }                  pixels in that snapshot
action.layer.click    { label: "new" }                    or a control by its label
action.layer.type     { text: "lobste.rs\n" }             a trailing \n submits
action.layer.press    { key: "cmd+l" }
action.layer.drag     { from: [95, 224], to: [570, 252] }
action.layer.scroll   { x: 475, y: 280, dy: -600 }
action.layer.close    {}
```

Points are pixels in the last `action.layer.snapshot` image, read through its crop and scale, so an agent never adds the layer's origin or works out the display's scale. `space: "layer"` takes points on the layer display instead. A point outside the last snapshot is an error, and so is a point with no snapshot taken yet.

Each primitive runs as an `action.act.execute` act, so the routing below applies, and returns how it landed (`host`), the lease it ran under, and a fresh snapshot taken a moment after the act (`look: false` skips it). A lease is taken for the caller when none is passed.

## Blink acts

While a layer is up, `action.act.execute` routes these acts as blink acts:

| Act | Host command | When |
|---|---|---|
| `click` with a point | `blink-click` | the point is on the layer display |
| `type` | `blink-type` | no accessibility label path applies |
| `press-key` | `blink-key` | always |
| `drag` | `blink-drag` | both points are on the layer, and no `filePath` |
| `scroll` | `blink-scroll` | the point is on the layer |

Accessibility comes first. A target with a bundle id and label is pressed or set through accessibility and never blinks. `blink-click` hit-tests its point before it touches the pointer: if the element there is a button, checkbox, radio, pop-up, menu item, disclosure triangle, link or tab that takes `AXPress`, it is pressed and the result says `via=ax`. A text field, text area, combo box or search field there is focused through accessibility instead of clicked into. Nothing moves and focus does not change.

`blink-type` works the same way. It inserts the text at the caret of the app's focused text field through accessibility (`via=ax`), and only borrows focus for keystrokes (`via=keys`) when the field doesn't take it, is secure, or a `delayMs` cadence is requested. Web fields usually take keystrokes. When the field's value is readable, the blink holds focus until the text shows up in it (`via=keys verified`), because a web view consumes keys in its own content process after the app's main loop has already drained. A trailing newline in `type` text (`"lobste.rs\n"`) splits off: the text goes in through accessibility and the field is submitted with `AXConfirm`, a Return that moves nothing. `press-key` tries accessibility too: a chord that is a menu item's shortcut (`cmd+l`, `cmd+n`) presses that menu item (`via=ax menu="Open Location…"`), and a bare Return or Escape in a text field confirms or cancels it. Anything else borrows focus for the keystroke (`via=keys`).

`press-key` takes a chord in `input.key`, written however the agent reads it: `"return"`, `"cmd+l"`, `"Cmd-Shift-T"`, `"⌘⇧T"`, `["cmd", "l"]` in `input.keys`, or `key` plus `input.modifiers`. Aliases such as `enter`, `esc`, `backspace` and `ArrowDown` map to the host's names. An unknown key is an error that points at `type`, never text typed one character at a time.

The pointer is the fallback: no pressable element at the point, a requested `holdMs`, or `--pointer` on the host command. A pointer blink saves the cursor position and the frontmost app, clicks, and restores both within tens of milliseconds. Its result says `via=pointer`.

`type` and `press-key` land in the app's focused window. If that window is off the layer, the blink raises the app's layer window first, without activating the app, and refuses if focus still isn't on the layer. Keystrokes never reach a window on the user's screen.

`type` and `press-key` target `input.bundleId` or `input.pid` if given, else the layer's app. Accessibility paths (`press-accessibility-element`, `set-accessibility-value`) do not change. A click outside the layer display uses `click-point`.

Drag and scroll have no accessibility equivalent and always use the pointer. It leaves the user's screens for the length of the gesture (200 ms for a drag by default; an instant for a scroll) and comes back. Scroll wheel events activate nothing. A drag's mouse-down activates the app it lands in for up to a second, and focus is handed back afterwards.

Blink acts report the `blink` tier. A background drive lease allows them. They do not show the pointer-focus countdown.

## Feed

The layer captures its own display, not the subject app. A stream that targets an app makes macOS badge that app's windows as shared, and the badge is drawn into the window, so it would show in every frame. The framing to the subject's windows happens downstream, by crop. The stream only delivers frames when something on the layer changes, so an idle layer costs next to nothing.

- **Viewer.** The PiP grows out of the screen corner on its first frame and frames the subject's windows, following them as they move and resize. Drag moves it; double-click enlarges it to a large centred view, and double-click again puts it back. Hiding it with × leaves the layer running; `layer pip` / `action.layer.pip` brings it back.
- **State.** One dot in the viewer's bottom-right corner: solid coral while the agent can act, breathing while a take records, hollow while paused.
- **Marks.** Blink acts don't move the pointer, so the host posts where each one landed and the viewer rings it: a circle for a click, an outline around the focused field for typing and keys.
- **Note.** The latest `action.drive.note` shows along the bottom edge for about 12 seconds.
- **Snapshot.** `layer snapshot` / `action.layer.snapshot` writes a PNG from the latest frame: the subject's windows by default, one window with `windowId`, or the whole layer with `full`. Nothing is captured on request, so it answers in tens of milliseconds. `unchangedMs` is how long the layer has been still, not how stale the picture is.
- **Recording.** `layer record start|stop` / `action.layer.record` adds a recording output to the running stream, so the take starts on the next frame. It records the whole layer display at its native size. One take at a time; closing the layer finishes a take in progress.

## Operator controls

Hovering the viewer shows four controls:

- **Go to owner.** Focuses whatever opened the layer. Action records the opener's process chain at `open` (`--owner-pids`), activates the nearest app in that chain, and otherwise asks Lattices (`terminals.search`, then `windows.focus`) which terminal window shows it. An agent under a daemonized multiplexer has no app in its chain, so this needs the Lattices app running; if nothing resolves, the viewer beeps.
- **Pause / resume.** While paused, `state.json` has `"paused": true` and `action.act.execute` refuses with a message saying so.
- **Take over.** Ends the layer, puts the windows back, and leaves `handoff.json`. Until the next `layer open` or `layer close`, `action.act.execute` refuses and says the operator took over.
- **×.** Hides the viewer.

Requests go through `control.request.json` next to the state file and a `SIGUSR2`; the reply lands in `control.reply.json`.

## Lifetime

`action.layer.close` is the intended teardown. It creates the stop file and waits for the layer to put the windows back and exit. Windows that were opened after the layer went up (`born` in the state file) never sat on the user's screen, so they are closed instead of moved there. One that asks before closing (unsaved changes) stays open and goes back to the frame it appeared at. If the layer does not exit, Action sends `SIGTERM`.

The layer also tears down when its owner dies:

- **MCP.** The layer watches the MCP server (`--parent-pid`) and restores the windows if the server exits.
- **CLI.** The CLI exits once the layer is up, so the layer is detached. Run `layer close` to take it down when the work is done.

A detached layer doesn't wait for `layer close` forever. It also comes down when:

- **Its owners exit.** Every process in the opener's chain that was alive at `open` has exited.
- **It goes idle.** 30 minutes pass with no act, no snapshot or recording request, and no use of the viewer. A recording in progress keeps the layer up. Pass `--idle-timeout <seconds>` to the host to change the lease; `0` turns it off.

Either way the windows go back first, as with `layer close`.

`layer status` reports the live layer. If the recorded process is gone, status removes the stale files and reports the layer as inactive.

State lives in `~/Library/Application Support/Action/agent-layer/`.

## Surfaces

- MCP: `action.layer.open`, `action.layer.close`, `action.layer.status`, `action.layer.pip`, `action.layer.snapshot`, `action.layer.record`, and the primitives `action.layer.click`, `action.layer.type`, `action.layer.press`, `action.layer.drag`, `action.layer.scroll`
- CLI: `bun packages/cli/src/main.ts layer open|close|status|pip|snapshot|record`

## Requirements and limits

- The feed needs Screen Recording for Action. Without it the layer still works (windows move, blink acts land), but there is no viewer, snapshot or recording; the layer's `layer.log` says `feed failed`. Recording needs macOS 15.
- The display touches the bottom-right-most display only at its corner. A pointer pushed exactly through that corner can still cross onto it.
- A pointer blink click on another app activates that app for a moment before focus goes back. The menu bar can flicker for that moment.
- Blink acts refuse targets that aren't on an agent layer: a point off the layer, or an app with no window on it. `--any-display` lifts that for tests.
- If the layer process is killed with `SIGKILL`, the display goes with it and macOS moves its windows to the main display rather than to where they were.
