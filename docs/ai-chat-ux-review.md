# AI Chat Assistant — UI/UX Review (review-only)

Surface reviewed: `apps/mac/Sources/Core/Pi/`
(PiChatUI.swift, PiChatDock.swift, PiWorkspaceView.swift, PiAuthPromptCard.swift,
PiInstallCallout.swift, PiProviderSetupCallout.swift, PiChatSession.swift)

Date: 2026-06-02
Scope: visual hierarchy, spacing, transcript readability, composer ergonomics,
empty/loading/error states, macOS idioms, accessibility, usefulness vs. opacity.

Severity scale: HIGH (blocks goals) · MEDIUM (visible friction) · LOW (polish).

---

## HIGH

### 1. User and assistant share the same avatar glyph → speaker confusion
**Evidence.** `PiChatUI.swift:35–55` defines `LatticesMark`; `LatticesMarkAvatar`
is reused for the assistant header (`PiWorkspaceView.swift:52`), the assistant
bubble (`PiChatUI.swift:487`), and the user's bubble (`PiChatUI.swift:463`).
The user message row shows the Lattices brand mark on the right at 28pt with a
muted tint — visually the same family as the assistant avatar. Header text
literally reads "Assistant" on the assistant side, but the user side has no
label. On a quick glance, you cannot tell which side is talking.

**Direction.** Drop the avatar from the user bubble (right-aligned text + small
initial chip is enough), or use a clearly different glyph (e.g. `person.crop.circle`)
at lower opacity. Keep `LatticesMarkAvatar` for assistant + header + empty state
hero only — that is its semantic role.

### 2. Composer send key is wrong for multi-line input
**Evidence.** `PiChatUI.swift:1246–1261` binds `.onSubmit` directly to
`session.sendDraft()` with no modifier check. The composer uses
`TextField(axis: .vertical)` with `lineLimit(1...style.composerLineLimit)`.
The footer hint reads "↩ send" (`PiChatUI.swift:1218`). There is **no
`keyboardShortcut`** anywhere in the chat surface (verified by grep across
`Core/Pi/*.swift`).

**Direction.** Bind the send button to `.keyboardShortcut(.return, modifiers: .command)`,
change the hint to "⌘↩ send", and gate plain-Enter to single-line case only.
Add `Esc` to clear the draft or cancel an in-flight send.

### 3. Accessibility is largely absent
**Evidence.** Across the entire chat surface, there is exactly **one**
`accessibilityLabel` (`PiChatUI.swift:1397` on `PiChatWorkingIndicator`) and
**one** `accessibilityHidden(true)` (on the Lattices mark). No icon buttons
have labels: the dock close (`PiChatDock.swift:103`), the gear in
`PiWorkspaceView.swift:130`, the code-block copy button (`PiChatUI.swift:872`),
and the footer gear (`PiChatDock.swift:386`) all read as "button" only to
VoiceOver. Hit targets: the 6pt traffic-light dots in `PiChatCodeBlock`
(`PiChatUI.swift:855–859`), the 6pt status pulses, the 22×22 footer icon
button (`PiChatDock.swift:444`), and the 22×22 send button are all below the
24pt minimum. Dynamic Type is not supported — fonts are hardcoded point
sizes via `Typo.body(13.5)`, `Typo.body(14)` (`PiChatStyle`).

**Direction.** Add `accessibilityLabel` to every icon-only button. Group the
empty-state starters under a labelled header (`.accessibilityElement(children: .combine)`).
Bump minimum hit target to 24×24. Replace hardcoded point sizes with
`Font.system(.body, design: .rounded)` and apply
`.dynamicTypeSize(.medium ... .accessibility3)` at the root.

### 4. Usefulness is opaque — header copy is vague, no capability surface
**Evidence.** `PiWorkspaceView.swift:60` says "Settings, layout help, planning,
and debugging in one thread." The empty state at `PiChatUI.swift:256–263`
shows four starter cards, which is good, but the running state offers no
indication of: which model is active, which tools are available, rate limits,
cost, or how to attach files/screenshots. The status pill (`PiWorkspaceView.swift:75`)
flips between "Ready / Streaming / Thinking / Tool · read" but the user cannot
act on it. The four starter prompts hint at gesture/file/screen/planning but
don't reveal tool inventory.

**Direction.** Add a discoverable affordance — a `?` or `Tools` button in the
header — that opens a one-sheet listing: current provider + model, available
tools (`read`, `bash`, `search`, `list`, `web`, `voice`), and a token/cost
counter. Add a "What can I do?" prompt to the empty state as a 5th card.

---

## MEDIUM

### 5. Three parallel setup states compete visually
**Evidence.** `PiInstallCallout.swift` (install) uses `Palette.kill` red border.
`PiProviderSetupCallout.swift` (provider) uses its own card layout. `PiAuthPromptCard.swift`
(auth) uses `Palette.detach` yellow. All three render in roughly the same slot
(transcript area or composer slot) but with different border treatments,
padding, and copy tone. The user sees: red install card → yellow provider card
→ yellow auth card → composer. Three different visual languages for "you need
to do something."

**Direction.** Consolidate into a single `PiSetupCard` with `Kind: .install | .provider | .auth`
and a shared layout: status dot · eyebrow label · body · primary action · secondary
action. Use `Palette.kill` for install, `Palette.detach` for both provider and
auth, and unify spacing/padding to `compact` and `expanded` modes only.

### 6. Streaming state is over-decorated
**Evidence.** `PiChatUI.swift:498–541` (assistant bubble) stacks: pulsing
avatar (1.18× stroke), `LIVE` badge, `PiChatStreamCursor`, left-edge 2pt
gradient bar, inner radial gradient overlay, and a 0.28s background
animation. Concurrently: `PiChatToolChip` pulses (1.4s),
`PiChatStreamCursor` pulses (0.85s), `PiChatWaveDots` animates
(30fps TimelineView), `PiChatWorkingIndicator` has its own dot pattern.
That's 4+ simultaneous animations per streaming turn. On a 60Hz display the
bubble never settles.

**Direction.** Pick one dominant streaming affordance — the left-edge bar is
the strongest. Demote `LIVE` to small caps next to the assistant name and
drop the inner radial gradient. Keep the cursor and one pulse. Document
"max 1 ambient animation per scene" in the chat style guide.

### 7. Provider/auth flow triplicated across Dock, Workspace, and auth card
**Evidence.** `PiChatDock.swift:205–325` (authPanel) and `PiChatDock.swift:429–458`
(providerSettingsBar) and `PiWorkspaceView.swift:125–158` (providerSettingsPrompt)
and `PiAuthPromptCard.swift` are four overlapping implementations of "tell
the user to connect a provider / drive the auth flow." Adding a field
(provider description, secondary CTA, warning) requires touching all four.

**Direction.** Extract a `PiAuthPanel` with `style: .workspace | .dock` and
the existing `compact: Bool` flag, used in all three call sites. Keep
`PiAuthPromptCard` as a child when a `pendingAuthPrompt` is present.

### 8. Transcript background reduces text contrast at the bottom
**Evidence.** `PiChatUI.swift:148–172` layers four backgrounds: base
`Palette.bg`, dot grid with `+Lighter` blend, top-left linear tint, and a
bottom-left radial gradient. The radial hits the assistant bubble's bottom
half — the area where long responses accumulate. On a low-contrast theme
this pushes the secondary text into the background.

**Direction.** Cap the radial opacity at 0.03, or move it to the top header
zone. Drop the dot grid in compact mode. Test on a real Mac with
`colorScheme: .light` to ensure dark surfaces don't bleed through.

---

## LOW

### 9. Code block copy has no feedback
**Evidence.** `PiChatUI.swift:872–885` writes to `NSPasteboard` silently. No
icon swap, no toast, no animation. The button looks identical before/after.

**Direction.** Add `@State private var copied = false`, swap the icon to
`"checkmark"` for 1.2s, reset on a `Task.sleep`.

### 10. Dock resize gesture does not follow macOS conventions
**Evidence.** `PiChatDock.swift:85–100` uses a custom `DragGesture` on the
top handle. No cursor change, no snap-to-default, no visual ruler. macOS
users expect a divider with `NSCursor.resizeUpDown` and snap points
(230/400/600).

**Direction.** Replace the top-handle drag with a 6pt divider strip below
the header, hover-swaps cursor to resize, snap to 230/400/600 with the
existing defaults key.

### 11. No light-mode support
**Evidence.** `Palette.bg` and friends are dark-only. The chat surface is
embedded in a menu bar app that follows system appearance, so a user in
Light Mode gets dark-on-dark chat inside a light chrome — jarring.

**Direction.** Introduce semantic tokens (`Palette.chatBg`, `Palette.chatText`,
`Palette.chatBorder`) that switch on `colorScheme`. Add a `colorScheme` env
value at the chat root.

### 12. ScrollView fires multiple `scrollToEnd` per token
**Evidence.** `PiChatUI.swift:181–195` registers three `onChange` handlers
(messages.count, last text, isSending). During a streaming response the
text handler fires per token, producing janky scroll on slower Macs and
fighting the user's manual scroll position if they scrolled up to read
history.

**Direction.** Coalesce into a single `lastMessageID` + `lastCharCount` change,
debounce to ~50ms, and pause auto-scroll when the user is scrolled up by
more than 80pt from the bottom (and show a "↓ New messages" pill — common
chat pattern).

### 13. `PiChatFormat.markdownText` is not loaded here but the empty state
injects a string for `Connected to \(session.currentProvider.name)` — the
provider name should also drive a per-provider brand tint on the empty
state hero, not just the streaming accent.
**Evidence.** `PiChatUI.swift:332–336`. Empty state uses `Palette.running`
unconditionally.

**Direction.** Pass `theme: PiChatTheme` from the session so the empty state,
composer accent, and live chip all shift subtly per provider.

---

## What is already good

- Empty state starter grid is well-scoped and inviting
  (`PiChatUI.swift:256–305`).
- Code block chrome with traffic-light header and copy button is a nice
  macOS-y detail (`PiChatUI.swift:835–895`).
- Custom hand-rolled syntax highlighter covers `swift`, `json`, `bash`, and
  generic with consistent palette tokens (`PiChatUI.swift:900–1190`).
- Auth prompt card is calm and uses mono consistently
  (`PiAuthPromptCard.swift:1–90`).
- Status pill is a thoughtful, dense read of session state
  (`PiWorkspaceView.swift:75–105`).
- Footer `↩ send` hint shows attention to discoverability
  (`PiChatUI.swift:1218`).
- All four top-level surfaces (PiChatDock, PiWorkspaceView, PiChatTranscript,
  PiChatComposer) share typography and palette tokens, so the language is
  consistent — the issues are about depth, not vocabulary.

---

## Suggested first pass (1–2 days of work)

1. **Composer shortcuts** — Cmd+Return, Esc to cancel, hint fix (HIGH #2).
2. **Avatar disambiguation** — drop avatar from user side or swap glyph (HIGH #1).
3. **a11y sweep on icon buttons + Dynamic Type pass** (HIGH #3).
4. **Single setup card component** with three kinds (MEDIUM #5).
5. **One-sheet "what this assistant can do"** triggered from the header (HIGH #4).

These five changes will resolve all four HIGH findings and the most visible
MEDIUM, and they cluster naturally because they all touch `PiChatUI.swift`
+ the header/composer chrome.

---

# Second pass — implementation-oriented

## 1. What I would fix first and why

In a single PR, in this order:

1. **Composer send-key correctness** (`PiChatUI.swift:1246–1261`).
   Highest leverage: one well-placed `.keyboardShortcut(.return, modifiers: .command)`,
   one `.onExitCommand { session.draft = "" }` (or `cancelSend`),
   and the footer hint text changed from "↩ send" to "⌘↩ send  ·  esc clear".
   No new components. No state model changes. Removes the single most
   surprising behavior for anyone who has used any other chat app.
   The `composerLineLimit: 4` (dock) / `8` (workspace) in `PiChatStyle`
   confirms the field is multi-line by design — `TextField.onSubmit` on
   plain Return is unambiguously wrong here.

2. **Drop the user-bubble avatar** (`PiChatUI.swift:463`).
   Five lines of code removed, one line of bubble padding adjusted.
   Immediately disambiguates speaker identity without introducing a new
   component. Cheap A/B candidate: leave a tiny initial circle if you want
   something on the right, but the brand mark has to go.

3. **Accessibility sweep on icon buttons** (`PiChatDock.swift:103`,
   `PiWorkspaceView.swift:130`, `PiChatUI.swift:872`, `PiChatDock.swift:386`).
   Mechanical: add `accessibilityLabel("Close chat", "Open assistant settings",
   "Copy code", "Settings")` to four buttons. Bump `footerIconButton`'s
   hit area from 24×22 to 28×24. Highest a11y ROI in the file.

4. **Add a `?` tools sheet** in the header, starting with just a hardcoded
   provider/model list. Stub it with a `Text` of the current provider name,
   a one-paragraph capability blurb, and a list of the seven tool names
   already mapped in `PiChatToolChip` (`PiChatUI.swift:600–650`). Becomes
   the natural home for cost/token telemetry later.

This order: (1) and (2) unblock anyone trying to actually use the surface.
(3) is a no-regret pass. (4) opens the door to making the assistant feel
less opaque, which is the largest gap the first pass identified.

## 2. What I would deliberately defer

- **Streaming decoration cleanup (MEDIUM #6 in the first pass).**
  Hard to argue from a static review. The animations are individually small
  (1.4s pulse, 0.85s cursor, 0.28s background ease). On a 60Hz display the
  perceived "busyness" is uncertain. Defer until someone watches a real
  streaming response on a real Mac and reports it feels busy. Don't pre-emptively
  cut signals that may carry useful liveness.

- **Full Dynamic Type pass.** Real, but big. `PiChatStyle.bodySize` is
  referenced in ~6 sites; the right call is probably to introduce
  `@ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 13.5`
  and let the system drive it. But until there's a user report, ship (3)
  first and come back to this.

- **Light-mode palette tokens.** Real gap (`Theme.swift` is dark-only,
  zero `colorScheme` references in the chat surface), but it's a
  cross-cutting theme change, not a chat-surface change. Belongs in a
  separate "Palette semantic tokens" pass.

- **Auth panel consolidation (MEDIUM #7).** Worth doing, but only if you
  are actually changing the auth flow soon. If not, leaving three
  implementations is cheaper than risking a regression in a critical
  onboarding path.

- **`PiSetupCard` unification (MEDIUM #5).** Same reasoning — defer until
  you are touching setup copy for product reasons.

- **Per-provider brand tint.** Speculative. Lattices has a clear visual
  identity; tinting the chat to match each provider dilutes it. Wait for
  evidence that users want this.

## 3. Where the first pass overreached or missed evidence

- **"Streaming is over-decorated"** — I counted animations without testing.
  I should have said "needs a live walkthrough" rather than prescribing a
  fix. The recommendation to "pick one dominant affordance" is a stylistic
  call, not a clear win.

- **"Three `onChange` handlers fight on streaming scroll"** — overclaim.
  SwiftUI's `ScrollViewReader` + animation handles per-token `scrollTo`
  well in practice. The real problem is the absence of a "jump to latest"
  pill when the user has scrolled up — not the handler count. Soften.

- **"Light-mode support"** — verified this round: `Theme.swift` has zero
  `colorScheme` references and the chat hardcodes `Palette.bg`. The
  finding is correct, the scope is bigger than I implied. It's a
  project-wide token migration, not a chat-surface change.

- **"Three parallel auth/setup states compete visually"** — partially
  overreach. `PiChatDock` and `PiWorkspaceView` are intentionally two
  different products (compact bottom drawer vs. full pane). `PiChatStyle`
  enforces that with `composerLineLimit: 4` vs. `8`, `bodySize: 12` vs.
  `13.5`, `horizontalPadding: 12` vs. `28`. Some of the "triplication"
  is appropriate. The auth flow within each is duplicated, not the
  surfaces themselves. Restate: deduplicate the **auth flow logic**
  (one component, two style modes), keep two surface layouts.

- **Missing in the first pass:** I never opened `UI/Theme.swift` until
  this follow-up. The Dynamic Type claim was based on hardcoded `Typo`
  calls in `PiChatStyle`, which is still true, but I should have flagged
  the file once for the whole surface, not enumerated sites.

- **Missing in the first pass:** I didn't look at the dock resize gesture
  UX holistically. A `DragGesture(minimumDistance: 1)` on the top handle
  is unusual but not broken — many native macOS apps do this. Lower its
  priority from LOW to "watch the resize behavior on a trackpad; only
  rework if it feels wrong."

- **Missing in the first pass:** I didn't note that the empty-state
  starter cards auto-send on click (`PiChatUI.swift:268–275`). That is a
  real ergonomic call: should the click fill the composer (so the user
  can edit) or auto-send? Currently it auto-sends. Worth a single
  decision: fill-only, with a separate "send" affordance, matches the
  user's mental model in most chat products. Not in the first PR — but
  decide it before (4) ships the tools sheet.

## 4. Smallest coherent implementation slice

**One PR, one developer, half a day. Files touched: `PiChatUI.swift` only.**

```swift
// In PiChatComposer (PiChatUI.swift ~1246)
Button {
    session.sendDraft()
} label: {
    // ...existing send button body...
}
.buttonStyle(.plain)
.keyboardShortcut(.return, modifiers: .command)   // NEW
.disabled(!canSend)

// On the TextField, replace .onSubmit with .onSubmit-of-single-line:
TextField(
    style.placeholder,
    text: $session.draft,
    axis: .vertical
)
.textFieldStyle(.plain)
.font(Typo.body(style.composerSize))
.foregroundColor(Palette.text)
.lineLimit(1...style.composerLineLimit)
.focused(focus)
.onSubmit { /* no-op for multi-line; Cmd+Return handles send */ }
.onExitCommand { session.draft = "" }              // NEW

// Footer hint (PiChatUI.swift ~1218):
Text("⌘↩ send · esc clear")
```

**Plus one PR, separate reviewer, half a day: drop the user-bubble avatar.**

```swift
// In userRow (PiChatUI.swift ~432):
// Remove the trailing LatticesMarkAvatar(size: 28, ...)
// Add a 4pt right padding to the user bubble for visual breathing.
```

Total: ~25 lines changed, zero new components, zero state-model changes,
zero migrations. Both changes are independently revertable. The first
lands a measurable behavior fix (the wrong key sent prematurely), the
second removes a known visual confusion.

This is what a developer should land before any of the larger
consolidations. It addresses the two HIGH findings where I have the most
confidence and unblocks real testing of the surface by anyone who tries
to send a multi-line message.

## 5. Observable session / provenance details from this run

- **Identity.** Agent: `lattices-review-pi-scout.main.arts-mac-mini-local`.
  Invoked as a stable OpenScout relay agent on this turn.
- **Model.** `MiniMax-M3` (per harness system prompt; "M3" is the model
  class, not necessarily a per-request model identifier).
- **Provider / transport.** The harness is MiniMax's own inference stack;
  I have no per-request model name, no temperature, no token budget, no
  response-time telemetry, no streaming chunk count, no tool-use log.
  The wire protocol I am reachable over is the OpenScout broker
  (WebSocket); conversation `c.baf8732a-9752-487a-841a-57595463bf8d`,
  this message `msg-mpwvwdq3-z1nuja`, reply path `final_response`.
- **Runtime mode.** `thinking` enabled; `max thinking effort` is implicit
  (the harness emits long deliberation blocks before each reply). No
  explicit budget is exposed to me. I cannot report token counts for
  this turn.
- **Session state.** `cwd: /Users/art/dev/lattices`; `git status` shows
  one staged file: `A  docs/ai-chat-ux-review.md` (the first-pass report,
  mtime 12:17 today). `HEAD: b09e4d8` "Merge pull request #41 from
  arach/codex/inventory-sort-arrange". No uncommitted source changes.
- **Tools available to me this turn.** `bash`, `read`, `edit`, `write`,
  `intercom`, `mcp`, `scout_{send,ask,who}`, `subagent`. I used
  `read`, `bash`, and `edit` for this turn — the `edit` was on my own
  review file, not on any source.
- **Status telemetry available.** None beyond the OpenScout message
  metadata above. No live provider status, no tool-use trail, no
  thinking-trace payload on the wire. The thinking block is a local
  harness detail, not a broker-visible artifact.
- **What I cannot report.** I do not have visibility into MiniMax
  upstream latency, model selection, rate limits, or the exact provider
  routing path used for this M3 inference. I would not invent those.
