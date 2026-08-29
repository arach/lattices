import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { centeredSafeBounds } from "./macos.js";

describe("centeredSafeBounds", () => {
  test("centers a website window with deterministic edge clearance", () => {
    assert.deepEqual(
      centeredSafeBounds(
        { x: 0, y: 0, width: 1200, height: 760 },
        { x: 0, y: 25, width: 1728, height: 1085 },
        72,
      ),
      { x: 264, y: 188, width: 1200, height: 760 },
    );
  });

  test("scales oversized windows proportionally into the safe area", () => {
    assert.deepEqual(
      centeredSafeBounds(
        { x: 0, y: 0, width: 1600, height: 1000 },
        { x: 0, y: 0, width: 1440, height: 900 },
        72,
      ),
      { x: 115, y: 72, width: 1210, height: 756 },
    );
  });

  test("preserves the selected display origin", () => {
    assert.deepEqual(
      centeredSafeBounds(
        { x: 2000, y: 100, width: 1200, height: 760 },
        { x: 1728, y: -200, width: 1920, height: 1080 },
        72,
      ),
      { x: 2088, y: -40, width: 1200, height: 760 },
    );
  });

  test("rejects invalid requested sizes", () => {
    assert.throws(
      () => centeredSafeBounds(
        { x: 0, y: 0, width: 0, height: 760 },
        { x: 0, y: 0, width: 1728, height: 1080 },
        72,
      ),
      /Centered viewport size must be greater than zero/,
    );
  });

  test("keeps extreme safe-area requests usable", () => {
    assert.deepEqual(
      centeredSafeBounds(
        { x: 0, y: 0, width: 1_000_000, height: 1 },
        { x: 0, y: 0, width: 1_440, height: 900 },
        10_000,
      ),
      { x: 720, y: 450, width: 1, height: 1 },
    );
  });
});
