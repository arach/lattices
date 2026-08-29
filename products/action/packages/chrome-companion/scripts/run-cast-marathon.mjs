#!/usr/bin/env bun

import { appendFileSync, mkdirSync, existsSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { join } from "node:path";

const rootPath = fileURLToPath(new URL("..", import.meta.url));
const repoRoot = fileURLToPath(new URL("../../..", import.meta.url));
const logPath = join(repoRoot, "assets/characters/cast/marathon.log");

const args = process.argv.slice(2);
const phasesArg = args.includes("--phases")
  ? args[args.indexOf("--phases") + 1]?.split(",").map((p) => p.trim()).filter(Boolean)
  : undefined;

const sharedFlags = ["--min-wait-ms", "5000", "--skip-prepare"];

const phases = [
  {
    id: "animals-expansion",
    label: "Expanded animal zoo portraits 19–42 (4-up each)",
    script: "cast:prompts",
    args: ["--only", "19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42", "--pick", "4", "--min-fresh", "4", ...sharedFlags],
    prepare: true,
  },
  {
    id: "portraits-remaining",
    label: "Finish portraits 15–18 (4-up each)",
    script: "cast:prompts",
    args: ["--only", "15,16,17,18", "--pick", "4", "--min-fresh", "4", ...sharedFlags],
    prepare: false,
  },
  {
    id: "portraits-variations",
    label: "Portrait variations all characters (4-up each)",
    script: "cast:variations",
    args: ["--pick", "4", "--min-fresh", "4", ...sharedFlags],
    prepare: false,
  },
  {
    id: "action-rows",
    label: "Action sprite rows (7 sets × 18 chars, 4-up each)",
    script: "cast:actions",
    args: [...sharedFlags],
    prepare: false,
  },
  {
    id: "animate",
    label: "Animate portraits (4 motions × 18 chars)",
    script: "cast:animate",
    args: [],
    prepare: false,
  },
];

function log(line) {
  const stamp = new Date().toISOString();
  const text = `[${stamp}] ${line}\n`;
  process.stdout.write(text);
  appendFileSync(logPath, text);
}

function runPhase(phase) {
  log(`START ${phase.id}: ${phase.label}`);
  if (phase.prepare) {
    const cdp = join(repoRoot, "native/engine/scripts/mira-midjourney-cdp.mjs");
    spawnSync("bun", [cdp, "prepare"], { stdio: "inherit", cwd: join(rootPath) });
  }
  const result = spawnSync("bun", ["run", phase.script, ...phase.args], {
    stdio: "inherit",
    cwd: join(rootPath),
  });
  if (result.status !== 0) {
    log(`FAIL ${phase.id} exit=${result.status}`);
    return false;
  }
  log(`DONE ${phase.id}`);
  return true;
}

mkdirSync(join(repoRoot, "assets/characters/cast"), { recursive: true });
log("marathon begin");

const selected = phasesArg?.length
  ? phases.filter((phase) => phasesArg.includes(phase.id))
  : phases;

for (const phase of selected) {
  const ok = runPhase(phase);
  if (!ok && !args.includes("--continue-on-failure")) {
    log("marathon stopped on failure");
    process.exit(1);
  }
}

log("marathon complete");