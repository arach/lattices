#!/usr/bin/env node
// Thin shim: exec the bundled native `blink` CLI (dist/blink), passing through
// args, stdio, and exit code. Kept in Node so it runs without bun.
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { existsSync } from "node:fs";

const here = dirname(fileURLToPath(import.meta.url));
const bin = join(here, "..", "dist", "blink");
const appInstaller = join(here, "blink-app.mjs");

if (process.platform !== "darwin") {
  console.error("@arach/blink runs on macOS only.");
  process.exit(1);
}
if (process.arch !== "arm64") {
  console.error(
    "This build of blink is Apple Silicon (arm64) only.\n" +
      "Intel support is coming; for now build from source: https://github.com/arach/blink"
  );
  process.exit(1);
}
if (!existsSync(bin)) {
  console.error("blink binary missing (expected dist/blink). Try reinstalling @arach/blink.");
  process.exit(1);
}

try {
  if (process.argv[2] === "app") {
    execFileSync(process.execPath, [appInstaller, ...process.argv.slice(3)], {
      stdio: "inherit",
    });
  } else {
    execFileSync(bin, process.argv.slice(2), { stdio: "inherit" });
  }
} catch (error) {
  // Surface the child's exit status; execFileSync throws on non-zero.
  process.exit(typeof error.status === "number" ? error.status : 1);
}
