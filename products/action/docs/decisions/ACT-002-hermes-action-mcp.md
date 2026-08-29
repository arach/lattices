# ACT-002: Hermes Action MCP Harness

## Status

Proposed

## Date

2026-05-09

## Decision Type

Architecture proposal and first harness integration

## Summary

Action will expose its native runtime through MCP as the stable harness-facing
control plane.

Hermes will be the first named harness integration. The integration should be a
thin skill and adapter layer, not a separate automation implementation.

## Context

Action is becoming a native-first runtime for observing, resolving, acting,
recording, inspecting, and later composing demos. Multiple agent harnesses should
be able to use those capabilities without each harness learning AppKit,
ScreenCaptureKit, AX, recording probe lifecycle, and artifact conventions from
scratch.

The repo already points in this direction:

- runtime primitives center `observe`, `resolve`, and `act`
- `@action/mcp` already names tool families
- recording behavior already depends on Action's native app lifecycle
- project docs preserve a hard boundary between `Action.app` and the local agent

Hermes is the first practical harness target. The goal is for Hermes to feel
native with Action while still sharing the same capability surface that Codex,
Claude, or any other harness can use later.

## Decision

Action will treat MCP as the canonical agent-harness surface.

Harness-specific integrations, including Hermes Action, should provide:

- install and configuration guidance
- operating doctrine for using Action safely
- harness-specific defaults and prompts
- small convenience wrappers where helpful

They should not reimplement native capture, AX inspection, target resolution,
recording orchestration, or artifact persistence.

## MCP Contract

The first MCP surface should expose a small native runtime API:

- `action.health`
- `action.session.create`
- `action.observe.snapshot`
- `action.observe.ax`
- `action.resolve.target`
- `action.act.execute`
- `action.record.start`
- `action.record.status`
- `action.record.stop`
- `action.artifacts.list`

Tools should return structured data with session ids, artifact paths, recording
ids, stop files, finished files, and explicit status fields.

Tools should avoid turning native lifecycle details into prose-only replies.
Those details are operational state and should remain machine-readable.

## Hermes Action Skill

The Hermes-facing skill should teach this loop:

1. run a native health check before native capture work
2. create or attach to a session
3. observe the current surface before acting
4. resolve targets before input whenever possible
5. execute deterministic actions through Action
6. treat recording start as an acknowledgement, not completion
7. wait for `.finished` or call `action.record.status`
8. inspect artifacts before summarizing success

The skill should be short and procedural. It should point Hermes at MCP tools
instead of copying implementation details from the native runtime.

## Boundaries

Keep:

- AppKit lifecycle in `Action.app`
- recording probe execution in the native app path
- local runtime and MCP as orchestration surfaces
- artifacts and trace files as durable truth
- harness skills as usage guidance

Avoid:

- harness-specific native capture code
- Hermes-only protocol behavior in the core runtime
- coordinate-first automation as the default path
- assuming a recording start acknowledgement means the recording completed
- making MCP tools return only natural-language summaries

## First Increment

Build the initial `@action/mcp` stdio server and a `hermes-action` skill.

The first implementation may wrap the capabilities that already exist and
return explicit unsupported states for not-yet-wired methods, as long as the
public contract is truthful and machine-readable.

## Consequences

This makes Action easier to adopt from Hermes immediately while keeping the
long-term architecture harness-neutral.

It also forces the runtime API to become explicit earlier. That is useful,
because the MCP surface will reveal which native capabilities are truly stable
and which ones are still only internal scripts or guided-demo helpers.
