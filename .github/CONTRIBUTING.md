# Contributing

Thanks for helping make Lattices better.

Lattices has a few main surfaces:

- TypeScript CLI and published package entry points in `bin/`
- native macOS app in `app/Sources/`
- shared Swift package code in `swift/`
- sites in `site/` and `docs-site/`
- agent-facing docs and skills in `docs/` and `skills/`

The CLI and app share contracts for session names, tmux title tags, daemon methods, project
discovery, and shortcut behavior. When a change touches one surface, check whether the other surface
needs to stay in sync.

## Development Setup

```sh
bun install
```

For the app, use Swift 6.2 / Xcode 26+ on macOS 26 or newer.

```sh
bun run check
```

Useful commands:

```sh
bun run check:types      # TypeScript CLI/API type check
bun run check:app        # Swift package build
bun run build:app-bundle # Build/sign the local .app bundle
```

## Pull Requests

Please keep PRs focused. Good PRs usually include:

- a short description of the user-facing behavior
- notes about CLI/app compatibility when relevant
- verification commands run locally
- screenshots or recordings for UI/overlay changes
- docs updates for new config, daemon methods, or user-visible workflows

## Repo Conventions

- Treat file structure as architecture: top-level directories should identify
  product surfaces, packages, docs, content, assets, tests, or tooling.
- Prefer existing app and CLI patterns over new abstractions.
- Keep global input handling and action dispatch fast and deterministic.
- Treat visual customization, animations, and agent integrations as best-effort layers that must not
  block core workspace actions.
- Avoid committing generated build output unless it is intentionally shipped.
- Preserve local-first behavior: no remote calls in startup, event taps, or shortcut hot paths.

## Docs

Docs live in `docs/`, `README.md`, and the Astro docs site under `docs-site`. For design/proposal
work, use numbered docs such as `LAT-001` so decisions can be discussed and approved before the
implementation grows.
