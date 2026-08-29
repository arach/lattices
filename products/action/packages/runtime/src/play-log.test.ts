import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

import {
  PlayLogger,
  defaultPlayHudEvents,
  isPlayHudEventVisible,
  normalizePlayHudFilter,
  playLogDirectory,
} from "./play-log.js";

describe("play logger", () => {
  test("writes start/ok events to current.log", async () => {
    const log = new PlayLogger(`test-${Date.now()}`);
    await log.playStart(2);
    await log.stepStart(0, 2, "aim", "left");
    await log.stepOk(0, 2, "aim", 12, "left");
    await log.playOk();
    const text = await readFile(join(playLogDirectory(), "current.log"), "utf8");
    assert.match(text, /2 steps/);
    assert.match(text, /1\/2 aim/);
    assert.match(text, /done/);
  });

  test("HUD filter hides step-ok by default and can hide the play log entirely", () => {
    const defaults = normalizePlayHudFilter(undefined);
    assert.equal(defaults.show, true);
    assert.deepEqual(defaults.events, [...defaultPlayHudEvents]);
    assert.equal(isPlayHudEventVisible("step-start", defaults), true);
    assert.equal(isPlayHudEventVisible("step-ok", defaults), false);
    assert.equal(isPlayHudEventVisible("step-fail", defaults), true);
    assert.equal(isPlayHudEventVisible("step-start", { show: false, events: defaultPlayHudEvents }), false);
    assert.equal(
      isPlayHudEventVisible("step-ok", { show: true, events: ["step-ok"] }),
      true,
    );
  });
});
