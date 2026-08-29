import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { readToolLedger, recordToolCall, verbForTool } from "./tool-ledger.js";

async function withTempLedger(run: () => Promise<void>): Promise<void> {
  const previous = process.env.ACTION_TOOL_LEDGER_DIR;
  process.env.ACTION_TOOL_LEDGER_DIR = await mkdtemp(join(tmpdir(), "action-tool-ledger-"));
  try {
    await run();
  } finally {
    if (previous === undefined) {
      delete process.env.ACTION_TOOL_LEDGER_DIR;
    } else {
      process.env.ACTION_TOOL_LEDGER_DIR = previous;
    }
  }
}

describe("tool ledger", () => {
  test("files an act under its kind and leaves other tools alone", () => {
    assert.equal(verbForTool("action.act.execute", { action: { kind: "click" } }), "click");
    assert.equal(verbForTool("action.observe.ax", { action: { kind: "click" } }), undefined);
  });

  test("a malformed act argument bag costs the verb, not the entry", () => {
    assert.equal(verbForTool("action.act.execute", undefined), undefined);
    assert.equal(verbForTool("action.act.execute", {}), undefined);
    assert.equal(verbForTool("action.act.execute", { action: { kind: 42 } }), undefined);
    assert.equal(verbForTool("action.act.execute", { action: { kind: "" } }), undefined);
  });

  test("records both successful and failed calls", async () => {
    await withTempLedger(async () => {
      await recordToolCall({ at: "2026-08-19T00:00:00.000Z", tool: "action.act.execute", verb: "click", ok: true, ms: 12 });
      await recordToolCall({ at: "2026-08-19T00:00:01.000Z", tool: "action.observe.ax", ok: false, ms: 3 });

      const entries = await readToolLedger();
      assert.equal(entries.length, 2);
      assert.equal(entries[0]?.verb, "click");
      assert.equal(entries[0]?.ok, true);
      assert.equal(entries[1]?.tool, "action.observe.ax");
      assert.equal(entries[1]?.ok, false);
    });
  });

  test("a torn line does not lose the surrounding entries", async () => {
    await withTempLedger(async () => {
      const { appendFile } = await import("node:fs/promises");
      const { toolLedgerPath } = await import("./tool-ledger.js");
      await recordToolCall({ at: "2026-08-19T00:00:00.000Z", tool: "action.drive.aim", ok: true, ms: 4 });
      await appendFile(toolLedgerPath(), '{"at":"broken"\n');
      await recordToolCall({ at: "2026-08-19T00:00:02.000Z", tool: "action.drive.note", ok: true, ms: 1 });

      const entries = await readToolLedger();
      assert.deepEqual(entries.map((entry) => entry.tool), ["action.drive.aim", "action.drive.note"]);
    });
  });
});
