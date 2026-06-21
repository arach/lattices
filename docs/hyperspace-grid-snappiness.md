# Hyper+G in-place grid — snappiness & satisfaction brief

Context: `relayoutGroup()` already switched from sequential `RealWindowAnimator.setFrameRobust`
to `WindowTiler.batchMoveAndRaiseWindows` (SLS freeze + one AX pass/app), with UI refresh
deferred and a tap on commit. This is the "make it even better" pass.

Code anchors:
- Grid path: `WindowMotionMode.swift:1100 relayoutGroup()` → `:1138 distributeGroup()` (G = keycode 5, `:833`)
- Batch move: `WindowTiler.swift:1753 batchMoveAndRaiseWindows` (freeze `:1767`, AX enum `:1776`, activate `:1818`, unfreeze `:1825`)
- Sound: `DiagnosticLog.swift:162 AppFeedback.playTap`
- Optional anim: `RealWindowAnimator.swift` (Timer 60fps, 0.28s — NOT on the batch path)
- Chrome flash: `WindowTiler.swift:54 WindowHighlight.flash` (single-window only)
- No haptics anywhere in the codebase yet → green field.

---

## The governing principle

Perceived latency is bound to the **earliest** feedback the brain receives, not the moment
pixels finish moving. The AX move is 40–120ms of work we can't fully erase. So the play is:
**acknowledge on key-down (haptic + sound + overlay), move under cover, let the windows catch
up.** Every quick win below is a variant of "fire feedback before the slow thing finishes."

---

## Quick wins (ship this week, low risk)

### Q1 — Haptic on key-down (biggest bang, ~10 lines)
There is zero haptic feedback today. `NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)`
is *exactly* the Loop/Magnet "snap" feel on trackpad/Force Touch. Fire it the instant `G` is
matched in `keyDown` (`:833`), **before** `distributeGroup()` runs. Costs nothing, lands on the
keypress, and the windows snapping ~80ms later reads as "instant + tactile."

### Q2 — Decouple + pre-warm the tap sound
`playTap` does `DispatchQueue.main.async { stop(); play() }`. Three problems:
- the async hop delays the sound ~1 runloop turn past the keypress,
- `stop()` then `play()` adds a tiny dead gap,
- NSSound's *first* play in a session stutters (codec spin-up).

Fixes: (a) prime the sound once on motion-mode entry by playing `tap.wav` at volume 0; (b) fire
it synchronously on key-down (same site as the haptic), not after the move; (c) consider a
prepared `AVAudioPlayer` (`prepareToPlay()`) or `AudioServicesPlaySystemSound` for sub-frame
latency. Net: the *thunk* and the *tap* (haptic) coincide with the keypress, not the landing.

### Q3 — Shrink the SLS freeze window
`batchMoveAndRaiseWindows` does the slow `kAXWindowsAttribute` enumeration **inside** the
`SLSDisableUpdate` freeze (`:1776`). The screen is frozen while we do AX queries. Resolve the
AX elements *before* the freeze, freeze only around the set-frame writes, unfreeze immediately.
Bonus: `relayoutGroup` already resolves each element via `recordOriginal`'s `ax(for: m)` (`:1113`)
and then the batch path re-resolves the whole window list — pass the resolved elements in and
skip the second AX pass entirely. Shorter freeze = less black-flash, snappier reveal.

### Q4 — Stop activating every app
`batchMoveAndRaiseWindows` calls `app.activate()` once per pid (`:1818`). With windows from N
apps that's N activations → focus churn, Space flicker, and the overlay can lose key. AX
`kAXRaiseAction` (already issued at `:1806`) reorders without activating. Activate **only** the
app that should end up frontmost (the last-picked / aimed window), once. Raise the rest.

### Q5 — Overlay "snap-pop" on the selection chrome
The real move is a teleport, so add the *sense* of motion in the cheap overlay layer (no AX
cost). When the grid lands, give each selection border a tiny scale overshoot (1.0→1.04→1.0,
~120ms, Core Animation) + a one-shot green edge flash converging on the slot. This is the
Arc/Raycast "it clicked into place" pop. Overlay-only, runs off the AX path, can't add input
latency.

---

## Bigger bets (more design, higher ceiling)

### B1 — Ghost-slot anticipation (kills perceived latency outright)
On `G`, **instantly** paint the target grid as outlined ghost slots (you already compute
`balancedGrid` rects → `tileFrame`). Animate the slots filling (or the picked windows' chrome
sliding toward their slots) over ~140ms while the real `batchMove` runs underneath. The user
sees motion begin on the same frame as the keypress; the real windows arrive under the
animation. This fully decouples felt-speed from AX latency and is the single highest-ceiling
change. The ghost overlay is also the natural home for Q5's pop.

### B2 — Precompute on selection, commit = pure writes
Every pluck/unpluck currently recomputes `balancedGrid` + `tileFrame` and re-resolves AX. Cache
(a) the AX element per picked wid and (b) the target frame map, updated incrementally as the
selection changes. By the time `G` fires, commit is nothing but the frozen set-frame loop —
nothing to compute, nothing to resolve, minimal freeze.

### B3 — Staggered cascade fill (the "deliberate fast" feel)
Real windows must move simultaneously (per-window AX animation = jank — see "avoid"). But the
*overlay* tiles/borders can land on a micro-stagger in reading order (~10–14ms/cell). The eye
reads a fast left-to-right cascade as more intentional and premium than a flat simultaneous
snap, while the actual work stays a single batch. Pure overlay timing.

---

## What to avoid (these ADD latency or jank)

- **Don't animate many real windows via per-tick AX writes.** `RealWindowAnimator`'s 0.28s
  Timer loop is fine for one window; across a group it's 60fps × N AX position+size writes —
  AX is slow and serializes, so it stutters and feels *slower* than a clean teleport. Keep the
  batch teleport; animate the overlay, not the windows.
- **Don't do AX enumeration / `DesktopModel.poll()` inside the freeze or on the commit path.**
  Poll/rebuild are already deferred (`refreshAfterGridMove`, `:1125`) — keep it that way; don't
  let new chrome work creep back onto the hot path.
- **Don't async-dispatch or `stop()`-then-`play()` the commit sound** (see Q2) — both push the
  thunk past the keypress.
- **Don't `app.activate()` per app** (Q4) — multi-app activation is the main source of flicker
  and overlay focus loss.
- **Avoid Timer-driven overlay animation.** Use Core Animation / `CADisplayLink`; `Timer` at
  1/60 drifts and can hitch under load.
- **Don't add dwell.** `WindowHighlight.flash` defaults to a 0.9s dwell + 0.3s fade — fine for a
  one-shot locate, wrong for a snap pop. Snap feedback wants ~120–180ms total. Long fades read
  as lag, not polish.

---

## Recommended ship order

1. **Q1 + Q2** together — one small change at the `G` key site: haptic + synchronous pre-warmed
   sound on key-down. Instant tactile upgrade, ~20 lines, no risk.
2. **Q3 + Q4** — tighten `batchMoveAndRaiseWindows` (pre-resolve AX, shorter freeze, single
   activate). Real latency reduction.
3. **Q5** — overlay snap-pop on the chrome. First "ooh" moment.
4. **B1** — ghost-slot anticipation once Q5's overlay exists to build on. This is the headliner.

---

## Implementation sketches

### Sketch 1 — Haptic + tactile commit on key-down (Q1+Q2)
At `WindowMotionMode.swift:833`, before dispatching the grid:
```swift
case 5: // G
    if exposed { gatherInPlace() }
    else {
        AppFeedback.shared.commitTactile()   // haptic + sound, synchronous, NOW
        distributeGroup()                     // remove the playTapSound() from relayoutGroup
    }
    return
```
New in `AppFeedback`:
```swift
func warmUp() {                       // call on motion-mode entry
    tapSound?.volume = 0; tapSound?.play(); tapSound?.stop(); tapSound?.volume = 1
}
func commitTactile() {                // called on the keypress, on main
    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    tapSound?.currentTime = 0
    tapSound?.play()                  // no async hop, no stop() gap
}
```
Remove `AppFeedback.shared.playTapSound()` from `relayoutGroup()` (`:1120`) so the feedback is
owned by the keypress, not the move completion.

### Sketch 2 — Pre-resolved, minimal-freeze batch (Q3+Q4)
New overload that trusts caller-resolved elements and freezes only the writes:
```swift
static func batchSetFrames(_ moves: [(el: AXUIElement, pid: Int32, frame: CGRect, raise: Bool)],
                           frontmostPid: Int32?) {
    // app -> enhanced-UI off, BEFORE freeze
    let pids = Set(moves.map(\.pid))
    let appRefs = Dictionary(uniqueKeysWithValues: pids.map { ($0, AXUIElementCreateApplication($0)) })
    appRefs.values.forEach { AXUIElementSetAttributeValue($0, "AXEnhancedUserInterface" as CFString, false as CFTypeRef) }

    let cid = _SLSMainConnectionID?()
    if let cid { _ = _SLSDisableUpdate?(cid) }          // freeze ONLY the writes
    for m in moves {
        setFrameTriplet(m.el, m.frame)                  // size→pos→size
        if m.raise { AXUIElementPerformAction(m.el, kAXRaiseAction as CFString) }
    }
    if let cid { _ = _SLSReenableUpdate?(cid) }         // unfreeze immediately

    appRefs.values.forEach { AXUIElementSetAttributeValue($0, "AXEnhancedUserInterface" as CFString, true as CFTypeRef) }
    if let frontmostPid { NSRunningApplication(processIdentifier: frontmostPid)?.activate() }  // ONE activate
}
```
`relayoutGroup` already has `el` in hand from `recordOriginal` — collect it into `moves` and
call this; no second `kAXWindows` enumeration, freeze shrinks to just the set-frame loop.

### Sketch 3 — Overlay snap-pop on selection chrome (Q5)
On grid landing, per slot, run a layer animation on the existing selection border view (overlay,
not the window):
```swift
let pop = CAKeyframeAnimation(keyPath: "transform.scale")
pop.values = [1.0, 1.045, 1.0]; pop.keyTimes = [0, 0.45, 1]
pop.duration = 0.13; pop.timingFunction = CAMediaTimingFunction(name: .easeOut)
borderLayer.add(pop, forKey: "snapPop")
// + a one-shot edge tint that fades over the same 0.13s
```
No dwell, no AX. Fire it from `refreshAfterGridMove` (`:1125`) so it rides the deferred turn.

### Sketch 4 — Ghost-slot anticipation (B1)
On `G`, before the move, draw target slots in the motion overlay and animate the picked windows'
*chrome* (or ghost rects) from current → slot, while `batchSetFrames` runs underneath:
```swift
func previewGrid(_ rects: [CGRect]) {     // rects already from balancedGrid → tileFrame
    for (i, r) in rects.enumerated() {
        let slot = ghostLayer(at: currentChromeFrame(i))
        slot.frame = currentChromeFrame(i)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.14)
        slot.frame = r                      // slides to target as the real window teleports under it
        CATransaction.commit()
    }
}
```
Sequence: keypress → `commitTactile()` (Sketch 1) + `previewGrid()` same frame → `batchSetFrames()`
→ ghosts fade as real windows land → `refreshAfterGridMove`. Felt latency ≈ 0; the move hides
under 140ms of overlay motion.

### Sketch 5 — Staggered cascade (B3, optional flourish)
In `previewGrid`/snap-pop, offset each cell's animation `beginTime` by `index * 0.012` in
row-major order. Overlay-only; the real batch stays simultaneous. Toggle behind a setting if you
want a "calm" vs "playful" feel.
