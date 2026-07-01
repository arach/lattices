# Lattices Dewey Agent

Local Eve proof of concept for Lattices agent-ready docs. It is intentionally small and should migrate into Dewey once the shared agent pipeline lands.

- Eve app state stays on disk in `~/.lattices/dewey-agent`.
- The Eve app runs in Apple's native `container` runtime.
- The Eve sandbox is pinned to `eve/sandbox/just-bash`, so there is no Docker or hosted sandbox dependency.
- The default model endpoint is local OpenAI-compatible (`http://host.container.internal:11434/v1`).
- The tools call the existing `apps/site/scripts/agent-docs.mjs` collector instead of inventing a second docs pipeline.

Target architecture: [Dewey Agent Architecture](/Users/art/dev/lattices/docs/agent/dewey-agent-architecture.md).

## Run in an Apple container

Requirements:

- Apple `container` CLI and services. The Fabric setup flow can install and configure this.
- A local OpenAI-compatible model server, such as Ollama with its `/v1` compatibility endpoint.

```sh
cd apps/dewey-agent
npm run container:build
npm run container:run
```

`container:build` only pulls or verifies the native `node:24-bookworm-slim` base image; there is no custom image build. The Eve app listens on `http://127.0.0.1:8787`. The runner mounts the repository at `/repo` and stores durable Eve state under `~/.lattices/dewey-agent`.

For host-local model servers, create a one-time Apple container DNS alias:

```sh
npm run container:host-dns
```

That command uses `container system dns create ... --localhost`, matching Apple's documented host-loopback pattern for the native container runtime.

## Model options

Default local mode:

```sh
DEWEY_AGENT_PROVIDER=local
DEWEY_AGENT_BASE_URL=http://host.container.internal:11434/v1
DEWEY_AGENT_MODEL=llama3.1:8b
DEWEY_AGENT_API_KEY=local
DEWEY_AGENT_CONTEXT_WINDOW_TOKENS=131072
```

Anthropic direct mode, if you choose to use it:

```sh
DEWEY_AGENT_PROVIDER=anthropic
DEWEY_AGENT_MODEL=claude-opus-4.8
ANTHROPIC_API_KEY=...
```

Do not use gateway model strings here. `agent/agent.ts` chooses a direct provider object so this app does not route through Vercel AI Gateway.

`DEWEY_AGENT_CONTEXT_WINDOW_TOKENS` is set explicitly because local model IDs are not in Eve's hosted model metadata catalog. Tune it to match the context window of the model you actually run.

## Fabric wrapper

`.fabric` points Fabric at the same `node:24-bookworm-slim` base image and `/repo` mount. Use Fabric as the higher-level local container wrapper when you want ad hoc sandbox commands; use `npm run container:*` for the Eve app lifecycle.

## Migration intent

This package is a spike. The durable home should be Dewey:

- Dewey owns the Eve agent, `/in` and `/out` bundle schemas, and apply pipeline.
- Fabric owns Apple `container` execution and mount orchestration.
- Lattices keeps only project instructions and an adapter for `apps/site/scripts/agent-docs.mjs`.

When that lands, this directory can shrink to a delegating script or disappear entirely.

## Local host run

This requires Node 24+.

```sh
cd apps/dewey-agent
npm install
LATTICES_REPO=/Users/art/dev/lattices npm run dev
```

## Deterministic smoke check

This does not call a model or start Eve. It only verifies that the helper can see the Lattices docs and agent artifacts.

```sh
cd apps/dewey-agent
LATTICES_REPO=/Users/art/dev/lattices npm run smoke
```

To run the same smoke check inside the Apple container image:

```sh
cd apps/dewey-agent
npm run container:smoke
```
