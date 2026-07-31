# Lats Fleet Deck — Design → Native implementation analysis

**Scope:** analysis only. No repo files were modified. Written 2026-07-19 outside the
repo, filed here 2026-07-29.

**Design source:** claude.ai/design project `e010d8da-…`, file `Lats Fleet Deck.html`
(read via the claude_design MCP `get_file`; returned untruncated, `truncated:false`).

**Native source:** `/Users/art/dev/lattices/apps/ios/Sources/` —
`LatsDeckScreen.swift` (Fleet types at 2519–4103), `DeckStore.swift`, `ContentView.swift`.

---

## 1. Revision visibility — what I can and cannot see

The claude_design MCP surface is file-oriented (`list_files` / `get_file`), **not**
revision-oriented: there is no per-file diff/history method. So I read the *current
published state* of `Lats Fleet Deck.html` and can describe it exactly, but I cannot
render a literal revision-over-revision diff. What I *can* establish about lineage from
internal evidence:

- The project contains a **separate, older sibling** `Lats Cockpit - iPad.html` — the
  single-Mac cockpit that the native `LatsDeckScreen` was originally ported from
  (per project memory). `Lats Fleet Deck.html` is the newer multi-Mac artifact; the
  project's `screenshots/` now carries a `fd-*` set (`fd-full`, `fd-deck`, `fd-lower`,
  `fd-now`, `fd-check`) that are Fleet-Deck reference captures.
- **Strong internal signal that the fader was recently re-purposed:** the CSS comment
  on the crossfader still reads *"one slot per host channel, aligned to the channel
  grid,"* but the live JS wires the fader to **command SETS** (`SETS` = 5 entries:
  WINDOW/AGENT/DEV/VOICE/SYSTEM), not to host channels. `selectSet()` re-renders the
  tile bay and the LCD. That stale comment vs. live behavior is the fingerprint of the
  latest change: **the crossfader moved from "route a Mac" to "select a command set."**

That single change is the most consequential delta vs. the native build, because the
current native Fleet Deck implements the *older* model (fader = channel router). See §3
and §5.

---

## 2. Design file — exact visual system

Root `#stage` centers a fixed **`.pad` 1376×1032** (iPad-landscape canvas) and JS
`fit()` scales it to the viewport. Everything is `var(--mono)`, 12px base.

**Vertical stack inside `.pad`** (gap 9px, padding `12 16 9`):

1. **`.fd-top`** (h 26) — brand `LATS · DECK` (700 + faint dot + `DECK`), right group
   `4 MACS` + close ✕. Bottom hairline `rgba(255,255,255,.07)` + shadow seam.
2. **`.fd-channels`** (h **252**) — CSS grid `repeat(4,1fr)`, radius `10px 10px 0 0`,
   one `.chan` per Mac, left hairline between columns. Per channel:
   - `.chan-head` (border-bottom dotted): `CH 0x` cap, device SVG icon, device name.
   - `.chan-ctx`: left `CURRENT APP` label (10.5px, tracked) + app name **16px** +
     sub file (ellipsized); right `.chan-metrics` CPU/MEM/WIN (`em` label + `b` value,
     tabular-nums).
   - `.chan-tape`: `AGENT LOG` + `IDLE`, then rows `[dot color][AGENT label 52px][text]`.
   - `.chan-foot` (border-top): `ON DECK` / `STANDBY` with dot; active channel's foot
     turns green + glowing dot.
   - `.chan.active` = subtle top-down white gradient wash.
3. **`.fd-route`** (radius `0 0 10px 10px`, pulled up `-9px` to fuse with channels) —
   the LCD/mixer:
   - `.route-top` grid `1fr auto 1fr`: left cap, center **`.led-win` LCD** panel
     (`SET 01 — WINDOW`, black inset, `text-shadow` glow), right `SET 1 / 5`.
   - `.f-track` **crossfader**: `grid-template-columns:repeat(N,1fr)` (N = 5 sets),
     `.f-rail` recessed bar, one `.f-slot` per set (tick dot + label), and a **machined
     aluminum `.f-handle`** (28×28, radius 5): layered `linear-gradient` +
     `repeating-linear-gradient` knurling + inset highlight/shadow, plus a `::before`
     recessed groove and `::after` bright center scribe line. Slides with
     `transition:left .3s cubic-bezier(.22,1,.36,1)`.
4. **`.fd-deck` → `.deck-panel`** (radius 12, embossed, 30px grid texture background,
   deep inset shadow) — a *single enclosure* containing:
   - **`.panel-head`** (embossed ledge, inset top highlight): left Mac name
     `Arach MacBook Pro`, right `Xcode · FleetDeckScreen.swift`.
   - **`.panel-body`** grid **`250px 1fr 320px`**, gap 16, inset shadow (well):
     - left `.panel-col.left`: `.mcard.mstats.recent` (host + `14ms` + CPU/MEM/GPU
       `.mbar` bars) and `.mcard.mdisp` (displays `D1/D2` toggle + `.dviz` 2×2 window
       grid). `.mcard.recent` draws white **corner-bracket ticks** via 8 layered
       gradients.
     - center `.panel-center`: `.pc-status` ghosted (**opacity .66**) two lines —
       `LIVE <task>` (18px) and `NEXT <task>` (16px, dimmer). A JS-injected
       **`.tp-cross` crosshair** (vertical + horizontal 1px lines, green dot, live
       `X … Y …` readout) tracks `pointermove` over `.panel-body`.
     - right `.panel-col.right`: `.mcard.mtx` transcript quote, `.mcard.mact` activity
       (`CODEX`/`SCOUT`/`BUILD` rows, `52px 1fr`).
   - **`.deck-tiles`** command bay: grid `repeat(3,1fr)` × 2 rows = **6 tiles**, h 162.
     Each `.tile`: `auto 1fr` grid, **34×34 icon** (radius 9, radial gradient, inset
     emboss), title **14px**, meta `NN · <verb>` (9px uppercase). Hover/active lift.
   - **`.deck-keys`** keyboard strip (embossed ledge, mirrors panel-head): groups
     `esc ⌘C ⌘V ⌘Z ⇥→ space` / arrow cluster / `⌃ ⌥ ⇧ ⌘ ↵enter`. Keys are molded caps
     (radius 7, inset highlight, press translateY).
5. **`.fd-status`** (h 26, full-bleed `margin:0 -16px -9px`) — status bar: green
   `● ONLINE`, Mac name, spacer, then `MACS 4`, `AGENTS 7`, `CPU 24%`, `MEM 52%`,
   `NET 14ms`, `SET · WINDOW` (green). Grouped by left hairlines.
6. **`.tweaks`** dev panel (Motion still/alive, Bloom off/on) — persisted to
   localStorage; drives `#pad.motion-alive` sweep/breathe animations and
   `#pad.bloom-on` overhead radial. Developer toy, not product chrome.

**Tokens / lighting / texture:**
- Colors: `--grn` = `--acc` (system.css green), `--vio` `oklch(.70 .15 300)`,
  `--blu` `oklch(.73 .11 250)`, `--amb` `oklch(.80 .12 82)`, `--red` `oklch(.68 .16 25)`.
  Cards `#0b0c0e`; breaks white `.08`/`.05`.
- Type: `var(--mono)` (JetBrains Mono in the design system) at 9–18px; uppercase labels
  tracked `.1–.24em`; `font-variant-numeric:tabular-nums` on all metrics/LCD.
- Radii: pad 14 · channels/route 10 · deck-panel 12 · mcard 5 · tiles 9 · keys 7.
- Lighting: radial page + pad gradients; embossed ledges (`inset 0 1px 0 rgba(255,…)`
  over dark) on panel-head/keys; machined-metal fader; LED glow via `text-shadow`;
  bloom overlay; 30px grid on the deck well.
- Motion (only when `motion-alive`): `barsweep` on `.mbar` fills, `livebreathe` on the
  transcript live dot, `actbreathe` on an activity row; all gated by
  `prefers-reduced-motion`.

---

## 3. Intended interaction model (Design)

- **Channels row = a 4-Mac monitor.** Each channel shows that Mac's context (current
  app/file), vitals (CPU/MEM/WIN), and its agent log. Exactly **one** channel is
  *active / ON DECK* (CH 01 in the mock); the others are STANDBY. (Note: the mock JS
  does not wire channel clicks — the active channel is fixed — but the `.chan.active`
  styling + `ON DECK/STANDBY` semantics make clear that **tapping a channel = choose
  which Mac feeds the common deck**.)
- **Crossfader = command-set mixer.** The fader parks on one of **5 command sets**
  (WINDOW · AGENT · DEV · VOICE · SYSTEM). Moving it (`selectSet`) swaps the tile bay to
  that set's 6 buttons, updates the LCD (`SET 0i — NAME`), the counter (`SET i/5`), and
  the status-bar `SET · NAME`. The handle animates to the chosen slot.
- **Common deck = the active Mac's live surface:** header names the Mac + frontmost app,
  the body is its trackpad (crosshair + ghosted LIVE/NEXT agent status) flanked by
  stats/displays (left) and transcript/activity (right), the tile bay is the selected
  command set, and the keyboard strip sends raw keys.

So the Design separates the two axes cleanly: **channel (which Mac)** is chosen in the
top lanes; **command set (which 6 actions)** is chosen on the fader/LCD.

---

## 4. Section-by-section map: Design → native SwiftUI

| Design section | Native type / member | File · approx lines |
|---|---|---|
| Presentation / router | `FleetDeckScreen` in `.fullScreenCover` | ContentView.swift:99–105 |
| `.pad` shell, landscape vs portrait | `FleetDeckScreen.fleetLayout` / `landscapeDecks` / `portraitDecks` | LatsDeckScreen.swift:2525, 2585, 2625, 2699 |
| `.fd-top` topbar | `fleetTopBar` (LATS·DECK, `N-UP` badge, `N MACS`) | 2604–2623 |
| `.fd-channels` (one `.chan`) | `FleetLanePicker` (header / contextStrip / agentTape / routeFooter) | 2896–3163 |
| `.chan-head` | `laneHeader` (`CH 0x`, machine icon, label, LIVE/LINK) | 2964–2994 |
| `.chan-ctx` (CURRENT APP + metrics) | `contextStrip` (CONTEXT + activeApp/Window + CPU/MEM/WIN) | 2996–3029, 3141 |
| `.chan-tape` (AGENT LOG) | `agentTape` + `agentEntries` (activityLog → cockpit agentRows) | 3051–3139 |
| `.chan-foot` ON DECK/STANDBY | `routeFooter` (ROUTED TO DECK / TAP TO ROUTE) | 3031–3049 |
| `.fd-route` fader + `.f-handle` | `FleetLaneFader` (**but routes channels, not sets**) | 2781–2886 |
| `.led-win` LCD / `SET i/5` / status SET | **no native equivalent** | — |
| `.deck-panel` enclosure | `FleetSharedDeck` (landscape) / `FleetMachineDeck` (portrait) | 3165–3514, 3516–~4100 |
| `.panel-head` (Mac · file) | `FleetSharedDeck.deckHeader` (+ page tabs) | 3281–3334 |
| `.panel-body` grid 250/1fr/320 | `LatsTrackpadSurface` (left cols / center / right cols / bezels) | 374–535 |
| left `.mstats` / `.mdisp` | `CompactSystemPanel` / `CompactDisplaysPanel` | 676–894 |
| center `.pc-status` + crosshair | `LatsTrackpadModeVisual` (idle/rec/replay/agent) | 998–1129 |
| right `.mtx` / `.mact` | `CompactTranscriptPanel` / `CompactActivityLogPanel` | 896–994 |
| `.deck-tiles` command bay | `LatsShortcutGrid` of `LatsShortcutTile` (from `activePage.tiles`) | 1475–1556, 1661–1792, 3231–3251 |
| `.deck-keys` keyboard strip | `LatsActionKeyboardRow` (+ `ModifierKey` sticky chords) | 1164–1471 |
| `.fd-status` status bar | **no native equivalent** (per-deck `deckFooter` instead) | 3336–3363 |
| `.tweaks` / bloom / motion | not ported (dev toy) | — |
| Data source | `DeckStore` snapshot; `DeckFleetStore` secondary sessions; `fleetPreview` mock | DeckStore.swift:13, 497, 576–712 |

---

## 5. Prioritized delta list

### MUST match (product-model / identity)
1. **Fader semantics — decide the model (owner call).** Design's latest fader is a
   **command-set mixer** (WINDOW/AGENT/DEV/VOICE/SYSTEM) with an LCD readout; native's
   `FleetLaneFader` is a **channel router** (which Mac → deck), with command sets
   surfaced instead as small **page tabs** in `deckHeader` (2307–2329). These are
   different mental models. This is the one delta that changes structure and must be
   resolved before anything else.
2. **LCD route/set readout** (`.led-win` `SET 0i — NAME`, `SET i/5`) — the signature
   element of the route strip; absent natively.
3. **Bottom status bar** (`.fd-status`: ONLINE · Mac · MACS/AGENTS/CPU/MEM/NET · SET).
   Native shows a *per-deck* footer (`OUTPUT · CPU · LANE READY`) — a different object.
   Note `AGENTS 7` implies a **fleet-aggregate agent count** native does not compute.

### SHOULD match (visual fidelity)
4. **Single deck enclosure vs. split.** Design is one `.deck-panel` (head→body→tiles→
   keys) as a unit; native splits it into `LatsCockpitShell{ trackpad }` (h 280) + a
   separate scrolling `LatsShortcutGrid`, and the keyboard lives *inside* the trackpad
   bottom bezel, not on an embossed strip under the tiles. Consider unifying to the
   enclosure + embossed ledges (panel-head/keys `inset` highlight).
5. **Machined-aluminum fader handle** (knurled multi-gradient cap + center scribe +
   `.3s cubic-bezier` slide). Native knob (2844–2862) is a simpler rounded-rect.
6. **Trackpad crosshair with live X/Y** and **ghosted LIVE/NEXT** status (opacity .66).
   Native has a mode visual but no crosshair/coordinate readout.
7. **`.mcard.recent` corner-bracket ticks**, 30px grid on the deck well, embossed
   ledges — texture cues currently softened natively.
8. **Command tile fidelity:** Design icon **34px** + meta `NN · <verb>`; native
   `LatsShortcutTile` icon **25px** + meta `act.NN · category` (1687). Tile grid is
   fixed **3×2 / 6** in Design; native derives columns from live tile count (3232).
9. **Typography:** Design uses `--mono` (JetBrains Mono) + oklch accents; native uses
   system `.monospaced` (LatsFont.mono, 51) + sRGB approximations (LatsPalette, 7–27).

### Intentional / acceptable native deviations
10. **SF Symbols instead of inline SVG** icon sets — correct for a native app.
11. **Live, data-driven tiles** from `store.snapshot.cockpit.pages` with real
    `actionID`s (3466–3480) instead of the Design's fixed 5×6 static set — functionally
    superior; keep.
12. **Portrait pager** (`FleetMachineDeck` in a `TabView`, 2699–2710) — a native
    responsive affordance the single fixed-canvas Design doesn't cover; keep.
13. **`N-UP` badge + horizontal scroll** of lanes for >4 Macs — native scale handling
    beyond the Design's fixed 4 columns; keep.

---

## 6. Effects / assets / data assumptions not represented natively

- **CSS effects absent natively:** knurled aluminum fader gradients; LED `text-shadow`
  glow; `.mcard.recent` corner brackets; embossed ledges (`inset` highlight over dark);
  30px deck-well grid; bloom radial overlay; `barsweep`/`livebreathe`/`actbreathe`
  animations (+ `prefers-reduced-motion` gating); crosshair overlay + live X/Y.
- **Data the Design assumes that native fleet chrome doesn't compute:** fleet-aggregate
  `AGENTS` count; a global `NET 14ms` latency figure in the status bar; a fixed
  **5-set** command model (`SET i/5`); per-Mac `WIN` count in the LCD context (native
  has WIN in the lane picker but not in a route LCD).
- **Assets:** Design ships inline `DEV` SVGs (laptop/studio/mini) + ~30 command SVGs and
  `system.css` tokens. Native substitutes SF Symbols + `LatsPalette`/`LatsFont` — fine.
  The `screenshots/fd-*.png` in the project are reference captures, not shipping assets.
- **Fonts:** if parity matters, the app must bundle JetBrains Mono; otherwise accept the
  system-monospaced deviation and match sizes/tracking only.

---

## 7. Recommended sequence + verification rubric

**Sequence (gated on the model decision):**
1. **Decide the fader model** (owner). If Design wins → introduce a command-set concept:
   either map live `cockpit.pages` onto the 5 named sets, or add a set layer above pages;
   move set-selection onto the fader and re-home channel-selection to the lane taps.
2. Add the **LCD route/set readout** to the route strip.
3. Add the **bottom `.fd-status` bar** (incl. a fleet agent-count aggregate + net RTT);
   reconcile with the current per-deck footer.
4. Fidelity pass: unify the **deck enclosure** + embossed ledges; upgrade the **fader
   handle**; add **crosshair X/Y** + ghosted LIVE/NEXT; restore corner ticks + deck-well
   grid; bump tile icon to 34px and align meta text.
5. Typography pass (JetBrains Mono + oklch-matched accents) if the font is bundled.

**Verification rubric (side-by-side at iPad landscape ≈ 1376×1032):**
- Channels: 4 equal columns, one ON DECK, CPU/MEM/WIN + agent tape present.
- Route: fader travel matches slot count; LCD + counter + status-bar set label agree.
- Deck body: proportions read as `250 / 1fr / 320`; left stats+displays, center
  trackpad w/ crosshair, right transcript+activity.
- Command bay: 3×2 grid, 34px icons, `NN · verb` meta.
- Keyboard: esc/⌘C/⌘V/⌘Z/⇥/space · arrows · ⌃⌥⇧⌘ · enter.
- Status bar groups render and update.
- Dark-load with no flicker (matches the recent web-view background fix); respects
  reduced-motion.

---

### Owner / next move
The fader-semantics decision (§5.1) is a product-model choice for the deck-builder owner
(`lattices.deck-builder-mac.arts-mac-mini-local`), not something to resolve unilaterally.
Everything else is fidelity work that can proceed once that axis is fixed. No repository
changes were made.
