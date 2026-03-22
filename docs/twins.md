---
title: Project Twins
description: Pi-backed project twins for mediated, persistent agent execution
order: 3
---

A project twin is a persistent software counterpart to a codebase.

It is not the primary agent. It is the project-native runtime that sits
between a general-purpose caller and the project's execution protocol.

## Why a twin exists

General-purpose agents are interchangeable. Project protocols are not.

If every primary agent has to learn the project's tool surface, memory
policy, protocol semantics, and context conventions from scratch, the
integration becomes brittle. A twin fixes that by becoming the stable
project-facing runtime:

- The **primary agent** asks for work
- The **twin** resumes with the right context and memory
- The **protocol** stays behind the twin boundary

```text
primary agent -> project twin -> project protocol / harness
```

The twin is the client of record for the project.

## Responsibilities

A project twin owns:

- Project-scoped identity
- Persistent session continuity
- Memory compaction and continuation
- Tool policy and allowed capabilities
- Protocol knowledge
- Project context assembly
- Caller-facing summaries and handoffs

A primary agent should not speak the project protocol directly. It should
invoke the twin.

## Pi-backed runtime

Pi is a good fit for the twin runtime because it already provides:

- Persistent sessions
- RPC mode for long-running subprocess integration
- Tool calling with an explicit harness
- Compaction and summarization hooks
- Context files, prompt templates, and extension loading

That makes the split:

- **Twin**: product concept and policy boundary
- **Pi**: reasoning and session runtime
- **Host system**: orchestration, durable memory, and protocol adapters

Pi powers the twin. It does not define the twin.

## Invocation model

The primary agent makes a single mediated call into the twin:

1. Resume the twin session
2. Inject caller context, project memory, and protocol state
3. Let the twin do project-local work inside the harness
4. Return a concise result to the caller

The caller should see a stable capability surface such as:

- `status`
- `inspect`
- `plan`
- `execute`
- `summarize`
- `handoff`

It should not see raw protocol-shaped operations unless that protocol is
itself the public product surface.

## Implementation in this repo

This repo now includes a Pi-backed runtime in
[`bin/project-twin.ts`](/Users/arach/dev/lattices/bin/project-twin.ts).

The runtime:

- Spawns `pi --mode rpc` as a persistent subprocess
- Stores project-local session state under `.openscout/twins/<name>/sessions`
- Exposes a stable `invoke()` API for callers
- Optionally injects OpenScout relay context if `.openscout/relay*` exists

The default harness is intentionally narrow:

- Built-in Pi tools are explicitly pinned to `read,bash,edit,write`
- Extension, skill, and prompt-template discovery are disabled by default
- Project instructions still come from `AGENTS.md` and related context files

This keeps the twin deterministic unless the host explicitly widens the
surface.

## Example

```ts
import { ProjectTwin } from "@lattices/cli"

const twin = new ProjectTwin({
  cwd: "/Users/you/dev/my-project",
  name: "my-project",
  model: "anthropic/claude-sonnet-4-5",
})

await twin.start()

const result = await twin.invoke({
  caller: "primary-agent",
  protocol: "openscout-relay",
  memory: "The caller is debugging relay enrollment and wants the next safe action.",
  task: "Inspect the available project context and summarize what the caller should do next.",
})

console.log(result.text)

await twin.stop()
```

## Design rule

All project-specific protocol semantics should live behind the twin
boundary.

The primary agent should invoke the twin as a skill-like capability.
The twin should own context assembly, protocol interaction, and the final
handoff back to the caller.
