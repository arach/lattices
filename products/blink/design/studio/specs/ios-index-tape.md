# Blink iOS — Index Tape

Pure visual synthesis by **Grok**, merging Opus **Paper Tape** and Kimi
**Ledger** into one direction. Product behavior is deliberately unchanged.

Controlled fixture (unchanged across the study matrix): Launch scope, offline
copy updated 2h ago, 3 REC, three notes (Launch checklist / Pairing notes /
Design review), same device geometry, read-only.

---

## 1. Thesis

**Chronology is the structure; ledger is the discipline.**

The pocket companion cannot be a desk, so it becomes a **carbon copy of the
desk log**: one continuous paper tape running under a machine rail. The rail
holds everything the machine knows — entry index, static time stamp, pin. The
paper holds only what a human wrote. Geometry is sharp and full-bleed (Ledger);
composition is chronological and dense (Paper Tape). Offline is the product
working, not a warning.

This is not a feature bag. One system wins every conflict:

| Conflict | Winner | Why |
| --- | --- | --- |
| Rounded cards vs zero-radius rules | Ledger | Soft cards read as iOS library; the desk is instrumented paper |
| Capsule / strip vs status rule | Paper Tape | Density and offline-as-success need the rule, not a hero card |
| Time rail vs numbered index | **Both, one gutter** | Rail stamps carry `%02d` over static time; pin replaces the index |
| Bottom dock vs top search | Paper Tape placement, Ledger sharpness | Thumb reach for compact; zero-radius mono field, not a pill |
| Forest dark vs graphite | Graphite | Same product as the Mac popover |
| Amber offline vs neutral offline | Neutral | Offline is the promised state |

---

## 2. Screen composition

### Log (iPhone, compact)

```
┌──────────────────────────────────────────────┐
│ [mark]                                   ((•))│  toolbar: workspace mark / link
│ Launch                                       │  large title = workspace scope
│ ════════════════════════════════════════════ │  2pt status rule (state-colored)
│ ■  OFFLINE COPY · UPDATED 2H AGO             │  square pip + mono line
│                                              │
│ LOG / LAUNCH                           3 REC │  instrument header
├────┬─────────────────────────────────────────┤
│ 01 │ Launch checklist                        │
│14:22│ Verify the encrypted LAN handshake —   │
│  ▪ │ read notes after the Mac disconnects…   │
│    │ launch · #release                       │
├────┼─────────────────────────────────────────┤
│ 02 │ Pairing notes                           │
│ MON│ Payloads are sealed end to end…         │
│    │ hudson · #security                      │
├────┼─────────────────────────────────────────┤
│ 03 │ Design review                           │
│4 AUG│ Keep note recall calm…                 │
│    │ blink · #ios                            │
└────┴─────────────────────────────────────────┘
│ SEARCH · LAUNCH                              │  sharp bottom index field
└──────────────────────────────────────────────┘
```

Vertical rhythm: toolbar 34 · title 40 · status rule+line 30 · section 24 ·
rows (min 84) · bottom field 36.

### Reader

```
   ■ MARKDOWN / READ ONLY     ← mono kicker + mark (only signal on the page)
   Launch checklist           ← New York large title
   AUG 1, 2026 · 17:20 · LAUNCH
   ──────────────────────────
   body…
   #release  #ios             ← sharp mono chips (0 radius or 2pt max)
```

Leading 28pt index gutter echoes the list rail (`01` at title baseline). Flat
canvas — no floating paper card, no botanical wash.

---

## 3. Color tokens

Graphite-and-paper. **No forest green.** Signal is the sole live accent.

### Light

| Token | Hex | Role |
| --- | --- | --- |
| `canvas` | `#F2F0EC` | ground |
| `surface` | `#FCFAF6` | plate / pressed |
| `raised` | `#FFFFFF` | search field fill |
| `rail` | `#EBE7DF` | machine gutter |
| `rule` | `#DAD5CB` | hairlines |
| `ink` | `#17130F` | titles, body |
| `secondary` | `#5C554F` | excerpts |
| `faint` | `#6F695F` | mono meta |
| `signal` | `#2D5DAF` | live only |
| `signal-soft` | `rgba(45,93,175,0.10)` | selection wash / match |
| `amber` | `#7E6029` | degraded data only |

### Dark

| Token | Hex | Role |
| --- | --- | --- |
| `canvas` | `#0A0B0C` | ground |
| `surface` | `#121416` | plate / pressed |
| `raised` | `#17191C` | search field fill |
| `rail` | `#0E1012` | machine gutter |
| `rule` | `#2A2E31` | hairlines |
| `ink` | `#FBEEE8` | titles (warm paper memory) |
| `secondary` | `#9AA0A2` | excerpts |
| `faint` | `#7A7F81` | mono meta |
| `signal` | `#83B4FF` | live only |
| `signal-soft` | `rgba(131,180,255,0.14)` | selection wash / match |
| `amber` | `#D6B96C` | degraded data only |

### Signal rule

One live thing per screen: status rule when linked/syncing, **or** search-match
highlight while querying, **or** the reader kicker mark. Never all three.

### Amber rule

Amber only for `snapshot.issues > 0` or data older than 7 days. **Offline copy
is neutral ink** — square pip is `ink-ghost` / faint, not amber.

---

## 4. Row anatomy

```
│◄── 48 ──►│◄ plate ─────────────────────────────│
│  01      │  Launch checklist                   │
│  14:22   │  excerpt two lines…                 │
│   ▪      │  launch · #release                  │
│          ├─────────────────────────────────────│  separator at plate lead
```

| Zone | Spec |
| --- | --- |
| Rail width | 48pt (`rail` fill), trailing 1px `rule` |
| Index | mono 9pt, `%02d`, `faint`, right-aligned. **Pin replaces index** (5×5 ink square) when pinned — Ledger law |
| Stamp | mono 8pt static time under index: `14:22` / `MON` / `4 AUG` — Paper Tape law, never live-relative |
| Title | SF 13pt semibold, `ink`, 1 line. No chevron, no trailing time |
| Excerpt | SF 10pt, `secondary`, 2 lines |
| Meta | mono 8pt, `faint`: `workspace · #tag` |
| Corners | **0 radius** everywhere on the list |
| Selection | `signal-soft` plate wash + 2pt signal bar on rail leading edge |

---

## 5. Search and sync

### Sync

Full-bleed **2pt rule** under the large title + one mono line with a **6pt square
pip** leading.

| State | Rule | Pip | Line |
| --- | --- | --- | --- |
| Offline copy (fixture) | `rule` / ghost | square, faint | `OFFLINE COPY · UPDATED 2H AGO` |
| Linked | `signal` @ 55% | square, signal | `LINKED · HOST · 2H AGO` |
| Syncing | signal sweep | square, signal | `SYNCING` |
| Degraded | amber | square, amber | `N NOTES RETAINED · …` |

### Search

Bottom **index field**, full width minus 0 inset to side rules: height 36pt,
**0 radius**, `raised` fill, top hairline only (reads as a ledger footer, not a
floating pill). Placeholder mono tracked: `SEARCH · LAUNCH`. Scope is stated
inside the field.

While querying: section `LOG` → `MATCHES`; optional match weight + `signal-soft`
fill on hits.

---

## 6. Light / dark, iPad, motion, a11y

- Light: warm-neutral paper. Dark: neutral graphite. No green gradient.
- Elevation by hairlines only on phone; iPad reader may use one restrained sheet
  shadow if the split study needs spatial depth later.
- iPad: 340pt sidebar = same Index Tape list; detail = flat reader with leading
  index gutter; search moves to sidebar top at regular width.
- Motion: row press 120ms fill; sync rule color 220ms; Reduce Motion → opacity
  cuts only.
- A11y: row is one element; rail stamps hidden from VoiceOver; Dynamic Type
  collapses rail content onto the plate; contrast ≥ 4.5:1 for body text; state
  never color-only.

---

## 7. Three unmistakable details

1. **Indexed machine rail** — continuous gutter with `%02d` over static time;
   pin square replaces the index, never decorates the title.
2. **Sync as rule + square** — Paper Tape density meets Ledger’s square state
   language; offline is quiet success.
3. **Zero-radius carbon geometry** — full-bleed rules, sharp search footer, no
   soft library cards.

---

## 8. Must-have vs optional

**Must-have**

1. Workspace as large title; `blink` reduced to mark-as-scope control.
2. 48pt rail with index + static stamp; pin replaces index.
3. Sync rule + square pip; offline neutral.
4. Zero-radius list and search field; no chevrons.
5. Graphite dark; signal rationed; amber degraded-only.
6. Two-type-worlds: SF / mono / New York labor split.
7. Controlled fixture content unchanged.

**Optional**

1. Day-boundary perforation on the rail rule.
2. Pull-to-refresh filling the rail with signal.
3. Match-centered excerpt window while searching.
4. iPad floating reader sheet (borrow Paper Tape only if split study needs it).

---

## 9. Lineage

| Inherited from | Kept |
| --- | --- |
| Paper Tape (Opus) | Continuous tape, rail stamps, workspace title, sync-as-rule, offline neutral, bottom search placement, two-type worlds, graphite |
| Ledger (Kimi) | Zero-radius rules, entry indices, square pip, pin-replaces-index, selection bar, flat reader, sharp mono discipline |
| Rejected from both | Paper Tape’s soft search pill radius; Ledger’s top native search as compact primary; Field Log capsule / forest dark (out of scope for this merge) |
