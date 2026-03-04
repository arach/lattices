# Concepts — Content Review

## Scores
| Criterion | Score |
|-----------|-------|
| Grounding | 5/5 |
| Completeness | 4/5 |
| Clarity | 5/5 |
| Examples | 3/5 |
| Agent-Friendliness | 4/5 |
| **Total** | **21/25** |

## Issues Found

1. **Incorrect RPC method and event counts (again)**: Repeated claim of "20 RPC methods and 3 real-time events" appears in the Glossary "Daemon" entry and the "Agentic architecture" section. Actual count is **26 endpoints** and **4 events** (`windowsChanged`, `tmuxChanged`, `layerSwitched`, `processesChanged`).

2. **Window tiling description is partially outdated**: The "Window Tiling" glossary entry says "halves, quarters, maximize, center" — this omits the `top`, `bottom`, `left-third`, `center-third`, `right-third`, and `distribute` positions that exist in both `WindowTiler.swift` (`TilePosition` enum) and `lattices.js` (`tilePresets`).

3. **"Tiling uses AppleScript bounds"**: This is true for the CLI (`lattices.js` uses `osascript`), but the Swift app uses the Accessibility API (`AXUISetAttributeValue` with `kAXPositionAttribute`/`kAXSizeAttribute`) as the primary path, falling back to AppleScript. The statement is misleading for the app's tiling behavior.

4. **CGWindowList fallback order**: The doc says CGWindowList is path 1, AX is path 2, AppleScript is path 3. This needs to be cross-checked against `WindowTiler.swift`. The actual code uses CGWindowList for discovery, AX for the actual move/resize, and AppleScript as a final fallback for Terminal.app/iTerm2. The description conflates "finding" with "navigating".

5. **No copy-pasteable code examples on this page**: The page is conceptual, but an agent trying to understand how to use lattices gets no runnable examples. The "Quick taste" from overview.md could be referenced here.

6. **Session naming description is accurate**: The `toSessionName()` function in `lattices.js` and the description match: `basename-hash6`. Verified.

7. **SkyLight APIs listed are accurate**: The five private API calls match what's used in the source.

## Drift from Codebase

| Claim | Actual |
|-------|--------|
| "20 RPC methods, 3 real-time events" | 26 endpoints, 4 events |
| "halves, quarters, maximize, center" | Also includes top, bottom, thirds, distribute |
| "Tiling uses AppleScript bounds" | CLI uses AppleScript; app uses AX API primarily |
| Session naming `<basename>-<hash>` | Correct; first 6 hex chars of SHA-256 |

## Recommendations

1. Update the RPC/event counts to match `LatticesApi.swift` and `EventBus.swift`.
2. Update the Window Tiling glossary entry to mention thirds and distribute.
3. Clarify that the CLI tiles via AppleScript while the app tiles via AX API.
4. Add a brief code example (or cross-link) so the page is more agent-actionable.

## Verdict: PASS
