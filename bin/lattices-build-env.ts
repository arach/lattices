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
 */

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

// Feature catalog: feature name -> build env HudsonKit gates on at SwiftPM
// manifest-eval time. HudsonVoice (Vox/Parakeet dictation) is an optional
// backend HudsonKit only declares when HUDSONKIT_WITH_VOICE=1 is set at build
// time. Name a *feature* here; never sprinkle the env var across build scripts.
export const FEATURE_CATALOG: Record<string, { env: Record<string, string>; note: string }> = {
  voice: { env: { HUDSONKIT_WITH_VOICE: "1" }, note: "HudsonVoice — Vox/Parakeet dictation" },
};

export interface BuildManifest {
  app?: string;
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

/** Resolve the manifest's declared features into a build-env map. */
export function resolveBuildEnv(manifestPath?: string): Record<string, string> {
  return resolveFeatureEnv(loadManifest(manifestPath).features ?? []);
}

// --- CLI: emit the resolved env for shell / json consumers -------------------
if (import.meta.main) {
  const mode = process.argv[2] ?? "shell";
  const env = resolveBuildEnv();
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
