import assert from "node:assert/strict";
import { describe, test } from "node:test";

import { isDriveLeaseInactiveError } from "./drive-client.js";

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
});
