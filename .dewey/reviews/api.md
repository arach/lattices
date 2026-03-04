# Daemon API — Content Review

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

### 1. Missing endpoints — 5 endpoints not documented
The source code in `LatticesApi.swift` registers **25** endpoints, but the doc says "20 RPC methods" and only documents **20**. The following are missing:

- **`processes.list`** — List interesting developer processes with tmux/window linkage. Accepts optional `command` param.
- **`processes.tree`** — Get all descendant processes of a given PID. Requires `pid` param.
- **`terminals.list`** — List all synthesized terminal instances (unified TTY view). Accepts optional `refresh` param.
- **`terminals.search`** — Search terminal instances by command, cwd, app, session, or hasClaude. Five optional filter params.
- **`layout.distribute`** — Distribute visible windows evenly across the screen. No params.

Additionally, the **`api.schema`** meta-endpoint is not documented (returns the full API schema). This is lower priority but worth mentioning.

### 2. Missing event — `processes.changed`
The doc says "3 real-time events" and documents `windows.changed`, `tmux.changed`, and `layer.switched`. The source code in `DaemonServer.swift` (`broadcastEvent`) also broadcasts a **4th event**: `processes.changed`, which fires with `interestingCount` and `pids`. This is undocumented.

### 3. Tile positions incomplete — 3 missing values
The doc lists 10 positions: `left`, `right`, `top`, `bottom`, `top-left`, `top-right`, `bottom-left`, `bottom-right`, `maximize`, `center`.

The actual `TilePosition` enum in `WindowTiler.swift` has **13** cases. Missing from docs:
- `left-third`
- `center-third`
- `right-third`

### 4. Default timeout mismatch
The doc says `daemonCall` default timeout is **5000ms** (line 133: "Custom timeout (default: 5000ms)"). The actual source in `daemon-client.js` line 18 shows the default is **3000ms**.

### 5. `windows.changed` event data shape is wrong
The doc shows the event data includes a full `"windows": [...]` array. The actual `DaemonServer.swift` (line 360-366) broadcasts:
```json
{
  "event": "windows.changed",
  "data": {
    "windowCount": 12,
    "added": [1234],
    "removed": [5678]
  }
}
```
The field is `windowCount` (an integer), **not** `windows` (an array). The doc's table says `windows` is a "Full current window list" — this is incorrect.

### 6. `tmux.changed` event data shape is wrong
The doc shows `"sessions": [...]` as an array of full session objects. The actual broadcast (line 369-375) sends:
```json
{
  "event": "tmux.changed",
  "data": {
    "sessionCount": 3,
    "sessions": ["name1", "name2", "name3"]
  }
}
```
- `sessions` is an array of **strings** (session names), not full session objects.
- `sessionCount` field is present but not documented.

## Drift from Codebase

| Doc claim | Actual (source) | Severity |
|-----------|-----------------|----------|
| "20 RPC methods" | 25 registered endpoints (+ `api.schema` = 26) | High |
| "3 real-time events" | 4 events (`processes.changed` missing) | Medium |
| Tile positions: 10 listed | 13 cases in `TilePosition` enum | Medium |
| `daemonCall` default timeout: 5000ms | 3000ms in `daemon-client.js` | Medium |
| `windows.changed` data has `windows` array | Has `windowCount` integer, no full array | High |
| `tmux.changed` data has full session objects | Has `sessionCount` + array of name strings | High |
| Import path `lattices/daemon-client` | No `exports` field in `package.json` | Medium |

## Structural Issues

### Import path validity
The doc uses `import { daemonCall } from 'lattices/daemon-client'` throughout. However, `package.json` has **no `exports` field**. Node.js subpath imports require an `exports` map to resolve `lattices/daemon-client` to `./bin/daemon-client.js`. Without it, this import will fail with `ERR_PACKAGE_PATH_NOT_EXPORTED`. Users would need to use a direct relative import or the `exports` field needs to be added to `package.json`.

### Error handling coverage
The doc includes a good "Errors" section (line 89-98) describing the three error types, and `daemonCall` documents that it "Throws if the daemon returns an error." However, there is **no try/catch example** showing how to handle an error response. Agents need to see what the catch block looks like.

### Operational lifecycle
Adequately covered in the "Connection lifecycle" section (lines 99-108). Documents disconnect, restart, and reconnect behavior. The note about `daemonCall` opening a fresh connection per call is accurate per the source.

### Event timing
The doc does not specify how frequently events fire. For `windows.changed`, there is no mention of debounce interval, polling rate, or batching behavior. An agent relying on these events may not know whether they are debounced or fire immediately on every window change. This should be documented.

### Cross-page duplication
The `daemonCall` import + usage pattern appears on `overview.md`, `layers.md`, and `app.md` as well. The snippets are contextually different (not verbatim multi-paragraph copies), so this is acceptable cross-referencing rather than problematic duplication.

### Install instruction currency
No explicit install instructions are given on this page. The package name `@arach/lattices` matches `package.json`. The `lattices app` command for launching the daemon is consistent with the `bin` field. Acceptable.

## Recommendations

1. **Add the 5 missing endpoints** (`processes.list`, `processes.tree`, `terminals.list`, `terminals.search`, `layout.distribute`) and the `api.schema` meta-endpoint. Update the count from "20" to the correct number.
2. **Add the `processes.changed` event** and update the count from "3" to "4".
3. **Fix the `windows.changed` event data shape** — replace `windows` array with `windowCount` integer to match the actual broadcast.
4. **Fix the `tmux.changed` event data shape** — show `sessionCount` integer and `sessions` as an array of strings (not objects).
5. **Add the three missing tile positions**: `left-third`, `center-third`, `right-third`.
6. **Fix the default timeout** from 5000ms to 3000ms.
7. **Add an `exports` field to `package.json`** so the `lattices/daemon-client` import path actually resolves, or update the docs to show a working import path.
8. **Add an error handling example** — a try/catch block showing what happens when `daemonCall` rejects.
9. **Document event timing** — note whether events are debounced, batched, or fire immediately.

## Verdict: PASS

Score is 21/25 which exceeds the 18-point threshold. The documentation is well-structured, clearly written, and has excellent agent integration patterns. However, there is significant drift from the implementation: 5 undocumented endpoints, incorrect event data shapes, missing tile positions, and a wrong default timeout. These should be corrected promptly to maintain trust with API consumers.
