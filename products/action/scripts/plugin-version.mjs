#!/usr/bin/env bun
/**
 * Keep the action-browser plugin version identical across every manifest.
 *
 * Harnesses cache installed plugin metadata — skills, interface copy, MCP server
 * entry — by version. Bumping one manifest and not the others is what leaves a
 * Claude Code or Kimi install serving stale tool text after the server has moved
 * on, so this is a release gate rather than a convenience.
 *
 *   bun run plugin:version            # check that every manifest agrees
 *   bun run plugin:version -- 0.3.0   # set them all
 */

import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const actionRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");

/** Every file that carries the plugin version, and how to read/write it. */
const targets = [
  jsonTarget("../../.claude-plugin/marketplace.json", ["plugins", 0, "version"]),
  jsonTarget("../../kimi.plugin.json", ["version"]),
  jsonTarget(".claude-plugin/marketplace.json", ["plugins", 0, "version"]),
  jsonTarget("plugins/action-browser/.claude-plugin/plugin.json", ["version"]),
  jsonTarget("plugins/action-browser/.codex-plugin/plugin.json", ["version"]),
  jsonTarget("plugins/action-browser/kimi.plugin.json", ["version"]),
  jsonTarget("kimi.plugin.json", ["version"]),
  sourceTarget(
    "plugins/action-browser/server/index.ts",
    /(const SERVER_VERSION = ")([^"]+)(")/,
  ),
];

/**
 * Read through the parsed document, but write by patching the raw text: these
 * manifests are hand-formatted and re-serializing them produces a diff nobody
 * asked for. Every manifest here carries exactly one "version" key.
 */
function jsonTarget(path, keyPath) {
  return sourceTarget(path, /("version"\s*:\s*")([^"]+)(")/, (text) =>
    keyPath.reduce((node, key) => node?.[key], JSON.parse(text)));
}

function sourceTarget(path, pattern, read) {
  return {
    path,
    read: read ?? ((text) => text.match(pattern)?.[2]),
    write(text, version) {
      return text.replace(pattern, `$1${version}$3`);
    },
  };
}

function load(target) {
  const absolute = join(actionRoot, target.path);
  const text = readFileSync(absolute, "utf8");
  return { ...target, absolute, text, version: target.read(text) };
}

const requested = process.argv[2];
if (requested && !/^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$/.test(requested)) {
  console.error(`Not a semantic version: ${requested}`);
  process.exit(2);
}

const entries = targets.map(load);
const missing = entries.filter((entry) => !entry.version);
if (missing.length > 0) {
  for (const entry of missing) {
    console.error(`Could not read a plugin version from ${entry.path}`);
  }
  process.exit(2);
}

if (requested) {
  for (const entry of entries) {
    const next = entry.write(entry.text, requested);
    if (next !== entry.text) writeFileSync(entry.absolute, next);
    console.log(`${entry.version === requested ? "  ok" : "  set"}  ${entry.path}`);
  }
  console.log(`\naction-browser is now ${requested} in ${entries.length} files.`);
  console.log("Reinstall or refresh the plugin in each harness so cached metadata is replaced.");
  process.exit(0);
}

const versions = [...new Set(entries.map((entry) => entry.version))];
if (versions.length > 1) {
  console.error("action-browser plugin versions disagree:\n");
  for (const entry of entries) {
    console.error(`  ${entry.version.padEnd(24)} ${relative(actionRoot, entry.absolute)}`);
  }
  console.error("\nHarnesses cache plugin metadata by version, so a partial bump ships stale");
  console.error("tool descriptions. Set them all: bun run plugin:version -- <version>");
  process.exit(1);
}

console.log(`action-browser ${versions[0]} across ${entries.length} manifests.`);
