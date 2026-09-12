import { expect, test } from "bun:test";

import { MAX_CAPTURE_EDGE, clipForRect, measureElementExpression, parseCaptureRequest } from "./capture.ts";

test("no area argument still means the viewport", () => {
  expect(parseCaptureRequest({})).toEqual({ kind: "viewport" });
  expect(parseCaptureRequest({ fullPage: true })).toEqual({ kind: "fullPage" });
  expect(parseCaptureRequest({ fullPage: false })).toEqual({ kind: "viewport" });
});

test("selector, clip and fullPage describe different rectangles, so only one may be given", () => {
  // Silently picking one would make the returned PNG a guess about intent.
  expect(() => parseCaptureRequest({ selector: ".card", fullPage: true })).toThrow(/Choose one of/);
  expect(() => parseCaptureRequest({ selector: ".card", clip: { x: 0, y: 0, width: 10, height: 10 } })).toThrow(/Choose one of/);
});

test("padding without a selector is rejected rather than ignored", () => {
  expect(() => parseCaptureRequest({ padding: 16 })).toThrow(/padding only applies alongside selector/);
  expect(parseCaptureRequest({ selector: ".card", padding: 16 })).toEqual({ kind: "element", selector: ".card", padding: 16 });
  expect(parseCaptureRequest({ selector: " .card " })).toEqual({ kind: "element", selector: ".card", padding: 0 });
});

test("a clip with a zero or missing edge is refused at parse time", () => {
  expect(() => parseCaptureRequest({ clip: { x: 0, y: 0, width: 0, height: 10 } })).toThrow(/clip.width/);
  expect(() => parseCaptureRequest({ clip: { x: 0, y: 0, width: 10 } })).toThrow(/clip.height/);
  expect(() => parseCaptureRequest({ clip: { x: -1, y: 0, width: 10, height: 10 } })).toThrow(/clip.x/);
  expect(() => parseCaptureRequest({ clip: [1, 2] })).toThrow(/clip must be an object/);
});

test("an element clip is the element's own rect when nothing constrains it", () => {
  const outcome = clipForRect({ x: 100, y: 200, width: 300, height: 150 }, 0, { width: 1440, height: 5_000 });
  expect(outcome).toEqual({ clip: { x: 100, y: 200, width: 300, height: 150 }, clamped: false, truncated: false });
});

test("padding stops at the document edge instead of capturing transparent pixels", () => {
  // A clip running off the page returns empty pixels, which reads as a rendering
  // bug in the page under review rather than a clipping mistake.
  const outcome = clipForRect({ x: 10, y: 0, width: 100, height: 50 }, 20, { width: 120, height: 400 });
  expect(outcome.clip).toEqual({ x: 0, y: 0, width: 120, height: 70 });
  expect(outcome.clamped).toBe(true);
});

test("an area past Chrome's capture ceiling is reported as cut off, never rescaled", () => {
  const outcome = clipForRect({ x: 0, y: 0, width: 1_000, height: MAX_CAPTURE_EDGE + 500 }, 0, { width: 1_000, height: MAX_CAPTURE_EDGE + 500 });
  expect(outcome.clip.height).toBe(MAX_CAPTURE_EDGE);
  expect(outcome.truncated).toBe(true);
});

test("the element is measured in document coordinates, not viewport coordinates", () => {
  // Page.captureScreenshot clips against the document origin, so a scrolled page
  // would capture the wrong band without the scroll offset folded in.
  const expression = measureElementExpression("#hero");
  expect(expression).toContain("rect.x + window.scrollX");
  expect(expression).toContain("rect.y + window.scrollY");
  expect(expression).toContain('querySelector("#hero")');
});
