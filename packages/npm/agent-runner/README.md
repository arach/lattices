# @openscout/agent-runner

Run **any** harnessable agent — pi, codex, claude-code, opencode, echo — through
one uniform CLI/SDK. All per-harness implementation details (binary discovery,
RPC framing, env/auth, event normalization, session lifecycle) are handled here
on top of `@openscout/agent-sessions` adapters, so callers only deal with
**start → prompt → events → stop**.

> **Status:** prototyped inside the lattices repo (`packages/npm/agent-runner`)
> to validate the shape end-to-end. Destined to be lifted into the openscout repo
> as a published `@openscout/*` package; the per-project shims
> (`@lattices/agent-runtime`, `@talkie/agent-runtime`) then re-export it.

> **Runtime:** requires **Bun** — the underlying adapters use `Bun.spawn`.

## Three layers

| Layer | Package | Role |
|---|---|---|
| Adapters | `@openscout/agent-sessions` | speak each harness's wire protocol, normalized |
| **Runner** | `@openscout/agent-runner` *(this)* | catalog + binary resolution + uniform SDK + stdio CLI |
| Project shims | `@lattices/agent-runtime`, `@talkie/agent-runtime` | re-export the runner, pin version, inject project config |

## SDK

```js
import { createAgentRunner } from "@openscout/agent-runner";

const runner = createAgentRunner();
runner.onEvent(({ event }) => {
  if (event.event === "block:delta") process.stdout.write(event.text);
});

await runner.start("pi", { sessionId: "s1", cwd: process.cwd(), provider: "openai-codex" });
runner.prompt({ sessionId: "s1", text: "Reply with exactly: hello" });
```

`runner.catalog()` reports each harness with live binary availability.

## CLI (stdio dispatcher)

JSON op per line on stdin; JSON lines on stdout. Native hosts (e.g. the Lattices
Swift app) drive this instead of spawning a harness themselves.

```sh
printf '{"op":"ping"}\n'    | bun ./bin/agent-runner.mjs
printf '{"op":"catalog"}\n' | bun ./bin/agent-runner.mjs
```

Ops: `ping`, `catalog`, `start`, `prompt`, `interrupt`, `shutdown`.
Adapter events stream as `{"type":"event","event":{…}}`.
