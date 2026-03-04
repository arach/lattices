# Menu Bar App — Content Review

## Scores
| Criterion | Score |
|-----------|-------|
| Grounding | 5/5 |
| Completeness | 3/5 |
| Clarity | 5/5 |
| Examples | 4/5 |
| Agent-Friendliness | 4/5 |
| **Total** | **21/25** |

## Issues Found

1. **Incorrect RPC method and event counts**: States "20 RPC methods" and "3 real-time events" in the Daemon section. Actual: 26 endpoints, 4 events. Same issue as overview.md and concepts.md (cross-page duplication of the incorrect count).

2. **Missing tile positions in app table**: The "Tile positions (app)" table lists 8 positions. The source `TilePosition` enum in `WindowTiler.swift` has **13 cases**: left, right, top, bottom, top-left, top-right, bottom-left, bottom-right, maximize, center, left-third, center-third, right-third. The app table is missing: **Top, Bottom, Left Third, Center Third, Right Third**.

3. **Missing hotkey actions**: The Shortcuts table in the Settings section shows `Cmd+Option+1/2/3` for layers but doesn't mention:
   - `Hyper+1` for Screen Map
   - `Hyper+2` for Window Bezel
   - `Hyper+3` for Cheat Sheet
   - `Ctrl+Option+Arrow/Letters` for tiling hotkeys

   These are all defined in `HotkeyStore.defaultBindings` and visible in the Shortcuts tab of the Settings UI.

4. **Settings tabs listed as three (General, Shortcuts, Docs)**: The actual source `SettingsView.swift` shows only **two internal tabs**: "General" and "Shortcuts". The "Docs" content is a separate page (`page == .docs`), not a settings tab. This is misleading.

5. **Missing `lattices app` launch flags**: The source `lattices-app.js` supports `--diagnostics` (`-d`) and `--screen-map` (`-m`) flags. These are not documented.

6. **Import path issue**: Same `lattices/daemon-client` import path issue as overview.md. No `exports` map in `package.json`.

7. **Auto-detection paths**: Lists `~/dev`, `~/Developer`, `~/projects`, `~/src` as auto-detection paths. Should be verified against the Swift source.

8. **Cross-page duplication of "20 RPC methods, 3 events"**: This exact claim appears on overview.md, concepts.md, and app.md.

## Drift from Codebase

| Claim | Actual |
|-------|--------|
| 8 tile positions in app table | 13 positions in `TilePosition` enum |
| "20 RPC methods" | 26 endpoints |
| "3 real-time events" | 4 events |
| Settings has "three tabs" | Two internal tabs (General, Shortcuts); Docs is a separate page |
| No mention of launch flags | `--diagnostics` and `--screen-map` exist |

## Recommendations

1. **P0**: Add Top, Bottom, Left Third, Center Third, Right Third to the tile positions table.
2. **P0**: Fix the settings tab count — clarify that Docs is a separate page, not a third settings tab.
3. **P1**: Add the full set of configurable hotkeys (tiling, app shortcuts) or link to a complete list.
4. **P1**: Document `--diagnostics` and `--screen-map` launch flags.
5. Fix the import path in the daemon example.
6. Update method/event counts.

## Verdict: PASS
