#!/usr/bin/env bun

import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

export function exerciseForNum(repoRoot, num) {
  const padded = String(num).padStart(2, "0");
  const cast = JSON.parse(readFileSync(join(repoRoot, "assets/characters/cast.json"), "utf8"));
  const exercise = (cast.exercises ?? [])[Number(padded) - 1];
  return { padded, cast, exercise, speciesId: exercise?.species };
}

export function canonicalPortraitFor(repoRoot, num) {
  const { padded, exercise, speciesId } = exerciseForNum(repoRoot, num);
  const castDir = join(repoRoot, "assets/characters/cast");
  const manifestPath = join(castDir, "manifest.json");

  if (exercise?.portraitFile) {
    const explicit = exercise.portraitFile.startsWith("/")
      ? exercise.portraitFile
      : join(repoRoot, exercise.portraitFile);
    if (existsSync(explicit)) {
      return buildEntry(padded, speciesId, explicit, exercise);
    }
  }

  const files = readdirSync(castDir)
    .filter((name) => name.startsWith(`${padded}-`) && name.endsWith(".webp") && !name.includes("sprite-row") && !name.includes("-v"))
    .sort();
  const preferred = files.find((name) => name.endsWith("-1.webp")) ?? files[0];
  if (!preferred) return null;

  const path = join(castDir, preferred);
  let saved;
  if (existsSync(manifestPath)) {
    const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
    const entry = manifest.find((item) => item.id === padded || item.id === String(Number(padded)));
    saved = entry?.saved?.find((item) => item.filename === preferred) ?? entry?.saved?.[0];
  }

  return {
    num: padded,
    speciesId,
    path,
    filename: preferred,
    href: saved?.href ?? exercise?.portraitHref,
    crefUrl: normalizeCrefUrl(saved?.imageUrl),
    jobId: (saved?.href ?? exercise?.portraitHref)?.match(/jobs\/([^?]+)/)?.[1]
      ?? exercise?.jobHint
      ?? exercise?.portraitJobId,
    source: saved ? "manifest" : "disk",
  };
}

export function normalizeCrefUrl(imageUrl) {
  if (!imageUrl || !/cdn\.midjourney\.com/i.test(imageUrl)) return undefined;
  return imageUrl.split("?")[0];
}

function buildEntry(num, speciesId, path, exercise) {
  return {
    num,
    speciesId,
    path,
    filename: path.split("/").pop(),
    href: exercise?.portraitHref,
    crefUrl: normalizeCrefUrl(exercise?.portraitCrefUrl),
    jobId: exercise?.portraitJobId ?? exercise?.jobHint,
    source: "exercise",
  };
}

export function portraitNums(repoRoot, only) {
  if (only?.length) {
    return only.map((entry) => String(entry).trim().padStart(2, "0"));
  }
  return [...new Set(
    readdirSync(join(repoRoot, "assets/characters/cast"))
      .filter((name) => /^\d{2}-/.test(name) && name.endsWith(".webp") && !name.includes("sprite-row") && !name.includes("-v"))
      .map((name) => name.slice(0, 2)),
  )].sort();
}