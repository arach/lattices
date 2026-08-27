#!/usr/bin/env bun

import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { join } from "node:path";
import { port } from "./mira-chrome.mjs";

const repoRoot = fileURLToPath(new URL("../../..", import.meta.url));
const cdpScript = join(repoRoot, "native/engine/scripts/mira-midjourney-cdp.mjs");
const castPath = join(repoRoot, "assets/characters/cast.json");
const outDir = join(repoRoot, "assets/characters/midjourney/page-review");
const debugPort = String(port);

function harvest() {
  const result = spawnSync("bun", [cdpScript, "harvest", "--debug-port", debugPort], { encoding: "utf8" });
  const start = result.stdout.indexOf("{");
  return JSON.parse(result.stdout.slice(start));
}

function buildPrompt(cast, species, exercise, poseSet) {
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
  const format = poseSet.format ?? species.format ?? "full-body";
  const template = cast.templates[format] ?? cast.templates["full-body"];
  const [pose1, pose2, pose3, pose4] = poseSet.poses ?? [];
  return template
    .replace("{subject}", species.subject)
    .replace("{pose1}", pose1)
    .replace("{pose2}", pose2)
    .replace("{pose3}", pose3)
    .replace("{pose4}", pose4)
    .replace("{accessory}", poseSet.accessory ?? exercise.accessory ?? "");
}

function loadCastSpec() {
  const cast = JSON.parse(readFileSync(castPath, "utf8"));
  const speciesById = Object.fromEntries(cast.species.map((s) => [s.id, s]));
  const exercises = cast.exercises ?? cast.candidates ?? [];
  const byJobHint = new Map();
  const expectedPrompt = new Map();

  for (const exercise of exercises) {
    if (exercise.jobHint) {
      byJobHint.set(exercise.jobHint.slice(0, 8), exercise.id);
      byJobHint.set(exercise.jobHint, exercise.id);
    }
    const species = speciesById[exercise.species];
    const poseSet = exercise.poseSet ? cast.poses?.[exercise.poseSet] : null;
    if (!species || (!exercise.pose && !poseSet)) continue;
    expectedPrompt.set(exercise.id, buildPrompt(cast, species, exercise, poseSet));
  }
  return { cast, speciesById, exercises, byJobHint, expectedPrompt };
}

function guessExercise(prompt, { speciesById, exercises, cast }) {
  const p = prompt.toLowerCase();
  if (/logo mark|abstract capital a/.test(p)) {
    return { exerciseId: "brand-logo", label: "Brand logo", species: "logo", tests: ["failure-detect"] };
  }

  let speciesId = "unknown";
  if (/hamster/.test(p)) speciesId = "hamster";
  else if (/polar bear|ice-pack harness/.test(p)) speciesId = "polar-bear";
  else if (/\bbrown bear\b|honey bear|honey pot satchel/.test(p)) speciesId = "brown-bear";
  else if (/\bbear\b/.test(p)) speciesId = "brown-bear";
  else if (/\bcrocodile\b|swamp guard|swamp ranger/.test(p)) speciesId = "crocodile";
  else if (/\balligator\b|bayou ranger/.test(p)) speciesId = "alligator";
  else if (/\bgiraffe\b|lookout giraffe/.test(p)) speciesId = "giraffe";
  else if (/\belephant\b|trail elephant/.test(p)) speciesId = "elephant";
  else if (/\blion\b|savanna sentinel/.test(p)) speciesId = "lion";
  else if (/\btiger\b|jungle stalker/.test(p)) speciesId = "tiger";
  else if (/\bwolf\b|night runner/.test(p)) speciesId = "wolf";
  else if (/\bdeer\b|meadow wanderer/.test(p)) speciesId = "deer";
  else if (/\bmoose\b|pine trailblazer/.test(p)) speciesId = "moose";
  else if (/\bbadger\b|burrow digger/.test(p)) speciesId = "badger";
  else if (/\bpenguin\b|ice dockhand/.test(p)) speciesId = "penguin";
  else if (/\braccoon\b|alley mechanic/.test(p)) speciesId = "raccoon";
  else if (/\bhedgehog\b|garden scholar/.test(p)) speciesId = "hedgehog";
  else if (/\bcapybara\b|river lounger/.test(p)) speciesId = "capybara";
  else if (/\beagle\b|cliff scout/.test(p)) speciesId = "eagle";
  else if (/\bfrog\b|pond caller|tree frog/.test(p)) speciesId = "frog";
  else if (/\bturtle\b|tortoise|shell courier/.test(p)) speciesId = "turtle";
  else if (/\bzebra\b|plains messenger/.test(p)) speciesId = "zebra";
  else if (/\bkoala\b|eucalyptus ranger/.test(p)) speciesId = "koala";
  else if (/\bflamingo\b|salt flat guide/.test(p)) speciesId = "flamingo";
  else if (/\bgoat\b|mountain climber|mountain goat/.test(p)) speciesId = "goat";
  else if (/terrier|scruffy.*dog/.test(p)) speciesId = "terrier";
  else if (/\bfox\b/.test(p)) speciesId = "fox";
  else if (/young woman|short dark hair/.test(p)) speciesId = /shoulders up only|busts arranged/.test(p) ? "girl-bust" : "girl";
  else if (/young man|curly brown hair/.test(p)) speciesId = /shoulders up only|busts arranged/.test(p) ? "boy-bust" : "boy";
  else if (/red panda|ranger bandana/.test(p)) speciesId = "red-panda";
  else if (/sea otter|dock mechanic/.test(p)) speciesId = "sea-otter";
  else if (/\brabbit\b|lop-eared/.test(p)) speciesId = "rabbit";
  else if (/\bowl\b|barn owl/.test(p)) speciesId = "owl";
  else if (/\bfox\b|rust-red/.test(p)) speciesId = "fox";
  else if (/trail scout|braided chestnut/.test(p)) speciesId = "trail-scout";
  else if (/cartographer|desert cartographer/.test(p)) speciesId = "cartographer";
  else if (/arctic researcher|white parka/.test(p)) speciesId = "arctic-researcher";
  else if (/skyship|deckhand/.test(p)) speciesId = "skyship-deckhand";
  else if (/jungle guide|machete/.test(p)) speciesId = "jungle-guide";
  else if (/magical girl|star wand/.test(p)) speciesId = "magical-girl";
  else if (/sword student|hakama|bokken/.test(p)) speciesId = "sword-student";
  else if (/mecha pilot|flight jumpsuit/.test(p)) speciesId = "mecha-pilot";
  else if (/schoolgirl|sailor uniform/.test(p)) speciesId = "school-walker";
  else if (/hooded rogue|chibi hooded/.test(p)) speciesId = "hooded-rogue";
  else if (/elf archer|pointed ears/.test(p)) speciesId = "elf-archer";
  else if (/retro robot|robot companion/.test(p)) speciesId = "retro-robot";
  else if (/explorer cat|striped cat|steampunk aviator/.test(p)) speciesId = "explorer-cat";

  let poseSetId = "idle-row";
  if (/monocle|clipboard|observe alert/.test(p)) poseSetId = "scout-row";
  else if (/orbital ring|bridge connected|navigate stepping/.test(p)) poseSetId = "relay-row";
  else if (/tally|clapper|countdown|recording with/.test(p)) poseSetId = "director-row";
  else if (/sleep curled|walk right profile/.test(p)) poseSetId = "dock-row";
  else if (/neutral bust|busy bust|error bust/.test(p)) poseSetId = "bust-row";

  const match = exercises.find((e) => e.species === speciesId && e.poseSet === poseSetId)
    ?? exercises.find((e) => e.species === speciesId);
  if (match) {
    return {
      exerciseId: match.id,
      label: match.label,
      species: match.species,
      tests: match.tests,
    };
  }

  return {
    exerciseId: speciesId === "unknown" ? "unknown" : `${speciesId}-${poseSetId}`,
    label: speciesById[speciesId]?.label ?? speciesId,
    species: speciesId,
    tests: [],
  };
}

function classify(size) {
  const [w, h] = size.split("x").map(Number);
  if (!w || !h) return "unknown";
  const ratio = w / h;
  if (ratio >= 2.5) return "sprite-row";
  if (ratio < 1.2) return "square";
  return "wide";
}

async function download(url, path) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`download failed ${response.status}`);
  writeFileSync(path, Buffer.from(await response.arrayBuffer()));
}

const { cast, speciesById, exercises, byJobHint, expectedPrompt } = loadCastSpec();
const data = harvest();
const failed = new Set((data.failedJobs ?? []).map((f) => f.jobId));
const promptByJob = new Map((data.jobCards ?? []).map((card) => [card.id, card.prompt ?? ""]));

const byJob = new Map();
for (const result of data.results ?? []) {
  const id = result.href.match(/jobs\/([^?]+)/)?.[1];
  if (!id) continue;
  if (!byJob.has(id)) byJob.set(id, []);
  byJob.get(id).push(result);
}

mkdirSync(outDir, { recursive: true });
const manifest = [];

for (const [id, tiles] of [...byJob.entries()].sort((a, b) => b[1][0].rect.y - a[1][0].rect.y)) {
  let prompt = promptByJob.get(id) ?? "";
  const hintedId = byJobHint.get(id) ?? byJobHint.get(id.slice(0, 8));
  const guessed = guessExercise(prompt, { speciesById, exercises, cast });
  const exerciseId = hintedId ?? guessed.exerciseId;
  const exercise = exercises.find((e) => e.id === exerciseId);
  if (!prompt && exerciseId && expectedPrompt.has(exerciseId)) prompt = expectedPrompt.get(exerciseId);

  const entry = {
    id,
    exerciseId,
    castId: exerciseId,
    label: exercise?.label ?? guessed.label,
    species: exercise?.species ?? guessed.species,
    tests: exercise?.tests ?? guessed.tests ?? [],
    status: failed.has(id) ? "failed" : "ok",
    prompt,
    kind: null,
    tiles: [],
    jobUrl: `https://www.midjourney.com/jobs/${id}`,
  };

  for (const tile of tiles.sort((a, b) => Number(a.href.match(/index=(\d+)/)?.[1]) - Number(b.href.match(/index=(\d+)/)?.[1]))) {
    const idx = tile.href.match(/index=(\d+)/)?.[1] ?? "0";
    const url = tile.imageUrl.replace("_640_", "_1024_");
    const file = `${id.slice(0, 8)}-${idx}.webp`;
    const path = join(outDir, file);
    if (!existsSync(path)) await download(url, path);
    const size = spawnSync("magick", ["identify", "-format", "%wx%h", path], { encoding: "utf8" }).stdout.trim();
    const kind = classify(size);
    entry.tiles.push({ index: Number(idx), file, size, kind, url, job: tile.href });
    if (!entry.kind || kind === "sprite-row") entry.kind = kind;
  }

  if (entry.kind === "sprite-row" && entry.exerciseId === "unknown") {
    entry.exerciseId = "baseline-cat";
    entry.castId = "baseline-cat";
    entry.label = "Baseline cat + reference";
    entry.species = "explorer-cat";
  }
  manifest.push(entry);
}

writeFileSync(join(outDir, "manifest.json"), `${JSON.stringify(manifest, null, 2)}\n`);
console.log(`Synced ${manifest.length} jobs → ${outDir}`);
for (const job of manifest) {
  const label = `${job.label ?? job.species ?? "?"}`;
  console.log(`  ${job.status.padEnd(6)} ${job.kind?.padEnd(10) ?? ""} ${label.padEnd(28)} ${job.id.slice(0, 8)}`);
}