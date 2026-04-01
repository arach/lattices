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
    position (required): Named position or grid:CxR:C,R syntax.
      Halves: left, right, top, bottom
      Quarters (2x2): top-left, top-right, bottom-left, bottom-right
      Thirds (3x1): left-third, center-third, right-third
      Sixths (3x2): top-left-third, top-center-third, top-right-third, bottom-left-third, bottom-center-third, bottom-right-third
      Fourths (4x1): first-fourth, second-fourth, third-fourth, last-fourth
      Eighths (4x2): top-first-fourth, top-second-fourth, top-third-fourth, top-last-fourth, bottom-first-fourth, bottom-second-fourth, bottom-third-fourth, bottom-last-fourth
      Special: maximize (full screen), center (centered floating)
      Grid syntax: grid:CxR:C,R (e.g. grid:5x3:2,1 = center cell of 5x3 grid)
    app (optional): Target app name — match loosely (e.g. "chrome" matches "Google Chrome")
    wid (optional): Target window ID (from snapshot)
    session (optional): Tmux session name
  If no app/wid/session given, tiles the frontmost window.
  "quarter" = 2x2 cell (top-left etc.), NOT a 4x1 fourth.
  "top quarter" = top-left or top-right (2x2). "top third" = top-left-third (3x2).
  Examples: "tile chrome left" → {intent:"tile_window", slots:{app:"chrome", position:"left"}}

focus: Focus a window, app, or session
  Slots:
    app (optional): App name to focus
    session (optional): Session name to focus
    wid (optional): Window ID to focus

distribute: Arrange windows in an even grid — with optional app filter and region constraint
  Slots:
    app (optional): Filter to windows of this app (e.g. "iTerm2", "Google Chrome"). Without this, distributes ALL visible windows.
    region (optional): Constrain the grid to a screen region. Uses the same position names as tile_window:
      Halves: left, right, top, bottom
      Quarters: top-left, top-right, bottom-left, bottom-right
      Thirds: left-third, center-third, right-third
      Without this, uses the full screen.
  Examples:
    "grid the terminals on the right" → {intent:"distribute", slots:{app:"iTerm2", region:"right"}}
    "organize my chrome windows in the bottom half" → {intent:"distribute", slots:{app:"Google Chrome", region:"bottom"}}
    "spread everything out" → {intent:"distribute", slots:{}}
    "tile all terminals" → {intent:"distribute", slots:{app:"iTerm2"}}

swap: Swap the positions of two windows
  Slots:
    wid_a (required): Window ID of the first window (from snapshot)
    wid_b (required): Window ID of the second window (from snapshot)
  Examples:
    "swap Chrome and iTerm" → {intent:"swap", slots:{wid_a:12345, wid_b:67890}}

hide: Hide or minimize a window or app
  Slots:
    app (optional): App name to hide (hides the entire app)
    wid (optional): Window ID to minimize (minimizes just that window)
  Use app to hide all windows of an app. Use wid to minimize a single window.
  Examples:
    "hide Slack" → {intent:"hide", slots:{app:"Slack"}}
    "minimize that" → {intent:"hide", slots:{wid:12345}}

highlight: Flash a window's border to identify it visually
  Slots:
    wid (optional): Window ID to highlight (from snapshot)
    app (optional): App name to highlight
  Use when the user asks "which one is that?" or wants to visually identify a window.
  Examples:
    "show me the lattices terminal" → {intent:"highlight", slots:{wid:12345}}
    "which one is Chrome?" → {intent:"highlight", slots:{app:"Google Chrome"}}

move_to_display: Move a window to another monitor/display
  Slots:
    display (required): Target display index (0 = main/primary, 1 = second, etc.)
    wid (optional): Window ID to move (from snapshot)
    app (optional): App name to move
    position (optional): Tile position on the target display (e.g. "left", "maximize")
  If no wid/app given, moves the frontmost window.
  Examples:
    "put this on my second monitor" → {intent:"move_to_display", slots:{wid:12345, display:1}}
    "move Chrome to the main screen" → {intent:"move_to_display", slots:{app:"Google Chrome", display:0}}
    "send iTerm to the other monitor, left half" → {intent:"move_to_display", slots:{app:"iTerm2", display:1, position:"left"}}

undo: Undo the last window move — restore windows to their previous positions
  No slots needed.
  Examples:
    "put it back" → {intent:"undo"}
    "undo that" → {intent:"undo"}

search: Search windows by text
  Slots:
    query (required): Search text
  Examples:
    "find the error message" → {intent:"search", slots:{query:"error"}}
    "find all terminal windows" → {intent:"search", slots:{query:"terminal"}}

list_windows: List all visible windows
  No slots needed. Use when the user asks "what's on screen?" or "what windows do I have?"

list_sessions: List active terminal sessions
  No slots needed. Use when the user asks "what sessions are running?" or "show my projects."

switch_layer: Switch to a workspace layer
  Slots:
    layer (required): Layer name or index
  Examples:
    "switch to the web layer" → {intent:"switch_layer", slots:{layer:"web"}}
    "go to layer 2" → {intent:"switch_layer", slots:{layer:"2"}}

create_layer: Save current window arrangement as a named layer
  Slots:
    name (required): Layer name
  Examples:
    "save this layout as review" → {intent:"create_layer", slots:{name:"review"}}

launch: Launch a project session
  Slots:
    project (required): Project name or path
  Examples:
    "open my frontend project" → {intent:"launch", slots:{project:"frontend"}}
    "start working on lattices" → {intent:"launch", slots:{project:"lattices"}}

kill: Kill a terminal session
  Slots:
    session (required): Session name or project name
  Examples:
    "stop the frontend session" → {intent:"kill", slots:{session:"frontend"}}

scan: Trigger an immediate screen text scan (OCR)
  No slots needed. Use when the user asks you to read or scan screen content.

CHOOSING THE RIGHT INTENT:
  Positioning:
    tile_window = position ONE specific window at a specific spot. Use for 1-6 named windows.
    distribute = auto-grid MANY windows. Use when the user says "all", "my terminals", "everything", or names more windows than the 6-action limit.
    distribute with app+region is the most powerful combo: "grid my terminals on the right" → distribute(app:"iTerm2", region:"right")
  Rearranging:
    swap = exchange positions of exactly two windows. "swap Chrome and iTerm"
    move_to_display = move a window to a different monitor. "put this on my other screen"
  Visibility:
    hide = hide an app or minimize a window. "hide Slack", "minimize that"
    highlight = flash a window's border to identify it. "which one is the lattices terminal?"
    focus = bring a window to the front. "focus Slack", "show me Chrome"
  Recovery:
    undo = restore previous positions after a move. "put it back", "undo that"
  Information:
    list_windows, list_sessions, search = answer questions about the desktop. NO actions needed for pure questions.
  Session lifecycle:
    launch = start a project session. "open my frontend project"
    kill = stop a session. "kill the API"

TILING PRESETS (use multiple tile_window actions):
  "split screen" / "side by side" → left + right
  "thirds" → left-third, center-third, right-third
  "main + sidebar" → main app left (or maximize), others stacked right
  "stack" → top + bottom
  "corners" / "quadrants" → top-left, top-right, bottom-left, bottom-right
  "six-up" / "3 by 2" → 3x2 grid using sixth positions
  "eight-up" / "4 by 2" → 4x2 grid using eighth positions

TILING PRESETS (use distribute intent):
  "mosaic" / "grid" / "spread out" → distribute (all windows, full screen)
  "grid the terminals" → distribute with app:"iTerm2"
  "terminals on the right" → distribute with app:"iTerm2", region:"right"
  "organize chrome on the left" → distribute with app:"Google Chrome", region:"left"
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
