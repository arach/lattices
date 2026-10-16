import type { Bounds, ResolvedTarget, RuntimeAction } from "@action/protocol";

import { parseKeyChord } from "./keys.js";

interface CalculatorButtonDescriptor {
  text?: string;
  semanticId?: string;
}

type HostRunner = (command: string, ...args: string[]) => Promise<{ stdout: string }>;

/**
 * An active agent layer, as the interaction router needs it. When present, coordinate
 * clicks inside `bounds` and keyboard acts run as blink acts against the layer's app.
 */
export interface AgentLayerRouting {
  bundleId?: string;
  pid?: number;
  /** Global top-left bounds of the layer display. Omitted means every point routes. */
  bounds?: Bounds;
}

export interface InteractionExecutionContext {
  runHost: HostRunner;
  resolveCalculatorButton: (query: CalculatorButtonDescriptor) => string;
  resolveBundleId: (surfaceId: string | undefined) => string | undefined;
  agentLayer?: AgentLayerRouting;
}

export type BlinkRoute = "blink-click" | "blink-type" | "blink-key" | "blink-drag" | "blink-scroll";

type RoutingContext = Pick<InteractionExecutionContext, "resolveBundleId" | "agentLayer">;

function numberFromInput(input: unknown): number | undefined {
  if (typeof input === "number" && Number.isFinite(input)) {
    return input;
  }

  if (typeof input === "string") {
    const value = Number(input);
    if (Number.isFinite(value)) {
      return value;
    }
  }

  return undefined;
}

function pointFromInput(input: unknown): { x: number; y: number } | undefined {
  if (!input || typeof input !== "object") {
    return undefined;
  }

  const record = input as Record<string, unknown>;
  const x = numberFromInput(record.x);
  const y = numberFromInput(record.y);
  if (x === undefined || y === undefined) {
    return undefined;
  }

  return { x, y };
}

function centerOfBounds(input: unknown): { x: number; y: number } | undefined {
  if (!input || typeof input !== "object") {
    return undefined;
  }

  const record = input as Record<string, unknown>;
  const x = numberFromInput(record.x);
  const y = numberFromInput(record.y);
  const width = numberFromInput(record.width);
  const height = numberFromInput(record.height);

  if (x === undefined || y === undefined || width === undefined || height === undefined) {
    return undefined;
  }

  return {
    x: x + width / 2,
    y: y + height / 2,
  };
}

function stringValue(input: unknown): string | undefined {
  return typeof input === "string" && input.length > 0 ? input : undefined;
}

function numberValue(input: unknown): number | undefined {
  return typeof input === "number" && Number.isFinite(input) ? input : undefined;
}

function targetLabel(action: RuntimeAction, target: ResolvedTarget | undefined): string | undefined {
  return stringValue(action.input?.targetLabel)
    ?? stringValue(action.input?.label)
    ?? action.target?.text
    ?? action.target?.semanticId
    ?? target?.label;
}

function targetRole(action: RuntimeAction): string | undefined {
  return stringValue(action.input?.role) ?? action.target?.role;
}

function targetBundleId(
  action: RuntimeAction,
  target: ResolvedTarget | undefined,
  context: RoutingContext,
): string | undefined {
  return stringValue(action.input?.bundleId)
    ?? context.resolveBundleId(action.target?.surfaceId ?? target?.surfaceId);
}

function holdMsFor(action: RuntimeAction): number | undefined {
  const holdMs = numberFromInput(action.input?.holdMs) ?? numberFromInput(action.input?.pressDurationMs);
  return holdMs !== undefined && holdMs > 0 ? holdMs : undefined;
}

export function clickPoint(action: RuntimeAction, target: ResolvedTarget | undefined): { x: number; y: number } | undefined {
  return pointFromInput(action.target?.point)
    ?? pointFromInput(action.input?.point)
    ?? target?.point
    ?? centerOfBounds(target?.bounds);
}

function pointInBounds(point: { x: number; y: number }, bounds: Bounds | undefined): boolean {
  if (!bounds) {
    return true;
  }
  return point.x >= bounds.x
    && point.x < bounds.x + bounds.width
    && point.y >= bounds.y
    && point.y < bounds.y + bounds.height;
}

/**
 * The app a blink-type or blink-key focuses. An explicit input.bundleId / input.pid wins;
 * otherwise the layer's subject app. The resolved surface is not used: it falls back to
 * whatever is frontmost on the user's screen, which is the app a blink must not type into.
 */
function blinkAppArgs(action: RuntimeAction, layer: AgentLayerRouting): string[] | undefined {
  const bundleId = stringValue(action.input?.bundleId);
  if (bundleId) {
    return ["--bundle-id", bundleId];
  }
  const pid = numberFromInput(action.input?.pid);
  if (pid !== undefined && pid > 0) {
    return ["--pid", String(Math.round(pid))];
  }
  if (layer.bundleId) {
    return ["--bundle-id", layer.bundleId];
  }
  if (layer.pid !== undefined && layer.pid > 0) {
    return ["--pid", String(layer.pid)];
  }
  return undefined;
}

/** A drag's start and end: from/source/start/fromX+fromY, and to/destination/end/toX+toY or the target's centre. */
export function dragPoints(action: RuntimeAction, target: ResolvedTarget | undefined): { from: { x: number; y: number }; to: { x: number; y: number } } | undefined {
  const fromFromCoordinates = (() => {
    const x = numberFromInput(action.input?.fromX);
    const y = numberFromInput(action.input?.fromY);

    if (x === undefined || y === undefined) {
      return undefined;
    }

    return { x, y };
  })();

  const sourcePoint = pointFromInput(action.input?.from)
    ?? pointFromInput(action.input?.source)
    ?? pointFromInput(action.input?.start)
    ?? fromFromCoordinates;

  const toFromCoordinates = (() => {
    const x = numberFromInput(action.input?.toX);
    const y = numberFromInput(action.input?.toY);

    if (x === undefined || y === undefined) {
      return undefined;
    }

    return { x, y };
  })();

  const targetPoint = pointFromInput(action.input?.to)
    || pointFromInput(action.input?.destination)
    || pointFromInput(action.input?.targetPoint)
    || pointFromInput(action.input?.end)
    || toFromCoordinates
    || centerOfBounds(target?.bounds)
    || centerOfBounds(action.target);

  return sourcePoint && targetPoint ? { from: sourcePoint, to: targetPoint } : undefined;
}

/** Where a scroll lands: the target point, input.point or input.at, or the target's centre. */
export function scrollPoint(action: RuntimeAction, target: ResolvedTarget | undefined): { x: number; y: number } | undefined {
  return action.target?.point
    ?? pointFromInput(action.input?.point)
    ?? pointFromInput(action.input?.at)
    ?? pointFromInput(target?.point)
    ?? centerOfBounds(target?.bounds);
}

/**
 * Which blink command, if any, `executeInteractionAction` will use for this act.
 * Undefined means the act takes its ordinary path. Accessibility paths
 * (press-accessibility-element, set-accessibility-value) never blink.
 */
export function blinkRouteFor(
  action: RuntimeAction,
  target: ResolvedTarget | undefined,
  context: RoutingContext,
): BlinkRoute | undefined {
  const layer = context.agentLayer;
  if (!layer) {
    return undefined;
  }

  if (action.kind === "click") {
    const bundleId = targetBundleId(action, target, context);
    const label = targetLabel(action, target);
    if (bundleId && label && holdMsFor(action) === undefined) {
      return undefined;
    }
    const point = clickPoint(action, target);
    return point && pointInBounds(point, layer.bounds) ? "blink-click" : undefined;
  }

  if (action.kind === "type") {
    const bundleId = targetBundleId(action, target, context);
    const label = targetLabel(action, target);
    if (bundleId && label) {
      return undefined;
    }
    return blinkAppArgs(action, layer) ? "blink-type" : undefined;
  }

  if (action.kind === "press-key") {
    return blinkAppArgs(action, layer) ? "blink-key" : undefined;
  }

  // A file drag carries a pasteboard the blink gesture doesn't; it takes the ordinary path.
  if (action.kind === "drag" && !stringValue(action.input?.filePath)) {
    const points = dragPoints(action, target);
    return points && pointInBounds(points.from, layer.bounds) && pointInBounds(points.to, layer.bounds)
      ? "blink-drag"
      : undefined;
  }

  if (action.kind === "scroll") {
    const point = scrollPoint(action, target);
    return point && pointInBounds(point, layer.bounds) ? "blink-scroll" : undefined;
  }

  return undefined;
}

export async function executeInteractionAction(
  action: RuntimeAction,
  target: ResolvedTarget | undefined,
  context: InteractionExecutionContext,
): Promise<void> {
  const blink = blinkRouteFor(action, target, context);
  const layer = context.agentLayer;

  if (action.kind === "type") {
    const text = String(action.input?.text ?? "");
    const bundleId = targetBundleId(action, target, context);
    const label = targetLabel(action, target);
    if (bundleId && label) {
      const args = [
        "set-accessibility-value",
        "--bundle-id", bundleId,
        "--label", label,
        "--value", text,
      ];
      const role = targetRole(action);
      if (role) {
        args.push("--role", role);
      }
      await context.runHost(args[0], ...args.slice(1));
      return;
    }

    const delayMs = numberValue(action.input?.delayMs);
    const appArgs = blink === "blink-type" && layer ? blinkAppArgs(action, layer) : undefined;
    const args = appArgs
      ? ["blink-type", "--text", text, ...appArgs]
      : ["type-text", "--text", text];
    if (delayMs && delayMs > 0) {
      args.push("--delay-ms", String(Math.round(delayMs)));
    }
    await context.runHost(args[0], ...args.slice(1));
    return;
  }

  if (action.kind === "press-key") {
    const { key, modifiers } = parseKeyChord(action.input ?? {});
    const appArgs = blink === "blink-key" && layer ? blinkAppArgs(action, layer) : undefined;
    const args = [appArgs ? "blink-key" : "press-key", "--key", key];
    if (modifiers.length > 0) {
      args.push("--modifiers", modifiers.join(","));
    }
    if (appArgs) {
      args.push(...appArgs);
    }
    await context.runHost(args[0], ...args.slice(1));
    return;
  }

  if (action.kind === "click") {
    // A hold is a HID gesture; the accessibility press path cannot express it, so any
    // requested holdMs forces the click through click-point.
    const holdMs = holdMsFor(action);
    const wantsHold = holdMs !== undefined;

    const bundleId = targetBundleId(action, target, context);
    const label = targetLabel(action, target);
    const hasCoordinateTarget = target?.mode === "coordinate"
      || action.target?.point || action.input?.point || target?.point;
    if (bundleId && label && !wantsHold && !hasCoordinateTarget) {
      const args = [
        "press-accessibility-element",
        "--bundle-id", bundleId,
        "--label", label,
      ];
      const role = targetRole(action);
      if (role) {
        args.push("--role", role);
      }
      await context.runHost(args[0], ...args.slice(1));
      return;
    }

    const point = clickPoint(action, target);
    if (point) {
      const command = blink === "blink-click" ? "blink-click" : "click-point";
      const args = [command, "--x", String(point.x), "--y", String(point.y)];
      if (holdMs !== undefined) {
        args.push("--hold-ms", String(Math.round(holdMs)));
      }
      await context.runHost(args[0], ...args.slice(1));
      return;
    }

    if (wantsHold) {
      throw new Error("Press-and-hold requires a point (action.target.point or input.point)");
    }

    if (bundleId !== "com.apple.calculator" || target?.mode === "coordinate") {
      throw new Error("Click requires a resolved point, bounds, or an accessibility target with an app bundle ID");
    }

    const buttonLabel = context.resolveCalculatorButton(
      target ? { text: target.label, semanticId: target.id } : action.target ?? {},
    );
    await context.runHost("click-calculator-button", "--button", buttonLabel);
    return;
  }

  if (action.kind === "drag") {
    const points = dragPoints(action, target);
    if (!points) {
      throw new Error("Drag action requires both from and to points");
    }
    const { from: sourcePoint, to: targetPoint } = points;

    const durationMs = numberFromInput(action.input?.durationMs) ?? numberValue(action.input?.duration) ?? 0;
    const filePath = stringValue(action.input?.filePath);

    const args = [
      blink === "blink-drag" ? "blink-drag" : "drag",
      "--from-x", String(sourcePoint.x),
      "--from-y", String(sourcePoint.y),
      "--to-x", String(targetPoint.x),
      "--to-y", String(targetPoint.y),
    ];
    if (durationMs > 0) {
      args.push("--duration-ms", String(Math.round(durationMs)));
    }
    if (filePath) {
      args.push("--file-path", filePath);
    }

    await context.runHost(args[0], ...args.slice(1));
    return;
  }

  if (action.kind === "scroll") {
    const point = scrollPoint(action, target);

    if (!point) {
      throw new Error("Scroll action requires a point (action.target.point or input.point)");
    }

    const deltaX = numberFromInput(action.input?.deltaX) ?? 0;
    const deltaY = numberFromInput(action.input?.deltaY) ?? 0;
    if (deltaX === 0 && deltaY === 0) {
      throw new Error("Scroll action requires a non-zero deltaX or deltaY");
    }

    const durationMs = numberFromInput(action.input?.durationMs) ?? numberValue(action.input?.duration) ?? 0;

    const args = [
      blink === "blink-scroll" ? "blink-scroll" : "scroll",
      "--x", String(point.x),
      "--y", String(point.y),
      "--delta-x", String(deltaX),
      "--delta-y", String(deltaY),
    ];
    if (durationMs > 0) {
      args.push("--duration-ms", String(Math.round(durationMs)));
    }

    await context.runHost(args[0], ...args.slice(1));
    return;
  }

  if (action.kind === "open-app") {
    const bundleId = targetBundleId(action, target, context);
    if (!bundleId) {
      throw new Error("open-app action requires a bundleId (input.bundleId or a resolved surface)");
    }

    const args = ["launch-app", "--bundle-id", bundleId];
    // The layer's own app opens without activating: it can't come to the front from a
    // background lease, and the window it brings is adopted onto the layer.
    const background = action.input?.background === true || (layer?.bundleId !== undefined && layer.bundleId === bundleId);
    if (background) {
      args.push("--background");
    }
    const url = stringValue(action.input?.url);
    if (url) {
      args.push("--url", url);
    }
    const timeoutMs = numberFromInput(action.input?.timeoutMs);
    if (timeoutMs !== undefined && timeoutMs > 0) {
      args.push("--timeout-ms", String(Math.round(timeoutMs)));
    }
    await context.runHost(args[0], ...args.slice(1));
    return;
  }

  if (action.kind === "focus-window") {
    const bundleId = targetBundleId(action, target, context);
    if (!bundleId) {
      throw new Error("focus-window action requires a bundleId (input.bundleId or a resolved surface)");
    }

    const args = ["focus-window", "--bundle-id", bundleId];
    const title = stringValue(action.input?.title) ?? stringValue(action.input?.windowTitle);
    if (title) {
      args.push("--title", title);
    }
    const timeoutMs = numberFromInput(action.input?.timeoutMs);
    if (timeoutMs !== undefined && timeoutMs > 0) {
      args.push("--timeout-ms", String(Math.round(timeoutMs)));
    }
    await context.runHost(args[0], ...args.slice(1));
    return;
  }

  // Every kind this runtime can perform returns above. Falling through means the action was
  // never dispatched, and reporting success for it would be a lie: callers derive
  // status: "succeeded" from this function returning without throwing.
  throw new Error(
    `Unsupported action kind "${action.kind}" — the macOS runtime has no handler for it, so nothing was performed.`,
  );
}
