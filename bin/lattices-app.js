#!/usr/bin/env node

import { execSync, spawn } from "node:child_process";
import { existsSync, mkdirSync, chmodSync, createWriteStream } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { get } from "node:https";

const __dirname = dirname(fileURLToPath(import.meta.url));
const appDir = resolve(__dirname, "../app");
const bundlePath = resolve(appDir, "Lattices.app");
const binaryDir = resolve(bundlePath, "Contents/MacOS");
const binaryPath = resolve(binaryDir, "Lattices");

const REPO = "arach/lattices";
const ASSET_NAME = "Lattices-macos-arm64";

// ── Helpers ──────────────────────────────────────────────────────────

function isRunning() {
  try {
    execSync("pgrep -f Lattices.app", { stdio: "pipe" });
    return true;
  } catch {
    return false;
  }
}

function hasSwift() {
  try {
    execSync("which swift", { stdio: "pipe" });
    return true;
  } catch {
    return false;
  }
}

function launch(extraArgs = []) {
  if (isRunning()) {
    console.log("lattices app is already running.");
    return;
  }
  const args = [bundlePath];
  if (extraArgs.length) args.push("--args", ...extraArgs);
  spawn("open", args, { detached: true, stdio: "ignore" }).unref();
  console.log("lattices app launched.");
}

// ── Build from source (current arch only) ────────────────────────────

function buildFromSource() {
  console.log("Building lattices app from source...");
  try {
    execSync("swift build -c release", {
      cwd: appDir,
      stdio: "inherit",
    });
  } catch {
    return false;
  }

  const builtPath = resolve(appDir, ".build/release/Lattices");
  if (!existsSync(builtPath)) return false;

  mkdirSync(binaryDir, { recursive: true });
  execSync(`cp '${builtPath}' '${binaryPath}'`);

  // Re-sign the bundle so macOS TCC recognizes a stable identity across rebuilds.
  // Without this, each build gets a new ad-hoc signature and permission grants are lost.
  try {
    // Prefer a real signing identity for stable TCC grants; fall back to ad-hoc with fixed identifier
    const identities = execSync("security find-identity -v -p codesigning", { stdio: "pipe" }).toString();
    const devId = identities.match(/"(Apple Development:[^"]+)"/)?.[1]
               || identities.match(/"(Developer ID Application:[^"]+)"/)?.[1];
    const signArg = devId ? `'${devId}'` : "-";
    execSync(
      `codesign --force --sign ${signArg} --identifier com.arach.lattices '${bundlePath}'`,
      { stdio: "pipe" }
    );
  } catch (e) {
    // Non-fatal — app still works, just permissions won't persist across rebuilds
    console.log("Warning: code signing failed — permissions may not persist across rebuilds.");
  }
  console.log("Build complete.");
  return true;
}

// ── Download from GitHub releases ────────────────────────────────────

function httpsGet(url) {
  return new Promise((resolve, reject) => {
    get(url, { headers: { "User-Agent": "lattices" } }, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        return httpsGet(res.headers.location).then(resolve, reject);
      }
      if (res.statusCode !== 200) {
        reject(new Error(`HTTP ${res.statusCode}`));
        res.resume();
        return;
      }
      resolve(res);
    }).on("error", reject);
  });
}

async function download() {
  console.log("Downloading pre-built binary...");

  try {
    const apiUrl = `https://api.github.com/repos/${REPO}/releases/latest`;
    const apiRes = await httpsGet(apiUrl);
    const chunks = [];
    for await (const chunk of apiRes) chunks.push(chunk);
    const release = JSON.parse(Buffer.concat(chunks).toString());

    const asset = release.assets?.find((a) => a.name === ASSET_NAME);
    if (!asset) throw new Error("Binary not found in release assets");

    const dlRes = await httpsGet(asset.browser_download_url);

    mkdirSync(binaryDir, { recursive: true });
    const ws = createWriteStream(binaryPath);
    await new Promise((resolve, reject) => {
      dlRes.pipe(ws);
      ws.on("finish", resolve);
      ws.on("error", reject);
    });

    chmodSync(binaryPath, 0o755);
    console.log("Download complete.");
    return true;
  } catch (e) {
    console.log(`Download failed: ${e.message}`);
    return false;
  }
}

// ── Commands ─────────────────────────────────────────────────────────

async function ensureBinary() {
  if (existsSync(binaryPath)) return;

  // 1. Try local compile (fast, matches exact system)
  if (hasSwift()) {
    if (buildFromSource()) return;
    console.log("Local build failed, trying download...");
  }

  // 2. Fall back to pre-built binary from GitHub releases
  const downloaded = await download();
  if (downloaded) return;

  // 3. Nothing worked
  console.error(
    "Could not build or download the lattices app.\n" +
    "Options:\n" +
    "  • Install Xcode CLI tools:  xcode-select --install\n" +
    "  • Download manually from:   https://github.com/" + REPO + "/releases"
  );
  process.exit(1);
}

const cmd = process.argv[2];
const flags = process.argv.slice(3);
const launchFlags = [];
if (flags.includes("--diagnostics") || flags.includes("-d")) launchFlags.push("--diagnostics");
if (flags.includes("--screen-map") || flags.includes("-m")) launchFlags.push("--screen-map");

if (cmd === "build") {
  if (!hasSwift()) {
    console.error("Swift is required. Install with: xcode-select --install");
    process.exit(1);
  }
  buildFromSource();
} else if (cmd === "quit") {
  try {
    execSync("pkill -f Lattices.app", { stdio: "pipe" });
    console.log("lattices app stopped.");
  } catch {
    console.log("lattices app is not running.");
  }
} else if (cmd === "restart") {
  // Quit → rebuild → relaunch
  try { execSync("pkill -f Lattices.app", { stdio: "pipe" }); } catch {}
  if (!hasSwift()) {
    console.error("Swift is required. Install with: xcode-select --install");
    process.exit(1);
  }
  if (!buildFromSource()) {
    console.error("Build failed.");
    process.exit(1);
  }
  launch(launchFlags);
} else {
  await ensureBinary();
  launch(launchFlags);
}
