# Composition And Scenarios

## Purpose

This document explains what "composition" means in `action`, and how it relates
to agentic automation, manual capture, and reusable scenarios.

The key point is simple:

**Composition happens after capture.**

It is not the runtime. It is not the session controller. It is not the source of
truth for what happened.

## Core Idea

`action` should separate three concerns:

1. live interaction and capture
2. scenario representation
3. final presentation

Those are related, but they should not be fused into one system.

### Live Interaction And Capture

This is the runtime phase.

It includes:

- observing windows, surfaces, and targets
- acting through clicks, typing, focus changes, and waits
- recording video and screenshots
- collecting structured traces

This is where truth is created.

### Scenario Representation

A scenario is a reusable, inspectable description of what should happen.

It may be authored:

- directly by a human
- directly by an agent
- derived from a recorded session
- derived from a hybrid of user actions plus later cleanup

This is where intent is organized.

### Final Presentation

This is the composition phase.

It includes:

- zooms
- reframing
- cursor emphasis
- chapter cards
- subtitles
- narration timing
- music
- transitions

This is where polish is applied.

## What Composer-Core Should Mean

`composer-core` should be a narrow package.

It should own:

- render-manifest types
- composition-friendly timing structures
- focus-window descriptions
- chapter and subtitle placement data
- effect definitions that can be consumed by a renderer

It should not own:

- live app control
- target resolution
- session lifecycle
- capture start/stop
- HUD control
- input synthesis

That means `composer-core` is not "the video editor." It is the contract between
the runtime's artifacts and a rendering backend such as Remotion.

## Agentic First Still Holds

This architecture is still agentic first.

The agent-facing value comes from:

- stable targets
- deterministic runs
- inspectable traces
- reusable scenarios

The important shift is that the agent should not be forced to author everything
up front.

There are at least three valid ways to create a scenario.

## Three Scenario Sources

### 1. Authored Scenario

A human or agent writes the intended sequence before execution.

Example:

- open Calculator
- type `12`
- click `+`
- type `30`
- press `=`

This is the most direct "agentic automation" mode.

### 2. Recorded Session

A human drives the product manually while `action` records:

- video
- focus changes
- target resolutions
- clicks
- keys
- timing
- window state

Later, `action` can convert that into a structured scenario draft.

This is the mode you were pointing at: a user navigates a website or UI, and the
system turns the observed session into something reusable.

### 3. Hybrid Scenario

The user records an initial pass, and then the system or agent cleans it up:

- replace weak coordinate clicks with semantic targets
- remove dead time
- add preconditions
- normalize waits
- insert cues

This is likely one of the strongest long-term workflows for `action`.

## Why Recorded Sessions Matter

Recorded sessions solve a real product problem.

Many users know how to show the flow they want, but they do not want to author a
scene format from scratch.

If `action` can observe a manual run and convert it into a scenario draft, then:

- onboarding becomes much easier
- the runtime captures real truth from the product
- agents get a better starting point than a blank file
- deterministic reruns become possible after the initial demonstration

This is one of the most compelling directions in the product.

## Proposed Pipeline

The long-term pipeline should look like this:

1. run a live session
2. capture media plus trace
3. derive or refine a scenario from the trace
4. replay or rerun that scenario deterministically
5. compose a polished export from the captured or rerun artifacts

In short:

`capture -> trace -> scenario -> rerun -> compose`

Not every workflow needs every step, but this is the most powerful full loop.

## Trace-To-Scenario

The compiler should not only accept hand-authored scene input.

It should also eventually accept recorded traces as source material.

That implies two compiler inputs:

- `intent -> timeline`
- `trace -> scenario draft -> timeline`

The second path is important because it lets `action` learn from a real user-run
session without turning the runtime into a scene DSL.

## What The Trace Must Preserve

If we want recorded sessions to become reusable scenarios later, the trace needs
to preserve enough structure now.

That includes:

- window and surface identity
- target query and resolution result
- confidence levels
- click positions
- key presses and text entry
- timing boundaries
- state transitions
- artifacts created during the run

This is another reason the runtime matters more than the scene format.

## What Composition Consumes

The composition layer should consume:

- raw video capture
- screenshots
- runtime trace
- viewport and focus metadata
- cues or chapters
- optional voice and music timing

It should then produce:

- a render manifest
- renderer-specific instructions
- final output artifacts

## A Practical Product Reading

A useful way to think about `action` is:

- the runtime is the camera operator and automation system
- the trace is the shooting log
- the scenario is the shot list or repeatable script
- the composer is post-production

That framing keeps the architecture honest.

## Implication For Early Milestones

The first milestone should focus on capture and trace, not polished composition.

That is why the guided capture loop is the right first implementation target.

Once that exists, the system can support:

- direct deterministic demos
- manual guided recordings
- trace-derived scenario drafts
- polished exports later
