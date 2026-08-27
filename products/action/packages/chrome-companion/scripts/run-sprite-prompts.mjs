#!/usr/bin/env bun

import { spawnSync } from "node:child_process";
import { mkdir, writeFile } from "node:fs/promises";
import { mkdtempSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { port, activateMiraProcess, miraChromePid } from "./mira-chrome.mjs";

const repoRoot = fileURLToPath(new URL("../../..", import.meta.url));
const cdpScript = join(repoRoot, "native/engine/scripts/mira-midjourney-cdp.mjs");
const promptsFile = join(repoRoot, "assets/characters/midjourney-sprite-prompts.txt");
const referenceFile = join(repoRoot, "assets/pets/explorer-cat/sprites/explorer-cat.v0.frames.png");
const outputDir = join(repoRoot, "assets/characters/sprites");
const debugPort = String(port);
const args = process.argv.slice(2);

function argValue(flag) {
  const index = args.indexOf(flag);
  return index === -1 ? undefined : args[index + 1];
}

const only = args.includes("--only")
  ? args[args.indexOf("--only") + 1]?.split(",").map((entry) => entry.trim()).filter(Boolean)
  : undefined;
const skipReference = args.includes("--no-reference");
const timeoutMs = String(process.env.ACTION_SPRITE_PROMPT_TIMEOUT_MS || 600000);

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function parsePrompts(text) {
  const blocks = [];
  let current;
  for (const line of text.split("\n")) {
    const heading = line.match(/^(\d{2})\s+(.+)$/);
    if (heading) {
      if (current?.prompt) blocks.push(current);
      current = { id: heading[1], title: heading[2], prompt: "" };
      continue;
    }
    if (!current) continue;
    const trimmed = line.trim();
    if (!trimmed || /^Action sprite|^Use reference:|^Contract:/i.test(trimmed)) continue;
    current.prompt = current.prompt ? `${current.prompt} ${trimmed}` : trimmed;
  }
  if (current?.prompt) blocks.push(current);
  return blocks;
}

function runCdp(command, extraArgs = []) {
  const result = spawnSync("bun", [cdpScript, command, "--debug-port", debugPort, ...extraArgs], {
    encoding: "utf8",
    env: { ...process.env, ACTION_MIRA_DEBUG_PORT: debugPort },
  });
  if (result.status !== 0 && command !== "submit") {
    throw new Error(result.stderr || result.stdout || `CDP ${command} failed`);
  }
  const jsonStart = result.stdout.indexOf("{");
  const jsonEnd = result.stdout.lastIndexOf("}");
  if (jsonStart === -1 || jsonEnd === -1) {
    return { raw: result.stdout, status: result.status };
  }
  return { ...JSON.parse(result.stdout.slice(jsonStart, jsonEnd + 1)), status: result.status };
}

async function imageShape(path) {
  const probe = spawnSync("magick", ["identify", "-format", "%w %h", path], { encoding: "utf8" });
  if (probe.status !== 0) return null;
  const [width, height] = probe.stdout.trim().split(/\s+/).map(Number);
  return { width, height, aspect: width / height };
}

async function downloadResult(url, destPath) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`Download failed ${response.status} for ${url}`);
  await writeFile(destPath, Buffer.from(await response.arrayBuffer()));
}

async function main() {
  const promptText = await Bun.file(promptsFile).text();
  let prompts = parsePrompts(promptText);
  if (only?.length) prompts = prompts.filter((entry) => only.includes(entry.id));
  if (prompts.length === 0) throw new Error("No sprite prompts matched.");

  await mkdir(outputDir, { recursive: true });
  try { activateMiraProcess(miraChromePid()); } catch { /* already frontmost */ }

  const manifest = [];
  for (const entry of prompts) {
    console.log(`\n=== ${entry.id} ${entry.title} ===`);
    const before = runCdp("harvest");
    const baselineDir = mkdtempSync(join(tmpdir(), "action-sprite-baseline-"));
    const baselineFile = join(baselineDir, "baseline.json");
    await writeFile(baselineFile, JSON.stringify(before.results?.map((r) => r.href) ?? []));

    let prompt = entry.prompt;
    const submitArgs = [];
    if (!skipReference) submitArgs.push("--reference-file", referenceFile);
    submitArgs.push("--prompt", prompt);
    console.log(skipReference ? "submitting (no reference)..." : "submitting with explorer-cat reference...");
    const submit = runCdp("submit", submitArgs);
    if (submit.reference?.ok === false) {
      console.warn(`reference attach failed: ${submit.reference.reason ?? "unknown"}`);
    } else if (submit.reference?.crefUrl) {
      console.log(`reference url: ${submit.reference.crefUrl}`);
    }

    console.log("waiting for 4-up sprite row...");
    const wait = spawnSync("bun", [
      cdpScript, "wait-new",
      "--debug-port", debugPort,
      "--timeout-ms", timeoutMs,
      "--baseline-file", baselineFile,
      "--min-fresh", "4",
    ], { encoding: "utf8", env: { ...process.env, ACTION_MIRA_DEBUG_PORT: debugPort } });

    if (wait.status !== 0) {
      console.error(wait.stdout || wait.stderr);
      manifest.push({ id: entry.id, title: entry.title, status: "failed", saved: [] });
      continue;
    }

    const waitPayload = JSON.parse(wait.stdout.slice(wait.stdout.indexOf("{"), wait.stdout.lastIndexOf("}") + 1));
    const fresh = waitPayload.fresh || [];
    const slug = entry.title.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "");
    const saved = [];

    for (const [index, result] of fresh.slice(0, 4).entries()) {
      if (!result.imageUrl) continue;
      const filename = `${entry.id}-${slug}-${index + 1}.webp`;
      const destPath = join(outputDir, filename);
      await downloadResult(result.imageUrl.replace("_640_", "_1024_"), destPath);
      const shape = await imageShape(destPath);
      const kind = shape && shape.aspect >= 2.5 ? "sprite-row" : shape && shape.aspect < 1.3 ? "logo-like" : "uncertain";
      if (kind === "logo-like") {
        console.warn(`  warn: ${filename} looks logo-like (${shape.width}x${shape.height})`);
      }
      saved.push({ filename, href: result.href, kind, ...shape });
      console.log(`saved ${filename} (${kind})`);
    }

    manifest.push({
      id: entry.id,
      title: entry.title,
      prompt: entry.prompt,
      status: saved.length ? "ok" : "failed",
      reference: skipReference ? null : referenceFile,
      saved,
    });
    await sleep(2000);
  }

  await writeFile(join(outputDir, "manifest.json"), `${JSON.stringify(manifest, null, 2)}\n`);
  console.log(`\nDone → ${outputDir}`);
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});