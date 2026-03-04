# Workspace Layers & Tab Groups — Content Review

## Scores
| Criterion | Score |
|-----------|-------|
| Grounding | 5/5 |
| Completeness | 4/5 |
| Clarity | 5/5 |
| Examples | 5/5 |
| Agent-Friendliness | 5/5 |
| **Total** | **24/25** |

## Issues Found

1. **Import path `lattices/daemon-client` will not resolve**: Same issue as overview.md and app.md. The programmatic switching example uses `import { daemonCall } from 'lattices/daemon-client'`. No `exports` map in `package.json`.

2. **Tile values section is incomplete**: The "Tile values" section lists 8 positions: `left`, `right`, `top-left`, `top-right`, `bottom-left`, `bottom-right`, `maximize`, `center`. It references the config page for the full list but omits `top`, `bottom`, `left-third`, `center-third`, `right-third` from its own inline list. Since the config page is also missing thirds, this creates a blind spot.

3. **Layer limit claim**: States "You can have up to 9 layers (Cmd+Option+1 through Cmd+Option+9)". The source `HotkeyAction` has `.layer1` through `.layer9` with `Cmd+Option+1-9` bindings. This is correct, but it's a hotkey limitation, not an architectural one. The workspace config itself has no layer count limit.

4. **`processesChanged` event not mentioned**: The page mentions `windows.changed`, `tmux.changed`, and `layer.switched` events but not `processesChanged`. This is consistent with other pages (all say "3 events") but technically incorrect.

5. **Excellent example coverage**: The page provides 7 distinct JSON examples covering: basic group, basic layer, groups in layers, single project, two-project split, group+project, and four quadrants. These are all valid and well-structured.

6. **Tab group session naming correct**: `lattices-group-<id>` matches `toGroupSessionName()` in `lattices.js`.

7. **Programmatic example is accurate**: The `daemonCall('layers.list')` and `daemonCall('layer.switch', { index: 0 })` calls match the registered endpoints in `LatticesApi.swift`. The return shape `{ layers, active }` matches the handler.

## Drift from Codebase

| Claim | Actual |
|-------|--------|
| Inline tile values list (8) | 13 positions available in source |
| "Up to 9 layers" | Correct for hotkeys; no config limit |
| `daemonCall('layers.list')` returns `{ layers, active }` | Matches source |
| `layer.switched` event name | Source uses `layerSwitched` internally; WebSocket broadcast name should be verified |

## Recommendations

1. Add `top`, `bottom`, `left-third`, `center-third`, `right-third` to the inline tile values list.
2. Fix the import path or add an `exports` map to `package.json`.
3. Clarify that the 9-layer limit is a hotkey constraint, not an architectural one.
4. This is the strongest page in the docs set. Consider using it as a template for other pages.

## Verdict: PASS
