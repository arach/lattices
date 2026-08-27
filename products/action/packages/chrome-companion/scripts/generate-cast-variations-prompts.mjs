#!/usr/bin/env bun

import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { join } from "node:path";

const repoRoot = fileURLToPath(new URL("../../..", import.meta.url));
const castPath = join(repoRoot, "assets/characters/cast.json");
const actionsPath = join(repoRoot, "assets/characters/cast-actions.json");
const outPath = join(repoRoot, "assets/characters/midjourney-cast-variations-prompts.txt");

const cast = JSON.parse(readFileSync(castPath, "utf8"));
const actions = JSON.parse(readFileSync(actionsPath, "utf8"));
const speciesById = Object.fromEntries(cast.species.map((s) => [s.id, s]));
const exercises = cast.exercises ?? [];
const template = cast.templates.portrait;

const variationPrefix = actions.variationPrefix
  ?? "same character design outfit colors and face as the reference portrait, only the pose changes:";

const lines = [
  "Cast portrait variations — midjourney-create · pixel-art-portrait, --ar 1:1",
  "Reference: canonical portrait from assets/characters/cast/ per character (--cref)",
  "",
];

exercises.forEach((exercise, index) => {
  const species = speciesById[exercise.species];
  if (!species) return;
  const num = String(index + 1).padStart(2, "0");
  for (const [poseIndex, pose] of (actions.variationPoses ?? []).entries()) {
    const prompt = template
      .replace("{subject}", species.subject)
      .replace("{poseClause}", `, ${variationPrefix} ${pose}`)
      .replace("{accessory}", exercise.accessory ?? "");
    lines.push(`${num}-v${poseIndex + 1} ${species.label} · variation ${poseIndex + 1}`);
    lines.push(prompt);
    lines.push("");
  }
});

writeFileSync(outPath, `${lines.join("\n").trim()}\n`);
console.log(`Wrote ${lines.filter((l) => /^\d{2}-v/.test(l)).length} variation prompts → ${outPath}`);