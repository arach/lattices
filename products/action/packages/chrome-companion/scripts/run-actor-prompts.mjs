#!/usr/bin/env bun

import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { join } from "node:path";

const rootPath = fileURLToPath(new URL("..", import.meta.url));
const repoRoot = fileURLToPath(new URL("../../..", import.meta.url));
const runner = join(rootPath, "scripts/run-brand-prompts.mjs");
const promptsFile = join(repoRoot, "assets/characters/midjourney-actor-prompts.txt");
const outputDir = join(repoRoot, "assets/characters/actors");

const result = spawnSync("bun", [
  runner,
  "--prompts-file", promptsFile,
  "--output-dir", outputDir,
  "--min-fresh", "4",
  "--pick", "4",
  ...process.argv.slice(2),
], { stdio: "inherit" });

if (result.status === 0) {
  spawnSync("bun", [join(rootPath, "scripts/sync-mj-page.mjs")], { stdio: "inherit" });
}

process.exit(result.status ?? 1);