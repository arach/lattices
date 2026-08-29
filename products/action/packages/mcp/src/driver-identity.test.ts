import assert from "node:assert/strict";
import { describe, test } from "node:test";

import { DriverIdentityContext, inferDriverIdentity } from "./driver-identity.js";

describe("driver identity", () => {
  test("prefers an explicit deployment label", () => {
    assert.equal(
      inferDriverIdentity({
        ACTION_DRIVER_LABEL: "Talkie Codex",
        OPENSCOUT_AGENT: "session-x",
      }).agent,
      "Talkie Codex",
    );
  });

  test("uses the stable Scout sender id when available", () => {
    assert.equal(
      inferDriverIdentity({
        OPENSCOUT_AGENT: "talkie.codex-recovery-talkie-stack-20260811.arachs-mac-mini-5-local",
      }).agent,
      "talkie.codex-recovery-talkie-stack-20260811.arachs-mac-mini-5-local",
    );
  });

  test("labels fallback honestly", () => {
    assert.deepEqual(inferDriverIdentity({}), {
      agent: "Unidentified MCP caller",
      source: "fallback",
    });
  });

  test("handshake overrides inference for subsequent implicit leases", () => {
    const context = new DriverIdentityContext({ OPENSCOUT_AGENT: "session-x" });
    assert.deepEqual(context.identify("Codex · checkout audit", "stage website"), {
      agent: "Codex · checkout audit",
      task: "stage website",
      source: "handshake",
    });
    assert.deepEqual(context.get(), {
      agent: "Codex · checkout audit",
      task: "stage website",
      source: "handshake",
    });
  });
});
