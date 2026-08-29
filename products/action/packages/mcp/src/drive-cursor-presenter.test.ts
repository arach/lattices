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
});
