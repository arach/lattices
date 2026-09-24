#!/usr/bin/env bun
/**
 * embedded-helpers — build helper apps into Lattices.app/Contents/Helpers and
 * sign them before the outer bundle (LAT-012 packaging).
 *
 * Each helper is assembled by its product's own packaging script, so the
 * embedded copy is the bundle the standalone recipe produces. That script
 * signs ad hoc; `signHelpers` re-signs with the identity used for Lattices.app.
 * Sign inside out: helpers first, then Lattices.app without --deep, because
 * --deep would re-sign the helpers with the outer identifier and entitlements.
 *
 *   import { embedHelpers, signHelpers } from "./embedded-helpers";   // TS callers
 *   bun bin/embedded-helpers.ts embed <Lattices.app>                    // bash callers
 *   bun bin/embedded-helpers.ts sign <Lattices.app> <identity> [--timestamp]
 *
 * LATTICES_SKIP_HELPERS=1 builds without helpers. Companion discovery then
 * falls back to standalone installs.
 */

import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, rmSync } from "node:fs";
import { join, resolve } from "node:path";

const root = resolve(import.meta.dir, "..");

type EmbeddedHelper = {
  /** Bundle name in Contents/Helpers, without `.app`. */
  name: string;
  /** Frozen bundle ID that companion discovery matches (CompanionBundleIdentifiers). */
  bundleIdentifier: string;
  /** Build the helper and leave `<name>.app`, signed ad hoc, in `outputDir`. */
  assemble(outputDir: string): void;
};

export const EMBEDDED_HELPERS: EmbeddedHelper[] = [
  {
    name: "Voice",
    bundleIdentifier: "dev.lattices.Speech",
    assemble(outputDir) {
      execFileSync("/bin/bash", [resolve(root, "products/voice/tools/package.sh")], {
        stdio: "inherit",
        env: {
          ...process.env,
          SPEECH_ARTIFACT_DIR: outputDir,
          SPEECH_BUILD_CONFIGURATION: "release",
          SPEECH_SIGN_IDENTITY: "-",
          SPEECH_DISTRIBUTABLE: "0",
          SPEECH_CREATE_DMG: "0",
        },
      });
    },
  },
];

export function helpersDirectory(bundlePath: string): string {
  return join(bundlePath, "Contents/Helpers");
}

function helperPath(bundlePath: string, helper: EmbeddedHelper): string {
  return join(helpersDirectory(bundlePath), `${helper.name}.app`);
}

function run(command: string, args: string[]): string {
  try {
    return execFileSync(command, args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
  } catch (error) {
    const stderr = (error as { stderr?: Buffer | string }).stderr;
    const detail = stderr ? `\n${String(stderr).trim()}` : "";
    throw new Error(`${command} ${args.join(" ")}${detail}`);
  }
}

/** Rebuild Contents/Helpers from scratch and check each helper's bundle ID. */
export function embedHelpers(bundlePath: string): void {
  const directory = helpersDirectory(bundlePath);
  // Start clean so no stale or half-staged helper is sealed into the bundle.
  rmSync(directory, { recursive: true, force: true });
  if (process.env.LATTICES_SKIP_HELPERS === "1") {
    console.log("Skipping embedded helpers because LATTICES_SKIP_HELPERS=1.");
    return;
  }
  mkdirSync(directory, { recursive: true });
  for (const helper of EMBEDDED_HELPERS) {
    console.log(`Embedding ${helper.name}.app...`);
    helper.assemble(directory);
    const app = helperPath(bundlePath, helper);
    const plist = join(app, "Contents/Info.plist");
    const identifier = existsSync(plist)
      ? run("/usr/bin/plutil", ["-extract", "CFBundleIdentifier", "raw", "-o", "-", plist]).trim()
      : "";
    if (identifier !== helper.bundleIdentifier) {
      throw new Error(`${app} has bundle ID "${identifier}", expected ${helper.bundleIdentifier}`);
    }
  }
}

/**
 * Sign each embedded helper with the identity used for Lattices.app. Call this
 * before signing the outer bundle. Release builds pass `timestamp`, which
 * notarization requires for nested code.
 */
export function signHelpers(bundlePath: string, identity: string, options: { timestamp?: boolean } = {}): void {
  for (const helper of EMBEDDED_HELPERS) {
    const app = helperPath(bundlePath, helper);
    if (!existsSync(app)) continue;
    const args = ["--force", "--options", "runtime"];
    if (options.timestamp) args.push("--timestamp");
    args.push("--sign", identity, app);
    run("/usr/bin/codesign", args);
  }
}

if (import.meta.main) {
  const [command, bundle, identity, ...flags] = process.argv.slice(2);
  if (command === "embed" && bundle) {
    embedHelpers(resolve(bundle));
  } else if (command === "sign" && bundle && identity) {
    signHelpers(resolve(bundle), identity, { timestamp: flags.includes("--timestamp") });
  } else {
    console.error("Usage: embedded-helpers.ts embed <Lattices.app>");
    console.error("       embedded-helpers.ts sign <Lattices.app> <identity> [--timestamp]");
    process.exit(1);
  }
}
