---
title: Dewey Eve Agent
description: Local Eve container plan for the Lattices agent-docs assistant.
---

# Dewey Eve Agent

Lattices now has a lightweight Eve scaffold for a local Dewey-style docs agent in `apps/dewey-agent`. This is a proof of concept. The target architecture is documented in [Dewey Agent Architecture](./dewey-agent-architecture).

## Shape

| Layer | Choice |
| --- | --- |
| Agent framework | Eve |
| Runtime | Apple `container` |
| Workflow state | Local `~/.lattices/dewey-agent` directory |
| Eve sandbox backend | `eve/sandbox/just-bash` |
| Container wrapper | Fabric-compatible `.fabric` config |
| Model default | Local OpenAI-compatible endpoint |
| Docs pipeline | Existing `apps/site/scripts/agent-docs.mjs` |

## Why Eve

Eve gives the docs agent a durable local session, tools, skills, and a sandbox without turning Dewey into a hosted service. Mastra is a better fit if this becomes a hosted product with RAG, eval dashboards, or multi-tenant workflow orchestration. For the first Lattices docs agent, Eve is the smaller surface.

## Permanent home

The reusable agent should live in Dewey, not Lattices. Lattices should eventually keep only:

- `dewey.config.ts`
- project instructions
- generated agent artifacts
- an adapter hook for `apps/site/scripts/agent-docs.mjs`

Until Dewey owns the runtime, `apps/dewey-agent` remains the local testbed for Apple `container`, Eve, and Fabric-friendly mounts.

## Apple local container

Run from the agent directory:

```sh
cd apps/dewey-agent
npm run container:build
npm run container:run
```

`container:build` only pulls or verifies the native `node:24-bookworm-slim` base image; there is no custom image build. The native Apple container mounts the repo at `/repo` and stores Eve state under `~/.lattices/dewey-agent`. There is no Docker daemon and no hosted sandbox dependency.

For host-local model servers such as Ollama, create the host-loopback DNS alias once:

```sh
cd apps/dewey-agent
npm run container:host-dns
```

## No cloud defaults

The scaffold avoids Vercel-specific defaults in two places:

- `agent/agent.ts` passes a direct provider object instead of an AI Gateway model string.
- `agent/sandbox/sandbox.ts` pins `justbash()` instead of `defaultBackend()` or `vercel()`.

Default model environment:

```sh
DEWEY_AGENT_PROVIDER=local
DEWEY_AGENT_BASE_URL=http://host.container.internal:11434/v1
DEWEY_AGENT_MODEL=llama3.1:8b
DEWEY_AGENT_API_KEY=local
DEWEY_AGENT_CONTEXT_WINDOW_TOKENS=131072
```

For a provider-hosted model, opt in explicitly:

```sh
DEWEY_AGENT_PROVIDER=anthropic
DEWEY_AGENT_MODEL=claude-opus-4.8
ANTHROPIC_API_KEY=...
```

The explicit context-window value is required for local model IDs because Eve cannot look up custom local models in hosted provider metadata.

## Fabric

`apps/dewey-agent/.fabric` targets the same `node:24-bookworm-slim` base image, mounts the repo at `/repo`, and carries the local model env. Fabric can sit above the Apple container runtime for ad hoc sandbox commands without changing the Eve app runner.

Eve does not currently ship an Apple-container sandbox backend. The scaffold therefore keeps Eve's built-in shell sandbox on `justbash()` and routes real repo work through deterministic authored tools. A future Fabric-backed Eve sandbox adapter should implement Eve's public `SandboxBackend` interface and delegate process/filesystem operations to Fabric's local runtime.

## Tools

| Tool | Purpose |
| --- | --- |
| `collect_docs` | Read markdown docs and current manifest shape without writing files. |
| `audit_agent_docs` | Check required source docs and generated agent artifacts. |
| `read_doc_artifact` | Read one source markdown doc by slug. |
| `generate_agent_artifacts` | Regenerate artifacts through the existing site writer. |

The first implementation deliberately keeps writes out of the model's shell path. The generator tool calls the existing Node script, so future docs changes do not fork into a second pipeline.

## Verification

The deterministic smoke check does not require Eve, Apple containers, or a model:

```sh
cd apps/dewey-agent
LATTICES_REPO=/Users/art/dev/lattices npm run smoke
```

Container verification requires the Apple `container` service to be running:

```sh
cd apps/dewey-agent
npm run container:status
npm run container:smoke
```
