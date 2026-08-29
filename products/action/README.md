# action

**[lattices.dev/action](https://lattices.dev/action)** · Native-first macOS automation, capture, and review from Lattices.

`action` is a local runtime for observing a Mac surface, executing deterministic actions, recording what happened, and preserving the result as inspectable session artifacts.

The project is built around a signed AppKit application, a local agent runtime, and shared CLI/MCP interfaces. Its strongest path today is native capture and replay; live inspection and durable companion jobs are the active development edge.

Source lives in the Lattices monorepo at [`products/action`](https://github.com/arach/lattices/tree/main/products/action).

## Status At A Glance

Working today:

- signed `Action.app` with a real AppKit lifecycle, menus, permissions UX, and embedded WebKit surfaces
- native screenshots plus region and app-window recording through `ScreenCaptureKit`
- asynchronous recording with explicit stop and finished markers
- guided capture sessions with trace, screenshots, manifests, replay, and in-app review
- current-surface inspection that can persist a screenshot, AX snapshot, and Apple Vision OCR
- deterministic runtime actions exposed through local CLI and MCP entrypoints
- a local HUD / console and repo-local native developer CLI

In active development:

- the long-lived Action Companion job queue and Rust supervisor
- provider-backed vision analysis and viewport-settling loops
- Chrome DOM observation and actions through the Chrome companion extension
- shared surface adapters, target evidence, and post-action verification
- Mira / character treatments used by launcher, session, and automation surfaces

Still mostly contract or roadmap work:

- trace-to-scenario generation and deterministic reruns from recorded sessions
- production composition, including zooms, subtitles, narration, and final rendering
- continuous computer-use perception and an autonomous observe → think → act loop
- a general-purpose editor

## Product Model

Action separates macOS lifecycle work from automation orchestration:

- `Action.app` owns AppKit, WebKit, permission UX, launcher and review UI, and the recording-probe lifecycle.
- `ActionAgent` owns local transport, native automation methods, and capture orchestration.
- the TypeScript runtime owns sessions, observations, targets, actions, traces, and artifact manifests.
- CLI and MCP are thin frontends over the same runtime concepts.
- compiler and composer packages consume runtime truth; they do not own live app control.

That boundary matters. WebKit and `ScreenCaptureKit` are reliable when they run inside a real app lifecycle, while automation clients need a stable service boundary that does not pretend to be the UI process.

## Current Workflows

### Capture And Review

1. Launch `Action.app`.
2. Select or stage a target surface.
3. Start a guided capture.
4. Execute deterministic actions while Action records video and trace data.
5. Stop through the live controls.
6. Review the playable session and its artifacts in-app.

### Inspect A Surface

1. Resolve the currently focused app/window.
2. Capture a screenshot and accessibility snapshot.
3. Run Apple Vision OCR by default.
4. Optionally request provider-backed image analysis.
5. Persist `session.json`, `manifest.json`, `trace.json`, and the observation artifacts under `artifacts/sessions/`.

The inspection path uses Action Companion when it is reachable and falls back to direct execution otherwise.

## Quick Start

Requirements:

- macOS on Apple Silicon
- Bun
- Xcode command line tools / Swift toolchain
- Accessibility and Screen Recording permission for `Action.app`

Install dependencies and build the signed app:

```bash
bun install
bun run native:app:build
```

Verify the bundle and native permissions:

```bash
bun run native:doctor
```

The current development doctor also checks the local vision-secret manifest. Provider-backed vision commands expect `MINIMAX_API_KEY` to be available through the local `secret` keychain helper; native capture itself does not use that provider.

Launch the app:

```bash
bun run action-dev -- launch
```

Run focused smoke checks:

```bash
bun run native:test:screenshot
bun run native:test:record
bun run typecheck
```

## CLI And Agent Surfaces

Use the product CLI for scenarios and inspection:

```bash
bun run action
bun run inspect:surface
bun run inspect:surface:vision
bun run scenario:calculator
```

Use the repo-local native CLI for the tightest app development loop:

```bash
alias action-dev='bun packages/cli/src/action-dev.ts'
action-dev relaunch
action-dev host guided-calculator-demo
action-dev logs
```

Useful native commands:

- `action-dev build`
- `action-dev rebuild`
- `action-dev launch`
- `action-dev relaunch`
- `action-dev quit`
- `action-dev doctor`
- `action-dev hud`
- `action-dev host <args...>`
- `action-dev agent <args...>`
- `action-dev agent-cli <args...>`

The MCP server exposes health, session creation, snapshot/OCR/vision/AX observation, target resolution, deterministic actions, asynchronous recording, and artifact listing:

```bash
bun run mcp
```

### Action Browser Plugin

Action Browser is the smallest agent-ready surface: it opens an isolated, real
Chrome profile in the background and exposes navigation, page inspection,
lightweight DOM actions, and PNG screenshots through MCP.

Install it from the Action plugin marketplace in Codex:

```bash
codex plugin marketplace add arach/lattices
codex plugin add action-browser@action
```

Start a new Codex task after installation, then ask:

> Open https://example.com in Action Browser, take a screenshot, and show it to me.

Claude Code uses its own plugin marketplace format. Install the same MCP bundle
with the Claude Code CLI:

```bash
claude plugin marketplace add arach/lattices
claude plugin install action-browser@action --scope user
```

Run `/reload-plugins` inside Claude Code to activate the MCP in the current
session. Run `/mcp` to confirm that `action-browser` is connected, then use the
same example prompt above.

Kimi Code reads the root `kimi.plugin.json` and installs the same bundle
directly from the GitHub repository. Pin the default branch — a bare
repository URL installs the latest release, which may predate the manifest:

```
/plugins install https://github.com/arach/lattices/tree/main
/reload
```

Run `/plugins info action-browser` to confirm the plugin loaded, then use the
same example prompt above.

This starter requires macOS, Google Chrome, and Bun. It drives **named Action-owned
Chrome identities** (default `agent-browser`), never your regular Chrome. To act on
a site you are signed in to, seed an identity with a selective cookie import rather
than handing the URL to your own browser; optionally load the Chrome Companion
extension for richer DOM tools.

```bash
# prepare a "work" identity + companion load-unpacked once
bun run chrome:companion:profile -- setup work
bun run chrome:companion:import:cookies -- import --into work --source "Profile 1" --domains github.com --confirm
```

Three browsers can be in play — your regular Chrome (open-only handoff, driven by
Action's native screen + accessibility tools), a blank Action browser, and an
Action identity seeded from one of your Chrome profiles (DOM tools, already signed
in). See [docs/browser-profiles.md](docs/browser-profiles.md) for the decision
table and the full `Profile 1` → `work` example.

Action Browser MCP tools include `browser_profiles`, `browser_use_profile`,
`browser_import_cookies`, and `browser_companion_status` in addition to open /
snapshot / click / screenshot.

### Action Companion

The in-development companion stores queued jobs, observations, artifacts, and vision timeline entries in a local SQLite database. A small Rust supervisor manages its process lifecycle.

```bash
bun run companion:start
bun run companion:status
bun run companion:doctor
bun run companion:stop
```

### Chrome Companion

The Chrome companion adds DOM-aware observation and actions for browser surfaces while preserving AX and native fallbacks.

```bash
bun run chrome:companion:build
bun run chrome:companion:install:dev
bun run chrome:companion:bridge
bun run chrome:companion:health
```

Treat this as a development integration, not a finished browser automation product.

## Distribution

Build a signed and notarized drag-to-Applications DMG:

```bash
bun run native:dmg:build
```

For local packaging without Apple notarization:

```bash
SKIP_NOTARIZE=1 bun run native:dmg:build
```

The output is `Installer/Action-for-Mac.dmg`.

Ship a public GitHub release from `main`:

```bash
bun run release:ship -- 0.3.0 --watch
```

The release workflow builds, signs, notarizes, verifies, and uploads generic and versioned DMG assets. It creates the `action-vX.Y.Z` tag only after verification passes and never replaces the repository-wide Lattices “Latest” release. Add `--no-publish` for an artifact-only run.

## Repository Layout

- `native/engine` — Swift app host, local agent, recording probe, UI, and native scripts
- `packages/protocol` — shared session, observation, target, action, and artifact types
- `packages/runtime` — sessions, inspection, adapters, interaction, providers, and companion client
- `packages/cli` — product and native-development CLI entrypoints
- `packages/mcp` — agent-facing MCP server
- `packages/companion` — durable local job queue and observation store
- `crates/action-supervisor` — companion process supervisor
- `packages/chrome-companion` — Chrome extension, local bridge, and browser tooling
- `packages/compiler` — scenario intent to executable timeline
- `packages/composer-core` — render-manifest contract
- `packages/composer-remotion` — early Remotion backend boundary
- `docs` — architecture, decisions, milestones, and runtime notes

## Important Runtime Notes

- Recording is asynchronous. A start response means startup was accepted, not that capture completed.
- Completion is represented by the output artifact plus its `.finished` marker.
- Actual recording work runs in a fresh `Action.app` instance in `recording-probe` mode.
- Prefer semantic, DOM, or AX targets. Coordinates are the final fallback.
- Provider secrets stay outside the native app and source tree.
- `artifacts/`, native build products, and local companion state are intentionally not source-controlled.

## Next Steps

The next milestone is **Agent Work Tape**: one complete proof that an agent can use Action to record and share its own computer use.

1. **Add the agent-friendly session facade.** Provide simple start, checkpoint, finish, and share operations over the existing runtime so agents never need to manage stop files or finished markers themselves.
2. **Drive the HUD from runtime truth.** Show agent identity, current task, recording state, meaningful checkpoints, and completion without decorative activity or duplicate supervision controls.
3. **Produce a shareable handoff.** Finish each run with video, timeline, artifacts, agent-friendly Markdown/JSON, and a local review link.
4. **Harden the golden path.** Make permissions preflight, interrupted-session recovery, artifact completeness, companion setup, and overlay cleanup dependable from a clean checkout.
5. **Strengthen action evidence.** Keep semantic, DOM, and AX targeting ahead of coordinates; expose ambiguity; and attach before/after observations to important actions.
6. **Derive reusable scenarios.** Once record-and-share is reliable, turn completed traces into editable scenario drafts and deterministic reruns.
7. **Compose after capture is solid.** Add production zooms, subtitles, narration, and rendering only after the work-tape contract is trustworthy.

The milestone is done when an agent can start Action, perform real work on macOS, finish the run, and receive a reviewable share bundle without an operator managing the recording lifecycle.

## Read Next

- [Getting Started](docs/getting-started.md)
- [Native Runtime](docs/native-runtime.md)
- [Recording](docs/recording.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Live Inspection Runtime](docs/LIVE_INSPECTION_RUNTIME.md)
- [Surface Adapter Plan](docs/SURFACE_ADAPTER_PLAN.md)
- [Composition And Scenarios](docs/COMPOSITION_AND_SCENARIOS.md)
