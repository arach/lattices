import assert from "node:assert/strict";
import { describe, test } from "node:test";

import type { ResolvedTarget, RuntimeAction } from "@action/protocol";

import {
  blinkRouteFor,
  executeInteractionAction,
  type AgentLayerRouting,
  type InteractionExecutionContext,
} from "./index.js";

const layer: AgentLayerRouting = {
  bundleId: "com.apple.calculator",
  bounds: { x: 5000, y: 0, width: 1280, height: 800 },
};

function harness(agentLayer?: AgentLayerRouting, surfaceBundleId?: string) {
  const calls: string[][] = [];
  const context: InteractionExecutionContext = {
    runHost: async (command, ...args) => {
      calls.push([command, ...args]);
      return { stdout: "{}" };
    },
    resolveCalculatorButton: () => "1",
    resolveBundleId: () => surfaceBundleId,
    ...(agentLayer ? { agentLayer } : {}),
  };
  return { calls, context };
}

function act(kind: RuntimeAction["kind"], input?: Record<string, unknown>, extra?: Partial<RuntimeAction>): RuntimeAction {
  return { id: "a1", kind, description: kind, ...(input ? { input } : {}), ...extra } as RuntimeAction;
}

describe("agent layer routing", () => {
  test("without a layer, acts take their ordinary paths", async () => {
    const { calls, context } = harness();
    await executeInteractionAction(act("click", { point: { x: 5100, y: 40 } }), undefined, context);
    await executeInteractionAction(act("type", { text: "hi" }), undefined, context);
    await executeInteractionAction(act("press-key", { key: "return" }), undefined, context);
    assert.deepEqual(calls.map((call) => call[0]), ["click-point", "type-text", "press-key"]);
  });

  test("a coordinate click on the layer blinks, with its hold", async () => {
    const { calls, context } = harness(layer);
    await executeInteractionAction(act("click", { point: { x: 5100, y: 40 }, holdMs: 300 }), undefined, context);
    assert.deepEqual(calls, [["blink-click", "--x", "5100", "--y", "40", "--hold-ms", "300"]]);
  });

  test("a click off the layer stays click-point", async () => {
    const { calls, context } = harness(layer);
    const click = act("click", { point: { x: 100, y: 40 } });
    assert.equal(blinkRouteFor(click, undefined, context), undefined);
    await executeInteractionAction(click, undefined, context);
    assert.equal(calls[0]?.[0], "click-point");
  });

  test("an accessibility press stays on the AX path", async () => {
    const { calls, context } = harness(layer, "com.apple.calculator");
    const target: ResolvedTarget = {
      id: "7",
      mode: "semantic",
      confidence: 1,
      label: "7",
      bounds: { x: 5100, y: 10, width: 20, height: 20 },
    };
    const click = act("click");
    assert.equal(blinkRouteFor(click, target, context), undefined);
    await executeInteractionAction(click, target, context);
    assert.equal(calls[0]?.[0], "press-accessibility-element");
  });

  test("type without a label blinks into the layer's app", async () => {
    const { calls, context } = harness(layer);
    await executeInteractionAction(act("type", { text: "12+3", delayMs: 20 }), undefined, context);
    assert.deepEqual(calls, [[
      "blink-type", "--text", "12+3", "--bundle-id", "com.apple.calculator", "--delay-ms", "20",
    ]]);
  });

  test("type with a labelled AX target stays set-accessibility-value", async () => {
    const { calls, context } = harness(layer, "com.apple.TextEdit");
    await executeInteractionAction(act("type", { text: "x", label: "Body" }), undefined, context);
    assert.equal(calls[0]?.[0], "set-accessibility-value");
  });

  test("press-key blinks and an explicit pid beats the layer subject", async () => {
    const { calls, context } = harness({ pid: 42, bounds: layer.bounds });
    await executeInteractionAction(act("press-key", { keys: ["cmd", "a"] }), undefined, context);
    await executeInteractionAction(act("press-key", { key: "return", pid: 77 }), undefined, context);
    assert.deepEqual(calls, [
      ["blink-key", "--key", "a", "--modifiers", "cmd", "--pid", "42"],
      ["blink-key", "--key", "return", "--pid", "77"],
    ]);
  });

  test("press-key reads a chord string the way an agent writes it", async () => {
    const { calls, context } = harness({ pid: 42, bounds: layer.bounds });
    await executeInteractionAction(act("press-key", { key: "cmd+l" }), undefined, context);
    assert.deepEqual(calls, [["blink-key", "--key", "l", "--modifiers", "cmd", "--pid", "42"]]);
  });

  test("a layer with no known app leaves keyboard acts alone", async () => {
    const { calls, context } = harness({ bounds: layer.bounds });
    assert.equal(blinkRouteFor(act("type", { text: "x" }), undefined, context), undefined);
    await executeInteractionAction(act("type", { text: "x" }), undefined, context);
    assert.equal(calls[0]?.[0], "type-text");
  });

  test("a drag held on the layer blinks; one leaving it, or carrying a file, doesn't", async () => {
    const { calls, context } = harness(layer);
    const onLayer = act("drag", { from: { x: 5100, y: 10 }, to: { x: 5200, y: 10 } });
    assert.equal(blinkRouteFor(act("drag", { from: { x: 5100, y: 1 }, to: { x: 100, y: 1 } }), undefined, context), undefined);
    assert.equal(blinkRouteFor(act("drag", { from: { x: 5100, y: 1 }, to: { x: 5200, y: 1 }, filePath: "/tmp/a" }), undefined, context), undefined);
    await executeInteractionAction(onLayer, undefined, context);
    assert.deepEqual(calls, [["blink-drag", "--from-x", "5100", "--from-y", "10", "--to-x", "5200", "--to-y", "10"]]);
  });

  test("a scroll on the layer blinks", async () => {
    const { calls, context } = harness(layer);
    assert.equal(blinkRouteFor(act("scroll", { point: { x: 100, y: 1 }, deltaY: 3 }), undefined, context), undefined);
    await executeInteractionAction(act("scroll", { point: { x: 5100, y: 1 }, deltaY: -400 }), undefined, context);
    assert.deepEqual(calls, [["blink-scroll", "--x", "5100", "--y", "1", "--delta-x", "0", "--delta-y", "-400"]]);
  });
});
