# AX Background Automation

Action should treat macOS Accessibility as the default path for host-native
automation.

The product goal is not to create a second hardware cursor. The goal is to act
through semantic app surfaces while presenting a visual cursor/caret overlay
that explains what is happening.

## Model

For a target app, Action should prefer:

1. read the AX tree
2. resolve a specific element
3. use semantic AX actions or settable attributes
4. show a non-interactive overlay describing the action
5. verify by reading AX state again

The overlay is presentation only. It must not be treated as the input channel.

## Action Ladder

Use the least attention-taking primitive that can complete the task:

1. `observe`: AX tree, window bounds, screenshot.
2. `semantic`: `AXPress`, `AXShowMenu`, set `AXValue`, set `AXSelectedText`.
3. `target-focus`: set `AXFocused`, then send direct app/process events if the
   app requires a focused control.
4. `app-api`: Chrome DevTools Protocol, AppleScript, Shortcuts, or app-specific
   APIs when they are more deterministic than generic AX.
5. `attention`: activate/raise an app, system hotkeys, pointer warping, or HID
   events.

The runtime should record which tier was used for every action.

## Warning Policy

`observe` and `semantic` actions can run silently with the top-right trace.

`target-focus` actions should show a subtle amber notice:

> Target focus may change inside {app}.

`attention` actions should require an explicit, visible warning before execution:

> Action needs foreground control of {app} and may move focus or the pointer.

The user should be able to cancel or defer attention-taking actions.

## Current Daily App Findings

Use:

```bash
bun run native:ax:audit
```

The audit is read-only. It snapshots AX nodes for daily apps and reports:

- roles
- available AX actions
- settable attributes
- pressable elements
- text-like writable controls
- whether the frontmost app changed during the audit

Early local findings:

- Chrome exposes many `AXPress` controls and an `AXTextField` for the omnibox.
- iTerm exposes titlebar/search controls plus a large terminal `AXTextArea`.
- Codex currently exposes a coarse Electron shell: mostly groups and titlebar
  buttons, not a rich editor/input AX tree in this sample.
- Cursor should be audited when running; the script intentionally does not
  launch apps because launching can itself become attention-taking behavior.
