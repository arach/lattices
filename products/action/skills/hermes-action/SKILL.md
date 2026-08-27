---
name: hermes-action
description: Use when Hermes should drive the Action native macOS runtime through MCP for observing surfaces, resolving targets, executing deterministic actions, recording captures, and inspecting artifacts. Trigger for Hermes + Action workflows, native demo automation, guided capture, target-first macOS actions, or recording through Action.app.
---

# Hermes Action

Use Action as Hermes' native macOS hands.

## Startup

Connect Hermes to the Action MCP server:

```bash
ACTION_ROOT="$(git rev-parse --show-toplevel)/products/action"
ACTION_ROOT="$ACTION_ROOT" bun --cwd "$ACTION_ROOT" packages/mcp/src/index.ts
```

Run the command from any directory inside a Lattices checkout. `ACTION_ROOT`
must identify the Action product root, not the Lattices repository root.

## Operating Loop

1. Call `action.health` before capture or native UI work.
2. Create a session with `action.session.create` when the task will produce artifacts.
3. Observe before acting with `action.observe.snapshot`.
4. Resolve targets with `action.resolve.target` before input whenever possible.
5. Execute only clear deterministic actions through `action.act.execute`.
6. Start recordings with `action.record.start`.
7. Treat recording start as an acknowledgement only.
8. Use `action.record.status` or the `.finished` marker to verify completion.
9. Use `action.artifacts.list` before summarizing outputs.

## Action Policy

- Prefer semantic, AX, or text target queries over coordinates.
- Use coordinates only when Action cannot resolve the target another way.
- Do not claim a recording succeeded until the finished marker reports completion.
- Preserve `stopFile`, `finishedFile`, and artifact paths in replies or logs.
- If permissions are missing, surface the `action.health` diagnostics first.

## Useful Tool Order

For inspection:

`action.health -> action.session.create -> action.observe.snapshot -> action.artifacts.list`

For acting:

`action.observe.snapshot -> action.resolve.target -> action.act.execute -> action.observe.snapshot`

For recording:

`action.session.create -> action.record.start -> action.record.status -> action.record.stop -> action.artifacts.list`

## Boundaries

Hermes should not reimplement AppKit lifecycle, ScreenCaptureKit recording,
Accessibility inspection, or artifact persistence. Those belong to Action.
