import assert from "node:assert/strict";
import { accessSync, rmSync } from "node:fs";
import { access, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, test } from "node:test";

import type { AgentLayerState } from "@action/protocol";

import { AgentLayerDirector, agentLayerRouting, parseAgentLayerOpen } from "./agent-layer.js";

function stateFor(pid: number): AgentLayerState {
  return {
    pid,
    displayId: 7,
    bounds: { x: 5000, y: 0, width: 1280, height: 800 },
    pip: true,
    windows: [{
      pid: 900,
      bundleId: "com.apple.calculator",
      title: "Calculator",
      original: { x: 100, y: 100, width: 230, height: 400 },
    }],
    startedAt: "2026-09-29T12:00:00.000Z",
  };
}

async function exists(path: string): Promise<boolean> {
  try {
    await access(path);
    return true;
  } catch {
    return false;
  }
}

/**
 * A fake native host. `agent-layer` "starts" a process (a pid in `live`), writes the state
 * file the way the native command does, and exits when the stop file appears.
 */
async function fixture(options: { stopExits?: boolean; writeState?: boolean } = {}) {
  const root = await mkdtemp(join(tmpdir(), "action-agent-layer-"));
  const live = new Set<number>();
  const calls: string[][] = [];
  const terminated: number[] = [];
  let nextPid = 5000;
  let director: AgentLayerDirector;

  const isAlive = (pid: number) => {
    if (live.has(pid) && options.stopExits !== false) {
      // Stop file present → the native process restores windows, deletes state, exits.
      const stop = director.paths().stop;
      try {
        accessSync(stop);
        live.delete(pid);
        rmSync(director.paths().state, { force: true });
      } catch {
        // Still running.
      }
    }
    return live.has(pid);
  };

  director = new AgentLayerDirector("/unused", {
    root,
    isAlive,
    terminate: (pid) => {
      terminated.push(pid);
      live.delete(pid);
    },
    stateWaitMs: 200,
    closeWaitMs: 120,
    runHost: async (args) => {
      calls.push(args);
      const pid = nextPid++;
      live.add(pid);
      if (options.writeState !== false) {
        const stateFile = args[args.indexOf("--state-file") + 1];
        await writeFile(stateFile, JSON.stringify(stateFor(pid)));
      }
      return { stdout: JSON.stringify({ status: "agent-layer-running", detail: String(pid) }) };
    },
  });
  return { root, director, live, calls, terminated, cleanup: () => rm(root, { recursive: true, force: true }) };
}

describe("parseAgentLayerOpen", () => {
  test("defaults to a caller-owned layer with no size", () => {
    assert.deepEqual(parseAgentLayerOpen({}), { owner: "caller" });
  });

  test("accepts CLI-shaped strings", () => {
    assert.deepEqual(
      parseAgentLayerOpen({ bundleId: "com.apple.calculator", width: "1280", height: "800", pip: "off", owner: "detached" }),
      { bundleId: "com.apple.calculator", width: 1280, height: 800, pip: false, owner: "detached" },
    );
  });

  test("rejects half a size and a doubled subject", () => {
    assert.throws(() => parseAgentLayerOpen({ width: 1280 }), /width and height go together/);
    assert.throws(() => parseAgentLayerOpen({ bundleId: "a", pid: 3 }), /bundleId or pid/);
    assert.throws(() => parseAgentLayerOpen({ pid: -1 }), /positive integer/);
  });
});

describe("AgentLayerDirector", () => {
  test("open launches agent-layer and returns the native state", async () => {
    const { director, calls, cleanup } = await fixture();
    try {
      const status = await director.open({ bundleId: "com.apple.calculator", width: 1280, height: 800, pip: true });
      const args = calls[0] ?? [];
      assert.equal(args[0], "agent-layer");
      assert.equal(args[args.indexOf("--parent-pid") + 1], String(process.pid));
      assert.equal(args[args.indexOf("--bundle-id") + 1], "com.apple.calculator");
      assert.equal(args[args.indexOf("--pip") + 1], "on");
      assert.equal(status.active, true);
      assert.equal(status.layer?.displayId, 7);
      assert.deepEqual(status.subject, { bundleId: "com.apple.calculator" });
      assert.deepEqual(agentLayerRouting(status), {
        bundleId: "com.apple.calculator",
        bounds: { x: 5000, y: 0, width: 1280, height: 800 },
      });
    } finally {
      await cleanup();
    }
  });

  test("a detached layer does not watch this process", async () => {
    const { director, calls, cleanup } = await fixture();
    try {
      await director.open({ pid: 900, owner: "detached" });
      assert.equal(calls[0]?.includes("--parent-pid"), false);
      assert.equal(calls[0]?.[calls[0].indexOf("--pid") + 1], "900");
    } finally {
      await cleanup();
    }
  });

  test("opening again closes the previous layer first", async () => {
    const { director, live, cleanup } = await fixture();
    try {
      const first = await director.open({ bundleId: "com.apple.calculator" });
      const second = await director.open({ bundleId: "com.apple.TextEdit" });
      assert.equal(live.has(first.layer!.pid), false);
      assert.equal(live.has(second.layer!.pid), true);
      assert.deepEqual((await director.status()).subject, { bundleId: "com.apple.TextEdit" });
    } finally {
      await cleanup();
    }
  });

  test("close stops the layer and clears its files", async () => {
    const { director, live, cleanup } = await fixture();
    try {
      const opened = await director.open({ bundleId: "com.apple.calculator" });
      const closed = await director.close();
      assert.equal(closed.active, false);
      assert.equal(live.has(opened.layer!.pid), false);
      assert.equal(await exists(director.paths().state), false);
      assert.equal(await exists(director.paths().request), false);
      assert.equal((await director.status()).active, false);
    } finally {
      await cleanup();
    }
  });

  test("close falls back to SIGTERM when the stop file is ignored", async () => {
    const { director, terminated, cleanup } = await fixture({ stopExits: false });
    try {
      const opened = await director.open({ bundleId: "com.apple.calculator" });
      const closed = await director.close();
      assert.deepEqual(terminated, [opened.layer!.pid]);
      assert.equal(closed.active, false);
    } finally {
      await cleanup();
    }
  });

  test("status cleans up after a layer that died", async () => {
    const { director, live, cleanup } = await fixture();
    try {
      const opened = await director.open({ bundleId: "com.apple.calculator" });
      live.delete(opened.layer!.pid);
      const status = await director.status();
      assert.equal(status.active, false);
      assert.equal(status.layer, undefined);
      assert.equal(await exists(director.paths().state), false);
      assert.equal(await director.routing(), undefined);
    } finally {
      await cleanup();
    }
  });

  test("routing falls back to the first moved window when no subject was given", async () => {
    const { director, cleanup } = await fixture();
    try {
      await director.open({});
      assert.deepEqual((await director.routing())?.bundleId, "com.apple.calculator");
      const request = JSON.parse(await readFile(director.paths().request, "utf8")) as { subject?: unknown };
      assert.equal(request.subject, undefined);
    } finally {
      await cleanup();
    }
  });

  test("open fails and tears down when no state file lands", async () => {
    const { director, live, cleanup } = await fixture({ writeState: false });
    try {
      await assert.rejects(director.open({ bundleId: "com.apple.calculator" }), /never wrote its state file/);
      assert.equal(live.size, 0);
    } finally {
      await cleanup();
    }
  });
});
