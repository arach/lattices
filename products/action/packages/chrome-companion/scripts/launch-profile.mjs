#!/usr/bin/env bun

import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const rootPath = fileURLToPath(new URL("..", import.meta.url));
const result = spawnSync("bun", ["scripts/profile.mjs", "launch", ...process.argv.slice(2)], {
  cwd: rootPath,
  stdio: "inherit",
});

process.exit(result.status ?? 1);
