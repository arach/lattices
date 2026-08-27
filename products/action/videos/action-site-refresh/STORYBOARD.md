# Action — Updated Website Film Storyboard

**Format:** 1920×1080, 30 fps, 21 seconds
**Audio:** Warm, concise voiceover + minimal analog/electronic underscore + restrained machine SFX
**VO direction:** Calm, curious, quietly confident; a field-documentary voice rather than an advertisement. Leave audible space after the opening question and before the final line.
**Style basis:** `DESIGN.md` — warm paper, graphite workbenches, coral record signals, cyan verified states, EB Garamond, and JetBrains Mono.

## Global Direction

The film behaves like an instrument waking up on a drafting table. Paper textures and precise geometry stay calm while browser surfaces, runtime states, and evidence move with mechanical clarity. Each beat has one obvious coral focal point, while cyan is reserved for confirmation. Motion is purposeful and visible: paths draw, states stamp into place, and artifacts travel from the live run into a durable manifest.

The underscore is a soft analog pulse at roughly 92 BPM: felted percussion, low tape warmth, and a faint electrical tick. It should swell under the evidence beat, then strip back to a single held tone for the closing mark. No triumphant corporate crescendo.

## Asset Audit

| Asset | Type | Assign to Beat | Role |
| --- | --- | --- | --- |
| `landing-hero-observe-act-record.png` | Hero illustration | Beats 1 and 5 | Recognizable Action world; opening camera field and closing tableau |
| `landing-trace-field.png` | Technical illustration | Beat 3 | Full-frame evidence map and motion-path bed |
| `landing-mira-field-companion.png` | Character illustration | Beat 4 | Human-scale companion and visible runtime-state metaphor |
| `action-mark.svg` | Brand mark | Beats 1, 2, and 5 | Opening stamp, browser badge, closing identity |
| `action-og.jpg` | Social image | Skip | Redundant with higher-resolution hero art |
| `action-mira-logo-poster.png` | Legacy poster | Skip | Tied to the outdated demo being replaced |
| `action-mira-midjourney-logo.mp4` | Legacy video | Skip | Outdated source material; documented only for contrast |

## Beat 1 — The Missing Proof (0.00–3.39s)

**VO:** “An agent can do the work. But can it show you what happened?”

**Concept:** The film opens already inside Action’s paper-and-ink world. A recorder is awake, but the evidence field is empty. The question lands like a red inspection stamp: capability without proof is incomplete.

**Visual:** A slow diagonal camera drift crosses `landing-hero-observe-act-record.png`, beginning on cream negative space and approaching the dark workstation. The Action mark sits in the upper-left as a tiny field label. Fine crosshairs draw around the coral lens. The words “AN AGENT CAN DO THE WORK” rise gently in EB Garamond; after a short hold, “CAN IT SHOW ITS WORK?” stamps over them in coral mono. A small REC node pulses once, and several tiny graphite calibration ticks react outward.

**Mood:** Editorial cold open; a technical monograph interrupted by a decisive field note.

**Techniques:** SVG path drawing for crosshairs and lens rings; per-word kinetic typography; Canvas 2D paper grain and calibration particles.

**Animation choreography:** Camera DRIFTS 3% across the hero; crosshairs DRAW clockwise; serif words SETTLE one phrase at a time; the coral question STAMPS with a two-frame overshoot; the REC node PULSES; calibration ticks SCATTER then lock.

**Transition:** Cinematic zoom through the coral lens, 0.55s, power2.inOut, into the browser/runtime workbench.

**Depth:** BG hero illustration and paper grain; MG concentric target geometry; FG typography, Action mark, and REC indicator.

**SFX:** Low tape tone from frame one; pencil-scratch path draw; warm shutter thunk on the coral question.

## Beat 2 — The Live Run (3.39–9.25s)

**VO:** “Action gives agents a real Chrome and a native macOS runtime to observe, resolve, act, and record.”

**Concept:** We are now inside a dark technical workbench where the browser and runtime operate as two sides of one instrument. This is not a generic desktop capture; it is an explicit, inspectable machine with a real browser surface and native state.

**Visual:** A graphite browser window unfolds in shallow perspective from the coral lens. Its chrome includes a small Action badge, tab strip, omnibox, active viewport, and a separate right-side runtime rail. The omnibox types `action://session/live`. A cursor target travels along an SVG route into the viewport, where four operational stages—OBSERVE, RESOLVE, ACT, RECORD—cascade across the bottom rail. OBSERVE reveals nodes, RESOLVE locks a coral reticle, ACT clicks with a restrained pulse, and RECORD turns the top-right status from slate to coral. A cyan line confirms the real Chrome connection while a second status line reads `NATIVE macOS RUNTIME`.

**Mood:** Darkroom instrumentation: exact, tactile, and legible rather than futuristic.

**Techniques:** CSS 3D transforms for browser assembly; character-by-character typing; SVG MotionPath for target travel; SVG path drawing for the connection line.

**Animation choreography:** Browser plane UNFOLDS from 76° to 4°; toolbar components SNAP into alignment; URL TYPES; cursor node TRAVELS; stage labels CASCADE at 280ms intervals; reticle LOCKS; click PULSES; REC state FLIPS; cyan verification line FILLS left to right.

**Transition:** Velocity-matched upward move: workbench exits y:-150 with blur 30px over 0.33s power2.in; the evidence field enters y:150→0 with blur clearing over 0.8s power2.out.

**Depth:** BG graphite grid and faint rule texture; MG browser and runtime rail; FG moving target, operational labels, connection status, and record lamp.

**SFX:** Quiet key taps for URL; precise relay clicks for each operational stage; subtle low pulse under REC.

## Beat 3 — Evidence, Not Ephemera (9.25–14.25s)

**VO:** “Every run leaves evidence: the capture, the trace, the snapshot, the accessibility tree, and the manifest.”

**Concept:** The run becomes a physical evidence map. Five outputs peel away from one coral source and arrive as durable, named objects—not a cloud of vague telemetry.

**Visual:** `landing-trace-field.png` fills the frame with a slow 1.02× drift. At the left coral target, a miniature REC core completes a rotation. A thin trace path draws across the paper toward the right target. Five artifact slips detach from the core and follow separate curved routes: `capture.mov`, `trace.json`, `snapshot.png`, `ax-snapshot.json`, and `manifest.json`. Each slip carries a small icon, timestamp, and verified cyan node. At right, the slips align into a graphite manifest panel while the headline “EVERY RUN LEAVES EVIDENCE” resolves above the connecting line.

**Mood:** Archival cartography—beautiful enough to study, exact enough to trust.

**Techniques:** GSAP MotionPath for artifact travel; SVG path drawing for the trace; per-word kinetic typography synced to narration; deterministic Canvas 2D micro-particles around verification nodes.

**Animation choreography:** Background DRIFTS; REC core ROTATES and stops; main trace DRAWS; artifact slips PEEL, TRAVEL, and DOCK in narration order; filenames TYPE on during travel; cyan nodes BLINK once; manifest panel ASSEMBLES line by line; headline RESOLVES with decaying horizontal motion.

**Transition:** Hard cut on the final manifest relay click to Mira’s field station; the coral target position is composition-matched to Mira’s machine lens.

**Depth:** BG trace-field illustration and paper grain; MG trace path, targets, and artifact routes; FG artifact slips, manifest panel, headline, and verification nodes.

**SFX:** Five soft paper/mechanical ticks, one per artifact; rising but restrained electrical tone along the trace; clean latch when the manifest finishes.

## Beat 4 — Ready to Inspect (14.25–18.61s)

**VO:** “One run. Every artifact. Ready to review, replay, and share.”

**Concept:** Proof becomes useful when someone—or another agent—can inspect it. Mira gives the system a visible, companionable presence while the three next actions become clear choices.

**Visual:** `landing-mira-field-companion.png` pans gently from the recording machine toward Mira. Above the machine, three square paper tiles emerge along the existing coral trajectory: REVIEW, REPLAY, SHARE. Each tile contains a tiny line icon and mono status. A coral orb follows the source illustration’s arc, touching each tile; touched tiles change from slate to cyan-verified. The serif line “ONE RUN. EVERY ARTIFACT.” sits in the clean left field.

**Mood:** Warm field station; competent and companionable, with notebook clarity.

**Techniques:** SVG MotionPath for the coral orb; CSS 3D tile reveals; SVG path drawing for tile icons; per-word typography for the thesis line.

**Animation choreography:** Image PANS 4%; machine lens BREATHES; thesis words RISE; tiles FLIP up in sequence; coral orb SWEEPS across the arc; icons DRAW; statuses TURN cyan; Mira’s target reticle PINGS once.

**Transition:** Blur-through to paper, 0.3s out and 0.25s in; all geometry converges toward the center Action mark.

**Depth:** BG field-companion illustration; MG machine, Mira, and orbital path; FG thesis, action tiles, coral orb, and cyan confirmations.

**SFX:** Soft servo sweep; three muted ceramic taps; a tiny bright confirmation tone on SHARE.

## Beat 5 — Record the Work (18.61–21.00s)

**VO:** “Action. Record the work.”

**Concept:** The instrument resolves into its identity. The close is confident and sparse: Action exists so agent work can be seen, trusted, and shared.

**Visual:** Warm paper fills the frame. A cropped echo of `landing-hero-observe-act-record.png` remains at 18% opacity on the right, keeping the world present. Construction lines contract into the centered Action mark, which settles beside the serif wordmark. The coral line `RECORD THE WORK` types below; a final mono footer reads `OBSERVE · RESOLVE · ACT · RECORD`. One cyan status point closes the sequence.

**Mood:** Publisher’s colophon meets a recorder’s end slate.

**Techniques:** SVG path drawing and morph-like line convergence; character typing for the CTA; audio-reactive 2% scale breath on the mark; Canvas 2D paper texture.

**Animation choreography:** Construction lines CONVERGE; mark SETTLES with a 1.015→1 scale ease; wordmark FADES upward; CTA TYPES; footer TICKS in; cyan point LIGHTS and holds for the final 10 frames.

**Transition:** Hold the finished end card for 0.8s, then cut cleanly to black.

**Depth:** BG paper and ghosted hero art; MG converging geometry; FG Action mark, wordmark, CTA, footer, and cyan status point.

**SFX:** Music resolves to one warm chord; single recorder stop click; no tail after black.

## Production Architecture

```text
action-site-refresh/
├── index.html
├── DESIGN.md
├── SCRIPT.md
├── STORYBOARD.md
├── transcript.json
├── narration.wav
├── capture/
│   ├── screenshots/
│   ├── assets/
│   │   ├── svgs/
│   │   ├── fonts/
│   │   ├── lottie/
│   │   └── videos/
│   └── extracted/
│       ├── tokens.json
│       ├── visible-text.txt
│       └── asset-descriptions.md
└── compositions/
    ├── beat-1-hook.html
    ├── beat-2-live-run.html
    ├── beat-3-evidence.html
    ├── beat-4-inspect.html
    └── beat-5-close.html
```
