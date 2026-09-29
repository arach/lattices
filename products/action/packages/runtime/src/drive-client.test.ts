import assert from "node:assert/strict";
import { describe, test } from "node:test";

import { inferAxTier, isDriveLeaseInactiveError } from "./drive-client.js";

describe("drive client", () => {
  test("recognizes the native terminal-lease response", () => {
    assert.equal(
      isDriveLeaseInactiveError(new Error("Drive lease drive_123 is not active")),
      true,
    );
  });

  test("does not hide transport or ownership failures", () => {
    assert.equal(isDriveLeaseInactiveError(new Error("Action agent connection closed")), false);
    assert.equal(
      isDriveLeaseInactiveError(new Error("Drive lease drive_123 belongs to another connection")),
      false,
    );
  });

  test("infers blink for acts routed onto the agent layer", () => {
    assert.equal(inferAxTier({ actionKind: "click", channel: "hid", targetMode: "coordinate" }), "attention");
    assert.equal(inferAxTier({ actionKind: "click", channel: "blink", targetMode: "coordinate", blink: true }), "blink");
    assert.equal(inferAxTier({ actionKind: "type", blink: true }), "blink");
    assert.equal(inferAxTier({ actionKind: "press-key", blink: true }), "blink");
    // Only click/type/press-key blink; a drag stays attention even with a layer up.
    assert.equal(inferAxTier({ actionKind: "drag", blink: true }), "attention");
  });
});
