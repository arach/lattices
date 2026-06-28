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
  const session = toSessionName(repoRoot);
  assert.equal(session, "lattices-c36f74");
  assert.equal(pathHash(repoRoot), "c36f74");
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