import type { Bounds, RuntimeAction } from "@action/protocol";

/**
 * The layer primitives: click, type, press, drag and scroll on the agent layer, with
 * points read the way the agent sees them. By default a point is a pixel in the last
 * layer snapshot, which is what the agent looked at; `space: "layer"` takes points on
 * the layer display instead. Either way the act lands as a blink, off the operator's
 * screens.
 */

export type LayerPrimitive = "click" | "type" | "press" | "drag" | "scroll";

export type LayerPointSpace = "snapshot" | "layer";

/** What the last snapshot showed: its crop of the layer (display-local points) and its pixel size. */
export interface LayerView {
  crop: { x: number; y: number; width: number; height: number };
  width: number;
  height: number;
}

export interface LayerPoint {
  x: number;
  y: number;
}

type Args = Record<string, unknown>;

function finite(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

/** `{ x, y }` or `[x, y]`. */
export function readPoint(value: unknown): LayerPoint | undefined {
  if (Array.isArray(value) && value.length === 2) {
    const [x, y] = value.map(finite);
    return x !== undefined && y !== undefined ? { x, y } : undefined;
  }
  if (value && typeof value === "object") {
    const x = finite((value as Args).x);
    const y = finite((value as Args).y);
    return x !== undefined && y !== undefined ? { x, y } : undefined;
  }
  return undefined;
}

export function readSpace(value: unknown): LayerPointSpace {
  if (value === undefined || value === "snapshot") {
    return "snapshot";
  }
  if (value === "layer") {
    return "layer";
  }
  throw new Error(`space must be "snapshot" (pixels in the last layer snapshot) or "layer" (points on the layer display)`);
}

/** A point as the agent gave it, to global top-left points on the layer display. */
export function toGlobal(
  point: LayerPoint,
  space: LayerPointSpace,
  bounds: Bounds,
  view: LayerView | undefined,
): LayerPoint {
  if (space === "layer") {
    return { x: bounds.x + point.x, y: bounds.y + point.y };
  }
  if (!view || view.width <= 0 || view.height <= 0) {
    throw new Error(
      'No layer snapshot to read the point against. Call action.layer.snapshot first, or pass space: "layer" for points on the layer display.',
    );
  }
  if (point.x < 0 || point.y < 0 || point.x > view.width || point.y > view.height) {
    throw new Error(
      `${point.x},${point.y} is outside the last snapshot (${view.width}×${view.height} px).`,
    );
  }
  const scaleX = view.crop.width / view.width;
  const scaleY = view.crop.height / view.height;
  return {
    x: Math.round((bounds.x + view.crop.x + point.x * scaleX) * 10) / 10,
    y: Math.round((bounds.y + view.crop.y + point.y * scaleY) * 10) / 10,
  };
}

function requirePoint(args: Args, key: string, primitive: LayerPrimitive): LayerPoint {
  const point = readPoint(args[key]);
  if (!point) {
    throw new Error(`${primitive} needs ${key}: { x, y } or [x, y]`);
  }
  return point;
}

/** `x`/`y` at the top level, or `at`. */
function requireAt(args: Args, primitive: LayerPrimitive): LayerPoint {
  const x = finite(args.x);
  const y = finite(args.y);
  if (x !== undefined && y !== undefined) {
    return { x, y };
  }
  return requirePoint(args, "at", primitive);
}

/**
 * The runtime action a primitive runs as. `subject` is the layer's app, which a label
 * click and keyboard acts are aimed at.
 */
export function primitiveAction(
  primitive: LayerPrimitive,
  args: Args,
  context: { bounds: Bounds; view: LayerView | undefined; subjectBundleId?: string },
): RuntimeAction {
  const space = readSpace(args.space);
  const global = (point: LayerPoint) => toGlobal(point, space, context.bounds, context.view);
  const id = `layer_${primitive}_${Date.now().toString(36)}`;

  switch (primitive) {
    case "click": {
      const label = typeof args.label === "string" && args.label.trim() !== "" ? args.label.trim() : undefined;
      if (label) {
        if (!context.subjectBundleId) {
          throw new Error("A label click needs the layer opened with a bundleId.");
        }
        return {
          id,
          kind: "click",
          description: `click "${label}"`,
          input: { bundleId: context.subjectBundleId, label },
        };
      }
      const point = global(requireAt(args, primitive));
      const holdMs = finite(args.holdMs);
      return {
        id,
        kind: "click",
        description: "click",
        target: { point },
        input: { point, ...(holdMs !== undefined ? { holdMs } : {}) },
      };
    }
    case "type": {
      if (typeof args.text !== "string" || args.text === "") {
        throw new Error('type needs text. End it with "\\n" to submit.');
      }
      return { id, kind: "type", description: "type", input: { text: args.text } };
    }
    case "press": {
      if (typeof args.key !== "string" || args.key.trim() === "") {
        throw new Error('press needs key: "return", "cmd+l", "⌘⇧T"…');
      }
      return { id, kind: "press-key", description: `press ${args.key}`, input: { key: args.key } };
    }
    case "drag": {
      const from = global(requirePoint(args, "from", primitive));
      const to = global(requirePoint(args, "to", primitive));
      const durationMs = finite(args.durationMs);
      return {
        id,
        kind: "drag",
        description: "drag",
        input: { from, to, ...(durationMs !== undefined ? { durationMs } : {}) },
      };
    }
    case "scroll": {
      const point = global(requireAt(args, primitive));
      const deltaX = finite(args.dx) ?? 0;
      const deltaY = finite(args.dy) ?? 0;
      if (deltaX === 0 && deltaY === 0) {
        throw new Error("scroll needs dy or dx (wheel pixels; positive dy scrolls up, the way a wheel turned up does)");
      }
      return { id, kind: "scroll", description: "scroll", target: { point }, input: { point, deltaX, deltaY } };
    }
  }
}
