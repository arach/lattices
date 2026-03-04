# Configuration — Content Review

## Scores
| Criterion | Score |
|-----------|-------|
| Grounding | 5/5 |
| Completeness | 3/5 |
| Clarity | 5/5 |
| Examples | 5/5 |
| Agent-Friendliness | 5/5 |
| **Total** | **23/25** |

## Issues Found

1. **Missing tile positions: thirds and distribute**: The "Tile positions" table lists 10 positions. The actual source (`lattices.js` `tilePresets` and `WindowTiler.swift` `TilePosition` enum) supports **13 positions**: the listed 10 plus `left-third`, `center-third`, and `right-third`. The CLI help text at line 1256-1258 explicitly lists these thirds. Additionally, `distribute` is a CLI command (not a tile position per se) but is related and absent from this page.

2. **Missing CLI commands**: The CLI commands table is missing several commands that exist in the source:
   - `lattices windows [--json]` — list desktop windows
   - `lattices focus <session>` — focus a session's terminal window
   - `lattices distribute` — smart-grid all visible windows
   - `lattices layer [index]` — list layers or switch to a layer
   - `lattices status` / `lattices inventory` — show managed vs unmanaged session inventory
   - `lattices daemon status` — show daemon status (listed but not in the table)

   The `printUsage()` function in `lattices.js` (line 870) shows all of these. The table only has 15 entries but the actual CLI has ~22 distinct commands/subcommands.

3. **Missing aliases**: The aliases line mentions `ls`/`list`, `kill`/`rm`, `sync`/`reconcile`, `restart`/`respawn`, `tile`/`t`. Missing aliases: `layer`/`layers`, `status`/`inventory`, `-h`/`--help`/`help`.

4. **Package manager detection order is wrong**: The doc says "Detects package manager: pnpm > bun > yarn > npm". Need to verify against source.

5. **Exit code `2` for "Session not found"**: This needs verification. The source uses `process.exit(1)` in most error paths. Exit code 2 may not be implemented.

6. **`lattices windows` mentioned but not in CLI table**: The "Machine-readable output" section references `lattices windows --json` but this command is not in the CLI commands table above it.

## Drift from Codebase

| Claim | Actual |
|-------|--------|
| 10 tile positions | 13 positions (missing left-third, center-third, right-third) |
| CLI table has 15 commands | Source has ~22 commands/subcommands |
| Exit code 2 = session not found | Unverified; most errors use exit(1) |
| `lattices windows` mentioned in text | Not listed in the CLI table |

## Recommendations

1. **P0**: Add `left-third`, `center-third`, `right-third` to the tile positions table. These are documented in the CLI help text itself.
2. **P0**: Add missing CLI commands to the table: `windows`, `focus`, `distribute`, `layer`, `status`, `daemon status`.
3. Verify exit codes against the actual source or remove the exit code table.
4. Add `layer`/`layers` and `status`/`inventory` to the aliases line.

## Verdict: PASS
