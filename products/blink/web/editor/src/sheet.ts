/**
 * Sheet templates for the Blink v2 editor surface.
 *
 * A note's whole visual identity is drawn by the web layer as a *sheet* — the
 * native panel is an invisible carrier. The five sheets are selected by a
 * `data-sheet="<name>"` attribute on `<body>`; the actual per-sheet visuals
 * live in the bundled stylesheet (`build.mjs` PAGE_CSS), keyed off that
 * attribute. This module only owns the name set and the (idempotent, validated)
 * DOM write.
 *
 *   glass       — the default. Native glass panel behind a transparent editor
 *                 (zero visual change for existing users).
 *   card        — an index card: near-opaque warm dark paper with subtle grain.
 *   dotted      — a cut-out: transparent, a dotted outline, ink text.
 *   bracket     — architect's framing: transparent, four corner brackets.
 *   marginalia  — barest: transparent, a single vertical rule down the left.
 *
 * Sheets 3–5 (dotted/bracket/marginalia) are "flat": the native glass is off,
 * so ink lands directly on the user's wallpaper. Their legibility floor is the
 * text halo declared in PAGE_CSS via `--blink-halo`.
 */

/** The five sheet template names. */
export type Sheet = "glass" | "card" | "dotted" | "bracket" | "marginalia";

/** All valid sheet names (source of truth for validation). */
export const SHEETS: readonly Sheet[] = [
  "glass",
  "card",
  "dotted",
  "bracket",
  "marginalia",
] as const;

/** The fallback sheet for unknown / missing names. */
export const DEFAULT_SHEET: Sheet = "glass";

/** True if `name` is one of the known sheet templates. */
export function isSheet(name: string): name is Sheet {
  return (SHEETS as readonly string[]).includes(name);
}

/**
 * Apply a sheet by setting `data-sheet` on `<body>`. Idempotent (writing the
 * same value is a harmless no-op); unknown names fall back to `DEFAULT_SHEET`.
 * Never posts a message — purely a presentation change.
 */
export function applySheet(name: string): void {
  const sheet = isSheet(name) ? name : DEFAULT_SHEET;
  const body = document.body;
  if (body.getAttribute("data-sheet") === sheet) return;
  body.setAttribute("data-sheet", sheet);
}
