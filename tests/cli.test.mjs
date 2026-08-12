import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { before, test } from "node:test";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { toSessionName, pathHash } from "../bin/cli/session.ts";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, "..");
const nodeBin = process.execPath;
const cliEntry = path.join(repoRoot, "bin/lattices.ts");
const daemonClientUrl = pathToFileURL(
  path.join(repoRoot, "bin/daemon-client.ts")
).href;

const { isDaemonRunning } = await import(daemonClientUrl);
const { createWorkspaceMapSnapshot, parseMapOptions, renderWorkspaceMap } = await import(
  pathToFileURL(path.join(repoRoot, "bin/cli/map.ts")).href
);

/** @type {boolean} */
let daemonRunning = false;

before(async () => {
  daemonRunning = await isDaemonRunning();
});

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

function runCliRaw(args) {
  try {
    const stdout = execFileSync(
      nodeBin,
      ["--experimental-strip-types", cliEntry, ...args],
      {
        cwd: repoRoot,
        encoding: "utf8",
        env: process.env,
      }
    );
    return { stdout: stdout.trim(), stderr: "", status: 0 };
  } catch (err) {
    return {
      stdout: (err.stdout || "").toString().trim(),
      stderr: (err.stderr || "").toString().trim(),
      status: err.status ?? 1,
    };
  }
}

// ── session hash parity ──────────────────────────────────────────────

test("session hash: known repo path produces stable session name", () => {
  // Keep the parity fixture independent of the checkout/worktree location.
  const knownRepoPath = "/Users/art/dev/lattices";
  const session = toSessionName(knownRepoPath);
  assert.equal(session, "lattices-c36f74");
  assert.equal(pathHash(knownRepoPath), "c36f74");
});

test("session hash: format is basename-6hex", () => {
  const session = toSessionName(repoRoot);
  assert.match(session, /^[a-zA-Z0-9_-]+-[0-9a-f]{6}$/);
});

test("session hash: basename sanitization replaces non-alphanumeric chars", () => {
  const session = toSessionName("/tmp/my.project+name");
  assert.match(session, /^my-project-name-[0-9a-f]{6}$/);
  assert.equal(session.slice(0, "my-project-name-".length), "my-project-name-");
});

test("session hash: different paths with same basename get distinct hashes", () => {
  const a = toSessionName("/tmp/proj-a/foo");
  const b = toSessionName("/tmp/proj-b/foo");
  assert.notEqual(a, b);
  assert.match(a, /^foo-[0-9a-f]{6}$/);
  assert.match(b, /^foo-[0-9a-f]{6}$/);
});

test("session hash: default command prints session name for cwd", () => {
  const { stdout } = runCliRaw([]);
  const expected = toSessionName(repoRoot);
  assert.match(stdout, new RegExp(`session\\s+${expected}`));
});

// ── default command & help ───────────────────────────────────────────

test("default command: prints home screen guidance", () => {
  const out = runCli([]);
  assert.match(out, /let's get you situated/);
  assert.match(out, /Common commands/);
});

test("help: mentions lattices start", () => {
  const out = runCli(["help"]);
  assert.match(out, /lattices start/);
});

test("map renderer: draws current-space windows and a useful legend", () => {
  const out = renderWorkspaceMap(
    [{ displayIndex: 1, name: "Samsung", currentSpaceId: 7, visibleFrame: { x: 100, y: 20, w: 2000, h: 1000 } }],
    [
      { wid: 10, app: "Simulator", title: "iPhone 16", frame: { x: 100, y: 20, w: 1000, h: 500 }, spaceIds: [7], isOnScreen: true },
      { wid: 11, app: "Chrome", title: "iii console", frame: { x: 1100, y: 20, w: 1000, h: 1000 }, spaceIds: [7], isOnScreen: true },
      { wid: 12, app: "Chrome", title: "hidden space", frame: { x: 100, y: 520, w: 1000, h: 500 }, spaceIds: [5], isOnScreen: false },
    ],
    { width: 60, height: 14 },
  );
  assert.match(out, /Display 1 · Samsung · Space 7/);
  assert.match(out, /Simulator · iPhone 16/);
  assert.match(out, /Chrome · iii console/);
  assert.doesNotMatch(out, /hidden space/);
  assert.match(out, /wid:10/);
});

test("map renderer: foreground windows occlude the back and labels stay cell-safe", () => {
  const out = renderWorkspaceMap(
    [{ displayIndex: 0, name: "Main 📺", currentSpaceId: 7, visibleFrame: { x: 0, y: 0, w: 100, h: 100 } }],
    [
      { wid: 2, app: "Front\u001b[31m", title: "前\u001b[31m", frame: { x: 40, y: 40, w: 60, h: 60 }, spaceIds: [7], isOnScreen: true },
      { wid: 1, app: "Back", title: "background", frame: { x: 0, y: 0, w: 100, h: 100 }, spaceIds: [7], isOnScreen: true },
    ],
    { width: 40, height: 12 },
  );
  const framedLines = out.split("\n").filter((line) => /^[┌│└]/u.test(line));
  assert.ok(framedLines.every((line) => line.length === 40), out);
  assert.match(out, /1 Front - \?/);
  assert.doesNotMatch(out, /\u001b/);
  assert.doesNotMatch(out, /┼/u, "occluded borders should not bleed through the foreground window");
});

test("map options: accept split and equals forms and reject malformed input", () => {
  assert.deepEqual(parseMapOptions(["--display", "1", "--width=80", "--height", "20", "--json"]), {
    display: 1,
    width: 80,
    height: 20,
    json: true,
  });
  assert.throws(() => parseMapOptions(["--width"]), /--width expects a non-negative integer/);
  assert.throws(() => parseMapOptions(["--display", "-1"]), /--display expects a non-negative integer/);
  assert.throws(() => parseMapOptions(["--bogus"]), /Unknown option: --bogus/);
});

test("map JSON snapshot: filters by display and current Space in front-to-back order", () => {
  const displays = [
    { displayIndex: 0, displayId: "main", currentSpaceId: 7, visibleFrame: { x: 0, y: 24, w: 1000, h: 776 } },
    { displayIndex: 1, displayId: "above", currentSpaceId: 8, spaces: [{ id: 8, index: 1, display: 1, isCurrent: true, rawOnly: "omit" }], visibleFrame: { x: -500, y: -900, w: 1200, h: 900 }, rawOnly: "omit" },
    { displayIndex: 2, displayId: "below", currentSpaceId: 9, visibleFrame: { x: 0, y: 800, w: 1000, h: 700 } },
  ];
  const windows = [
    { wid: 20, app: "Front", title: "above front", frame: { x: -400, y: -800, w: 600, h: 400 }, spaceIds: [8], isOnScreen: true, rawOnly: "omit" },
    { wid: 21, app: "Back", title: "above back", frame: { x: 100, y: -500, w: 500, h: 400 }, spaceIds: [8], isOnScreen: true },
    { wid: 22, app: "Hidden", title: "other Space", frame: { x: -400, y: -800, w: 600, h: 400 }, spaceIds: [99], isOnScreen: false },
    { wid: 23, app: "Below", title: "below", frame: { x: 0, y: 900, w: 500, h: 400 }, spaceIds: [9], isOnScreen: true },
  ];

  const snapshot = createWorkspaceMapSnapshot(displays, windows, { display: 1 });
  assert.deepEqual(snapshot.coordinateSystem, {
    origin: "top-left",
    units: "points",
    reference: "global-desktop",
  });
  assert.equal(snapshot.version, 1);
  assert.equal(snapshot.displays.length, 1);
  assert.equal(snapshot.displays[0].displayId, "above");
  assert.deepEqual(snapshot.displays[0].spaces, [{ id: 8, index: 1, display: 1, isCurrent: true }]);
  assert.equal("rawOnly" in snapshot.displays[0], false);
  assert.equal("rawOnly" in snapshot.displays[0].spaces[0], false);
  assert.equal("rawOnly" in snapshot.displays[0].windows[0], false);
  assert.deepEqual(snapshot.displays[0].windows.map(({ wid, zIndex }) => ({ wid, zIndex })), [
    { wid: 20, zIndex: 0 },
    { wid: 21, zIndex: 1 },
  ]);
});

test("map --help: works without a running daemon", () => {
  const out = runCli(["map", "--help"]);
  assert.match(out, /Render the current Space/);
  assert.match(out, /--display <n>/);
});

// ── search --deep ────────────────────────────────────────────────────

test("search --deep: does not crash when daemon is running", async (t) => {
  if (!daemonRunning) {
    t.skip("daemon not running — start with: lattices app");
    return;
  }
  const { status, stdout, stderr } = runCliRaw(["search", "foo", "--deep"]);
  const combined = `${stdout}\n${stderr}`;
  assert.equal(status, 0, `expected exit 0, got ${status}: ${combined}`);
});

test("search --deep: exits non-zero with friendly message when daemon is down", async (t) => {
  if (daemonRunning) {
    t.skip("daemon is running — stop daemon to exercise daemon-down path");
    return;
  }
  const { status, stdout, stderr } = runCliRaw(["search", "foo", "--deep"]);
  const combined = `${stdout}\n${stderr}`.trim();
  assert.equal(status, 1, `expected exit 1, got ${status}: ${combined}`);
  assert.match(combined, /Daemon not running/i);
  assert.match(combined, /lattices app/i);
});
