#!/usr/bin/env bun

import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { join } from "node:path";

const repoRoot = fileURLToPath(new URL("../../..", import.meta.url));
const castPath = join(repoRoot, "assets/characters/cast.json");
const outPath = join(repoRoot, "assets/characters/midjourney-cast-prompts.txt");

const cast = JSON.parse(readFileSync(castPath, "utf8"));
const speciesById = Object.fromEntries(cast.species.map((s) => [s.id, s]));
const exercises = cast.exercises ?? cast.candidates ?? [];

function buildPrompt(exercise) {
  const species = speciesById[exercise.species];
  if (!species) throw new Error(`Missing species for ${exercise.id}`);

  if (exercise.prompt) {
    return exercise.prompt;
  }

  if (exercise.pose) {
    const format = species.format ?? "portrait";
    const template = cast.templates[format] ?? cast.templates.portrait;
    const poseClause = exercise.pose ? `, ${exercise.pose}` : "";
    return template
      .replace("{subject}", species.subject)
      .replace("{poseClause}", poseClause)
      .replace("{accessory}", exercise.accessory ?? "");
  }

  const poseSet = cast.poses?.[exercise.poseSet] ?? cast.roles?.find((r) => r.id === exercise.role);
  if (!poseSet) throw new Error(`Missing poseSet for ${exercise.id}`);
  const format = poseSet.format ?? species.format ?? "full-body";
  const template = cast.templates[format] ?? cast.templates["full-body"];
  const [pose1, pose2, pose3, pose4] = poseSet.poses ?? ["idle", "thinking", "working", "done"];
  return template
    .replace("{subject}", species.subject)
    .replace("{pose1}", pose1)
    .replace("{pose2}", pose2)
    .replace("{pose3}", pose3)
    .replace("{pose4}", pose4)
    .replace("{accessory}", poseSet.accessory ?? exercise.accessory ?? "");
}

const lines = [
  `Animal cast one-offs — ${cast.recipe ?? "midjourney-create"} · ${cast.style}, --ar ${cast.aspectRatio}`,
  cast.description ?? "One portrait per character. Species from prompt text only.",
  "",
];

exercises.forEach((exercise, index) => {
  const species = speciesById[exercise.species];
  const num = String(index + 1).padStart(2, "0");
  const tests = (exercise.tests ?? []).join(", ");
  const label = `${exercise.label} · ${species?.label ?? exercise.species}`;
  lines.push(`${num} ${label}`);
  lines.push(buildPrompt(exercise));
  if (tests) lines.push(`# tests: ${tests}`);
  if (exercise.notes) lines.push(`# ${exercise.notes}`);
  lines.push("");
});

writeFileSync(outPath, `${lines.join("\n").trim()}\n`);
console.log(`Wrote ${exercises.length} cast prompts → ${outPath}`);