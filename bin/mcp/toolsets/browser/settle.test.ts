import { expect, test } from "bun:test";

import {
  NETWORK_IDLE_QUIET_MS,
  NetworkIdleTracker,
  parseSettleRequest,
  parseWaitMs,
  selectorStateExpression,
  unsatisfiedSelectorError,
} from "./settle.ts";

const options = { defaultMode: "paint", defaultWaitMs: 10_000, label: "browser_click" } as const;

test("a bare interaction gets the tool's own default settle, not a shared one", () => {
  expect(parseSettleRequest({}, options)).toEqual({
    mode: "paint",
    waitMs: 10_000,
    selector: undefined,
    selectorState: "visible",
  });
  // A fill is usually not a navigation, so it waits for nothing unless asked.
  expect(parseSettleRequest({}, { ...options, defaultMode: "none", label: "browser_fill" }).mode).toBe("none");
});

test("an unknown settle mode names the ones that exist", () => {
  expect(() => parseSettleRequest({ settle: "idle" }, options))
    .toThrow(/settle must be one of none, paint, navigation, network-idle/);
});

test("waitForSelectorGone without a selector is rejected rather than ignored", () => {
  // Accepting it silently would leave the caller believing it asked for something.
  expect(() => parseSettleRequest({ waitForSelectorGone: true }, options))
    .toThrow(/only applies alongside waitForSelector/);
  expect(parseSettleRequest({ waitForSelector: ".modal", waitForSelectorGone: true }, options).selectorState).toBe("gone");
});

test("waitMs is bounded the same way browser_open bounds it", () => {
  expect(parseWaitMs(undefined, 10_000, "browser_click")).toBe(10_000);
  expect(parseWaitMs(0, 10_000, "browser_click")).toBe(0);
  for (const bad of [-1, Number.NaN, Number.POSITIVE_INFINITY, 2_147_483_648, "5000"]) {
    expect(() => parseWaitMs(bad, 10_000, "browser_click")).toThrow(/finite nonnegative/);
  }
});

test("the selector expression asks about visibility, not mere presence", () => {
  const visible = selectorStateExpression("#done", "visible");
  // A zero-size or display:none element is not the result a caller waited for.
  expect(visible).toContain("display");
  expect(visible).toContain("rect.width > 0");
  expect(selectorStateExpression("#spinner", "gone")).toContain("!visible");
});

test("a missed postcondition explains what did not happen", () => {
  const request = parseSettleRequest({ waitForSelector: "#done", waitMs: 3_000 }, options);
  expect(unsatisfiedSelectorError(request, "browser_click").message)
    .toContain("#done did not become visible within 3000ms");
});

test("network idle needs a quiet window, not merely an empty queue", () => {
  const tracker = new NetworkIdleTracker(0);
  expect(tracker.isIdle(0)).toBe(false);
  expect(tracker.isIdle(NETWORK_IDLE_QUIET_MS)).toBe(true);

  tracker.started("a", 1_000);
  tracker.started("b", 1_010);
  expect(tracker.pending).toBe(2);
  expect(tracker.isIdle(9_000)).toBe(false);

  tracker.settled("a", 1_100);
  expect(tracker.isIdle(9_000)).toBe(false);
  tracker.settled("b", 1_200);
  expect(tracker.isIdle(1_200 + NETWORK_IDLE_QUIET_MS)).toBe(true);
});

test("a request finishing that we never saw start does not strand the wait", () => {
  // Chrome reports requests that began before Network.enable. Counting those
  // would push the in-flight count negative and idle would never arrive.
  const tracker = new NetworkIdleTracker(0);
  tracker.settled("unknown", 100);
  expect(tracker.pending).toBe(0);
  expect(tracker.isIdle(NETWORK_IDLE_QUIET_MS)).toBe(true);
});
