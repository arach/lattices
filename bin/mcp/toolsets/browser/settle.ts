/**
 * What "the click is done" means, as a value.
 *
 * Without this, an agent loop is click -> screenshot -> hope, and the only lever
 * is a fixed sleep that is either too short to be correct or too long to be
 * pleasant. Parsing the request into an explicit postcondition lets the caller
 * say what it is waiting for, and lets the failure say what never happened.
 */

export type SettleMode = "none" | "paint" | "navigation" | "network-idle";

export const SETTLE_MODES: readonly SettleMode[] = ["none", "paint", "navigation", "network-idle"];

/** Milliseconds of quiet that count as "the network stopped". */
export const NETWORK_IDLE_QUIET_MS = 500;

/**
 * How long to wait for a navigation to *start* before concluding the interaction
 * was not a navigating one. A click that navigates does so promptly; a click that
 * does not should not cost the caller its whole deadline.
 */
export const NAVIGATION_GRACE_MS = 1_500;

export type SettleRequest = {
  mode: SettleMode;
  waitMs: number;
  selector?: string;
  /** Whether the selector must appear, or stop matching. */
  selectorState: "visible" | "gone";
};

export type SettleOptions = {
  /** Tool-specific default, because a fill is usually not a navigation. */
  defaultMode: SettleMode;
  defaultWaitMs: number;
  label: string;
};

const MAX_WAIT_MS = 2_147_483_647;

export function parseWaitMs(value: unknown, fallback: number, label: string): number {
  if (value === undefined) return fallback;
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0 || value > MAX_WAIT_MS) {
    throw new Error(`${label} waitMs must be a finite nonnegative number no greater than ${MAX_WAIT_MS}.`);
  }
  return value;
}

export function parseSettleRequest(args: Record<string, unknown>, options: SettleOptions): SettleRequest {
  const mode = args.settle === undefined ? options.defaultMode : args.settle;
  if (typeof mode !== "string" || !SETTLE_MODES.includes(mode as SettleMode)) {
    throw new Error(`${options.label} settle must be one of ${SETTLE_MODES.join(", ")}.`);
  }

  const selector = args.waitForSelector;
  if (selector !== undefined && (typeof selector !== "string" || !selector.trim())) {
    throw new Error(`${options.label} waitForSelector must be a non-empty CSS selector.`);
  }

  const gone = args.waitForSelectorGone;
  if (gone !== undefined && typeof gone !== "boolean") {
    throw new Error(`${options.label} waitForSelectorGone must be a boolean.`);
  }
  // Silently ignoring this would leave the caller believing it asked for something.
  if (gone !== undefined && selector === undefined) {
    throw new Error(`${options.label} waitForSelectorGone only applies alongside waitForSelector.`);
  }

  return {
    mode: mode as SettleMode,
    waitMs: parseWaitMs(args.waitMs, options.defaultWaitMs, options.label),
    selector: typeof selector === "string" ? selector.trim() : undefined,
    selectorState: gone === true ? "gone" : "visible",
  };
}

/**
 * Track in-flight requests for the network-idle settle. Chrome can report a
 * request finishing that we never saw start (it began before Network.enable), so
 * the count floors at zero rather than going negative and stranding the wait.
 */
export class NetworkIdleTracker {
  private readonly inFlight = new Set<string>();
  private quietSince: number;

  constructor(now: number) {
    this.quietSince = now;
  }

  started(requestId: string, now: number): void {
    this.inFlight.add(requestId);
    this.quietSince = now;
  }

  settled(requestId: string, now: number): void {
    if (!this.inFlight.delete(requestId)) return;
    if (this.inFlight.size === 0) this.quietSince = now;
  }

  get pending(): number {
    return this.inFlight.size;
  }

  isIdle(now: number, quietMs = NETWORK_IDLE_QUIET_MS): boolean {
    return this.inFlight.size === 0 && now - this.quietSince >= quietMs;
  }

  quietFor(now: number): number {
    return this.inFlight.size === 0 ? Math.max(0, now - this.quietSince) : 0;
  }
}

/** The expression that answers whether a selector is in the requested state. */
export function selectorStateExpression(selector: string, state: "visible" | "gone"): string {
  return `(() => {
    const element = document.querySelector(${JSON.stringify(selector)});
    if (!element) return ${state === "gone" ? "true" : "false"};
    const style = getComputedStyle(element);
    const rect = element.getBoundingClientRect();
    const visible = style.display !== "none" && style.visibility !== "hidden" && Number(style.opacity) !== 0 && rect.width > 0 && rect.height > 0;
    return ${state === "gone" ? "!visible" : "visible"};
  })()`;
}

/** The message a caller needs when a postcondition never arrived. */
/**
 * How much of the deadline to hold back for the answer. The outer withDeadline
 * aborts the whole tool call at waitMs; without a margin its generic "timed out
 * after Nms" wins the race and the caller never learns which postcondition went
 * unmet -- which is the entire point of naming one.
 */
export const POSTCONDITION_MARGIN_MS = 300;

export function unsatisfiedNetworkIdleError(pending: number, waitMs: number, label: string): Error {
  return new Error(
    `${label} ran, but the page still had ${pending} request${pending === 1 ? "" : "s"} in flight `
    + `after ${waitMs}ms. Nothing was lost -- the interaction happened -- but the page had not gone quiet.`,
  );
}

export function unsatisfiedSelectorError(request: SettleRequest, label: string): Error {
  const wanted = request.selectorState === "gone" ? "stop matching" : "become visible";
  return new Error(
    `${label} ran, but waitForSelector ${request.selector} did not ${wanted} within ${request.waitMs}ms. `
    + "The interaction may not have had the effect it was expected to have.",
  );
}
