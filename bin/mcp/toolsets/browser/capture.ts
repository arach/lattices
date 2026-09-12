/**
 * Deciding what rectangle a screenshot covers, separately from taking it.
 *
 * Design review is most of what browser_screenshot gets used for, and cropping a
 * full-viewport PNG by hand afterwards loses the one property that makes a
 * capture evidence: that its pixels correspond to CSS pixels at a known scale.
 * Every clip this module produces is emitted at scale 1, and every capture
 * reports the scale it used so a reader never has to assume.
 */

/** Chrome refuses a capture larger than this on either edge. */
export const MAX_CAPTURE_EDGE = 16_384;

export type CaptureRect = { x: number; y: number; width: number; height: number };

export type CaptureRequest =
  | { kind: "viewport" }
  | { kind: "fullPage" }
  | { kind: "element"; selector: string; padding: number }
  | { kind: "clip"; clip: CaptureRect };

function finitePositive(value: unknown, label: string): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) {
    throw new Error(`clip.${label} must be a finite number greater than zero.`);
  }
  return value;
}

function finiteNonNegative(value: unknown, label: string): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
    throw new Error(`${label} must be a finite nonnegative number.`);
  }
  return value;
}

export function parseCaptureRequest(args: Record<string, unknown>): CaptureRequest {
  const selector = args.selector;
  const clip = args.clip;
  const fullPage = args.fullPage === true;

  if (selector !== undefined && (typeof selector !== "string" || !selector.trim())) {
    throw new Error("selector must be a non-empty CSS selector.");
  }
  if (args.padding !== undefined && selector === undefined) {
    throw new Error("padding only applies alongside selector.");
  }

  // These three name three different rectangles. Picking one silently would make
  // the returned PNG a guess about which the caller meant.
  const chosen = [selector !== undefined && "selector", clip !== undefined && "clip", fullPage && "fullPage"]
    .filter(Boolean) as string[];
  if (chosen.length > 1) {
    throw new Error(`Choose one of ${chosen.join(", ")}: they describe different capture areas.`);
  }

  if (typeof selector === "string") {
    return { kind: "element", selector: selector.trim(), padding: finiteNonNegative(args.padding ?? 0, "padding") };
  }

  if (clip !== undefined) {
    if (typeof clip !== "object" || clip === null || Array.isArray(clip)) {
      throw new Error("clip must be an object with x, y, width, and height.");
    }
    const rect = clip as Record<string, unknown>;
    return {
      kind: "clip",
      clip: {
        x: finiteNonNegative(rect.x, "clip.x"),
        y: finiteNonNegative(rect.y, "clip.y"),
        width: finitePositive(rect.width, "width"),
        height: finitePositive(rect.height, "height"),
      },
    };
  }

  return fullPage ? { kind: "fullPage" } : { kind: "viewport" };
}

export type MeasuredElement = {
  /** Rect in document coordinates: viewport rect plus scroll offset. */
  x: number;
  y: number;
  width: number;
  height: number;
};

export type DocumentSize = { width: number; height: number };

export type ClipOutcome = {
  clip: CaptureRect;
  /** True when padding or the document edge changed what was asked for. */
  clamped: boolean;
  /** True when the requested area exceeded Chrome's capture ceiling. */
  truncated: boolean;
};

/**
 * Expand an element rect by its padding, then hold it inside the document. A clip
 * that runs off the page returns transparent pixels rather than an error, which
 * reads as a rendering bug in the page being reviewed.
 */
export function clipForRect(rect: MeasuredElement, padding: number, document: DocumentSize): ClipOutcome {
  const left = rect.x - padding;
  const top = rect.y - padding;
  const right = rect.x + rect.width + padding;
  const bottom = rect.y + rect.height + padding;

  const x = Math.max(0, left);
  const y = Math.max(0, top);
  const maxRight = document.width > 0 ? Math.min(right, document.width) : right;
  const maxBottom = document.height > 0 ? Math.min(bottom, document.height) : bottom;

  let width = Math.max(1, maxRight - x);
  let height = Math.max(1, maxBottom - y);
  const truncated = width > MAX_CAPTURE_EDGE || height > MAX_CAPTURE_EDGE;
  width = Math.min(width, MAX_CAPTURE_EDGE);
  height = Math.min(height, MAX_CAPTURE_EDGE);

  const clamped = x !== left || y !== top || maxRight !== right || maxBottom !== bottom;
  return { clip: { x, y, width, height }, clamped, truncated };
}

/** Measure an element in document coordinates, plus the document's own size. */
export function measureElementExpression(selector: string): string {
  return `(() => {
    const element = document.querySelector(${JSON.stringify(selector)});
    if (!element) return { found: false };
    const rect = element.getBoundingClientRect();
    const doc = document.documentElement;
    return {
      found: true,
      x: rect.x + window.scrollX,
      y: rect.y + window.scrollY,
      width: rect.width,
      height: rect.height,
      documentWidth: Math.max(doc.scrollWidth, document.body ? document.body.scrollWidth : 0),
      documentHeight: Math.max(doc.scrollHeight, document.body ? document.body.scrollHeight : 0),
      tag: element.tagName.toLowerCase(),
    };
  })()`;
}
