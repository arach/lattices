import assert from "node:assert/strict";
import { describe, test } from "node:test";

import {
  AGENT_CURSOR_IDLE_EXPIRY_MS,
  POINTER_FOCUS_COUNTDOWN_SECONDS,
  POINTER_FOCUS_COUNTDOWN_STEP_MS,
  agentCursorExpiration,
  cursorTravelMs,
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

  test("waits for the overlay warp before the next act", () => {
    assert.equal(cursorTravelMs({ x: 10, y: 10 }, { x: 10, y: 10 }), 80);
    assert.equal(cursorTravelMs(undefined, { x: 10, y: 10 }), 220);
    const far = cursorTravelMs({ x: 0, y: 0 }, { x: 2000, y: 0 });
    assert.equal(far, 470);
    assert.ok(far > cursorTravelMs({ x: 0, y: 0 }, { x: 100, y: 0 }));
  });
});
