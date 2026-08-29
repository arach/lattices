#!/usr/bin/env bun

import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { join } from "node:path";

const repoRoot = fileURLToPath(new URL("../../..", import.meta.url));
const specPath = join(repoRoot, "assets/characters/actor-prompts.json");
const outPath = join(repoRoot, "assets/characters/midjourney-actor-prompts.txt");

const spec = JSON.parse(readFileSync(specPath, "utf8"));

function buildPrompt(actor) {
  const [pose1, pose2, pose3, pose4] = actor.poses ?? ["idle", "thinking", "working", "done"];
  return spec.template
    .replace("{pose1}", pose1)
    .replace("{pose2}", pose2)
    .replace("{pose3}", pose3)
    .replace("{pose4}", pose4)
    .replace("{accessory}", actor.accessory ?? "");
}

const lines = [
  `Action actor sprite rows — ${spec.style}, --ar ${spec.aspectRatio}, black background`,
  `Reference: ${spec.reference}`,
  "",
];

spec.actors.forEach((actor, index) => {
  const num = String(index + 1).padStart(2, "0");
  const label = `${actor.displayName} (${actor.project})`;
  lines.push(`${num} ${label}`);
  lines.push(buildPrompt(actor));
  lines.push("");
});

writeFileSync(outPath, `${lines.join("\n").trim()}\n`);
console.log(`Wrote ${spec.actors.length} actor prompts → ${outPath}`);