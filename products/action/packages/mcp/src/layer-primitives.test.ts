import assert from "node:assert/strict";
import { describe, test } from "node:test";

import { primitiveAction, readPoint, toGlobal, type LayerView } from "./layer-primitives.js";

const bounds = { x: 5000, y: 100, width: 1280, height: 800 };
// A 2× snapshot of a window at 40,30 on the layer, 600×400 points.
const view: LayerView = { crop: { x: 40, y: 30, width: 600, height: 400 }, width: 1200, height: 800 };

describe("layer primitives", () => {
  test("a snapshot pixel lands where the agent saw it", () => {
    assert.deepEqual(toGlobal({ x: 200, y: 100 }, "snapshot", bounds, view), { x: 5140, y: 180 });
  });

  test("layer space is points on the layer display", () => {
    assert.deepEqual(toGlobal({ x: 10, y: 20 }, "layer", bounds, undefined), { x: 5010, y: 120 });
  });

  test("snapshot space needs a snapshot, and a point inside it", () => {
    assert.throws(() => toGlobal({ x: 1, y: 1 }, "snapshot", bounds, undefined), /action\.layer\.snapshot first/);
    assert.throws(() => toGlobal({ x: 1300, y: 1 }, "snapshot", bounds, view), /outside the last snapshot/);
  });

  test("points read as objects or pairs", () => {
    assert.deepEqual(readPoint([3, 4]), { x: 3, y: 4 });
    assert.deepEqual(readPoint({ x: 3, y: 4 }), { x: 3, y: 4 });
    assert.equal(readPoint([3]), undefined);
    assert.equal(readPoint({ x: "3", y: 4 }), undefined);
  });

  test("each primitive becomes the runtime act it runs as", () => {
    const context = { bounds, view, subjectBundleId: "com.apple.Safari" };
    const click = primitiveAction("click", { x: 200, y: 100 }, context);
    assert.equal(click.kind, "click");
    assert.deepEqual(click.input?.point, { x: 5140, y: 180 });

    const labelled = primitiveAction("click", { label: "Sign In" }, context);
    assert.deepEqual(labelled.input, { bundleId: "com.apple.Safari", label: "Sign In" });

    const drag = primitiveAction("drag", { from: [0, 0], to: { x: 1200, y: 800 } }, context);
    assert.deepEqual(drag.input, { from: { x: 5040, y: 130 }, to: { x: 5640, y: 530 } });

    const scroll = primitiveAction("scroll", { x: 10, y: 10, dy: -400, space: "layer" }, context);
    assert.deepEqual(scroll.input, { point: { x: 5010, y: 110 }, deltaX: 0, deltaY: -400 });

    assert.equal(primitiveAction("press", { key: "cmd+l" }, context).kind, "press-key");
    assert.equal(primitiveAction("type", { text: "hi\n" }, context).input?.text, "hi\n");
  });

  test("bad input says what to pass", () => {
    const context = { bounds, view };
    assert.throws(() => primitiveAction("scroll", { x: 1, y: 1 }, context), /dy or dx/);
    assert.throws(() => primitiveAction("drag", { from: [1, 1] }, context), /to: \{ x, y \}/);
    assert.throws(() => primitiveAction("click", { label: "OK" }, context), /bundleId/);
    assert.throws(() => primitiveAction("click", { x: 1, y: 1, space: "screen" }, context), /space must be/);
  });
});
