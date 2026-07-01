---
title: Dewey Agent Architecture
description: Target architecture for Dewey-owned docs agents, Fabric execution, and Lattices project adapters.
---

# Dewey Agent Architecture

This document records the target architecture after the Lattices Eve spike. The spike proves the local runtime shape, but the reusable agent should live in Dewey.

## Decision

Use a Dewey-owned agent and pipeline with project-mounted inputs:

| Owner | Responsibility |
| --- | --- |
| Dewey | Agent runtime, ingest/out/apply pipeline, bundle schemas, generic docs tools, audit/generate orchestration |
| Fabric | Apple `container` execution, mounts, local runtime setup, future snapshots and handoff |
| Lattices | Dewey config, project instructions, and an adapter hook for the existing docs artifact writer |

Lattices should not permanently own a full Eve agent. `apps/dewey-agent` is a prototype until Dewey owns the generic runner.

## Runtime Model

The default runtime is local-only:

```text
host repo path
  -> Fabric / Apple container
  -> Dewey ingest
  -> Dewey Eve agent
  -> Dewey outbox
  -> explicit apply
```

No cloud provider is part of the default path. No Docker daemon is part of the default path. Provider-hosted models and cloud runtimes are opt-in.

## Mount Contract

Mounts are trusted launch parameters, not something the agent can arbitrarily change mid-conversation.

| Mount | Default | Purpose |
| --- | --- | --- |
| `/repo` | read-only | Source project mounted by the caller |
| `/in` | read-only | Normalized Dewey input bundle |
| `/out` | writable | Generated reports, artifacts, patches, and apply plans |
| `/state` | writable | Durable Eve/Fabric state and caches |

Recommended CLI shape:

```sh
dewey ingest --repo /Users/art/dev/lattices --out .dewey/in
dewey agent run --in .dewey/in --out .dewey/out
dewey apply --repo /Users/art/dev/lattices --from .dewey/out
```

Convenience form:

```sh
dewey agent run --repo /Users/art/dev/lattices
```

The convenience command should expand to an ingest plus agent run. It should keep `/repo` read-only unless the caller explicitly selects an apply/write mode.

## Pipeline Modes

| Mode | Repo mount | Writes | Use case |
| --- | --- | --- | --- |
| `read` | read-only | `/out/report.md`, `/out/audit.json` | Inspect docs, explain gaps, answer questions |
| `generate` | read-only | `/out/artifacts/**`, `/out/patches/**` | Generate proposed docs/artifacts without mutating the repo |
| `apply` | read-write or host-side apply | repo plus `/out/apply-report.json` | Apply a selected patch/artifact plan |

The safest default is read-only repo plus host-side `dewey apply`. The agent proposes changes; deterministic Dewey code applies them.

## In Bundle

The ingest step should produce a deterministic bundle. The agent should reason from this bundle instead of crawling the full repository every turn.

```text
/in/
  manifest.json
  project.md
  instructions.md
  source-index.json
  docs/
    overview.md
    quickstart.md
    ...
  generated/
    AGENTS.md
    llms.txt
    docs.json
    agent-docs.json
  adapters/
    lattices.json
  checks/
    latest-audit.json
```

Required fields for `/in/manifest.json`:

| Field | Purpose |
| --- | --- |
| `schemaVersion` | Version the bundle contract |
| `project.name` | Human and machine project identifier |
| `project.rootLabel` | Display-only source root label, never trusted as a path |
| `source.repoMount` | Usually `/repo` |
| `instructions.files` | Ordered instruction files included in the bundle |
| `docs.entries` | Slug, source path, title, and content path for each doc |
| `generated.entries` | Known generated artifacts and content hashes |
| `adapters` | Adapter names and declared capabilities |
| `createdAt` | Timestamp for freshness checks |

## Out Bundle

Agent output should be inspectable and deterministic enough to apply later.

```text
/out/
  manifest.json
  report.md
  audit.json
  apply-plan.json
  patches/
    docs.patch
  artifacts/
    AGENTS.md
    llms.txt
    docs.json
  notes/
    migration.md
```

Required fields for `/out/manifest.json`:

| Field | Purpose |
| --- | --- |
| `schemaVersion` | Version the outbox contract |
| `inputHash` | Hash of `/in/manifest.json` plus referenced content hashes |
| `mode` | `read`, `generate`, or `apply` |
| `status` | `ok`, `needs-review`, or `blocked` |
| `artifacts` | Files written under `/out/artifacts` |
| `patches` | Patches written under `/out/patches` |
| `commands` | Suggested verification commands, not auto-executed unless apply mode permits |
| `risks` | Known uncertainty and human review notes |

## Adapter API

Dewey should expose a small project adapter surface. A project can provide this in `dewey.config.ts` or a sibling module.

```ts
export default defineDeweyProject({
  instructions: [
    "AGENTS.md",
    "docs/agent/cua-implementation.md",
  ],

  async ingest(ctx) {
    await ctx.includeDocs("docs/**/*.md")
    await ctx.includeGenerated("AGENTS.md")
    await ctx.includeGenerated("llms.txt")
  },

  async generate(ctx) {
    await ctx.run("node apps/site/scripts/agent-docs.mjs")
  },
})
```

For Lattices, the first adapter should wrap `apps/site/scripts/agent-docs.mjs` instead of moving that logic into the agent.

## Agent Tool Boundary

The Eve agent should prefer deterministic Dewey tools:

| Tool | Mutates repo | Purpose |
| --- | --- | --- |
| `read_in_bundle` | no | Read normalized inputs |
| `audit_docs` | no | Score and list gaps |
| `draft_outputs` | no | Write `/out` artifacts and reports |
| `propose_patch` | no | Write patch files under `/out/patches` |
| `apply_outbox` | yes, gated | Apply a selected plan through Dewey, not raw shell |

Raw shell access should be optional and scoped. The agent should not use shell writes to mutate `/repo` in read or generate mode.

## Security Model

- Path mounts are validated before the container starts.
- `/repo` is read-only by default.
- `/out` is the only default writable project output.
- Apply mode requires an explicit command or flag.
- The agent cannot request arbitrary new host mounts during a conversation.
- Provider-hosted models and cloud runtimes require explicit env/config.
- Local model IDs must supply an explicit context window because they are not in hosted model metadata catalogs.

## Migration Plan

1. Keep `apps/dewey-agent` as the Lattices proof of concept.
2. In Dewey, add the `/in` and `/out` bundle schema plus `ingest`, `agent run`, and `apply` commands.
3. Move the Apple `container` runner and Eve agent into Dewey.
4. Add a Dewey Fabric runtime adapter that can launch the agent with `/repo`, `/in`, `/out`, and `/state` mounts.
5. Convert Lattices to a Dewey project adapter that calls `apps/site/scripts/agent-docs.mjs`.
6. Replace `apps/dewey-agent` with a small note or script that delegates to Dewey.
7. Regenerate Lattices agent artifacts and run the docs smoke check from the Dewey CLI.

## Verification

The migration is complete when these commands work from the Dewey repo against Lattices:

```sh
dewey ingest --repo /Users/art/dev/lattices --out /tmp/lattices-in
dewey agent run --in /tmp/lattices-in --out /tmp/lattices-out
dewey apply --repo /Users/art/dev/lattices --from /tmp/lattices-out --dry-run
```

And these invariants hold:

- The repo-local Lattices adapter can regenerate the same agent docs artifacts as the current script.
- The agent can audit Lattices without write access to `/repo`.
- The generated outbox contains a readable report and machine-readable manifest.
- Applying outputs is deterministic and separately reviewable.
