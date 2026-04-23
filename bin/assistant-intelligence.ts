import { readFileSync } from "fs";
import { dirname, join } from "path";

export type AssistantSlotValue = string | number | boolean;

export interface AssistantAction {
  intent: string;
  slots?: Record<string, AssistantSlotValue>;
}

export interface AssistantPlan {
  actions: AssistantAction[];
  spoken: string;
  _meta?: Record<string, unknown>;
}

export interface DesktopWindowSnapshot {
  wid?: number;
  app?: string;
  title?: string;
  frame?: string;
  onScreen?: boolean;
  zIndex?: number;
  session?: string;
}

export interface DesktopSnapshot {
  windows?: DesktopWindowSnapshot[];
  activeStage?: DesktopWindowSnapshot[];
  screens?: Array<{ width?: number; height?: number; isMain?: boolean }>;
  stageManager?: boolean;
  smGrouping?: string;
  stripApps?: string[];
  hiddenApps?: string[];
  terminals?: Array<Record<string, unknown>>;
  tmuxSessions?: Array<Record<string, unknown>>;
  currentLayer?: { name?: string; index?: number } | string;
  screen?: string;
}

interface IntentDefinition {
  intent: string;
  description: string;
  slots: Array<{ name: string; required?: boolean; description: string }>;
  examples: string[];
}

const repoRoot = dirname(import.meta.dir);
export const assistantPromptPath = join(repoRoot, "docs", "prompts", "hands-off-system.md");

export const tilePositions = [
  "left",
  "right",
  "top",
  "bottom",
  "top-left",
  "top-right",
  "bottom-left",
  "bottom-right",
  "left-third",
  "center-third",
  "right-third",
  "top-left-third",
  "top-center-third",
  "top-right-third",
  "bottom-left-third",
  "bottom-center-third",
  "bottom-right-third",
  "first-fourth",
  "second-fourth",
  "third-fourth",
  "last-fourth",
  "top-first-fourth",
  "top-second-fourth",
  "top-third-fourth",
  "top-last-fourth",
  "bottom-first-fourth",
  "bottom-second-fourth",
  "bottom-third-fourth",
  "bottom-last-fourth",
  "maximize",
  "center",
] as const;

export const intentDefinitions: IntentDefinition[] = [
  {
    intent: "tile_window",
    description: "Tile one window to a named position or grid cell.",
    slots: [
      { name: "position", required: true, description: "Named tile position or grid:CxR:C,R syntax." },
      { name: "app", description: "Loose app name when no window id is known." },
      { name: "wid", description: "Specific macOS window id from the desktop snapshot." },
      { name: "session", description: "Tmux session name." },
    ],
    examples: [
      "tile chrome left",
      "snap this to the top right",
      "maximize the window",
    ],
  },
  {
    intent: "focus",
    description: "Focus a window, app, or session.",
    slots: [
      { name: "app", description: "Loose app name." },
      { name: "wid", description: "Specific window id." },
      { name: "session", description: "Tmux session name." },
    ],
    examples: ["focus Slack", "show me the lattices terminal"],
  },
  {
    intent: "distribute",
    description: "Arrange visible windows in an even grid, optionally filtered by app and region.",
    slots: [
      { name: "app", description: "Optional app filter." },
      { name: "region", description: "Optional screen region such as left, right, top, or bottom." },
    ],
    examples: ["organize my terminals", "grid Chrome on the right"],
  },
  {
    intent: "swap",
    description: "Swap two windows by id.",
    slots: [
      { name: "wid_a", required: true, description: "First window id." },
      { name: "wid_b", required: true, description: "Second window id." },
    ],
    examples: ["swap Chrome and iTerm"],
  },
  {
    intent: "hide",
    description: "Hide an app or minimize a window.",
    slots: [
      { name: "app", description: "App name to hide." },
      { name: "wid", description: "Window id to minimize." },
    ],
    examples: ["hide Slack", "minimize that"],
  },
  {
    intent: "highlight",
    description: "Flash a window border so the user can identify it.",
    slots: [
      { name: "app", description: "App name to find." },
      { name: "wid", description: "Window id to flash." },
    ],
    examples: ["which one is the lattices terminal", "highlight Chrome"],
  },
  {
    intent: "move_to_display",
    description: "Move a window to another display, optionally placing it there.",
    slots: [
      { name: "display", required: true, description: "Display index, where 0 is main." },
      { name: "position", description: "Optional tile position on the target display." },
      { name: "app", description: "App name when no window id is known." },
      { name: "wid", description: "Specific window id." },
    ],
    examples: ["move Chrome to my second monitor"],
  },
  {
    intent: "undo",
    description: "Restore the previous window positions.",
    slots: [],
    examples: ["undo that", "put it back"],
  },
  {
    intent: "search",
    description: "Search windows, terminal context, and OCR content.",
    slots: [{ name: "query", required: true, description: "Search text." }],
    examples: ["find the error message", "search for terminal windows"],
  },
  {
    intent: "list_windows",
    description: "List visible windows.",
    slots: [],
    examples: ["what windows are open"],
  },
  {
    intent: "list_sessions",
    description: "List active terminal sessions.",
    slots: [],
    examples: ["what sessions are running"],
  },
  {
    intent: "switch_layer",
    description: "Switch to a workspace layer.",
    slots: [{ name: "layer", required: true, description: "Layer name or index." }],
    examples: ["switch to the review layer", "go to layer 2"],
  },
  {
    intent: "create_layer",
    description: "Save current arrangement as a named layer.",
    slots: [{ name: "name", required: true, description: "Layer name." }],
    examples: ["save this layout as deploy"],
  },
  {
    intent: "launch",
    description: "Launch a project session.",
    slots: [{ name: "project", required: true, description: "Project name or path." }],
    examples: ["open the frontend project"],
  },
  {
    intent: "kill",
    description: "Kill a terminal session.",
    slots: [{ name: "session", required: true, description: "Session name or project name." }],
    examples: ["kill the API session"],
  },
  {
    intent: "scan",
    description: "Trigger immediate OCR scan.",
    slots: [],
    examples: ["scan the screen", "read what's on screen"],
  },
  {
    intent: "find_mouse",
    description: "Show the cursor location with a pulse.",
    slots: [],
    examples: ["find my mouse"],
  },
  {
    intent: "summon_mouse",
    description: "Move the cursor to the center of the screen.",
    slots: [],
    examples: ["summon mouse"],
  },
];

const positionAliases: Array<{ position: string; phrases: string[] }> = [
  { position: "top-left", phrases: ["top left", "upper left", "top-left"] },
  { position: "top-right", phrases: ["top right", "upper right", "top-right"] },
  { position: "bottom-left", phrases: ["bottom left", "lower left", "bottom-left"] },
  { position: "bottom-right", phrases: ["bottom right", "lower right", "bottom-right"] },
  { position: "left-third", phrases: ["left third", "first third", "left-third"] },
  { position: "center-third", phrases: ["center third", "middle third", "centre third", "center-third"] },
  { position: "right-third", phrases: ["right third", "last third", "right-third"] },
  { position: "left", phrases: ["left half", "left side", "the left", "left"] },
  { position: "right", phrases: ["right half", "right side", "the right", "right"] },
  { position: "top", phrases: ["top half", "upper half", "the top", "top"] },
  { position: "bottom", phrases: ["bottom half", "lower half", "the bottom", "bottom"] },
  { position: "maximize", phrases: ["maximize", "maximise", "full screen", "fullscreen", "make it big", "max"] },
  { position: "center", phrases: ["center", "centre", "middle"] },
];

const appAliases: Record<string, string[]> = {
  "Google Chrome": ["chrome", "google chrome"],
  iTerm2: ["iterm", "iterm2", "terminal", "terminals"],
  Terminal: ["terminal app", "terminal"],
  "Visual Studio Code": ["vs code", "vscode", "visual studio code"],
};

const noisePrefixes = [
  "can you",
  "could you",
  "would you",
  "please",
  "just",
  "go ahead and",
  "let's",
  "lets",
  "i want to",
  "i need to",
  "i'd like to",
  "id like to",
  "ok",
  "okay",
  "hey",
  "yo",
];

const fillerWords = new Set([
  "the",
  "my",
  "a",
  "an",
  "this",
  "that",
  "it",
  "window",
  "windows",
  "app",
  "application",
  "project",
  "session",
  "layer",
  "please",
  "for",
  "me",
  "to",
  "in",
  "on",
  "into",
  "at",
  "side",
  "half",
  "corner",
]);

export function renderIntentCatalog(): string {
  const parts = intentDefinitions.map((def) => {
    const slots = def.slots.length
      ? def.slots.map((slot) => {
          const marker = slot.required ? " required" : " optional";
          return `    ${slot.name} (${marker}): ${slot.description}`;
        }).join("\n")
      : "    none";
    return [
      `${def.intent}: ${def.description}`,
      "  Slots:",
      slots,
      `  Examples: ${def.examples.map((x) => `"${x}"`).join(", ")}`,
    ].join("\n");
  });

  return `${parts.join("\n\n")}

TILING PRESETS:
  "split screen" / "side by side" -> tile_window left + right
  "thirds" -> left-third + center-third + right-third
  "quadrants" / "four corners" -> top-left + top-right + bottom-left + bottom-right
  "mosaic" / "grid" / "spread out" -> distribute

POSITION RULES:
  "quarter" means a 2x2 cell, not a 4x1 fourth.
  Use wid from the snapshot when a target window is clear.
  Use app only when no specific wid is available.`;
}

export function buildAssistantSystemPrompt(): string {
  let prompt: string;
  try {
    prompt = readFileSync(assistantPromptPath, "utf-8")
      .split("\n")
      .filter((line) => !line.startsWith("# "))
      .join("\n")
      .trim();
  } catch {
    prompt = "You are a workspace assistant. Respond with JSON: {actions, spoken}.";
  }

  return prompt.replace("{{intent_catalog}}", renderIntentCatalog());
}

export function buildAssistantContextMessage(transcript: string, snapshot: DesktopSnapshot = {}): string {
  let msg = `USER: "${transcript}"\n\n`;
  msg += "--- DESKTOP SNAPSHOT ---\n";

  const screens = snapshot.screens ?? [];
  if (screens.length > 1) {
    msg += `Displays: ${screens.map((s) => `${s.width}x${s.height}${s.isMain ? " (main)" : ""}`).join(", ")}\n`;
  } else if (screens.length === 1) {
    msg += `Screen: ${screens[0].width}x${screens[0].height}\n`;
  } else if (snapshot.screen) {
    msg += `Screen: ${snapshot.screen}\n`;
  }

  msg += `Stage Manager: ${snapshot.stageManager ? `ON (${snapshot.smGrouping ?? "all-at-once"})` : "OFF"}\n`;

  const windows = listWindows(snapshot);
  const onScreen = windows.filter((w) => w.onScreen !== false);
  const offScreen = windows.filter((w) => w.onScreen === false);

  msg += `\nVisible windows (${onScreen.length}, front-to-back order):\n`;
  for (const w of onScreen) {
    const flags: string[] = [];
    if (w.zIndex === 0) flags.push("FRONTMOST");
    if (w.session) flags.push(`session:${w.session}`);
    const flagStr = flags.length ? ` [${flags.join(", ")}]` : "";
    msg += `  wid:${w.wid ?? "?"} ${w.app ?? "Unknown"}: "${w.title ?? ""}"`;
    if (w.frame) msg += ` - ${w.frame}`;
    msg += `${flagStr}\n`;
  }

  if (offScreen.length > 0) {
    const hiddenByApp = new Map<string, number>();
    for (const w of offScreen) {
      if (!w.app) continue;
      hiddenByApp.set(w.app, (hiddenByApp.get(w.app) ?? 0) + 1);
    }
    const summary = [...hiddenByApp.entries()].map(([app, count]) => `${app}(${count})`).join(", ");
    if (summary) msg += `\nHidden windows: ${summary}\n`;
  }

  const terminals = snapshot.terminals ?? [];
  if (terminals.length > 0) {
    msg += `\nTerminal tabs (${terminals.length}):\n`;
    for (const tab of terminals) {
      const displayName = String(tab.displayName ?? tab.app ?? "Terminal");
      const cwd = typeof tab.cwd === "string" ? ` cwd:${tab.cwd.replace(/^\/Users\/[^/]+\//, "~/")}` : "";
      const tmux = tab.tmuxSession ? ` tmux:${String(tab.tmuxSession)}` : "";
      const claude = tab.hasClaude ? " Claude Code" : "";
      const wid = tab.windowId ? ` wid:${String(tab.windowId)}` : "";
      msg += `  ${displayName}${cwd}${tmux}${claude}${wid}\n`;
    }
  }

  const sessions = snapshot.tmuxSessions ?? [];
  if (sessions.length > 0) {
    msg += `\nTmux sessions: ${sessions.map((s) => String(s.name ?? "unknown")).join(", ")}\n`;
  }

  if (snapshot.currentLayer) {
    const layer = typeof snapshot.currentLayer === "string"
      ? snapshot.currentLayer
      : `${snapshot.currentLayer.name ?? "unknown"} (index: ${snapshot.currentLayer.index ?? "?"})`;
    msg += `\nCurrent layer: ${layer}\n`;
  }

  msg += "--- END SNAPSHOT ---\n";
  return msg;
}

export function tryLocalAssistantPlan(transcript: string, snapshot: DesktopSnapshot = {}): AssistantPlan | null {
  const text = normalizeTranscript(transcript);
  if (!text) return null;

  if (/^(undo|put it back|restore|restore that|that was wrong)/.test(text)) {
    return plan([{ intent: "undo", slots: {} }], "Restoring the previous positions.", "local-rule");
  }

  if (/(find|show|where).*(mouse|cursor)/.test(text)) {
    return plan([{ intent: "find_mouse", slots: {} }], "Showing your cursor.", "local-rule");
  }

  if (/(summon|center|bring).*(mouse|cursor)/.test(text)) {
    return plan([{ intent: "summon_mouse", slots: {} }], "Moving the cursor to the center.", "local-rule");
  }

  if (/^(scan|read|ocr|rescan)/.test(text) && /(screen|window|text|ocr)/.test(text)) {
    return plan([{ intent: "scan", slots: {} }], "Scanning the screen.", "local-rule");
  }

  const split = parseSplitPlan(text, snapshot);
  if (split) return split;

  const layout = parseLayoutPlan(text, snapshot);
  if (layout) return layout;

  const tile = parseTilePlan(text, snapshot);
  if (tile) return tile;

  const distribute = parseDistributePlan(text);
  if (distribute) return distribute;

  const focus = parsePrefixedEntity(text, [
    "focus on",
    "focus",
    "switch to",
    "go to",
    "show me",
    "show",
    "bring up",
    "pull up",
  ]);
  if (focus && !/(layer|screen|windows|sessions)/.test(focus)) {
    const target = resolveWindowTarget(focus, snapshot);
    const slots = targetToSlots(target, focus);
    return plan([{ intent: "focus", slots }], `Focusing ${target.label}.`, "local-rule");
  }

  const search = parseSearchQuery(text);
  if (search) {
    return plan([{ intent: "search", slots: { query: search } }], `Searching for ${search}.`, "local-rule");
  }

  if (/what.*windows|list windows|show.*windows|what.*open|what.*on screen/.test(text)) {
    return plan([{ intent: "list_windows", slots: {} }], summarizeWindows(snapshot), "local-rule");
  }

  if (/sessions|projects.*running|what.*running/.test(text) && !/kill|stop/.test(text)) {
    return plan([{ intent: "list_sessions", slots: {} }], "Listing your sessions.", "local-rule");
  }

  const layer = parseLayerSwitch(text);
  if (layer) {
    return plan([{ intent: "switch_layer", slots: { layer } }], `Switching to ${layer}.`, "local-rule");
  }

  const layerName = parsePrefixedEntity(text, [
    "save this layout as",
    "save layout as",
    "create a layer called",
    "create layer called",
    "make a layer called",
    "name this layer",
  ]);
  if (layerName) {
    return plan([{ intent: "create_layer", slots: { name: cleanEntity(layerName) } }], `Saving this layout as ${cleanEntity(layerName)}.`, "local-rule");
  }

  const launch = parsePrefixedEntity(text, [
    "open project",
    "open the project",
    "open",
    "launch",
    "start working on",
    "work on",
  ]);
  if (launch && !looksLikeAppCommand(launch)) {
    const project = cleanEntity(launch);
    return plan([{ intent: "launch", slots: { project } }], `Launching ${project}.`, "local-rule");
  }

  const kill = parsePrefixedEntity(text, ["kill", "stop", "shut down", "terminate"]);
  if (kill) {
    const session = cleanEntity(kill);
    return plan([{ intent: "kill", slots: { session } }], `Killing ${session}.`, "local-rule");
  }

  return null;
}

export function normalizeAssistantPlan(raw: unknown, fallbackTranscript = ""): AssistantPlan {
  const obj = isRecord(raw) ? raw : {};
  const rawActions = Array.isArray(obj.actions) ? obj.actions : [];
  const actions = rawActions
    .map(normalizeAction)
    .filter((action): action is AssistantAction => action !== null);

  const spokenRaw = typeof obj.spoken === "string" ? obj.spoken.trim() : "";
  const spoken = spokenRaw || fallbackSpoken(actions, fallbackTranscript);

  return {
    actions,
    spoken,
    _meta: isRecord(obj._meta) ? obj._meta : undefined,
  };
}

function normalizeAction(raw: unknown): AssistantAction | null {
  if (!isRecord(raw)) return null;

  const intent = normalizeIntentName(String(raw.intent ?? raw.action ?? ""));
  if (!intent) return null;

  const slotsRaw = isRecord(raw.slots) ? raw.slots : {};
  const slots: Record<string, AssistantSlotValue> = {};
  for (const [key, value] of Object.entries(slotsRaw)) {
    if (typeof value === "string" || typeof value === "number" || typeof value === "boolean") {
      slots[key] = value;
    }
  }

  return { intent, slots };
}

function normalizeIntentName(intent: string): string {
  const lower = intent.trim().toLowerCase().replace(/[.\s-]+/g, "_");
  const aliases: Record<string, string> = {
    window_place: "tile_window",
    window_tile: "tile_window",
    layer_activate: "switch_layer",
    layer_switch: "switch_layer",
    space_optimize: "distribute",
    layout_distribute: "distribute",
  };
  return aliases[lower] ?? lower;
}

function parseTilePlan(text: string, snapshot: DesktopSnapshot): AssistantPlan | null {
  if (!/(tile|snap|put|move|throw|maximize|maximise|center|centre|full screen|fullscreen)/.test(text)) {
    return null;
  }

  const hit = findPosition(text);
  if (!hit) return null;

  let targetText = text
    .replace(/^(tile|snap|put|move|throw)\s+/, "")
    .replace(hit.phrase, " ")
    .replace(/\b(to|in|on|into|at|the|half|side|corner)\b/g, " ");

  if (/^(maximize|maximise|full screen|fullscreen|center|centre)/.test(text)) {
    targetText = "";
  }

  const target = resolveWindowTarget(cleanEntity(targetText), snapshot);
  const slots = { ...targetToSlots(target, cleanEntity(targetText)), position: hit.position };
  return plan([{ intent: "tile_window", slots }], tileSpoken(target.label, hit.position), "local-rule");
}

function parseSplitPlan(text: string, snapshot: DesktopSnapshot): AssistantPlan | null {
  const match = text.match(/split\s+(.+?)\s+(?:and|with|&)\s+(.+)/);
  if (match) {
    const left = resolveWindowTarget(match[1], snapshot);
    const right = resolveWindowTarget(match[2], snapshot);
    return plan([
      { intent: "tile_window", slots: { ...targetToSlots(left, match[1]), position: "left" } },
      { intent: "tile_window", slots: { ...targetToSlots(right, match[2]), position: "right" } },
    ], `${left.label} left, ${right.label} right.`, "local-rule");
  }

  const explicit = text.match(/(.+?)\s+left\s+(.+?)\s+right$/);
  if (explicit && /(chrome|safari|iterm|terminal|slack|code|cursor|finder)/.test(text)) {
    const left = resolveWindowTarget(explicit[1], snapshot);
    const right = resolveWindowTarget(explicit[2], snapshot);
    return plan([
      { intent: "tile_window", slots: { ...targetToSlots(left, explicit[1]), position: "left" } },
      { intent: "tile_window", slots: { ...targetToSlots(right, explicit[2]), position: "right" } },
    ], `${left.label} left, ${right.label} right.`, "local-rule");
  }

  return null;
}

function parseLayoutPlan(text: string, snapshot: DesktopSnapshot): AssistantPlan | null {
  const windows = listWindows(snapshot).filter((w) => w.onScreen !== false);

  if (/(quadrants?|four corners?|corners)/.test(text) && windows.length >= 4) {
    const positions = ["top-left", "top-right", "bottom-left", "bottom-right"];
    const actions = windows.slice(0, 4).map((w, index) => ({
      intent: "tile_window",
      slots: { wid: w.wid ?? 0, position: positions[index] },
    }));
    return plan(actions, "Putting four windows in quadrants.", "local-rule");
  }

  if (/\bthirds\b/.test(text) && windows.length >= 3) {
    const positions = ["left-third", "center-third", "right-third"];
    const actions = windows.slice(0, 3).map((w, index) => ({
      intent: "tile_window",
      slots: { wid: w.wid ?? 0, position: positions[index] },
    }));
    return plan(actions, "Arranging three windows in thirds.", "local-rule");
  }

  if (/(split screen|side by side)/.test(text) && windows.length >= 2) {
    return plan([
      { intent: "tile_window", slots: { wid: windows[0].wid ?? 0, position: "left" } },
      { intent: "tile_window", slots: { wid: windows[1].wid ?? 0, position: "right" } },
    ], "Splitting the front two windows.", "local-rule");
  }

  return null;
}

function parseDistributePlan(text: string): AssistantPlan | null {
  if (!/(grid|mosaic|distribute|spread|organize|organise|arrange|tidy|clean up)/.test(text)) {
    return null;
  }

  const slots: Record<string, AssistantSlotValue> = {};
  const app = appFromText(text);
  const region = regionFromText(text);
  if (app) slots.app = app;
  if (region) slots.region = region;

  const scope = app ? `${app} windows` : "your windows";
  const where = region ? ` on the ${region}` : "";
  return plan([{ intent: "distribute", slots }], `Gridding ${scope}${where}.`, "local-rule");
}

function parseSearchQuery(text: string): string | null {
  const query = parsePrefixedEntity(text, [
    "find all",
    "find",
    "search for",
    "search",
    "look for",
    "locate",
    "where is",
    "where does it say",
    "which window has",
  ]);
  if (!query) return null;
  return cleanQuery(query);
}

function parseLayerSwitch(text: string): string | null {
  if (text === "next layer" || text === "previous layer") return text;
  const literal: Record<string, string> = {
    "layer one": "1",
    "layer two": "2",
    "layer three": "3",
    "first layer": "1",
    "second layer": "2",
    "third layer": "3",
  };
  if (literal[text]) return literal[text];
  const entity = parsePrefixedEntity(text, [
    "switch to layer",
    "switch to the",
    "switch to",
    "go to layer",
    "go to the",
    "activate layer",
    "layer",
  ]);
  return entity ? cleanEntity(entity).replace(/\s+layer$/, "") : null;
}

function findPosition(text: string): { position: string; phrase: string } | null {
  const grid = text.match(/grid:\d+x\d+:\d+,\d+/);
  if (grid) return { position: grid[0], phrase: grid[0] };

  for (const entry of positionAliases) {
    for (const phrase of entry.phrases) {
      if (text.includes(phrase)) {
        return { position: entry.position, phrase };
      }
    }
  }
  return null;
}

function regionFromText(text: string): string | null {
  const hit = findPosition(text);
  if (!hit) return null;
  return ["left", "right", "top", "bottom", "top-left", "top-right", "bottom-left", "bottom-right", "left-third", "center-third", "right-third"].includes(hit.position)
    ? hit.position
    : null;
}

function appFromText(text: string): string | null {
  for (const [app, aliases] of Object.entries(appAliases)) {
    if (aliases.some((alias) => text.includes(alias))) return app;
  }

  const entity = parsePrefixedEntity(text, ["grid", "organize", "organise", "arrange", "distribute"]);
  return entity ? titleCase(cleanEntity(entity).replace(/\bon (left|right|top|bottom).*$/, "")) : null;
}

function parsePrefixedEntity(text: string, prefixes: string[]): string | null {
  const sorted = [...prefixes].sort((a, b) => b.length - a.length);
  for (const prefix of sorted) {
    if (text === prefix) return "";
    if (text.startsWith(`${prefix} `)) {
      return text.slice(prefix.length + 1).trim();
    }
  }
  return null;
}

function normalizeTranscript(input: string): string {
  let text = String(input ?? "")
    .toLowerCase()
    .replace(/[^a-z0-9\s:-]/g, " ")
    .split(/\s+/)
    .join(" ")
    .trim();

  let changed = true;
  while (changed) {
    changed = false;
    for (const prefix of noisePrefixes) {
      if (text.startsWith(`${prefix} `)) {
        text = text.slice(prefix.length + 1).trim();
        changed = true;
      }
    }
  }

  return text;
}

function cleanEntity(input: string): string {
  const words = input
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, " ")
    .split(/\s+/)
    .filter((word) => word && !fillerWords.has(word));
  return words.join(" ").trim();
}

function cleanQuery(input: string): string {
  return cleanEntity(input)
    .replace(/\ball\b/g, " ")
    .replace(/\bwith\b/g, " ")
    .split(/\s+/)
    .filter(Boolean)
    .join(" ");
}

function listWindows(snapshot: DesktopSnapshot): DesktopWindowSnapshot[] {
  const raw = snapshot.windows ?? snapshot.activeStage ?? [];
  return raw
    .filter((w) => w && (w.app || w.title || w.wid))
    .sort((a, b) => (a.zIndex ?? 999) - (b.zIndex ?? 999));
}

function resolveWindowTarget(raw: string, snapshot: DesktopSnapshot): { wid?: number; app?: string; label: string } {
  const cleaned = cleanEntity(raw);
  const windows = listWindows(snapshot).filter((w) => w.onScreen !== false);

  if (!cleaned || ["this", "that", "it"].includes(cleaned)) {
    const front = windows.find((w) => w.zIndex === 0) ?? windows[0];
    if (front?.wid) return { wid: front.wid, app: front.app, label: front.app ?? "this window" };
    return { label: "this window" };
  }

  for (const [app, aliases] of Object.entries(appAliases)) {
    if (aliases.includes(cleaned)) {
      const win = windows.find((w) => w.app?.toLowerCase().includes(app.toLowerCase()));
      if (win?.wid) return { wid: win.wid, app: win.app, label: win.app ?? app };
      return { app, label: app };
    }
  }

  const win = windows.find((w) => {
    const app = w.app?.toLowerCase() ?? "";
    const title = w.title?.toLowerCase() ?? "";
    return app.includes(cleaned) || cleaned.includes(app) || title.includes(cleaned);
  });
  if (win?.wid) return { wid: win.wid, app: win.app, label: win.app ?? cleaned };

  return { app: titleCase(cleaned), label: titleCase(cleaned) };
}

function targetToSlots(target: { wid?: number; app?: string }, fallback: string): Record<string, AssistantSlotValue> {
  if (target.wid) return { wid: target.wid };
  if (target.app) return { app: target.app };
  const cleaned = cleanEntity(fallback);
  return cleaned ? { app: titleCase(cleaned) } : {};
}

function tileSpoken(label: string, position: string): string {
  if (position === "maximize") return `Maximizing ${label}.`;
  if (position === "center") return `Centering ${label}.`;
  return `Tiling ${label} to the ${position}.`;
}

function summarizeWindows(snapshot: DesktopSnapshot): string {
  const windows = listWindows(snapshot).filter((w) => w.onScreen !== false);
  if (!windows.length) return "I do not see any windows in the snapshot.";
  const counts = new Map<string, number>();
  for (const w of windows) {
    const app = w.app ?? "Unknown";
    counts.set(app, (counts.get(app) ?? 0) + 1);
  }
  const summary = [...counts.entries()]
    .slice(0, 5)
    .map(([app, count]) => count === 1 ? app : `${count} ${app}`)
    .join(", ");
  return `You've got ${windows.length} windows: ${summary}.`;
}

function fallbackSpoken(actions: AssistantAction[], transcript: string): string {
  if (actions.length === 0) return transcript ? `I heard ${transcript}, but I do not have an action for it.` : "No action planned.";
  if (actions.length === 1) {
    const action = actions[0];
    if (action.intent === "tile_window") return tileSpoken(String(action.slots?.app ?? "this window"), String(action.slots?.position ?? "there"));
    if (action.intent === "focus") return `Focusing ${String(action.slots?.app ?? "that window")}.`;
    if (action.intent === "distribute") return "Arranging the windows.";
  }
  return "I'll handle that.";
}

function plan(actions: AssistantAction[], spoken: string, source: string): AssistantPlan {
  return { actions, spoken, _meta: { source } };
}

function titleCase(input: string): string {
  return input
    .split(/\s+/)
    .filter(Boolean)
    .map((word) => word.slice(0, 1).toUpperCase() + word.slice(1))
    .join(" ");
}

function looksLikeAppCommand(input: string): boolean {
  return /(chrome|safari|slack|finder|iterm|terminal|code|cursor|xcode)/.test(input);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

if (import.meta.main) {
  const args = process.argv.slice(2);
  const json = args.includes("--json");
  const text = args.filter((arg) => arg !== "--json").join(" ");
  const stdin = await Bun.stdin.text();
  const snapshot = stdin.trim() ? JSON.parse(stdin) as DesktopSnapshot : {};
  const local = tryLocalAssistantPlan(text, snapshot);
  const result = local ?? { actions: [], spoken: "No local plan matched.", _meta: { source: "local-rule", matched: false } };
  console.log(json ? JSON.stringify(result, null, 2) : result.spoken);
}
