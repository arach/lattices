#!/usr/bin/env bun

import { mkdir } from "node:fs/promises";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  readlinkSync,
  renameSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { dirname, isAbsolute, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  assessNavigation,
  browserOpenMode,
  navigationIsReady,
  regularChromeLaunchArgs,
  shouldReuseCurrentTab,
} from "./navigation.ts";
import {
  DEFAULT_WINDOW_SIZE,
  MAX_DEVICE_SCALE_FACTOR,
  MAX_VIEWPORT_EDGE,
  MIN_DEVICE_SCALE_FACTOR,
  MIN_VIEWPORT_EDGE,
  measureDrift,
  parseResizeRequest,
  widthClass,
  windowBoundsFor,
  type ViewportOverride,
} from "./viewport.ts";

// Keep in step with every plugin manifest. `bun run plugin:version` checks and sets this.
const SERVER_VERSION = "0.3.0";

type JsonObject = Record<string, unknown>;

type JsonRpcRequest = {
  jsonrpc: "2.0";
  id?: string | number | null;
  method: string;
  params?: JsonObject;
};

type ChromeTarget = {
  id: string;
  type: string;
  title: string;
  url: string;
  webSocketDebuggerUrl?: string;
};

type ToolResult = {
  content: Array<
    | { type: "text"; text: string }
    | { type: "image"; data: string; mimeType: "image/png" }
  >;
  structuredContent?: JsonObject;
  isError?: boolean;
};

type BrowserClaim = {
  session: string;
  pid: number;
  ownerStartedAt: number;
  profile: string;
  profileDir: string;
  debugPort: number;
  claimedAt: string;
};

type ReleaseOutcome = {
  reason: string;
  closed: boolean;
  liveOwners: number;
};

const debugPort = Number(process.env.ACTION_BROWSER_DEBUG_PORT ?? "9334");
const profileRoot = process.env.ACTION_BROWSER_PROFILE_ROOT
  ?? process.env.ACTION_CHROME_COMPANION_PROFILE_ROOT
  ?? join(homedir(), "Library/Application Support/Action/ChromeProfiles");
const fixedProfileDir = process.env.ACTION_BROWSER_PROFILE_DIR
  ?? process.env.ACTION_CHROME_COMPANION_PROFILE_DIR;
let profileName = sanitizeProfileName(
  process.env.ACTION_BROWSER_PROFILE
    ?? process.env.ACTION_CHROME_COMPANION_PROFILE
    ?? "agent-browser",
);
let profileDir = fixedProfileDir ?? join(profileRoot, profileName);
const artifactRoot = process.env.ACTION_BROWSER_ARTIFACT_DIR
  ?? join(homedir(), "Library/Application Support/Action/BrowserArtifacts");
const sessionRoot = process.env.ACTION_BROWSER_SESSION_DIR
  ?? join(homedir(), "Library/Application Support/Action/BrowserSessions");
const sessionName = (process.env.ACTION_BROWSER_SESSION
  ?? `action-${process.pid}-${Math.random().toString(36).slice(2, 8)}`)
  .replace(/[^A-Za-z0-9._-]/g, "-");
const idleTimeoutMs = Math.max(0, Number(process.env.ACTION_BROWSER_IDLE_TIMEOUT_MS ?? "900000") || 0);
const shutdownBudgetMs = Math.max(500, Number(process.env.ACTION_BROWSER_SHUTDOWN_TIMEOUT_MS ?? "4000") || 4_000);
const chromeAppName = process.env.ACTION_BROWSER_CHROME_APP ?? "Google Chrome";
const chromeBaseURL = `http://127.0.0.1:${debugPort}`;
const companionBridgeHealthURL = process.env.ACTION_CHROME_COMPANION_HEALTH_URL
  ?? "http://127.0.0.1:4321/health";
const textDecoder = new TextDecoder();
let currentTargetId: string | undefined;
/**
 * Emulated viewports, keyed by tab id. A device-metrics override lives on the CDP
 * client session, so it would vanish with the socket every tool call closes. Keeping
 * it here and re-applying it per session is what makes a resize hold across a later
 * screenshot or snapshot. Nothing is written to the profile: quit Chrome and the
 * override is gone.
 */
const viewportOverrides = new Map<string, ViewportOverride>();
let claimHeld = false;
let ownsBrowser = false;
let shuttingDown = false;
let idleTimer: ReturnType<typeof setTimeout> | undefined;

function sanitizeProfileName(name: string): string {
  const cleaned = name.trim().replace(/[^A-Za-z0-9._-]/g, "-");
  if (!cleaned || cleaned === "." || cleaned === "..") {
    throw new Error(`Invalid Action profile name: ${name}`);
  }
  return cleaned;
}

function resolveActionRoot(): string {
  if (process.env.ACTION_ROOT) return resolve(process.env.ACTION_ROOT);
  // plugins/action-browser/server -> repo root
  return resolve(fileURLToPath(new URL("../../..", import.meta.url)));
}

function companionScriptsDir(): string {
  return join(resolveActionRoot(), "packages/chrome-companion/scripts");
}

function companionDistDir(): string {
  return join(resolveActionRoot(), "packages/chrome-companion/dist");
}

function writeProfileMeta(name: string, dir: string): void {
  try {
    mkdirSync(dir, { recursive: true });
    writeFileSync(
      join(dir, ".action-profile.json"),
      `${JSON.stringify({
        name,
        profileDir: dir,
        extensionDist: companionDistDir(),
        debugPort,
        updatedAt: new Date().toISOString(),
      }, null, 2)}\n`,
    );
  } catch {
    // Metadata is best-effort.
  }
}

function listActionProfilesOnDisk(): Array<{
  name: string;
  userDataDir: string;
  current: boolean;
  hasCookiesDb: boolean;
  meta: JsonObject | null;
}> {
  if (!existsSync(profileRoot)) return [];
  return readdirSync(profileRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && !entry.name.startsWith("."))
    .map((entry) => {
      const userDataDir = join(profileRoot, entry.name);
      const defaultDir = existsSync(join(userDataDir, "Cookies"))
        ? userDataDir
        : join(userDataDir, "Default");
      const metaPath = join(userDataDir, ".action-profile.json");
      let meta: JsonObject | null = null;
      if (existsSync(metaPath)) {
        try {
          meta = JSON.parse(readFileSync(metaPath, "utf8")) as JsonObject;
        } catch {
          meta = null;
        }
      }
      return {
        name: entry.name,
        userDataDir,
        current: userDataDir === profileDir,
        hasCookiesDb: existsSync(join(defaultDir, "Cookies")),
        meta,
      };
    })
    .sort((left, right) => left.name.localeCompare(right.name));
}

async function loadCookieModule(): Promise<{
  importCookiesToActionProfile: (args: {
    into?: string;
    sourceProfile?: string;
    domains?: string[];
    selectors?: Array<{ hostKey?: string; name: string }>;
  }) => {
    into: string;
    sourceProfilePath: string;
    destUserDataDir: string;
    destProfilePath: string;
    cookies: string[];
    count: number;
  };
  listCookieEntries: (
    profileDir: string,
    opts: { domains?: string[]; selectors?: Array<{ hostKey?: string; name: string }> },
  ) => Array<{ hostKey: string; name: string }>;
  listPersonalProfiles: () => Array<{ dir: string; name: string; path: string }>;
  parseCookieSelectors: (specs: string[]) => Array<{ hostKey?: string; name: string }>;
  resolveSourceProfileDir: (profileDir?: string) => string;
}> {
  const modulePath = join(companionScriptsDir(), "chrome-cookies.mjs");
  if (!existsSync(modulePath)) {
    throw new Error(
      `Cookie tooling not found at ${modulePath}. ` +
      "Set ACTION_ROOT to the Action monorepo root when using the marketplace plugin outside the repo.",
    );
  }
  return await import(modulePath);
}

// The three browsers an agent can end up talking to. Keep this list, the tool
// descriptions, docs/browser-profiles.md, and the skill saying the same thing.
const BROWSER_SURFACES = [
  {
    id: "regular-chrome",
    label: "The user's regular Chrome",
    what: "Their everyday browser and its real profiles (Default, Profile 1 / \"Work\", ...), with their tabs, history, extensions, and logins.",
    reach: "browser_open with mode=regular opens a URL there and stops. No CDP, no DOM tools.",
    control: "Action native screen + accessibility control: action.observe.snapshot, action.resolve.target, action.act.execute.",
    why: "Chrome 136 and later ignore remote-debugging switches for the user's default data directory, and Action does not try to bypass that.",
  },
  {
    id: "action-browser",
    label: "An Action browser",
    what: "A real, non-headless Chrome that Action owns, running on its own user-data-dir. The default identity agent-browser starts blank and signed into nothing.",
    reach: "Full DOM tooling: browser_snapshot, browser_click, browser_fill, browser_screenshot, browser_tabs.",
    control: "CDP on a private debug port, plus the optional Chrome Companion extension for richer observe/act.",
    why: "Isolated from the user's browsing, so an agent can drive it without touching their session.",
  },
  {
    id: "action-identity",
    label: "An Action browser identity seeded from a regular Chrome profile",
    what: "The same Action-owned Chrome under a named identity (for example work), carrying cookies copied from one of the user's real Chrome profiles for an explicit domain allowlist.",
    reach: "Full DOM tooling, on pages the user is already signed in to.",
    control: "browser_import_cookies to seed, browser_use_profile or browser_open profile to drive.",
    why: "The way to get signed-in DOM control without automating the user's own browser.",
  },
] as const;

const tools = [
  {
    name: "browser_profiles",
    title: "List Action Browser Identities",
    description: "List the Action browser identities on this machine (named Chrome profiles Action owns under ChromeProfiles) and which one is active. These are not the user's regular Chrome profiles. Only an Action browser can be driven with browser_snapshot / browser_click / browser_fill / browser_screenshot.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
    annotations: { readOnlyHint: true, idempotentHint: true },
  },
  {
    name: "browser_use_profile",
    title: "Use Action Browser Identity",
    description: "Switch the active Action browser identity to a named profile. Any name is valid; an unknown name creates a fresh blank identity on first open. Closes the Action Chrome this session owned. This never attaches to the user's regular Chrome, which is driven through Action's native screen + accessibility tools instead.",
    inputSchema: {
      type: "object",
      properties: {
        profile: {
          type: "string",
          description: "Action browser identity name. agent-browser is the blank default. Use a descriptive name such as work for an identity seeded from a regular Chrome profile via browser_import_cookies.",
        },
      },
      required: ["profile"],
      additionalProperties: false,
    },
    annotations: { readOnlyHint: false, idempotentHint: true },
  },
  {
    name: "browser_profile_info",
    title: "Current Browser Identity Info",
    description: "Report the active Action browser identity: profile name, user-data-dir, whether it already has a cookie store, CDP port, companion extension dist, and optional companion bridge health.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
    annotations: { readOnlyHint: true, idempotentHint: true },
  },
  {
    name: "browser_import_cookies",
    title: "Seed Action Browser Identity From Regular Chrome",
    description: "Copy selected cookies from one of the user's regular Chrome profiles into an Action browser identity, so that identity is signed in for those domains and can still be driven with DOM tools. Dry-run unless confirm=true. Always scope with a domain allowlist; this never dumps the full cookie jar by default. Canonical example: source \"Profile 1\" (the directory behind the user's Work browser) into \"work\" with domains [\"github.com\"].",
    inputSchema: {
      type: "object",
      properties: {
        into: {
          type: "string",
          description: "Action browser identity to seed, e.g. work. Created on first open if it does not exist. Defaults to the active identity.",
        },
        source: {
          type: "string",
          description: "Regular Chrome profile DIRECTORY name, not its display name: Default, Profile 1, Profile 2, ... A browser the user calls \"Work\" is usually the Profile 1 directory. Call with listSourceProfiles=true to map display names to directories. Defaults to the most recently used.",
        },
        domains: {
          type: "array",
          items: { type: "string" },
          description: "Host suffixes to import, e.g. [\"github.com\", \"midjourney.com\"].",
        },
        only: {
          type: "array",
          items: { type: "string" },
          description: "Optional cookie names or host:name selectors.",
        },
        confirm: {
          type: "boolean",
          description: "When true, write cookies. When false/omitted, list matches only.",
        },
        listSourceProfiles: {
          type: "boolean",
          description: "When true, list the user's regular Chrome profiles (directory name plus display name) and return.",
        },
      },
      additionalProperties: false,
    },
    annotations: { readOnlyHint: false, idempotentHint: false },
  },
  {
    name: "browser_companion_status",
    title: "Chrome Companion Status",
    description: "Check whether the Action Chrome Companion extension dist exists and whether the localhost bridge reports a live connection for richer DOM act/observe.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
    annotations: { readOnlyHint: true, idempotentHint: true },
  },
  {
    name: "browser_open",
    title: "Open Browser URL",
    description: "Open a URL in one of two different browsers. mode=action (default) uses an Action browser identity that this plugin can then snapshot, click, fill, and screenshot over CDP. mode=regular hands the URL to the user's own everyday Chrome: visible, already signed in as them, and deliberately not DOM-controllable — drive that window with Action's native screen + accessibility tools (action.observe.* then action.act.execute) instead. To get DOM control of a signed-in session, seed an Action identity with browser_import_cookies rather than reaching for mode=regular.",
    inputSchema: {
      type: "object",
      properties: {
        url: { type: "string", description: "URL to open. https:// is added when no scheme is provided." },
        mode: {
          type: "string",
          enum: ["action", "regular"],
          description: "action = Action browser identity with DOM tools (default). regular = open-only handoff to the user's normal Chrome; browser_snapshot / browser_click / browser_fill / browser_screenshot do not reach it.",
        },
        profile: {
          type: "string",
          description: "Action mode only. Action browser identity to use, e.g. agent-browser (blank) or work (seeded from a regular Chrome profile). Created on first use.",
        },
        background: { type: "boolean", description: "Action mode only: keep Chrome hidden in the background. Defaults to true. Regular mode is always visible." },
        waitMs: { type: "number", description: "Action mode only: maximum time to wait for the page to become ready. Defaults to 15000." },
        newTab: { type: "boolean", description: "Action mode only: create a separate tab instead of reusing this session's current tab. Defaults to false." },
      },
      required: ["url"],
      additionalProperties: false,
    },
    annotations: { readOnlyHint: false, idempotentHint: false },
  },
  {
    name: "browser_tabs",
    title: "List Action Browser Tabs",
    description: "List open page tabs in the active Action browser identity. Tabs in the user's regular Chrome are not visible here.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
    annotations: { readOnlyHint: true, idempotentHint: true },
  },
  {
    name: "browser_snapshot",
    title: "Inspect Browser Page",
    description: "Read page metadata, visible text, and stable selectors for interactive elements in the active Action browser. Does not reach pages opened with mode=regular; use action.observe.snapshot for those.",
    inputSchema: {
      type: "object",
      properties: {
        tabId: { type: "string", description: "Optional tab id from browser_open or browser_tabs." },
        maxTextChars: { type: "number", description: "Maximum visible-text characters. Defaults to 12000." },
        maxElements: { type: "number", description: "Maximum interactive elements. Defaults to 80." },
      },
      additionalProperties: false,
    },
    annotations: { readOnlyHint: true, idempotentHint: true },
  },
  {
    name: "browser_click",
    title: "Click Browser Element",
    description: "Click a DOM element by CSS selector or visible text in the active Action browser. Does not reach pages opened with mode=regular; use action.act.execute for those.",
    inputSchema: {
      type: "object",
      properties: {
        tabId: { type: "string", description: "Optional tab id." },
        selector: { type: "string", description: "Preferred CSS selector from browser_snapshot." },
        text: { type: "string", description: "Visible text fallback when a selector is unavailable." },
      },
      additionalProperties: false,
    },
    annotations: { readOnlyHint: false, idempotentHint: false },
  },
  {
    name: "browser_fill",
    title: "Fill Browser Field",
    description: "Set the value of an input, textarea, select, or contenteditable element in the active Action browser and dispatch input/change events. Does not reach pages opened with mode=regular.",
    inputSchema: {
      type: "object",
      properties: {
        tabId: { type: "string", description: "Optional tab id." },
        selector: { type: "string", description: "CSS selector for the field." },
        value: { type: "string", description: "Text value to enter." },
      },
      required: ["selector", "value"],
      additionalProperties: false,
    },
    annotations: { readOnlyHint: false, idempotentHint: false },
  },
  {
    name: "browser_resize",
    title: "Resize Browser Viewport",
    description: "Set the viewport of an already-open Action browser tab to an explicit width and height, so responsive breakpoints can be exercised and screenshotted. target=tab (default) emulates the size for that one tab only and is exact, reversible, and invisible to every other tab; target=window resizes the real Chrome window hosting the tab, which moves every tab in it and may be clamped by the display. The size sticks across later browser_open / browser_snapshot / browser_screenshot calls on that tab until reset, and is dropped when the tab or the browser closes -- nothing is written to the profile. Send reset=true to restore the default size. Does not reach pages opened with mode=regular.",
    inputSchema: {
      type: "object",
      properties: {
        width: {
          type: "integer",
          minimum: MIN_VIEWPORT_EDGE,
          maximum: MAX_VIEWPORT_EDGE,
          description: `Viewport width in CSS pixels, ${MIN_VIEWPORT_EDGE}-${MAX_VIEWPORT_EDGE}. Required unless reset is true. Example breakpoints: 390 phone, 768 tablet, 1280 laptop, 1920 desktop.`,
        },
        height: {
          type: "integer",
          minimum: MIN_VIEWPORT_EDGE,
          maximum: MAX_VIEWPORT_EDGE,
          description: `Viewport height in CSS pixels, ${MIN_VIEWPORT_EDGE}-${MAX_VIEWPORT_EDGE}. Required unless reset is true.`,
        },
        target: {
          type: "string",
          enum: ["tab", "window"],
          description: "tab = emulate the size for this tab only (default, exact, reversible). window = resize the real Chrome window, which affects every tab in it, may be clamped by the display, and drops any emulated viewport on this tab first so the new window size is what the page actually sees.",
        },
        tabId: { type: "string", description: "Optional tab id from browser_open or browser_tabs. Defaults to this session's current tab." },
        deviceScaleFactor: {
          type: "number",
          minimum: MIN_DEVICE_SCALE_FACTOR,
          maximum: MAX_DEVICE_SCALE_FACTOR,
          description: "target=tab only. Device pixel ratio. Defaults to 1, which makes screenshot pixels equal CSS pixels; use 2 for a retina-density capture.",
        },
        mobile: {
          type: "boolean",
          description: "target=tab only. Emulate a mobile device: honour the viewport meta tag and enable touch. Defaults to false, which is desktop responsive mode.",
        },
        matchMedia: {
          type: "array",
          items: { type: "string" },
          description: "Optional media queries to evaluate after the resize, e.g. [\"(max-width: 768px)\"]. Returns which ones match, so a breakpoint can be asserted instead of eyeballed.",
        },
        reset: {
          type: "boolean",
          description: `When true, drop the override: target=tab returns the tab to the real window viewport, target=window restores the default ${DEFAULT_WINDOW_SIZE.width}x${DEFAULT_WINDOW_SIZE.height} window. Cannot be combined with width or height.`,
        },
      },
      additionalProperties: false,
    },
    annotations: { readOnlyHint: false, idempotentHint: true },
  },
  {
    name: "browser_screenshot",
    title: "Capture Browser Screenshot",
    description: "Capture the current Action browser page as a PNG, save it locally, and return the image directly to the agent. Does not reach pages opened with mode=regular; capture those with Action's native screen tools.",
    inputSchema: {
      type: "object",
      properties: {
        tabId: { type: "string", description: "Optional tab id." },
        outputPath: { type: "string", description: "Optional absolute PNG path." },
        fullPage: { type: "boolean", description: "Capture the full document instead of the viewport. Defaults to false." },
        includeImage: { type: "boolean", description: "Include image bytes in the MCP response. Defaults to true." },
      },
      additionalProperties: false,
    },
    annotations: { readOnlyHint: true, idempotentHint: false },
  },
  {
    name: "browser_close",
    title: "Close Browser Tab or Session",
    description: "Close a tab in the active Action browser identity, or release this session's browser entirely. Never closes anything in the user's regular Chrome.",
    inputSchema: {
      type: "object",
      properties: {
        tabId: { type: "string", description: "Optional tab id. Defaults to the current Action Browser tab." },
        scope: {
          type: "string",
          enum: ["tab", "browser"],
          description: "Close a single tab (default) or quit Chrome once no other live session still claims it.",
        },
      },
      additionalProperties: false,
    },
    annotations: { readOnlyHint: false, idempotentHint: false },
  },
];

class CDPSession {
  private socket: WebSocket;
  private nextId = 1;
  private pending = new Map<number, {
    resolve: (value: JsonObject) => void;
    reject: (error: Error) => void;
  }>();

  private constructor(socket: WebSocket) {
    this.socket = socket;
    socket.addEventListener("message", (event) => {
      const message = JSON.parse(String(event.data)) as {
        id?: number;
        result?: JsonObject;
        error?: { message?: string };
      };
      if (!message.id) return;
      const waiter = this.pending.get(message.id);
      if (!waiter) return;
      this.pending.delete(message.id);
      if (message.error) {
        waiter.reject(new Error(message.error.message ?? "Chrome DevTools command failed."));
      } else {
        waiter.resolve(message.result ?? {});
      }
    });
    socket.addEventListener("close", () => {
      for (const waiter of this.pending.values()) {
        waiter.reject(new Error("Chrome DevTools connection closed."));
      }
      this.pending.clear();
    });
  }

  static async connect(url: string): Promise<CDPSession> {
    const socket = new WebSocket(url);
    await new Promise<void>((resolveConnection, reject) => {
      const timeout = setTimeout(() => reject(new Error("Timed out connecting to Chrome DevTools.")), 5_000);
      socket.addEventListener("open", () => {
        clearTimeout(timeout);
        resolveConnection();
      }, { once: true });
      socket.addEventListener("error", () => {
        clearTimeout(timeout);
        reject(new Error("Could not connect to Chrome DevTools."));
      }, { once: true });
    });
    return new CDPSession(socket);
  }

  call(method: string, params: JsonObject = {}): Promise<JsonObject> {
    const id = this.nextId++;
    return new Promise((resolveCall, reject) => {
      this.pending.set(id, { resolve: resolveCall, reject });
      this.socket.send(JSON.stringify({ id, method, params }));
    });
  }

  close(): void {
    this.socket.close();
  }
}

function normalizeURL(value: string): string {
  if (/^[a-z][a-z0-9+.-]*:\/\//i.test(value) || value.startsWith("chrome://")) {
    return value;
  }
  return `https://${value}`;
}

async function fetchJson<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${chromeBaseURL}${path}`, init);
  if (!response.ok) {
    throw new Error(`Chrome endpoint ${path} returned ${response.status}.`);
  }
  return await response.json() as T;
}

async function chromeIsReady(): Promise<boolean> {
  try {
    await fetchJson("/json/version");
    return true;
  } catch {
    return false;
  }
}

function probe(command: string[]): string {
  try {
    const result = Bun.spawnSync(command, { stdout: "pipe", stderr: "ignore" });
    return result.success ? textDecoder.decode(result.stdout).trim() : "";
  } catch {
    return "";
  }
}

function note(event: string, detail: JsonObject = {}): void {
  try {
    process.stderr.write(`${JSON.stringify({ scope: "action-browser", session: sessionName, event, ...detail })}\n`);
  } catch {
    // A closed transport must never break shutdown.
  }
}

function processIsRunning(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return (error as { code?: string }).code === "EPERM";
  }
}

function processStartedAt(pid: number): number | undefined {
  const started = Date.parse(probe(["/bin/ps", "-p", String(pid), "-o", "lstart="]));
  return Number.isFinite(started) ? started : undefined;
}

function signalProcess(pid: number, signal: "SIGTERM" | "SIGKILL"): void {
  try {
    process.kill(pid, signal);
  } catch {
    // Already gone.
  }
}

const ownerStartedAt = processStartedAt(process.pid) ?? Date.now();

function pidFromSessionName(name: string): number {
  const match = /^action-(\d+)(?:-|$)/.exec(name);
  return match ? Number(match[1]) : 0;
}

function claimPath(session: string): string {
  return join(sessionRoot, `${session}.json`);
}

function readClaims(): BrowserClaim[] {
  let entries: string[];
  try {
    entries = readdirSync(sessionRoot);
  } catch {
    return [];
  }
  const claims: BrowserClaim[] = [];
  for (const entry of entries) {
    if (!entry.endsWith(".json")) continue;
    const session = entry.slice(0, -".json".length);
    try {
      const claim = JSON.parse(readFileSync(join(sessionRoot, entry), "utf8")) as Partial<BrowserClaim>;
      const pid = Number.isInteger(claim.pid) ? Number(claim.pid) : pidFromSessionName(session);
      if (pid <= 0) throw new Error("Claim has no resolvable owner pid.");
      claims.push({
        session,
        pid,
        ownerStartedAt: Number(claim.ownerStartedAt),
        profile: String(claim.profile ?? profileName),
        profileDir: String(claim.profileDir ?? profileDir),
        debugPort: Number(claim.debugPort ?? debugPort),
        claimedAt: String(claim.claimedAt ?? ""),
      });
    } catch {
      try {
        unlinkSync(join(sessionRoot, entry));
      } catch {
        // Another session may have swept it already.
      }
    }
  }
  return claims;
}

function ownerIsAlive(claim: BrowserClaim): boolean {
  if (!processIsRunning(claim.pid)) return false;
  if (!Number.isFinite(claim.ownerStartedAt)) return true;
  const startedAt = processStartedAt(claim.pid);
  return startedAt === undefined || startedAt <= claim.ownerStartedAt + 2_000;
}

function claimTargetsThisBrowser(claim: BrowserClaim): boolean {
  return claim.profileDir === profileDir && claim.debugPort === debugPort;
}

function claimBrowser(): void {
  if (claimHeld || shuttingDown) return;
  const claim: BrowserClaim = {
    session: sessionName,
    pid: process.pid,
    ownerStartedAt,
    profile: profileName,
    profileDir,
    debugPort,
    claimedAt: new Date().toISOString(),
  };
  try {
    mkdirSync(sessionRoot, { recursive: true });
    const staging = join(sessionRoot, `.${sessionName}.tmp`);
    writeFileSync(staging, `${JSON.stringify(claim, null, 2)}\n`);
    renameSync(staging, claimPath(sessionName));
    claimHeld = true;
    ownsBrowser = true;
    note("claim", { pid: process.pid, profileDir, debugPort });
  } catch {
    // Losing the registry must not block browser work.
  }
}

function releaseClaim(): void {
  claimHeld = false;
  try {
    unlinkSync(claimPath(sessionName));
  } catch {
    // Nothing to release.
  }
}

function sweepClaims(): { liveOwners: number; staleOwners: number } {
  let liveOwners = 0;
  let staleOwners = 0;
  for (const claim of readClaims()) {
    if (claim.session === sessionName) continue;
    if (ownerIsAlive(claim)) {
      if (claimTargetsThisBrowser(claim)) liveOwners += 1;
      continue;
    }
    if (claimTargetsThisBrowser(claim)) staleOwners += 1;
    try {
      unlinkSync(claimPath(claim.session));
    } catch {
      // Another session may have swept it already.
    }
  }
  return { liveOwners, staleOwners };
}

function chromeProcessId(): number | undefined {
  let link: string;
  try {
    link = readlinkSync(join(profileDir, "SingletonLock"));
  } catch {
    return undefined;
  }
  const pid = Number(link.slice(link.lastIndexOf("-") + 1));
  if (!Number.isInteger(pid) || pid <= 1) return undefined;
  return probe(["/bin/ps", "-p", String(pid), "-o", "command="]).includes(`--user-data-dir=${profileDir}`)
    ? pid
    : undefined;
}

async function closeChrome(): Promise<boolean> {
  const chromePid = chromeProcessId();
  try {
    const version = await fetchJson<{ webSocketDebuggerUrl?: string }>("/json/version");
    if (version.webSocketDebuggerUrl) {
      const session = await CDPSession.connect(version.webSocketDebuggerUrl);
      await Promise.race([session.call("Browser.close").catch(() => {}), Bun.sleep(1_500)]);
      session.close();
    }
  } catch {
    // Chrome is unreachable; fall through to the signal ladder.
  }
  if (chromePid === undefined) return !(await chromeIsReady());
  for (let attempt = 0; attempt < 24; attempt += 1) {
    if (!processIsRunning(chromePid)) return true;
    if (attempt === 2) signalProcess(chromePid, "SIGTERM");
    if (attempt === 16) signalProcess(chromePid, "SIGKILL");
    await Bun.sleep(125);
  }
  return !processIsRunning(chromePid);
}

async function releaseBrowser(reason: string): Promise<ReleaseOutcome> {
  releaseClaim();
  const { liveOwners } = sweepClaims();
  if (liveOwners > 0) {
    ownsBrowser = false;
    return { reason, closed: false, liveOwners };
  }
  const closed = await closeChrome();
  if (closed) ownsBrowser = false;
  return { reason, closed, liveOwners };
}

async function releaseOwnedBrowser(reason: string): Promise<ReleaseOutcome | undefined> {
  return ownsBrowser ? await releaseBrowser(reason) : undefined;
}

function releaseBrowserSync(): void {
  if (!ownsBrowser) return;
  releaseClaim();
  if (sweepClaims().liveOwners > 0) return;
  const chromePid = chromeProcessId();
  if (chromePid !== undefined) signalProcess(chromePid, "SIGTERM");
}

async function sweepOrphans(): Promise<void> {
  const { liveOwners, staleOwners } = sweepClaims();
  if (staleOwners === 0 || liveOwners > 0) return;
  if (chromeProcessId() === undefined && !(await chromeIsReady())) return;
  const closed = await closeChrome();
  note("sweep", { staleOwners, closed });
}

function scheduleIdleRelease(): void {
  if (idleTimer) clearTimeout(idleTimer);
  idleTimer = undefined;
  if (idleTimeoutMs <= 0 || shuttingDown) return;
  const timer = setTimeout(() => {
    void releaseOwnedBrowser("idle").then((outcome) => {
      if (outcome) note("idle", outcome);
    });
  }, idleTimeoutMs);
  timer.unref();
  idleTimer = timer;
}

async function shutdown(reason: string): Promise<void> {
  if (shuttingDown) return;
  shuttingDown = true;
  if (idleTimer) clearTimeout(idleTimer);
  const owned = ownsBrowser;
  const outcome = await Promise.race([
    releaseOwnedBrowser(reason),
    Bun.sleep(shutdownBudgetMs).then(() => undefined),
  ]);
  note("shutdown", { reason, owned, closed: outcome?.closed ?? false, timedOut: owned && outcome === undefined });
  process.exit(0);
}

function installLifecycleHooks(): void {
  for (const signal of ["SIGTERM", "SIGINT", "SIGHUP"] as const) {
    process.on(signal, () => {
      void shutdown(signal);
    });
  }
  process.on("exit", () => {
    releaseBrowserSync();
  });
}

async function useProfile(nextName: string): Promise<{
  profile: string;
  profileDir: string;
  switched: boolean;
  closedPrevious: boolean;
}> {
  if (fixedProfileDir) {
    throw new Error(
      "ACTION_BROWSER_PROFILE_DIR is fixed for this MCP process; unset it to switch named profiles.",
    );
  }
  const name = sanitizeProfileName(nextName);
  const nextDir = join(profileRoot, name);
  if (name === profileName && nextDir === profileDir) {
    writeProfileMeta(profileName, profileDir);
    return { profile: profileName, profileDir, switched: false, closedPrevious: false };
  }
  let closedPrevious = false;
  if (ownsBrowser) {
    const outcome = await releaseBrowser("profile-switch");
    closedPrevious = outcome.closed;
    currentTargetId = undefined;
    viewportOverrides.clear();
  }
  profileName = name;
  profileDir = nextDir;
  writeProfileMeta(profileName, profileDir);
  return { profile: profileName, profileDir, switched: true, closedPrevious };
}

async function companionStatus(): Promise<JsonObject> {
  const dist = companionDistDir();
  const distExists = existsSync(dist);
  const manifestPath = join(dist, "manifest.json");
  let bridge: JsonObject = { ok: false, connected: false };
  try {
    const response = await fetch(companionBridgeHealthURL);
    bridge = await response.json() as JsonObject;
  } catch (error) {
    bridge = {
      ok: false,
      connected: false,
      error: error instanceof Error ? error.message : String(error),
      hint: "Start the bridge with: bun run chrome:companion:bridge",
    };
  }

  let extensionTargets: Array<{ type: string; title: string; url: string }> = [];
  let extensionIds: string[] = [];
  if (await chromeIsReady()) {
    try {
      const targets = await fetchJson<ChromeTarget[]>("/json/list");
      extensionTargets = targets
        .filter((target) => typeof target.url === "string" && target.url.includes("chrome-extension://"))
        .map((target) => ({ type: target.type, title: target.title, url: target.url }));
      extensionIds = [
        ...new Set(
          extensionTargets
            .map((target) => target.url.match(/^chrome-extension:\/\/([^/]+)\//)?.[1])
            .filter((id): id is string => Boolean(id)),
        ),
      ];
    } catch {
      // Chrome may not expose targets yet.
    }
  }

  return {
    profile: profileName,
    profileDir,
    companionDist: dist,
    companionDistExists: distExists,
    companionManifestExists: existsSync(manifestPath),
    bridgeHealthUrl: companionBridgeHealthURL,
    bridge,
    extensionTargets,
    extensionIds,
    setupHint: distExists
      ? `Load unpacked extension once in this Action profile: ${dist}`
      : "Build companion first: bun run chrome:companion:build",
  };
}

async function ensureChrome(background = true): Promise<void> {
  if (await chromeIsReady()) {
    claimBrowser();
    return;
  }

  await mkdir(profileDir, { recursive: true });
  writeProfileMeta(profileName, profileDir);
  const openArgs = [
    "/usr/bin/open",
    "-n",
    "-a",
    chromeAppName,
  ];
  if (background) {
    openArgs.push("-j", "-g");
  }
  openArgs.push(
    "--args",
    `--user-data-dir=${profileDir}`,
    `--remote-debugging-port=${debugPort}`,
    "--remote-allow-origins=*",
    "--no-first-run",
    "--no-default-browser-check",
    "--disable-background-timer-throttling",
    "--disable-backgrounding-occluded-windows",
    "--disable-renderer-backgrounding",
    `--window-size=${DEFAULT_WINDOW_SIZE.width},${DEFAULT_WINDOW_SIZE.height}`,
    "about:blank",
  );

  const launch = Bun.spawn(openArgs, { stdout: "ignore", stderr: "pipe" });
  const status = await launch.exited;
  if (status !== 0) {
    const stderr = await new Response(launch.stderr).text();
    throw new Error(stderr.trim() || `Could not launch ${chromeAppName}.`);
  }

  for (let attempt = 0; attempt < 60; attempt += 1) {
    if (await chromeIsReady()) {
      claimBrowser();
      return;
    }
    await Bun.sleep(250);
  }

  throw new Error(`Chrome did not expose its local debugging port at ${chromeBaseURL}.`);
}

async function listTargets(): Promise<ChromeTarget[]> {
  await ensureChrome();
  const targets = (await fetchJson<ChromeTarget[]>("/json/list"))
    .filter((target) => target.type === "page" && Boolean(target.webSocketDebuggerUrl));
  if (viewportOverrides.size > 0) {
    const live = new Set(targets.map((target) => target.id));
    for (const id of viewportOverrides.keys()) {
      if (!live.has(id)) viewportOverrides.delete(id);
    }
  }
  return targets;
}

async function targetFor(tabId?: unknown): Promise<ChromeTarget> {
  const targets = await listTargets();
  const requestedId = typeof tabId === "string" ? tabId : currentTargetId;
  const target = requestedId
    ? targets.find((candidate) => candidate.id === requestedId)
    : targets.find((candidate) => !candidate.url.startsWith("chrome://")) ?? targets[0];
  if (!target?.webSocketDebuggerUrl) {
    throw new Error("No Action Browser tab is available. Call browser_open first.");
  }
  currentTargetId = target.id;
  return target;
}

async function withTarget<T>(tabId: unknown, work: (session: CDPSession, target: ChromeTarget) => Promise<T>): Promise<T> {
  const target = await targetFor(tabId);
  const session = await CDPSession.connect(target.webSocketDebuggerUrl!);
  try {
    await applyViewportOverride(session, target.id);
    return await work(session, target);
  } finally {
    session.close();
  }
}

/**
 * Re-apply this tab's emulated viewport on a fresh CDP session. Failure throws
 * rather than degrading quietly: a screenshot taken at the wrong width would look
 * like a verified breakpoint when nothing was verified.
 */
async function applyViewportOverride(session: CDPSession, targetId: string): Promise<void> {
  const override = viewportOverrides.get(targetId);
  if (!override) return;
  try {
    await session.call("Emulation.setDeviceMetricsOverride", {
      width: override.width,
      height: override.height,
      deviceScaleFactor: override.deviceScaleFactor,
      mobile: override.mobile,
    });
    await session.call("Emulation.setTouchEmulationEnabled", {
      enabled: override.mobile,
      maxTouchPoints: override.mobile ? 5 : 1,
    });
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    throw new Error(
      `Could not restore the ${override.width}x${override.height} viewport on tab ${targetId}: ${detail}. `
      + "Call browser_resize again, or browser_resize { reset: true } to drop the override.",
    );
  }
}

/** Read what the page actually got, which is the only number worth reporting. */
async function measureViewport(session: CDPSession, queries: string[] = []): Promise<JsonObject> {
  const expression = `(() => {
    const queries = ${JSON.stringify(queries)};
    return {
      width: window.innerWidth,
      height: window.innerHeight,
      devicePixelRatio: window.devicePixelRatio,
      documentWidth: document.documentElement.scrollWidth,
      documentHeight: document.documentElement.scrollHeight,
      ...(queries.length
        ? { matchMedia: Object.fromEntries(queries.map((query) => [query, window.matchMedia(query).matches])) }
        : {}),
    };
  })()`;
  return await evaluateValue(session, expression) as JsonObject;
}

/** Browser-scope CDP (window bounds, browser close) rather than a single page target. */
async function withBrowserSession<T>(work: (session: CDPSession) => Promise<T>): Promise<T> {
  await ensureChrome();
  const version = await fetchJson<{ webSocketDebuggerUrl?: string }>("/json/version");
  if (!version.webSocketDebuggerUrl) {
    throw new Error("Chrome did not expose a browser-level DevTools endpoint.");
  }
  const session = await CDPSession.connect(version.webSocketDebuggerUrl);
  try {
    return await work(session);
  } finally {
    session.close();
  }
}

/**
 * Drop a device-metrics override on a tab, including one left behind by a CDP
 * session that has already disconnected.
 *
 * An override belongs to the session that set it. A later session calling
 * clearDeviceMetricsOverride is accepted and silently does nothing, so Chrome keeps
 * serving the stale size forever once the owning socket is gone. Re-setting the
 * metrics first moves ownership to this session, which can then clear them for real.
 * Adopting the size already on screen makes the round trip invisible.
 */
async function clearViewportOverride(session: CDPSession): Promise<void> {
  const current = await measureViewport(session);
  await session.call("Emulation.setDeviceMetricsOverride", {
    width: Number(current.width) || DEFAULT_WINDOW_SIZE.width,
    height: Number(current.height) || DEFAULT_WINDOW_SIZE.height,
    deviceScaleFactor: 1,
    mobile: false,
  });
  await session.call("Emulation.clearDeviceMetricsOverride");
  // Touch emulation has the same session ownership rule, so take it the same way.
  await session.call("Emulation.setTouchEmulationEnabled", { enabled: true, maxTouchPoints: 1 });
  await session.call("Emulation.setTouchEmulationEnabled", { enabled: false, maxTouchPoints: 1 });
}

/** Forget a tab's emulated viewport and put the real one back. */
async function dropViewportOverride(targetId: string): Promise<void> {
  viewportOverrides.delete(targetId);
  await withTarget(targetId, clearViewportOverride);
}

/**
 * Resize the real Chrome window hosting a tab.
 *
 * sizeIs="viewport" sizes the window so the *page* lands on the requested size:
 * window bounds carry the tab strip and omnibox, so the chrome inset is measured
 * live rather than hard-coded per Chrome version. sizeIs="bounds" sets the window
 * itself, which is what restoring the launch size means.
 *
 * Callers must drop any emulated viewport first. Emulation rewrites window.innerWidth,
 * which would both hide the new window size from the page and inflate the inset by
 * the difference between the emulated and real widths.
 */
async function resizeWindowForTab(
  targetId: string,
  size: { width: number; height: number },
  sizeIs: "viewport" | "bounds",
): Promise<JsonObject> {
  let inset = { width: 0, height: 0 };
  if (sizeIs === "viewport") {
    inset = await withTarget(targetId, async (session) => {
      const metrics = await evaluateValue(session, `({
        width: window.outerWidth - window.innerWidth,
        height: window.outerHeight - window.innerHeight,
      })`) as JsonObject;
      return { width: Number(metrics.width ?? 0) || 0, height: Number(metrics.height ?? 0) || 0 };
    });
  }
  const bounds = sizeIs === "viewport" ? windowBoundsFor(size, inset) : { ...size };
  await withBrowserSession(async (session) => {
    const window = await session.call("Browser.getWindowForTarget", { targetId });
    const windowId = window.windowId;
    const current = window.bounds as JsonObject | undefined;
    // Bounds are only writable from the normal window state.
    if (current?.windowState && current.windowState !== "normal") {
      await session.call("Browser.setWindowBounds", { windowId, bounds: { windowState: "normal" } });
    }
    await session.call("Browser.setWindowBounds", {
      windowId,
      bounds: { width: bounds.width, height: bounds.height },
    });
  });
  // The window manager applies asynchronously, and the page relayouts after it.
  await Bun.sleep(250);
  return { chromeInset: inset, windowBounds: bounds };
}

/** Let media queries settle and the page repaint before anything screenshots it. */
async function settleLayout(session: CDPSession): Promise<void> {
  try {
    await evaluateValue(session, `new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(() => resolve(true))))`);
  } catch {
    // A page mid-navigation can drop the evaluation; the measurement below still reports truth.
  }
}

type PageReadiness = {
  readyState?: string;
  documentUrl?: string;
  title?: string;
  loaderId?: string;
  timedOut: boolean;
};

async function waitUntilReady(
  session: CDPSession,
  timeoutMs: number,
  expectedLoaderId?: string,
): Promise<PageReadiness> {
  const started = Date.now();
  let last: PageReadiness = { timedOut: true };
  while (true) {
    try {
      const frameTreeResult = await session.call("Page.getFrameTree");
      const result = await session.call("Runtime.evaluate", {
        expression: "({ readyState: document.readyState, documentUrl: location.href, title: document.title })",
        returnByValue: true,
      });
      const value = (result.result as JsonObject | undefined)?.value as JsonObject | undefined;
      const frameTree = frameTreeResult.frameTree as JsonObject | undefined;
      const frame = frameTree?.frame as JsonObject | undefined;
      last = {
        readyState: typeof value?.readyState === "string" ? value.readyState : undefined,
        documentUrl: typeof value?.documentUrl === "string" ? value.documentUrl : undefined,
        title: typeof value?.title === "string" ? value.title : undefined,
        loaderId: typeof frame?.loaderId === "string" ? frame.loaderId : undefined,
        timedOut: true,
      };
      if (navigationIsReady({
        ...last,
        expectedLoaderId,
        observedLoaderId: last.loaderId,
      })) return { ...last, timedOut: false };
    } catch {
      // Navigation may replace the execution context between polls.
    }
    if (Date.now() - started >= timeoutMs) return last;
    await Bun.sleep(Math.min(150, Math.max(1, timeoutMs - (Date.now() - started))));
  }
}

async function evaluateValue(session: CDPSession, expression: string): Promise<unknown> {
  const response = await session.call("Runtime.evaluate", {
    expression,
    awaitPromise: true,
    returnByValue: true,
    userGesture: true,
  });
  const exception = response.exceptionDetails as JsonObject | undefined;
  if (exception) {
    throw new Error(String(exception.text ?? "Page evaluation failed."));
  }
  return (response.result as JsonObject | undefined)?.value;
}

function asString(value: unknown, label: string): string {
  if (typeof value !== "string" || !value.trim()) {
    throw new Error(`${label} is required.`);
  }
  return value.trim();
}

function stringValue(value: unknown, label: string): string {
  if (typeof value !== "string") {
    throw new Error(`${label} is required.`);
  }
  return value;
}

function optionalNumber(value: unknown, fallback: number): number {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function textResult(data: JsonObject): ToolResult {
  return {
    content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
    structuredContent: data,
  };
}

function errorResult(data: JsonObject): ToolResult {
  return {
    isError: true,
    content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
    structuredContent: data,
  };
}

async function callTool(name: string, args: JsonObject): Promise<ToolResult> {
  switch (name) {
    case "browser_profiles":
      return textResult({
        ok: true,
        profileRoot,
        current: { profile: profileName, profileDir, fixedProfileDir: Boolean(fixedProfileDir) },
        profiles: listActionProfilesOnDisk(),
        surfaces: BROWSER_SURFACES,
        policy: {
          default: "Action browser identities (named profiles under ChromeProfiles)",
          regularChrome: "open-only handoff via browser_open mode=regular; controlled with Action native screen + AX tools, never with CDP",
          cookies: "seed an identity with browser_import_cookies using domain allowlists",
          companion: "load packages/chrome-companion/dist unpacked once per identity",
        },
      });

    case "browser_use_profile": {
      const result = await useProfile(asString(args.profile, "profile"));
      return textResult({ ok: true, ...result });
    }

    case "browser_profile_info": {
      const defaultDir = existsSync(join(profileDir, "Cookies"))
        ? profileDir
        : join(profileDir, "Default");
      return textResult({
        ok: true,
        profile: profileName,
        profileDir,
        defaultDir,
        hasCookiesDb: existsSync(join(defaultDir, "Cookies")),
        debugPort,
        fixedProfileDir: Boolean(fixedProfileDir),
        companion: await companionStatus(),
      });
    }

    case "browser_companion_status":
      return textResult({ ok: true, ...(await companionStatus()) });

    case "browser_import_cookies": {
      const cookies = await loadCookieModule();
      if (args.listSourceProfiles === true) {
        return textResult({
          ok: true,
          sourceProfiles: cookies.listPersonalProfiles(),
          actionProfiles: listActionProfilesOnDisk(),
        });
      }
      const domains = Array.isArray(args.domains)
        ? args.domains.map((entry) => String(entry).trim()).filter(Boolean)
        : [];
      const only = Array.isArray(args.only)
        ? args.only.map((entry) => String(entry).trim()).filter(Boolean)
        : [];
      const selectors = cookies.parseCookieSelectors(only);
      if (!domains.length && !selectors.length) {
        throw new Error("browser_import_cookies requires domains and/or only.");
      }
      const into = typeof args.into === "string" && args.into.trim()
        ? sanitizeProfileName(args.into)
        : profileName;
      const source = typeof args.source === "string" && args.source.trim()
        ? args.source.trim()
        : undefined;
      const sourceProfilePath = cookies.resolveSourceProfileDir(source);
      const matches = cookies.listCookieEntries(sourceProfilePath, { domains, selectors });
      if (args.confirm !== true) {
        return textResult({
          ok: true,
          dryRun: true,
          into,
          sourceProfilePath,
          count: matches.length,
          cookies: matches.map((cookie) => `${cookie.hostKey}:${cookie.name}`),
          confirmRequired: true,
          hint: "Re-call with confirm=true to write these cookies into the Action profile.",
        });
      }
      if (into === profileName && ownsBrowser) {
        await releaseBrowser("cookie-import");
        currentTargetId = undefined;
      }
      const result = cookies.importCookiesToActionProfile({
        into,
        sourceProfile: source,
        domains,
        selectors,
      });
      return textResult({ ok: true, dryRun: false, ...result });
    }

    case "browser_open": {
      const inputUrl = asString(args.url, "url");
      const url = normalizeURL(inputUrl);
      const mode = browserOpenMode(args.mode);
      if (mode === "regular") {
        if (typeof args.profile === "string" && args.profile.trim()) {
          throw new Error("profile is only available in action mode; regular mode uses the user's normal Chrome profile.");
        }
        const launch = Bun.spawn(regularChromeLaunchArgs(chromeAppName, url), {
          stdout: "ignore",
          stderr: "pipe",
        });
        const status = await launch.exited;
        if (status !== 0) {
          const stderr = await new Response(launch.stderr).text();
          throw new Error(stderr.trim() || `Could not open ${chromeAppName}.`);
        }
        return textResult({
          ok: true,
          mode,
          ...(inputUrl === url ? {} : { inputUrl }),
          openedUrl: url,
          controlAvailable: false,
          handoff: true,
          chrome: {
            app: chromeAppName,
            profile: "system-selected",
            profileVerified: false,
            automated: false,
          },
          message: "Opened in the user's regular Chrome. Action Browser cannot inspect, click, fill, or screenshot this tab.",
          nativeControlPath: "Drive this window with Action's native macOS tools instead: action.observe.snapshot (screen + accessibility), action.resolve.target, action.act.execute.",
          domControlAlternative: "For DOM-level control of a signed-in session, seed an Action identity: browser_import_cookies { into: \"work\", source: \"Profile 1\", domains: [...], confirm: true } then browser_open { url, profile: \"work\" }.",
        });
      }
      if (typeof args.profile === "string" && args.profile.trim()) {
        await useProfile(args.profile);
      }
      const background = args.background !== false;
      const timeoutMs = Math.max(0, optionalNumber(args.waitMs, 15_000));
      await ensureChrome(background);
      let target: ChromeTarget | undefined;
      let reusedTab = false;
      if (shouldReuseCurrentTab({
        currentTargetId,
        newTab: args.newTab === true,
      })) {
        target = (await listTargets()).find((candidate) => candidate.id === currentTargetId);
        reusedTab = Boolean(target);
      }
      if (!target) {
        target = await fetchJson<ChromeTarget>("/json/new?about%3Ablank", { method: "PUT" });
        if (!target.webSocketDebuggerUrl) {
          throw new Error("Chrome created a tab without a DevTools endpoint.");
        }
      }
      currentTargetId = target.id;
      const session = await CDPSession.connect(target.webSocketDebuggerUrl);
      try {
        await session.call("Page.enable");
        // Restore a sticky viewport before navigating so the first layout, and any
        // breakpoint-sensitive script the page runs on load, sees the right width.
        await applyViewportOverride(session, target.id);
        const navigation = await session.call("Page.navigate", { url });
        const navigateErrorText = typeof navigation.errorText === "string"
          ? navigation.errorText
          : undefined;
        const loaderId = typeof navigation.loaderId === "string" ? navigation.loaderId : undefined;
        const readiness = await waitUntilReady(
          session,
          navigateErrorText ? Math.min(timeoutMs, 1_500) : timeoutMs,
          loaderId,
        );
        let page: JsonObject = {};
        try {
          page = await evaluateValue(
            session,
            "({ title: document.title, documentUrl: location.href, readyState: document.readyState, pageText: (document.body?.innerText || '').replace(/\\s+/g, ' ').trim().slice(0, 1000) })",
          ) as JsonObject;
        } catch {
          // The target metadata and readiness observation still provide a useful failure contract.
        }
        let observedTarget: ChromeTarget | undefined;
        try {
          observedTarget = (await fetchJson<ChromeTarget[]>("/json/list"))
            .find((candidate) => candidate.id === target.id);
        } catch {
          // Chrome can briefly withhold target metadata while replacing an error document.
        }
        const outcome = assessNavigation({
          requestedUrl: url,
          documentUrl: typeof page.documentUrl === "string"
            ? page.documentUrl
            : readiness.documentUrl,
          targetUrl: observedTarget?.url ?? target.url,
          title: typeof page.title === "string" ? page.title : readiness.title,
          readyState: typeof page.readyState === "string" ? page.readyState : readiness.readyState,
          timedOut: readiness.timedOut,
          timeoutMs,
          navigateErrorText,
          pageText: typeof page.pageText === "string" ? page.pageText : undefined,
        });
        const result: JsonObject = {
          ...outcome,
          mode,
          ...(inputUrl === url ? {} : { inputUrl }),
          reusedTab,
          tab: {
            id: target.id,
            title: page.title ?? readiness.title ?? observedTarget?.title ?? target.title,
            url: outcome.finalUrl,
          },
          chrome: {
            profile: profileName,
            profileDir,
            background,
            debugPort,
            session: sessionName,
          },
        };
        return outcome.ok ? textResult(result) : errorResult(result);
      } finally {
        session.close();
      }
    }

    case "browser_tabs": {
      const tabs = (await listTargets()).map(({ id, title, url }) => ({
        id,
        title,
        url,
        current: id === currentTargetId,
      }));
      return textResult({ ok: true, tabs });
    }

    case "browser_snapshot":
      return await withTarget(args.tabId, async (session, target) => {
        const maxTextChars = Math.max(500, optionalNumber(args.maxTextChars, 12_000));
        const maxElements = Math.max(1, optionalNumber(args.maxElements, 80));
        const expression = `(() => {
          const visible = (element) => {
            const style = getComputedStyle(element);
            const rect = element.getBoundingClientRect();
            return style.display !== "none" && style.visibility !== "hidden" && rect.width > 0 && rect.height > 0;
          };
          const selector = (element) => {
            if (element.id) return "#" + CSS.escape(element.id);
            const testId = element.getAttribute("data-testid");
            if (testId) return '[data-testid="' + CSS.escape(testId) + '"]';
            const name = element.getAttribute("name");
            if (name) return element.tagName.toLowerCase() + '[name="' + CSS.escape(name) + '"]';
            const role = element.getAttribute("role");
            if (role) return element.tagName.toLowerCase() + '[role="' + CSS.escape(role) + '"]';
            return element.tagName.toLowerCase();
          };
          const nodes = [...document.querySelectorAll('a[href],button,input,select,textarea,[role],[contenteditable="true"],[tabindex]')]
            .filter(visible)
            .slice(0, ${maxElements})
            .map((element) => {
              const rect = element.getBoundingClientRect();
              const isPassword = element instanceof HTMLInputElement && element.type === "password";
              return {
                selector: selector(element),
                tag: element.tagName.toLowerCase(),
                role: element.getAttribute("role"),
                label: element.getAttribute("aria-label") || element.getAttribute("placeholder") || element.innerText?.trim() || element.getAttribute("name"),
                value: isPassword ? null : ("value" in element ? String(element.value).slice(0, 500) : null),
                rect: { x: rect.x, y: rect.y, width: rect.width, height: rect.height }
              };
            });
          return {
            title: document.title,
            url: location.href,
            text: (document.body?.innerText || "").replace(/\\s+/g, " ").trim().slice(0, ${maxTextChars}),
            elements: nodes
          };
        })()`;
        const snapshot = await evaluateValue(session, expression) as JsonObject;
        return textResult({ ok: true, tabId: target.id, ...snapshot });
      });

    case "browser_click":
      return await withTarget(args.tabId, async (session, target) => {
        const selector = typeof args.selector === "string" ? args.selector : undefined;
        const text = typeof args.text === "string" ? args.text : undefined;
        if (!selector && !text) throw new Error("browser_click requires selector or text.");
        const expression = `(() => {
          const selector = ${JSON.stringify(selector)};
          const text = ${JSON.stringify(text?.trim().toLowerCase())};
          const candidates = [...document.querySelectorAll('a[href],button,input,[role="button"],[role="link"],[tabindex]')];
          const element = selector
            ? document.querySelector(selector)
            : candidates.find((candidate) => (candidate.innerText || candidate.textContent || candidate.getAttribute("aria-label") || "").trim().toLowerCase().includes(text));
          if (!(element instanceof HTMLElement)) throw new Error("No clickable element matched.");
          element.scrollIntoView({ block: "center", inline: "center" });
          element.click();
          return { selector: selector || element.tagName.toLowerCase(), text: (element.innerText || element.textContent || "").trim().slice(0, 300) };
        })()`;
        const result = await evaluateValue(session, expression) as JsonObject;
        await Bun.sleep(250);
        return textResult({ ok: true, tabId: target.id, result });
      });

    case "browser_fill":
      return await withTarget(args.tabId, async (session, target) => {
        const selector = asString(args.selector, "selector");
        const value = stringValue(args.value, "value");
        const expression = `(() => {
          const element = document.querySelector(${JSON.stringify(selector)});
          if (!(element instanceof HTMLElement)) throw new Error("No field matched the selector.");
          if (element instanceof HTMLInputElement || element instanceof HTMLTextAreaElement || element instanceof HTMLSelectElement) {
            const setter = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(element), "value")?.set;
            setter ? setter.call(element, ${JSON.stringify(value)}) : element.value = ${JSON.stringify(value)};
          } else if (element.isContentEditable) {
            element.textContent = ${JSON.stringify(value)};
          } else {
            throw new Error("Matched element is not editable.");
          }
          element.focus();
          element.dispatchEvent(new InputEvent("input", { bubbles: true, data: ${JSON.stringify(value)}, inputType: "insertText" }));
          element.dispatchEvent(new Event("change", { bubbles: true }));
          return { selector: ${JSON.stringify(selector)}, valueLength: ${value.length} };
        })()`;
        const result = await evaluateValue(session, expression) as JsonObject;
        return textResult({ ok: true, tabId: target.id, result });
      });

    case "browser_resize": {
      const request = parseResizeRequest(args);
      const target = await targetFor(args.tabId);
      const hadEmulatedViewport = viewportOverrides.has(target.id);

      let windowDetail: JsonObject = {};
      // Only a caller-named viewport size can be checked for drift. A reset asks for
      // "whatever the window is", so there is nothing to have missed.
      let requestedViewport: { width: number; height: number } | undefined;

      if (request.kind === "set" && request.target === "tab") {
        viewportOverrides.set(target.id, request.viewport);
        requestedViewport = { width: request.viewport.width, height: request.viewport.height };
      } else if (request.kind === "set") {
        // The window path owns the tab's size outright: an emulated viewport would
        // mask the resize the caller asked to see.
        await dropViewportOverride(target.id);
        requestedViewport = { width: request.viewport.width, height: request.viewport.height };
        windowDetail = await resizeWindowForTab(target.id, requestedViewport, "viewport");
      } else if (request.target === "window") {
        await dropViewportOverride(target.id);
        windowDetail = await resizeWindowForTab(target.id, DEFAULT_WINDOW_SIZE, "bounds");
      } else {
        await dropViewportOverride(target.id);
      }

      const measured = await withTarget(target.id, async (session) => {
        await settleLayout(session);
        return await measureViewport(session, request.matchMedia);
      });
      const drift = requestedViewport
        ? measureDrift(requestedViewport, {
          width: Number(measured.width ?? 0),
          height: Number(measured.height ?? 0),
        })
        : undefined;

      const result: JsonObject = {
        ok: true,
        target: request.target,
        tabId: target.id,
        url: target.url,
        reset: request.kind === "reset",
        requested: request.kind === "set"
          ? { ...request.viewport }
          : {
            restoredTo: request.target === "window"
              ? `the default ${DEFAULT_WINDOW_SIZE.width}x${DEFAULT_WINDOW_SIZE.height} window`
              : "the real window viewport",
          },
        viewport: measured,
        ...(drift ?? {}),
        widthClass: widthClass(Number(measured.width ?? 0)),
        emulated: viewportOverrides.has(target.id),
        ...(request.target === "window" && hadEmulatedViewport
          ? { clearedEmulatedViewport: true }
          : {}),
        ...windowDetail,
      };
      if (drift && !drift.exact) {
        result.note = request.target === "window"
          ? "The window manager did not grant the exact size; a window cannot exceed its display. Use target=tab for an exact viewport."
          : "The page did not lay out at the requested size. A hard min-width or a zoom level can hold it wider.";
      }
      return textResult(result);
    }

    case "browser_screenshot":
      return await withTarget(args.tabId, async (session, target) => {
        await session.call("Page.enable");
        const fullPage = args.fullPage === true;
        let captureParams: JsonObject = {
          format: "png",
          fromSurface: true,
          captureBeyondViewport: fullPage,
        };
        if (fullPage) {
          const metrics = await session.call("Page.getLayoutMetrics");
          const contentSize = metrics.cssContentSize as JsonObject | undefined
            ?? metrics.contentSize as JsonObject | undefined;
          if (contentSize) {
            captureParams = {
              ...captureParams,
              clip: {
                x: 0,
                y: 0,
                width: Math.min(Number(contentSize.width ?? 1440), 16_384),
                height: Math.min(Number(contentSize.height ?? 1000), 16_384),
                scale: 1,
              },
            };
          }
        }
        const capture = await session.call("Page.captureScreenshot", captureParams);
        const data = asString(capture.data, "screenshot data");
        const requestedPath = typeof args.outputPath === "string" ? args.outputPath : undefined;
        if (requestedPath && !isAbsolute(requestedPath)) {
          throw new Error("outputPath must be absolute when provided.");
        }
        const outputPath = requestedPath
          ? resolve(requestedPath)
          : join(artifactRoot, `browser-${new Date().toISOString().replace(/[:.]/g, "-")}.png`);
        await mkdir(dirname(outputPath), { recursive: true });
        await Bun.write(outputPath, Buffer.from(data, "base64"));
        const metadata: JsonObject = {
          ok: true,
          tabId: target.id,
          title: target.title,
          url: target.url,
          outputPath,
          fullPage,
          mimeType: "image/png",
          // Say which viewport this frame is evidence of, so a breakpoint screenshot
          // is self-describing rather than a size the reader has to remember.
          viewport: await measureViewport(session).catch(() => undefined),
          emulated: viewportOverrides.has(target.id),
        };
        return {
          content: [
            { type: "text", text: JSON.stringify(metadata, null, 2) },
            ...(args.includeImage === false ? [] : [{ type: "image" as const, data, mimeType: "image/png" as const }]),
          ],
          structuredContent: metadata,
        };
      });

    case "browser_close": {
      if (args.scope === "browser") {
        const outcome = await releaseBrowser("browser_close");
        currentTargetId = undefined;
        viewportOverrides.clear();
        return textResult({
          ok: true,
          scope: "browser",
          session: sessionName,
          closed: outcome.closed,
          liveOwners: outcome.liveOwners,
        });
      }
      const target = await targetFor(args.tabId);
      const response = await fetch(`${chromeBaseURL}/json/close/${encodeURIComponent(target.id)}`);
      if (!response.ok) {
        throw new Error(`Chrome could not close tab ${target.id}.`);
      }
      viewportOverrides.delete(target.id);
      if (currentTargetId === target.id) currentTargetId = undefined;
      return textResult({ ok: true, closed: target.id });
    }

    default:
      throw new Error(`Unknown tool: ${name}`);
  }
}

async function handleRequest(request: JsonRpcRequest): Promise<JsonObject | undefined> {
  const id = request.id;
  if (request.method.startsWith("notifications/") || id === undefined) {
    return undefined;
  }

  try {
    switch (request.method) {
      case "initialize":
        return {
          jsonrpc: "2.0",
          id,
          result: {
            protocolVersion: String(request.params?.protocolVersion ?? "2025-06-18"),
            capabilities: { tools: { listChanged: false } },
            serverInfo: { name: "action-browser", version: SERVER_VERSION },
            instructions: [
              "Action Browser drives Action-owned Chrome identities, never the user's regular Chrome.",
              "Three browsers exist. (1) The user's regular Chrome: browser_open mode=regular opens a URL there and nothing else; control it with Action's native screen + accessibility tools (action.observe.* then action.act.execute). (2) An Action browser: the default agent-browser identity, blank and isolated, with full DOM tools. (3) An Action browser identity seeded from a regular Chrome profile: same DOM tools, already signed in.",
              "To act on a signed-in site, seed rather than hand off: browser_import_cookies { into: \"work\", source: \"Profile 1\", domains: [\"github.com\"] } to preview, again with confirm: true to write, then browser_open { url, profile: \"work\" }.",
              "Fast path for anything public: browser_open → browser_screenshot.",
              "Responsive checks: browser_open → browser_resize { width, height } → browser_screenshot. The size sticks to that tab until browser_resize { reset: true }.",
              "browser_profiles lists identities and surfaces; browser_companion_status reports the extension bridge.",
            ].join("\n"),
          },
        };
      case "ping":
        return { jsonrpc: "2.0", id, result: {} };
      case "tools/list":
        return { jsonrpc: "2.0", id, result: { tools } };
      case "tools/call": {
        scheduleIdleRelease();
        const params = request.params ?? {};
        const name = asString(params.name, "tool name");
        const args = params.arguments && typeof params.arguments === "object"
          ? params.arguments as JsonObject
          : {};
        return { jsonrpc: "2.0", id, result: await callTool(name, args) };
      }
      default:
        return {
          jsonrpc: "2.0",
          id,
          error: { code: -32601, message: `Method not found: ${request.method}` },
        };
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (request.method === "tools/call") {
      return {
        jsonrpc: "2.0",
        id,
        result: {
          isError: true,
          content: [{ type: "text", text: JSON.stringify({ ok: false, error: message }, null, 2) }],
          structuredContent: { ok: false, error: message },
        },
      };
    }
    return { jsonrpc: "2.0", id, error: { code: -32603, message } };
  }
}

async function main(): Promise<void> {
  installLifecycleHooks();
  await sweepOrphans();

  let buffer = "";
  const decoder = new TextDecoder();

  for await (const chunk of Bun.stdin.stream()) {
    buffer += decoder.decode(chunk, { stream: true });
    while (buffer.includes("\n")) {
      const newline = buffer.indexOf("\n");
      const line = buffer.slice(0, newline).trim();
      buffer = buffer.slice(newline + 1);
      if (!line) continue;
      const request = JSON.parse(line) as JsonRpcRequest;
      const response = await handleRequest(request);
      if (response) process.stdout.write(`${JSON.stringify(response)}\n`);
    }
  }

  await shutdown("stdin-eof");
}

main().catch((error) => {
  console.error(error instanceof Error ? error.stack ?? error.message : String(error));
  process.exit(1);
});
