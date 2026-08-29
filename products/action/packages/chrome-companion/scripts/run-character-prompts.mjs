#!/usr/bin/env bun

import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { join } from "node:path";

const rootPath = fileURLToPath(new URL("..", import.meta.url));
const repoRoot = fileURLToPath(new URL("../../..", import.meta.url));
const runner = join(rootPath, "scripts/run-brand-prompts.mjs");
const promptsFile = join(repoRoot, "assets/characters/midjourney-prompts.txt");
const outputDir = join(repoRoot, "assets/characters/midjourney");

const result = spawnSync("bun", [
  runner,
  "--prompts-file", promptsFile,
  "--output-dir", outputDir,
  "--min-fresh", "1",
  "--pick", "1",
  ...process.argv.slice(2),
], { stdio: "inherit" });

process.exit(result.status ?? 1);