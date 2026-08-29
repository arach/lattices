import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, test } from "node:test";

import {
  DEFAULT_CLICK_FEEDBACK,
  activePointerEventLogMarkerPath,
  POINTER_EVENT_LOG_ENV,
  parsePointerEventLog,
  pointerEventLogPath,
  publishPointerEventLog,
  readPointerEventLog,
  startPointerEventLog,
  stopPointerEventLog,
} from "./pointer-events.js";

function recordingHostStub() {
  const calls: string[][] = [];
  return {
    calls,
    runHost: async (command: string, ...args: string[]) => {
      calls.push([command, ...args]);
      return {};
    },
  };
}

/** A host path that cannot spawn, so a test never leaves a real overlay process behind. */
const unspawnableHost = join(tmpdir(), "action-tests-no-such-host");

afterEach(async () => {
  await publishPointerEventLog(undefined);
});

describe("pointer event log lifecycle", () => {
  test("names the artifact alongside the recording it belongs to", () => {
    assert.equal(
      pointerEventLogPath("/artifacts/sessions/demo/recording_1.mov"),
      "/artifacts/sessions/demo/recording_1.mov.pointer-events.jsonl",
    );
  });

  test("click feedback is off unless it is asked for, and the log is created either way", async () => {
    const directory = await mkdtemp(join(tmpdir(), "action-pointer-"));
    const host = recordingHostStub();

    const handle = await startPointerEventLog({
      runHost: host.runHost,
      nativeHostPath: unspawnableHost,
      outputPath: join(directory, "capture.mov"),
      recordingId: "recording_1",
      sessionId: "session_1",
    });

    assert.equal(handle.feedbackEnabled, false);
    assert.equal(handle.recordingId, "recording_1");
    assert.equal(handle.path, join(directory, "capture.mov.pointer-events.jsonl"));

    const [init] = host.calls;
    assert.equal(init[0], "pointer-event-log-init");
    // The header is written natively so its clock reference matches the click processes'.
    assert.ok(init.includes("--recording-id"));
    assert.equal(init[init.indexOf("--click-feedback") + 1], "false");
    assert.equal(
      init[init.indexOf("--click-feedback-duration-ms") + 1],
      String(DEFAULT_CLICK_FEEDBACK.durationMs),
    );
    assert.equal(init[init.indexOf("--session-id") + 1], "session_1");

    await rm(directory, { recursive: true, force: true });
  });

  test("passes an opted-in feedback shape through to the native header", async () => {
    const directory = await mkdtemp(join(tmpdir(), "action-pointer-"));
    const host = recordingHostStub();

    // Spawning the overlay fails against a nonexistent host path; the log must still be usable.
    await assert.rejects(
      startPointerEventLog({
        runHost: host.runHost,
        nativeHostPath: unspawnableHost,
        outputPath: join(directory, "capture.mov"),
        recordingId: "recording_2",
        clickFeedback: { enabled: true, style: "pulse", durationMs: 500, radius: 20 },
      }),
    );

    const [init] = host.calls;
    assert.equal(init[init.indexOf("--click-feedback") + 1], "true");
    assert.equal(init[init.indexOf("--click-feedback-duration-ms") + 1], "500");
    assert.equal(init[init.indexOf("--click-feedback-radius") + 1], "20");
    // No sessionId was given, so no flag should be invented for it.
    assert.equal(init.includes("--session-id"), false);

    await rm(directory, { recursive: true, force: true });
  });

  test("publishes and withdraws the log for native host subprocesses", async () => {
    assert.equal(process.env[POINTER_EVENT_LOG_ENV], undefined);

    await publishPointerEventLog("/tmp/demo.pointer-events.jsonl");
    assert.equal(process.env[POINTER_EVENT_LOG_ENV], "/tmp/demo.pointer-events.jsonl");
    // The marker is what reaches a host started through `open -n`, where the environment does not
    // carry across, so it must agree with the variable.
    const marker = JSON.parse(await readFile(activePointerEventLogMarkerPath(), "utf8"));
    assert.equal(marker.path, "/tmp/demo.pointer-events.jsonl");

    await publishPointerEventLog(undefined);
    assert.equal(process.env[POINTER_EVENT_LOG_ENV], undefined);
    await assert.rejects(readFile(activePointerEventLogMarkerPath(), "utf8"));
  });

  test("stopping a log without feedback does not write a stop marker", async () => {
    const directory = await mkdtemp(join(tmpdir(), "action-pointer-"));
    const stopFile = join(directory, "capture.mov.pointer-events.jsonl.stop");

    await stopPointerEventLog({
      path: join(directory, "capture.mov.pointer-events.jsonl"),
      stopFile,
      recordingId: "recording_3",
      feedbackEnabled: false,
    });

    await assert.rejects(readFile(stopFile, "utf8"));
    await rm(directory, { recursive: true, force: true });
  });

  test("stopping a feedback log signals the overlay to exit", async () => {
    const directory = await mkdtemp(join(tmpdir(), "action-pointer-"));
    const stopFile = join(directory, "capture.mov.pointer-events.jsonl.stop");

    await stopPointerEventLog({
      path: join(directory, "capture.mov.pointer-events.jsonl"),
      stopFile,
      recordingId: "recording_4",
      feedbackEnabled: true,
    });

    assert.equal(await readFile(stopFile, "utf8"), "stop\n");
    await rm(directory, { recursive: true, force: true });
  });
});

describe("pointer event log parsing", () => {
  const header = JSON.stringify({
    kind: "header",
    version: 1,
    recordingId: "recording_1",
    sessionId: "session_1",
    startedAt: "2026-08-16T10:00:00.000Z",
    startedAtUptime: 1000,
    feedback: { enabled: true, style: "pulse", durationMs: 320, radius: 34 },
  });
  const down = JSON.stringify({
    kind: "pointer",
    recordingId: "recording_1",
    correlationId: "pe_abc",
    gesture: "click",
    phase: "down",
    button: "left",
    x: 400,
    y: 300,
    recordingElapsedMs: 1500,
    at: "2026-08-16T10:00:01.500Z",
    uptime: 1001.5,
    source: "click-point",
  });
  const up = JSON.stringify({
    kind: "pointer",
    recordingId: "recording_1",
    correlationId: "pe_abc",
    gesture: "click",
    phase: "up",
    button: "left",
    x: 400,
    y: 300,
    recordingElapsedMs: 1531,
    at: "2026-08-16T10:00:01.531Z",
    uptime: 1001.531,
    holdMs: 31,
    source: "click-point",
  });

  test("separates the header from the events", () => {
    const parsed = parsePointerEventLog(`${header}\n${down}\n${up}\n`);
    assert.equal(parsed.header?.recordingId, "recording_1");
    assert.equal(parsed.header?.feedback.enabled, true);
    assert.equal(parsed.events.length, 2);
    assert.equal(parsed.events[0].phase, "down");
    assert.equal(parsed.events[1].holdMs, 31);
    // The pair is rejoinable, which is how a viewer maps a pulse back to its metadata.
    assert.equal(parsed.events[0].correlationId, parsed.events[1].correlationId);
  });

  test("relative time is measured against the header, not the wall clock", () => {
    const parsed = parsePointerEventLog(`${header}\n${down}\n`);
    const event = parsed.events[0];
    assert.equal(event.uptime - (parsed.header?.startedAtUptime ?? 0), 1.5);
    assert.equal(event.recordingElapsedMs, 1500);
    // The wall-clock stamp agrees with the monotonic one, so either can index a video frame.
    assert.equal(
      Date.parse(event.at) - Date.parse(parsed.header?.startedAt ?? ""),
      event.recordingElapsedMs,
    );
  });

  test("ignores a partial trailing line from a live writer", () => {
    const parsed = parsePointerEventLog(`${header}\n${down}\n{"kind":"pointer","recordin`);
    assert.equal(parsed.events.length, 1);
  });

  test("reading a missing log is empty rather than an error", async () => {
    const parsed = await readPointerEventLog(join(tmpdir(), "action-no-such-log.jsonl"));
    assert.deepEqual(parsed, { events: [] });
  });

  test("reads a log back off disk", async () => {
    const directory = await mkdtemp(join(tmpdir(), "action-pointer-"));
    const path = join(directory, "capture.mov.pointer-events.jsonl");
    await writeFile(path, `${header}\n${down}\n${up}\n`);

    const parsed = await readPointerEventLog(path);
    assert.equal(parsed.events.length, 2);
    assert.equal(parsed.header?.startedAtUptime, 1000);

    await rm(directory, { recursive: true, force: true });
  });
});
