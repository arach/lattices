#!/usr/bin/env bun

import { mkdir, writeFile } from "node:fs/promises";
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { join } from "node:path";
import { port, activateMiraProcess, miraChromePid } from "./mira-chrome.mjs";
import { canonicalPortraitFor, portraitNums } from "./cast-portrait.mjs";

const repoRoot = fileURLToPath(new URL("../../..", import.meta.url));
const cdpScript = join(repoRoot, "native/engine/scripts/mira-midjourney-cdp.mjs");
const castDir = join(repoRoot, "assets/characters/cast");
const actionsPath = join(repoRoot, "assets/characters/cast-actions.json");
const outputDir = join(repoRoot, "assets/characters/cast/animations");
const debugPort = String(port);
const args = process.argv.slice(2);
const timeoutMs = String(process.env.ACTION_CAST_ANIMATE_TIMEOUT_MS || 600000);

function argValue(flag) {
  const index = args.indexOf(flag);
  return index === -1 ? undefined : args[index + 1];
}

const only = args.includes("--only")
  ? args[args.indexOf("--only") + 1]?.split(",").map((entry) => entry.trim()).filter(Boolean)
  : undefined;

function runCdp(command, extraArgs = []) {
  const result = spawnSync("bun", [cdpScript, command, "--debug-port", debugPort, ...extraArgs], {
    encoding: "utf8",
    env: { ...process.env, ACTION_MIRA_DEBUG_PORT: debugPort },
  });
  const jsonStart = result.stdout.indexOf("{");
  const jsonEnd = result.stdout.lastIndexOf("}");
  if (jsonStart === -1 || jsonEnd === -1) {
    throw new Error(result.stderr || result.stdout || `CDP ${command} failed`);
  }
  return JSON.parse(result.stdout.slice(jsonStart, jsonEnd + 1));
}

function portraitEntry(num) {
  const portrait = canonicalPortraitFor(repoRoot, num);
  if (!portrait) return null;
  let jobId = portrait.jobId;
  if (!jobId && portrait.href) {
    jobId = portrait.href.match(/jobs\/([^?]+)/)?.[1];
  }
  if (!jobId) {
    const pageReview = join(repoRoot, "assets/characters/midjourney/page-review/manifest.json");
    try {
      const review = JSON.parse(readFileSync(pageReview, "utf8"));
      const match = review.find((item) => item.species === portrait.speciesId && item.status === "ok");
      jobId = match?.id;
    } catch {
      /* ok */
    }
  }
  return { num: portrait.num, filename: portrait.filename, speciesId: portrait.speciesId, jobId };
}

async function download(url, destPath) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`Download failed ${response.status}`);
  await writeFile(destPath, Buffer.from(await response.arrayBuffer()));
}

async function main() {
  const actions = JSON.parse(readFileSync(actionsPath, "utf8"));
  const motions = actions.motionPrompts ?? ["gentle idle loop, pixel art character"];
  await mkdir(outputDir, { recursive: true });
  try { activateMiraProcess(miraChromePid()); } catch { /* ok */ }

  const nums = portraitNums(repoRoot, only);

  const manifest = [];
  for (const num of nums) {
    const entry = portraitEntry(num);
    if (!entry?.jobId) {
      console.warn(`skip ${num}: no job id (run sync-mj-page after portraits)`);
      continue;
    }
    for (const [motionIndex, motion] of motions.entries()) {
      console.log(`\n=== animate ${num} motion ${motionIndex + 1} ===`);
      console.log(motion);
      try {
        const animate = runCdp("animate", [
          "--job-id", entry.jobId,
          "--job-index", "0",
          "--motion-prompt", motion,
          "--timeout-ms", timeoutMs,
        ]);
        const wait = await new Promise((resolve) => {
          const started = Date.now();
          const poll = () => {
            const result = spawnSync("bun", [cdpScript, "harvest", "--debug-port", debugPort], { encoding: "utf8" });
            const json = JSON.parse(result.stdout.slice(result.stdout.indexOf("{"), result.stdout.lastIndexOf("}") + 1));
            const video = (json.results || []).find((r) => /\/video\/|\.mp4/i.test(r.imageUrl || ""));
            if (video?.imageUrl) return resolve(video);
            if (Date.now() - started > Number(timeoutMs)) return resolve(null);
            setTimeout(poll, 5000);
          };
          poll();
        });
        if (!wait?.imageUrl) {
          manifest.push({ num, motionIndex: motionIndex + 1, motion, status: "timeout" });
          continue;
        }
        const slug = motion.slice(0, 24).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "");
        const filename = `${num}-animate-${motionIndex + 1}-${slug}.mp4`;
        const dest = join(outputDir, filename);
        await download(wait.imageUrl, dest);
        console.log(`saved ${filename}`);
        manifest.push({ num, motionIndex: motionIndex + 1, motion, status: "ok", filename, href: wait.href, imageUrl: wait.imageUrl });
      } catch (error) {
        console.warn(error.message || error);
        manifest.push({ num, motionIndex: motionIndex + 1, motion, status: "failed", error: String(error.message || error) });
      }
    }
  }

  await writeFile(join(outputDir, "manifest.json"), `${JSON.stringify(manifest, null, 2)}\n`);
  console.log(`\nDone → ${outputDir}`);
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});