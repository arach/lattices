#!/usr/bin/env bun
/**
 * Slice a 4:1 Midjourney sprite row into individual frame PNGs (macOS sips).
 * Usage: bun run slice-sprite-row.mjs --input path/to/row.webp --output dir --frames 4
 */

import { mkdirSync } from "node:fs";
import { basename, join } from "node:path";
import { spawnSync as run } from "node:child_process";

const args = process.argv.slice(2);
function flag(name, fallback) {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : fallback;
}

const input = flag("--input", null);
const outputDir = flag("--output", null);
const frames = Number(flag("--frames", "4"));

if (!input || !outputDir) {
  console.error("Usage: slice-sprite-row.mjs --input <row.webp> --output <dir> [--frames 4]");
  process.exit(1);
}

mkdirSync(outputDir, { recursive: true });

const probe = run("magick", ["identify", "-format", "%w %h", input], { encoding: "utf8" });
if (probe.status !== 0) {
  console.error(probe.stderr || probe.stdout);
  process.exit(probe.status ?? 1);
}
const [width, height] = probe.stdout.trim().split(/\s+/).map(Number);
const frameWidth = Math.floor(width / frames);
const stem = basename(input).replace(/\.[^.]+$/, "");

for (let i = 0; i < frames; i++) {
  const out = join(outputDir, `${stem}-frame-${i + 1}.png`);
  const crop = run("magick", [
    input,
    "-crop", `${frameWidth}x${height}+${i * frameWidth}+0`,
    "+repage",
    out,
  ], { encoding: "utf8" });
  if (crop.status !== 0) {
    console.error(crop.stderr || crop.stdout);
    process.exit(crop.status ?? 1);
  }
  console.log(out);
}