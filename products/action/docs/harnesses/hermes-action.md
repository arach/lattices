# Hermes Action

Hermes Action is the first harness-specific way to use Action natively.

The important split is:

- `@action/mcp` exposes the shared native control plane
- `hermes-action` teaches Hermes how to use that control plane safely

Hermes should not get a separate native automation stack. It should call the
same Action MCP tools that other harnesses can call.

## MCP Server

Launch the server from this repo:

```bash
bun run mcp
```

Or directly:

```bash
bun --cwd /Users/art/dev/action packages/mcp/src/index.ts
```

If the server is launched from another working directory, set:

```bash
ACTION_ROOT=/Users/art/dev/action
```

## Initial Tools

- `action.health`
- `action.session.create`
- `action.observe.snapshot`
- `action.observe.ax`
- `action.resolve.target`
- `action.act.execute`
- `action.stage.set` (fails if the listed windows are not actually on the sheet)
- `action.stage.clear`
- `action.stage.status`
- `action.record.start`
- `action.record.status`
- `action.record.stop`
- `action.artifacts.list`

## Recommended Hermes Loop

For native inspection:

```text
action.health
action.session.create
action.observe.snapshot
action.artifacts.list
```

For target-first action:

```text
action.observe.snapshot
action.resolve.target
action.act.execute
action.observe.snapshot
```

For recording:

```text
action.session.create
action.record.start
action.record.status
action.record.stop
action.artifacts.list
```

## Recording Rule

`action.record.start` is asynchronous.

The reply means the native recording path accepted startup. Completion is
represented by:

- the `.mov` output
- the `.finished` marker
- `action.record.status`

Hermes should preserve the returned `recordingId`, `outputPath`, `stopFile`, and
`finishedFile` until the run is complete.

## Skill

The bundled skill lives at:

```text
skills/hermes-action/SKILL.md
```

Use it as the harness-side doctrine for Action workflows.
