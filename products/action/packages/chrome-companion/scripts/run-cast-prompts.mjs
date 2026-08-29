#!/usr/bin/env bun

import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { join } from "node:path";

const rootPath = fileURLToPath(new URL("..", import.meta.url));
const repoRoot = fileURLToPath(new URL("../../..", import.meta.url));
const runner = join(rootPath, "scripts/run-brand-prompts.mjs");
const generate = join(rootPath, "scripts/generate-cast-prompts.mjs");
const castPath = join(repoRoot, "assets/characters/cast.json");
const promptsFile = join(repoRoot, "assets/characters/midjourney-cast-prompts.txt");
const outputDir = join(repoRoot, "assets/characters/cast");

spawnSync("bun", [generate], { stdio: "inherit" });

const cast = JSON.parse(readFileSync(castPath, "utf8"));
const referenceFile = cast.reference ? join(repoRoot, cast.reference) : undefined;
const userArgs = process.argv.slice(2);
const runnerArgs = [
  runner,
  "--prompts-file", promptsFile,
  "--output-dir", outputDir,
  "--retries", "0",
  ...userArgs,
];
if (!userArgs.includes("--min-fresh")) runnerArgs.push("--min-fresh", "1");
if (!userArgs.includes("--pick")) runnerArgs.push("--pick", "1");
if (!userArgs.includes("--min-wait-ms")) runnerArgs.push("--min-wait-ms", "5000");
if (referenceFile && userArgs.includes("--with-reference")) {
  runnerArgs.push("--reference-file", referenceFile);
}

const result = spawnSync("bun", runnerArgs, { stdio: "inherit" });

if (result.status === 0) {
  spawnSync("bun", [join(rootPath, "scripts/sync-mj-page.mjs")], { stdio: "inherit" });
}

process.exit(result.status ?? 1);