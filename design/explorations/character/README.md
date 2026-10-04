# Ledge — a careful mover for Lattices

Ledge is a small architectural tile with a carrying ledge. It picks things up with intent and puts them down precisely. The stepped shoulder, two clear eyes, and broad handhold give it a job before it moves.

This is an exploratory character study, following Fab's Tuck process: one isolated transparent master, exact generation prompts, a family of distinct alternatives, and honest size comparisons. It is not an adopted identity or an app feature.

## Personality and construction

Patient, attentive, and slightly particular about alignment. Ledge waits for the user, checks the destination, then carries the window as if it matters. It never races, hops, celebrates extravagantly, or asks for attention while idle.

The body is one solid stepped form. The face sits directly in the material; there is no screen or separate head. The lower handhold gives a window row somewhere to rest. The shape comes from the idea of a grid piece, rather than attaching eyes to the Lattices logo.

Keep the step, eye spacing, handhold, and feet consistent between poses. Change the gaze and posture, not the character's construction. Use off-white `#f2f2f2`, near-black `#141416`, neutral shading, and one running-green `#33C773` accent. Green belongs to the carrying surface.

## Files

- [ledge-v1.png](ledge-v1.png) — transparent PNG master made with built-in image generation.
- [prompt.txt](prompt.txt) — exact prompt used to generate the lead.
- [index.html](index.html) — standalone static gallery of all seven concepts, large and at 16, 24, and 32 px on dark and light surfaces.
- [alternatives-v1/README.md](alternatives-v1/README.md) — six names, personalities, and the small-control recommendation.
- [alternatives-v1/prompts.json](alternatives-v1/prompts.json) — exact alternative prompts.
- `alternatives-v1/01-shim.png`, `02-nook.png`, `03-dov.png`, `04-ply.png`, `05-span.png`, `06-plinth.png` — six transparent masters.

Open `index.html` directly in a browser. It has no script, build step, remote asset, or network dependency.

## Size and placement

The proposed control is 32 × 32 pt with a 24 × 24 pt image frame, centered with 4 pt of space on each side. Transparent padding inside a master makes its visible silhouette a little smaller than the frame. The gallery labels image-frame dimensions in CSS pixels, not opaque artwork bounds; compare at 100% browser zoom.

Use 24 px for the everyday control and 32 px for roomier placements. The 16 px sample is a lower-bound stress test. Large views reveal the shape and material; they are not the target interface size. A production asset pass should simplify broad shading and align the eyes to the target pixel grid, with separate 1× and 2× exports.

Ledge is the lead because its asymmetry and handhold explain carrying. The simpler alternatives help judge whether that extra character earns its space in a tiny control.

## Proposed desktop move — 2.5 seconds

The character accompanies the existing Overview operation. It must not delay the actual move just to finish a performance. A single window-row representation stays associated with its source and target desktop throughout.

| Time | Beat | Proposed behaviour |
| --- | --- | --- |
| 0–180 ms | Notice | Eyes turn toward the selected row. Feet remain planted. |
| 180–480 ms | Take hold | Ledge inclines by about 3°, places the ledge under the row, then lifts the row 3 pt as one rigid piece. |
| 480–780 ms | Check | Hold the row level. Eyes turn toward the target desktop column while Mission Control runs. |
| 780–1,780 ms | Carry | Travel horizontally toward the target at a measured pace, with a short ease-in and ease-out. Keep the row level; no bobbing, spring, or overshoot. |
| 1,780–2,150 ms | Place | Align with the destination slot, then lower the row 3 pt. Its edges meet the grid exactly. |
| 2,150–2,350 ms | Settle | Release the grip. The hands settle by at most 1 pt once; the placed row stays fixed. |
| 2,350–2,500 ms | Acknowledge | One shallow 2° nod only after the move is confirmed, then return to the idle pose. |

These are nominal timings for an operation that completes within the sequence. If Mission Control takes longer, hold at Check with both feet steady and the window supported. Do not loop the carry or imply success. Resume once the destination is ready; do not queue overlapping performances.

### State poses

- **Idle:** level feet, relaxed hands, eyes forward. No continuous breathing, bounce, blink loop, or other idle animation.
- **Thinking:** keep the row steady; shift the eyes toward the target and incline the body by at most 2° over 180 ms, then hold. Return over 120 ms when the operation resolves. A visible text status provides the meaning.
- **Success:** the single 150 ms nod above, gated on confirmed placement. Green is part of the character, not the only success signal.
- **Failure:** preserve or restore the row at its actual location. Ledge returns to rest, lifts both hands by 1 pt over 140 ms, holds for 120 ms, then lowers them over 180 ms: one small 440 ms shrug. Show the failure reason and retry action in normal interface text. Never animate a successful placement when the operation failed.

### Reduced motion

With Reduce Motion enabled, omit travel, lift, rotation, settle, nod, and shrug. Keep Ledge in its idle pose and use the existing progress/result text. Update the row directly to its confirmed destination; use an instantaneous change or a brief crossfade of at most 100 ms if appropriate. An operation's real duration and result remain the same. The character is decorative to assistive technology; the control keeps a functional accessible name.

Motion is a written proposal only. This folder contains no app integration and the gallery itself is still.

## Verification

All seven saved masters were created with built-in image generation and inspected as images. They have genuine RGBA transparency. The HTML is checked for all seven concepts, both surfaces, large views, exact 16/24/32 px image dimensions, and 24 px images in 32 px control frames. Links remain local to this folder; there are no scripts or external dependencies.

Rendered desktop/mobile gallery verification is still outstanding: this session's browser policy rejects local-file URLs, and the shell sandbox prevents binding a localhost preview server. The source review does not establish browser layout or native-control acceptance.
