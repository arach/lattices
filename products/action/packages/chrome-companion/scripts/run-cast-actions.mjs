#!/usr/bin/env bun

import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { join } from "node:path";
import { canonicalPortraitFor, portraitNums } from "./cast-portrait.mjs";

const rootPath = fileURLToPath(new URL("..", import.meta.url));
const repoRoot = fileURLToPath(new URL("../../..", import.meta.url));
const runner = join(rootPath, "scripts/run-brand-prompts.mjs");
const generate = join(rootPath, "scripts/generate-cast-actions-prompts.mjs");
const promptsFile = join(repoRoot, "assets/characters/midjourney-cast-actions-prompts.txt");
const outputDir = join(repoRoot, "assets/characters/cast/actions");
const userArgs = process.argv.slice(2);
const foreground = userArgs.includes("--foreground");
const backgroundArgs = foreground ? [] : ["--background"];

const only = userArgs.includes("--only")
  ? userArgs[userArgs.indexOf("--only") + 1]?.split(",").map((entry) => entry.trim())
  : undefined;

spawnSync("bun", [generate], { stdio: "inherit" });

const cdpPrepare = join(repoRoot, "native/engine/scripts/mira-midjourney-cdp.mjs");
if (!userArgs.includes("--skip-prepare")) {
  console.log(foreground ? "preparing Midjourney composer..." : "preparing Midjourney composer (background, no focus steal)...");
  spawnSync("bun", [cdpPrepare, "prepare", ...(foreground ? [] : ["--background"])], {
    stdio: "inherit",
    env: foreground ? process.env : { ...process.env, ACTION_MJ_BACKGROUND: "1" },
  });
}

let failed = 0;
let first = true;
for (const num of portraitNums(repoRoot, only)) {
  const portrait = canonicalPortraitFor(repoRoot, num);
  if (!portrait?.path) {
    console.warn(`skip ${num}: no canonical portrait in assets/characters/cast/`);
    failed += 1;
    continue;
  }
  const refLabel = portrait.crefUrl ? "cdn cref" : "file cref";
  console.log(`\n>>> ${num} actions — reference ${portrait.filename} (${portrait.source}, ${refLabel})`);
  const referenceArgs = portrait.crefUrl
    ? ["--reference-url", portrait.crefUrl]
    : ["--reference-file", portrait.path];
  const phaseArgs = [
    runner,
    "--prompts-file", promptsFile,
    "--output-dir", outputDir,
    ...referenceArgs,
    ...backgroundArgs,
    "--min-fresh", "4",
    "--pick", "4",
    "--retries", "1",
    "--min-wait-ms", "5000",
    "--only", num,
    ...userArgs.filter((arg, index, args) => {
      const prev = args[index - 1];
      const passthroughFlags = new Set([
        "--only",
        "--foreground",
        "--background",
        "--wait",
        "--no-wait",
        "--submit-only",
        "--collect",
        "--wait-only",
        "--fail-fast",
        "--no-resume",
        "--dry-run",
        "--skip-prepare",
        "--no-reference",
      ]);
      if (passthroughFlags.has(arg)) return false;
      if (prev && passthroughFlags.has(prev)) return false;
      return true;
    }),
  ];
  if (!first && !userArgs.includes("--skip-prepare")) {
    phaseArgs.push("--skip-prepare");
  }
  first = false;
  const result = spawnSync("bun", phaseArgs, { stdio: "inherit" });
  if (result.status !== 0) {
    failed += 1;
    console.warn(`character ${num} finished with failures — continuing batch`);
  }
}

if (failed === 0) {
  spawnSync("bun", [join(rootPath, "scripts/sync-mj-page.mjs")], { stdio: "inherit" });
} else {
  console.warn(`\nBatch complete with ${failed} character(s) that had failures. Re-run with the same --only to resume skipped prompts.`);
}

process.exit(failed > 0 ? 1 : 0);