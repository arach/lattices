#!/usr/bin/env node
// Install and manage the Blink menubar app. Installation downloads the latest
// signed DMG from GitHub and replaces /Applications/Blink.app without launching
// it; `open` is the explicit launch command.
import { execFileSync } from "node:child_process";
import {
  createWriteStream,
  existsSync,
  mkdtempSync,
  renameSync,
  rmSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { get } from "node:https";

const REPO = "arach/blink";
const APP_PATH = "/Applications/Blink.app";
const BUNDLE_ID = "dev.arach.blink";

function httpsGet(url) {
  return new Promise((resolvePromise, reject) => {
    get(url, { headers: { "User-Agent": "blink" } }, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        return httpsGet(res.headers.location).then(resolvePromise, reject);
      }
      if (res.statusCode !== 200) {
        res.resume();
        return reject(new Error(`HTTP ${res.statusCode} for ${url}`));
      }
      resolvePromise(res);
    }).on("error", reject);
  });
}

async function downloadTo(url, dest) {
  const res = await httpsGet(url);
  await new Promise((resolvePromise, reject) => {
    const ws = createWriteStream(dest);
    res.pipe(ws);
    ws.on("finish", resolvePromise);
    ws.on("error", reject);
  });
}

async function latestDmgUrl() {
  const res = await httpsGet(`https://api.github.com/repos/${REPO}/releases?per_page=30`);
  const chunks = [];
  for await (const chunk of res) chunks.push(chunk);
  const releases = JSON.parse(Buffer.concat(chunks).toString());
  const release = Array.isArray(releases)
    ? releases
        .filter(
          (candidate) =>
            !candidate.draft && /^v2(?:\.|$)/.test(candidate.tag_name ?? "")
        )
        // GitHub may surface its "latest" stable release ahead of a newer
        // prerelease, so make recency explicit instead of trusting API order.
        .sort((a, b) => {
          const publishedA =
            Date.parse(a.published_at ?? a.created_at ?? "") || 0;
          const publishedB =
            Date.parse(b.published_at ?? b.created_at ?? "") || 0;
          return publishedB - publishedA;
        })[0]
    : undefined;
  if (!release) throw new Error("no compatible Blink 2 release is available yet");
  const assets = Array.isArray(release.assets) ? release.assets : [];
  const dmg =
    assets.find((asset) => asset.name === "Blink.dmg") ??
    assets.find((asset) => /^Blink(?:-[\w.-]+)?\.dmg$/.test(asset.name));
  if (!dmg) throw new Error("no .dmg asset in the latest release");
  return dmg.browser_download_url;
}

function installFromDmg(dmgPath) {
  const mount = mkdtempSync(join(tmpdir(), "blink-mount-"));
  try {
    execFileSync(
      "spctl",
      [
        "--assess",
        "--type",
        "open",
        "--context",
        "context:primary-signature",
        dmgPath,
      ],
      { stdio: "pipe" }
    );
    execFileSync(
      "hdiutil",
      ["attach", "-nobrowse", "-readonly", "-mountpoint", mount, dmgPath],
      { stdio: "pipe" }
    );
    const mounted = resolve(mount, "Blink.app");
    if (!existsSync(mounted)) throw new Error("Blink.app not found in DMG");

    // Stage and validate the complete replacement on the destination volume
    // before touching the currently installed app.
    const transaction = mkdtempSync(join(dirname(APP_PATH), ".blink-install-"));
    const staged = join(transaction, "Blink.app");
    const backup = join(transaction, "Previous-Blink.app");
    let preserveTransaction = false;
    try {
      execFileSync("ditto", [mounted, staged], { stdio: "pipe" });
      execFileSync("codesign", ["--verify", "--deep", "--strict", staged], {
        stdio: "pipe",
      });
      const installedBundleID = execFileSync(
        "plutil",
        [
          "-extract",
          "CFBundleIdentifier",
          "raw",
          join(staged, "Contents", "Info.plist"),
        ],
        { encoding: "utf8" }
      ).trim();
      if (installedBundleID !== BUNDLE_ID) {
        throw new Error(`unexpected app bundle identifier: ${installedBundleID}`);
      }

      const hadExistingApp = existsSync(APP_PATH);
      if (hadExistingApp) renameSync(APP_PATH, backup);
      try {
        renameSync(staged, APP_PATH);
      } catch (error) {
        if (hadExistingApp && existsSync(backup)) {
          try {
            renameSync(backup, APP_PATH);
          } catch (restoreError) {
            preserveTransaction = true;
            throw new Error(
              `install failed and the previous app could not be restored; it remains at ${backup}: ${restoreError.message}`,
              { cause: error }
            );
          }
        }
        throw error;
      }
      rmSync(backup, { recursive: true, force: true });
    } finally {
      if (!preserveTransaction) {
        rmSync(transaction, { recursive: true, force: true });
      }
    }
  } finally {
    try {
      execFileSync("hdiutil", ["detach", mount, "-quiet"], { stdio: "pipe" });
    } catch {}
    rmSync(mount, { recursive: true, force: true });
  }
}

async function ensureInstalled(force, message) {
  if (existsSync(APP_PATH) && !force) return;
  console.log(message ?? "Installing Blink.app from the latest release…");
  const url = await latestDmgUrl();
  const dir = mkdtempSync(join(tmpdir(), "blink-dl-"));
  const dmg = join(dir, "Blink.dmg");
  try {
    await downloadTo(url, dmg);
    installFromDmg(dmg);
    console.log(`Installed ${APP_PATH}`);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

function launch() {
  execFileSync("open", ["-b", BUNDLE_ID], { stdio: "inherit" });
  console.log("Blink launched (menubar).");
}

if (process.platform !== "darwin") {
  console.error("@arach/blink runs on macOS only.");
  process.exit(1);
}

const cmd = process.argv[2];
try {
  if (cmd === "install") {
    await ensureInstalled(true, "Installing the latest compatible Blink 2 release…");
  } else if (cmd === "update") {
    await ensureInstalled(true, "Updating to the latest compatible Blink 2 release…");
  } else if (cmd === "open") {
    if (!existsSync(APP_PATH)) {
      throw new Error("Blink.app is not installed (run `blink app install` first)");
    }
    launch();
  } else if (cmd === "path") {
    console.log(APP_PATH);
  } else if (cmd === undefined) {
    await ensureInstalled(false, "Installing Blink.app from the latest release…");
    launch();
  } else {
    throw new Error(
      `unknown command '${cmd}' (expected install, update, open, or path)`
    );
  }
} catch (error) {
  console.error(`blink-app: ${error.message}`);
  console.error(`Download manually: https://github.com/${REPO}/releases`);
  process.exit(1);
}
