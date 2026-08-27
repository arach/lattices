# Field report: driving Talkie's console with Action (2026-08-26 session)

Operator-side field report from a real work session, for whoever is coding on
Action. Context: Claude (coordinator session on Arach's mini) used Action to
verify a Talkie UI redesign and to reproduce/verify a console deadlock fix.
Roughly 20 drive actions across 6 leases over ~4 hours, all `mode:
"background"` against the dev Talkie build (`to.talkie.app.mac.dev`,
1720x1440 window at 0,0). What follows is every friction point hit, with exact
evidence, ordered by how much time each one cost.

## 1. Synthetic typing to a ghostty-embedded surface silently drops (worst)

Talkie's console embeds a ghostty terminal (Termini package). `act.execute
{kind: "type"}` against it was *intermittently* delivered:

- 13:10:40 — `type "seq 1 200000\n"` right after launching the tab: only
  partial garbage arrived (`se1` — dropped keys mid-burst, likely raced the
  surface becoming first responder).
- 13:29:38 — `press-key return` after an explicit `click` on the surface:
  **delivered** (the mangled line executed).
- 13:31:12 — `type` again, same window, same focus, 90 seconds later:
  **silently dropped**. Action reported `status: "succeeded"`, screenshot
  shows nothing arrived.
- 13:44:19 — after fresh `focus-window` + `click` + `type`: dropped again.

So: two delivered, two dropped, all four reported success. The report-success/
actually-dropped combination is the damaging part — the caller cannot tell
the difference without a screenshot diff. If keystroke delivery can't be
confirmed (no AX echo, no focused-element check), a `type` result that can't
verify delivery should say so (`delivery: "unconfirmed"`), not `succeeded`.
Suspected factor: ghostty's NSView takes keyboard via its own event monitor
and the synthetic events need the window to be key + view first-responder;
first-responder state visibly lagged clicks.

## 2. Bare `point` triggers the Calculator stub

`act.execute {kind: "click", point: {x,y}}` (point at top level) fails with:

    click-calculator-button failed: No running application matches bundle
    identifier com.apple.calculator

The same click with `input: {point: ...}` works. So the legacy calculator
demo path is still the fallback resolver for a malformed action, and the
error message sends the caller chasing a nonexistent Calculator. A malformed
click should fail with "point must be under input", or better, accept both
shapes.

## 3. First click after focus-window is eaten — reliably

Documented caveat, confirmed again ~5 times tonight: after `focus-window`,
the first `click` activates/focuses but does not land on the control. The
workaround (click twice, or focus-window then click) is now muscle memory but
costs a round-trip + screenshot every time. Since Action knows it just
focused the window, it could absorb this: if the target window was not key
when the click was issued, send activate-then-click as one action.

## 4. Background leases expire fast and silently

Three times tonight a lease died between two actions separated by normal
think/verify time (screenshot + sample + a Bash round-trip, ~3-15 min):

    Unknown drive lease: drive_20260826_130959854_09842509
    Unknown drive lease: drive_20260826_132740824_85b9ee4f
    Unknown drive lease: drive_20260826_134119090_2475fcad

Each expiry costs a re-begin + re-focus + the eaten-first-click tax (see #3).
No signal distinguishes "expired" from "never existed". Asks: (a) an
`expiresAt`/idle-timeout in the drive.begin response, (b) an error that says
"expired after Ns idle, re-begin to continue", (c) ideally a longer idle
window for background leases — a driving session interleaved with
verification steps has natural 5-10 minute gaps.

## 5. tab-strip clicks that report success but change nothing

Clicks at (96,36) and (403,36) on Talkie's console tab strip (breadcrumb/
tab chips, "+" button) reported `axTier: "semantic"`, `status: succeeded`,
but no tab switch / no picker opened, across two attempts each with correct
retina-point coordinates (verified against screenshots at 1x). Could be
Talkie's hit targets, could be delivery — but as with #1, the caller can't
tell from the result. A `semantic` tier result could usefully include what AX
element it believes it hit (role + title), which would separate "hit the
wrong thing" from "hit nothing".

## What worked well (so it doesn't get lost)

- `focus-window {bundleId}` — 100% reliable, every time.
- Point clicks on plain SwiftUI controls (sidebar icons, list rows, LAUNCH
  buttons) — reliable once the focus tax was paid.
- The window screenshot flow via the driven app's own HTTP was our
  verification loop; `record`/`observe` weren't needed tonight.
- Lease/HUD ergonomics (`drive_begin` task strings, release summaries) are
  genuinely good operator UX.

## Repro environment

- Action MCP from this checkout (main @ 2945e64), background leases only.
- Target: Talkie dev build, ghostty surface = Termini 0.1.2.
- The Talkie-side deadlock that motivated the session is fixed separately
  (arach/Termini@57cf01c); nothing in this report depends on it.

## Suggested priority

1 and 5 are the same root ask: **honest delivery feedback** — never report
`succeeded` for input that cannot be confirmed delivered. 2 is a stray stub
with a misleading error. 3 and 4 are ergonomics taxes paid on every session.
