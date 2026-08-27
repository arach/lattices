#!/usr/bin/env bun

import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { join } from "node:path";

const repoRoot = fileURLToPath(new URL("../../..", import.meta.url));
const castPath = join(repoRoot, "assets/characters/cast.json");
const actionsPath = join(repoRoot, "assets/characters/cast-actions.json");
const outPath = join(repoRoot, "assets/characters/midjourney-cast-actions-prompts.txt");

const cast = JSON.parse(readFileSync(castPath, "utf8"));
const actions = JSON.parse(readFileSync(actionsPath, "utf8"));
const speciesById = Object.fromEntries(cast.species.map((s) => [s.id, s]));
const exercises = cast.exercises ?? [];

const lines = [
  `Cast action sprite rows — ${actions.style}, --ar ${actions.aspectRatio}`,
  "Reference: canonical portrait per character (--cref --cw 100), same identity across all action rows",
  "",
];

exercises.forEach((exercise, index) => {
  const species = speciesById[exercise.species];
  if (!species) return;
  const num = String(index + 1).padStart(2, "0");
  const sets = [...actions.actionSets];
  const signature = actions.signatureActions?.[exercise.species];
  if (signature) sets.push(signature);

  for (const set of sets) {
    const prompt = actions.template
      .replace("{subject}", species.subject)
      .replace("{panels}", set.panels);
    lines.push(`${num}-${set.id} ${species.label} · ${set.label}`);
    lines.push(prompt);
    lines.push("");
  }
});

writeFileSync(outPath, `${lines.join("\n").trim()}\n`);
console.log(`Wrote ${lines.filter((l) => /^\d{2}-/.test(l)).length} action prompts → ${outPath}`);