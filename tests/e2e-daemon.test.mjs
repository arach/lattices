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
  assert.equal(typeof status.permissions, "object");
  assert.equal(typeof status.permissions.accessibility, "boolean");
  assert.equal(typeof status.permissions.screenRecording, "boolean");
});

test("desktop.snapshot returns frontmost, displays, and windows", async () => {
  const snap = await daemonCall("desktop.snapshot");
  assert.equal(typeof snap, "object");
  assert.ok(Array.isArray(snap.displays));
  assert.ok(snap.displays.length > 0);
  assert.ok(Array.isArray(snap.windows));
  assert.ok(Array.isArray(snap.sessions));
  assert.equal(typeof snap.permissions, "object");
  assert.equal(typeof snap.permissions.accessibility, "boolean");
  if (snap.frontmost) {
    assert.equal(typeof snap.frontmost.wid, "number");
    assert.equal(typeof snap.frontmost.app, "string");
  }
  if (snap.windows.length > 0) {
    assert.equal(typeof snap.windows[0].zIndex, "number");
    assert.equal(typeof snap.windows[0].focused, "boolean");
  }
});

test("terminals.capture requires a target", async () => {
  await assert.rejects(
    () => daemonCall("terminals.capture", {}),
    /session, paneId, or tty|Missing parameter/i,
  );
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

test("spaces.list returns displays with ordered spaces and a current space", async () => {
  const payload = await daemonCall("spaces.list");
  // Daemon may return an array of displays or { displays: [...] }.
  const displays = Array.isArray(payload)
    ? payload
    : Array.isArray(payload?.displays)
      ? payload.displays
      : null;
  assert.ok(Array.isArray(displays), "spaces.list should return displays");
  assert.ok(displays.length > 0, "expected at least one display");

  for (const display of displays) {
    assert.equal(typeof display.displayIndex, "number");
    assert.equal(typeof display.name, "string");
    assert.equal(typeof display.frame, "object");
    assert.equal(typeof display.visibleFrame, "object");
    for (const frame of [display.frame, display.visibleFrame]) {
      assert.equal(typeof frame.x, "number");
      assert.equal(typeof frame.y, "number");
      assert.ok(frame.w > 0);
      assert.ok(frame.h > 0);
    }
    assert.ok(Array.isArray(display.spaces), "display.spaces must be an array");
    assert.ok(display.spaces.length > 0, "display should list at least one space");
    assert.equal(typeof display.currentSpaceId, "number");

    let currentCount = 0;
    for (const space of display.spaces) {
      assert.equal(typeof space.id, "number");
      if (typeof space.index === "number") {
        assert.ok(space.index >= 1, "space.index is 1-based when present");
      }
      if (space.isCurrent === true || space.id === display.currentSpaceId) {
        currentCount += 1;
      }
    }
    assert.ok(
      currentCount >= 1,
      `display ${display.displayId ?? display.displayIndex} should mark a current space`
    );
  }

  // Contract for previous/next math: spaces are ordered; first has no prev, last no next.
  const primary = displays[0];
  if (primary.spaces.length >= 2) {
    const ids = primary.spaces.map((s) => s.id);
    assert.equal(new Set(ids).size, ids.length, "space ids unique per display");
  }
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

// ── window.move contract ─────────────────────────────────────────────
//
// These tests exercise validation and dry-run planning only; none of them
// moves a real window.

test("window.move rejects a missing target instead of falling back to frontmost", async () => {
  await assert.rejects(
    daemonCall("window.move", { display: 0 }),
    /wid or session/,
  );
});

test("window.move rejects a call with no operation", async () => {
  await assert.rejects(
    daemonCall("window.move", { wid: 999999999 }),
    /display, placement, or spaceId/,
  );
});

test("window.move rejects spaceId combined with display or placement", async () => {
  await assert.rejects(
    daemonCall("window.move", { wid: 999999999, spaceId: 1, display: 0 }),
    /spaceId cannot be combined/,
  );
  await assert.rejects(
    daemonCall("window.move", { wid: 999999999, spaceId: 1, placement: "left" }),
    /spaceId cannot be combined/,
  );
});

test("window.move rejects an unknown placement synchronously", async () => {
  await assert.rejects(
    daemonCall("window.move", { wid: 999999999, placement: "diagonal" }),
    /Unknown placement/,
  );
});

test("window.move rejects an unknown wid", async () => {
  await assert.rejects(
    daemonCall("window.move", { wid: 999999999, display: 0 }),
    /Not found: window/,
  );
});

test("window.move dry run plans a display move with structured geometry", async () => {
  const windows = await daemonCall("windows.list");
  const candidate = (Array.isArray(windows) ? windows : []).find((w) => w.isOnScreen);
  if (!candidate) return; // headless desktop — nothing to plan against

  const receipt = await daemonCall("window.move", { wid: candidate.wid, display: 0, dryRun: true });
  assert.equal(receipt.ok, true);
  assert.equal(receipt.status, "planned");
  assert.equal(receipt.dryRun, true);
  assert.equal(receipt.wid, candidate.wid);
  assert.equal(receipt.action?.type, "window.move");
  assert.equal(receipt.targetResolution, "wid");
  assert.equal(typeof receipt.display?.name, "string");
  assert.equal(typeof receipt.sourceDisplay?.name, "string");

  const mutation = receipt.mutations?.[0];
  assert.equal(mutation?.kind, "moveWindowToDisplay");
  for (const key of ["from", "to"]) {
    for (const field of ["x", "y", "w", "h"]) {
      assert.equal(typeof mutation[key]?.[field], "number", `${key}.${field} should be numeric`);
    }
  }
  assert.equal("after" in mutation, false, "dry run must not report an after frame");

  const fractions = receipt.fractions;
  for (const field of ["x", "y", "w", "h"]) {
    assert.equal(typeof fractions?.[field], "number");
    assert.ok(fractions[field] >= 0 && fractions[field] <= 1, `fraction ${field} in [0,1]`);
  }
});

test("window.move dry run with placement routes through canonical window.place", async () => {
  const windows = await daemonCall("windows.list");
  const candidate = (Array.isArray(windows) ? windows : []).find((w) => w.isOnScreen);
  if (!candidate) return;

  const receipt = await daemonCall("window.move", {
    wid: candidate.wid,
    display: 0,
    placement: "left",
    dryRun: true,
  });
  assert.equal(receipt.status, "planned");
  assert.equal(receipt.action?.type, "window.place");
  assert.equal(receipt.compatibilityMethod, "window.move");
  assert.equal(receipt.placement?.kind, "tile");
  assert.equal(receipt.placement?.value, "left");
});

test("window.move placement rejects an explicit unknown display", async () => {
  const windows = await daemonCall("windows.list");
  const candidate = (Array.isArray(windows) ? windows : []).find((w) => w.isOnScreen);
  if (!candidate) return;

  await assert.rejects(
    daemonCall("window.move", {
      wid: candidate.wid,
      display: 999999,
      placement: "left",
      dryRun: true,
    }),
    /Not found: display 999999/,
  );
});

test("window.place dry run resolves an explicit wid without mutating", async () => {
  const windows = await daemonCall("windows.list");
  const candidate = (Array.isArray(windows) ? windows : []).find((w) => w.isOnScreen);
  if (!candidate) return;

  const receipt = await daemonCall("window.place", {
    wid: candidate.wid,
    placement: "bottom-right",
    dryRun: true,
  });
  assert.equal(receipt.status, "planned");
  assert.equal(receipt.wid, candidate.wid);
  assert.equal(receipt.targetResolution, "wid");
});
