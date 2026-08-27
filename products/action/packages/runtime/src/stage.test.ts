import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, test } from "node:test";
import type { StageWindowInfo } from "@action/protocol";
import {
  describeStageScene,
  evaluateStageScene,
  normalizeHexColor,
  parseStageWorld,
  StageDirector,
  StageSceneError,
} from "./stage.js";

function win(
  partial: Partial<StageWindowInfo> & Pick<StageWindowInfo, "owner" | "pid">,
): StageWindowInfo {
  return {
    title: "",
    layer: 0,
    bounds: { x: 0, y: 0, width: 800, height: 600 },
    ...partial,
  };
}

describe("parseStageWorld", () => {
  test("defaults to a normal-level drape and no subjects", () => {
    assert.deepEqual(parseStageWorld({}), {
      mode: "drape",
      color: "0e0d0a",
      level: "normal",
      subjects: [],
    });
  });

  test("accepts a declarative world", () => {
    assert.deepEqual(
      parseStageWorld({
        mode: "drape",
        color: "#1e1e2e",
        subjects: [
          { bundleId: "to.talkie.agent.dev", title: "Settings" },
          { bundleId: "com.googlecode.iterm2" },
        ],
      }),
      {
        mode: "drape",
        color: "1e1e2e",
        level: "normal",
        subjects: [
          { bundleId: "to.talkie.agent.dev", title: "Settings" },
          { bundleId: "com.googlecode.iterm2" },
        ],
      },
    );
  });

  test("space mode keeps the sheet on the current Space", () => {
    assert.equal(parseStageWorld({ mode: "space" }).mode, "space");
  });

  test("space mode reports the level it actually launches with", () => {
    assert.equal(parseStageWorld({ mode: "space", level: "desktop" }).level, "normal");
  });

  test("carries an optional lifetime and rejects a nonsense one", () => {
    assert.equal(parseStageWorld({ seconds: 900 }).seconds, 900);
    assert.equal(parseStageWorld({}).seconds, undefined);
    assert.throws(() => parseStageWorld({ seconds: 0 }), /seconds must be a positive number/);
    assert.throws(() => parseStageWorld({ seconds: "soon" }), /seconds must be a positive number/);
  });

  test("rejects a wallpaper-shaped color", () => {
    assert.throws(() => normalizeHexColor("not-a-color"), /Invalid stage color/);
  });
});

describe("evaluateStageScene", () => {
  const drape = win({
    owner: "Action",
    title: "Action Drape",
    bundleId: "dev.action.Action",
    pid: 64405,
    bounds: { x: 0, y: 0, width: 1440, height: 900 },
  });
  const calculator = win({
    owner: "Calculator",
    title: "Calculator",
    bundleId: "com.apple.calculator",
    pid: 60850,
    bounds: { x: 220, y: 150, width: 230, height: 461 },
  });
  const ghostty = win({
    owner: "Ghostty",
    title: "herdr",
    bundleId: "com.mitchellh.ghostty",
    pid: 99,
    bounds: { x: 100, y: 80, width: 900, height: 700 },
  });

  test("accepts listed subjects on the sheet", () => {
    const scene = evaluateStageScene({
      windows: [calculator, drape],
      subjects: [{ bundleId: "com.apple.calculator" }],
      drapePid: 64405,
    });
    assert.equal(scene.ok, true);
    assert.deepEqual(scene.tops.map((window) => window.bundleId), ["com.apple.calculator"]);
    assert.equal(scene.intruders.length, 0);
  });

  test("refuses a driver window sitting in the scene", () => {
    const scene = evaluateStageScene({
      windows: [ghostty, calculator, drape],
      subjects: [{ bundleId: "com.apple.calculator" }],
      drapePid: 64405,
    });
    assert.equal(scene.ok, false);
    assert.equal(scene.intruders[0]?.bundleId, "com.mitchellh.ghostty");
    assert.equal(scene.intruders[0]?.reason, "above-subject");
    assert.match(describeStageScene(scene), /herdr sits above a subject/);
  });

  test("refuses a non-subject that occupies the capture rect", () => {
    const scene = evaluateStageScene({
      windows: [ghostty, drape],
      subjects: [],
      drapePid: 64405,
    });
    assert.equal(scene.ok, false);
    assert.equal(scene.intruders[0]?.reason, "in-rect");
  });

  test("refuses a listed subject that is still under the sheet", () => {
    const scene = evaluateStageScene({
      windows: [drape, calculator],
      subjects: [{ bundleId: "com.apple.calculator" }],
      drapePid: 64405,
    });
    assert.equal(scene.ok, false);
    assert.ok(scene.intruders.some((window) => window.reason === "subject-buried"));
  });

  test("ignores a window buried under the sheet", () => {
    const scene = evaluateStageScene({
      windows: [calculator, drape, ghostty],
      subjects: [{ bundleId: "com.apple.calculator" }],
      drapePid: 64405,
    });
    assert.equal(scene.ok, true);
    assert.equal(scene.intruders.length, 0);
  });
});

describe("StageDirector.set scene proof", () => {
  test("throws when the world is still buried after raise", async () => {
    const root = await mkdtemp(join(tmpdir(), "action-stage-"));
    const host = async (args: string[]) => {
      if (args[0] === "drape") {
        return { stdout: JSON.stringify({ status: "drape-running", detail: "64405" }) };
      }
      if (args[0] === "raise-window") {
        return { stdout: JSON.stringify({ status: "raised", detail: "com.apple.calculator: Calculator" }) };
      }
      if (args[0] === "window-order") {
        return {
          stdout: JSON.stringify({
            status: "window-order",
            windows: [
              {
                pid: 99,
                bundleId: "com.mitchellh.ghostty",
                owner: "Ghostty",
                title: "herdr",
                layer: 0,
                bounds: { x: 0, y: 0, width: 800, height: 600 },
              },
              {
                pid: 64405,
                bundleId: "dev.action.Action",
                owner: "Action",
                title: "Action Drape",
                layer: 0,
                bounds: { x: 0, y: 0, width: 1440, height: 900 },
              },
            ],
          }),
        };
      }
      throw new Error(`unexpected host ${args.join(" ")}`);
    };

    const director = new StageDirector("/unused", root, host);
    await assert.rejects(
      () => director.set({ subjects: [{ bundleId: "com.apple.calculator" }] }),
      (error: unknown) => {
        assert.ok(error instanceof StageSceneError);
        assert.match(error.message, /buried/);
        assert.equal(error.stage.scene?.ok, false);
        assert.equal(error.stage.scene?.intruders[0]?.bundleId, "com.mitchellh.ghostty");
        return true;
      },
    );
    await rm(root, { recursive: true, force: true });
  });
});
