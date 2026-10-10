# Long: depth-first review

This is a review slice, not a claim that the full direction brief is complete.

## Choice

Keep the 44 pt tile and its 80 × 80 body on a 100-unit drawing grid. Choose
**soft** depth: 17% lit top-left highlight, a 30.6% top rim fading to 4%,
18% lower shade, and a small downward black shadow. The comparison includes
8%, 17%, and 32% highlight strengths on dark and light grounds, enlarged and
at actual desktop size. After inspecting both scales on both grounds, soft gives volume without turning the
ink tile into a silver button. Coral remains reserved for the away cell.

Eyes now repeat the body's rounded-square geometry (14 units wide, 25% corner
radius). Listen raises and enlarges them, oops squashes and lowers them, work
narrows and turns them, away looks toward the visited host. Talk's mouth takes
an explicit playback level; it no longer invents a 140 ms repeating cycle.
Column proportions are deferred: preserving the approved silhouette keeps the
first comparison about depth alone.

## Motion and card

Removed idle blink timers, repeating work scan, and synthetic speech loops.
Layer changes trigger a single 0.6 s acknowledgement (0.24 s ease-out); existing
visit start/end events retain their moods. Listening lean retains its 0.35 s
spring. Reduce Motion disables character transforms and interpolation.

Card: Search; layers; machines/visits; displays (also on a single display);
Cursor home; a small Hide Long icon in the corner. Existing action
routes remain unchanged. A tested, sticky 3 pt drag threshold prevents a drag
that returns to its start from opening the card.

## Sources examined

- Fab `cli/native/FabPanel/Sources/FabPanel/DesktopTuck.swift`: 44 pt default,
  remembered free placement, padded nonactivating panel, own ground shadow.
- Fab `design/explorations/micro-pet/tuck-v1.png`: restrained material volume.
- Scout `apps/macos/Sources/Scout/ScoutCompanionController.swift`: nonactivating
  companion, native panel shadow disabled, web-owned figure/card composition.
- Scout `design/studio/views/scoutbot-character.tsx` and CSS: geometric body,
  solid eyes, compact expression cues, light/dark grounds.
- Supplied Claude character-sheet URL was inaccessible from the web tool;
  checked-in Long drawing was the visual authority.

## Not yet verified / next slice

- No running app was quit, relaunched, or replaced. Live drag, card actions,
  desktop compositing, and the reported white smudge remain unverified.
- The source already uses a clear, nonopaque panel with `hasShadow = false`.
  The drawn ground shadow is black. Those facts do not establish the smudge's
  root cause. No speculative window-level/background workaround was applied.
  Next check needs operator-approved live capture of the host/window backing
  against the same offline drawing.
- Voice/Fab playback is not yet connected to Long. `speechLevel` is a rendering
  input, not a producer integration. Voice emits `speech.changed`; forwarding
  currently belongs to per-caller authenticated helper connections. A robust
  bridge must cover pause/end/disconnect and independent Fab playback without
  polling or misrepresenting queued/generating speech as audible playback.
- Listen is still a renderable mood, not yet connected to capture lifecycle.

## Reproduce

```sh
LONG_RENDER_DIR="$PWD/artifacts/long-depth" xcrun swift test --package-path apps/mac --filter LongRenderTests
```

Use Xcode's toolchain on this machine: the plain `swift` shim points at a
missing Swift 6.2.3 install. The command above does not launch the app.

## Verification (2026-10-10)

- `LongRenderTests`: 3 passed, including offline exports, sticky drag threshold,
  and cancellation of a superseded mood-reset event.
- Full `xcrun swift test --package-path apps/mac`: 516 executed, 37 opt-in tests
  skipped, zero failures. Build has existing SDK deprecation/concurrency warnings.
- Inspected depth and mood sheets on light/dark grounds at enlarged and 44 pt
  sizes. The selected midpoint retains an ink face while making the top edge
  legible on dark backgrounds; bold reads more metallic.
- Inspected the card export, then corrected clipped layer labels with three
  columns and replaced an unsupported offline native Menu rendering with a
  directly actionable Hide Long icon. Confirmed the final card export.
- `git diff --check`: clean.

Exports: `long-depth-comparison.png`, `long-moods.png`, `long-card.png`.

## Approved soft depth: system light/dark appearances

The operator approved soft depth. Dark appearance keeps the ink body and light
face. Light appearance swaps to the #f2f2f2 body and #101518 face. Coral is
unchanged. Light depth uses a 34% white top highlight, a white-to-22%-ink rim,
10% lower ink shade, and a 30% black shadow with a 5-unit blur and 4-unit drop;
the shadow and lower rim define the object on a light desktop. Dark depth
retains the approved values above.

The app pins `NSApp.appearance` to dark in `AppDelegate.swift`. Inheriting the
app appearance alone would therefore fail. Both Long panels now explicitly
resolve the global system appearance on creation and on the system theme-change
notification; SwiftUI's `colorScheme` updates the drawing and card. No polling,
no app-wide theme changes, and observer lifetime follows its panel.

`long-moods.png` now has four labeled rows: dark Long on dark/light desktops,
then light Long on dark/light desktops, each at 100 pt and 44 pt. `long-card.png`
shows dark and light cards side by side. The original three-strength ink depth
comparison remains pinned to dark appearance for reproducibility.

Appearance verification: both token directions and the panel's system resolver
are covered by tests, including refreshing a panel away from a stale explicit
appearance. Offline renders were inspected in all four combinations and both
card appearances. The operator's running app and system appearance were not
changed; an actual Settings-driven desktop flip remains a live review check.

Final appearance run: `LONG_RENDER_DIR="$PWD/artifacts/long-depth" xcrun swift
test --package-path apps/mac` passed: 518 tests, 36 skipped, zero failures.
All five Long tests ran, including the render test. `git diff --check` is clean.
