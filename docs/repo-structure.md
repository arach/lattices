# Repository Structure

Lattices is one project with several real product surfaces. The root should make
those surfaces obvious before a maintainer has to infer history from directory
names.

This document is the current maintainer-facing map and the proposed direction
for keeping file structure as architecture.

## First Impression Goal

A visitor should be able to answer three questions from the root:

1. What are the product surfaces?
2. What code is reusable package/runtime code?
3. What is support material: docs, release tooling, tests, generated output, or
   agent tooling?

The current root partially answers those questions, but it exposes too many
eras of the repo at the same level.

## Current Top-Level Areas

| Path | Role |
| --- | --- |
| `app/` | Native macOS menu bar app. Swift/AppKit/SwiftUI package. |
| `bin/` | Published TypeScript CLI and app helper entry points. |
| `swift/` | Shared Swift package code used by the app. |
| `iOS/` | iOS companion app experiments and local build state. |
| `site/` | Public marketing site. |
| `docs-site/` | Astro documentation site. |
| `content/` | Shared blog/content source consumed by sites. |
| `docs/` | Markdown docs and engineering proposals. |
| `skills/` | Agent skill pack for driving Lattices. |
| `assets/` | Shared release/app assets. |
| `scripts/` | Maintainer scripts for building and shipping. |
| `test/` | CLI, daemon, and evaluation tests. |
| `lib/` | Shared TypeScript helpers that are not CLI entry points. |

## Problem

The root currently mixes categories:

- shipped product surfaces: `app/`, `bin/`, `swift/`, `iOS/`
- websites: `site/`, `docs-site/`, `content/`
- generated or release output: `dist/`
- maintainer and agent affordances: `docs/`, `skills/`, `scripts/`, `test/`

That makes the project feel larger than it is. It also makes it harder to see
which directories are architecture and which are support material.

The most confusing root-level pairs are:

- `site/` and `docs-site/`: both are Astro apps, but their ownership and public
  output are not obvious from the root.
- `bin/` and `lib/`: public CLI entry points sit beside internal TypeScript
  runtime modules.
- `app/`, `swift/`, and `iOS/`: these are related Apple-platform code, but the
  relationship is only implicit.
- `docs/`, `docs.json`, `llms.txt`, `AGENTS.md`, `CLAUDE.md`, and `skills/`:
  human docs, generated docs, and agent affordances compete for attention.

## Target Shape

Do not reorganize everything at once. The target is:

```text
apps/
  mac/            # current app/
  ios/            # current iOS/
  site/           # current site/
  docs-site/      # current docs-site/

packages/
  cli/            # current bin/ plus TypeScript package surface
  swift/          # current swift/

content/
  blog/

docs/
  proposals/

tools/
  scripts/        # current scripts/
  skills/         # current skills/
```

This is intentionally similar to the `apps/` and `packages/` split used by
small monorepos such as Flue, but adapted for Lattices' macOS app plus CLI
shape.

## Root Contract

Long term, the root should contain only:

- product/app directories: `apps/`
- package/runtime directories: `packages/`
- docs and content: `docs/`, `content/`
- support tooling: `tools/`, `tests/`
- package metadata and project policy files

Generated output such as `dist/`, `.build/`, bundled apps, screenshots, and
release artifacts should stay ignored or live under clearly named build output
locations.

## Migration Rules

- Move one category at a time.
- Keep published npm entry points stable.
- Keep app bundle and release scripts working after each move.
- Update docs and agent instructions in the same PR as any move.
- Avoid renames that only satisfy aesthetics without reducing ambiguity.
- Keep generated output ignored and out of the architectural map.

## Near-Term Cleanup

Good first moves:

1. Decide whether `site/` and `docs-site/` are both active. If both stay, name
   their roles clearly in README and package scripts.
2. Treat `dist/`, `.build/`, and generated app bundles as generated output only.
3. Make plist ownership canonical: one template/source of truth, generated
   bundle files ignored or intentionally tracked.
4. Regenerate or remove stale docs artifacts such as `docs.json`.
5. Move blog content closer to the site that owns it, or explicitly document it
   as shared content.
6. Split internal plans/proposals from user-facing docs.
7. Decide whether `bin/` remains the package root for the CLI or becomes
   `packages/cli/src/` before adding more exported modules.
8. Move `iOS/` under `apps/ios/` once companion work becomes active again.

## Suggested PR Sequence

Keep the cleanup boring and reviewable:

1. **Root clarity:** README map, this document, stale generated-doc cleanup.
2. **Generated artifacts:** plist ownership, ignored bundle output, release
   output cleanup.
3. **Docs split:** public docs versus engineering notes and agent references.
4. **Web ownership:** decide and document `site/` versus `docs-site/`.
5. **Directory moves:** `apps/` and `packages/`, one category at a time.

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
