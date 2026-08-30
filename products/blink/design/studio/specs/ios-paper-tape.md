# Blink iOS — "Paper Tape"

A purely visual design direction for the read-only iOS/iPadOS companion.
Scope: composition, hierarchy, material, type, row anatomy, motion, responsive
behavior. **No product behavior changes.** Preserved as-is: read-only,
offline-first recall; list, search, workspace scope, peer sync status, note
detail; native iPhone/iPad idiom.

Target medium: a code-native study in `design/studio` (registered alongside
`MenubarPopoverStudy` / `NotePanelStudy`), not a ship-ready patch to
`apps/ios/BlinkMobile/ContentView.swift`.

---

## 1. Thesis

**On the Mac, Blink is spatial. In the pocket, Blink is chronological.**

The phone cannot give you a desk, so it should stop pretending. What it can give
you is the same workspace **read as a continuous tape** — a paper column of notes
running under a graphite instrument rail that carries everything the machine
knows (time, pin, day boundaries, sync). The paper stays clean because the rail
absorbs the metadata.

That split — *human ink on paper, machine ink on graphite* — is the whole
direction. It is the same graphite-and-paper world as the Mac popover
(`CapturePopoverView`), rotated 90° into a single scrolling column.

### What this direction fixes in the current build

| Observed | Read |
| --- | --- |
| Dark mode surfaces are forest green (`#07100B`/`#101C15`/`#2D4637`) | Inherited from the landing page's `[data-theme="black"]`, not from the app. The Mac popover's dark world is neutral graphite. The phone currently looks like a different product than the Mac. |
| `Available offline` sits in a card with an **amber** dot | Amber reads as warning. Offline is this product's *correct, default, promised* state. The hero feature is being drawn as a fault. |
| Title block + sync card consume ~40% of the first viewport | Three note rows visible on a 6.9" display. A recall app should show the log. |
| `Text(note.updatedAt, style: .relative)` → `6 hrs, 23 mins` | Live-ticking, two-unit, variable-width. Noisy, and it re-lays out the row while you read. |
| Separators inset to ~x=136 | Aligned to nothing in the row. Reads as an accident. |
| Disclosure chevrons on custom-filled rows | Redundant with the push affordance; adds a third right-edge element after the timestamp. |
| No search match highlighting | The single biggest functional gap for a recall-first product. |

---

## 2. Screen composition

### 2.1 List (iPhone, compact)

```
┌──────────────────────────────────────────────┐
│ ⧉                                         ((•))│  toolbar: mark+workspace / link
│                                              │
│ Launch                                       │  large title = WORKSPACE
│ ──────────────────────────────────────────── │  status rule (2pt, state-colored)
│ LINKED · STUDIO-MINI · 2H AGO                │  mono status line  (tap → sheet)
│                                              │
│ LOG                                    7 REC │  instrument header
├──────┬───────────────────────────────────────┤
│14:22 │ Launch checklist                      │
│  ▪   │ Verify the encrypted LAN handshake —  │
│      │ read notes after the Mac disconnects… │
│      │ launch · #release                     │
│      ├─────────────────────────────────────  │
│ MON  │ Pairing notes                         │
│      │ Payloads are sealed end to end …      │
│      │ hudson · #security                    │
│      ├─────────────────────────────────────  │
│ 4 AUG│ Saturday                              │
│  ▲   │ ← rail (44pt)   ▲ plate                │
└──────┴───────────────────────────────────────┘
        ╭──────────────────────────────╮
        │ ⌕  SEARCH · LAUNCH           │        bottom search pill
        ╰──────────────────────────────╯
```

**Must-have moves**

1. **The workspace is the large title.** `blink` shrinks to the `BlinkMark` in
   the leading toolbar item (which is already the workspace menu — so the mark
   *is* the scope control). The biggest text on screen tells you where you are,
   matching the Mac's workspace scope. Wordmark-as-title is vanity; it is the
   one thing the user never needs to be told.
2. **Sync card → status rule.** ~110pt of card becomes a 2pt full-bleed rule +
   one mono line, ~34pt total. Net recovery: ~6 rows in the first viewport
   instead of 3.
3. **The rail** (§4) is introduced as a persistent 44pt leading gutter.
4. Search stays bottom-anchored and thumb-reachable — that placement is already
   right; only its typography and match feedback change.

Vertical rhythm from the safe-area top: toolbar 44 · large title block 52 ·
status rule + line 34 · 16 gap · instrument header 26 · rows.

### 2.2 Detail (reader)

Unchanged structure, tightened:

```
   ▪ MARKDOWN / READ ONLY            ← eyebrow, mono, ink-muted
   Launch checklist                  ← serif largeTitle, ink-strong
   AUG 1, 2026 · 17:20 · LAUNCH      ← mono meta, one line, no icon
   ────────────────────────────────  ← rule, full measure
   (body)
   #release  #ios                    ← mono chips at the foot
```

- The eyebrow's `▪` is the `BlinkMark`, 14pt, signal. It is the only signal-blue
  element in the reader.
- Meta collapses to one mono line; drop the `square.grid.2x2` glyph — at 12pt it
  is texture, not information. The workspace name in mono says it better.
- Body measure clamped to **68 characters** (≈ the existing 720pt cap, expressed
  typographically so it survives Dynamic Type).
- Optional: a 1px `rule`-colored vertical line at the reader's leading margin,
  full column height — the rail's echo, so detail and list feel like one object.

---

## 3. Color tokens

Two palettes, both graphite-and-paper. **No green anywhere.** The landing page's
forest world is the marketing site's identity; the app's is the popover's.

### 3.1 Light — *Paper*

| Token | Hex | Use | Contrast on `paper-0` |
| --- | --- | --- | --- |
| `paper-0` | `#F2F0EC` | canvas | — |
| `paper-1` | `#FCFAF6` | plate, pressed row, reader sheet | — |
| `paper-2` | `#E8E5DF` | recessed field, search pill | — |
| `rail` | `#EBE7DF` | rail gutter fill | — |
| `rule` | `#DAD5CB` | hairlines, separators | 1.28 (non-text) |
| `ink-strong` | `#17130F` | titles, reader body | 16.2 |
| `ink` | `#342F2A` | primary body | 11.6 |
| `ink-mid` | `#5C554F` | excerpt | 6.4 |
| `ink-muted` | `#6F695F` | mono meta, rail stamps | 4.8 |
| `ink-faint` | `#8F8880` | ≥17pt or decorative only | 3.1 |
| `ink-ghost` | `#ADA79E` | never text; dividers/ticks | 2.1 |
| `signal` | `#2D5DAF` | the one live thing | 5.6 |
| `signal-soft` | `rgba(45,93,175,0.10)` | search match fill | — |
| `amber` | `#7E6029` | **degraded data only** | 5.1 |

### 3.2 Dark — *Graphite*

| Token | Hex | Use | Contrast on `graphite-0` |
| --- | --- | --- | --- |
| `graphite-0` | `#0A0B0C` | canvas | — |
| `graphite-1` | `#121416` | plate, pressed row | — |
| `graphite-2` | `#17191C` | reader sheet, search pill | — |
| `rail` | `#0E1012` | rail gutter fill | — |
| `rule` | `#2A2E31` | hairlines, separators | 1.44 (non-text) |
| `ink-strong` | `#FBEEE8` | titles, reader body (warm — paper remembered) | 17.4 |
| `ink` | `#D2D5D3` | primary body | 13.3 |
| `ink-mid` | `#9AA0A2` | excerpt | 7.4 |
| `ink-muted` | `#7A7F81` | mono meta, rail stamps | 4.9 |
| `ink-faint` | `#5F6467` | ≥17pt or decorative only | ~3.2 |
| `ink-ghost` | `#3D4143` | never text; dividers/ticks | 1.9 |
| `signal` | `#83B4FF` | the one live thing | 9.3 |
| `signal-soft` | `rgba(131,180,255,0.14)` | search match fill | — |
| `amber` | `#D6B96C` | **degraded data only** | 10.3 |

Both palettes are lifted from `PopoverPalette.light` / `.dark`
(`CapturePopoverView.swift:1645–1700`) so the two apps are provably one product.
`ink-mid`/`ink-muted` are retuned to clear 4.5:1; the current
`secondaryInk`/`faintInk` do not.

### 3.3 The signal rule (must-have)

> **Signal blue marks exactly one thing per screen: what is live right now.**

- List: the status rule + its square, *or* the search-match highlight when
  searching. Never both.
- Row: nothing. Pins are `ink-strong`, not signal — a pin is a user's decision,
  not a live event.
- Reader: the eyebrow mark, and list-item bullets. Nothing else.

Everything else is ink. This is what stops a warm-neutral app from turning into
a blue-accented iOS template.

### 3.4 The amber rule (must-have)

> **Amber means "this data is not what it claims."**

Only: `snapshot.issues > 0` (last-known notes retained), or a snapshot older
than 7 days. **Being offline is not amber.** Offline is neutral ink — it is the
product working.

---

## 4. Note-row anatomy

Two zones, separated by a continuous 1px `rule` running the full length of the
list. Minimum row height 72pt.

```
│◄── 44 ──►│◄── 14 ──►│                                    │◄18►│
│          │                                                     │
│   14:22  │  Launch checklist                                   │  ← title
│          │  Verify the encrypted LAN handshake — read notes    │  ← excerpt
│     ▪    │  after the Mac disconnects…                         │
│          │  launch · #release                                  │  ← mono meta
│          ├─────────────────────────────────────────────────────│  ← separator
```

### Rail (44pt, `rail` fill)

| Element | Spec |
| --- | --- |
| Stamp | mono 11pt medium, tracking 0.6, `ink-muted`, right-aligned to rail trailing −10, baseline aligned to the title's first baseline |
| Stamp format | `14:22` today · `MON` this week · `4 AUG` this year · `8·25` older. **Static** — computed once at snapshot load, never `Text(style: .relative)` |
| Pin | 5×5pt filled square, `ink-strong`, centered in the rail, 8pt below the stamp. Echoes `BlinkMark`'s two offset squares |
| Day tick *(optional)* | at each date boundary the rail's trailing rule thickens to 2pt for 10pt — a perforation |

The rail's continuity is the point. It is the tape; the rows are what is printed
on it.

### Plate

| Line | Spec |
| --- | --- |
| Title | `.headline` semibold, `ink-strong`, 1 line, truncate tail. **No trailing timestamp, no chevron** |
| Excerpt | `.subheadline`, `ink-mid`, 2 lines, `lineSpacing 2` |
| Meta | mono `.caption` 12pt, `ink-muted`, 1 line: `workspace · #tag`. No SF Symbol. Row omitted entirely when both are absent |
| Padding | top 12 / bottom 13 / trailing 18 |
| Separator | 1px `rule`, **leading inset = 58pt** (rail 44 + plate lead 14), full-bleed trailing. Replaces the current arbitrary ~136pt inset |
| Press | plate fill → `paper-1` / `graphite-1`, 120ms ease-out. No scale, no bounce |

### Accessibility sizes (≥ AX1)

The rail **collapses**: its content moves to the top of the plate as a mono line
(`14:22` / `MON 4 AUG` long form), rail fill removed, separator inset drops to
18pt. All HStacks become VStacks; excerpt 2 → 4 lines; title allowed 3 lines.
This is the same collapse strategy already in the codebase — keep it, now with
one thing to collapse instead of four.

---

## 5. Search and sync

### 5.1 Search

- Bottom pill, `paper-2` / `graphite-2` fill, 1px `rule`, radius 22, 52pt tall.
- Placeholder: mono 15pt `ink-muted`, `SEARCH · <WORKSPACE>` — the scope is
  stated inside the field, so a search in a workspace can never be mistaken for
  a global one.
- On focus the instrument header swaps `LOG` → `MATCHES` and the count becomes
  live (this already exists in `BlinkSectionHeader` — keep it, it's good).
- **Match highlighting (must-have):** matched substrings in title and excerpt get
  `signal-soft` fill (2pt horizontal padding, 3pt radius) **and** semibold
  weight. Weight carries it for color-blind and high-contrast users.
- Excerpt becomes **match-centered** while searching: the 2 shown lines window
  around the first body hit rather than always starting at the note's head.
  Recall products live or die on this.
- Empty result keeps `ContentUnavailableView.search(text:)` — native, correct.

### 5.2 Sync

Card → **rule**. Full-bleed 2pt bar directly under the large title, plus one mono
11pt line, tracking 1.0. Whole block is one tappable target (visual 34pt,
touch 44pt) opening the existing connection sheet.

| State | Rule | Square | Line |
| --- | --- | --- | --- |
| Offline copy | `ink-ghost` | none | `OFFLINE COPY · UPDATED 2H AGO` (`ink-muted`) |
| Connecting | `signal` @ 40% | none | `CONNECTING · STUDIO-MINI` |
| Linked | `signal` @ 55% | 5pt `signal` | `LINKED · STUDIO-MINI · 2H AGO` |
| Syncing | `signal` sweep (§7) | 5pt `signal` | `SYNCING` |
| Degraded | `amber` | 5pt `amber` | `3 NOTES RETAINED · UPDATED 6D AGO` |

State is **never** color-only — the mono word always names it.

The `internaldrive` / `lock.fill` icon tile is dropped. A 38pt icon to say
"offline" in an app whose entire premise is offline is a tautology occupying
prime real estate.

---

## 6. Light / dark behavior

- Both modes ship the full token set; `UITraitCollection` resolves them (keep the
  existing `adaptive(light:dark:)` helper — only the values change).
- **Light** is warm-neutral paper. `BlinkBackdrop`'s radial signal wash drops to
  `0.05` and moves to `UnitPoint(0.92, -0.04)` — a hint of daylight from the
  corner, not a tint.
- **Dark** is neutral graphite. Backdrop = flat `graphite-0` plus a 1.5% dither
  at the top-right. **The green gradient is removed entirely.**
- Elevation is carried by **hairlines, not shadows**, in both modes. One
  exception: the iPad reader sheet (§7).
- Nav/toolbar background stays `.ultraThinMaterial` — it is the one place system
  material is more credible than a custom fill.
- Increase Contrast: `rule` → `ink-faint`, `ink-mid` → `ink`, `signal-soft`
  opacity → 0.20, all separators to 1.5pt.

---

## 7. iPad adaptation

`NavigationSplitView(.balanced)`, sidebar 340pt (min 300, max 400).

- **Sidebar = the tape.** Identical rail + plate anatomy; stamps take their long
  form (`MON 14:22`). Selected row: `paper-1`/`graphite-1` fill with a **3pt
  signal bar in the rail** — the selection is live, so it earns the blue.
- **Detail = the panel on the desk.** This is the one place the spatial metaphor
  survives to iPad, and it is why iPad is not a large phone:

  - The reader is a **floating sheet**, not a full-bleed scroll view.
  - `paper-1` / `graphite-2` fill, 1px `rule`, radius 14, max width 680pt,
    centered on the `paper-0`/`graphite-0` canvas.
  - Padding 40 top / 56 sides / 64 bottom.
  - The **only** shadow in the app: `0 18 40 -18 rgba(40,32,20,0.28)` light,
    `0 22 48 -20 rgba(0,0,0,0.72)` dark. A note on a desk casts one.
  - Canvas behind it carries the `TerminalGrid` at 2% — the same grid the
    popover canvas uses.
- Search moves to the sidebar top at regular width (system default). The bottom
  pill is compact-only.
- Placeholder detail keeps `BlinkMark` + copy, centered in the sheet's footprint
  with the sheet rendered as a 1px dashed `rule` outline — the empty desk.
- *Optional:* hardware keyboard — ↑/↓ selection, ⌘F search, `Space` page-down.

---

## 8. Motion

Everything short, everything interruptible. Nothing loops.

| Moment | Spec | Tier |
| --- | --- | --- |
| Row press | fill 120ms `easeOut` | must |
| Push to reader | `.navigationTransition(.zoom)` sourced on the plate (iOS 18+); title cross-fades headline → serif largeTitle. Absent below 18 — no custom fallback | must |
| Sync state change | 220ms color cross-fade on rule + line | must |
| Snapshot arrival | square scales 1.0 → 1.35 → 1.0 over 300ms, **once** | must |
| Syncing sweep | 900ms `signal` gradient traveling L→R along the 2pt rule, repeating only while `isSyncing` | must |
| Pull-to-refresh | the rail fills top-down with `signal` in proportion to pull distance — the tape advancing — then releases | optional, high payoff |
| Row insertion after sync | 200ms fade + 6pt rise, staggered 20ms, capped at 6 rows | optional |

`.accessibilityReduceMotion` → all of the above become 150ms opacity
cross-fades; the sweep becomes a static `signal` @ 40% bar; the pull fill becomes
a static state change. No exceptions.

---

## 9. Accessibility constraints (all must-have)

1. Body and secondary text ≥ 4.5:1; `ink-faint` only at ≥17pt or decorative;
   `ink-ghost` never carries text.
2. No state encoded by color alone — sync always names itself in words; search
   matches carry weight as well as fill.
3. **The row is one accessibility element.**
   `label`: `"<title>, <workspace>, updated <full relative date>"` + `", pinned"`.
   `value`: excerpt. `traits`: `.isButton`.
   The rail stamp is `.accessibilityHidden(true)` — `8·25` and `MON` are display
   abbreviations and must never reach VoiceOver.
4. Dynamic Type through AX5 with the §4 collapse. No text truncated below its
   stated line allowance at any size.
5. Every tap target ≥ 44×44pt, including the visually-34pt sync rule.
6. The instrument header keeps its combined a11y label
   (`"Launch, 7 notes"`) — the `LOG / … / 7 REC` construction is visual only.
7. Reader keeps `.textSelection(.enabled)` and `.isHeader` traits on headings.
8. Mono tracking ≤ 1.2 anywhere it exceeds 3 words — tracked uppercase is a label
   device, not a text device.

---

## 10. The three details that make it unmistakable

1. **The rail.** A 44pt graphite gutter running unbroken down the whole list,
   holding the time, the pin, and the day perforations, and turning signal-blue
   as you pull to refresh. No other notes app has one. It is why the screen reads
   as a *tape* rather than a table, and it is what lets the paper column stay
   completely clean.

2. **The two-type-worlds law.** Everything a human wrote is set in system text
   and New York serif on paper. Everything the machine knows — times, counts,
   workspaces, tags, sync state, `MARKDOWN / READ ONLY` — is SF Mono, uppercase,
   tracked, in the graphite tier. There is no third register and nothing crosses
   over. One glance tells you which words are yours.

3. **Sync as a line, not a badge.** The peer-sync state is a 2pt rule spanning the
   full width under the title — quiet ink when you are offline (because that is
   the promise being kept), signal when a Mac is linked, a traveling sweep while
   it syncs, amber only when the data is stale. It occupies 34pt instead of 110pt
   and it is the first thing your eye crosses on the way to the notes.

---

## 11. Must-have vs optional

**Must-have — the direction does not exist without these**

1. Dark palette re-alignment to graphite; forest green removed.
2. Amber demoted to degraded-data-only; offline rendered neutral.
3. Header collapse — workspace as large title, sync as a rule.
4. The rail, with static (non-ticking) stamps.
5. The two-type-worlds law.
6. Signal rationed to one live thing per screen.
7. Separators aligned to the plate leading edge (58pt).
8. Search match highlighting, fill + weight, with match-centered excerpts.
9. iPad reader as a floating sheet on the canvas.
10. The full §9 accessibility set.

**Optional flourish — cut freely under time pressure**

1. Pull-to-refresh rail fill.
2. Zoom navigation transition.
3. Day-boundary perforation ticks in the rail.
4. `TerminalGrid` dither on dark canvas / iPad detail canvas.
5. Staggered row insertion after sync.
6. The reader's leading rule echoing the rail.
7. iPad hardware-keyboard navigation.

---

## 12. Notes for the study build

- Register as `IOSPaperTapeStudy` in `design/studio/src/studio/studioRegistry.ts`,
  alongside `MenubarPopoverStudy`.
- Render three frames: iPhone list (light), iPhone list (dark), iPhone reader
  (dark), plus one iPad split (either mode).
- Drive both palettes off one token object so the light/dark flip is a single
  prop — the study's job is to prove the two modes are the same design, which is
  precisely what the current build cannot claim.
- Reuse the landing site's mono stack for the machine tier; SF Mono is the
  shipping equivalent.
