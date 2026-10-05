# Ply — one careful mover

A patient little mover who keeps things level and puts them down precisely.

Ply, Span and Plinth are now one character. **Ply** is the name; a low pedestal, a lifted stack and a bridge are its working postures. The broad off-white slab face, two dark pill eyes, green carrying surface, rounded edges and neutral material stay consistent. Only the supporting body, gaze and carried window change with the activity.

This family continues the [original study](../README.md) and its [alternatives](../alternatives-v1/README.md). It is exploratory artwork and a proposed Overview treatment. No app code is changed.

## Activity mapping

| Activity | Pose | When the app shows it |
| --- | --- | --- |
| Idle | [Resting slab](01-idle.png) on a low base | No window move is active; return here after the result settles. |
| Drop / pick up | [Lifted, offset slab](02-pick-up.png), window acquired | A valid Overview drop is accepted and the move is reserved, after pointer input is released. |
| Carry in flight | [Bridge legs](03-carry.png), window card upright on top | The window is being relocated and destination placement remains pending. |
| Mission Control running | [Patient wait](04-wait.png), settled base and upward gaze | Mission Control is working and destination membership is not yet confirmed. Hold this pose for as long as needed. |
| Landed / success | [Set down](05-set-down.png), card beside Ply and one green tick | The runtime confirms that the window reached the requested display and Desktop. |
| Failed / snap back | [Bridge with returned card](06-snap-back.png), downward gaze and muted gray | The move fails or remains unverified; Overview reconciles the pending tile to the window's observed location. |

These are proposed placements for the artwork, not six newly implemented runtime states. Current Overview publishes moving/pending state and the final receipt; separate pickup, carry and Mission Control phase events would need explicit integration.

The mapping follows `OverviewModel.swift` (accepted move reservation, deferred start, pending destination and reconciliation), `WindowSpaceCarry.swift` (Mission Control and Space membership checks), and `WindowMovementService.swift` (success requires both `status == "ok"` and `verified == true`). “Snap back” describes reconciliation of the projected tile. It does not promise a physical return to the original Desktop after every failure. Keep a plain-language result and retry action alongside the decorative character.

## Family rules

- Keep the face width, aspect ratio, eye shapes and spacing, camera, material and green top plane consistent. The upper slab moves as one rigid piece during pickup.
- Off-white near `#f2f2f2`, dark eyes and contour near `#141416`, neutral gray shading, one accent: `#33C773`. No purple, violet, magenta or red.
- A dark contour preserves the pale body on the light surface. The window is a plain neutral card, with one titlebar and no miniature interface details.
- Idle has an empty top. Pickup opens a gap between the slabs. Carry has a broad open arch and upright card. Waiting closes the arch into a low base. Success moves the card beside the character. Failure keeps the arch but lowers the card into a gray diagonal.
- Treat the window as one associated object through the move. The small side card in the success master is an icon-sized placement cue; the real window row remains the authoritative object.

## Gallery and motion

Open [index.html](index.html) directly in a browser. It uses local PNGs, system sans and locally available JetBrains Mono, with no build step, external assets or network dependency. Six poses appear side by side on both `#141416` and `#f2f2f2`, large and in exact 16, 24 and 32 CSS-pixel image frames. A further sample places a 24 px image inside a 32 px control. Narrow screens retain the comparison order with horizontal scrolling.

The gallery plays one **2.5-second** CSS sequence and provides replay and pause controls:

| Time | Pose |
| --- | --- |
| 0–350 ms | Idle |
| 350–800 ms | Pick up |
| 800–1,400 ms | Carry |
| 1,400–2,100 ms | Wait |
| 2,100–2,500 ms | Set down |

The strip swaps registered masters without bouncing, overshooting or an automatic loop. In the app, real operation state must determine the pace: never delay a finished move to complete the performance, hold Wait during a slow Mission Control operation, and never show success on a failed receipt. The failure pose is outside the successful sequence.

With Reduce Motion enabled, the live frame stays idle and the five labeled steps remain visible without animation. The character should be decorative to assistive technology; an eventual native control keeps its functional accessible name and existing progress/result text.

## Deliverables and provenance

- Six **1254 × 1254 RGBA** PNG pose masters, all generated with the built-in image tool from one identity anchor. The original files are retained by the tool; project copies live here without pixel edits. The resting baseline stays within five master pixels across all six poses, less than 0.1 px in a 24 px frame.
- [prompts.json](prompts.json) records the exact generation prompts and reference chain.
- [contact-sheet.png](contact-sheet.png) compares every master at its native resolution and at 24 px, on both surfaces. View the file at 100% for literal 24 px samples.
- [index.html](index.html) is the local comparison and motion study.
- [build-contact-sheet.mjs](build-contact-sheet.mjs) rebuilds the contact sheet with ImageMagick and prints the path to a compact size proof. It composites the original masters at native resolution and downsizes only the comparison samples.

## Verification

All six PNGs were inspected large and as literal 16/24/32 px raster samples on both surfaces. At 24 px, the empty top, separated slab, open bridge, settled base, side card and low diagonal card remain distinguishable. The gaze and tick are secondary details; neither carries the state alone. At 16 px those details soften, so 24 px remains the minimum intended image frame.

All masters share the same canvas dimensions and genuine transparency. The visible character baseline is consistent; the pickup slab deliberately lifts and offsets. An opaque-pixel hue check found no vivid red, purple, violet or magenta. The native contact sheet is 7764 × 2828 px, with six unscaled masters per surface and literal 24 px samples beneath them.

Source checks confirmed both surfaces, all six poses, exact small-size dimensions, local links, no missing files or duplicate IDs, valid gallery JavaScript syntax, a 2.5-second CSS sequence, image-decode gating, pause/replay and reduced-motion handling. The static design detector reported zero findings.

The sandbox denies localhost server binding, and browser policy disallows `file:` navigation, so this session cannot establish live browser layout or playback. The gallery can be opened locally by a person; native app integration and control acceptance remain outside this artwork task.
