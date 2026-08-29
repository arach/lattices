# ACT-001: Surface Adapter Architecture

## Status

Proposed

## Date

2026-05-09

## Decision Type

Architecture proposal and product direction

## Summary

Action will use an AX-first surface adapter architecture.

Every app surface starts with the macOS accessibility tree as the baseline
source of UI truth. First-class surfaces get complementary semantic channels
where those channels make Action faster, safer, or more precise.

This gives Action a small set of excellent high-volume integrations while
preserving a credible long-tail path through generic accessibility, native
capture, and vision verification.

## Context

Action is a native-first macOS automation runtime. It needs to observe, resolve,
act, verify, capture, and present what happened without unnecessarily fighting
the user's cursor, keyboard focus, or current work.

AX alone is universal but sometimes too shallow. It can tell us that Chrome has
a web area or that a terminal has a text region, but it often cannot expose the
semantic structure that users and agents care about.

At the same time, app-specific APIs alone are not enough. They can miss native
window state, permission reality, focus behavior, and what is visibly on screen.

The architecture therefore needs both:

- a universal native baseline
- specialized semantic adapters for the places builders actually live

## Decision

Action will introduce a runtime-level surface adapter system.

Each adapter must treat AX as the baseline observation layer. First-class
adapters may add app-specific semantic channels such as browser DOM inspection,
tmux state, editor extension APIs, filesystem context, or local app metadata.

The runtime should merge these channels into one observation envelope and use
evidence-based target resolution before acting.

## Principles

- AX first, specialized channels second.
- Prefer semantic actions over focus-taking input.
- Prefer verified targets over coordinate clicks.
- Warn before any action that may steal focus or move the real pointer.
- Verify action results through a different channel when possible.
- Keep first-class adapters reserved for high-volume surfaces.
- Use recipes for narrower or user-specific workflows.
- Keep the generic AX adapter strong enough for the long tail.

## Runtime Contract

Action should expose one adapter contract.

```ts
interface SurfaceAdapter {
  id: string;
  label: string;
  priority: number;

  canHandle(surface: SurfaceRef): Promise<AdapterMatch>;
  observe(context: ObserveContext): Promise<SurfaceObservation>;
  resolve(query: TargetQuery, observation: SurfaceObservation): Promise<TargetCandidate[]>;
  act(action: RuntimeAction, target: TargetCandidate): Promise<ActionResult>;
  extract(query: ExtractionQuery, observation: SurfaceObservation): Promise<ExtractionResult>;
  captureHints(target: TargetCandidate): Promise<CaptureHint[]>;
  verify(result: ActionResult, context: VerifyContext): Promise<VerificationResult>;
}
```

The shared observation envelope should carry native, AX, semantic, and optional
vision state together.

```ts
interface SurfaceObservation {
  surface: SurfaceRef;
  ax: AXSnapshot;
  native: NativeWindowState;
  semantic?: ChromeDomState | BrowserPageState | TerminalState | EditorState | SiteState;
  vision?: ScreenshotReflection;
  freshness: {
    axCapturedAt: string;
    semanticCapturedAt?: string;
    screenshotCapturedAt?: string;
  };
}
```

Target resolution should return candidates with evidence, confidence, rects, and
preferred action channel.

```ts
interface TargetCandidate {
  id: string;
  label: string;
  role?: string;
  rect?: Rect;
  confidence: number;
  stabilityKey?: string;
  evidence: TargetEvidence[];
  preferredActionChannel: "ax" | "dom" | "tmux" | "editor" | "native" | "hid";
  fallbackChannels: string[];
}
```

## Action Policy

Adapters should choose the safest available action channel.

Recommended order:

1. App-native semantic action, such as DOM value set, tmux send-keys, or editor command.
2. AX action, such as `AXPress`, `AXValue`, `AXSelectedText`, or settable focused value.
3. Process-directed key or text event.
4. HID event that may move focus or the real pointer.

If an action may disturb the user's current focus, Action should warn through the
overlay before acting.

## First-Class Adapter Families

## Browser App Adapters

Browsers are first-class because much of the target user base works inside web
apps.

### Chrome

Channels:

- AX snapshot for window, omnibox, tabs, web area, and native Chrome controls.
- Chrome extension for DOM observe, resolve, act, and extract.
- Optional Chrome DevTools Protocol for development and debugging flows.
- Native capture for screenshots, previews, and recording.

Profile policy:

- Action should launch and own a dedicated Chrome profile by default.
- That profile should carry the Action Chrome Companion extension and any
  Action-managed browser state.
- Authenticated workflows such as Midjourney may use a named persistent Action
  profile so the user can sign in once without mixing automation state into
  their daily Chrome profile.
- Attaching to the user's existing Chrome profile should be an explicit mode,
  not the default.
- Repeatable local setup should create and launch named Action profiles through
  project commands. The user-owned step is approving the companion extension in
  the Action profile when Chrome requires UI approval.
- Authenticated Action profiles may be seeded with **selective cookie import**
  from personal Chrome (domain / name allowlists), not a full profile clone.
  See [docs/browser-profiles.md](../browser-profiles.md).

Core abilities:

- Inspect tab URL, title, and loading state.
- Return visible DOM nodes with roles, labels, text, rects, selectors, and image URLs.
- Resolve form fields, buttons, links, menus, image cards, and content regions.
- Set input and textarea values with browser events.
- Click page-local elements without moving the OS pointer.
- Return semantic crop hints for previews and recording focus.

### Safari

Channels:

- AX snapshot for window, toolbar, web area, form controls, and page content.
- Safari extension later if Chrome-like DOM fidelity becomes necessary.
- AppleScript or Safari automation only where reliable.
- Native capture.

### Firefox

Channels:

- AX snapshot for browser shell and web area.
- Firefox extension for DOM observe, act, and extract if parity becomes important.
- Native capture.

## Browser Site Adapters And Recipes

Site-specific behavior should usually start as a recipe on top of the generic
browser adapter. A site should become a first-class adapter only when usage
volume and workflow depth justify it.

Initial first-class site adapters:

- GitHub
- Google search/docs-like surfaces

Bundled recipes:

- Midjourney Create as a dogfood recipe for background browser action, result
  monitoring, image extraction, and semantic preview crops.

## Terminal Adapters

Terminals are first-class because shell workflows are central to this product.

Initial terminal family:

- Terminal base adapter
- tmux
- iTerm
- Ghostty
- Warp

Channels:

- AX snapshot for app/window/pane bounds.
- Native capture for screenshots and previews.
- tmux state when available.
- Shell integration markers where available.
- App-specific scripting or local APIs only where stable.

Core abilities:

- Resolve panes, sessions, windows, visible text, cwd, and command output.
- Send keys without OS focus when tmux or shell integration can support it.
- Capture exact pane regions.
- Warn when an action requires focus-taking input.

## Coding Surface Adapters

Coding apps are first-class because Action users live in editors and agent
consoles.

Initial coding surfaces:

- Cursor
- VS Code
- Codex
- Conductor

Channels:

- AX snapshot for app shell, editor, command palette, terminal panels, chat, and sidebars.
- Editor extension APIs where available.
- Filesystem and workspace state.
- Local app/session metadata where available.
- Native capture and overlay.

Core abilities:

- Identify active workspace, file, selection, diagnostics, terminal panel, and chat region.
- Run editor commands through extension APIs where possible.
- Capture focused code or agent-output regions.
- Warn before actions that may interfere with the user's current focus.

## System And Long-Tail Adapters

Initial system adapters:

- Finder and file pickers
- System dialogs and permissions
- Generic AX

Generic AX remains the fallback for every other app.

Core abilities:

- Inspect app/window/control trees.
- Resolve buttons, text fields, menus, lists, and scroll areas.
- Prefer AX actions over coordinates.
- Use coordinate or HID fallback only with explicit risk labeling.

## Initial Adapter Set

The first shippable set should be roughly 15 to 18 adapters:

1. Generic AX
2. Chrome
3. Chrome extension generic web
4. GitHub site adapter
5. Google search/docs-like site adapter
6. Safari
7. Firefox
8. Terminal base
9. tmux
10. iTerm
11. Ghostty
12. Warp
13. Cursor
14. VS Code
15. Codex
16. Conductor
17. Finder/file pickers
18. System dialogs/permissions

Midjourney should start as a bundled recipe, not as a core adapter.

## User-Authored Adapters

Users should be able to teach Action their own high-volume surfaces without
waiting for a bundled adapter release.

There should be three authoring levels.

## Level 1: Recipes

Recipes are declarative target and extraction definitions.

Good fits:

- internal web apps
- niche SaaS tools
- personal dashboards
- demo targets like Midjourney
- simple editor or terminal workflows that mostly need better labels and crops

Recipes can define targets, fallback selectors, capture hints, waits, and
verification checks. They should not run arbitrary shell commands.

Example:

```json
{
  "id": "user.midjourney.create",
  "label": "Midjourney Create",
  "surface": {
    "kind": "browser-page",
    "urlMatches": ["https://www.midjourney.com/imagine*"]
  },
  "targets": {
    "prompt": {
      "dom": { "role": "textbox", "text": "What will you imagine?" },
      "ax": { "role": "AXTextArea" }
    },
    "latestResult": {
      "dom": { "nearTextTarget": "prompt", "image": true },
      "capture": { "padding": 32, "preferAspectRatio": "16:9" }
    }
  },
  "actions": {
    "submitPrompt": [
      { "setValue": "prompt" },
      { "key": "Enter" },
      { "waitFor": "latestResult" }
    ]
  }
}
```

## Level 2: TypeScript Adapter Modules

TypeScript adapters implement a constrained subset of the adapter contract for
users who need logic, not just selectors.

They should run in a sandboxed runtime with explicit capabilities:

- browser DOM access
- AX snapshot read access
- capture hint generation
- local filesystem read access only when granted
- no native input or shell by default

## Level 3: Native Capability Adapters

Native capability adapters are for integrations that need privileged local
behavior, such as deep terminal or editor control.

These should usually be bundled, reviewed, or explicitly installed because they
can affect the user's OS session.

## Sharing Model

Adapters and recipes should be packageable as small packs:

- local user recipes
- team-shared packs
- bundled Action packs
- optional community packs later

Each pack should declare:

- surfaces matched
- capabilities requested
- actions it can perform
- whether actions are background-safe
- whether actions may steal focus
- verification strategy

## Milestones

### Milestone 1: Adapter Registry And Observation Envelope

- Add a runtime-level adapter registry.
- Normalize AX, native window, screenshot, and semantic observations into one envelope.
- Add target candidates with evidence, confidence, rects, and preferred action channel.
- Add action risk classification.

### Milestone 2: Chrome Companion Extension

- Build a minimal Manifest V3 extension.
- Add content-script DOM observe, resolve, act, and extract.
- Add native messaging or local WebSocket pairing with Action.
- Use extension rects to drive native top-right semantic previews.
- Keep AX as the Chrome window and toolbar source of truth.

### Milestone 3: tmux And Terminal Family

- Add tmux observe, extract, and send primitives.
- Add terminal host detection for iTerm, Ghostty, Warp, and Terminal.app.
- Map tmux pane geometry back to native capture regions.
- Warn when a terminal action requires focus-taking input.

### Milestone 4: Coding Surfaces

- Start with Cursor and VS Code because their extension story is strongest.
- Add active file, selection, diagnostics, terminal panel, command palette, and chat observations.
- Add Codex and Conductor as AX-first app adapters with optional local state hooks.

### Milestone 5: Recipe Authoring

- Add a declarative recipe format for browser and AX targets.
- Add local recipe loading, validation, and capability summaries.
- Ship a Midjourney recipe as dogfood, not as a core adapter.
- Add import/export for team-shared recipes.

### Milestone 6: Site Adapters

- Layer GitHub and Google-like flows on top of the browser adapter.
- Promote recipes to first-class site adapters only after repeated usage proves they deserve it.
- Keep site adapters small and evidence-driven.
- Avoid hard-coding pixel layouts when DOM or AX can provide stable targets.

### Milestone 7: Long-Tail Hardening

- Improve generic AX resolution.
- Add screenshot plus local VLM verification.
- Add better ambiguity reporting.
- Add focus-stealing warnings for unsafe actions.

## Consequences

Positive:

- Action can be excellent in high-volume workflows without pretending every app is the same.
- AX remains the universal baseline and long-tail fallback.
- Chrome and terminal workflows get much more precise than AX alone allows.
- Users get a path to teach Action their own tools through recipes and adapter packs.

Tradeoffs:

- Adapter registry and capability management add product and engineering complexity.
- Browser extensions and editor extensions introduce installation and permission UX.
- Recipe authoring needs careful validation and debugging tools.
- First-class adapter promotion needs discipline to avoid a pile of bespoke integrations.

## Open Questions

- Should Chrome extension pairing use native messaging, local WebSocket, or both?
- What is the minimum useful recipe schema for v0?
- How should Action visualize target evidence and ambiguity to users?
- How much editor integration should be handled by VS Code-compatible extensions versus filesystem/runtime inspection?
- What is the pack signing or trust model for shared adapter packs?

## Proposal Document Format

Future Action engineering proposals and decisions should follow this general
shape:

- `ACT-NNN: Short Title`
- `Status`
- `Date`
- `Decision Type`
- `Summary`
- `Context`
- `Decision`
- `Principles` when useful
- `Design`
- `Milestones` or `Implementation Plan`
- `Consequences`
- `Open Questions`

Status values should start simple:

- `Proposed`
- `Accepted`
- `Superseded`
- `Rejected`
- `Implemented`
