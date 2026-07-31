# Lats Fleet Deck — design review vs. native iPad app

**Reviewer:** senior FE/product-design pass (SwiftUI + high-fidelity control surfaces)
**Scope:** analysis only — no repo files edited/built/committed. Written 2026-07-19 outside the repo, filed here 2026-07-29.
**Baseline:** merged `63aab23`. DEBUG fixture: `--fleet-preview` → `FleetDeckPreviewHost(machineCount:4)` (LatsDeckScreen.swift:2756–2779).
**Sources read:** `artifacts/Lats-Fleet-Deck.html`, `artifacts/system.css`, `artifacts/PROVENANCE.md`, prior `design-analysis.md`; native `LatsDeckScreen.swift` (fleet 2519–4101), `DeckStore.swift`, `ContentView.swift`.

---

## 1. Recommendation: **SYNTHESIZE** (lean Design on the fader's *job*, keep Native's routing + data truth)

The central decision is really about **removing a redundancy**, not choosing a winner:

- **Design (latest HTML):** lanes conceptually pick the Mac (ON DECK / STANDBY — but the mock never wires channel clicks; CH 01 is hardcoded `active:true`, HTML 486). The **physical fader is the only wired control** and it selects one of **5 command sets** (WINDOW/AGENT/DEV/VOICE/SYSTEM, HTML 560–576) → swaps the 6-tile bank, drives the LCD (`SET 01 — WINDOW`) and the status-bar SET label.
- **Native:** lane taps **really** route a Mac to the deck (`FleetLanePicker.onSelect` → `selectedSessionID`, 2629–2659). But `FleetLaneFader` (2781–2886) *also* routes the Mac — **so the fader duplicates the lane taps.** Command sets are demoted to small header page-tabs (`deckHeader` 3307–3329).

**The native fader has no unique job.** The operator explicitly wants to *keep* a tactile physical fader ("bottom-aligned controls… one stable tactile common deck"), so deleting it is off the table. The clean resolution is the Design's division of labor:

> **Route the Mac by tapping its lane. Select the command bank with the fader.**

This gives the fader the one job it lacks, and it creates a tight cause→effect adjacency: the fader sits directly above the tile bay it now controls — slide it, the bank right below re-banks, the deck enclosure itself stays put ("one stable tactile common deck"; only the bank content swaps, exactly as the HTML's `selectSet()` re-renders only `#tiles` + LCD, HTML 605–613).

**Two deliberate departures from the Design (keep Native's strengths):**
1. **Command sets stay data-driven** from `store.snapshot.cockpit.pages` (2 pages / 6+4 tiles in the fixture, DeckStore 602–625) — *not* the Design's hardcoded 5 sets × 6 tiles. The fader slot count adapts to the routed Mac's page count.
2. **The LCD names both axes** — routed Mac (`CH 0i`) *and* active bank (`SET 0i — NAME`) — reconciling the two controls into one readout.

### Exact operator workflow (post-synthesis)

1. Enter Fleet Deck (`.fullScreenCover`, ContentView 99–105). Landscape → 4 Mac lanes on top.
2. **Tap a lane** → routes that Mac to the common deck (ON DECK/STANDBY; accent border). Deck header names the Mac + frontmost file. *(unchanged native behavior)*
3. **Slide the fader** (route strip, above the deck) → parks on a command bank. LCD updates `CH 0i · SET 0j — NAME`, the tile bay re-banks, status-bar SET label updates, handle animates ≤0.3s. *(fader's new job)*
4. **Tap a tile** → fires on the routed Mac (`perform`, 3493–3508). **Keyboard strip / trackpad** → raw input. *(unchanged)*
5. **Re-route to another Mac** → fader re-populates with that Mac's banks, parks on bank 1; LCD shows new CH + SET.
6. **Portrait** → keep the pager + page strip (a horizontal fader is awkward on a narrow single-deck pager; intentional deviation, see §5).

---

## 2. Highest-impact ideas, ordered by value

1. **Fader → command-bank selector; route Macs by lane tap** *(model — do first)*. Kills the fader/lane redundancy; gives the tactile control a real job; keeps sets truthful/adaptive. Touches `FleetLaneFader` (2781–2886) + `landscapeDecks` (2625–2677) + lift `selectedPageID` out of `FleetSharedDeck` (3170).
2. **LCD route/set readout** (`.led-win`, HTML 118–124): recessed black inset, tabular-nums, text-glow via `.shadow`. Signature element; gives the fader semantic feedback. No native equivalent today.
3. **Unify the deck into one enclosure** (`.deck-panel` head→body→tile-bay→keys as a single bordered unit, HTML 163–277). Native currently splits it: `LatsCockpitShell{trackpad}` at fixed h=280 (3193–3225) + a *separate scrolling* `LatsShortcutGrid` (3237–3251), with the keyboard buried in the trackpad bezel. Unifying with embossed head/keys ledges is the single biggest "stable tactile deck" win.
4. **Machined-aluminum fader handle** (HTML 139–149: layered `linear`+`repeating-linear` knurl, recessed `::before` groove, bright `::after` scribe, `.3s cubic-bezier(.22,1,.36,1)` slide). Current knob is a plain rounded-rect + center bar (2844–2862).
5. **Bottom fleet status bar** (`.fd-status`, HTML 326–335 / 445–455): full-bleed, hairline-grouped: `● ONLINE · <Mac> · MACS N · AGENTS Σ · CPU% · MEM% · SET·NAME`. **Truthful subset only** — MACS=`stores.count`, AGENTS=Σ live agent rows across stores, CPU/MEM from the routed Mac's telemetry, SET from the fader. **Omit `NET 14ms`** (no truthful source — see §5). Native only has a per-deck footer (`deckFooter` 3336–3363), a different object.
6. **Trackpad crosshair + live X/Y + ghosted LIVE/NEXT** (HTML 226–238, 630–646): 1px cross, 7px green dot, `X … Y …` 9px readout; `pc-status` LIVE (18px) / NEXT (16px) at opacity .66. Adds precision cue + agent status on the control surface.
7. **Command-tile fidelity bump**: icon **25→34px** (`iconBadge` 1732 → HTML `.tile-ic` 317), keep `NN · verb` meta (already at 1687), and lock the bank to a fixed **3×2 / 6** where the page supplies ≥6 tiles (native derives columns from count, 3232).
8. **Texture cues**: `.mcard.recent` corner-bracket ticks (HTML 185–195), 30px deck-well grid (HTML 166–168), embossed `inset 0 1px 0 rgba(255,255,255,.09)` ledges on panel-head/keys (HTML 173, 260). Mostly folds into #3.
9. **Adaptive fader slot count** (2..N): render N=page-count slots, degrade labels gracefully past ~5 (abbreviate; rely on LCD for the full name). Keeps the control truthful where the Design hardcodes 5.
10. **Typography parity**: bundle **JetBrains Mono** + oklch-matched accents (HTML 11–14), or accept the system-`.monospaced` deviation (`LatsFont.mono`) and match sizes/tracking only. Lowest priority.

---

## 3. Section-by-section Design → native SwiftUI map

| Design section | Native type / member | File · lines |
|---|---|---|
| Presentation / router | `FleetDeckScreen` in `.fullScreenCover` | ContentView.swift:99–105 |
| `.pad` shell; landscape vs portrait | `FleetDeckScreen.fleetLayout` / `landscapeDecks` / `portraitDecks` | LatsDeckScreen.swift:2585, 2625, 2699 |
| `.fd-top` topbar (`LATS·DECK`, `N MACS`, ✕) | `fleetTopBar` (+ `N-UP`/`SWIPE` badge) | 2604–2623 |
| `.fd-channels` → one `.chan` | `FleetLanePicker` | 2896–3163 |
| `.chan-head` (`CH 0x`, dev icon, LIVE) | `laneHeader` | 2964–2994 |
| `.chan-ctx` (CURRENT APP + CPU/MEM/WIN) | `contextStrip` / `laneMetric` | 2996–3029, 3141–3150 |
| `.chan-tape` (AGENT LOG rows) | `agentTape` / `agentEntries` | 3051–3139 |
| `.chan-foot` ON DECK / STANDBY | `routeFooter` | 3031–3049 |
| `.fd-route` fader + `.f-handle` | `FleetLaneFader` **(routes Macs — repurpose to banks)** | 2781–2886; knob 2844–2862 |
| `.led-win` LCD / `SET i/5` / status SET | **none — build new** | — |
| `.deck-panel` enclosure | `FleetSharedDeck` (landscape) / `FleetMachineDeck` (portrait) | 3165–3514 / 3516–3976 |
| `.panel-head` (Mac · file) | `FleetSharedDeck.deckHeader` (**holds page tabs — move to fader**) | 3281–3334 |
| `.panel-body` 250 / 1fr / 320 | `LatsTrackpadSurface` (via `LatsCockpitShell`) | 374–535; shell 3193–3225 |
| left `.mstats` / `.mdisp` | `CompactSystemPanel` / `CompactDisplaysPanel` | ~676–894 |
| center `.pc-status` + crosshair | `LatsTrackpadModeVisual` (idle/rec/replay/agent) | ~998–1129 |
| right `.mtx` / `.mact` | `CompactTranscriptPanel` / `CompactActivityLogPanel` | ~896–994 |
| `.deck-tiles` command bay | `LatsShortcutGrid` of `LatsShortcutTile` | grid 1475–1556; tile 1661–1792; wired 3231–3251 |
| `.deck-keys` keyboard strip | `LatsActionKeyboardRow` (+ `ModifierKey`) | 1164–1471 |
| `.fd-status` status bar | **none — per-deck `deckFooter` instead** | 3336–3363 |
| `.tweaks` / bloom / motion | not ported (dev toy) | — |
| Data | `DeckStore` snapshot; `DeckFleetStore`; `fleetPreview` fixture | DeckStore.swift:576–712 |

---

## 4. Minimal implementation slices (each independently shippable + verifiable under `--fleet-preview`)

- **Slice A — model (smallest fix).** Lift `selectedPageID` from `FleetSharedDeck` (3170) up to `FleetDeckScreen`. Repoint `FleetLaneFader` from `selectedIndex=channel` to `selectedIndex=pageIndex` of the routed store; `onSelect(i)` → set that page. Relabel `"CHANNEL ROUTE"` / `"DECK OUT · CH"` (2811, 2821) → `"COMMAND BANK"` / `"SET · <NAME>"`. Mac routing stays on lane taps (already there). Remove the header page-tabs in landscape (3307–3329); reclaim that space for the frontmost-file `ph-r` readout. *No new chrome — resolves the redundancy alone.*
- **Slice B — LCD.** New `FleetRouteLCD` subview in the route strip: `CH 0i` + `SET 0j — NAME` + `SET j / N`, recessed inset + `.shadow` glow. Pure presentation; `accessibilityHidden` (fader carries the value).
- **Slice C — handle craft.** Replace the knob (2844–2862) with a machined cap (layered gradients + 2×14 center scribe); animate `knobX` with `.spring`/`.easeOut(0.28)` as the cubic-bezier analog.
- **Slice D — enclosure.** Wrap header/trackpad/tile-bay/keyboard into one bordered `.deck-panel`; move `LatsActionKeyboardRow` out of the trackpad bezel onto a dedicated embossed ledge under the tile bay; add embossed head/keys ledges + 30px well grid. *(Higher effort — after A–C.)*
- **Slice E — status bar.** `fleetStatusBar` at the bottom of `fleetLayout` (below the deck, above safe area): ONLINE · routed Mac · `MACS N` · `AGENTS Σ` · `CPU%` · `MEM%` · `SET·NAME`. Truthful data only; reconcile with (or replace) `deckFooter`.
- **Slice F — fidelity.** Tile icon 25→34; crosshair overlay + ghosted LIVE/NEXT; `.mcard.recent` corner ticks. Lowest risk; last.

---

## 5. Risks & intentional deviations

- **Truthful data — `NET ms` has no source.** `DeckSystemTelemetry` (DeckStore 662–668) has CPU/MEM/GPU/windowCount/sessionCount, **no latency**. `latencyMs` exists only in the Home model and its adapter hard-codes `nil` (HomeDataAdapter 171/205/226); only `HomeMockData` (213) shows `14`. → **Omit NET from the status bar** (or gate it on a real `health` RTT if/when one lands). Do **not** fabricate. `AGENTS Σ` *is* truthful (sum live `agentRows`/`activityLog` across stores).
- **Variable banks vs. fixed 5×6.** Design hardcodes 5 sets × 6 tiles; native pages vary (fixture: 2 pages, 6 & 4 tiles). Fader slot count and the tile bay must adapt (don't force empty 3×2 cells). *Intentional.*
- **Portrait keeps the page strip.** A horizontal fader on a narrow single-deck pager is poor ergonomics; retain `FleetMachineDeck.deckPageStrip` (3709–3733) in portrait. *Intentional.*
- **Touch targets.** Design handle is 28×28; iOS HIG wants ≥44pt hit area. The fader gesture already spans the whole track (`minimumDistance:0`, 2865–2873) and the row is 58pt (2660) — keep the *hit* region ≥44pt even if the visual cap is smaller.
- **Accessibility.** Preserve `accessibilityAdjustableAction` on the fader (2877–2883) — repoint value to "Command set n of N". Keep `FleetLanePicker`'s route label (2961). Mark the LCD decorative.
- **Safe areas.** The full-bleed `.fd-status` maps to a bottom bar inset **above** the home indicator — don't let it slide under the safe area.
- **Reduced motion.** Gate the handle slide + any bar-sweep on `@Environment(\.accessibilityReduceMotion)` (Design already gates its motion via `prefers-reduced-motion`, CSS 294–295).
- **Keep, don't "fix":** SF Symbols over inline SVG (correct native choice); data-driven live tiles/pages over static sets; `N-UP` badge + horizontal lane scroll for >4 Macs; portrait pager. These are native affordances the fixed 1376×1032 Design doesn't cover.

---

## 6. Simulator visual rubric (exact sizes / states)

**Harness:** launch `--fleet-preview` (`FleetDeckPreviewHost(machineCount:4)`); iPad **landscape ≈ 1366×1024** (matches the DEBUG `#Preview`, 4112–4116; Design pad is 1376×1032). Verify `.preferredColorScheme(.dark)`, no flash.

- **Lanes:** 4 equal columns; lane width ≥245pt (`laneWidth` clamp 2692–2697); row height `min(255, max(225, h·0.25))` (2647). Exactly **one ON DECK** (accent border 1pt + 2pt top bar; 2947–2952), rest STANDBY. Per lane: `CH 0x` 8pt-bold, machine icon 11pt, LIVE/LINK dot 5pt, CONTEXT app 11pt, CPU/MEM/WIN values 9pt, AGENT TAPE ≤3 rows (label 6pt / 42pt-wide, 3081–3099).
- **Fader (route strip):** row 58pt (2660); N slots = **routed Mac's page count** (fixture: 2); handle parked on the active bank; slide ≤0.3s; center LCD `SET 0j — NAME` 13pt w/ glow; right `SET j / N`; left `CH 0i`. Handle hit-region ≥44pt.
- **Deck enclosure:** single bordered panel, radius 12; header 42pt (Mac left, `Xcode · <file>` right); body proportions read **250 / 1fr / 320**; trackpad center shows crosshair (1px lines, 7px green dot, `X…Y…` 9pt) + ghosted LIVE (18pt) / NEXT (16pt) at opacity .66; tile bay **3×2 = 6**, icon **34px**, title 14pt, meta `0i · verb` 9pt; keyboard ledge: `esc ⌘C ⌘V ⌘Z ⇥ space / ← ↑ ↓ → / ⌃ ⌥ ⇧ ⌘ ↵enter`, keys 31pt tall / ≥42pt wide.
- **Status bar:** 26pt; hairline-grouped `● ONLINE`(green) · Mac · `MACS 4` · `AGENTS Σ` · `CPU%` · `MEM%` · `SET·NAME`(green); sits above the home-indicator safe area; **no NET group**.
- **Interaction states to capture:**
  (a) route Mac A→B — lane ON DECK moves, deck header + LCD `CH` update;
  (b) slide fader bank1→bank2 — tile bay re-banks, LCD `SET` + status SET update, handle animates;
  (c) tile press — scale 0.985 + shadow drop (1713–1720);
  (d) trackpad drag — crosshair follows, X/Y updates; tap → click;
  (e) **reduced-motion ON** — no slide/sweep;
  (f) **portrait** — pager + page strip, one deck per page;
  (g) **empty** — "No reachable Macs" (2719–2727);
  (h) **1-up** — single `LatsDeckScreen` path (2541–2542).

---

## 7. Product decision memo

- **Decision:** **Synthesize.** Fader becomes the **command-bank selector** (adopt Design's division of labor + its signature LCD/machined handle). **Mac routing stays on lane taps** (keep Native's real, direct interaction). One **LCD** reconciles both axes (`CH 0i · SET 0j — NAME`). Command banks remain **data-driven** from `cockpit.pages`, not the Design's hardcoded 5.
- **Why:** eliminates the current fader↔lane-tap redundancy; keeps the tactile fader the operator wants and gives it a real job with tight fader→tile-bay adjacency; the deck enclosure stays stable while only the bank swaps; adopts the highest-craft Design elements without sacrificing truthful or adaptive data.
- **Guardrails:** omit `NET ms` (no truthful source); compute `AGENTS` from live rows; portrait keeps the page strip; preserve ≥44pt touch targets, the adjustable-fader a11y, safe-area insets, and reduced-motion gating.
- **Sequence:** Slice **A** (model) first, behind `--fleet-preview`; verify against the §6 rubric in Simulator; then **B→F**.
- **Owner / next move:** greenlighting the **fader repurpose** is the deck-builder-mac owner's product call — it changes the interaction model, so it should be their explicit yes before implementation. Everything after is fidelity work gated on that yes. **No repo changes were made in this review.**
