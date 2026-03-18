#!/usr/bin/env bun
/**
 * Hands-off inference script — called by HandsOffSession.swift.
 *
 * Usage: echo '{"transcript":"tile chrome left","snapshot":{...}}' | bun run bin/handsoff-infer.ts
 *
 * Reads JSON from stdin, calls Groq via lib/infer.ts, prints JSON result to stdout.
 * All logging goes to stderr so it doesn't pollute the JSON output.
 */

import { inferJSON } from "../lib/infer.ts";
import { readFileSync } from "fs";
import { join, dirname } from "path";
import { homedir } from "os";

// ── Read input from stdin ──────────────────────────────────────────

const input = await Bun.stdin.text();
const req = JSON.parse(input) as {
  transcript: string;
  snapshot: {
    stageManager?: boolean;
    smGrouping?: string;
    activeStage?: Array<{ wid: number; app: string; title: string; frame: string }>;
    stripApps?: string[];
    hiddenApps?: string[];
    currentLayer?: string;
    screen?: string;
  };
  history?: Array<{ role: "user" | "assistant"; content: string }>;
};

// ── Load system prompt from file ───────────────────────────────────

const promptDir = join(dirname(import.meta.dir), "docs", "prompts");
let systemPrompt: string;
try {
  systemPrompt = readFileSync(join(promptDir, "hands-off-system.md"), "utf-8")
    .split("\n")
    .filter((l) => !l.startsWith("# "))
    .join("\n")
    .trim();
} catch {
  systemPrompt = "You are a workspace assistant. Respond with JSON: {actions, spoken}.";
}

// Replace {{intent_catalog}} with the actual tiling reference
const intentCatalog = `
tile_window: Tile a window to a screen position
  Slots:
    position (required): left, right, top, bottom, top-left, top-right, bottom-left, bottom-right, left-third, center-third, right-third, maximize, center
    app (optional): Target app name — match loosely (e.g. "chrome" matches "Google Chrome")
    wid (optional): Target window ID (from snapshot)
    session (optional): Tmux session name
  If no app/wid/session given, tiles the frontmost window.
  Examples: "tile chrome left" → {intent:"tile_window", slots:{app:"chrome", position:"left"}}

focus: Focus a window, app, or session
  Slots:
    app (optional): App name to focus
    session (optional): Session name to focus
    wid (optional): Window ID to focus

distribute: Arrange all visible windows in an even grid
  No slots needed. Tiles all on-screen windows.

search: Search windows by text
  Slots:
    query (required): Search text

list_windows: List all visible windows
  No slots needed.

switch_layer: Switch to a workspace layer
  Slots:
    layer (required): Layer name or index

create_layer: Save current window arrangement as a named layer
  Slots:
    name (required): Layer name

TILING PRESETS (use multiple tile_window actions):
  "split screen" / "side by side" → tile first app left, second app right
  "thirds" → tile three apps left-third, center-third, right-third
  "mosaic" / "grid" → use distribute intent
  "main + sidebar" → tile main app to left (or maximize), others stacked right
  "stack horizontally" → top and bottom halves
  "corners" / "quadrants" → four apps in top-left, top-right, bottom-left, bottom-right
`;

systemPrompt = systemPrompt.replace("{{intent_catalog}}", intentCatalog);

// ── Build the per-turn message ─────────────────────────────────────

let userMessage = `USER: "${req.transcript}"\n\n`;
userMessage += "--- DESKTOP SNAPSHOT ---\n";

const snap = req.snapshot;
if (snap.stageManager) {
  userMessage += `Stage Manager: ON (grouping: ${snap.smGrouping ?? "all-at-once"})\n\n`;
  userMessage += `Active stage (${snap.activeStage?.length ?? 0} windows):\n`;
  for (const w of snap.activeStage ?? []) {
    userMessage += `  [${w.wid}] ${w.app}: "${w.title}" — ${w.frame}\n`;
  }
  userMessage += `\nStrip: ${snap.stripApps?.join(", ") ?? "none"}\n`;
  userMessage += `Other stages: ${snap.hiddenApps?.join(", ") ?? "none"}\n`;
} else {
  userMessage += "Stage Manager: OFF\n";
  userMessage += `Visible windows (${snap.activeStage?.length ?? 0}):\n`;
  for (const w of snap.activeStage ?? []) {
    userMessage += `  [${w.wid}] ${w.app}: "${w.title}" — ${w.frame}\n`;
  }
}

if (snap.currentLayer) {
  userMessage += `\nCurrent layer: ${snap.currentLayer}\n`;
}
if (snap.screen) {
  userMessage += `Screen: ${snap.screen}\n`;
}
userMessage += "--- END SNAPSHOT ---\n";

// ── Call inference ──────────────────────────────────────────────────

const messages = (req.history ?? []).map((h) => ({
  role: h.role as "user" | "assistant",
  content: h.content,
}));

try {
  const { data, raw } = await inferJSON(userMessage, {
    provider: "groq",
    model: "llama-3.3-70b-versatile",
    system: systemPrompt,
    messages,
    temperature: 0.2,
    maxTokens: 512,
    tag: "hands-off",
  });

  // Output result as JSON to stdout
  const output = {
    ...data,
    _meta: {
      provider: raw.provider,
      model: raw.model,
      durationMs: raw.durationMs,
      tokens: raw.usage?.totalTokens,
    },
  };

  console.log(JSON.stringify(output));
} catch (err: any) {
  console.log(
    JSON.stringify({
      actions: [],
      spoken: "Sorry, I had trouble processing that.",
      _meta: { error: err.message },
    })
  );
  process.exit(1);
}
