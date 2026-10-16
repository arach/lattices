import assert from "node:assert/strict";
import { describe, test } from "node:test";

import type { DriveLease } from "@action/protocol";

import {
  DriveCursorPresenter,
  parseDriveCursorStyle,
  type AgentCursorCue,
} from "./drive-cursor-presenter.js";

function lease(leaseId: string): DriveLease {
  return {
    leaseId,
    agent: "Fable",
    task: "Drive a take",
    mode: "background",
    status: "driving",
    sessionId: "session-1",
    startedAt: "2026-08-17T12:00:00.000Z",
    lastActAt: "2026-08-17T12:00:01.000Z",
    stopFile: "/tmp/action-drive.stop",
  };
}

describe("drive cursor presenter", () => {
  test("never starts or updates an agent cursor for system cursor leases", async () => {
    const calls: string[] = [];
    const presenter = new DriveCursorPresenter({
      start: async () => { calls.push("start"); },
      update: async () => { calls.push("update"); },
      stop: async () => { calls.push("stop"); },
      isLive: async () => true,
    });
    const currentLease = lease("system-lease");

    presenter.recordStyle(currentLease.leaseId, "system");
    await presenter.ensure(currentLease);
    await presenter.renew(currentLease);
    await presenter.update({ leaseId: currentLease.leaseId, label: "click" });

    assert.deepEqual(calls, []);
    assert.equal(presenter.isPresenting(currentLease.leaseId), false);
  });

  test("keeps synthetic presentation as the default and routes its lifecycle", async () => {
    const calls: Array<{ operation: string; cue?: AgentCursorCue }> = [];
    const presenter = new DriveCursorPresenter({
      start: async () => { calls.push({ operation: "start" }); },
      update: async (cue) => { calls.push({ operation: "update", cue }); },
      stop: async () => { calls.push({ operation: "stop" }); },
      isLive: async () => true,
    });
    const currentLease = lease("synthetic-lease");

    await presenter.ensure(currentLease);
    await presenter.ensure(currentLease);
    await presenter.update({ leaseId: currentLease.leaseId, label: "Open memos" });
    await presenter.release(currentLease.leaseId);

    assert.deepEqual(calls.map((call) => call.operation), ["start", "update", "update", "stop"]);
    assert.equal(presenter.isPresenting(currentLease.leaseId), false);
  });

  test("parses only the explicit system style as hidden presentation", () => {
    assert.equal(parseDriveCursorStyle("system"), "system");
    assert.equal(parseDriveCursorStyle("synthetic"), "synthetic");
    assert.equal(parseDriveCursorStyle(undefined), "synthetic");
    assert.equal(parseDriveCursorStyle("hidden"), "synthetic");
  });
  test("silent-cue leases keep the cursor but skip act cues and countdown warnings", async () => {
    const calls: string[] = [];
    const presenter = new DriveCursorPresenter({
      start: async () => { calls.push("start"); },
      update: async () => { calls.push("update"); },
      stop: async () => { calls.push("stop"); },
      isLive: async () => true,
    });
    const currentLease = lease("quiet-lease");
    presenter.recordCues(currentLease.leaseId, false);

    assert.equal(presenter.presentsCues(currentLease.leaseId), false);
    // Cue policy never gates presentation itself — the cursor still follows.
    await presenter.ensure(currentLease);
    await presenter.update({ leaseId: currentLease.leaseId, label: "click" });
    assert.deepEqual(calls, ["start", "update"]);
  });

  test("restarts an overlay that quit while the agent was away, where the cursor last was", async () => {
    const calls: Array<{ operation: string; point?: { x: number; y: number } }> = [];
    let live = true;
    const presenter = new DriveCursorPresenter({
      start: async ({ point }) => { calls.push({ operation: "start", point }); },
      update: async () => { calls.push({ operation: "update" }); },
      stop: async () => { calls.push({ operation: "stop" }); },
      isLive: async () => live,
    });
    const currentLease = lease("paused-lease");

    await presenter.ensure(currentLease);
    await presenter.update({ leaseId: currentLease.leaseId, point: { x: 640, y: 320 } });
    // The overlay idles out and deletes its state while the agent deploys.
    live = false;
    await presenter.ensure(currentLease);
    live = true;
    await presenter.update({ leaseId: currentLease.leaseId, point: { x: 900, y: 500 } });

    assert.deepEqual(calls, [
      { operation: "start", point: undefined },
      { operation: "update" },
      { operation: "start", point: { x: 640, y: 320 } },
      { operation: "update" },
    ]);
    assert.equal(presenter.isPresenting(currentLease.leaseId), true);

    // A heartbeat from an observe call revives it the same way.
    live = false;
    await presenter.renew(currentLease);
    assert.deepEqual(calls.at(-1), { operation: "start", point: { x: 900, y: 500 } });
  });

  test("cues default to on for leases without a recorded preference", () => {
    const presenter = new DriveCursorPresenter({
      start: async () => {},
      update: async () => {},
      stop: async () => {},
      isLive: async () => true,
    });
    assert.equal(presenter.presentsCues("unknown-lease"), true);
  });
});
