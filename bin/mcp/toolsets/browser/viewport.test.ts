import { describe, expect, test } from "bun:test";

import {
  DEFAULT_WINDOW_SIZE,
  MAX_VIEWPORT_EDGE,
  MIN_VIEWPORT_EDGE,
  measureDrift,
  parseResizeRequest,
  viewportTarget,
  widthClass,
  windowBoundsFor,
} from "./viewport.ts";

describe("Action Browser resize targets", () => {
  test("emulates the tab by default, and never guesses at an unknown target", () => {
    expect(viewportTarget(undefined)).toBe("tab");
    expect(viewportTarget("tab")).toBe("tab");
    expect(viewportTarget("window")).toBe("window");
    expect(() => viewportTarget("screen")).toThrow("target must be either tab or window");
  });

  test("keeps CSS emulation options off the real-window path", () => {
    expect(() => parseResizeRequest({ width: 390, height: 844, target: "window", deviceScaleFactor: 2 }))
      .toThrow("only apply to target=tab");
    expect(() => parseResizeRequest({ width: 390, height: 844, target: "window", mobile: true }))
      .toThrow("only apply to target=tab");
  });
});

describe("Action Browser resize arguments", () => {
  test("requires an explicit width and height", () => {
    expect(() => parseResizeRequest({})).toThrow("width is required");
    expect(() => parseResizeRequest({ width: 390 })).toThrow("height is required");
  });

  test("defaults to a CSS-pixel-exact desktop viewport", () => {
    expect(parseResizeRequest({ width: 1280, height: 800 })).toEqual({
      kind: "set",
      target: "tab",
      matchMedia: [],
      viewport: { width: 1280, height: 800, deviceScaleFactor: 1, mobile: false },
    });
  });

  test("carries mobile emulation and retina density through", () => {
    const request = parseResizeRequest({
      width: 390,
      height: 844,
      mobile: true,
      deviceScaleFactor: 3,
      matchMedia: ["(max-width: 768px)", " (pointer: coarse) "],
    });
    expect(request).toEqual({
      kind: "set",
      target: "tab",
      matchMedia: ["(max-width: 768px)", "(pointer: coarse)"],
      viewport: { width: 390, height: 844, deviceScaleFactor: 3, mobile: true },
    });
  });

  test("rejects sizes Chrome cannot lay out", () => {
    expect(() => parseResizeRequest({ width: MIN_VIEWPORT_EDGE - 1, height: 800 }))
      .toThrow(`between ${MIN_VIEWPORT_EDGE} and ${MAX_VIEWPORT_EDGE}`);
    expect(() => parseResizeRequest({ width: 1280, height: MAX_VIEWPORT_EDGE + 1 }))
      .toThrow(`between ${MIN_VIEWPORT_EDGE} and ${MAX_VIEWPORT_EDGE}`);
    expect(() => parseResizeRequest({ width: 390.5, height: 844 }))
      .toThrow("whole number of CSS pixels");
    expect(() => parseResizeRequest({ width: "390", height: 844 }))
      .toThrow("width is required");
    expect(() => parseResizeRequest({ width: 390, height: 844, deviceScaleFactor: 9 }))
      .toThrow("deviceScaleFactor must be between");
    expect(() => parseResizeRequest({ width: 390, height: 844, matchMedia: [""] }))
      .toThrow("non-empty media query");
  });

  test("treats reset as its own instruction rather than a size", () => {
    expect(parseResizeRequest({ reset: true })).toEqual({ kind: "reset", target: "tab", matchMedia: [] });
    expect(parseResizeRequest({ reset: true, target: "window" }))
      .toEqual({ kind: "reset", target: "window", matchMedia: [] });
    expect(() => parseResizeRequest({ reset: true, width: 390, height: 844 }))
      .toThrow("reset cannot be combined with width or height");
  });
});

describe("Action Browser viewport reporting", () => {
  test("reports the gap when a page refuses the requested size", () => {
    expect(measureDrift({ width: 390, height: 844 }, { width: 390, height: 844 }))
      .toEqual({ exact: true, widthDelta: 0, heightDelta: 0 });
    expect(measureDrift({ width: 390, height: 844 }, { width: 980, height: 844 }))
      .toEqual({ exact: false, widthDelta: 590, heightDelta: 0 });
  });

  test("labels widths for the caller without pretending to know their breakpoints", () => {
    expect(widthClass(375)).toBe("mobile");
    expect(widthClass(600)).toBe("large-mobile");
    expect(widthClass(834)).toBe("tablet");
    expect(widthClass(1280)).toBe("small-desktop");
    expect(widthClass(1920)).toBe("desktop");
  });

  test("adds the tab strip and omnibox back when sizing a real window", () => {
    expect(windowBoundsFor({ width: 1280, height: 800 }, { width: 0, height: 87 }))
      .toEqual({ width: 1280, height: 887 });
    expect(windowBoundsFor(DEFAULT_WINDOW_SIZE, { width: 0, height: 0 }))
      .toEqual({ width: DEFAULT_WINDOW_SIZE.width, height: DEFAULT_WINDOW_SIZE.height });
  });

  test("never asks the window manager for a window smaller than a viewport floor", () => {
    expect(windowBoundsFor({ width: MIN_VIEWPORT_EDGE, height: MIN_VIEWPORT_EDGE }, { width: -400, height: -400 }))
      .toEqual({ width: MIN_VIEWPORT_EDGE, height: MIN_VIEWPORT_EDGE });
  });
});
