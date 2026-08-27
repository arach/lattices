#!/usr/bin/env bun

import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { join } from "node:path";
import { canonicalPortraitFor, portraitNums } from "./cast-portrait.mjs";

const rootPath = fileURLToPath(new URL("..", import.meta.url));
const repoRoot = fileURLToPath(new URL("../../..", import.meta.url));
const runner = join(rootPath, "scripts/run-brand-prompts.mjs");
const generate = join(rootPath, "scripts/generate-cast-variations-prompts.mjs");
const promptsFile = join(repoRoot, "assets/characters/midjourney-cast-variations-prompts.txt");
const outputDir = join(repoRoot, "assets/characters/cast/variations");
const userArgs = process.argv.slice(2);
const foreground = userArgs.includes("--foreground");
const backgroundArgs = foreground ? [] : ["--background"];

const only = userArgs.includes("--only")
  ? userArgs[userArgs.indexOf("--only") + 1]?.split(",").map((entry) => entry.trim())
  : undefined;

spawnSync("bun", [generate], { stdio: "inherit" });

let failed = 0;
let first = true;
for (const num of portraitNums(repoRoot, only)) {
  const portrait = canonicalPortraitFor(repoRoot, num);
  if (!portrait?.path) {
    console.warn(`skip ${num}: no canonical portrait`);
    failed += 1;
    continue;
  }
  const refLabel = portrait.crefUrl ? "cdn cref" : "file cref";
  console.log(`\n>>> ${num} variations — reference ${portrait.filename} (${portrait.source}, ${refLabel})`);
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
    "--retries", "0",
    "--min-wait-ms", "5000",
    "--only", num,
    ...userArgs.filter((arg, index, args) =>
      arg !== "--only" && args[index - 1] !== "--only" && arg !== "--foreground" && arg !== "--background"),
  ];
  if (!first && !userArgs.includes("--skip-prepare")) {
    phaseArgs.push("--skip-prepare");
  }
  first = false;
  const result = spawnSync("bun", phaseArgs, { stdio: "inherit" });
  if (result.status !== 0) failed += 1;
}

if (failed === 0) {
  spawnSync("bun", [join(rootPath, "scripts/sync-mj-page.mjs")], { stdio: "inherit" });
}

process.exit(failed > 0 ? 1 : 0);