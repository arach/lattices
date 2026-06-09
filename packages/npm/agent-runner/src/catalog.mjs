// Harness catalog + binary resolution for the agent runner.
//
// Each entry describes one harnessable agent: its adapter type (matching an
// @openscout/agent-sessions factory), the executable to look for, env-var
// overrides, and candidate install paths. Resolution order: explicit env var →
// candidate paths → PATH lookup. This is the generic, project-agnostic core —
// no Lattices/Talkie specifics live here.

import { accessSync, constants } from "node:fs";
import { homedir } from "node:os";
import { delimiter, join } from "node:path";

const home = homedir();

export const HARNESS_CATALOG = [
  {
    id: "pi",
    name: "Pi",
    adapterType: "pi",
    command: "pi",
    envKeys: ["OPENSCOUT_PI_BIN", "PI_BIN"],
    candidates: [
      join(home, ".local", "bin", "pi"),
      join(home, ".bun", "bin", "pi"),
      "/opt/homebrew/bin/pi",
      "/usr/local/bin/pi",
    ],
  },
  {
    id: "codex",
    name: "Codex",
    adapterType: "codex",
    command: "codex",
    envKeys: ["OPENSCOUT_CODEX_BIN", "CODEX_BIN"],
    candidates: [
      "/Applications/Codex.app/Contents/Resources/codex",
      join(home, "Applications", "Codex.app", "Contents", "Resources", "codex"),
      join(home, ".local", "bin", "codex"),
      join(home, ".bun", "bin", "codex"),
      "/opt/homebrew/bin/codex",
      "/usr/local/bin/codex",
    ],
  },
  {
    id: "claude-code",
    name: "Claude Code",
    adapterType: "claude-code",
    command: "claude",
    envKeys: ["OPENSCOUT_CLAUDE_BIN", "CLAUDE_BIN"],
    candidates: [
      join(home, ".local", "bin", "claude"),
      join(home, ".claude", "local", "claude"),
      "/opt/homebrew/bin/claude",
      "/usr/local/bin/claude",
    ],
  },
  {
    id: "opencode",
    name: "OpenCode",
    adapterType: "opencode",
    command: "opencode",
    envKeys: ["OPENSCOUT_OPENCODE_BIN", "OPENCODE_BIN"],
    candidates: [
      join(home, ".opencode", "bin", "opencode"),
      "/opt/homebrew/bin/opencode",
      "/usr/local/bin/opencode",
    ],
  },
  {
    id: "echo",
    name: "Echo",
    adapterType: "echo",
    builtin: true,
    command: null,
    envKeys: [],
    candidates: [],
  },
];

export function harnessById(id) {
  return HARNESS_CATALOG.find((h) => h.id === id || h.adapterType === id) ?? null;
}

export function resolveAgentExecutable(agent, env = process.env) {
  for (const key of agent.envKeys ?? []) {
    const value = normalizeString(env[key]);
    if (value) {
      return { path: value, source: `env:${key}`, executable: isExecutable(value), explicit: true };
    }
  }

  for (const candidate of uniqueStrings([
    ...(agent.candidates ?? []),
    ...pathExecutableCandidates(agent.command, env),
  ])) {
    if (isExecutable(candidate)) {
      return { path: candidate, source: "path", executable: true, explicit: false };
    }
  }

  return null;
}

function pathExecutableCandidates(command, env = process.env) {
  if (!command) return [];
  return (env.PATH ?? "")
    .split(delimiter)
    .filter(Boolean)
    .map((directory) => join(directory, command));
}

function isExecutable(filePath) {
  try {
    accessSync(filePath, constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

function normalizeString(value) {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : null;
}

function uniqueStrings(values) {
  const seen = new Set();
  const out = [];
  for (const v of values) {
    if (typeof v !== "string" || v.length === 0 || seen.has(v)) continue;
    seen.add(v);
    out.push(v);
  }
  return out;
}
