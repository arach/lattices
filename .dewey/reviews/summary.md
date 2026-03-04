# Documentation Review Summary

**Reviewed**: 2026-03-03
**Source validation**: Cross-referenced against `lattices.js`, `lattices-app.js`, `LatticesApi.swift`, `WindowTiler.swift`, `HotkeyStore.swift`, `CommandModeState.swift`, `SettingsView.swift`, `EventBus.swift`, `package.json`

## Aggregate Scores

| Page | Grounding | Completeness | Clarity | Examples | Agent-Friendly | Total | Verdict |
|------|-----------|--------------|---------|----------|----------------|-------|---------|
| overview.md | 5 | 3 | 5 | 4 | 4 | **21/25** | PASS |
| quickstart.md | 5 | 3 | 5 | 3 | 4 | **20/25** | PASS |
| concepts.md | 5 | 4 | 5 | 3 | 4 | **21/25** | PASS |
| config.md | 5 | 3 | 5 | 5 | 5 | **23/25** | PASS |
| app.md | 5 | 3 | 5 | 4 | 4 | **21/25** | PASS |
| layers.md | 5 | 4 | 5 | 5 | 5 | **24/25** | PASS |
| **Average** | **5.0** | **3.3** | **5.0** | **4.0** | **4.3** | **21.7/25** | |

All pages PASS (18+ threshold). The weakest dimension across all pages is **Completeness** (3.3 average).

## Systemic Issues (appear on 3+ pages)

### 1. Incorrect RPC method and event counts [P0 -- 4 pages affected]
**Pages**: overview.md, concepts.md, app.md, layers.md (by reference)
**Claim**: "20 RPC methods, 3 real-time events"
**Actual**: **26 endpoints** registered in `LatticesApi.setup()`, **4 events** in `EventBus` (`windowsChanged`, `tmuxChanged`, `layerSwitched`, `processesChanged`)
**Fix**: Global find-and-replace "20 RPC methods" with the correct count. Add `processesChanged` to event lists.

### 2. Import path `lattices/daemon-client` will not resolve [P0 -- 3 pages affected]
**Pages**: overview.md, app.md, layers.md
**Claim**: `import { daemonCall } from 'lattices/daemon-client'`
**Actual**: `package.json` has no `exports` map. Node.js will throw `ERR_PACKAGE_PATH_NOT_EXPORTED`.
**Fix**: Add to `package.json`:
```json
"exports": {
  ".": "./bin/lattices.js",
  "./daemon-client": "./bin/daemon-client.js"
}
```

### 3. Missing tile positions: thirds [P0 -- 3 pages affected]
**Pages**: config.md, app.md, layers.md
**Actual positions in source** (`TilePosition` enum + `tilePresets` object): left, right, top, bottom, top-left, top-right, bottom-left, bottom-right, maximize, center, **left-third, center-third, right-third** (13 total)
**Fix**: Add left-third, center-third, right-third to all tile position tables.

### 4. Missing CLI commands from config.md table [P1]
**Commands missing from the table**: `windows`, `focus`, `distribute`, `layer`, `status`/`inventory`, `daemon status`
**Fix**: Add these to the CLI commands table in config.md.

## Priority Fixes (ordered by impact)

| # | Priority | Fix | Pages |
|---|----------|-----|-------|
| 1 | P0 | Add `exports` map to `package.json` so `lattices/daemon-client` resolves | overview, app, layers |
| 2 | P0 | Update "20 RPC methods" to 26 and "3 events" to 4 across all pages | overview, concepts, app |
| 3 | P0 | Add `left-third`, `center-third`, `right-third` to all tile position tables | config, app, layers |
| 4 | P1 | Add missing CLI commands (`windows`, `focus`, `distribute`, `layer`, `status`, `daemon status`) to config.md table | config |
| 5 | P1 | Fix settings tab description (2 tabs + separate Docs page, not 3 tabs) | app |
| 6 | P1 | Document `--diagnostics` and `--screen-map` app launch flags | app |
| 7 | P2 | Add Accessibility/Screen Recording permission note to quickstart | quickstart |
| 8 | P2 | Add error handling examples for common failures | quickstart |
| 9 | P2 | Add tiling hotkeys reference (Ctrl+Option+Arrow/Letters) to app.md shortcuts table | app |
| 10 | P2 | Verify exit code table against source (exit code 2 may not be implemented) | config |

## Cross-Page Duplication

| Duplicated content | Pages |
|-------------------|-------|
| "20 RPC methods, 3 real-time events" | overview, concepts, app |
| `import { daemonCall } from 'lattices/daemon-client'` code block | overview, app, layers |
| Tile position tables (partial overlap) | config, app, layers |
| `.lattices.json` example | quickstart, config |

The daemon-client import and RPC count are the most problematic duplications because they propagate the same error. The tile position tables and config examples are acceptable duplication for reader convenience.

## Strongest Page

**layers.md** (24/25) -- Excellent grounding, 7 distinct JSON examples, accurate API usage, clear structure. Use as a template for improving other pages.

## Weakest Dimension

**Completeness** (3.3/5 average) -- The main gap is missing tile positions (thirds) and CLI commands that exist in the source but are absent from the docs. This is a documentation-trailing-code issue, likely from recent feature additions (Phase 2 tiling) that were not reflected back into docs.
