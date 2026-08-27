#!/usr/bin/env bun

import { mkdir, readFile, writeFile, appendFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const root = fileURLToPath(new URL("../../..", import.meta.url));
const logoRoot = join(root, "assets/brand/project-logos");
const outputDir = join(logoRoot, "midjourney");
const statePath = join(logoRoot, "sprint-state.json");
const logPath = join(logoRoot, "sprint.log");
const brandRunner = join(root, "packages/chrome-companion/scripts/run-brand-prompts.mjs");
const analyzeRunner = join(root, "packages/chrome-companion/scripts/run-logo-analyze-loop.mjs");
const cdpPrepare = join(root, "native/engine/scripts/mira-midjourney-cdp.mjs");

const args = process.argv.slice(2);
const batchSize = Number(argValue("--batch") || process.env.ACTION_LOGO_BATCH_SIZE || "3");
const intervalMs = Number(argValue("--interval-ms") || process.env.ACTION_LOGO_INTERVAL_MS || "600000");
const maxCycles = Number(argValue("--max-cycles") || process.env.ACTION_LOGO_MAX_CYCLES || "0");
const once = args.includes("--once");
const dryRun = args.includes("--dry-run");
const skipAnalyze = args.includes("--skip-analyze");
const analyzeEvery = Number(argValue("--analyze-every") || process.env.ACTION_LOGO_ANALYZE_EVERY || "2");
const maxIdleCycles = Number(argValue("--max-idle-cycles") || process.env.ACTION_LOGO_MAX_IDLE_CYCLES || "6");

function argValue(flag) {
  const index = args.indexOf(flag);
  return index >= 0 ? args[index + 1] : undefined;
}

async function loadJson(path, fallback) {
  if (!existsSync(path)) return fallback;
  return JSON.parse(await readFile(path, "utf8"));
}

async function saveState(state) {
  state.updatedAt = new Date().toISOString();
  await writeFile(statePath, `${JSON.stringify(state, null, 2)}\n`);
}

async function loadDirectionPool() {
  const pools = ["directions.json", "directions-round2.json", "directions-round3.json", "directions-round4.json"];
  const merged = [];
  for (const name of pools) {
    const path = join(logoRoot, name);
    if (!existsSync(path)) continue;
    const items = await loadJson(path, []);
    merged.push(...items);
  }
  return merged;
}

function formatPromptBlock(seq, direction) {
  const id = `${String(seq).padStart(2, "0")}-${direction.directionId}`;
  return `${id} ${direction.project} — ${direction.title}\n${direction.mjPrompt}\n`;
}

async function logLine(message) {
  const line = `[${new Date().toISOString()}] ${message}\n`;
  await appendFile(logPath, line);
  console.log(message);
}

async function prepareComposer() {
  if (dryRun) return { ok: true, dryRun: true };
  const result = spawnSync("bun", [cdpPrepare, "prepare", "--background"], {
    encoding: "utf8",
    env: { ...process.env, ACTION_MJ_BACKGROUND: "1" },
  });
  if (result.status !== 0) {
    return { ok: false, error: result.stderr || result.stdout || "prepare failed" };
  }
  try {
    const payload = JSON.parse(result.stdout);
    if (!payload.ready) {
      return { ok: false, error: "prepare finished but composer not ready (profile chip?)" };
    }
    return { ok: true };
  } catch {
    return { ok: true };
  }
}

async function submitBatch(ids, promptsText) {
  const batchFile = join(logoRoot, "batch-prompts.txt");
  await writeFile(batchFile, `Project logo sprint batch\n\n${promptsText}`);
  if (dryRun) {
    await logLine(`dry-run: would submit ${ids.join(", ")}`);
    return { ok: true, dryRun: true };
  }

  let failures = 0;
  for (const id of ids) {
    const prepared = await prepareComposer();
    if (!prepared.ok) {
      failures += 1;
      await logLine(`prepare failed before ${id}: ${prepared.error}`);
      continue;
    }
    const result = spawnSync("bun", [
      brandRunner,
      "--no-wait",
      "--background",
      "--no-reference",
      "--no-resume",
      "--skip-prepare",
      "--prompts-file", batchFile,
      "--output-dir", outputDir,
      "--only", id,
    ], {
      cwd: join(root, "packages/chrome-companion"),
      encoding: "utf8",
      env: { ...process.env, ACTION_MJ_BACKGROUND: "1" },
    });
    if (result.status !== 0) {
      failures += 1;
      await logLine(`submit failed for ${id}: ${result.stderr || result.stdout}`);
      continue;
    }
    await logLine(`submitted: ${id}`);
  }
  return failures === 0 ? { ok: true } : { ok: false, error: `${failures}/${ids.length} failed` };
}

async function runAnalyzePass(state) {
  if (skipAnalyze || dryRun) return state;
  await logLine("analyze pass: collect + vision review + refinements");
  const result = spawnSync("bun", [analyzeRunner], {
    cwd: join(root, "packages/chrome-companion"),
    encoding: "utf8",
    env: { ...process.env, ACTION_MJ_BACKGROUND: "1" },
  });
  if (result.status !== 0) {
    await logLine(`analyze pass failed: ${result.stderr || result.stdout}`);
    return state;
  }
  state.analyzeRuns = (state.analyzeRuns ?? 0) + 1;
  state.lastAnalyzeAt = new Date().toISOString();
  return state;
}

async function runCycle(state, pool) {
  const pending = pool.filter((direction) => !state.submittedIds.includes(direction.directionId));
  if (pending.length === 0) {
    state.idleCycles = (state.idleCycles ?? 0) + 1;
    await logLine(`pool exhausted (${state.idleCycles}/${maxIdleCycles}) — waiting for directions-round4.json, etc.`);
    return state;
  }
  state.idleCycles = 0;

  const batch = pending.slice(0, batchSize);
  const blocks = [];
  const ids = [];
  let seq = state.nextSeq;

  for (const direction of batch) {
    blocks.push(formatPromptBlock(seq, direction));
    ids.push(`${String(seq).padStart(2, "0")}-${direction.directionId}`);
    seq += 1;
  }
  state.nextSeq = seq;

  await logLine(`cycle ${state.cycles + 1}: queuing ${ids.length} prompt(s)`);
  const outcome = await submitBatch(ids, blocks.join("\n"));
  if (outcome.ok) {
    for (const direction of batch) {
      state.submittedIds.push(direction.directionId);
    }
    state.cycles += 1;
    state.lastBatchIds = ids;
  } else {
    state.nextSeq -= batch.length;
  }
  return state;
}

async function main() {
  await mkdir(logoRoot, { recursive: true });
  await mkdir(outputDir, { recursive: true });

  let state = await loadJson(statePath, {
    nextSeq: 19,
    cycles: 0,
    submittedIds: [],
    lastBatchIds: [],
    analyzeRuns: 0,
  });

  let pool = await loadDirectionPool();
  const alreadySubmitted = new Set([
    ...state.submittedIds,
    "atelier-forge", "atelier-dovetail",
    "openscout-open-ring", "openscout-dispatch-hub",
    "studio-index", "studio-blueprint-rail",
    "hudson-dock", "hudson-dotted-canvas",
    "talkie-beam", "talkie-memo-card",
    "lattices-tiling-grid", "lattices-split-map",
    "missionwriter-dispatch-stamp", "missionwriter-synthesis",
    "linea-margin", "linea-folio-leaf",
    "fabric-weave", "fabric-envelope",
  ]);
  state.submittedIds = [...new Set([...state.submittedIds, ...alreadySubmitted])];

  await logLine(`logo sprint loop start (batch=${batchSize}, interval=${Math.round(intervalMs / 1000)}s, pool=${pool.length})`);

  let cyclesRun = 0;
  do {
    pool = await loadDirectionPool();
    state = await runCycle(state, pool);
    if (analyzeEvery > 0 && state.cycles > 0 && state.cycles % analyzeEvery === 0) {
      state = await runAnalyzePass(state);
    }
    await saveState(state);
    cyclesRun += 1;
    if (once) break;
    if (maxCycles > 0 && cyclesRun >= maxCycles) break;
    if (maxIdleCycles > 0 && (state.idleCycles ?? 0) >= maxIdleCycles) {
      await logLine(`stopping after ${state.idleCycles} idle cycle(s) — add directions-round4.json or restart sprint`);
      break;
    }
    await logLine(`sleeping ${Math.round(intervalMs / 1000)}s`);
    await Bun.sleep(intervalMs);
    Object.assign(state, await loadJson(statePath, state));
  } while (true);

  await logLine("logo sprint loop stopped");
}

main().catch(async (error) => {
  await logLine(`fatal: ${error.message || String(error)}`);
  process.exitCode = 1;
});