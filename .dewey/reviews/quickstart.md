# Quickstart — Content Review

## Scores
| Criterion | Score |
|-----------|-------|
| Grounding | 5/5 |
| Completeness | 3/5 |
| Clarity | 5/5 |
| Examples | 3/5 |
| Agent-Friendliness | 4/5 |
| **Total** | **20/25** |

## Issues Found

1. **Install command uses `npm` instead of noting the package manager**: Step 2 shows `npm install -g @arach/lattices` and the from-source section uses `npm link`. The project's own CLAUDE.md and `bun.lockb` indicate bun is preferred. While npm is fine for end users, the from-source step should at least mention `bun link` as an alternative.

2. **`lattices app` behavior described inaccurately**: Step 5 says "This builds (or downloads) and launches the native macOS companion." The actual code in `lattices-app.js` shows the `app` command (no subcommand) calls `ensureBinary()` which only builds/downloads if the binary doesn't already exist. "Builds (or downloads)" implies it always does this. The description should say "ensures the binary exists (building or downloading if needed) and launches."

3. **Command palette hotkey**: States `Cmd+Shift+M`. Source confirms this is the default (`keyCode: 46, cmdShift`). Correct.

4. **Missing error handling for common failures**: No mention of what happens when:
   - tmux is not installed and you run `lattices`
   - The Swift build fails (Xcode not installed)
   - The daemon is not running when you try `lattices app`

5. **No mention of Accessibility/Screen Recording permissions**: The app needs these for full functionality but the quickstart does not mention them at all. Users will be confused when tiling or "Go to" does not work.

6. **Cross-page duplication**: The `.lattices.json` example in Step 4 is nearly identical to the one on the config page. Acceptable for a quickstart but worth noting.

## Drift from Codebase

| Claim | Actual |
|-------|--------|
| "Open the command palette with Cmd+Shift+M" | Correct; matches `HotkeyStore.defaultBindings` for `.palette` |
| `lattices init` generates config with `"ensure": true` | Source `initConfig()` confirms this |
| "left pane (60%): claude, right pane (40%): dev command" | Matches `defaultPanes()` in `lattices.js` |

## Recommendations

1. Add a brief note about granting Accessibility and Screen Recording permissions after first launch.
2. Add a "Troubleshooting" micro-section or link for common failure modes (no tmux, no Swift).
3. Consider showing `bun install -g @arach/lattices` as an alternative.
4. Clarify that `lattices app` only builds on first run (not every run).

## Verdict: PASS
