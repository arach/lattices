# LAT-007: Unified App Shell

## Summary

Lattices should feel like one structured app, not a collection of useful
windows added one feature at a time. The native app already has a strong
starting point in the unified shell managed by `ScreenMapWindowController`.
Future feature work should treat that shell as the durable product surface.

Transient surfaces such as the command palette, voice command window, HUD,
and menu bar popover should become launchers, inspectors, or fast overlays
that route back into the shell for persistent workflows.

## Product Shape

The main Lattices window should own the primary information architecture:

| Area | Purpose |
|------|---------|
| Home | Workspace status, desktop control, agent/search entry points, and discoverable project launch |
| Assistant | Chat and agent-oriented workspace help |
| Layout | Visual desktop map and window arrangement |
| Desktop Inventory | Window/search/OCR inventory |
| Activity | Logs, diagnostics, event history, and operational feedback |
| Settings | Preferences, permissions, shortcuts, mouse, AI, OCR, companion |
| Docs | Reference and onboarding material |

The menu bar popover should stay lightweight: quick project launch plus
buttons into the main shell. The command palette should stay global and
action-oriented. The HUD and voice UI should stay transient and contextual.

## First User Experience

The friendliest starting point is Home, not Settings and not a floating
utility panel.

On first launch:

1. The onboarding window introduces the product briefly.
2. Onboarding presents optional capabilities only; it does not require project
   setup or terminal-session setup.
3. Completing onboarding opens the unified Home page.
4. Home starts with desktop control, search/context, and assistant entry points;
   project launch remains discoverable inside the app.
5. Missing setup is explained in place. Settings remains available, but the app
   should not throw the user into Settings just because a scan root is missing.

This keeps the first mental model simple:

> Lattices sees your workspace, helps arrange it, and gives agents local context.
> Project and terminal workflows are useful depth, not the first required step.

## Surface Rules

1. Durable state belongs in the unified app shell.
2. Popovers and overlays should not become alternate versions of the app.
3. Feature entry points should navigate to an app page when the user needs
   to read, configure, inspect, or continue a workflow.
4. Floating panels are appropriate for short-lived interactions: search,
   command execution, voice capture, HUD previews, and permission helpers.
5. Settings, diagnostics, docs, assistant setup, and inventory views should
   avoid standalone windows unless there is an explicit debugging reason.
6. Page changes inside the shell should preserve the user's window size and
   position. Pick a good initial size, then let the window feel stable.

## Migration Plan

### Phase 1: Route Existing Entry Points

- Add missing primary pages to the unified shell.
- Redirect menu, palette, hotkey, and footer links into shell pages.
- Keep legacy utility windows available internally where useful, but stop
  presenting them from normal app navigation.

### Phase 2: Normalize Page Responsibilities

- Make Home the status and launch surface.
- Make Layout the only visual arrangement surface.
- Make Desktop Inventory the only persistent search/inventory surface.
- Make Activity the only persistent diagnostics surface.
- Keep Settings and Docs under the shell instead of separate windows.

### Phase 3: Reduce Duplicate UI

- Convert repeated panel headers, footers, and shell chrome into reusable
  components.
- Move preview rendering and diagnostic log rendering into shared views.
- Keep command palette rows and menu items as bindings to canonical actions.

### Phase 4: Product-Level Navigation

- Add a route helper for app pages so callers express intent like
  `showActivity()` or `showSettings(.shortcuts)` instead of manually choosing
  windows.
- Add page-specific deep links for companion, docs, and diagnostics.
- Record navigation in diagnostics so support sessions can reconstruct how a
  user reached a feature.

## First Slice

The first implemented slice is Activity consolidation:

- `Activity` is now a primary app-shell page.
- Home links to Activity.
- menu bar, command palette, hotkey, settings/docs footers, launch flag, voice,
  and Layout log links route to the Activity page.
- The legacy floating `DiagnosticWindow` remains for internal/debug use.

The second implemented slice is first-run Home consolidation:

- Completing onboarding opens Home.
- Missing scan-root setup is handled inside Home instead of auto-opening
  Settings.
- Onboarding no longer introduces project-root or tmux setup.
- Home shows a desktop-first getting-started path when no projects are
  discovered: layout, search/context, and assistant.
- Project scanning is skipped when the scan root is empty.
- App-shell tab navigation preserves the current window frame instead of
  resizing per page.

## Open Questions

- Should the menu bar click open Home in the unified shell by default, leaving
  the project popover as an explicit quick-launch mode?
- Should Command Mode become the embedded Desktop Inventory page only, with the
  standalone panel reserved for a hotkey overlay?
- Should Settings expose direct subroutes such as `settings.shortcuts` and
  `settings.permissions`?
