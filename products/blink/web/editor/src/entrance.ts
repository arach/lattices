/**
 * Entrance effects for the Blink v2 editor surface (Arrival).
 *
 * Notes don't appear — they land. The native panel animates its own window
 * (alpha, and for "drop" the frame); this module choreographs the *content*
 * inside the web layer, keyed off a transient `data-enter` attribute on
 * `<body>` that the per-effect CSS (`build.mjs` PAGE_CSS) animates against.
 *
 *   shimmer  — content starts at 0 opacity; a soft highlight sweep crosses the
 *              sheet left→right as the text fades in behind it.
 *   drop     — the content fades in while the native window scales/drifts into
 *              place (the settle spring lives natively; here we just fade).
 *   draw     — for FLAT sheets: the frame chrome (dotted outline / brackets /
 *              margin rule, all painted on body::before) strokes itself on via
 *              a clip-path wipe, THEN the text fades in. On glass/card there is
 *              no frame to draw, so the native side substitutes "shimmer".
 *   none     — instant (no class, no animation).
 *
 * This module only owns the name set and the (self-clearing) DOM write; it never
 * posts a message — a purely presentational garnish, same no-echo discipline as
 * setContent/setMode/setSheet.
 */

/** The entrance kinds the web layer understands. */
export type Entrance = "shimmer" | "drop" | "draw" | "none";

const ENTRANCES: readonly Entrance[] = ["shimmer", "drop", "draw", "none"] as const;

/** True if `kind` is a known entrance name. */
function isEntrance(kind: string): kind is Entrance {
  return (ENTRANCES as readonly string[]).includes(kind);
}

/** Tracks the timer that clears the current `data-enter` so a rapid re-entry
 *  (e.g. the blink toggled twice) cancels the previous one cleanly rather than
 *  leaving the page stuck mid-animation. */
let clearTimer: number | undefined;

/**
 * Run an entrance. Sets `data-enter="<kind>"` on `<body>` (which the CSS
 * animates), then clears it after `durationMs` so the page returns to its
 * resting state and a later entrance starts fresh. Unknown kinds and `"none"`
 * are no-ops (the content simply shows instantly). Re-entrancy safe.
 */
export function runEntrance(kind: string, durationMs: number): void {
  const body = document.body;

  // Always cancel any in-flight entrance first: a stuck-mid-fade page is worse
  // than an abrupt one, and rapid toggles must never accumulate.
  if (clearTimer !== undefined) {
    clearTimeout(clearTimer);
    clearTimer = undefined;
  }
  body.removeAttribute("data-enter");

  if (!isEntrance(kind) || kind === "none") return;

  // Duration drives the CSS via a custom property so native config flows through
  // to the keyframes without hard-coding a value here.
  const dur = Number.isFinite(durationMs) && durationMs > 0 ? durationMs : 260;
  body.style.setProperty("--blink-enter-ms", `${dur}ms`);

  // Force a reflow so re-applying the same attribute restarts the animation.
  body.setAttribute("data-enter", kind);
  void body.offsetWidth;

  clearTimer = window.setTimeout(() => {
    body.removeAttribute("data-enter");
    body.style.removeProperty("--blink-enter-ms");
    clearTimer = undefined;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
  }, dur + 120) as unknown as number;
}
