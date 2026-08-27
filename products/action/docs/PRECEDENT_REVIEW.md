# Precedent Review

## Purpose

`action` is a rewrite, not a fresh invention.

That means every meaningful feature should be implemented with awareness of prior
iterations such as `vif`, `stage`, and other reference products already named in
the vision docs.

The point is not to cargo-cult old code or old abstractions. The point is to
avoid relearning the same lessons and to preserve the parts that were genuinely
good.

## Primary References

There are two primary implementation precedents for this repo:

### `vif`

`vif` is the more mature reference.

Use it for:

- richer product instincts
- features that were already proven in practice
- examples of end-to-end flows that felt real
- areas where the UX had already become compelling

Treat it carefully because it also carries more historical complexity:

- broader product surface
- accumulated lifecycle complications
- architectural entanglement
- features that worked but were hard to reason about internally

### `stage`

`stage` is the less mature reference, but often the cleaner conceptual one.

Use it for:

- stronger boundaries
- cleaner framing of capabilities
- improved instincts around agent-facing primitives
- ideas that look more like a v2 architecture

Treat it carefully because it is also less proven:

- some concepts were still underdeveloped
- some reliability questions were unresolved
- some abstractions were cleaner than their implementation maturity

## How To Read The Two Together

When both references are relevant:

- use `vif` to understand what felt good and what actually mattered in practice
- use `stage` to understand how that idea wanted to be cleaned up architecturally
- do not inherit `vif` complexity just because it is more complete
- do not inherit `stage` abstractions just because they are cleaner on paper

In short:

- `vif` is often the better product reference
- `stage` is often the better architecture prompt
- `action` should combine the strongest parts of both without importing their
  weaknesses

## Additional Reference: Peekaboo

Peekaboo is a strong native implementation reference for:

- permission handling
- Swift-first macOS automation ownership
- CLI and agent surfaces over one underlying automation stack
- separating visual feedback concerns from the lowest-level automation core

It is not the primary product precedent for `action`, but it is highly relevant
when we are deciding how to structure:

- native permissions
- capture services
- macOS automation boundaries
- app/CLI/MCP sharing

Use Peekaboo mainly as an implementation precedent for native host architecture,
not as a reason to broaden `action` beyond the guided demo mission.

## Rule

Before implementing a substantial feature, do a short precedent review.

A substantial feature includes things like:

- HUD
- stage and viewport
- countdown and recording controls
- target resolution
- timeline/scenario format
- overlays and cues
- replay and artifact presentation
- composition/export behavior

## What A Precedent Review Should Ask

For the specific feature being built:

1. What did `vif` do that was genuinely good?
2. What did `stage` do that was genuinely good?
3. What failed in those implementations?
4. What should be preserved in spirit but re-implemented differently?
5. What should be explicitly rejected this time?

Also ask:

6. Is this feature better informed by `vif` as product precedent, `stage` as
   architecture precedent, or both?

The review does not need to be long. It does need to be explicit.

## Expected Output

For each substantial feature, produce a short note before or during
implementation with these headings:

### Keep

- behaviors, UX ideas, or implementation instincts worth preserving

### Avoid

- failure modes, overreach, or known weak abstractions

### Adapt

- ideas that were good but need a different architecture in `action`

### Decision

- what this repo will actually build now

### Reference Weight

- whether this feature leans more on `vif`, `stage`, or a blend of both

## Example: HUD

### Keep

- a persistent control surface
- visible logs and state
- polished feeling, not a debug-only panel
- recording controls that are always easy to reach

### Avoid

- HUD logic owning runtime state directly
- UI behavior diverging from runtime truth
- messy control flow tied to CLI lifecycle hacks

### Adapt

- preserve the operator-first feeling
- move state authority into the runtime session model
- let the HUD render events instead of inventing its own truth

### Decision

- HUD is a thin frontend over guided-session events and controls

## Working Agreement

When implementing features in this repo:

- review the relevant precedent first
- write down the keep/avoid/adapt/declaration summary
- then implement

This keeps the rewrite grounded without letting old architecture silently
control the new one.
