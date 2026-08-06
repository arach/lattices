# Solo deck transition performance audit

Date: 2026-07-30
Branch inspected: `codex/fix-assistant-voice-runtime`
Scope: Home host tap -> `fullScreenCover` -> `HostDeckHost` -> `LatsDeckScreen`

## Bottom line

The operator's premise is correct: the slow solo-deck presentation is primarily local main-thread view construction/diff/layout, not network wait, the recording waveform, or the Fleet Deck shadows.

The largest measured event is constructing the full `LatsDeckScreen` tree during presentation. A local representative snapshot added roughly 90 ms to time-to-appearance and about 130 ms to the worst display-link interval over a lightweight cover. Removing either of the two large visible subtrees—the cockpit or shortcut grid—saved 26–35 ms of time-to-appearance and about 52 ms of the worst interval. Publishing a new snapshot later re-evaluated the whole deck and produced roughly 37 ms hitches in an optimized simulator build.

The single biggest win is therefore to stop constructing/diffing the entire cockpit and shortcut tree on the presentation animation frame, then keep those stable subtrees out of unrelated 1 Hz snapshot updates.

## What was measured

I temporarily added a CADisplayLink harness, then removed it completely. The harness presented a local `DeckRuntimeSnapshot` with the production-size cockpit catalog (6 pages x 16 tiles) and a 24-window layout preview. No network was involved.

- Build: Release-optimized iOS app.
- Target: iPad Pro 13-inch (M5) iOS 26.5 Simulator.
- Simulator display cadence: 60 Hz, despite requesting 120 Hz. These numbers do not predict the exact 120 Hz device result, but the multi-frame main-run-loop stalls are far above either budget.
- Values below are medians of three runs for the controlled A/B set unless stated otherwise.

| Variant | Presentation request -> content `onAppear` | Worst display-link interval | Delta from matched baseline |
|---|---:|---:|---:|
| Lightweight cover | 32.6 ms | 43.9 ms | reference only |
| Full local deck | 122.4 ms | 175.1 ms | baseline |
| No shortcut grid | 96.8 ms | 123.2 ms | -25.6 ms appear, -51.9 ms stall |
| No cockpit subtree | 87.4 ms | 123.1 ms | -35.0 ms appear, -52.0 ms stall |
| No cockpit and no grid | 75.8 ms | 97.3 ms | -46.6 ms appear, -77.8 ms stall |
| Solo-deck shadows disabled | 130.3 ms | 176.8 ms | no improvement within run variance |

There was substantial cold/warm variance: one cold full-deck run was 234.1 ms to appearance with a 321.2 ms interval. A separate five-run full-deck set had a 156.7 ms / 213.5 ms median. The direction and ranking of the A/B results were stable; absolute simulator timings were not.

For steady state, I changed only `updatedAt`/telemetry in the representative snapshot three times at approximately 1 Hz:

- `LatsDeckScreen.body` evaluated once initially plus once per publication (4 total).
- The otherwise-idle 16.67 ms cadence acquired a 37.05 ms maximum interval and two over-33 ms frames across the three updates.

This is direct evidence that broad snapshot publication, not only presentation, causes visible deck hitches.

I attempted Instruments/xctrace SwiftUI/Animation Hitches and Time Profiler capture. The SwiftUI template was not usable against the Simulator, and Time Profiler did not yield an actionable call tree. Therefore this ranking is based on frame intervals plus controlled subtree A/Bs, not a physical-device CPU/GPU trace. A device Core Animation trace is still required before making the shadows a priority.

## Ranked costs and causes

### 1. Full synchronous deck-tree construction on cover presentation — dominant transition cost

Relevant code:

- `apps/ios/Sources/ContentView.swift:128` creates the `fullScreenCover` destination.
- `apps/ios/Sources/ContentView.swift:309-328` conditionally creates the deck.
- `apps/ios/Sources/ContentView.swift:350-360` instantiates `LatsDeckScreen` from the already-held snapshot.
- `apps/ios/Sources/LatsDeckScreen.swift:2158-2245` builds the root tree, cockpit, and shortcut grid.
- `apps/ios/Sources/LatsDeckScreen.swift:1475-1526` lays out the shortcut controls; the production catalog is six 16-slot pages at `apps/mac/Sources/Core/Companion/LatticesCompanionCockpit.swift:141-212` (only the active 16 are mounted, but all pages are decoded and mapped as needed).

The cover closure is evaluated and reconciled on the main actor as presentation begins. The lightweight-vs-full and subtree A/B results show the local tree is what turns a normal cover into a long frame. It is not necessary to wait for I/O to reproduce the symptom.

The current working tree already has a 300 ms fixed deferral in `ContentView.swift:289-337`. I measured the same strategy: initial cover appearance improved to 22.4 ms, but mounting the deck then caused a 240.9 ms interval beginning about 336 ms after the presentation request. In other words, 300 ms relocates the stall into the later portion of the transition; it does not remove it. It can also produce a skeleton-then-pop experience.

Clean tactical deferral should be keyed to the actual presentation transition completion, not a guessed 300 ms timer. A small `UIViewControllerRepresentable` bridge can observe the presentation controller's transition coordinator completion. During the transition, show a cheap snapshot-derived deck shell (host/deck title, fixed cockpit frame, key placeholders) so arrival is not blank. Then crossfade the live tree. This protects the transition, but tree cost still needs reduction or staged mounting to avoid an after-arrival hitch.

The structural fix is to make the cockpit and key grid separately diffable/reusable and cheap enough to mount. If an interim staged mount is needed, build shell -> cockpit -> key grid on separate main-loop turns after transition completion rather than inserting both large subtrees at once.

### 2. Whole-tree invalidation on every snapshot — dominant steady-state cost

Relevant code:

- `apps/ios/Sources/DeckStore.swift:14-31` makes one `@MainActor ObservableObject` with 14 `@Published` properties.
- `apps/ios/Sources/ContentView.swift:285-300` observes the entire store, although the solo view mainly needs snapshot and connection state.
- `apps/ios/Sources/DeckStore.swift:446-455` publishes the full snapshot, then also assigns selected page and error state.
- `apps/ios/Sources/DeckStore.swift:646-653` republishes every secondary store's `objectWillChange` through `DeckFleetStore`; a secondary solo deck can therefore invalidate both `HostDeckHost` directly and the root `ContentView` indirectly.
- `apps/ios/Sources/LatsDeckScreen.swift:2093-2135` sorts/maps transcript, preview windows, and shortcuts during root evaluation; `liveShortcuts()` maps the active page at `LatsDeckScreen.swift:2284-2316`.

`DeckRuntimeSnapshot` and its component types already conform to `Equatable`, so missing model conformance is not the problem. The full snapshot includes `updatedAt` (`swift/Sources/DeckKit/DeckRuntimeSnapshot.swift:3-4`), and telemetry timestamps also change, so the whole value is intentionally different every poll even when the cockpit page/tiles did not change.

Fix by publishing/observing derived, narrowly scoped presentation state:

1. Split stable cockpit page/tiles, trackpad/mode, telemetry/status, and activity/transcript into separate `Equatable` inputs.
2. Make the cockpit and shortcut grid explicit equatable boundaries so telemetry or `updatedAt` cannot rebuild them. Closures prevent relying on synthesized view equality; use a wrapper whose equality compares only the relevant model.
3. Do not forward every inner store change through `DeckFleetStore` to the root. Publish a fleet-specific derived revision/state only while the Fleet view needs it, or let per-host row subviews observe their own store.
4. Avoid assigning `selectedCockpitPageID`/`errorMessage` when the value did not change. This is smaller than the snapshot fix but removes unnecessary `@Published` emissions.

### 3. Poll fanout and duplicate refresh work — an avoidable transition amplifier

Relevant code:

- `apps/ios/Sources/ContentView.swift:238-252` now contains the correct policy: only the selected host is `.fast` for a solo deck; all hosts are `.fast` only for Fleet.
- `apps/ios/Sources/DeckStore.swift:488-521` implements 1 s fast and 5 s ambient polling.
- `apps/ios/Sources/ContentView.swift:94-102` explicitly refreshes on the tap.
- `apps/ios/Sources/ContentView.swift:332-337` refreshes the same store again inside `HostDeckHost.task`.

The previous "solo deck makes every host fast" behavior was wrong. The current targeted `applyPollPriority` is the right policy and should be kept. Note that `setUIPriority` only changes the interval chosen at the next poll iteration; it does not wake an existing sleep or immediately fetch.

The two explicit `refreshSnapshot()` calls are redundant, and neither is needed to present an already-fetched local snapshot. They can cause a snapshot publication/invalidation during the transition. Remove both for the cached-snapshot path; refresh only when there is no usable snapshot or when staleness policy explicitly requires it, and deduplicate in-flight refreshes in the store.

### 4. Recording waveform — real CPU/energy cost, but not an idle or presentation cause

Relevant code:

- `apps/ios/Sources/LatsDeckScreen.swift:1007-1014` mounts `recView` only for `.rec` mode.
- `apps/ios/Sources/LatsDeckScreen.swift:1030-1044` ticks at 30 Hz and creates 70 capsules with two sine calculations per element.

Measured:

- Idle mode: zero recording timeline ticks.
- Recording mode: 132 ticks in roughly 4.4 seconds (~30 Hz).
- The timeline invalidated its own subtree; it did not re-evaluate the `LatsDeckScreen` root.
- The optimized 60 Hz simulator stayed at a 16.67 ms steady maximum during this isolated run.

So the suspicion is numerically correct—about 2,100 capsule instances and 4,200 `sin` calls per second while recording—but it is absent when idle and was not the slow host-tap transition. Replace the 70-view `HStack` with one `Canvas` draw pass, use actual audio levels, and pause it whenever recording is not visible/active. This is an energy/recording-mode fix after the two items above.

### 5. Shadows — not the measured main-thread transition cause; device GPU validation remains

Relevant solo-deck sites include:

- shell: `apps/ios/Sources/LatsDeckScreen.swift:378`
- four inset panels: `LatsDeckScreen.swift:454-484`, modifier at `:670`
- every key surface: `LatsDeckScreen.swift:1715-1720`
- every key icon: `LatsDeckScreen.swift:1748`
- recent-key adornments: `LatsDeckScreen.swift:1710` and `:1790`

The large radius-30/radius-22 and every-keycap Fleet shadows at `apps/ios/Sources/FleetDeck/FleetDeckView.swift:164` and `FleetDeck/FleetDeckTheme.swift:187,258` are not mounted for `DeckDestination.host`; they cannot explain the solo transition.

Disabling the mounted solo-deck shadows did not improve simulator presentation timing. That rules them out as the primary main-thread cause in this path, not as a physical-device GPU/render-server cost. On the real iPad, use Core Animation's Color Offscreen-Rendered / Color Blended Layers and GPU counters before removing visual depth. If the device trace implicates them, start with per-tile/icon shadows because cost scales with the 16 visible controls, then the four large inset panels.

### 6. Fleet timelines — low priority for this path

- `apps/ios/Sources/FleetDeck/FleetDeckVoiceBar.swift:138` is already paused when inactive.
- `FleetDeckVoiceBar.swift:163` has an ungated 0.55 s caret timer, but the voice-bar caret is only mounted while listening at `:49-51`.
- `apps/ios/Sources/FleetDeck/FleetDeckFocusPane.swift:102` mounts a caret continuously while the Fleet focus pane is visible.

These views are not in the solo host deck. The continuously mounted Fleet focus caret is worth gating on scene activity/visibility, but at ~1.8 updates/s for one rectangle it is far below the measured solo-deck costs.

### 7. File size/type-check complexity — maintenance issue, not runtime evidence

I built with:

```text
-Xfrontend -warn-long-expression-type-checking=100
-Xfrontend -warn-long-function-bodies=100
```

There were warnings in `LatsDeckScreen.swift` (for example a 318 ms action-key body and a 750 ms Fleet header getter) and a 171 ms warning in `FleetDeckVoiceBar`. There was no >100 ms compiler warning for the actual solo `LatsDeckScreen.body` around line 2158. These are compiler times, not runtime frame times. Splitting the 4,134-line file is good maintenance and can improve build times, but doing so without new observation/equality boundaries will not fix the transition.

## Structural suspect check

- **Broad `@ObservedObject` invalidation:** confirmed and measured; high-priority steady-state issue.
- **Missing `Equatable` on wire models:** no; snapshot components are already equatable. The missing piece is using smaller equatable presentation projections/boundaries.
- **`AnyView` erasure:** present in the general `LatsTopBar` API (`apps/ios/Sources/LatsDesignSystem.swift:26`), but `LatsDeckScreen` uses its own `LatsTopChrome` and does not hit that erasure on the solo root. Not causal here.
- **`.id()` churn:** `apps/ios/Sources/LatsDeckScreen.swift:2238` uses `.id(effectiveDeckID)`. The ID is stable across polls and changes only when switching decks, where resetting the grid is intentional. Not causal here.
- **Eager construction:** confirmed by local presentation and subtree A/B measurements.

## Decode executor finding

Relevant path:

- `apps/ios/Sources/DeckStore.swift:446-450` starts on the main actor and awaits `client.snapshot`.
- `apps/ios/Sources/DeckBridgeClient.swift:244-268` resumes the protected request and calls `openProtectedResponse`.
- `apps/ios/Sources/DeckBridgeSecurityStore.swift:251-270` decodes the envelope, decrypts, and decodes the snapshot.
- The app is Swift 5 mode (`apps/ios/LatticesCompanion.xcodeproj/project.pbxproj:523,583`) with no default-main-actor setting.

I called a temporary probe through `DeckBridgeClient` from `Task { @MainActor in ... }`, suspended, then used the client's real encoder/decoder. It reported `Thread.isMainThread == false`. That empirically confirms the plain async client method resumes on the generic executor in this configuration. Because the decrypt/decode calls are synchronous inside that nonisolated async client chain, they should remain off main; only the returned snapshot assignment is main-actor work.

Limitation: the Simulator was not paired to a live Mac, so I did not capture an actual encrypted full-snapshot response. The protected-path conclusion is executor inference backed by the client probe, not a live ChaChaPoly stack trace. If this must be made invariant rather than configuration-dependent, put decrypt/decode behind an explicit nonisolated worker/actor and add an assertion/signpost test.

## Recommended fix order

1. **Protect presentation:** replace the fixed 300 ms delay with actual transition-completion signaling and a cheap local snapshot-derived shell; remove the two automatic refreshes from the cached-snapshot path. This is the quickest user-visible win.
2. **Stop whole-tree snapshot churn:** introduce stable presentation projections and equatable boundaries for cockpit and keys; stop root-level forwarding of every secondary-store change. This addresses the measured 37 ms 1 Hz hitches and also reduces mount/diff work.
3. **Reduce/stage the two heavy subtrees:** cockpit and shortcut grid independently account for the largest A/B savings. Cache their derived arrays, avoid sorting/mapping in root body evaluation, and if needed mount them on separate turns after transition completion.
4. **Keep solo polling targeted:** retain the current selected-host-only `.fast` logic. Reserve fleet-wide `.fast` for Fleet Deck.
5. **Optimize recording waveform:** one `Canvas`, activity/visibility gating, lower/adaptive cadence.
6. **Run the physical-device GPU pass before shadow edits:** prioritize repeated tile/icon shadows only if Core Animation shows offscreen-render/render-server pressure.
7. **Refactor the monolithic source for build maintainability**, but do not count that alone as a runtime fix.

## Verification after fixes

On the operator's iPad Pro, record SwiftUI + Animation Hitches + Core Animation while tapping the same host 10 times (first run and warm runs separately). Add `os_signpost` intervals for tap, cover content creation, cockpit mount, grid mount, snapshot assignment, and protected decode. Success criteria should be no >16.7 ms main-thread hitch during the 60 Hz transition (ideally <8.3 ms on the 120 Hz panel), and no visible 1 Hz hitch when only telemetry/timestamps change.

## Build verification

After removing all temporary instrumentation, a clean Debug simulator build of the current working tree succeeded with `xcodebuild` for the iPad Pro 13-inch (M5) simulator. Existing Home preview trailing-closure warnings remain; there were no errors.
