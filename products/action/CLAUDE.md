# action

Action's repository migration into Lattices is complete. Work in `arach/lattices` under `products/action/`; the old `arach/action` repository is historical. On Arach's Mac, `/Users/arach/dev/action` is a compatibility symlink to `/Users/arach/dev/lattices/products/action`, so both paths share one Git checkout and its uncommitted work.

Action keeps its own `Action.app`, local agent, and recording lifecycle. This product has agent-oriented documentation generated with Dewey.

Read first:

- [Lattices workspace instructions](../../AGENTS.md)
- [AGENTS.md](AGENTS.md)
- [docs/overview.agent.md](docs/overview.agent.md)
- [docs/native-runtime.agent.md](docs/native-runtime.agent.md)
- [docs/recording.agent.md](docs/recording.agent.md)

Design work lives in [design/](design/README.md):

- `design/studio` is the central place — every design study, beside the code it argues about (`bun dev` in there, port 3070).
- `design/tokens/action.css` mirrors the Swift theme; the Swift is the source of truth.
- `design/kit` builds the previews for the **Action — Design System** project in Claude Design.
- A study marked SHIPPED draws only what the app records. Anything needing data the runtime does not write is a separate CONCEPT study.

Critical rules:

- Use bun for JS package management.
- Treat `Action.app` as the owner of AppKit lifecycle.
- Treat the local agent as orchestration and transport, not the owner of fragile UI lifecycle behavior.
- Treat recording completion as artifact-marker based, not initial-response based.
