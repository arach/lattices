#!/usr/bin/env bun

import { existsSync } from "node:fs";
import { mkdir, writeFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { dirname, extname, resolve } from "node:path";

const HELP = `
Create an editor-friendly app-window plate over a solid chroma matte.

Usage:
  bun scripts/chroma-window-video.mjs \\
    --input capture.mp4 \\
    --output capture.chroma.mp4 \\
    [--key-color 00FF00] \\
    [--canvas 1920x1080] \\
    [--padding 96] \\
    [--fps 30] \\
    [--metadata capture.chroma.json]

The companion JSON records the exact key color and window rectangle so a
renderer can key or reframe the plate without rediscovering its geometry.
`.trim();

function fail(message) {
  console.error(`chroma-window-video: ${message}`);
  process.exit(1);
}

function readOption(name, fallback) {
  const index = process.argv.indexOf(`--${name}`);
  if (index === -1) return fallback;
  const value = process.argv[index + 1];
  if (!value || value.startsWith("--")) fail(`--${name} requires a value`);
  return value;
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    encoding: "utf8",
    stdio: options.capture ? ["ignore", "pipe", "pipe"] : "inherit",
  });
  if (result.error) fail(`${command} is unavailable: ${result.error.message}`);
  if (result.status !== 0) {
    const detail = options.capture ? result.stderr.trim() : `exit ${result.status}`;
    fail(`${command} failed${detail ? `: ${detail}` : ""}`);
  }
  return result.stdout?.trim() ?? "";
}

function evenFloor(value) {
  return Math.max(2, Math.floor(value / 2) * 2);
}

if (process.argv.includes("--help") || process.argv.includes("-h")) {
  console.log(HELP);
  process.exit(0);
}

const inputPath = resolve(readOption("input"));
const outputPath = resolve(readOption("output"));
const keyColor = readOption("key-color", "00FF00").replace(/^#/, "").toUpperCase();
const canvas = readOption("canvas", "1920x1080");
const padding = Number(readOption("padding", "96"));
const fps = Number(readOption("fps", "30"));
const metadataPath = resolve(
  readOption("metadata", `${outputPath.slice(0, -extname(outputPath).length)}.chroma.json`),
);

if (!existsSync(inputPath)) fail(`input does not exist: ${inputPath}`);
if (!/^[0-9A-F]{6}$/.test(keyColor)) fail("--key-color must be a six-digit hex color");
if (!Number.isFinite(padding) || padding < 0) fail("--padding must be zero or greater");
if (!Number.isFinite(fps) || fps <= 0) fail("--fps must be greater than zero");

const canvasMatch = /^(\d+)x(\d+)$/.exec(canvas);
if (!canvasMatch) fail("--canvas must use WIDTHxHEIGHT, for example 1920x1080");
const canvasWidth = Number(canvasMatch[1]);
const canvasHeight = Number(canvasMatch[2]);
if (canvasWidth % 2 || canvasHeight % 2) fail("--canvas dimensions must be even");

const probe = JSON.parse(
  run(
    "ffprobe",
    [
      "-v",
      "error",
      "-select_streams",
      "v:0",
      "-show_entries",
      "stream=width,height,r_frame_rate,codec_name:format=duration",
      "-of",
      "json",
      inputPath,
    ],
    { capture: true },
  ),
);
const source = probe.streams?.[0];
const duration = Number(probe.format?.duration);
if (!source?.width || !source?.height || !Number.isFinite(duration)) {
  fail("ffprobe did not return usable video dimensions and duration");
}

const availableWidth = canvasWidth - padding * 2;
const availableHeight = canvasHeight - padding * 2;
if (availableWidth < 2 || availableHeight < 2) fail("padding leaves no room for the app window");

const scale = Math.min(1, availableWidth / source.width, availableHeight / source.height);
const windowWidth = evenFloor(source.width * scale);
const windowHeight = evenFloor(source.height * scale);
const windowX = Math.floor((canvasWidth - windowWidth) / 2);
const windowY = Math.floor((canvasHeight - windowHeight) / 2);

await mkdir(dirname(outputPath), { recursive: true });
await mkdir(dirname(metadataPath), { recursive: true });

const filter = [
  `[1:v]fps=${fps},scale=${windowWidth}:${windowHeight}:flags=lanczos,setsar=1[window]`,
  `[0:v][window]overlay=${windowX}:${windowY}:shortest=1:format=auto[out]`,
].join(";");

run("ffmpeg", [
  "-y",
  "-f",
  "lavfi",
  "-i",
  `color=c=0x${keyColor}:s=${canvasWidth}x${canvasHeight}:r=${fps}:d=${duration}`,
  "-i",
  inputPath,
  "-filter_complex",
  filter,
  "-map",
  "[out]",
  "-map",
  "1:a?",
  "-c:v",
  "libx264",
  "-preset",
  "slow",
  "-crf",
  "18",
  "-pix_fmt",
  "yuv420p",
  "-c:a",
  "aac",
  "-movflags",
  "+faststart",
  outputPath,
]);

const metadata = {
  schema: "action.chroma-window/v1",
  source: {
    path: inputPath,
    width: source.width,
    height: source.height,
    duration,
    frameRate: source.r_frame_rate,
    codec: source.codec_name,
  },
  plate: {
    path: outputPath,
    width: canvasWidth,
    height: canvasHeight,
    frameRate: fps,
    keyColor: `#${keyColor}`,
    windowRect: {
      x: windowX,
      y: windowY,
      width: windowWidth,
      height: windowHeight,
    },
  },
};

await writeFile(metadataPath, `${JSON.stringify(metadata, null, 2)}\n`);
console.log(JSON.stringify({ outputPath, metadataPath, ...metadata.plate }, null, 2));
