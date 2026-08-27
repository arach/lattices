# Surface Adapter Plan

> Formalized as [ACT-001: Surface Adapter Architecture](decisions/ACT-001-surface-adapter-architecture.md).
> Keep ACT-001 as the source of truth for the decision/proposal record.

## Principle

Every surface starts with the macOS accessibility tree.

First-class surfaces get complementary semantic channels. Those channels should
make Action faster and more precise, but they should not replace AX as the
baseline source of UI truth.

In practice:

- AX tells Action what app/window/control exists in the OS.
- Native capture tells Action what is visible.
- Adapter-specific channels tell Action what the app means internally.
- Vision verifies visual outcomes when AX or semantic state is incomplete.

## Runtime Shape

Action should expose one runtime contract and many adapters.

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

The shared observation envelope should look roughly like this:

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

The target resolver should produce candidates with evidence, not just a point.

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

The adapter should choose the safest available channel for each action.

Recommended order:

1. App-native semantic action, such as DOM value set, tmux send-keys, or editor command.
2. AX action, such as `AXPress`, `AXValue`, `AXSelectedText`, or settable focused value.
3. Process-directed key or text event.
4. HID event that may move focus or the real pointer.

When an action may disturb the user's current focus, Action should warn through
the overlay before doing it.

Post-action verification should use a different channel when possible. For
example, a DOM set should be verified by DOM state plus AX or screenshot.

## Adapter Families

## 1. Browser App Adapters

Browsers are first-class because a large share of user work happens inside
web apps, and AX alone is too lossy inside complex pages.

### Chrome

Channels:

- AX snapshot for window, omnibox, tabs, web area, and native Chrome controls.
- Chrome extension for DOM observe/act/extract.
- Optional Chrome DevTools Protocol for development and debugging flows.
- Native capture for screenshots, previews, and recording.

Core abilities:

- Inspect current tab URL/title/loading state.
- Return visible DOM nodes with roles, labels, text, rects, selectors, and image URLs.
- Resolve form fields, buttons, links, menus, image cards, and content regions.
- Set input and textarea values with browser events.
- Click page-local elements without moving the OS pointer.
- Return semantic crop hints for top-right preview or recording focus.

### Safari

Channels:

- AX snapshot for window, toolbar, web area, form controls, and page content.
- Safari extension later if the product needs Chrome-like DOM fidelity.
- AppleScript or Safari automation only where reliable.
- Native capture.

Core abilities:

- Browser-window awareness.
- URL/title extraction through AX or scripting.
- Basic target resolution and form interaction.
- Conservative fallbacks when Safari does not expose stable internals.

### Firefox

Channels:

- AX snapshot for browser shell and web area.
- Firefox extension for DOM observe/act/extract if we want parity with Chrome.
- Native capture.

Core abilities:

- Same conceptual model as Chrome, with a smaller initial scope.
- Good enough for users who do not want Chrome.

## 2. Browser Site Adapters And Recipes

Site adapters live inside the browser extension world. They should not be
separate native apps. They specialize the generic browser adapter for high-volume
web products.

Not every product deserves a bundled first-class adapter. The default path
should be:

1. generic browser adapter
2. user-authored or bundled browser recipe
3. first-class site adapter only when usage volume and workflow depth justify it

### GitHub

Why:

- Pull requests, issues, reviews, checks, diffs, and file browsing are common
agent workflows.

Extra semantics:

- PR title/status/checks/review state.
- File tree and diff hunks.
- Comment boxes and review submission controls.
- Repo/branch/commit context.

### Google Search And Docs-Like Surfaces

Why:

- Search, docs, sheets, and web forms appear in many demos.

Extra semantics:

- Search box and result list.
- Document title and editable region.
- Save/sync state when exposed.
- Selection and visible cursor context where possible.

### Midjourney Recipe

Why:

- It is a strong demo and dogfood target for background generation, visual
preview, and rendered result monitoring.
- It is probably too specific for the initial first-class adapter set.

Recipe semantics:

- Create prompt composer target.
- Submit control target.
- Job/result card targets.
- Prompt text associated with result cards.
- Image URL and crop hint extraction.

This should start as a bundled recipe on top of the Chrome companion extension,
not as a bespoke core adapter.

## 3. Terminal Adapters

Terminals are first-class because the user base lives in shells, and terminal
AX output is often weaker than the shell's own state.

### Terminal Base Adapter

Channels:

- AX snapshot for app/window/pane bounds.
- Native capture for terminal screenshots.
- Optional shell integration markers.
- Process/window metadata.

Core abilities:

- Identify terminal app, window title, and visible text region.
- Capture a visible pane region.
- Warn before focus-taking input.
- Detect when only HID/focus-based typing is available.

### tmux

Channels:

- `tmux list-sessions`, `list-windows`, `list-panes`.
- `tmux capture-pane`.
- `tmux send-keys`.
- `tmux display-message` for current command, cwd, and pane metadata.
- AX/native capture for the terminal window that hosts the pane.

Core abilities:

- Resolve a pane by session/window/pane id, title, cwd, or visible text.
- Send keys without using the OS pointer.
- Extract command output reliably.
- Know whether a command exited and with what status when shell integration is available.

### iTerm

Channels:

- AX snapshot for windows, tabs, split panes, and text areas.
- iTerm scripting API where available.
- tmux adapter when iTerm hosts tmux.
- Native capture.

Core abilities:

- Resolve window/tab/session.
- Read visible text where possible.
- Send text/keys through the safest available path.
- Capture exact pane bounds.

### Ghostty

Channels:

- AX snapshot and native capture.
- tmux/shell integration when present.
- App-specific hooks later if Ghostty exposes stable automation APIs.

Core abilities:

- Window/pane bounds.
- Visible terminal text via AX/capture.
- tmux-backed control when applicable.

### Warp

Channels:

- AX snapshot and native capture.
- Block-aware semantics if Warp exposes them through AX or local APIs.
- Shell integration where possible.

Core abilities:

- Resolve command blocks.
- Extract visible block output.
- Warn when input requires focus.

## 4. Coding Surface Adapters

Coding apps are first-class because Action's users spend most of their time in
editors and agent consoles.

### Cursor

Channels:

- AX snapshot for editor shell, command palette, sidebars, terminal panels, and chat.
- VS Code-compatible extension channel if available.
- Filesystem/workspace state.
- Native capture.

Core abilities:

- Identify active workspace, file, selection, editor region, terminal panel, and chat panel.
- Run editor commands through extension APIs where possible.
- Capture focused code regions.
- Avoid stealing focus unless the requested action truly requires it.

### VS Code

Channels:

- AX snapshot.
- VS Code extension API.
- Filesystem/workspace state.
- Native capture.

Core abilities:

- Active file/selection/diagnostics.
- Command palette actions.
- Terminal panel state.
- Extension-mediated text edits and navigation.

### Codex

Channels:

- AX snapshot for the desktop app UI.
- Local workspace and thread context when available.
- Native capture and overlay.

Core abilities:

- Understand chat/input/output regions.
- Track running commands and visible logs where exposed.
- Capture meaningful preview regions.
- Warn before actions that may interfere with the user's current Codex focus.

### Conductor

Channels:

- AX snapshot.
- Local app/project metadata if exposed.
- Native capture.

Core abilities:

- Identify active project/session.
- Resolve chat, task, and result regions.
- Capture agent progress and output state.

## 5. System And Long-Tail Adapters

### Finder And File Pickers

Why:

- Files, save dialogs, open dialogs, downloads, and permissions are frequent
automation edges.

Channels:

- AX snapshot.
- Filesystem APIs.
- Native capture.

Core abilities:

- Resolve file picker fields and buttons.
- Navigate known folders.
- Select files without fragile coordinate clicking when possible.

### System Dialogs And Permissions

Why:

- macOS permission dialogs and settings are unavoidable for capture and
automation products.

Channels:

- AX snapshot.
- System settings URLs.
- Native capture.

Core abilities:

- Detect permission state.
- Open correct settings pane.
- Explain when manual user action is required.

### Generic AX Adapter

This is the long-tail fallback for every other app.

Channels:

- AX snapshot.
- Native capture.
- Optional vision reflection.

Core abilities:

- Inspect app/window/control tree.
- Resolve buttons, text fields, menus, lists, and scroll areas.
- Prefer AX actions over coordinates.
- Use coordinate/HID fallback only with explicit risk labeling.

## 6. User-Authored Adapters

The adapter system should let users teach Action their own high-volume surfaces
without waiting for a bundled adapter release.

There should be three authoring levels.

### Level 1: Recipes

Recipes are declarative target and extraction definitions. They should be enough
for most site-specific and app-specific customizations.

Good fits:

- internal web apps
- niche SaaS tools
- personal dashboards
- demo targets like Midjourney
- simple editor or terminal workflows that mostly need better labels and crops

Example shape:

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

Recipes should be inspectable, exportable, and safe by default. They can define
targets, fallback selectors, capture hints, waits, and verification checks. They
should not run arbitrary shell commands.

### Level 2: TypeScript Adapter Modules

TypeScript adapters implement a constrained subset of the adapter contract for
users who need logic, not just selectors.

Good fits:

- teams with complex internal tools
- workflow products with stable local APIs
- browser apps where extracting state requires page-specific logic

They should run in a sandboxed runtime with explicit capabilities:

- browser DOM access
- AX snapshot read access
- capture hint generation
- local filesystem read access only when granted
- no native input or shell by default

### Level 3: Native Capability Adapters

Native capability adapters are for integrations that need privileged local
behavior, such as deep terminal or editor control.

These should usually be bundled, reviewed, or explicitly installed because they
can affect the user's OS session.

Good fits:

- tmux
- terminal hosts
- editor extension bridges
- permission/settings flows

### Sharing Model

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

Bundled recipes can cover specific demo or workflow targets without promoting
them into core adapters. Midjourney is a good first bundled recipe because it
exercises browser DOM resolution, background action, result monitoring, image
extraction, and semantic preview crops.

This is enough to cover the highest-volume places while preserving a credible
long-tail story through AX.

## Milestones

### Milestone 1: Adapter Registry And Observation Envelope

- Add a runtime-level adapter registry.
- Normalize AX, native window, screenshot, and semantic observations into one envelope.
- Add target candidates with evidence, confidence, rects, and preferred action channel.
- Add action risk classification.

### Milestone 2: Chrome Companion Extension

- Build a minimal Manifest V3 extension.
- Add content-script DOM observe/resolve/act/extract.
- Add native messaging or local WebSocket pairing with Action.
- Use extension rects to drive native top-right semantic previews.
- Keep AX as the Chrome window and toolbar source of truth.

### Milestone 3: tmux And Terminal Family

- Add tmux observe/extract/send primitives.
- Add terminal host detection for iTerm, Ghostty, Warp, and Terminal.app.
- Map tmux pane geometry back to native capture regions.
- Warn when a terminal action requires focus-taking input.

### Milestone 4: Coding Surfaces

- Start with Cursor and VS Code because their extension story is strongest.
- Add active file, selection, diagnostics, terminal panel, command palette, and chat surface observations.
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
- Add "focus will be stolen" warnings for unsafe actions.

## Definition Of Done For A First-Class Adapter

An adapter is first-class when it can:

- Observe the current state from AX and at least one complementary channel.
- Resolve targets with evidence and confidence.
- Act through the safest available channel.
- Verify the result after acting.
- Provide capture hints for screenshots, zooms, and overlays.
- Explain when it cannot act without interfering with the user.
- Fall back cleanly to generic AX behavior.

## Product Rule

Action should be excellent in the places builders actually live, and still
competent everywhere else.
