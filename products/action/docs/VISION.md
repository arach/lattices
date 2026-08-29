# Vision

`action` is an agentic system for producing polished software demos and promotional videos on macOS.

It is designed for a workflow where an engineer, founder, or AI agent can say:

> Show the core features of this product clearly, stylishly, and repeatably.

And the system can turn that intent into a deterministic run, a trace of what happened, and a polished output that is ready to share.

## Why This Exists

Existing work in this space tends to split into a few categories:

- capture tools that are visually polished but not programmable enough
- automation tools that can click around but do not produce presentation-quality output
- DSL-driven systems that become fragile because execution, lifecycle, and rendering are all mixed together

`action` is meant to bridge those gaps.

It should feel like:

- a serious automation runtime
- a serious demo-production system
- a tool an agent can use confidently

## What We Learned From Prior Work

### From `vif`

Keep:

- ambition around browser/app automation plus media output
- promo/demo orientation
- support for overlays, audio, and export
- the insight that this is useful for AI-agent workflows

Do not keep:

- loosely bounded product surface
- CLI-owned lifecycle complexity
- runtime state spread across unrelated modules
- architectural drift caused by feature accumulation

### From `stage`

Keep:

- cleaner module instincts
- stronger agent-tool framing
- the desire for explicit capabilities and clearer boundaries

Do not keep:

- incomplete lifecycle/error handling
- underdeveloped reliability story
- early-stage abstractions that still need significant hardening

### From Recordly

Borrow:

- the render-time polish mindset
- auto zoom and stylish motion language
- cursor smoothing and emphasis
- project/artifact-oriented composition

Do not borrow:

- editor-first assumptions as the primary architecture
- GUI-centric runtime control

### From Stagehand

Borrow:

- the conceptual separation of `observe`, `act`, and `extract`
- conservative, inspectable target resolution
- agent-friendly interaction model

### From Peekaboo

Borrow:

- native-first Swift ownership of macOS automation concerns
- explicit permission handling as a first-class product concern
- thin consumer surfaces over a shared automation core
- the idea that visual feedback can be a distinct layer instead of being mixed into runtime truth

Do not borrow:

- a broad automation surface before the guided demo loop is solid
- product sprawl caused by trying to cover every macOS interaction mode too early

### From QuickRecorder and similar macOS-native tools

Borrow:

- native-first capture fidelity
- macOS-specific optimizations
- acceptance that cursor, capture, and media quality are better when treated as native concerns

### From Remotion

Borrow:

- rendering and templating as a backend capability
- separation of composition from capture/runtime concerns

Do not borrow:

- the temptation to make the rendering layer define the whole product

## Product Vision

The ideal end-state for `action` is:

1. an agent can inspect an app or website
2. resolve meaningful targets safely
3. execute a demo scenario deterministically
4. record raw media and rich metadata
5. automatically produce a polished output with zooms, cues, subtitles, and audio

The user should not need to hand-author every coordinate or every transition.

The user should be able to define intent, constraints, and style, while `action` handles the hard parts around:

- target resolution
- runtime stability
- capture fidelity
- metadata collection
- composition orchestration

## What `action` Should Be Great At

### 1. Agentic Demos

An AI agent should be able to:

- inspect available windows and surfaces
- resolve likely targets
- ask for confirmation when resolution is ambiguous
- execute a feature demo in a repeatable way

### 2. Product Storytelling

The output should feel closer to a polished product walkthrough than a raw screen recording.

That means:

- chapter cues
- focus guidance
- subtitles
- tasteful zooming and reframing
- cursor clarity
- music and narration support

### 3. Deterministic Runs

A run should leave behind a trace that explains:

- what was observed
- what targets were resolved
- what actions were taken
- what failed or was ambiguous
- what assets were produced

This is essential both for debugging and for agent trust.

### 4. Strong Native Fidelity

The system should feel designed for macOS, not merely compatible with it.

That includes:

- ScreenCaptureKit quality
- Accessibility API targeting
- native window handling
- native cursor and input behavior

## What We Explicitly Do Not Want

- a haunted runtime with hidden background state
- click automation that guesses recklessly
- a giant scene DSL that becomes the true implementation
- a framework that claims to be universal before it is reliable
- premature editor complexity
- a product that is visually polished but operationally fragile

## Design Taste

`action` should feel:

- deliberate
- inspectable
- native
- cinematic
- composable
- dependable

The cinematic part matters. This is not merely automation; it is automation in service of making good-looking software demos.

## v0 Aspiration

The first successful version of `action` should let a user or agent:

- define a short demo scenario
- run it against a macOS app or browser flow
- get a raw capture plus trace
- generate a polished edit with:
  - zooms
  - click emphasis
  - labels or chapters
  - subtitles
  - optional voice/music

That would already be meaningfully better than either a plain recorder or a plain automation tool.

## Strategic Direction

`action` should be built as a stable core with borrowable edges.

The system should own:

- runtime behavior
- session model
- targeting model
- trace model
- render manifest

And it should delegate where appropriate:

- Remotion for polished render backends
- FFmpeg or similar tools for specific media-processing tasks
- browser adapters for DOM-specific observation and action

This allows the product to move quickly without surrendering architectural control.

## Working Name

`action` is a good working name because it fits the cinema lexicon and reinforces the runtime emphasis.

It may or may not be the final public name. The architectural direction matters more than the branding for now.
