# Repository Structure

Lattices is a small project with several real product surfaces. The root should
make those surfaces obvious.

This document is the current maintainer-facing map and the proposed direction
for keeping file structure as architecture.

## Current Top-Level Areas

| Path | Role |
| --- | --- |
| `apps/mac/` | Native macOS menu bar app. Swift/AppKit/SwiftUI package. |
| `bin/` | Published TypeScript CLI and app helper entry points. |
| `swift/` | Shared Swift package code used by the app. |
| `apps/ios/` | iOS companion app experiments and local build state. |
| `apps/site/` | Public marketing site and blog content. |
| `apps/docs-site/` | Astro documentation site. |
| `docs/` | Markdown docs and engineering proposals. |
| `tools/agents/skills/` | Agent skill pack for driving Lattices. |
| `assets/` | Shared release/app assets. |
| `tools/release/` | Maintainer scripts for building and shipping. |
| `tests/` | CLI, daemon, and evaluation tests. |

## Problem

The root currently mixes categories:

- shipped product surfaces: `apps/mac/`, `bin/`, `swift/`
- websites: `apps/site/`, `apps/docs-site/`
- companion experiments: `apps/ios/`
- generated or release output: `dist/`
- maintainer and agent affordances: `docs/`, `tools/`, `tests/`

That makes the project feel larger than it is. It also makes it harder to see
which directories are architecture and which are support material.

## Target Shape

Do not reorganize everything at once. The target is:

```text
apps/
  mac/            # macOS menu bar app
  ios/            # iOS companion app
  site/           # marketing site and blog content
  docs-site/      # documentation site

packages/
  cli/            # current bin/ plus TypeScript package surface
  swift/          # current swift/

docs/
  proposals/

tools/
  release/        # release/build scripts
  agents/skills/  # agent skill pack
```

This is intentionally similar to the `apps/` and `packages/` split used by
small monorepos such as Flue, but adapted for Lattices' macOS app plus CLI
shape.

## Migration Rules

- Move one category at a time.
- Keep published npm entry points stable.
- Keep app bundle and release scripts working after each move.
- Update docs and agent instructions in the same PR as any move.
- Avoid renames that only satisfy aesthetics without reducing ambiguity.
- Keep generated output ignored and out of the architectural map.

## Near-Term Cleanup

Good first moves:

1. Treat `dist/` as generated output only.
2. Move blog content closer to the site that owns it, or explicitly document it
   as shared content.
3. Decide whether the iOS companion remains in this repo or moves to its own
   repo once the companion work becomes active again.
4. Split `docs/proposals/` for numbered engineering docs such as `LAT-001`.
5. Decide whether `bin/` remains the package root for the CLI or becomes
   `packages/cli/src/` before adding more exported modules.

## What Stays Boring

Root files should be few and intentional:

- `README.md`
- `AGENTS.md`
- `package.json`
- lockfile
- TypeScript config
- license/security/contribution docs
- release/install affordances

Everything else should either be a product surface, a package, docs, content,
or tooling.
