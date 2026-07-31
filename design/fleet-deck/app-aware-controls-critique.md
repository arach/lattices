# App-aware deck controls — direction critique

Requested by fleetdeck-coordinator (fleet-deck channel, ask f-ms86kqof-4brj). Brief: find what is
wrong with "detect the frontmost app, swap the deck's buttons" + spatial minimap, before it is built.

## The structural flaw first: frontmost is the wrong dispatch key

The proposal binds both *which buttons show* and *what a press does* to the Mac's frontmost app.
Surfacing on frontmost is fine. **Dispatching on frontmost is not**, and it is wrong in a way
specific to this product.

The race: the deck snapshot says Chrome is frontmost; the operator taps "next tab"; between
snapshot and tap, focus moved — and on this Mac, focus moves *by itself*, because the product's
premise is autonomous agents running unattended, opening windows, spawning dialogs. On an ordinary
remote control, focus changes when the user changes it. Here, frontmost is the least stable state
on the machine, and the operator is by definition not looking at it. A keystroke synthesized at
the focused app (`CompanionKeyboardController.typeText`, dispatch via `frontmostWindowTarget()` —
`apps/mac/Sources/Core/Companion/LatticesDeckHost.swift:423,1060,1095,1333`) lands wherever focus
is *now*. Misdirected input on an unwatched machine is silent and destructive — picture ⌘W arriving
in the wrong app.

Rule: every app-aware action must carry the target's identity (wid / session name) captured from
the snapshot the operator was actually looking at. The Mac verifies the target still exists —
raising it first if needed — or refuses and reports. If the deck can't name the target, the button
doesn't exist.

Side note: the snapshot has two notions of "active app" (`layout.frontmostWindow.appName` vs
`desktop.activeAppName`, built at `LatticesDeckHost.swift:631` with its own fallback chain). They
can disagree. Pick one authority before building anything that swaps on it.

## 1. Maintenance trap — split the proposal into three tiers

- **Tier A — platform conventions, not per-app contracts.** ⌘1–⌘8, ⌘9-last-tab, ⌘T, ⌘⇧[/],
  ctrl-tab are macOS-wide tabbing conventions shared by Chrome, Safari, iTerm, Slack, Ghostty.
  One "tabbed app" control set, zero per-app code, no treadmill. But note: fire-and-forget
  keystrokes **cannot degrade honestly**, because the deck has no read-back — the snapshot carries
  no tab state (`.tab` declared at `swift/Sources/DeckKit/DeckRuntimeSnapshot.swift:279`, never
  emitted; only `.task/.application/.window/.session` at `LatticesDeckHost.swift:947–1018`).
  Success is unverifiable from the iPad. Tier A is tolerable only for low-stakes, idempotent-ish
  actions, and only with target-carrying dispatch per the rule above.
- **Tier B — apps with a real automation API.** tmux (CLI/control mode), iTerm2 (Python/
  AppleScript API), Chrome/Safari (scriptable tab enumeration). Readable state means the deck can
  display truth and confirm effects. This is per-app work, but it's a contract with an API —
  versioned, testable, fails loudly — not a contract with someone else's UI. This tier is where
  app-awareness earns its keep.
- **Tier C — apps with neither** (Ghostty: no scripting interface, minimal AX). Nothing to build
  on. Skip entirely rather than faking it with keystrokes.

The treadmill only starts if Tier B work is done by synthesizing keystrokes against UI assumptions.
Smallest set that earns per-app support: **tmux** (the daemon already indexes it — `terminals.search`,
`[lattices:session-name]` window tags) and **one scriptable browser** for tab lists. Stop there.

## 2. "Jump to the seventh tab" is a demo

The ordinal is only knowable by looking at the Mac's screen. If the operator can see the screen,
they are within reach of a keyboard, and ⌘7 beats picking up an iPad. If they can't see the screen
— the app's entire premise — the ordinal is unknowable and the button is dead weight. The feature
does not survive the blind case *as specified*.

The version that survives: build the `.tab` **producer** and put tab *titles* in the switcher, so
the iPad is the source of tab knowledge rather than requiring it. Tap the tab by name; "seventh"
becomes an implementation detail of a list row, not a feature. The protocol slot has been waiting
for exactly this. Cut ordinal voice/buttons outright.

## 3. Minimap: situational awareness yes, precision navigation no

For *finding a window you can name*, the honest ranking at 15 windows / 2 displays is:
text list > voice > minimap. Spatial memory covers the three or four deliberately placed windows —
which are precisely the ones easiest to name, so the minimap's theoretical win ("know where, not
what") is thinnest exactly where it's claimed. The rest of a 15-window desktop renders as
overlapping slivers; a tap on 8pt targets (Apple floor: 44pt) is ambiguous between three stacked
rectangles, and ambiguity in a *focus* action means focusing the wrong window on a machine you
can't see.

What the minimap uniquely provides is **state, not navigation**: "what does the Mac look like right
now — did the agent open something, did a dialog appear." A list can't show that; for this product
it's genuinely valuable, and it's nearly free because it already exists (`LatsLayoutSurface.previewCard`,
tap-to-focus working, buried in the legacy surfaces screen). Keep it glanceable, coarse. Where a
tap is ambiguous, disambiguate *into* the list (pop the windows near the tap point) rather than
pretending the map has precision it lacks. Do not invest in zoom, per-window labels at strip size,
or making it the primary switcher. (Adjacent: grieg holds the design ruling on trackpad/minimap
fusion — this argues against map-as-trackpad, but that ruling is theirs.)

## 4. Multiplexer: only address layers that have an address

"Which layer does the button hit" has one clean answer: a button may only target a layer with an
addressable API, and it names its target explicitly.

- **tmux layer**: never send Ctrl-b keystrokes through the emulator through the window system. The
  Mac runs `tmux select-window -t <session>:<n>` against the socket. Unambiguous by construction,
  works even when the Ghostty window isn't focused, and `list-windows` gives read-back so the deck
  shows truth. tmux is the *good* case in the whole proposal.
- **Emulator layer** (Ghostty splits/tabs): no API → no buttons, deliberately, until one exists.
- **OS window layer**: already has first-class deck controls (focus by wid, layout actions).

The user knows the target because the strip is **labeled with and pinned to a session name**, not
because they reason about focus. Framing rule: if a control's effect depends on state the iPad
cannot display, the control is forbidden.

## 5. Cut list and build-order correction

Cut outright:
- Frontmost-swapping as **dispatch** semantics (keep it only for choosing which set to surface).
- Ordinal tab jumping, voice or button.
- Anything Ghostty-specific.
- A generic "app profiles" framework/config format. Build exactly two concrete sets — tabbed-app
  conventions with target-carrying dispatch, and a tmux session strip — and abstract only if a
  third genuinely appears.

Build-order correction: **read path before write path.** Every deck surface that works today
(windows, sessions, tasks) is snapshot-backed; the proposal jumps straight to write-only buttons
acting on state the iPad can't see. First make the Mac emit tab/tmux state into the snapshot
(the `.tab` producer, a tmux session feed from the daemon's existing index). Buttons that act on
what the iPad already displays are a small, safe increment. Buttons acting on invisible state are
the entire risk of this feature.
