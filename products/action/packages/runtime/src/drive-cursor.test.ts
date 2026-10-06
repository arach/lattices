import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, test } from "node:test";

import {
  AGENT_CURSOR_IDLE_EXPIRY_MS,
  AGENT_CURSOR_LIVENESS_MARGIN_MS,
  POINTER_FOCUS_COUNTDOWN_SECONDS,
  POINTER_FOCUS_COUNTDOWN_STEP_MS,
  POINTER_FOCUS_REARM_MS,
  agentCursorExpiration,
  agentCursorStateIsLive,
  cursorTravelMs,
  notePointerFocusAct,
  pointerFocusWarningDue,
  pointFromBounds,
  revalidatePointerFocusLease,
  requiresPointerFocusWarning,
  runPointerFocusCountdown,
} from "./drive-cursor.js";

describe("agent cursor lifecycle", () => {
  test("renews its deadline for the drive idle window", () => {
    const updatedAt = "2026-08-12T12:00:00.000Z";
    assert.equal(
      Date.parse(agentCursorExpiration(updatedAt)) - Date.parse(updatedAt),
      AGENT_CURSOR_IDLE_EXPIRY_MS,
    );
  });

  test("targets the center of resolved bounds", () => {
    assert.deepEqual(
      pointFromBounds({ x: 10, y: 20, width: 80, height: 40 }),
      { x: 50, y: 40 },
    );
  });

  test("warns only for attention-taking execution paths", () => {
    const action = {
      id: "action-1",
      kind: "click" as const,
      description: "Press Save",
    };
    assert.equal(requiresPointerFocusWarning({
      action,
      axTier: "semantic",
      channel: "native",
    }), false);
    assert.equal(requiresPointerFocusWarning({
      action,
      axTier: "attention",
      channel: "hid",
    }), true);
    assert.equal(requiresPointerFocusWarning({
      action: { ...action, target: { point: { x: 10, y: 20 } } },
      axTier: "semantic",
      channel: "native",
    }), true);
    assert.equal(requiresPointerFocusWarning({
      action: { ...action, kind: "focus-window" },
      axTier: "target-focus",
      channel: "native",
    }), true);
  });

  test("keeps the warning cadence explicit and rejects invalid timing", async () => {
    assert.equal(POINTER_FOCUS_COUNTDOWN_SECONDS, 3);
    assert.equal(POINTER_FOCUS_COUNTDOWN_STEP_MS, 800);
    await assert.rejects(
      runPointerFocusCountdown({ leaseId: "test", seconds: 0 }),
      /positive integer/,
    );
    await assert.rejects(
      runPointerFocusCountdown({ leaseId: "test", stepMs: -1 }),
      /non-negative number/,
    );
  });

  test("refuses to act when the lease ends during the warning", async () => {
    let cleanupCalls = 0;
    await assert.rejects(
      revalidatePointerFocusLease({
        warningShown: true,
        isLeaseActive: async () => false,
        onLeaseEnded: async () => {
          cleanupCalls += 1;
        },
      }),
      /Drive lease ended during pointer focus countdown/,
    );
    assert.equal(cleanupCalls, 1);
  });

  test("skips the extra lease check when no warning was shown", async () => {
    let checks = 0;
    await revalidatePointerFocusLease({
      warningShown: false,
      isLeaseActive: async () => {
        checks += 1;
        return false;
      },
    });
    assert.equal(checks, 0);
  });

  test("cleans up presentation when the lease check itself fails", async () => {
    let cleanupCalls = 0;
    await assert.rejects(
      revalidatePointerFocusLease({
        warningShown: true,
        isLeaseActive: async () => {
          throw new Error("agent disconnected");
        },
        onCheckFailed: async () => {
          cleanupCalls += 1;
        },
      }),
      /agent disconnected/,
    );
    assert.equal(cleanupCalls, 1);
  });

  test("waits for the overlay trajectory before the next act", () => {
    assert.equal(cursorTravelMs({ x: 10, y: 10 }, { x: 10, y: 10 }), 80);
    assert.equal(cursorTravelMs(undefined, { x: 10, y: 10 }), 220);
    const far = cursorTravelMs({ x: 0, y: 0 }, { x: 2000, y: 0 });
    assert.equal(far, 870);
    assert.ok(far > cursorTravelMs({ x: 0, y: 0 }, { x: 100, y: 0 }));
  });

  test("treats a deleted or lapsing overlay state as gone", () => {
    const now = Date.parse("2026-09-25T21:46:42.000Z");
    const expiresIn = (ms: number) => ({ expiresAt: new Date(now + ms).toISOString() });
    assert.equal(agentCursorStateIsLive(undefined, now), false);
    assert.equal(agentCursorStateIsLive(expiresIn(-5_000), now), false);
    assert.equal(agentCursorStateIsLive(expiresIn(AGENT_CURSOR_LIVENESS_MARGIN_MS / 2), now), false);
    assert.equal(agentCursorStateIsLive(expiresIn(30_000), now), true);
    assert.equal(agentCursorStateIsLive({}, now), true);
  });
});

describe("pointer focus countdown pacing", () => {
  async function withRecord(run: (path: string) => Promise<void>): Promise<void> {
    const directory = await mkdtemp(join(tmpdir(), "action-pointer-focus-"));
    try {
      await run(join(directory, "drive", "pointer-focus.json"));
    } finally {
      await rm(directory, { recursive: true, force: true });
    }
  }

  test("counts down once per stretch of pointer work, however slowly it is paced", async () => {
    await withRecord(async (path) => {
      const start = Date.parse("2026-09-25T21:42:42.000Z");
      assert.equal(await pointerFocusWarningDue({ now: start, path }), true);
      await notePointerFocusAct({ now: start, path });

      // The field report's pacing: clicks 9-30s apart, each after a fresh look.
      let at = start;
      for (const gap of [9_000, 17_000, 24_000, 29_000, 20_000]) {
        at += gap;
        assert.equal(await pointerFocusWarningDue({ now: at, path }), false);
        await notePointerFocusAct({ now: at, path });
      }

      // A pause long enough that the operator may have taken the machine back re-arms it.
      assert.equal(await pointerFocusWarningDue({ now: at + POINTER_FOCUS_REARM_MS - 1, path }), false);
      assert.equal(await pointerFocusWarningDue({ now: at + POINTER_FOCUS_REARM_MS, path }), true);
    });
  });

  test("warns when the record is torn or the clock went backwards", async () => {
    await withRecord(async (path) => {
      const now = Date.parse("2026-09-25T21:46:42.000Z");
      await notePointerFocusAct({ now: now + 60_000, path });
      assert.equal(await pointerFocusWarningDue({ now, path }), true);
      await writeFile(path, "{\"lastActAt\":");
      assert.equal(await pointerFocusWarningDue({ now, path }), true);
    });
  });
});
