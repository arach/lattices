#!/usr/bin/env bun

import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { join } from "node:path";

const repoRoot = fileURLToPath(new URL("../../..", import.meta.url));
const castPath = join(repoRoot, "assets/characters/cast.json");
const animalsPath = join(repoRoot, "assets/characters/cast-animals.json");

const cast = JSON.parse(readFileSync(castPath, "utf8"));
const expansion = JSON.parse(readFileSync(animalsPath, "utf8"));
const existingIds = new Set(cast.species.map((entry) => entry.id));

let added = 0;
for (const animal of expansion.animals) {
  if (existingIds.has(animal.id)) continue;
  cast.species.push({
    id: animal.id,
    label: animal.label,
    kind: "animal",
    subject: animal.subject,
    format: "portrait",
  });
  cast.exercises.push({
    id: `cast-${animal.id}`,
    label: animal.label,
    tests: ["portrait-harvest", "sync"],
    species: animal.id,
    pose: animal.pose,
    status: "queued",
  });
  existingIds.add(animal.id);
  added += 1;
}

cast.schemaVersion = 5;
cast.description = "Portrait cast roster — original animals, adventure, manga, plus expanded animal zoo cast.";
writeFileSync(castPath, `${JSON.stringify(cast, null, 2)}\n`);
console.log(`Merged ${added} animals into cast.json (${cast.exercises.length} exercises total)`);