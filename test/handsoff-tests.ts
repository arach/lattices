#!/usr/bin/env bun
/**
 * Automated test suite for hands-off mode.
 * Runs 100 scenarios through the inference pipeline and scores results.
 *
 * Usage: bun run test/handsoff-tests.ts
 */

import { infer } from "../lib/infer.ts";
import { readFileSync } from "fs";
import { join, dirname } from "path";

// ── Load system prompt ─────────────────────────────────────────────

const promptDir = join(dirname(import.meta.dir), "docs", "prompts");
let systemPrompt: string;
try {
  systemPrompt = readFileSync(join(promptDir, "hands-off-system.md"), "utf-8")
    .split("\n")
    .filter((l) => !l.startsWith("# "))
    .join("\n")
    .trim();
} catch {
  console.error("Could not load system prompt");
  process.exit(1);
}

const intentCatalog = `
tile_window: Tile a window to a screen position
  position (required): left, right, top, bottom, top-left, top-right, bottom-left, bottom-right, left-third, center-third, right-third, maximize, center
  app (optional): Target app name
  wid (optional): Window ID
  session (optional): Tmux session name

focus: Focus a window, app, or session
  app, session, or wid (at least one)

distribute: Arrange all visible windows in an even grid. No slots.

search: Search windows by text
  query (required)

switch_layer: Switch to a workspace layer
  layer (required)

create_layer: Save current arrangement as a named layer
  name (required)
`;

systemPrompt = systemPrompt.replace("{{intent_catalog}}", intentCatalog);

// ── Realistic snapshot ─────────────────────────────────────────────

const snapshot = `
Displays: 3440x1440 (main), 2160x3840
Stage Manager: OFF

Visible windows (12, front-to-back order):
  wid:423 iTerm2: "✳ Claude Code" — 0,0 1720x1440 [FRONTMOST]
  wid:10439 iTerm2: "✳ Claude Code" — 1720,0 1720x1440
  wid:91912 Google Chrome: "Home / X" — 594,0 2231x1186
  wid:26732 Google Chrome: "Models | xAI Cloud Console" — 0,360 573x375
  wid:27062 Google Chrome: "Lattices PR #12 - GitHub" — -1592,-122 573x375
  wid:27168 Finder: "Applications" — 1146,360 573x360
  wid:33301 Finder: "Hudson" — 1720,360 573x360
  wid:97308 Vox: "Vox" — 1988,721 900x640
  wid:47788 Finder: "public" — 2866,360 573x360
  wid:109838 iTerm2: "tail -f ~/.lattices/lattices.log" — -1750,159 1515x2125
  wid:112439 iTerm2: "tail -f ~/.lattices/handsoff.jsonl | jq" — -1080,-1556 1080x3840
  wid:111884 Karabiner-EventViewer: "Karabiner-EventViewer" — 1290,168 1376x992

Hidden windows: Activity Monitor(1), ChatGPT(1), Codex(1), Slack(1), Messages(1), Zoom(3), ScoutApp(1)

Terminal tabs (8):
  Claude Code (lattices) cwd:~/dev/lattices running:claude [Claude Code, tmux:lattices] (wid:423)
  Claude Code (hudson) cwd:~/dev/hudson running:claude [Claude Code, tmux:hudson] (wid:10439)
  Claude Code (vox) cwd:~/dev/vox running:claude [Claude Code, tmux:vox] (wid:94520)
  server (lattices) cwd:~/dev/lattices running:bun [tmux:lattices] (wid:423)
  server (hudson) cwd:~/dev/hudson running:node [tmux:hudson] (wid:10439)
  log tail cwd:~/dev/lattices running:tail (wid:109838)
  jsonl tail cwd:~/dev/lattices running:tail (wid:112439)
  scratch cwd:~/dev running:zsh (wid:94520)

Tmux sessions: lattices (3 windows, attached), hudson (2 windows, attached), vox (2 windows, attached)
`;

// ── Test definitions ───────────────────────────────────────────────

interface Test {
  id: string;
  category: string;
  say: string;
  checks: Check[];
  history?: Array<{ role: "user" | "assistant"; content: string }>;
}

interface Check {
  desc: string;
  fn: (result: any) => boolean;
}

// Helpers
const hasAction = (intent: string) => (r: any) =>
  (r.actions ?? []).some((a: any) => a.intent === intent);

const hasNoActions = (r: any) => (r.actions ?? []).length === 0;

const hasActionWithSlot = (intent: string, slot: string, value?: string) => (r: any) =>
  (r.actions ?? []).some((a: any) => {
    if (a.intent !== intent) return false;
    if (!a.slots?.[slot]) return false;
    if (value && !a.slots[slot].toLowerCase().includes(value.toLowerCase())) return false;
    return true;
  });

const spokenIncludes = (text: string) => (r: any) =>
  (r.spoken ?? "").toLowerCase().includes(text.toLowerCase());

const spokenNotIncludes = (text: string) => (r: any) =>
  !(r.spoken ?? "").toLowerCase().includes(text.toLowerCase());

const noWidsInSpeech = (r: any) =>
  !/wid[\s:]*\d+/i.test(r.spoken ?? "") && !/\bwid\b/i.test(r.spoken ?? "");

const hasSpoken = (r: any) => !!(r.spoken && r.spoken.length > 0);

const actionCount = (n: number) => (r: any) => (r.actions ?? []).length === n;

const tests: Test[] = [
  // ── 1. Basic Awareness (1-15) ────────────────────────────────
  { id: "1.01", category: "awareness", say: "What is the frontmost window?",
    checks: [
      { desc: "mentions iTerm or Claude Code", fn: spokenIncludes("iterm") },
      { desc: "mentions lattices project", fn: spokenIncludes("lattices") },
      { desc: "no wids", fn: noWidsInSpeech },
      { desc: "no actions", fn: hasNoActions },
    ]},
  { id: "1.02", category: "awareness", say: "How many monitors do I have?",
    checks: [
      { desc: "says two", fn: spokenIncludes("two") },
      { desc: "mentions 3440", fn: spokenIncludes("3440") },
      { desc: "no actions", fn: hasNoActions },
    ]},
  { id: "1.03", category: "awareness", say: "What terminals are open?",
    checks: [
      { desc: "mentions lattices", fn: spokenIncludes("lattices") },
      { desc: "mentions hudson", fn: spokenIncludes("hudson") },
      { desc: "has spoken text", fn: hasSpoken },
      { desc: "no wids", fn: noWidsInSpeech },
    ]},
  { id: "1.04", category: "awareness", say: "Which terminals are running Claude Code?",
    checks: [
      { desc: "mentions lattices", fn: spokenIncludes("lattices") },
      { desc: "mentions hudson", fn: spokenIncludes("hudson") },
      { desc: "mentions vox", fn: spokenIncludes("vox") },
      { desc: "mentions three", fn: (r) => /three|3/.test(r.spoken ?? "") },
    ]},
  { id: "1.05", category: "awareness", say: "What's on my second monitor?",
    checks: [
      { desc: "mentions log or tail", fn: (r) => /log|tail/i.test(r.spoken ?? "") },
      { desc: "no wids", fn: noWidsInSpeech },
    ]},
  { id: "1.06", category: "awareness", say: "How many windows do I have open?",
    checks: [
      { desc: "mentions a number", fn: (r) => /\d+/.test(r.spoken ?? "") },
      { desc: "has spoken", fn: hasSpoken },
    ]},
  { id: "1.07", category: "awareness", say: "What Chrome windows do I have?",
    checks: [
      { desc: "mentions X or xAI", fn: (r) => /x\b|xai|cloud console/i.test(r.spoken ?? "") },
      { desc: "mentions GitHub or PR", fn: (r) => /github|pr/i.test(r.spoken ?? "") },
    ]},
  { id: "1.08", category: "awareness", say: "Is Slack running?",
    checks: [
      { desc: "mentions Slack", fn: spokenIncludes("slack") },
      { desc: "says hidden or not visible", fn: (r) => /hidden|not visible|not on screen|background/i.test(r.spoken ?? "") },
    ]},
  { id: "1.09", category: "awareness", say: "What project is the frontmost window in?",
    checks: [
      { desc: "says lattices", fn: spokenIncludes("lattices") },
      { desc: "no wids", fn: noWidsInSpeech },
    ]},
  { id: "1.10", category: "awareness", say: "What Finder windows do I have?",
    checks: [
      { desc: "mentions Applications", fn: spokenIncludes("applications") },
      { desc: "mentions Hudson", fn: spokenIncludes("hudson") },
    ]},
  { id: "1.11", category: "awareness", say: "What's the biggest window on screen?",
    checks: [
      { desc: "mentions iTerm or Claude", fn: (r) => /iterm|claude/i.test(r.spoken ?? "") },
      { desc: "no wids", fn: noWidsInSpeech },
    ]},
  { id: "1.12", category: "awareness", say: "Are there any hidden windows?",
    checks: [
      { desc: "mentions some hidden apps", fn: (r) => /chatgpt|codex|slack|zoom|activity/i.test(r.spoken ?? "") },
    ]},
  { id: "1.13", category: "awareness", say: "What tmux sessions are active?",
    checks: [
      { desc: "mentions lattices", fn: spokenIncludes("lattices") },
      { desc: "mentions hudson", fn: spokenIncludes("hudson") },
      { desc: "mentions vox", fn: spokenIncludes("vox") },
    ]},
  { id: "1.14", category: "awareness", say: "Which window is running bun?",
    checks: [
      { desc: "mentions lattices server or dev server", fn: (r) => /lattices|server|bun/i.test(r.spoken ?? "") },
    ]},
  { id: "1.15", category: "awareness", say: "What's the resolution of my main monitor?",
    checks: [
      { desc: "mentions 3440", fn: spokenIncludes("3440") },
      { desc: "mentions 1440", fn: spokenIncludes("1440") },
    ]},

  // ── 2. Simple Tiling (16-30) ─────────────────────────────────
  { id: "2.01", category: "tile", say: "Tile Chrome left",
    checks: [
      { desc: "has tile action", fn: hasAction("tile_window") },
      { desc: "position is left", fn: hasActionWithSlot("tile_window", "position", "left") },
      { desc: "targets chrome", fn: (r) => (r.actions ?? []).some((a: any) => /chrome/i.test(JSON.stringify(a.slots))) },
      { desc: "has spoken", fn: hasSpoken },
    ]},
  { id: "2.02", category: "tile", say: "Put iTerm on the right",
    checks: [
      { desc: "has tile action", fn: hasAction("tile_window") },
      { desc: "position is right", fn: hasActionWithSlot("tile_window", "position", "right") },
    ]},
  { id: "2.03", category: "tile", say: "Maximize this window",
    checks: [
      { desc: "has tile action", fn: hasAction("tile_window") },
      { desc: "position is maximize", fn: hasActionWithSlot("tile_window", "position", "maximize") },
    ]},
  { id: "2.04", category: "tile", say: "Center the Finder window",
    checks: [
      { desc: "has tile action", fn: hasAction("tile_window") },
      { desc: "position is center", fn: hasActionWithSlot("tile_window", "position", "center") },
    ]},
  { id: "2.05", category: "tile", say: "Snap Chrome to the top left corner",
    checks: [
      { desc: "has tile action", fn: hasAction("tile_window") },
      { desc: "position is top-left", fn: hasActionWithSlot("tile_window", "position", "top-left") },
    ]},
  { id: "2.06", category: "tile", say: "Put Vox in the bottom right",
    checks: [
      { desc: "has tile action", fn: hasAction("tile_window") },
      { desc: "position is bottom-right", fn: hasActionWithSlot("tile_window", "position", "bottom-right") },
    ]},
  { id: "2.07", category: "tile", say: "Make Chrome take up the left third",
    checks: [
      { desc: "position is left-third", fn: hasActionWithSlot("tile_window", "position", "left-third") },
    ]},
  { id: "2.08", category: "tile", say: "Tile the lattices terminal to the right half",
    checks: [
      { desc: "has tile action", fn: hasAction("tile_window") },
      { desc: "position is right", fn: hasActionWithSlot("tile_window", "position", "right") },
    ]},
  { id: "2.09", category: "tile", say: "Put the Karabiner window in the top half",
    checks: [
      { desc: "has tile action", fn: hasAction("tile_window") },
      { desc: "position is top", fn: hasActionWithSlot("tile_window", "position", "top") },
    ]},
  { id: "2.10", category: "tile", say: "Bottom half for Finder",
    checks: [
      { desc: "has tile action", fn: hasAction("tile_window") },
      { desc: "position is bottom", fn: hasActionWithSlot("tile_window", "position", "bottom") },
    ]},
  { id: "2.11", category: "tile", say: "Full screen the Chrome window that has Twitter",
    checks: [
      { desc: "has tile action", fn: hasAction("tile_window") },
      { desc: "position maximize", fn: hasActionWithSlot("tile_window", "position", "maximize") },
    ]},
  { id: "2.12", category: "tile", say: "Move Chrome to the center third",
    checks: [
      { desc: "position center-third", fn: hasActionWithSlot("tile_window", "position", "center-third") },
    ]},
  { id: "2.13", category: "tile", say: "Right third for the xAI console",
    checks: [
      { desc: "has tile action", fn: hasAction("tile_window") },
      { desc: "position right-third", fn: hasActionWithSlot("tile_window", "position", "right-third") },
    ]},
  { id: "2.14", category: "tile", say: "Tile the Hudson Claude Code window left",
    checks: [
      { desc: "has tile action", fn: hasAction("tile_window") },
      { desc: "targets hudson window", fn: (r) => (r.actions ?? []).some((a: any) => a.slots?.wid === 10439 || /hudson/i.test(JSON.stringify(a.slots))) },
    ]},
  { id: "2.15", category: "tile", say: "Make the GitHub PR window take up the right side",
    checks: [
      { desc: "has tile action", fn: hasAction("tile_window") },
      { desc: "position right", fn: hasActionWithSlot("tile_window", "position", "right") },
    ]},

  // ── 3. Multi-Window Layouts (31-45) ──────────────────────────
  { id: "3.01", category: "layout", say: "Split Chrome and iTerm",
    checks: [
      { desc: "two tile actions", fn: actionCount(2) },
      { desc: "one left", fn: hasActionWithSlot("tile_window", "position", "left") },
      { desc: "one right", fn: hasActionWithSlot("tile_window", "position", "right") },
    ]},
  { id: "3.02", category: "layout", say: "Put everything in a grid",
    checks: [
      { desc: "has distribute", fn: hasAction("distribute") },
      { desc: "has spoken", fn: hasSpoken },
    ]},
  { id: "3.03", category: "layout", say: "Thirds with Chrome, iTerm, and Finder",
    checks: [
      { desc: "three tile actions", fn: actionCount(3) },
      { desc: "has left-third", fn: hasActionWithSlot("tile_window", "position", "left-third") },
      { desc: "has center-third", fn: hasActionWithSlot("tile_window", "position", "center-third") },
      { desc: "has right-third", fn: hasActionWithSlot("tile_window", "position", "right-third") },
    ]},
  { id: "3.04", category: "layout", say: "Quadrants",
    checks: [
      { desc: "four tile actions", fn: actionCount(4) },
      { desc: "has top-left", fn: hasActionWithSlot("tile_window", "position", "top-left") },
      { desc: "has top-right", fn: hasActionWithSlot("tile_window", "position", "top-right") },
      { desc: "has bottom-left", fn: hasActionWithSlot("tile_window", "position", "bottom-left") },
      { desc: "has bottom-right", fn: hasActionWithSlot("tile_window", "position", "bottom-right") },
    ]},
  { id: "3.05", category: "layout", say: "Stack Chrome on top, iTerm on bottom",
    checks: [
      { desc: "two actions", fn: actionCount(2) },
      { desc: "has top", fn: hasActionWithSlot("tile_window", "position", "top") },
      { desc: "has bottom", fn: hasActionWithSlot("tile_window", "position", "bottom") },
    ]},
  { id: "3.06", category: "layout", say: "Side by side the two Claude Code windows",
    checks: [
      { desc: "two tile actions", fn: actionCount(2) },
      { desc: "has left", fn: hasActionWithSlot("tile_window", "position", "left") },
      { desc: "has right", fn: hasActionWithSlot("tile_window", "position", "right") },
    ]},
  { id: "3.07", category: "layout", say: "Distribute all the terminal windows",
    checks: [
      { desc: "has distribute", fn: hasAction("distribute") },
    ]},
  { id: "3.08", category: "layout", say: "Mosaic everything",
    checks: [
      { desc: "has distribute", fn: hasAction("distribute") },
    ]},
  { id: "3.09", category: "layout", say: "Grid layout please",
    checks: [
      { desc: "has distribute", fn: hasAction("distribute") },
    ]},
  { id: "3.10", category: "layout", say: "Chrome left third, iTerm center third, Finder right third",
    checks: [
      { desc: "three actions", fn: actionCount(3) },
      { desc: "has left-third", fn: hasActionWithSlot("tile_window", "position", "left-third") },
      { desc: "has center-third", fn: hasActionWithSlot("tile_window", "position", "center-third") },
      { desc: "has right-third", fn: hasActionWithSlot("tile_window", "position", "right-third") },
    ]},
  { id: "3.11", category: "layout", say: "Put Chrome top left, iTerm top right, Finder bottom left, Vox bottom right",
    checks: [
      { desc: "four actions", fn: actionCount(4) },
      { desc: "has all four corners", fn: (r) => {
        const positions = (r.actions ?? []).map((a: any) => a.slots?.position);
        return ["top-left","top-right","bottom-left","bottom-right"].every(p => positions.includes(p));
      }},
    ]},
  { id: "3.12", category: "layout", say: "Arrange my windows nicely",
    checks: [
      { desc: "has actions", fn: (r) => (r.actions ?? []).length > 0 },
      { desc: "has spoken", fn: hasSpoken },
    ]},
  { id: "3.13", category: "layout", say: "Even split all visible windows",
    checks: [
      { desc: "has distribute", fn: hasAction("distribute") },
    ]},
  { id: "3.14", category: "layout", say: "Tile the three Finder windows across the bottom",
    checks: [
      { desc: "has tile actions", fn: (r) => (r.actions ?? []).length >= 2 },
    ]},
  { id: "3.15", category: "layout", say: "Put the lattices and hudson terminals side by side",
    checks: [
      { desc: "two tile actions", fn: actionCount(2) },
      { desc: "has left", fn: hasActionWithSlot("tile_window", "position", "left") },
      { desc: "has right", fn: hasActionWithSlot("tile_window", "position", "right") },
    ]},

  // ── 4. Focus + Switching (46-60) ─────────────────────────────
  { id: "4.01", category: "focus", say: "Focus on Chrome",
    checks: [
      { desc: "has focus action", fn: hasAction("focus") },
      { desc: "targets chrome", fn: (r) => (r.actions ?? []).some((a: any) => /chrome/i.test(JSON.stringify(a.slots))) },
    ]},
  { id: "4.02", category: "focus", say: "Switch to the Hudson terminal",
    checks: [
      { desc: "has focus action", fn: hasAction("focus") },
      { desc: "targets hudson", fn: (r) => (r.actions ?? []).some((a: any) => /hudson|10439/i.test(JSON.stringify(a.slots))) },
    ]},
  { id: "4.03", category: "focus", say: "Go to the lattices Claude Code",
    checks: [
      { desc: "has focus action", fn: hasAction("focus") },
    ]},
  { id: "4.04", category: "focus", say: "Show me Vox",
    checks: [
      { desc: "has focus action", fn: hasAction("focus") },
      { desc: "targets vox", fn: (r) => (r.actions ?? []).some((a: any) => /vox/i.test(JSON.stringify(a.slots))) },
    ]},
  { id: "4.05", category: "focus", say: "Bring up ChatGPT",
    checks: [
      { desc: "has focus action", fn: hasAction("focus") },
      { desc: "targets chatgpt", fn: (r) => (r.actions ?? []).some((a: any) => /chatgpt/i.test(JSON.stringify(a.slots))) },
    ]},
  { id: "4.06", category: "focus", say: "Switch to the GitHub PR window",
    checks: [
      { desc: "has focus action", fn: hasAction("focus") },
    ]},
  { id: "4.07", category: "focus", say: "Focus the xAI console",
    checks: [
      { desc: "has focus action", fn: hasAction("focus") },
    ]},
  { id: "4.08", category: "focus", say: "Go to my Codex window",
    checks: [
      { desc: "has focus action", fn: hasAction("focus") },
      { desc: "targets codex", fn: (r) => (r.actions ?? []).some((a: any) => /codex/i.test(JSON.stringify(a.slots))) },
    ]},
  { id: "4.09", category: "focus", say: "Open the Applications folder",
    checks: [
      { desc: "has focus action", fn: hasAction("focus") },
      { desc: "targets finder", fn: (r) => (r.actions ?? []).some((a: any) => /finder|application/i.test(JSON.stringify(a.slots))) },
    ]},
  { id: "4.10", category: "focus", say: "Switch to the terminal that's tailing the log",
    checks: [
      { desc: "has focus action", fn: hasAction("focus") },
    ]},
  { id: "4.11", category: "focus", say: "Focus on Zoom",
    checks: [
      { desc: "has focus action", fn: hasAction("focus") },
      { desc: "targets zoom", fn: (r) => (r.actions ?? []).some((a: any) => /zoom/i.test(JSON.stringify(a.slots))) },
    ]},
  { id: "4.12", category: "focus", say: "Go to the terminal running bun",
    checks: [
      { desc: "has focus action", fn: hasAction("focus") },
    ]},
  { id: "4.13", category: "focus", say: "Switch to the vox project",
    checks: [
      { desc: "has focus action", fn: hasAction("focus") },
      { desc: "targets vox", fn: (r) => (r.actions ?? []).some((a: any) => /vox/i.test(JSON.stringify(a.slots))) },
    ]},
  { id: "4.14", category: "focus", say: "Show me the Slack window",
    checks: [
      { desc: "has focus action", fn: hasAction("focus") },
    ]},
  { id: "4.15", category: "focus", say: "Bring up Activity Monitor",
    checks: [
      { desc: "has focus action", fn: hasAction("focus") },
    ]},

  // ── 5. Conversational Context (61-70) ────────────────────────
  { id: "5.01", category: "context", say: "Now put the other one on the right",
    history: [
      { role: "user", content: 'USER: "Tile Chrome left"\n--- DESKTOP SNAPSHOT ---\n' + snapshot },
      { role: "assistant", content: '{"actions":[{"intent":"tile_window","slots":{"app":"Google Chrome","position":"left"}}],"spoken":"Tiling Chrome to the left."}' },
    ],
    checks: [
      { desc: "has tile action", fn: hasAction("tile_window") },
      { desc: "position right", fn: hasActionWithSlot("tile_window", "position", "right") },
    ]},
  { id: "5.02", category: "context", say: "Do the same for Finder",
    history: [
      { role: "user", content: 'USER: "Tile Chrome left"\n--- DESKTOP SNAPSHOT ---\n' + snapshot },
      { role: "assistant", content: '{"actions":[{"intent":"tile_window","slots":{"app":"Google Chrome","position":"left"}}],"spoken":"Tiling Chrome to the left."}' },
    ],
    checks: [
      { desc: "has tile action", fn: hasAction("tile_window") },
      { desc: "targets finder", fn: (r) => (r.actions ?? []).some((a: any) => /finder/i.test(JSON.stringify(a.slots))) },
      { desc: "position left", fn: hasActionWithSlot("tile_window", "position", "left") },
    ]},
  { id: "5.03", category: "context", say: "Actually make it right instead",
    history: [
      { role: "user", content: 'USER: "Tile Chrome left"\n--- DESKTOP SNAPSHOT ---\n' + snapshot },
      { role: "assistant", content: '{"actions":[{"intent":"tile_window","slots":{"app":"Google Chrome","position":"left"}}],"spoken":"Tiling Chrome to the left."}' },
    ],
    checks: [
      { desc: "has tile action", fn: hasAction("tile_window") },
      { desc: "position right", fn: hasActionWithSlot("tile_window", "position", "right") },
      { desc: "targets chrome", fn: (r) => (r.actions ?? []).some((a: any) => /chrome/i.test(JSON.stringify(a.slots))) },
    ]},
  { id: "5.04", category: "context", say: "What about the other Claude Code windows?",
    history: [
      { role: "user", content: 'USER: "Which terminals are running Claude Code?"\n--- DESKTOP SNAPSHOT ---\n' + snapshot },
      { role: "assistant", content: '{"actions":[],"spoken":"Three terminals running Claude Code: lattices, hudson, and vox."}' },
    ],
    checks: [
      { desc: "has spoken", fn: hasSpoken },
      { desc: "doesn't re-list all three", fn: (r) => !/three.*lattices.*hudson.*vox/i.test(r.spoken ?? "") },
    ]},
  { id: "5.05", category: "context", say: "Swap them",
    history: [
      { role: "user", content: 'USER: "Split Chrome and iTerm"\n--- DESKTOP SNAPSHOT ---\n' + snapshot },
      { role: "assistant", content: '{"actions":[{"intent":"tile_window","slots":{"app":"Google Chrome","position":"left"}},{"intent":"tile_window","slots":{"app":"iTerm2","position":"right"}}],"spoken":"Chrome left, iTerm right."}' },
    ],
    checks: [
      { desc: "two tile actions", fn: actionCount(2) },
      { desc: "chrome now right", fn: (r) => (r.actions ?? []).some((a: any) => /chrome/i.test(JSON.stringify(a.slots)) && a.slots?.position === "right") },
      { desc: "iterm now left", fn: (r) => (r.actions ?? []).some((a: any) => /iterm/i.test(JSON.stringify(a.slots)) && a.slots?.position === "left") },
    ]},
  { id: "5.06", category: "context", say: "Organize those",
    history: [
      { role: "user", content: 'USER: "What Finder windows do I have?"\n--- DESKTOP SNAPSHOT ---\n' + snapshot },
      { role: "assistant", content: '{"actions":[],"spoken":"You have three Finder windows: Applications, Hudson, and public."}' },
    ],
    checks: [
      { desc: "has actions", fn: (r) => (r.actions ?? []).length > 0 },
    ]},
  { id: "5.07", category: "context", say: "No, the big one",
    history: [
      { role: "user", content: 'USER: "Tile Chrome left"\n--- DESKTOP SNAPSHOT ---\n' + snapshot },
      { role: "assistant", content: '{"actions":[{"intent":"tile_window","slots":{"app":"Google Chrome","position":"left"}}],"spoken":"Tiling the xAI console Chrome window left."}' },
      { role: "user", content: 'USER: "No, the big one"\n--- DESKTOP SNAPSHOT ---\n' + snapshot },
    ],
    checks: [
      { desc: "has tile action", fn: hasAction("tile_window") },
      { desc: "has spoken", fn: hasSpoken },
    ]},
  { id: "5.08", category: "context", say: "And Finder on the right",
    history: [
      { role: "user", content: 'USER: "Tile Chrome left"\n--- DESKTOP SNAPSHOT ---\n' + snapshot },
      { role: "assistant", content: '{"actions":[{"intent":"tile_window","slots":{"app":"Google Chrome","position":"left"}}],"spoken":"Tiling Chrome left."}' },
    ],
    checks: [
      { desc: "has tile action", fn: hasAction("tile_window") },
      { desc: "targets finder", fn: (r) => (r.actions ?? []).some((a: any) => /finder/i.test(JSON.stringify(a.slots))) },
      { desc: "position right", fn: hasActionWithSlot("tile_window", "position", "right") },
    ]},
  { id: "5.09", category: "context", say: "Focus on that one instead",
    history: [
      { role: "user", content: 'USER: "What project is the Hudson terminal in?"\n--- DESKTOP SNAPSHOT ---\n' + snapshot },
      { role: "assistant", content: '{"actions":[],"spoken":"The Hudson terminal is in ~/dev/hudson, running Claude Code."}' },
    ],
    checks: [
      { desc: "has focus action", fn: hasAction("focus") },
      { desc: "targets hudson", fn: (r) => (r.actions ?? []).some((a: any) => /hudson|10439/i.test(JSON.stringify(a.slots))) },
    ]},
  { id: "5.10", category: "context", say: "Maximize it",
    history: [
      { role: "user", content: 'USER: "Focus on Chrome"\n--- DESKTOP SNAPSHOT ---\n' + snapshot },
      { role: "assistant", content: '{"actions":[{"intent":"focus","slots":{"app":"Google Chrome"}}],"spoken":"Focusing Chrome."}' },
    ],
    checks: [
      { desc: "has tile maximize", fn: hasActionWithSlot("tile_window", "position", "maximize") },
      { desc: "targets chrome", fn: (r) => (r.actions ?? []).some((a: any) => /chrome/i.test(JSON.stringify(a.slots))) },
    ]},

  // ── 6. Intelligence (71-80) ──────────────────────────────────
  { id: "6.01", category: "intelligence", say: "Set up for coding",
    checks: [
      { desc: "has actions", fn: (r) => (r.actions ?? []).length > 0 },
      { desc: "has spoken", fn: hasSpoken },
      { desc: "no wids in speech", fn: noWidsInSpeech },
    ]},
  { id: "6.02", category: "intelligence", say: "I'm going to review a PR",
    checks: [
      { desc: "has actions or spoken suggestion", fn: (r) => (r.actions ?? []).length > 0 || (r.spoken ?? "").length > 20 },
    ]},
  { id: "6.03", category: "intelligence", say: "Clean up my desktop",
    checks: [
      { desc: "has actions", fn: (r) => (r.actions ?? []).length > 0 },
    ]},
  { id: "6.04", category: "intelligence", say: "I need to focus, minimize distractions",
    checks: [
      { desc: "has spoken", fn: hasSpoken },
    ]},
  { id: "6.05", category: "intelligence", say: "Set up for a presentation",
    checks: [
      { desc: "has actions", fn: (r) => (r.actions ?? []).length > 0 },
      { desc: "probably maximize", fn: hasActionWithSlot("tile_window", "position", "maximize") },
    ]},
  { id: "6.06", category: "intelligence", say: "I want to compare two things side by side",
    checks: [
      { desc: "two tile actions or asks which", fn: (r) => (r.actions ?? []).length === 2 || (r.spoken ?? "").includes("which") },
    ]},
  { id: "6.07", category: "intelligence", say: "Make the lattices Claude Code the main window and put Chrome on the side",
    checks: [
      { desc: "two tile actions", fn: actionCount(2) },
      { desc: "has spoken", fn: hasSpoken },
    ]},
  { id: "6.08", category: "intelligence", say: "I want to work on the Hudson project",
    checks: [
      { desc: "has focus action", fn: hasAction("focus") },
      { desc: "targets hudson", fn: (r) => (r.actions ?? []).some((a: any) => /hudson|10439/i.test(JSON.stringify(a.slots))) },
    ]},
  { id: "6.09", category: "intelligence", say: "Show me everything related to lattices",
    checks: [
      { desc: "has spoken", fn: hasSpoken },
      { desc: "mentions lattices windows", fn: spokenIncludes("lattices") },
    ]},
  { id: "6.10", category: "intelligence", say: "Can you suggest a good layout for what I have open?",
    checks: [
      { desc: "has actions", fn: (r) => (r.actions ?? []).length > 0 },
      { desc: "explains reasoning", fn: (r) => (r.spoken ?? "").length > 30 },
    ]},

  // ── 7. Error Handling (81-90) ────────────────────────────────
  { id: "7.01", category: "error", say: "Focus on Firefox",
    checks: [
      { desc: "says not found", fn: (r) => /can't find|not running|don't see|no.*firefox/i.test(r.spoken ?? "") },
      { desc: "no focus action", fn: (r) => !(r.actions ?? []).some((a: any) => a.intent === "focus") },
    ]},
  { id: "7.02", category: "error", say: "Tile Photoshop to the left",
    checks: [
      { desc: "says not found", fn: (r) => /can't find|not running|don't see|no.*photoshop|isn't open/i.test(r.spoken ?? "") },
      { desc: "no tile action", fn: (r) => !(r.actions ?? []).some((a: any) => a.intent === "tile_window") },
    ]},
  { id: "7.03", category: "error", say: "Switch to the deploy layer",
    checks: [
      { desc: "says not found or no layers", fn: (r) => /don't have|no layer|can't find|not available/i.test(r.spoken ?? "") },
    ]},
  { id: "7.04", category: "error", say: "Open the spreadsheet",
    checks: [
      { desc: "says can't find or asks", fn: (r) => /can't find|don't see|which|what spreadsheet/i.test(r.spoken ?? "") },
    ]},
  { id: "7.05", category: "error", say: "Tile the um the thing",
    checks: [
      { desc: "asks for clarification", fn: (r) => /which|what|can you|say that again|unclear/i.test(r.spoken ?? "") },
    ]},
  { id: "7.06", category: "error", say: "Move everything to the third monitor",
    checks: [
      { desc: "says only two monitors", fn: (r) => /two|only.*2|don't have.*third|no third/i.test(r.spoken ?? "") },
    ]},
  { id: "7.07", category: "error", say: "Tile VS Code left",
    checks: [
      { desc: "says not running", fn: (r) => /not running|don't see|can't find|isn't open/i.test(r.spoken ?? "") },
    ]},
  { id: "7.08", category: "error", say: "Focus on the email window",
    checks: [
      { desc: "says can't find", fn: (r) => /can't find|don't see|no email|not open/i.test(r.spoken ?? "") },
    ]},
  { id: "7.09", category: "error", say: "Blarf the garble",
    checks: [
      { desc: "asks for clarification", fn: (r) => /didn't catch|say.*again|understand|unclear|don't know/i.test(r.spoken ?? "") },
    ]},
  { id: "7.10", category: "error", say: "Tile Chrome to the middle",
    checks: [
      { desc: "interprets as center", fn: (r) => hasActionWithSlot("tile_window", "position", "center")(r) || hasActionWithSlot("tile_window", "position", "center-third")(r) || /center/i.test(r.spoken ?? "") },
    ]},

  // ── 8. Speech Quality (91-100) ───────────────────────────────
  { id: "8.01", category: "speech", say: "What do you see?",
    checks: [
      { desc: "no wids", fn: noWidsInSpeech },
      { desc: "has spoken", fn: hasSpoken },
      { desc: "uses app names", fn: (r) => /chrome|iterm|finder|vox/i.test(r.spoken ?? "") },
    ]},
  { id: "8.02", category: "speech", say: "Tile Chrome left",
    checks: [
      { desc: "spoken confirms action", fn: (r) => /tiling|chrome|left/i.test(r.spoken ?? "") },
      { desc: "not robotic", fn: spokenNotIncludes("executed") },
      { desc: "not sycophantic", fn: spokenNotIncludes("happy to") },
    ]},
  { id: "8.03", category: "speech", say: "Organize my windows",
    checks: [
      { desc: "actions match spoken", fn: (r) => (r.actions ?? []).length > 0 === ((r.spoken ?? "").length > 10) },
      { desc: "spoken describes what it's doing", fn: (r) => (r.spoken ?? "").length > 15 },
    ]},
  { id: "8.04", category: "speech", say: "How many terminals?",
    checks: [
      { desc: "concise answer", fn: (r) => (r.spoken ?? "").length < 200 },
      { desc: "contains a number", fn: (r) => /\d+|one|two|three|four|five|six|seven|eight/i.test(r.spoken ?? "") },
    ]},
  { id: "8.05", category: "speech", say: "Thanks",
    checks: [
      { desc: "short response", fn: (r) => (r.spoken ?? "").length < 100 },
      { desc: "no actions", fn: hasNoActions },
    ]},
  { id: "8.06", category: "speech", say: "What can you do?",
    checks: [
      { desc: "mentions tiling", fn: (r) => /tile|tiling|arrange/i.test(r.spoken ?? "") },
      { desc: "mentions focus", fn: (r) => /focus|switch/i.test(r.spoken ?? "") },
      { desc: "no wids", fn: noWidsInSpeech },
    ]},
  { id: "8.07", category: "speech", say: "Split Chrome and iTerm side by side",
    checks: [
      { desc: "spoken < 100 chars", fn: (r) => (r.spoken ?? "").length < 100 },
      { desc: "no markdown", fn: spokenNotIncludes("```") },
      { desc: "no emoji", fn: (r) => !/[\u{1F600}-\u{1F64F}\u{1F300}-\u{1F5FF}\u{1F680}-\u{1F6FF}]/u.test(r.spoken ?? "") },
    ]},
  { id: "8.08", category: "speech", say: "What's happening on screen?",
    checks: [
      { desc: "no wids", fn: noWidsInSpeech },
      { desc: "uses project names", fn: (r) => /lattices|hudson|vox/i.test(r.spoken ?? "") },
    ]},
  { id: "8.09", category: "speech", say: "Distribute everything",
    checks: [
      { desc: "spoken says what it's doing", fn: (r) => /distribut|grid|arrang/i.test(r.spoken ?? "") },
      { desc: "action matches", fn: hasAction("distribute") },
    ]},
  { id: "8.10", category: "speech", say: "Help me organize for a code review of the lattices PR",
    checks: [
      { desc: "has actions", fn: (r) => (r.actions ?? []).length > 0 },
      { desc: "mentions PR or github", fn: (r) => /pr|github|review|lattices/i.test(r.spoken ?? "") },
      { desc: "no wids", fn: noWidsInSpeech },
    ]},
];

// ── Run tests ──────────────────────────────────────────────────────

async function runTest(test: Test): Promise<{ pass: number; fail: number; errors: string[] }> {
  const messages = (test.history ?? []).map((h) => ({
    role: h.role as "user" | "assistant",
    content: h.content,
  }));

  const userMessage = `USER: "${test.say}"\n\n--- DESKTOP SNAPSHOT ---\n${snapshot}\n--- END SNAPSHOT ---\n`;

  try {
    const raw = await infer(userMessage, {
      provider: "xai",
      model: "grok-4.20-beta-0309-non-reasoning",
      system: systemPrompt,
      messages,
      temperature: 0.2,
      maxTokens: 512,
      tag: `test-${test.id}`,
    });

    // Parse response
    let result: any;
    const cleaned = raw.text.replace(/```json\s*/g, "").replace(/```\s*/g, "").trim();
    const jsonStart = cleaned.indexOf("{");
    const jsonEnd = cleaned.lastIndexOf("}");

    if (jsonStart !== -1 && jsonEnd !== -1) {
      try {
        result = JSON.parse(cleaned.slice(jsonStart, jsonEnd + 1));
      } catch {
        result = { actions: [], spoken: raw.text };
      }
    } else {
      result = { actions: [], spoken: raw.text };
    }

    let pass = 0;
    let fail = 0;
    const errors: string[] = [];

    for (const check of test.checks) {
      if (check.fn(result)) {
        pass++;
      } else {
        fail++;
        errors.push(check.desc);
      }
    }

    return { pass, fail, errors };
  } catch (err: any) {
    return { pass: 0, fail: test.checks.length, errors: [`API error: ${err.message}`] };
  }
}

// ── Main ───────────────────────────────────────────────────────────

console.log(`Running ${tests.length} tests against xai/grok-4.20-beta-0309-non-reasoning...\n`);

let totalPass = 0;
let totalFail = 0;
let totalChecks = 0;
const categoryResults: Record<string, { pass: number; fail: number }> = {};

for (const test of tests) {
  const { pass, fail, errors } = await runTest(test);
  totalPass += pass;
  totalFail += fail;
  totalChecks += pass + fail;

  const cat = test.category;
  if (!categoryResults[cat]) categoryResults[cat] = { pass: 0, fail: 0 };
  categoryResults[cat].pass += pass;
  categoryResults[cat].fail += fail;

  const status = fail === 0 ? "✅" : "❌";
  const errorStr = errors.length > 0 ? ` — FAILED: ${errors.join(", ")}` : "";
  console.log(`${status} ${test.id} [${cat}] "${test.say}"${errorStr}`);
}

console.log(`\n${"=".repeat(60)}`);
console.log(`TOTAL: ${totalPass}/${totalChecks} checks passed (${Math.round(totalPass / totalChecks * 100)}%)\n`);

console.log("By category:");
for (const [cat, { pass, fail }] of Object.entries(categoryResults)) {
  const total = pass + fail;
  const pct = Math.round(pass / total * 100);
  console.log(`  ${cat}: ${pass}/${total} (${pct}%)`);
}

console.log(`\nFailed: ${totalFail} checks across ${tests.filter((_, i) => true).length} tests`);
