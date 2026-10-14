#!/usr/bin/env bun
/**
 * lattices-build-env — declarative build-feature resolver.
 *
 * Mirrors openscout's `hkit` style: an app names *features* in a manifest
 * (apps/mac/build.json), never raw env vars. The feature → build-env mapping
 * lives in the catalog below, so every build entrypoint (package / dev / dist)
 * resolves the same way from one source of truth, instead of each hardcoding
 * its own `HUDSONKIT_WITH_*` flags.
 *
 *   import { resolveBuildEnv } from "./lattices-build-env";  // TS callers
 *   eval "$(bun bin/lattices-build-env.ts shell)"            // bash callers
 *   bun bin/lattices-build-env.ts json                       // inspect
 *
 * Both modes take an optional manifest path after the mode; the default is
 * apps/mac/build.json. Voice's package script passes products/voice/build.json.
 *
 * Tier: the manifest's `tier` ("free" | "bundle") picks which build this is;
 * LATTICES_TIER overrides it for one build. The bundle tier adds the `bundle`
 * feature, which compiles apps/mac/Sources/Bundle.
 */

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

// Feature catalog: feature name -> build env HudsonKit gates on at SwiftPM
// manifest-eval time. HudsonKit declares HudsonVoice (Vox/Parakeet dictation)
// unless HUDSONKIT_WITH_VOICE=0, which resolveBuildEnv sets for any app that
// doesn't name the voice feature. Name a *feature* here; never sprinkle the env
// var across build scripts.
export const FEATURE_CATALOG: Record<string, { env: Record<string, string>; note: string }> = {
  voice: { env: { HUDSONKIT_WITH_VOICE: "1" }, note: "HudsonVoice — Vox/Parakeet dictation" },
  bundle: { env: { LATTICES_BUNDLE: "1" }, note: "Bundle tier — compiles apps/mac/Sources/Bundle" },
};

export type BuildTier = "free" | "bundle";

export interface BuildManifest {
  app?: string;
  tier?: BuildTier;
  features?: string[];
}

const MANIFEST_PATH = join(import.meta.dir, "../apps/mac/build.json");

export function loadManifest(path = MANIFEST_PATH): BuildManifest {
  if (!existsSync(path)) return {};
  return JSON.parse(readFileSync(path, "utf8")) as BuildManifest;
}

export function resolveFeatureEnv(features: string[] = []): Record<string, string> {
  const env: Record<string, string> = {};
  for (const f of features) {
    const entry = FEATURE_CATALOG[f];
    if (!entry) {
      throw new Error(
        `unknown build feature "${f}" — known features: ${Object.keys(FEATURE_CATALOG).join(", ")}`,
      );
    }
    Object.assign(env, entry.env);
  }
  return env;
}

/** The tier to build: LATTICES_TIER, else the manifest's, else free. */
export function resolveTier(manifest: BuildManifest = loadManifest()): BuildTier {
  const tier = process.env.LATTICES_TIER || manifest.tier || "free";
  if (tier !== "free" && tier !== "bundle") {
    throw new Error(`unknown tier "${tier}" — use free or bundle`);
  }
  return tier;
}

/** Resolve the manifest's declared features (and tier) into a build-env map. */
export function resolveBuildEnv(manifestPath?: string): Record<string, string> {
  const manifest = loadManifest(manifestPath);
  const features = [...(manifest.features ?? [])];
  if (resolveTier(manifest) === "bundle" && !features.includes("bundle")) features.push("bundle");
  const env = resolveFeatureEnv(features);
  // HudsonKit enables HudsonVoice by default; opt out unless the voice feature is declared.
  if (!features.includes("voice")) {
    env.HUDSONKIT_WITH_VOICE = "0";
  }
  // Pin the free tier too, so a LATTICES_BUNDLE left in the shell can't leak in.
  if (!features.includes("bundle")) {
    env.LATTICES_BUNDLE = "0";
  }
  return env;
}

// --- CLI: emit the resolved env for shell / json consumers -------------------
if (import.meta.main) {
  const mode = process.argv[2] ?? "shell";
  const env = resolveBuildEnv(process.argv[3]);
  if (mode === "json") {
    console.log(JSON.stringify(env, null, 2));
  } else if (mode === "shell") {
    // eval-able by bash: `eval "$(bun bin/lattices-build-env.ts shell)"`
    for (const [k, v] of Object.entries(env)) console.log(`export ${k}=${JSON.stringify(v)}`);
  } else {
    console.error(`lattices-build-env: unknown mode "${mode}" (use: shell | json)`);
    process.exit(1);
  }
}
