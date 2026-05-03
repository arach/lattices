#!/usr/bin/env bun

import { execSync, spawn } from "node:child_process";
import { existsSync, mkdirSync, chmodSync, createWriteStream, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { get } from "node:https";
import type { IncomingMessage } from "node:http";

const __dirname = import.meta.dir;
const appDir = resolve(__dirname, "../app");
const cliRoot = resolve(__dirname, "..");
const bundlePath = resolve(appDir, "Lattices.app");
const binaryDir = resolve(bundlePath, "Contents/MacOS");
const binaryPath = resolve(binaryDir, "Lattices");
const entitlementsPath = resolve(__dirname, "../app/Lattices.entitlements");
const resourcesDir = resolve(bundlePath, "Contents/Resources");
const iconPath = resolve(__dirname, "../assets/AppIcon.icns");
const tapSoundPath = resolve(__dirname, "../app/Resources/tap.wav");

const REPO = "arach/lattices";
const RELEASE_APP_ASSET_NAMES = ["Lattices.dmg"];
const RELEASE_BINARY_ASSET_NAMES = ["Lattices-macos-arm64", "LatticeApp-macos-arm64"];
type ReleaseAsset = { name: string; browser_download_url: string };
const selfScriptPath = resolve(__dirname, "lattices-app.ts");

// ── Helpers ──────────────────────────────────────────────────────────

function isRunning(): boolean {
  try {
    execSync("pgrep -x Lattices", { stdio: "pipe" });
    return true;
  } catch {
    return false;
  }
}

function quit(): boolean {
  try {
    execSync("pkill -x Lattices", { stdio: "pipe" });
    // Wait briefly for process to exit
    try { execSync("sleep 0.5", { stdio: "pipe" }); } catch {}
    // Force kill if still running
    if (isRunning()) {
      execSync("pkill -9 -x Lattices", { stdio: "pipe" });
    }
    return true;
  } catch {
    return false;
  }
}

function hasSwift(): boolean {
  try {
    execSync("which swift", { stdio: "pipe" });
    return true;
  } catch {
    return false;
  }
}

function packageVersion(): string {
  try {
    const pkg = JSON.parse(readFileSync(resolve(__dirname, "../package.json"), "utf8"));
    return typeof pkg.version === "string" ? pkg.version : "0.1.0";
  } catch {
    return "0.1.0";
  }
}

function gitRevision(): string {
  try {
    return execSync("git rev-parse --short HEAD", {
      cwd: cliRoot,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return "unknown";
  }
}

function xmlEscape(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&apos;");
}

function launch(extraArgs: string[] = []): void {
  if (isRunning()) {
    console.log("lattices app is already running.");
    return;
  }
  const args = [bundlePath];
  const appArgs = ["--lattices-cli-root", cliRoot, ...extraArgs];
  if (appArgs.length) args.push("--args", ...appArgs);
  spawn("open", args, { detached: true, stdio: "ignore" }).unref();
  console.log("lattices app launched.");
}

function relaunchIfNeeded(shouldLaunch: boolean, extraArgs: string[] = []): void {
  if (!shouldLaunch) {
    console.log("App updated. Launch with: lattices app");
    return;
  }
  launch(extraArgs);
}

function resolveSigningIdentity(): string | null {
  try {
    const identities = execSync("security find-identity -v -p codesigning", { stdio: "pipe" }).toString();
    return identities.match(/"(Developer ID Application:[^"]+)"/)?.[1]
        || identities.match(/"(Apple Development:[^"]+)"/)?.[1]
        || null;
  } catch {
    return null;
  }
}

function signBundle(): void {
  const identity = resolveSigningIdentity();
  const entFlag = existsSync(entitlementsPath) ? ` --entitlements '${entitlementsPath}'` : "";
  const tempBinaryPath = `${binaryPath}.cstemp`;

  try {
    if (existsSync(tempBinaryPath)) rmSync(tempBinaryPath, { force: true });
  } catch {}

  if (identity) {
    console.log(`Signing with: ${identity}`);
    try {
      execSync(
        `codesign --force --sign '${identity}'${entFlag} --identifier com.arach.lattices '${bundlePath}'`,
        { stdio: "pipe" }
      );
      return;
    } catch {
      console.log(`Warning: signing with '${identity}' failed — falling back to ad-hoc.`);
    }
  } else {
    console.log("Warning: no local signing identity found — falling back to ad-hoc.");
  }

  execSync(
    `codesign --force --sign -${entFlag} --identifier com.arach.lattices '${bundlePath}'`,
    { stdio: "pipe" }
  );

  try {
    if (existsSync(tempBinaryPath)) rmSync(tempBinaryPath, { force: true });
  } catch {}
}

type BundleBuildMetadata = {
  channel?: "dev" | "release";
  track?: string;
  revision?: string;
  timestamp?: string;
};

function buildMetadataPlist(metadata: BundleBuildMetadata): string {
  if (metadata.channel !== "dev") return "";

  const track = metadata.track ?? "latest";
  const revision = metadata.revision ?? gitRevision();
  const timestamp = metadata.timestamp ?? new Date().toISOString();

  return `    <key>LatticesBuildChannel</key>
    <string>dev</string>
    <key>LatticesBuildTrack</key>
    <string>${xmlEscape(track)}</string>
    <key>LatticesBuildRevision</key>
    <string>${xmlEscape(revision)}</string>
    <key>LatticesBuildTimestamp</key>
    <string>${xmlEscape(timestamp)}</string>
`;
}

function writeInfoPlist(metadata: BundleBuildMetadata = {}): void {
  mkdirSync(resolve(bundlePath, "Contents"), { recursive: true });
  const version = packageVersion();
  const buildMetadata = buildMetadataPlist(metadata);
  const plist = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.arach.lattices</string>
    <key>CFBundleName</key>
    <string>Lattices</string>
    <key>CFBundleDisplayName</key>
    <string>Lattices</string>
    <key>CFBundleExecutable</key>
    <string>Lattices</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.arach.lattices</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>lattices</string>
            </array>
        </dict>
    </array>
    <key>CFBundleVersion</key>
    <string>${version}</string>
    <key>CFBundleShortVersionString</key>
    <string>${version}</string>
${buildMetadata}    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
</dict>
</plist>
`;
  writeFileSync(resolve(bundlePath, "Contents/Info.plist"), plist);
}

function syncBundleResources(): void {
  mkdirSync(resourcesDir, { recursive: true });
  if (existsSync(iconPath)) {
    execSync(`cp '${iconPath}' '${resolve(resourcesDir, "AppIcon.icns")}'`);
  }
  if (existsSync(tapSoundPath)) {
    execSync(`cp '${tapSoundPath}' '${resolve(resourcesDir, "tap.wav")}'`);
  }
}

// ── Build from source (current arch only) ────────────────────────────

function buildFromSource(): boolean {
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
  writeInfoPlist({ channel: "dev", track: "latest" });
  syncBundleResources();

  // Re-sign the bundle so macOS TCC recognizes a stable identity across rebuilds.
  // Prefer a real local signing identity; only fall back to ad-hoc when necessary.
  try {
    signBundle();
  } catch {
    // Non-fatal — app still works, just permissions won't persist across rebuilds
    console.log("Warning: code signing failed — permissions may not persist across rebuilds.");
  }
  // Update bundle timestamp so Finder shows the correct modified date
  try { execSync(`touch '${bundlePath}'`, { stdio: "pipe" }); } catch {}
  console.log("Build complete.");
  return true;
}

// ── Download from GitHub releases ────────────────────────────────────

function httpsGet(url: string): Promise<IncomingMessage> {
  return new Promise((resolve, reject) => {
    get(url, { headers: { "User-Agent": "lattices" } }, (res) => {
      if (res.statusCode! >= 300 && res.statusCode! < 400 && res.headers.location) {
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

async function downloadToFile(url: string, destination: string): Promise<void> {
  const res = await httpsGet(url);
  const ws = createWriteStream(destination);
  await new Promise<void>((resolve, reject) => {
    res.pipe(ws);
    ws.on("finish", resolve);
    ws.on("error", reject);
  });
}

function installBundleFromDmg(dmgPath: string): void {
  const mountPoint = mkdtempSync(join(tmpdir(), "lattices-mount-"));
  try {
    execSync(`hdiutil attach -nobrowse -readonly -mountpoint '${mountPoint}' '${dmgPath}'`, { stdio: "pipe" });
    const mountedBundle = resolve(mountPoint, "Lattices.app");
    if (!existsSync(mountedBundle)) {
      throw new Error("Lattices.app not found in mounted disk image");
    }
    rmSync(bundlePath, { recursive: true, force: true });
    execSync(`cp -R '${mountedBundle}' '${bundlePath}'`);
  } finally {
    try {
      execSync(`hdiutil detach '${mountPoint}' -quiet`, { stdio: "pipe" });
    } catch {}
    rmSync(mountPoint, { recursive: true, force: true });
  }
}

async function download(): Promise<boolean> {
  console.log("Downloading pre-built lattices app...");

  try {
    const apiUrl = `https://api.github.com/repos/${REPO}/releases/latest`;
    const apiRes = await httpsGet(apiUrl);
    const chunks: Buffer[] = [];
    for await (const chunk of apiRes) chunks.push(chunk as Buffer);
    const release = JSON.parse(Buffer.concat(chunks).toString());

    const assets: ReleaseAsset[] = Array.isArray(release.assets) ? release.assets : [];
    const appAsset = assets.find((a) =>
      RELEASE_APP_ASSET_NAMES.includes(a.name) || (a.name.endsWith(".dmg") && a.name.startsWith("Lattices"))
    );
    if (appAsset) {
      const tempDir = mkdtempSync(join(tmpdir(), "lattices-download-"));
      const dmgPath = resolve(tempDir, appAsset.name);
      try {
        await downloadToFile(appAsset.browser_download_url, dmgPath);
        installBundleFromDmg(dmgPath);
      } finally {
        rmSync(tempDir, { recursive: true, force: true });
      }
      console.log("Download complete.");
      return true;
    }

    const binaryAsset = assets.find((a) => RELEASE_BINARY_ASSET_NAMES.includes(a.name));
    if (!binaryAsset) throw new Error("App bundle not found in release assets");

    mkdirSync(binaryDir, { recursive: true });
    await downloadToFile(binaryAsset.browser_download_url, binaryPath);
    chmodSync(binaryPath, 0o755);
    writeInfoPlist();
    syncBundleResources();
    console.log("Download complete.");
    return true;
  } catch (e) {
    console.log(`Download failed: ${(e as Error).message}`);
    return false;
  }
}

// ── Commands ─────────────────────────────────────────────────────────

async function ensureBinary(): Promise<void> {
  if (existsSync(binaryPath)) return;

  const downloaded = await download();
  if (downloaded) return;

  console.error(
    "Could not find a bundled lattices app or download one.\n" +
    "Options:\n" +
    "  \u2022 Reinstall or update @lattices/cli\n" +
    "  \u2022 Developers can build from source with: lattices-app build\n" +
    "  \u2022 Download manually from:   https://github.com/" + REPO + "/releases"
  );
  process.exit(1);
}

function spawnDetachedUpdateWorker(extraArgs: string[] = [], shouldLaunch = false): void {
  const workerArgs = [
    selfScriptPath,
    "update",
    "--worker",
    ...(shouldLaunch ? ["--launch"] : []),
    ...extraArgs,
  ];
  const child = spawn(process.execPath, workerArgs, {
    cwd: cliRoot,
    detached: true,
    stdio: "ignore",
  });
  child.unref();
}

async function updateApp(extraArgs: string[] = [], shouldLaunch = false): Promise<void> {
  const wasRunning = isRunning();
  if (wasRunning) {
    quit();
  }

  const downloaded = await download();
  if (!downloaded) {
    console.error("Update failed.");
    if (wasRunning || shouldLaunch || extraArgs.length > 0) {
      launch(extraArgs);
    }
    process.exit(1);
  }

  relaunchIfNeeded(shouldLaunch || wasRunning || extraArgs.length > 0, extraArgs);
}

const cmd = process.argv[2];
const flags = process.argv.slice(3);
const launchFlags: string[] = [];
if (flags.includes("--diagnostics") || flags.includes("-d")) launchFlags.push("--diagnostics");
if (flags.includes("--screen-map") || flags.includes("-m")) launchFlags.push("--screen-map");
const shouldLaunchAfterUpdate = flags.includes("--launch") || launchFlags.length > 0;
const shouldDetachUpdate = flags.includes("--detach");
const isUpdateWorker = flags.includes("--worker");

if (cmd === "build") {
  if (!hasSwift()) {
    console.error("Swift is required. Install with: xcode-select --install");
    process.exit(1);
  }
  if (!buildFromSource()) {
    console.error("Build failed.");
    process.exit(1);
  }
} else if (cmd === "quit") {
  if (quit()) {
    console.log("lattices app stopped.");
  } else {
    console.log("lattices app is not running.");
  }
} else if (cmd === "restart") {
  // Quit → rebuild → relaunch
  quit();
  if (!hasSwift()) {
    console.error("Swift is required. Install with: xcode-select --install");
    process.exit(1);
  }
  if (!buildFromSource()) {
    console.error("Build failed.");
    process.exit(1);
  }
  launch(launchFlags);
} else if (cmd === "update") {
  if (shouldDetachUpdate && !isUpdateWorker) {
    spawnDetachedUpdateWorker(launchFlags, shouldLaunchAfterUpdate);
    console.log("lattices app update started.");
  } else {
    await updateApp(launchFlags, shouldLaunchAfterUpdate);
  }
} else {
  await ensureBinary();
  launch(launchFlags);
}
