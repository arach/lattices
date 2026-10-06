import assert from "node:assert/strict";
import { test } from "node:test";
import { MacOSCommandEngine } from "../macos.js";
import { executeInteractionAction, type InteractionExecutionContext } from "./index.js";

function recorder(bundleId?: string) {
  const calls: string[][] = [];
  const context: InteractionExecutionContext = {
    runHost: async (...args) => { calls.push(args); return { stdout: "" }; },
    resolveBundleId: () => bundleId,
    resolveCalculatorButton: () => "7",
  };
  return { calls, context };
}

for (const bundleId of [undefined, "com.google.Chrome", "com.apple.calculator"]) {
  test(`resolve then click retains coordinates (${bundleId})`, async () => {
    const point = { x: 0, y: 240 };
    const target = await new MacOSCommandEngine().resolveTarget({ point });
    assert.deepEqual(target.point, point);
    assert.equal(target.mode, "coordinate");
    const { calls, context } = recorder(bundleId);
    await executeInteractionAction({ id: "click", kind: "click", description: "click" }, target, context);
    assert.deepEqual(calls, [["click-point", "--x", "0", "--y", "240"]]);
  });
}

test("missing click geometry never falls back to Calculator on another surface", async () => {
  const { calls, context } = recorder();
  await assert.rejects(executeInteractionAction({ id: "click", kind: "click", description: "click" }, undefined, context), /Click requires/);
  assert.deepEqual(calls, []);
});

test("explicit action point wins over resolved point and semantic label", async () => {
  const target = await new MacOSCommandEngine().resolveTarget({ point: { x: 10, y: 20 } });
  const { calls, context } = recorder("com.google.Chrome");
  await executeInteractionAction({ id: "click", kind: "click", description: "click", target: { point: { x: 30, y: 40 } } }, target, context);
  assert.deepEqual(calls, [["click-point", "--x", "30", "--y", "40"]]);
});

test("semantic AX click remains preferred for native labels", async () => {
  const { calls, context } = recorder("com.apple.TextEdit");
  await executeInteractionAction({ id: "click", kind: "click", description: "click", target: { text: "Save" } }, undefined, context);
  assert.equal(calls[0]?.[0], "press-accessibility-element");
});

test("coordinate target without geometry cannot use Calculator fallback", async () => {
  const { calls, context } = recorder("com.apple.calculator");
  await assert.rejects(executeInteractionAction(
    { id: "click", kind: "click", description: "click" },
    { id: "target", mode: "coordinate", confidence: 1, label: "Resolved Target" },
    context,
  ), /Click requires/);
  assert.deepEqual(calls, []);
});

test("resolved point supports press-and-hold", async () => {
  const target = await new MacOSCommandEngine().resolveTarget({ point: { x: 10, y: 20 } });
  const { calls, context } = recorder();
  await executeInteractionAction({ id: "click", kind: "click", description: "hold", input: { holdMs: 500 } }, target, context);
  assert.deepEqual(calls, [["click-point", "--x", "10", "--y", "20", "--hold-ms", "500"]]);
});
