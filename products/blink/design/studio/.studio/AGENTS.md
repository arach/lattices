# Blink Studio + Local Agents

This studio follows the shared studio hybrid workflow: human iteration in the
browser, zero-friction pickup by local agents.

## Human surface (browser)

- Doc pages (`plans/v2-plan`, `plans/ui-map`, `foundations/functionality-v1`)
  render through `<AnnotatableDoc>`: click blocks or select spans to leave
  notes, 🎤 for dictation, ★ to pin the notes that should become decisions.
- Study pages (`studies/*`) are live macOS and iOS mockups with design intent,
  specs, and open questions. Controlled comparisons keep product behavior and
  fixture data fixed while visual treatments vary.

## Local agent surface

- Annotations persist to `.studio/annotations/<sanitized-key>.json` via the
  local API route (`app/api/studio/annotations/route.ts`).
- Any local process can `cat` those sidecars or hit
  `GET /api/studio/annotations?key=<href>`.
- Pinned notes are derived into structured `TreatmentDecision`s via
  `annotationsToDecisions`.

## Source of truth

The plan documents are NOT copied into this app — `app/api/docs/[doc]/route.ts`
reads them live from `blink/docs/`. Edit the markdown, refresh the page.
