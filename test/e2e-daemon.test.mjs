import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { before, test } from "node:test";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, "..");
const nodeBin = process.execPath;
const cliEntry = path.join(repoRoot, "bin/lattices.ts");
const daemonClientUrl = pathToFileURL(
  path.join(repoRoot, "bin/daemon-client.ts")
).href;

const { daemonCall, isDaemonRunning } = await import(daemonClientUrl);

function runCli(args) {
  return execFileSync(
    nodeBin,
    ["--experimental-strip-types", cliEntry, ...args],
    {
      cwd: repoRoot,
      encoding: "utf8",
      env: process.env,
    }
  ).trim();
}

function runCliJson(args) {
  return JSON.parse(runCli(args));
}

function assertStatusShape(status) {
  assert.equal(typeof status, "object");
  assert.equal(typeof status.uptime, "number");
  assert.equal(typeof status.clientCount, "number");
  assert.equal(typeof status.windowCount, "number");
  assert.equal(typeof status.tmuxSessionCount, "number");
  assert.equal(typeof status.version, "string");
  assert.ok(status.uptime >= 0);
}

function assertWindowShape(win) {
  assert.equal(typeof win, "object");
  assert.equal(typeof win.wid, "number");
  assert.equal(typeof win.app, "string");
  assert.equal(typeof win.title, "string");
  assert.equal(typeof win.pid, "number");
  assert.equal(typeof win.isOnScreen, "boolean");
  assert.ok(Array.isArray(win.spaceIds));
  assert.equal(typeof win.frame, "object");
  assert.equal(typeof win.frame.x, "number");
  assert.equal(typeof win.frame.y, "number");
  assert.equal(typeof win.frame.w, "number");
  assert.equal(typeof win.frame.h, "number");
}

function assertProjectShape(project) {
  assert.equal(typeof project, "object");
  assert.equal(typeof project.path, "string");
  assert.equal(typeof project.name, "string");
  assert.equal(typeof project.sessionName, "string");
  assert.equal(typeof project.isRunning, "boolean");
}

before(async () => {
  const running = await isDaemonRunning();
  assert.equal(
    running,
    true,
    "Lattices daemon is not running. Start it with ./bin/lattices-dev restart"
  );
});

test("daemon.status RPC returns healthy counts", async () => {
  const status = await daemonCall("daemon.status");
  assertStatusShape(status);
});

test("CLI daemon status call returns JSON status payload", () => {
  const status = runCliJson(["call", "daemon.status"]);
  assertStatusShape(status);
});

test("CLI windows --json returns window records", () => {
  const windows = runCliJson(["windows", "--json"]);
  assert.ok(Array.isArray(windows));
  if (windows.length > 0) {
    assertWindowShape(windows[0]);
  }
});

test("projects.scan round-trips and projects.list remains readable", async () => {
  const scan = await daemonCall("projects.scan");
  assert.deepEqual(scan, { ok: true });

  const projects = await daemonCall("projects.list");
  assert.ok(Array.isArray(projects));
  if (projects.length > 0) {
    assertProjectShape(projects[0]);
  }
});

test("tmux.inventory returns array buckets", async () => {
  const inventory = await daemonCall("tmux.inventory");
  assert.equal(typeof inventory, "object");
  assert.ok(Array.isArray(inventory.all));
  assert.ok(Array.isArray(inventory.orphans));
});

test("voice.simulate parses a search command without executing", async () => {
  const result = await daemonCall("voice.simulate", {
    text: "find lattices",
    execute: false,
  });

  assert.equal(result.parsed, true);
  assert.equal(result.intent, "search");
  assert.equal(result.slots?.query, "lattices");
  assert.equal(typeof result.confidence, "number");
  assert.ok(!("executed" in result));
});

test("voice.simulate reports no-match commands cleanly", async () => {
  const result = await daemonCall("voice.simulate", {
    text: "tell me a joke",
    execute: false,
  });

  assert.equal(result.parsed, false);
  assert.equal(result.intent, null);
  assert.equal(result.message, "No intent matched");
});

test("CLI search --json returns structured quick-search results", () => {
  const results = runCliJson(["search", "Chrome", "--json"]);
  assert.ok(Array.isArray(results));

  if (results.length > 0) {
    const first = results[0];
    assert.equal(typeof first.wid, "number");
    assert.equal(typeof first.app, "string");
    assert.equal(typeof first.title, "string");
    assert.equal(typeof first.score, "number");
    assert.ok(Array.isArray(first.reasons));
  }
});
