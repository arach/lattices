#!/usr/bin/env bun

import { createHash } from "node:crypto";
import { execSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { basename, dirname, isAbsolute, resolve } from "node:path";
import { homedir } from "node:os";

// Daemon client (lazy-loaded to avoid blocking startup for TTY commands)
let _daemonClient: typeof import("./daemon-client.ts") | undefined;
async function getDaemonClient(): Promise<typeof import("./daemon-client.ts")> {
  if (!_daemonClient) {
    _daemonClient = await import("./daemon-client.ts");
  }
  return _daemonClient;
}

const args: string[] = process.argv.slice(2);
const command: string | undefined = args[0];

// ── Helpers ──────────────────────────────────────────────────────────

interface ExecOpts {
  encoding?: string;
  stdio?: string | string[];
  cwd?: string;
  [key: string]: any;
}

function run(cmd: string, opts: ExecOpts = {}): string {
  return execSync(cmd, { encoding: "utf8", ...opts } as any).trim();
}

function runQuiet(cmd: string): string | null {
  try {
    return run(cmd, { stdio: "pipe" });
  } catch {
    return null;
  }
}

function hasTmux(): boolean {
  return runQuiet("which tmux") !== null;
}

/** Commands that require tmux to be installed */
const tmuxRequiredCommands = new Set([
  "start", "tmux", "init", "ls", "list", "kill", "rm", "sync", "reconcile",
  "restart", "respawn", "group", "groups", "tab", "status",
  "inventory", "sessions",
]);

function requireTmux(command: string | undefined): void {
  if (hasTmux()) return;

  if (!command) return;

  if (!tmuxRequiredCommands.has(command)) return;

  console.error(`
\x1b[1;31m✘ tmux not found\x1b[0m

Lattices uses tmux for terminal session management.
Install it with Homebrew:

    \x1b[1mbrew install tmux\x1b[0m

If tmux is installed somewhere else, make sure it's on your PATH:

    \x1b[90mexport PATH="/path/to/tmux/bin:$PATH"\x1b[0m

Then run this command again.
`.trim());
  process.exit(1);
}

function isInsideTmux(): boolean {
  return !!process.env.TMUX;
}

function sessionExists(name: string): boolean {
  return runQuiet(`tmux has-session -t "${name}" 2>&1`) !== null;
}

function pathHash(dir: string): string {
  return createHash("sha256").update(resolve(dir)).digest("hex").slice(0, 6);
}

function toSessionName(dir: string): string {
  const base = basename(dir).replace(/[^a-zA-Z0-9_-]/g, "-");
  return `${base}-${pathHash(dir)}`;
}

function esc(str: string): string {
  return str.replace(/'/g, "'\\''");
}

function appleScriptString(str: string): string {
  return str.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
}

function slugify(str: string): string {
  return str
    .toLowerCase()
    .replace(/\.app$/i, "")
    .replace(/[^a-z0-9_-]+/g, "-")
    .replace(/^-+|-+$/g, "") || "app";
}

function parseFlagValue(args: string[], name: string): string | undefined {
  const prefix = `--${name}=`;
  const exact = `--${name}`;
  for (let i = 0; i < args.length; i++) {
    if (args[i].startsWith(prefix)) return args[i].slice(prefix.length);
    if (args[i] === exact) return args[i + 1];
  }
  return undefined;
}

function hasFlag(args: string[], name: string): boolean {
  return args.includes(`--${name}`);
}

function nonFlagArgs(args: string[]): string[] {
  const valueFlags = new Set([
    "id", "state", "ttl", "ttlMs", "x", "y", "gap", "placement", "style", "name", "scale",
    "hud-url", "hudUrl", "hud-html", "hudHTML", "hudHtml", "hud-title", "hudTitle",
    "hud-width", "hudWidth", "hud-height", "hudHeight", "width", "height",
    "manifest", "root", "max-depth", "maxDepth", "read-access", "readAccess",
    "pause",
  ]);
  const out: string[] = [];
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (!arg.startsWith("--")) {
      out.push(arg);
      continue;
    }
    const flagName = arg.slice(2);
    if (!arg.includes("=") && valueFlags.has(flagName)) i++;
  }
  return out;
}

// ── Config ───────────────────────────────────────────────────────────

function readConfig(dir: string): any | null {
  const configPath = resolve(dir, ".lattices.json");
  if (!existsSync(configPath)) return null;
  try {
    const raw = readFileSync(configPath, "utf8");
    return JSON.parse(raw);
  } catch (e: unknown) {
    console.warn(`Warning: invalid .lattices.json — ${(e as Error).message}`);
    return null;
  }
}

// ── Workspace config (tab groups) ───────────────────────────────────

function readWorkspaceConfig(): any | null {
  const configPath = resolve(homedir(), ".lattices", "workspace.json");
  if (!existsSync(configPath)) return null;
  try {
    const raw = readFileSync(configPath, "utf8");
    return JSON.parse(raw);
  } catch (e: unknown) {
    console.warn(`Warning: invalid workspace.json — ${(e as Error).message}`);
    return null;
  }
}

function toGroupSessionName(groupId: string): string {
  return `lattices-group-${groupId}`;
}

/** Get ordered pane IDs for a specific window within a session */
function getPaneIdsForWindow(sessionName: string, windowIndex: number): string[] {
  const out = runQuiet(
    `tmux list-panes -t "${sessionName}:${windowIndex}" -F "#{pane_id}"`
  );
  return out ? out.split("\n").filter(Boolean) : [];
}

interface PaneConfig {
  name?: string;
  cmd?: string;
  size?: number;
}

/** Create a tmux window with pane layout for a project dir */
function createWindowForProject(sessionName: string, windowIndex: number, dir: string, label?: string): void {
  const config = readConfig(dir);
  const d = esc(dir);

  let panes: PaneConfig[];
  if (config?.panes?.length) {
    panes = resolvePane(config.panes, dir);
  } else {
    panes = defaultPanes(dir);
  }

  if (windowIndex === 0) {
    // First window already exists from new-session, just set working dir
    run(`tmux send-keys -t "${sessionName}:0" 'cd ${d}' Enter`);
  } else {
    run(`tmux new-window -t "${sessionName}" -c '${d}'`);
  }

  const winTarget = `${sessionName}:${windowIndex}`;

  // Rename the window
  const winLabel = label || basename(dir);
  runQuiet(`tmux rename-window -t "${winTarget}" "${winLabel}"`);

  // Create pane splits
  if (panes.length === 2) {
    const mainSize = panes[0].size || 60;
    run(`tmux split-window -h -t "${winTarget}" -c '${d}' -p ${100 - mainSize}`);
  } else if (panes.length >= 3) {
    const mainSize = panes[0].size || 60;
    for (let i = 1; i < panes.length; i++) {
      run(`tmux split-window -t "${winTarget}" -c '${d}'`);
    }
    runQuiet(`tmux set-option -t "${winTarget}" -w main-pane-width '${mainSize}%'`);
    run(`tmux select-layout -t "${winTarget}" main-vertical`);
  }

  // Get pane IDs and send commands
  const paneIds = getPaneIdsForWindow(sessionName, windowIndex);
  for (let i = 0; i < panes.length && i < paneIds.length; i++) {
    if (panes[i].cmd) {
      run(`tmux send-keys -t "${paneIds[i]}" '${esc(panes[i].cmd!)}' Enter`);
    }
    if (panes[i].name) {
      runQuiet(`tmux select-pane -t "${paneIds[i]}" -T "${panes[i].name}"`);
    }
  }

  // Focus first pane in this window
  if (paneIds.length) {
    run(`tmux select-pane -t "${paneIds[0]}"`);
  }
}

interface TabConfig {
  path: string;
  label?: string;
}

interface GroupConfig {
  id: string;
  label?: string;
  tabs?: TabConfig[];
}

/** Create a group session with one tmux window per tab */
function createGroupSession(group: GroupConfig): string | null {
  const name = toGroupSessionName(group.id);
  const tabs = group.tabs || [];

  if (!tabs.length) {
    console.log(`Group "${group.id}" has no tabs.`);
    return null;
  }

  // Validate all paths exist
  for (const tab of tabs) {
    if (!existsSync(tab.path)) {
      console.log(`Warning: path does not exist — ${tab.path}`);
    }
  }

  const firstDir = esc(tabs[0].path);
  console.log(`Creating group "${group.label || group.id}" (${tabs.length} tabs)...`);

  // Create session with first window
  run(`tmux new-session -d -s "${name}" -c '${firstDir}'`);

  // Set up each window/tab
  for (let i = 0; i < tabs.length; i++) {
    const tab = tabs[i];
    const dir = resolve(tab.path);
    createWindowForProject(name, i, dir, tab.label);
  }

  // Tag the session title
  runQuiet(`tmux set-option -t "${name}" set-titles on`);
  runQuiet(`tmux set-option -t "${name}" set-titles-string "[lattices:${name}] #{window_name} — #{pane_title}"`);

  // Select first window
  runQuiet(`tmux select-window -t "${name}:0"`);

  return name;
}

function listGroups(): void {
  const ws = readWorkspaceConfig();
  if (!ws?.groups?.length) {
    console.log("No tab groups configured in ~/.lattices/workspace.json");
    return;
  }

  console.log("Tab Groups:\n");
  for (const group of ws.groups) {
    const tabs = group.tabs || [];
    const runningCount = tabs.filter((t: TabConfig) => sessionExists(toSessionName(resolve(t.path)))).length;
    const running = runningCount > 0;
    const status = running
      ? `\x1b[32m● ${runningCount}/${tabs.length} running\x1b[0m`
      : "\x1b[90m○ stopped\x1b[0m";
    const tabLabels = tabs.map((t: TabConfig) => t.label || basename(t.path)).join(", ");
    console.log(`  ${group.label || group.id}  ${status}`);
    console.log(`    id: ${group.id}`);
    console.log(`    tabs: ${tabLabels}`);
    console.log();
  }
}

function groupCommand(id?: string): void {
  const ws = readWorkspaceConfig();
  if (!ws?.groups?.length) {
    console.log("No tab groups configured in ~/.lattices/workspace.json");
    return;
  }

  if (!id) {
    listGroups();
    return;
  }

  const group = ws.groups.find((g: GroupConfig) => g.id === id);
  if (!group) {
    console.log(`No group "${id}". Available: ${ws.groups.map((g: GroupConfig) => g.id).join(", ")}`);
    return;
  }

  const tabs = group.tabs || [];
  if (!tabs.length) {
    console.log(`Group "${group.id}" has no tabs.`);
    return;
  }

  // Each tab gets its own lattices session (individual project sessions)
  const firstDir = resolve(tabs[0].path);
  const firstName = toSessionName(firstDir);

  // If the first tab's session already exists, just attach
  if (sessionExists(firstName)) {
    console.log(`Reattaching to "${group.label || group.id}" (${tabs[0].label || basename(firstDir)})...`);
    attach(firstName);
    return;
  }

  // Create a detached session for each tab
  console.log(`Launching group "${group.label || group.id}" (${tabs.length} tabs)...`);
  for (const tab of tabs) {
    const dir = resolve(tab.path);
    const name = toSessionName(dir);
    if (!sessionExists(name)) {
      console.log(`  Creating session: ${tab.label || basename(dir)}`);
      createSession(dir);
    }
  }

  // Attach to the first tab's session
  attach(firstName);
}

function tabCommand(groupId?: string, tabName?: string): void {
  if (!groupId) {
    console.log("Usage: lattices tab <group-id> <tab-name|index>");
    return;
  }

  const ws = readWorkspaceConfig();
  if (!ws?.groups?.length) {
    console.log("No tab groups configured.");
    return;
  }

  const group = ws.groups.find((g: GroupConfig) => g.id === groupId);
  if (!group) {
    console.log(`No group "${groupId}".`);
    return;
  }

  const tabs: TabConfig[] = group.tabs || [];

  if (!tabName) {
    // List tabs with their session status
    console.log(`Tabs in "${group.label || group.id}":\n`);
    for (let i = 0; i < tabs.length; i++) {
      const label = tabs[i].label || basename(tabs[i].path);
      const tabSession = toSessionName(resolve(tabs[i].path));
      const running = sessionExists(tabSession);
      const status = running ? "\x1b[32m●\x1b[0m" : "\x1b[90m○\x1b[0m";
      console.log(`  ${status} ${i}: ${label}  (session: ${tabSession})`);
    }
    return;
  }

  // Resolve tab target to an index
  let tabIdx: number;
  if (/^\d+$/.test(tabName)) {
    tabIdx = parseInt(tabName, 10);
  } else {
    tabIdx = tabs.findIndex(
      (t) => (t.label || basename(t.path)).toLowerCase() === tabName.toLowerCase()
    );
    if (tabIdx === -1) {
      const available = tabs.map((t) => t.label || basename(t.path)).join(", ");
      console.log(`No tab "${tabName}". Available: ${available}`);
      return;
    }
  }

  if (tabIdx < 0 || tabIdx >= tabs.length) {
    console.log(`Tab index ${tabIdx} is out of range (${tabs.length} tabs).`);
    return;
  }

  // Each tab is its own lattices session — attach to it
  const dir = resolve(tabs[tabIdx].path);
  const tabSession = toSessionName(dir);
  const label = tabs[tabIdx].label || basename(dir);

  if (sessionExists(tabSession)) {
    console.log(`Attaching to tab: ${label}`);
    attach(tabSession);
  } else {
    console.log(`Creating session for tab: ${label}`);
    createSession(dir);
    attach(tabSession);
  }
}

// ── Detect dev command ───────────────────────────────────────────────

function detectPackageManager(dir: string): string {
  if (existsSync(resolve(dir, "bun.lockb")) || existsSync(resolve(dir, "bun.lock")))
    return "bun";
  if (existsSync(resolve(dir, "pnpm-lock.yaml"))) return "pnpm";
  if (existsSync(resolve(dir, "yarn.lock"))) return "yarn";
  return "npm";
}

function detectDevCommand(dir: string): string | null {
  const pkgPath = resolve(dir, "package.json");
  if (!existsSync(pkgPath)) return null;

  let pkg: any;
  try {
    pkg = JSON.parse(readFileSync(pkgPath, "utf8"));
  } catch {
    return null;
  }

  const scripts = pkg.scripts || {};
  const pm = detectPackageManager(dir);
  const runCmd = pm === "npm" ? "npm run" : pm;

  if (scripts.dev) return `${runCmd} dev`;
  if (scripts.start) return `${runCmd} start`;
  if (scripts.serve) return `${runCmd} serve`;
  if (scripts.watch) return `${runCmd} watch`;
  return null;
}

// ── Session creation ─────────────────────────────────────────────────

function resolvePane(panes: any[], dir: string): PaneConfig[] {
  return panes.map((p: any) => ({
    name: p.name || "",
    cmd: p.cmd || undefined,
    size: p.size || undefined,
  }));
}

/** Get ordered pane IDs (e.g. ["%0", "%1"]) for a session */
function getPaneIds(name: string): string[] {
  const out = runQuiet(
    `tmux list-panes -t "${name}" -F "#{pane_id}"`
  );
  return out ? out.split("\n").filter(Boolean) : [];
}

function createSession(dir: string): string {
  const name = toSessionName(dir);
  const config = readConfig(dir);
  const d = esc(dir);

  let panes: PaneConfig[];
  if (config?.panes?.length) {
    panes = resolvePane(config.panes, dir);
    console.log(`Using .lattices.json (${panes.length} panes)`);
  } else {
    panes = defaultPanes(dir);
    if (panes.length > 1) console.log(`Detected: ${panes[1].cmd}`);
    else console.log(`No dev server detected — single pane`);
  }

  // Create session (targets are config-agnostic — no hardcoded indices)
  run(`tmux new-session -d -s "${name}" -c '${d}'`);

  if (panes.length === 2) {
    const mainSize = panes[0].size || 60;
    run(
      `tmux split-window -h -t "${name}" -c '${d}' -p ${100 - mainSize}`
    );
  } else if (panes.length >= 3) {
    const mainSize = panes[0].size || 60;
    for (let i = 1; i < panes.length; i++) {
      run(`tmux split-window -t "${name}" -c '${d}'`);
    }
    runQuiet(
      `tmux set-option -t "${name}" -w main-pane-width '${mainSize}%'`
    );
    run(`tmux select-layout -t "${name}" main-vertical`);
  }

  // Get actual pane IDs (works regardless of base-index / pane-base-index)
  const paneIds = getPaneIds(name);

  // Send commands and name each pane
  for (let i = 0; i < panes.length && i < paneIds.length; i++) {
    if (panes[i].cmd) {
      run(`tmux send-keys -t "${paneIds[i]}" '${esc(panes[i].cmd!)}' Enter`);
    }
    if (panes[i].name) {
      runQuiet(`tmux select-pane -t "${paneIds[i]}" -T "${panes[i].name}"`);
    }
  }

  // Tag the terminal window title so the menu bar app can find it
  // Format: [lattices:session-hash] pane_title: current_command
  runQuiet(`tmux set-option -t "${name}" set-titles on`);
  runQuiet(`tmux set-option -t "${name}" set-titles-string "[lattices:${name}] #{pane_title}"`);

  // Name the tmux window after the project and focus the first pane
  runQuiet(`tmux rename-window -t "${name}" "${basename(dir)}"`);
  if (paneIds.length) {
    run(`tmux select-pane -t "${paneIds[0]}"`);
  }

  return name;
}

/** Check each pane and prefill or restart commands that have exited.
 *  mode: "prefill" types the command without pressing Enter
 *  mode: "ensure" types the command and presses Enter */
function restoreCommands(name: string, dir: string, mode: "prefill" | "ensure"): void {
  const config = readConfig(dir);
  let panes: PaneConfig[];
  if (config?.panes?.length) {
    panes = resolvePane(config.panes, dir);
  } else {
    panes = defaultPanes(dir);
  }

  const paneIds = getPaneIds(name);
  const shells = new Set(["bash", "zsh", "fish", "sh", "dash"]);

  let count = 0;
  for (let i = 0; i < panes.length && i < paneIds.length; i++) {
    if (!panes[i].cmd) continue;
    const cur = runQuiet(
      `tmux display-message -t "${paneIds[i]}" -p "#{pane_current_command}"`
    );
    if (cur && shells.has(cur)) {
      if (mode === "ensure") {
        run(`tmux send-keys -t "${paneIds[i]}" '${esc(panes[i].cmd!)}' Enter`);
      } else {
        run(`tmux send-keys -t "${paneIds[i]}" '${esc(panes[i].cmd!)}'`);
      }
      count++;
    }
  }
  if (count > 0) {
    const verb = mode === "ensure" ? "Restarted" : "Prefilled";
    console.log(`${verb} ${count} exited command${count > 1 ? "s" : ""}`);
  }
}

// ── Sync / reconcile ────────────────────────────────────────────────

function resolvePanes(dir: string): PaneConfig[] {
  const config = readConfig(dir);
  if (config?.panes?.length) {
    return resolvePane(config.panes, dir);
  }
  return defaultPanes(dir);
}

// ── Dev command ──────────────────────────────────────────────────────

function detectProjectType(dir: string): string | null {
  // Check for lattices-style hybrid project (Swift app + Node CLI)
  if (existsSync(resolve(dir, "apps/mac/Package.swift")) && existsSync(resolve(dir, "bin/lattices-app.ts")))
    return "lattices-app";
  if (existsSync(resolve(dir, "Package.swift"))) return "swift";
  if (existsSync(resolve(dir, "Cargo.toml"))) return "rust";
  if (existsSync(resolve(dir, "go.mod"))) return "go";
  if (existsSync(resolve(dir, "package.json"))) return "node";
  if (existsSync(resolve(dir, "Makefile"))) return "make";
  return null;
}

async function forwardToLatticesDevHelper(dir: string, cmd: string, extraFlags: string[] = []): Promise<void> {
  const localDevScript = resolve(dir, "bin/lattices-dev");
  const devScript = existsSync(localDevScript) ? localDevScript : resolve(import.meta.dir, "lattices-dev");
  const { execFileSync } = await import("node:child_process");
  try {
    execFileSync(devScript, [cmd, ...extraFlags], { stdio: "inherit" });
  } catch {
    /* exit code forwarded */
  }
}

async function devCommand(sub?: string, ...flags: string[]): Promise<void> {
  const dir = process.cwd();
  const type = detectProjectType(dir);

  if (!sub) {
    // bare `lattices dev` — run dev server
    if (!type) {
      console.log("No recognized project in current directory.");
      return;
    }
    console.log(`Detected: ${type} project`);
    if (type === "lattices-app") {
      await forwardToLatticesDevHelper(dir, "restart", flags);
    } else if (type === "node") {
      const cmd = detectDevCommand(dir);
      if (cmd) {
        console.log(`Running: ${cmd}`);
        execSync(cmd, { cwd: dir, stdio: "inherit" });
      } else {
        console.log("No dev script found in package.json.");
      }
    } else if (type === "swift") {
      console.log("Running: swift run");
      execSync("swift run", { cwd: dir, stdio: "inherit" });
    } else if (type === "rust") {
      console.log("Running: cargo run");
      execSync("cargo run", { cwd: dir, stdio: "inherit" });
    } else if (type === "go") {
      console.log("Running: go run .");
      execSync("go run .", { cwd: dir, stdio: "inherit" });
    } else if (type === "make") {
      execSync("make", { cwd: dir, stdio: "inherit" });
    }
    return;
  }

  if (sub === "placement-smoke") {
    await placementSmokeCommand(flags);
    return;
  }

  if (sub === "build") {
    if (!type) {
      console.log("No recognized project in current directory.");
      return;
    }
    if (type === "lattices-app") {
      await forwardToLatticesDevHelper(dir, "build");
    } else if (type === "swift") {
      console.log("Building: swift build -c release");
      execSync("swift build -c release", { cwd: dir, stdio: "inherit" });
    } else if (type === "node") {
      const pm = detectPackageManager(dir);
      const runCmd = pm === "npm" ? "npm run" : pm;
      const pkg = JSON.parse(readFileSync(resolve(dir, "package.json"), "utf8"));
      if (pkg.scripts?.build) {
        console.log(`Running: ${runCmd} build`);
        execSync(`${runCmd} build`, { cwd: dir, stdio: "inherit" });
      } else {
        console.log("No build script found in package.json.");
      }
    } else if (type === "rust") {
      console.log("Building: cargo build --release");
      execSync("cargo build --release", { cwd: dir, stdio: "inherit" });
    } else if (type === "go") {
      console.log("Building: go build .");
      execSync("go build .", { cwd: dir, stdio: "inherit" });
    } else if (type === "make") {
      execSync("make", { cwd: dir, stdio: "inherit" });
    }
    return;
  }

  if (sub === "restart") {
    if (type === "lattices-app") {
      await forwardToLatticesDevHelper(dir, "restart", flags);
    } else {
      // For other project types, just rebuild
      await devCommand("build");
    }
    return;
  }

  if (sub === "type") {
    console.log(type || "unknown");
    return;
  }

  console.log(`Unknown dev subcommand: ${sub}`);
  console.log("Usage: lattices dev [build|restart|type]");
}

function defaultPanes(dir: string): PaneConfig[] {
  const devCmd = detectDevCommand(dir);
  if (devCmd) {
    return [
      { name: "shell", size: 60 },
      { name: "server", cmd: devCmd },
    ];
  }
  // No dev server detected → single pane
  return [{ name: "shell" }];
}

function syncSession(): void {
  const dir = process.cwd();
  const name = toSessionName(dir);

  if (!sessionExists(name)) {
    console.log(`No session "${name}" — creating from scratch.`);
    createSession(dir);
    console.log("Session created.");
    return;
  }

  const panes = resolvePanes(dir);
  const actualIds = getPaneIds(name);
  const declared = panes.length;
  const actual = actualIds.length;
  const d = esc(dir);
  const shells = new Set(["bash", "zsh", "fish", "sh", "dash"]);

  console.log(`Session "${name}": ${actual} pane(s) found, ${declared} declared.`);

  // Phase 1: recreate missing panes
  if (actual < declared) {
    const missing = declared - actual;
    console.log(`Recreating ${missing} missing pane(s)...`);
    for (let i = 0; i < missing; i++) {
      run(`tmux split-window -t "${name}" -c '${d}'`);
    }

    // Re-apply layout
    if (declared === 2) {
      const mainSize = panes[0].size || 60;
      // With 2 panes, use horizontal split layout
      run(`tmux select-layout -t "${name}" even-horizontal`);
      runQuiet(
        `tmux set-option -t "${name}" -w main-pane-width '${mainSize}%'`
      );
      run(`tmux select-layout -t "${name}" main-vertical`);
    } else if (declared >= 3) {
      const mainSize = panes[0].size || 60;
      runQuiet(
        `tmux set-option -t "${name}" -w main-pane-width '${mainSize}%'`
      );
      run(`tmux select-layout -t "${name}" main-vertical`);
    }
  }

  // Phase 2: restore commands and labels on all panes
  const freshIds = getPaneIds(name);
  let restored = 0;
  for (let i = 0; i < panes.length && i < freshIds.length; i++) {
    // Set pane title/label
    if (panes[i].name) {
      runQuiet(`tmux select-pane -t "${freshIds[i]}" -T "${panes[i].name}"`);
    }
    // If pane is idle at a shell prompt, send its declared command
    if (panes[i].cmd) {
      const cur = runQuiet(
        `tmux display-message -t "${freshIds[i]}" -p "#{pane_current_command}"`
      );
      if (cur && shells.has(cur)) {
        run(`tmux send-keys -t "${freshIds[i]}" '${esc(panes[i].cmd!)}' Enter`);
        restored++;
      }
    }
  }

  // Focus first pane
  if (freshIds.length) {
    run(`tmux select-pane -t "${freshIds[0]}"`);
  }

  if (restored > 0) {
    console.log(`Restarted ${restored} command(s).`);
  }
  console.log("Sync complete.");
}

// ── Restart pane ────────────────────────────────────────────────────

function restartPane(target?: string): void {
  const dir = process.cwd();
  const name = toSessionName(dir);

  if (!sessionExists(name)) {
    console.log(`No session "${name}".`);
    return;
  }

  const panes = resolvePanes(dir);
  const paneIds = getPaneIds(name);

  // Resolve target to an index
  let idx: number;
  if (target === undefined || target === null || target === "") {
    // Default: first pane
    idx = 0;
  } else if (/^\d+$/.test(target)) {
    idx = parseInt(target, 10);
  } else {
    // Match by name (case-insensitive)
    idx = panes.findIndex(
      (p) => p.name && p.name.toLowerCase() === target.toLowerCase()
    );
    if (idx === -1) {
      console.log(
        `No pane named "${target}". Available: ${panes.map((p, i) => p.name || `[${i}]`).join(", ")}`
      );
      return;
    }
  }

  if (idx < 0 || idx >= paneIds.length) {
    console.log(`Pane index ${idx} is out of range (${paneIds.length} panes).`);
    return;
  }

  const paneId = paneIds[idx];
  const pane = panes[idx] || {};
  const label = pane.name || `pane ${idx}`;

  // Get the PID of the process running in the pane
  const panePid = runQuiet(
    `tmux display-message -t "${paneId}" -p "#{pane_pid}"`
  );

  // Step 1: try C-c to gracefully stop
  console.log(`Stopping ${label}...`);
  run(`tmux send-keys -t "${paneId}" C-c`);

  // Brief pause to let C-c propagate
  execSync("sleep 0.5");

  // Step 2: check if the process is still running (not back to shell)
  const shells = new Set(["bash", "zsh", "fish", "sh", "dash"]);
  const cur = runQuiet(
    `tmux display-message -t "${paneId}" -p "#{pane_current_command}"`
  );

  if (cur && !shells.has(cur)) {
    // Still hung — escalate: kill the child processes of the pane
    console.log(`Process still running (${cur}), sending SIGKILL...`);
    if (panePid) {
      // Kill all children of the pane's shell process
      runQuiet(`pkill -KILL -P ${panePid}`);
      execSync("sleep 0.3");
    }
  }

  // Step 3: send the declared command
  if (pane.cmd) {
    console.log(`Starting: ${pane.cmd}`);
    run(`tmux send-keys -t "${paneId}" '${esc(pane.cmd)}' Enter`);
  } else {
    console.log(`No command declared for ${label} — pane is at shell prompt.`);
  }
}

// ── Commands ─────────────────────────────────────────────────────────

// ── Daemon-aware commands ────────────────────────────────────────────

async function mouseCommand(sub?: string): Promise<void> {
  const { daemonCall } = await getDaemonClient();
  if (sub === "summon") {
    const result = await daemonCall("mouse.summon") as any;
    console.log(`🎯 Mouse summoned to (${result.x}, ${result.y})`);
  } else {
    // Default: find
    const result = await daemonCall("mouse.find") as any;
    console.log(`🔍 Mouse at (${result.x}, ${result.y})`);
  }
}

async function daemonStatusCommand(): Promise<void> {
  try {
    const { daemonCall } = await getDaemonClient();
    const status = await daemonCall("daemon.status") as any;
    const uptime = Math.round(status.uptime);
    const h = Math.floor(uptime / 3600);
    const m = Math.floor((uptime % 3600) / 60);
    const s = uptime % 60;
    const uptimeStr = h > 0 ? `${h}h ${m}m ${s}s` : m > 0 ? `${m}m ${s}s` : `${s}s`;
    console.log(`\x1b[32m●\x1b[0m Daemon running on ws://127.0.0.1:9399`);
    console.log(`  uptime:    ${uptimeStr}`);
    console.log(`  clients:   ${status.clientCount}`);
    console.log(`  windows:   ${status.windowCount}`);
    console.log(`  tmux:      ${status.tmuxSessionCount} sessions`);
    console.log(`  version:   ${status.version}`);
  } catch {
    console.log("\x1b[90m○\x1b[0m Daemon not running (start with: lattices app)");
  }
}

async function windowsCommand(jsonFlag: boolean): Promise<void> {
  try {
    const { daemonCall } = await getDaemonClient();
    const windows = await daemonCall("windows.list") as any[];
    if (jsonFlag) {
      console.log(JSON.stringify(windows, null, 2));
      return;
    }
    if (!windows.length) {
      console.log("No windows tracked.");
      return;
    }
    console.log(`Windows (${windows.length}):\n`);
    for (const w of windows) {
      const session = w.latticesSession ? `  \x1b[36m[lattices:${w.latticesSession}]\x1b[0m` : "";
      const layer = w.layerTag ? `  \x1b[33m[layer:${w.layerTag}]\x1b[0m` : "";
      const spaces = w.spaceIds.length ? ` space:${w.spaceIds.join(",")}` : "";
      console.log(`  \x1b[1m${w.app}\x1b[0m  wid:${w.wid}${spaces}${session}${layer}`);
      console.log(`    "${w.title}"`);
      console.log(`    ${Math.round(w.frame.w)}×${Math.round(w.frame.h)} at (${Math.round(w.frame.x)},${Math.round(w.frame.y)})`);
      console.log();
    }
  } catch {
    console.log("Daemon not running. Start with: lattices app");
  }
}

async function windowAssignCommand(wid?: string, layerId?: string): Promise<void> {
  if (!wid || !layerId) {
    console.log("Usage: lattices window assign <wid> <layer-id>");
    return;
  }
  try {
    const { daemonCall } = await getDaemonClient();
    await daemonCall("window.assignLayer", { wid: parseInt(wid), layer: layerId });
    console.log(`Tagged wid:${wid} → layer:${layerId}`);
  } catch (e: unknown) {
    console.log(`Error: ${(e as Error).message}`);
  }
}

async function windowLayerMapCommand(jsonFlag: boolean): Promise<void> {
  try {
    const { daemonCall } = await getDaemonClient();
    const map = await daemonCall("window.layerMap") as any;
    if (jsonFlag) {
      console.log(JSON.stringify(map, null, 2));
      return;
    }
    const entries = Object.entries(map);
    if (!entries.length) {
      console.log("No layer tags assigned.");
      return;
    }
    console.log("Window → Layer map:\n");
    for (const [wid, layer] of entries) {
      console.log(`  wid:${wid} → ${layer}`);
    }
  } catch {
    console.log("Daemon not running. Start with: lattices app");
  }
}

async function focusCommand(session?: string): Promise<void> {
  if (!session) {
    console.log("Usage: lattices focus <session-name>");
    return;
  }
  try {
    const { daemonCall } = await getDaemonClient();
    await daemonCall("window.focus", { session });
    console.log(`Focused: ${session}`);
  } catch (e: unknown) {
    console.log(`Error: ${(e as Error).message}`);
  }
}

// ── Search ───────────────────────────────────────────────────────────

interface SearchResult {
  score: number;
  window: any;
  tabs: { tab: number; cwd: string; title: string; hasClaude: boolean; tmuxSession: string }[];
  reasons: string[];
}

function relativeTime(iso: string): string {
  const ms = Date.now() - new Date(iso).getTime();
  const s = Math.floor(ms / 1000);
  if (s < 60) return "just now";
  const m = Math.floor(s / 60);
  if (m < 60) return `${m}m ago`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h ago`;
  const d = Math.floor(h / 24);
  return `${d}d ago`;
}

// Unified search via lattices.search daemon API.
// All search surfaces should go through this one function.
interface SearchOptions {
  sources?: string[];    // e.g. ["titles", "apps", "cwd", "ocr"] — omit for smart default
  after?: string;        // ISO8601 — only windows interacted after this time
  before?: string;       // ISO8601 — only windows interacted before this time
  recency?: boolean;     // boost recently-focused windows (default true)
  mode?: string;         // legacy compat: "quick", "complete", "terminal"
}

async function search(query: string, opts: SearchOptions = {}): Promise<SearchResult[]> {
  const { daemonCall } = await getDaemonClient();
  const params: Record<string, any> = { query };
  if (opts.sources) params.sources = opts.sources;
  if (opts.after) params.after = opts.after;
  if (opts.before) params.before = opts.before;
  if (opts.recency !== undefined) params.recency = opts.recency;
  if (opts.mode) params.mode = opts.mode; // legacy fallback
  const hits = await daemonCall("lattices.search", params, 10000) as any[];
  return hits.map((w: any) => ({
    score: w.score || 0,
    window: w,
    tabs: (w.terminalTabs || []).map((t: any) => ({
      tab: t.tabIndex, cwd: t.cwd, title: t.tabTitle, hasClaude: t.hasClaude, tmuxSession: t.tmuxSession,
    })),
    reasons: w.matchSources || [],
  }));
}

// Convenience aliases
async function deepSearch(query: string): Promise<SearchResult[]> { return search(query, { sources: ["all"] }); }
async function terminalSearch(query: string): Promise<SearchResult[]> { return search(query, { sources: ["terminals"] }); }

// Format and print search results
function printResults(ranked: SearchResult[]): void {
  if (!ranked.length) return;
  for (const r of ranked) {
    const w = r.window;
    const age = w.lastInteraction ? ` \x1b[2m${relativeTime(w.lastInteraction)}\x1b[0m` : "";
    console.log(`  \x1b[1m${w.app}\x1b[0m  "${w.title}"  wid:${w.wid}  score:${r.score}  (${r.reasons.join(", ")})${age}`);
    for (const t of r.tabs) {
      const claude = t.hasClaude ? " \x1b[32m●\x1b[0m" : "";
      const tmux = t.tmuxSession ? ` \x1b[36m[${t.tmuxSession}]\x1b[0m` : "";
      console.log(`    tab ${t.tab}: ${t.cwd || t.title}${claude}${tmux}`);
    }
    if (w.ocrSnippet) console.log(`    ocr: "${w.ocrSnippet}"`);
  }
  console.log();
}

// ── search command ───────────────────────────────────────────────────

async function searchCommand(query: string | undefined, flags: Set<string>, rawArgs: string[] = []): Promise<void> {
  if (!query) {
    console.log("Usage: lattices search <query> [--quick | --terminal | --all | --sources=... | --after=... | --before=... | --json | --wid]");
    return;
  }

  // Build search options from flags
  const opts: SearchOptions = {};

  // Source selection: explicit --sources, or legacy --quick/--terminal, or default
  const sourcesFlag = rawArgs.find(a => a.startsWith("--sources="));
  if (sourcesFlag) {
    opts.sources = sourcesFlag.slice("--sources=".length).split(",");
  } else if (flags.has("--all")) {
    opts.sources = ["all"];
  } else if (flags.has("--quick")) {
    opts.sources = ["titles", "apps", "sessions"];
  } else if (flags.has("--terminal")) {
    opts.sources = ["terminals"];
  }
  // else: omit → smart default on daemon side

  // Time filters
  const afterFlag = rawArgs.find(a => a.startsWith("--after="));
  if (afterFlag) opts.after = afterFlag.slice("--after=".length);
  const beforeFlag = rawArgs.find(a => a.startsWith("--before="));
  if (beforeFlag) opts.before = beforeFlag.slice("--before=".length);

  // No-recency flag
  if (flags.has("--no-recency")) opts.recency = false;

  const ranked = await search(query, opts);
  const jsonOut = flags.has("--json");
  const widOnly = flags.has("--wid");

  if (jsonOut) {
    console.log(JSON.stringify(ranked.map(r => ({
      wid: r.window.wid, app: r.window.app, title: r.window.title,
      score: r.score, reasons: r.reasons, tabs: r.tabs, ocrSnippet: r.window.ocrSnippet,
    })), null, 2));
    return;
  }

  if (widOnly) {
    for (const r of ranked) console.log(r.window.wid);
    return;
  }

  if (!ranked.length) {
    console.log(`No results for "${query}"`);
    return;
  }

  printResults(ranked);
}

// ── place command ────────────────────────────────────────────────────

async function placeCommand(query?: string, tilePosition?: string): Promise<void> {
  if (!query) {
    console.log("Usage: lattices place <query> [position]");
    return;
  }
  try {
    const { daemonCall } = await getDaemonClient();
    const ranked = await deepSearch(query);

    if (!ranked.length) {
      console.log(`No window matching "${query}"`);
      return;
    }

    const pos = tilePosition || "bottom-right";
    const win = ranked[0].window;
    await daemonCall("window.focus", { wid: win.wid });
    await daemonCall("intents.execute", {
      intent: "tile_window",
      slots: { position: pos, wid: win.wid }
    }, 3000);
    console.log(`${win.app} "${win.title}" (wid:${win.wid}) → ${pos}`);
  } catch (e: unknown) {
    console.log(`Error: ${(e as Error).message}`);
  }
}

function pause(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function receiptLine(receipt: any): string {
  const id = receipt?.action?.id || "action";
  const session = receipt?.session || receipt?.target?.session || "?";
  const wid = receipt?.wid ?? receipt?.target?.wid ?? "?";
  const status = receipt?.status || "?";
  const verified = receipt?.verified === true ? "true" : "false";
  const resolution = receipt?.targetResolution || "?";
  return `  ${id}  session=${session}  wid=${wid}  status=${status}  verified=${verified}  resolution=${resolution}`;
}

async function placementSmokeCommand(rawArgs: string[] = []): Promise<void> {
  const { daemonCall } = await getDaemonClient();
  const pauseMs = Number(parseFlagValue(rawArgs, "pause") || 1200);
  const positional = nonFlagArgs(rawArgs);

  let sessions = positional.slice(0, 2);
  if (sessions.length < 2) {
    const tmuxSessions = await daemonCall("tmux.sessions") as any[];
    sessions = tmuxSessions
      .map(s => s?.name)
      .filter((name: unknown): name is string => typeof name === "string" && name.startsWith("lattices-place-"))
      .slice(0, 2);
  }

  if (sessions.length < 2) {
    console.log("Need two named sessions. Usage: lattices dev placement-smoke <session-a> <session-b>");
    console.log("Tip: launch two small lattices fixture projects first, then rerun this command.");
    return;
  }

  const [a, b] = sessions;
  console.log(`Placement smoke: ${a} + ${b}`);

  for (const session of sessions) {
    const resolved = await daemonCall("window.resolve", {
      target: { kind: "session", session },
      placement: "left",
    }) as any;
    console.log(`  resolve ${session}: wid=${resolved.wid ?? "?"} app=${resolved.app ?? "?"} resolution=${resolved.targetResolution ?? "?"}`);
  }

  const beats = [
    {
      label: "beat 1: halves",
      actions: [
        { id: "a-left-half", type: "window.place", target: { kind: "session", session: a }, args: { placement: "left" } },
        { id: "b-right-half", type: "window.place", target: { kind: "session", session: b }, args: { placement: "right" } },
      ],
    },
    {
      label: "beat 2: 4x4 corners",
      actions: [
        { id: "a-top-left-4x4", type: "window.place", target: { kind: "session", session: a }, args: { placement: "grid:4x4:0,0" } },
        { id: "b-bottom-right-4x4", type: "window.place", target: { kind: "session", session: b }, args: { placement: "grid:4x4:3,3" } },
      ],
    },
    {
      label: "beat 3: workbench",
      actions: [
        {
          id: "a-workbench-left",
          type: "window.place",
          target: { kind: "session", session: a },
          args: { placement: { kind: "fractions", x: 0.02, y: 0.05, w: 0.62, h: 0.9 } },
        },
        {
          id: "b-console-right",
          type: "window.place",
          target: { kind: "session", session: b },
          args: { placement: { kind: "fractions", x: 0.67, y: 0.12, w: 0.3, h: 0.76 } },
        },
      ],
    },
  ];

  for (const beat of beats) {
    console.log(`\n${beat.label}`);
    const result = await daemonCall("actions.execute", {
      source: "placement-smoke",
      actions: beat.actions,
    }, 15000) as any;
    console.log(`  batch=${result.status || "?"} request=${result.requestId || "?"}`);
    for (const receipt of result.receipts || []) {
      console.log(receiptLine(receipt));
    }
    await pause(pauseMs);
  }

  const focused = await daemonCall("window.focus", { session: a }, 5000) as any;
  console.log(`\nfocus ${a}: ok=${focused.ok === true} wid=${focused.wid ?? "?"} raised=${focused.raised === true}`);
}

async function sessionsCommand(jsonFlag: boolean): Promise<void> {
  try {
    const { daemonCall } = await getDaemonClient();
    const sessions = await daemonCall("tmux.sessions") as any[];
    if (jsonFlag) {
      console.log(JSON.stringify(sessions, null, 2));
      return;
    }
    if (!sessions.length) {
      console.log("No active sessions.");
      return;
    }
    console.log(`Sessions (${sessions.length}):\n`);
    for (const s of sessions) {
      const windows = s.windowCount || s.windows || "?";
      console.log(`  \x1b[1m${s.name}\x1b[0m  (${windows} windows)`);
    }
  } catch {
    console.log("Daemon not running. Start with: lattices app");
  }
}

async function voiceCommand(subcommand?: string, ...rest: string[]): Promise<void> {
  const { daemonCall } = await getDaemonClient();
  try {
    switch (subcommand) {
      case "status": {
        const status = await daemonCall("voice.status") as any;
        console.log(`Provider: ${status.provider}`);
        console.log(`Available: ${status.available}`);
        console.log(`Listening: ${status.listening}`);
        if (status.lastTranscript) console.log(`Last: "${status.lastTranscript}"`);
        break;
      }
      case "simulate":
      case "sim": {
        const text = rest.join(" ");
        if (!text) {
          console.log("Usage: lattices voice simulate <text>");
          return;
        }
        const execute = !rest.includes("--dry-run");
        const dryFlag = rest.includes("--dry-run");
        const cleanText = dryFlag ? rest.filter(r => r !== "--dry-run").join(" ") : text;
        const result = await daemonCall("voice.simulate", { text: cleanText, execute }, 15000) as any;
        if (!result.parsed) {
          console.log(`\x1b[33mNo match:\x1b[0m "${cleanText}"`);
          return;
        }
        const slots = Object.entries(result.slots || {}).map(([k,v]) => `${k}: ${v}`).join(", ");
        const conf = result.confidence ? ` (${(result.confidence * 100).toFixed(0)}%)` : "";
        console.log(`\x1b[36m${result.intent}\x1b[0m${slots ? `  ${slots}` : ""}${conf}`);
        if (result.executed) {
          console.log(`\x1b[32mExecuted\x1b[0m`);
        } else if (result.error) {
          console.log(`\x1b[31mError:\x1b[0m ${result.error}`);
        }
        break;
      }
      case "intents": {
        const intents = await daemonCall("intents.list") as any[];
        for (const intent of intents) {
          const slots = intent.slots.map((s: any) => `${s.name}:${s.type}${s.required ? "*" : ""}`).join(", ");
          console.log(`  \x1b[1m${intent.intent}\x1b[0m  ${intent.description}`);
          if (slots) console.log(`    slots: ${slots}`);
          console.log(`    e.g. "${intent.examples[0]}"`);
          console.log();
        }
        break;
      }
      default:
        console.log("Usage: lattices voice <subcommand>\n");
        console.log("  status      Show voice provider status");
        console.log("  simulate    Parse and execute a voice command");
        console.log("  intents     List all available intents");
        console.log("\nExamples:");
        console.log('  lattices voice simulate "tile this left"');
        console.log('  lattices voice simulate "focus chrome" --dry-run');
    }
  } catch (e: unknown) {
    console.log(`Error: ${(e as Error).message}`);
  }
}

async function assistantCommand(subcommand?: string, ...rest: string[]): Promise<void> {
  if (subcommand !== "plan") {
    console.log("Usage: lattices assistant plan <text> [--json]");
    return;
  }

  const jsonOut = rest.includes("--json");
  const text = rest.filter((arg) => arg !== "--json").join(" ").trim();
  if (!text) {
    console.log("Usage: lattices assistant plan <text> [--json]");
    return;
  }

  const { tryLocalAssistantPlan } = await import("./assistant-intelligence.ts");
  const result = tryLocalAssistantPlan(text) ?? {
    actions: [],
    spoken: "No local TS plan matched.",
    _meta: { source: "local-rule", matched: false },
  };

  if (jsonOut) {
    console.log(JSON.stringify(result, null, 2));
    return;
  }

  console.log(result.spoken);
}

async function callCommand(method?: string, ...rest: string[]): Promise<void> {
  if (!method) {
    console.log("Usage: lattices call <method> [params-json]");
    console.log("\nExamples:");
    console.log("  lattices call daemon.status");
    console.log("  lattices call api.schema");
    console.log('  lattices call window.place \'{"session":"vox","placement":"left"}\'');
    return;
  }
  try {
    const { daemonCall } = await getDaemonClient();
    const params = rest[0] ? JSON.parse(rest[0]) : null;
    const result = await daemonCall(method, params, 15000);
    console.log(JSON.stringify(result, null, 2));
  } catch (e: unknown) {
    console.log(`Error: ${(e as Error).message}`);
  }
}

interface AppActorAsset {
  id: string;
  appName: string;
  appPath: string;
  bundleIdentifier?: string;
  iconPath: string;
  assetDir: string;
}

function plistValue(plistPath: string, key: string): string | undefined {
  const value = runQuiet(`/usr/libexec/PlistBuddy -c 'Print :${esc(key)}' '${esc(plistPath)}' 2>/dev/null`);
  return value?.trim() || undefined;
}

function resolveApplication(appQuery: string): string | undefined {
  const directPath = appQuery.endsWith(".app") ? resolve(appQuery) : undefined;
  if (directPath && existsSync(directPath)) return directPath.replace(/\/$/, "");

  const script = `POSIX path of (path to application "${appleScriptString(appQuery.replace(/\.app$/i, ""))}")`;
  const fromLaunchServices = runQuiet(`osascript -e '${esc(script)}' 2>/dev/null`);
  if (fromLaunchServices) return fromLaunchServices.trim().replace(/\/$/, "");

  const appName = appQuery.endsWith(".app") ? appQuery : `${appQuery}.app`;
  const fromFind = runQuiet(
    `find /Applications /System/Applications '${esc(resolve(homedir(), "Applications"))}' -maxdepth 5 -iname '${esc(appName)}' -print -quit 2>/dev/null`
  );
  return fromFind?.trim().replace(/\/$/, "") || undefined;
}

function resolveApplicationByBundleIdentifier(bundleIdentifier: string): string | undefined {
  const script = `POSIX path of (path to application id "${appleScriptString(bundleIdentifier)}")`;
  const fromLaunchServices = runQuiet(`osascript -e '${esc(script)}' 2>/dev/null`);
  return fromLaunchServices?.trim().replace(/\/$/, "") || undefined;
}

function iconPathForApplication(appPath: string): string | undefined {
  const resourcesDir = resolve(appPath, "Contents", "Resources");
  const infoPlist = resolve(appPath, "Contents", "Info.plist");
  const iconFile = plistValue(infoPlist, "CFBundleIconFile");
  const candidates: string[] = [];
  if (iconFile) {
    candidates.push(resolve(resourcesDir, iconFile));
    if (!/\.[a-z0-9]+$/i.test(iconFile)) {
      candidates.push(resolve(resourcesDir, `${iconFile}.icns`));
    }
  }
  candidates.push(
    resolve(resourcesDir, "AppIcon.icns"),
    resolve(resourcesDir, "icon.icns"),
    resolve(resourcesDir, "electron.icns")
  );
  for (const candidate of candidates) {
    if (existsSync(candidate)) return candidate;
  }
  const firstIcns = runQuiet(`find '${esc(resourcesDir)}' -maxdepth 1 -iname '*.icns' -print -quit 2>/dev/null`);
  return firstIcns?.trim() || undefined;
}

function ensureAppActorAsset(appQuery: string): AppActorAsset {
  const appPath = resolveApplication(appQuery);
  if (!appPath) {
    throw new Error(`Could not find application: ${appQuery}`);
  }

  const appName = basename(appPath, ".app");
  const iconPath = iconPathForApplication(appPath);
  if (!iconPath) {
    throw new Error(`Could not find an icon resource in ${appPath}`);
  }

  const id = `${slugify(appName)}-icon`;
  const assetDir = resolve(homedir(), ".codex", "pets", id);
  const spritesheetPath = resolve(assetDir, "spritesheet.png");
  mkdirSync(assetDir, { recursive: true });
  run(`sips -s format png -Z 192 '${esc(iconPath)}' --out '${esc(spritesheetPath)}' >/dev/null`);

  const metadata = {
    id,
    displayName: `${appName} Icon`,
    description: `A one-frame overlay actor made from the ${appName} application icon.`,
    spritesheetPath: "spritesheet.png",
    states: {
      idle: { row: 0, frames: 1, frameWidth: 192, frameHeight: 192 },
      thinking: { row: 0, frames: 1, frameWidth: 192, frameHeight: 192 },
      working: { row: 0, frames: 1, frameWidth: 192, frameHeight: 192 },
      listening: { row: 0, frames: 1, frameWidth: 192, frameHeight: 192 },
      waiting: { row: 0, frames: 1, frameWidth: 192, frameHeight: 192 },
      ready: { row: 0, frames: 1, frameWidth: 192, frameHeight: 192 },
    },
  };
  writeFileSync(resolve(assetDir, "pet.json"), `${JSON.stringify(metadata, null, 2)}\n`);

  const bundleIdentifier = plistValue(resolve(appPath, "Contents", "Info.plist"), "CFBundleIdentifier");
  return { id, appName, appPath, bundleIdentifier, iconPath, assetDir };
}

function ensureIconActorAsset(idSeed: string, displayName: string, iconPath: string): string {
  if (!existsSync(iconPath)) {
    throw new Error(`HUD icon does not exist: ${iconPath}`);
  }

  const id = `${slugify(idSeed)}-hud-icon`;
  const assetDir = resolve(homedir(), ".codex", "pets", id);
  const spritesheetPath = resolve(assetDir, "spritesheet.png");
  mkdirSync(assetDir, { recursive: true });
  run(`sips -s format png -Z 192 '${esc(iconPath)}' --out '${esc(spritesheetPath)}' >/dev/null`);

  const metadata = {
    id,
    displayName: `${displayName} HUD Icon`,
    description: `A one-frame overlay actor icon for the ${displayName} HUD.`,
    spritesheetPath: "spritesheet.png",
    states: {
      idle: { row: 0, frames: 1, frameWidth: 192, frameHeight: 192 },
      thinking: { row: 0, frames: 1, frameWidth: 192, frameHeight: 192 },
      working: { row: 0, frames: 1, frameWidth: 192, frameHeight: 192 },
      listening: { row: 0, frames: 1, frameWidth: 192, frameHeight: 192 },
      waiting: { row: 0, frames: 1, frameWidth: 192, frameHeight: 192 },
      ready: { row: 0, frames: 1, frameWidth: 192, frameHeight: 192 },
    },
  };
  writeFileSync(resolve(assetDir, "pet.json"), `${JSON.stringify(metadata, null, 2)}\n`);
  return id;
}

function actorUsage(): void {
  console.log(`Usage:
  lattices actor app <app-name> [message] [--state=idle] [--x=520 --y=340] [--show-label]
  lattices actor switcher [app-name ...] [--x=420 --y=220 --gap=270] [--show-label]
  lattices actor hud <actor-id> <url> [--hud-width=360 --hud-height=240]
  lattices actor show|hide|toggle|status

Examples:
  lattices actor app Codex "Building the release"
  lattices actor app Talkie "Hover for latest state" --hud-url=http://localhost:5173
  lattices actor hud switch-talkie http://localhost:5173
  lattices actor switcher Codex Talkie
  lattices actor toggle
  lattices actor switcher "Google Chrome" Codex Talkie --show-label --scale=0.8
`);
}

async function actorCommand(sub?: string, ...rest: string[]): Promise<void> {
  if (sub === "app") {
    await actorAppCommand(rest);
    return;
  }
  if (sub === "switcher") {
    await actorSwitcherCommand(rest);
    return;
  }
  if (sub === "hud") {
    await actorHUDCommand(rest);
    return;
  }
  if (sub === "show" || sub === "hide" || sub === "toggle" || sub === "status") {
    await actorVisibilityCommand(sub, rest);
    return;
  }
  actorUsage();
}

function actorHUDOptions(rest: string[]): Record<string, unknown> {
  const hudUrl = parseFlagValue(rest, "hud-url") || parseFlagValue(rest, "hudUrl");
  const hudHTML = parseFlagValue(rest, "hud-html") || parseFlagValue(rest, "hudHTML") || parseFlagValue(rest, "hudHtml");
  const hudTitle = parseFlagValue(rest, "hud-title") || parseFlagValue(rest, "hudTitle");
  const hudWidth = parseFlagValue(rest, "hud-width") || parseFlagValue(rest, "hudWidth") || parseFlagValue(rest, "width");
  const hudHeight = parseFlagValue(rest, "hud-height") || parseFlagValue(rest, "hudHeight") || parseFlagValue(rest, "height");
  return {
    ...(hudUrl ? { hudUrl } : {}),
    ...(hudHTML ? { hudHTML } : {}),
    ...(hudTitle ? { hudTitle } : {}),
    ...(hudWidth ? { hudWidth: Number(hudWidth) } : {}),
    ...(hudHeight ? { hudHeight: Number(hudHeight) } : {}),
  };
}

function shouldHideActorLabel(rest: string[]): boolean {
  if (hasFlag(rest, "show-label") || hasFlag(rest, "showLabel")) return false;
  return true;
}

async function actorHUDCommand(rest: string[]): Promise<void> {
  const positional = nonFlagArgs(rest);
  const id = positional[0];
  if (!id) {
    actorUsage();
    return;
  }

  const { daemonCall } = await getDaemonClient();
  const url = positional[1];
  const clear = hasFlag(rest, "clear");
  const result = await daemonCall("overlay.actor.hud", {
    id,
    clear,
    ...(url && !clear ? { hudUrl: url } : {}),
    ...actorHUDOptions(rest),
  }, 15000) as any;

  if (hasFlag(rest, "json")) {
    console.log(JSON.stringify(result, null, 2));
  } else if (clear) {
    console.log(`Cleared HUD for ${id}.`);
  } else {
    console.log(`Attached hover HUD to ${id}.`);
  }
}

async function actorVisibilityCommand(action: string, rest: string[]): Promise<void> {
  const { daemonCall } = await getDaemonClient();
  const result = await daemonCall("overlay.actor.visibility", {
    action,
    feedback: !hasFlag(rest, "quiet") && action !== "status",
  }, 15000) as any;

  if (hasFlag(rest, "json")) {
    console.log(JSON.stringify(result, null, 2));
    return;
  }

  const state = result.visible ? "shown" : "hidden";
  const count = Number(result.actorCount ?? 0);
  console.log(`Actor layer ${state} (${count} actor${count === 1 ? "" : "s"}).`);
}

async function actorAppCommand(rest: string[]): Promise<void> {
  const positional = nonFlagArgs(rest);
  const appQuery = positional[0];
  if (!appQuery) {
    actorUsage();
    return;
  }
  const message = positional.slice(1).join(" ") || `Tap to switch to ${appQuery}.`;
  const asset = ensureAppActorAsset(appQuery);
  const { daemonCall } = await getDaemonClient();
  const id = parseFlagValue(rest, "id") || `app-${slugify(asset.appName)}`;
  const state = parseFlagValue(rest, "state") || "idle";
  const ttlMs = Number(parseFlagValue(rest, "ttl") || parseFlagValue(rest, "ttlMs") || 0);
  const x = Number(parseFlagValue(rest, "x") || 520);
  const y = Number(parseFlagValue(rest, "y") || 340);
  const placement = parseFlagValue(rest, "placement") || "point";
  const style = parseFlagValue(rest, "style") || "playful";
  const dismissible = hasFlag(rest, "dismissible");
  const labelHidden = shouldHideActorLabel(rest);
  const closeOnActivate = hasFlag(rest, "close-on-activate") || hasFlag(rest, "closeOnActivate");
  const scale = Number(parseFlagValue(rest, "scale") || 1);

  const result = await daemonCall("overlay.actor.publish", {
    id,
    renderer: "sprite",
    asset: asset.id,
    state,
    name: parseFlagValue(rest, "name") || asset.appName,
    message,
    placement,
    x,
    y,
    style,
    ttlMs,
    dismissible,
    labelHidden,
    closeOnActivate,
    scale,
    ...actorHUDOptions(rest),
    targetApp: asset.appName,
    targetBundleId: asset.bundleIdentifier,
    targetAppPath: asset.appPath,
  }, 15000) as any;

  if (!hasFlag(rest, "no-move")) {
    await daemonCall("overlay.actor.moveTo", {
      id,
      x: x + 40,
      y: y + 50,
      durationMs: 700,
      easing: "spring",
    }, 15000);
  }

  if (hasFlag(rest, "json")) {
    console.log(JSON.stringify({ ...result, asset: asset.id, appPath: asset.appPath }, null, 2));
  } else {
    console.log(`Published ${asset.appName} actor (${id}). Click it to switch to ${asset.appName}.`);
  }
}

async function actorSwitcherCommand(rest: string[]): Promise<void> {
  const appNames = nonFlagArgs(rest);
  const apps = appNames.length ? appNames : ["Codex", "Talkie"];
  const { daemonCall } = await getDaemonClient();
  const startX = Number(parseFlagValue(rest, "x") || 420);
  const y = Number(parseFlagValue(rest, "y") || 220);
  const gap = Number(parseFlagValue(rest, "gap") || 270);
  const ttlMs = Number(parseFlagValue(rest, "ttl") || parseFlagValue(rest, "ttlMs") || 0);
  const style = parseFlagValue(rest, "style") || "info";
  const dismissible = hasFlag(rest, "dismissible");
  const labelHidden = shouldHideActorLabel(rest);
  const closeOnActivate = hasFlag(rest, "close-on-activate") || hasFlag(rest, "closeOnActivate");
  const scale = Number(parseFlagValue(rest, "scale") || 1);
  const results: any[] = [];

  for (let i = 0; i < apps.length; i++) {
    const asset = ensureAppActorAsset(apps[i]);
    const id = `switch-${slugify(asset.appName)}`;
    const x = startX + i * gap;
    const result = await daemonCall("overlay.actor.publish", {
      id,
      renderer: "sprite",
      asset: asset.id,
      state: "ready",
      name: asset.appName,
      message: `Tap to switch to ${asset.appName}.`,
      placement: "point",
      x,
      y,
      style,
      ttlMs,
      dismissible,
      labelHidden,
      closeOnActivate,
      scale,
      ...actorHUDOptions(rest),
      targetApp: asset.appName,
      targetBundleId: asset.bundleIdentifier,
      targetAppPath: asset.appPath,
    }, 15000) as any;
    results.push({ ...result, asset: asset.id, appPath: asset.appPath });
    await daemonCall("overlay.actor.moveTo", {
      id,
      x: x + 28,
      y: y + 36,
      durationMs: 650,
      easing: "spring",
    }, 15000);
  }

  if (hasFlag(rest, "json")) {
    console.log(JSON.stringify(results, null, 2));
  } else {
    console.log(`Published app switcher for ${apps.join(", ")}.`);
  }
}

type HUDPathField = string | {
  path?: string;
  format?: string;
  schema?: string;
  presentation?: string;
  title?: string;
  description?: string;
  pollMs?: number;
};

interface HUDManifest {
  version?: number;
  manifestVersion?: number;
  id?: string;
  name?: string;
  bundleId?: string;
  bundleIdentifier?: string;
  app?: string;
  appPath?: string;
  icon?: string;
  entry?: string;
  readAccess?: string | string[];
  state?: HUDPathField;
  events?: HUDPathField | HUDPathField[];
  log?: HUDPathField;
  logs?: HUDPathField[];
  sources?: HUDPathField[] | Record<string, HUDPathField>;
  surface?: {
    width?: number;
    height?: number;
    title?: string;
    transparent?: boolean;
  };
  actor?: {
    id?: string;
    message?: string;
    state?: string;
    x?: number;
    y?: number;
    placement?: string;
    style?: string;
    scale?: number;
    labelHidden?: boolean;
    closeOnActivate?: boolean;
    click?: string | { type?: string };
  };
}

interface ResolvedHUDManifest {
  manifestPath: string;
  rootDir: string;
  manifest: HUDManifest;
  id: string;
  name: string;
  entry: string;
  iconPath?: string;
  appPath?: string;
  bundleIdentifier?: string;
  readAccessPath?: string;
}

interface HUDRegistryEntry {
  id: string;
  name?: string;
  bundleIdentifier?: string;
  manifestPath: string;
  registeredAt: string;
  lastPublishedAt?: string;
}

interface HUDRegistry {
  version: 1;
  entries: HUDRegistryEntry[];
}

function hudUsage(): void {
  console.log(`Usage:
  lattices hud register [manifest] [--publish]   Register .lattices/hud/manifest.json
  lattices hud publish [manifest-or-id]          Publish one HUD actor now
  lattices hud sync                              Publish all registered HUD actors
  lattices hud list                              List registered HUDs
  lattices hud discover [root] [--register]      Find HUD manifests under a folder

Manifest:
  .lattices/hud/manifest.json

Examples:
  lattices hud register .lattices/hud/manifest.json --publish
  lattices hud publish talkie --x=520 --y=340
  lattices hud sync
`);
}

function hudRegistryPath(): string {
  return resolve(homedir(), ".lattices", "huds.json");
}

function readHUDRegistry(): HUDRegistry {
  const path = hudRegistryPath();
  if (!existsSync(path)) return { version: 1, entries: [] };
  try {
    const parsed = JSON.parse(readFileSync(path, "utf8")) as Partial<HUDRegistry>;
    return {
      version: 1,
      entries: Array.isArray(parsed.entries) ? parsed.entries : [],
    };
  } catch (e: unknown) {
    throw new Error(`Invalid HUD registry ${path}: ${(e as Error).message}`);
  }
}

function writeHUDRegistry(registry: HUDRegistry): void {
  const path = hudRegistryPath();
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, `${JSON.stringify(registry, null, 2)}\n`);
}

function isDirectory(path: string): boolean {
  try {
    return statSync(path).isDirectory();
  } catch {
    return false;
  }
}

function isURLLike(value: string): boolean {
  return /^[a-z][a-z0-9+.-]*:/i.test(value);
}

function resolveHUDPath(rootDir: string, value: HUDPathField | undefined, fallback?: string): string | undefined {
  const raw = typeof value === "string" ? value : value?.path;
  const path = raw || fallback;
  if (!path) return undefined;
  if (isURLLike(path)) return path;
  if (path.startsWith("~/")) return resolve(homedir(), path.slice(2));
  return isAbsolute(path) ? path : resolve(rootDir, path);
}

function resolveHUDReadAccess(rootDir: string, manifest: HUDManifest, rest: string[] = []): string {
  const flagValue = parseFlagValue(rest, "read-access") || parseFlagValue(rest, "readAccess");
  const declared = flagValue
    ?? (Array.isArray(manifest.readAccess) ? manifest.readAccess[0] : manifest.readAccess);
  if (!declared) return rootDir;
  if (isURLLike(declared)) return rootDir;
  if (declared.startsWith("~/")) return resolve(homedir(), declared.slice(2));
  return isAbsolute(declared) ? declared : resolve(rootDir, declared);
}

function resolveHUDManifestInput(input?: string): string {
  if (!input) {
    const defaultPath = resolve(process.cwd(), ".lattices", "hud", "manifest.json");
    if (existsSync(defaultPath)) return defaultPath;
    throw new Error("No manifest provided and .lattices/hud/manifest.json was not found.");
  }

  const candidate = resolve(input);
  if (existsSync(candidate)) {
    return isDirectory(candidate) ? resolve(candidate, "manifest.json") : candidate;
  }

  const registry = readHUDRegistry();
  const entry = registry.entries.find((item) => item.id === input);
  if (entry) return entry.manifestPath;

  throw new Error(`HUD manifest or registered id not found: ${input}`);
}

function readHUDManifest(input?: string): ResolvedHUDManifest {
  const manifestPath = resolveHUDManifestInput(input);
  if (!existsSync(manifestPath)) {
    throw new Error(`HUD manifest does not exist: ${manifestPath}`);
  }

  const rootDir = dirname(manifestPath);
  const manifest = JSON.parse(readFileSync(manifestPath, "utf8")) as HUDManifest;
  const id = manifest.actor?.id || manifest.id;
  if (!id) throw new Error(`HUD manifest is missing id: ${manifestPath}`);

  const name = manifest.name || id;
  const entry = resolveHUDPath(rootDir, manifest.entry, "./index.html");
  if (!entry) throw new Error(`HUD manifest is missing entry: ${manifestPath}`);
  if (!isURLLike(entry) && !existsSync(entry)) {
    throw new Error(`HUD entry does not exist: ${entry}`);
  }

  const iconPath = resolveHUDPath(rootDir, manifest.icon);
  const appPath = resolveHUDPath(rootDir, manifest.appPath)
    ?? (manifest.bundleId || manifest.bundleIdentifier
      ? resolveApplicationByBundleIdentifier(manifest.bundleId || manifest.bundleIdentifier || "")
      : undefined)
    ?? (manifest.app ? resolveApplication(manifest.app) : undefined);
  const bundleIdentifier = manifest.bundleId
    ?? manifest.bundleIdentifier
    ?? (appPath ? plistValue(resolve(appPath, "Contents", "Info.plist"), "CFBundleIdentifier") : undefined);

  return {
    manifestPath,
    rootDir,
    manifest,
    id,
    name,
    entry,
    iconPath: iconPath && !isURLLike(iconPath) ? iconPath : undefined,
    appPath: appPath && !isURLLike(appPath) ? appPath : undefined,
    bundleIdentifier,
    readAccessPath: resolveHUDReadAccess(rootDir, manifest),
  };
}

function numberFlag(rest: string[], name: string, fallback: number): number {
  const raw = parseFlagValue(rest, name);
  if (!raw) return fallback;
  const value = Number(raw);
  return Number.isFinite(value) ? value : fallback;
}

function numberFlagAny(rest: string[], names: string[], fallback: number): number {
  for (const name of names) {
    const raw = parseFlagValue(rest, name);
    if (!raw) continue;
    const value = Number(raw);
    if (Number.isFinite(value)) return value;
  }
  return fallback;
}

function hudActorAsset(resolved: ResolvedHUDManifest): string | undefined {
  if (resolved.iconPath) {
    return ensureIconActorAsset(resolved.id, resolved.name, resolved.iconPath);
  }

  const appQuery = resolved.appPath || resolved.manifest.app;
  if (!appQuery) return undefined;

  try {
    return ensureAppActorAsset(appQuery).id;
  } catch {
    return undefined;
  }
}

function hudClickType(manifest: HUDManifest): string {
  const click = manifest.actor?.click;
  if (!click) return "activateApp";
  return typeof click === "string" ? click : click.type || "activateApp";
}

function hudPublishPayload(resolved: ResolvedHUDManifest, rest: string[], index = 0): Record<string, unknown> {
  const manifest = resolved.manifest;
  const actor = manifest.actor ?? {};
  const surface = manifest.surface ?? {};
  const targetEnabled = hudClickType(manifest) !== "none";
  const asset = hudActorAsset(resolved);
  const x = numberFlag(rest, "x", actor.x ?? 420 + index * 112);
  const y = numberFlag(rest, "y", actor.y ?? 220);

  return {
    id: resolved.id,
    renderer: "sprite",
    ...(asset ? { asset } : {}),
    state: parseFlagValue(rest, "state") || actor.state || "ready",
    name: parseFlagValue(rest, "name") || resolved.name,
    message: actor.message || `Hover for ${resolved.name} status.`,
    placement: parseFlagValue(rest, "placement") || actor.placement || "point",
    x,
    y,
    style: parseFlagValue(rest, "style") || actor.style || "info",
    labelHidden: actor.labelHidden ?? true,
    closeOnActivate: actor.closeOnActivate ?? false,
    scale: numberFlag(rest, "scale", actor.scale ?? 1),
    hudUrl: resolved.entry,
    hudTitle: surface.title || resolved.name,
    hudWidth: numberFlagAny(rest, ["hud-width", "hudWidth", "width"], surface.width ?? 380),
    hudHeight: numberFlagAny(rest, ["hud-height", "hudHeight", "height"], surface.height ?? 260),
    hudReadAccess: resolveHUDReadAccess(resolved.rootDir, manifest, rest),
    ...(targetEnabled && resolved.bundleIdentifier ? { targetBundleId: resolved.bundleIdentifier } : {}),
    ...(targetEnabled && resolved.appPath ? { targetAppPath: resolved.appPath } : {}),
    ...(targetEnabled && manifest.app ? { targetApp: manifest.app } : {}),
  };
}

function upsertHUDRegistryEntry(resolved: ResolvedHUDManifest, published = false): HUDRegistryEntry {
  const registry = readHUDRegistry();
  const now = new Date().toISOString();
  const existing = registry.entries.find((entry) => entry.id === resolved.id);
  const next: HUDRegistryEntry = {
    id: resolved.id,
    name: resolved.name,
    bundleIdentifier: resolved.bundleIdentifier,
    manifestPath: resolved.manifestPath,
    registeredAt: existing?.registeredAt ?? now,
    lastPublishedAt: published ? now : existing?.lastPublishedAt,
  };
  registry.entries = [
    next,
    ...registry.entries.filter((entry) => entry.id !== resolved.id),
  ].sort((a, b) => a.id.localeCompare(b.id));
  writeHUDRegistry(registry);
  return next;
}

async function publishHUDManifest(resolved: ResolvedHUDManifest, rest: string[], index = 0): Promise<Record<string, unknown>> {
  const { daemonCall } = await getDaemonClient();
  const payload = hudPublishPayload(resolved, rest, index);
  const result = await daemonCall("overlay.actor.publish", payload, 15000) as Record<string, unknown>;
  if (!hasFlag(rest, "no-move")) {
    await daemonCall("overlay.actor.moveTo", {
      id: resolved.id,
      x: Number(payload.x) + 24,
      y: Number(payload.y) + 30,
      durationMs: 600,
      easing: "spring",
    }, 15000);
  }
  upsertHUDRegistryEntry(resolved, true);
  return result;
}

async function hudRegisterCommand(rest: string[]): Promise<void> {
  const manifestArg = nonFlagArgs(rest)[0] || parseFlagValue(rest, "manifest");
  const resolved = readHUDManifest(manifestArg);
  const entry = upsertHUDRegistryEntry(resolved, false);

  if (hasFlag(rest, "publish")) {
    await publishHUDManifest(resolved, rest);
  }

  const published = hasFlag(rest, "publish");
  if (hasFlag(rest, "json")) {
    console.log(JSON.stringify(entry, null, 2));
  } else {
    console.log(`${published ? "Registered and published" : "Registered"} HUD ${resolved.id} -> ${resolved.manifestPath}`);
  }
}

async function hudPublishCommand(rest: string[]): Promise<void> {
  const manifestArg = nonFlagArgs(rest)[0] || parseFlagValue(rest, "manifest");
  const resolved = readHUDManifest(manifestArg);
  const result = await publishHUDManifest(resolved, rest);

  if (hasFlag(rest, "json")) {
    console.log(JSON.stringify({ ...result, manifestPath: resolved.manifestPath }, null, 2));
  } else {
    console.log(`Published HUD actor ${resolved.id}. Hover it for ${resolved.name}.`);
  }
}

async function hudSyncCommand(rest: string[]): Promise<void> {
  const registry = readHUDRegistry();
  const results: Record<string, unknown>[] = [];
  for (let i = 0; i < registry.entries.length; i++) {
    const resolved = readHUDManifest(registry.entries[i].id);
    results.push(await publishHUDManifest(resolved, rest, i));
  }

  if (hasFlag(rest, "json")) {
    console.log(JSON.stringify(results, null, 2));
  } else {
    console.log(`Published ${results.length} registered HUD actor${results.length === 1 ? "" : "s"}.`);
  }
}

function hudListCommand(rest: string[]): void {
  const registry = readHUDRegistry();
  if (hasFlag(rest, "json")) {
    console.log(JSON.stringify(registry, null, 2));
    return;
  }
  if (!registry.entries.length) {
    console.log("No registered HUDs. Run lattices hud register .lattices/hud/manifest.json");
    return;
  }
  console.log("Registered HUDs:\n");
  for (const entry of registry.entries) {
    console.log(`  ${entry.id}${entry.name ? ` (${entry.name})` : ""}`);
    console.log(`    manifest: ${entry.manifestPath}`);
    if (entry.bundleIdentifier) console.log(`    bundle:   ${entry.bundleIdentifier}`);
    if (entry.lastPublishedAt) console.log(`    shown:    ${entry.lastPublishedAt}`);
    console.log();
  }
}

function hudDiscoverCommand(rest: string[]): void {
  const root = resolve(nonFlagArgs(rest)[0] || parseFlagValue(rest, "root") || process.cwd());
  const maxDepth = Number(parseFlagValue(rest, "max-depth") || parseFlagValue(rest, "maxDepth") || 6);
  const out = runQuiet(`find '${esc(root)}' -maxdepth ${maxDepth} -path '*/.lattices/hud/manifest.json' -print 2>/dev/null`);
  const manifests = out ? out.split("\n").filter(Boolean) : [];

  if (hasFlag(rest, "register")) {
    for (const manifestPath of manifests) {
      upsertHUDRegistryEntry(readHUDManifest(manifestPath), false);
    }
  }

  if (hasFlag(rest, "json")) {
    console.log(JSON.stringify(manifests, null, 2));
    return;
  }

  if (!manifests.length) {
    console.log(`No HUD manifests found under ${root}`);
    return;
  }
  for (const manifestPath of manifests) console.log(manifestPath);
  if (hasFlag(rest, "register")) {
    console.log(`\nRegistered ${manifests.length} HUD manifest${manifests.length === 1 ? "" : "s"}.`);
  }
}

async function hudCommand(sub?: string, ...rest: string[]): Promise<void> {
  try {
    switch (sub) {
    case "register":
      await hudRegisterCommand(rest);
      return;
    case "publish":
    case "show":
      await hudPublishCommand(rest);
      return;
    case "sync":
      await hudSyncCommand(rest);
      return;
    case "list":
    case "ls":
      hudListCommand(rest);
      return;
    case "discover":
      hudDiscoverCommand(rest);
      return;
    default:
      hudUsage();
    }
  } catch (e: unknown) {
    console.log(`Error: ${(e as Error).message}`);
  }
}

async function layerCommand(sub?: string, ...rest: string[]): Promise<void> {
  try {
    const { daemonCall } = await getDaemonClient();

    // ── Subcommands ──
    if (sub === "create") {
      await layerCreateCommand(rest);
      return;
    }
    if (sub === "snap") {
      await layerSnapCommand(rest[0]);
      return;
    }
    if (sub === "session" || sub === "sessions") {
      await layerSessionCommand(rest[0]);
      return;
    }
    if (sub === "clear") {
      await daemonCall("session.layers.clear");
      console.log("Cleared all session layers.");
      return;
    }
    if (sub === "delete" || sub === "rm") {
      if (!rest[0]) { console.log("Usage: lattices layer delete <name>"); return; }
      await daemonCall("session.layers.delete", { name: rest[0] });
      console.log(`Deleted session layer "${rest[0]}".`);
      return;
    }

    // ── List or switch (original behavior) ──
    if (sub === undefined || sub === null || sub === "") {
      const result = await daemonCall("layers.list") as any;
      if (!result.layers.length) {
        console.log("No layers configured.");
        return;
      }
      console.log("Layers:\n");
      for (const layer of result.layers) {
        const active = layer.index === result.active ? " \x1b[32m● active\x1b[0m" : "";
        console.log(`  [${layer.index}] ${layer.label}  (${layer.projectCount} projects)${active}`);
      }
      return;
    }
    const idx = parseInt(sub, 10);
    if (!isNaN(idx)) {
      await daemonCall("layer.activate", { index: idx, mode: "launch" });
      console.log(`Activated layer ${idx}`);
    } else {
      await daemonCall("layer.activate", { name: sub, mode: "launch" });
      console.log(`Activated layer "${sub}"`);
    }
  } catch (e: unknown) {
    console.log(`Error: ${(e as Error).message}`);
  }
}

// ── Layer create: build a session layer from window specs ────────────
// Usage: lattices layer create <name> [wid:123 wid:456 ...]
//        lattices layer create <name> --json '[{"app":"Chrome","tile":"left"},...]'
async function layerCreateCommand(args: string[]): Promise<void> {
  const { daemonCall } = await getDaemonClient();
  const name = args[0];
  if (!name) {
    console.log("Usage: lattices layer create <name> [wid:123 ...] [--json '<specs>']");
    return;
  }

  const jsonIdx = args.indexOf("--json");
  if (jsonIdx !== -1 && args[jsonIdx + 1]) {
    // JSON mode: parse window specs with tile positions
    const specs = JSON.parse(args[jsonIdx + 1]) as Array<{
      wid?: number; app?: string; title?: string; tile?: string;
    }>;

    // Collect wids, resolve app-based specs
    const windowIds: number[] = [];
    const windows: Array<{ app: string; contentHint?: string }> = [];
    const tiles: Array<{ wid?: number; app?: string; title?: string; tile: string }> = [];

    for (const spec of specs) {
      if (spec.wid) {
        windowIds.push(spec.wid);
        if (spec.tile) tiles.push({ wid: spec.wid, tile: spec.tile });
      } else if (spec.app) {
        windows.push({ app: spec.app, contentHint: spec.title });
        if (spec.tile) tiles.push({ app: spec.app, title: spec.title, tile: spec.tile });
      }
    }

    const result = await daemonCall("session.layers.create", {
      name,
      ...(windowIds.length ? { windowIds } : {}),
      ...(windows.length ? { windows } : {}),
    }) as any;

    console.log(`Created session layer "${name}" with ${specs.length} window(s).`);

    // Apply tile positions
    for (const t of tiles) {
      try {
        await daemonCall("window.place", {
          ...(t.wid ? { wid: t.wid } : { app: t.app, title: t.title }),
          placement: t.tile,
        });
      } catch { /* window may not be resolved yet */ }
    }

    if (tiles.length) console.log(`Tiled ${tiles.length} window(s).`);
    return;
  }

  // Simple wid mode: lattices layer create <name> wid:123 wid:456
  const wids = args.slice(1)
    .filter(a => a.startsWith("wid:"))
    .map(a => parseInt(a.slice(4), 10))
    .filter(n => !isNaN(n));

  const result = await daemonCall("session.layers.create", {
    name,
    ...(wids.length ? { windowIds: wids } : {}),
  }) as any;

  console.log(`Created session layer "${name}"${wids.length ? ` with ${wids.length} window(s)` : ""}.`);
}

// ── Layer snap: snapshot current visible windows into a session layer ─
async function layerSnapCommand(name?: string): Promise<void> {
  const { daemonCall } = await getDaemonClient();
  const layerName = name || `snap-${new Date().toISOString().slice(11, 19).replace(/:/g, "")}`;

  // Get all current windows
  const windows = await daemonCall("windows.list") as any[];
  const visibleWids = windows
    .filter((w: any) => !w.isMinimized && w.app !== "lattices")
    .map((w: any) => w.wid);

  if (!visibleWids.length) {
    console.log("No visible windows to snapshot.");
    return;
  }

  await daemonCall("session.layers.create", {
    name: layerName,
    windowIds: visibleWids,
  });

  console.log(`Snapped ${visibleWids.length} window(s) → session layer "${layerName}".`);
}

// ── Layer session: list or switch session layers ─────────────────────
async function layerSessionCommand(nameOrIndex?: string): Promise<void> {
  const { daemonCall } = await getDaemonClient();
  const result = await daemonCall("session.layers.list") as any;

  if (!nameOrIndex) {
    // List session layers
    if (!result.layers.length) {
      console.log("No session layers. Create one with: lattices layer create <name>");
      return;
    }
    console.log("Session layers:\n");
    for (let i = 0; i < result.layers.length; i++) {
      const l = result.layers[i];
      const active = i === result.activeIndex ? " \x1b[32m● active\x1b[0m" : "";
      const winCount = l.windows?.length || 0;
      console.log(`  [${i}] ${l.name}  (${winCount} windows)${active}`);
    }
    return;
  }

  // Switch by index or name
  const idx = parseInt(nameOrIndex, 10);
  if (!isNaN(idx)) {
    await daemonCall("session.layers.switch", { index: idx });
    console.log(`Switched to session layer ${idx}.`);
  } else {
    await daemonCall("session.layers.switch", { name: nameOrIndex });
    console.log(`Switched to session layer "${nameOrIndex}".`);
  }
}

async function diagCommand(limit?: string): Promise<void> {
  try {
    const { daemonCall } = await getDaemonClient();
    const result = await daemonCall("diagnostics.list", { limit: parseInt(limit || "", 10) || 40 }) as any;
    if (!result.entries || !result.entries.length) {
      console.log("No diagnostic entries.");
      return;
    }
    for (const entry of result.entries) {
      const icon = entry.level === "success" ? "\x1b[32m✓\x1b[0m" :
                   entry.level === "warning" ? "\x1b[33m⚠\x1b[0m" :
                   entry.level === "error"   ? "\x1b[31m✗\x1b[0m" : "›";
      console.log(`  \x1b[90m${entry.time}\x1b[0m ${icon} ${entry.message}`);
    }
  } catch (e: unknown) {
    console.log(`Error: ${(e as Error).message}`);
  }
}

async function distributeCommand(rawArgs: string[] = []): Promise<void> {
  const request = parseSpaceOptimizeArgs(rawArgs, "visible");
  await optimizeWindowsCommand(request, "Distributed");
}

async function tileFamilyCommand(rawArgs: string[]): Promise<void> {
  const request = parseSpaceOptimizeArgs(rawArgs, "active-app");
  await optimizeWindowsCommand(request, "Smart-tiled");
}

async function daemonLsCommand(): Promise<boolean> {
  try {
    const { daemonCall, isDaemonRunning } = await getDaemonClient();
    if (!(await isDaemonRunning())) return false;
    const sessions = await daemonCall("tmux.sessions") as any[];
    if (!sessions.length) {
      console.log("No active tmux sessions.");
      return true;
    }

    // Annotate sessions with workspace group info
    const ws = readWorkspaceConfig();
    const sessionGroupMap = new Map<string, { group: string; tab: string }>();
    if (ws?.groups) {
      for (const g of ws.groups) {
        for (const tab of g.tabs || []) {
          const tabSession = toSessionName(resolve(tab.path));
          sessionGroupMap.set(tabSession, {
            group: g.label || g.id,
            tab: tab.label || basename(tab.path),
          });
        }
      }
    }

    console.log("Sessions:\n");
    for (const s of sessions) {
      const info = sessionGroupMap.get(s.name);
      const groupTag = info ? `  \x1b[36m[${info.group}: ${info.tab}]\x1b[0m` : "";
      const attachTag = s.attached ? "  \x1b[33m[attached]\x1b[0m" : "";
      console.log(`  ${s.name}  (${s.windowCount} windows)${attachTag}${groupTag}`);
    }
    return true;
  } catch {
    return false;
  }
}

async function daemonStatusInventory(): Promise<boolean> {
  try {
    const { daemonCall, isDaemonRunning } = await getDaemonClient();
    if (!(await isDaemonRunning())) return false;
    const inv = await daemonCall("tmux.inventory") as any;

    // Build managed session name set
    const managed = new Map<string, string>();
    const ws = readWorkspaceConfig();
    if (ws?.groups) {
      for (const g of ws.groups) {
        for (const tab of g.tabs || []) {
          const name = toSessionName(resolve(tab.path));
          const label = `${g.label || g.id}: ${tab.label || basename(tab.path)}`;
          managed.set(name, label);
        }
      }
    }
    for (const s of inv.all) {
      if (!managed.has(s.name)) {
        // Check if it matches a scanned project (via daemon)
        const projects = await daemonCall("projects.list") as any[];
        for (const p of projects) {
          managed.set(p.sessionName, p.name);
        }
        break;
      }
    }

    const managedSessions = inv.all.filter((s: any) => managed.has(s.name));
    const orphanSessions = inv.orphans;

    if (managedSessions.length > 0) {
      console.log(`\x1b[32m●\x1b[0m Managed Sessions (${managedSessions.length})\n`);
      for (const s of managedSessions) {
        const label = managed.get(s.name) || s.name;
        const attachTag = s.attached ? "  \x1b[33m[attached]\x1b[0m" : "";
        console.log(`  \x1b[1m${s.name}\x1b[0m  (${s.windowCount} window${s.windowCount === 1 ? "" : "s"})${attachTag}  \x1b[36m[${label}]\x1b[0m`);
        for (const p of s.panes) {
          console.log(`    ${p.title || "pane"}: ${p.currentCommand}`);
        }
        console.log();
      }
    } else {
      console.log("\x1b[90m○\x1b[0m No managed sessions running.\n");
    }

    if (orphanSessions.length > 0) {
      console.log(`\x1b[33m○\x1b[0m Unmanaged Sessions (${orphanSessions.length})\n`);
      for (const s of orphanSessions) {
        const attachTag = s.attached ? "  \x1b[33m[attached]\x1b[0m" : "";
        console.log(`  \x1b[1m${s.name}\x1b[0m  (${s.windowCount} window${s.windowCount === 1 ? "" : "s"})${attachTag}`);
        for (const p of s.panes) {
          console.log(`    ${p.title || "pane"}: ${p.currentCommand}`);
        }
        console.log();
      }
    } else {
      console.log("\x1b[90m○\x1b[0m No unmanaged sessions.\n");
    }
    return true;
  } catch {
    return false;
  }
}

// ── OCR commands ──────────────────────────────────────────────────────

async function scanCommand(sub?: string, ...rest: string[]): Promise<void> {
  const { daemonCall } = await getDaemonClient();

  if (!sub || sub === "snapshot" || sub === "ls" || sub === "--full" || sub === "-f" || sub === "--json") {
    const full = sub === "--full" || sub === "-f" || rest.includes("--full") || rest.includes("-f");
    const json = sub === "--json" || rest.includes("--json");
    try {
      const results = await daemonCall("ocr.snapshot", null, 5000) as any[];
      if (!results.length) {
        console.log("No scan results yet. The first scan runs ~60s after launch.");
        return;
      }
      if (json) {
        console.log(JSON.stringify(results, null, 2));
        return;
      }
      console.log(`\x1b[1mScan\x1b[0m  (${results.length} windows)\n`);
      for (const r of results) {
        const age = Math.round((Date.now() / 1000) - r.timestamp);
        const ageStr = age < 60 ? `${age}s ago` : age < 3600 ? `${Math.floor(age / 60)}m ago` : `${Math.floor(age / 3600)}h ago`;
        const src = r.source === "accessibility" ? "\x1b[33mAX\x1b[0m" : "\x1b[35mOCR\x1b[0m";
        const lines = (r.fullText || "").split("\n").filter(Boolean);
        console.log(`  \x1b[1m${r.app}\x1b[0m  wid:${r.wid}  ${src}  \x1b[90m${ageStr}\x1b[0m`);
        console.log(`    \x1b[36m"${r.title || "(untitled)"}"\x1b[0m`);
        if (lines.length) {
          if (full) {
            for (const line of lines) {
              console.log(`    \x1b[90m${line}\x1b[0m`);
            }
          } else {
            const maxPreview = 5;
            const preview = lines.slice(0, maxPreview).map((l: string) => l.length > 100 ? l.slice(0, 97) + "..." : l);
            for (const line of preview) {
              console.log(`    \x1b[90m${line}\x1b[0m`);
            }
            if (lines.length > maxPreview) {
              console.log(`    \x1b[90m… ${lines.length - maxPreview} more lines\x1b[0m`);
            }
          }
        } else {
          console.log(`    \x1b[90m(no text detected)\x1b[0m`);
        }
        console.log();
      }
    } catch {
      console.log("Daemon not running. Start with: lattices app");
    }
    return;
  }

  if (sub === "search") {
    const query = rest.join(" ");
    if (!query) {
      console.log("Usage: lattices scan search <query>");
      return;
    }
    try {
      const results = await daemonCall("ocr.search", { query }, 5000) as any[];
      if (!results.length) {
        console.log(`No matches for "${query}".`);
        return;
      }
      console.log(`\x1b[1mSearch\x1b[0m  "${query}"  (${results.length} matches)\n`);
      for (const r of results) {
        const snippet = r.snippet || r.fullText?.slice(0, 120) || "";
        const src = r.source === "accessibility" ? "\x1b[33mAX\x1b[0m" : "\x1b[35mOCR\x1b[0m";
        console.log(`  ${src}  \x1b[1m${r.app}\x1b[0m  wid:${r.wid}`);
        console.log(`    \x1b[36m"${r.title || "(untitled)"}"\x1b[0m`);
        console.log(`    ${snippet}`);
        console.log();
      }
    } catch (e: unknown) {
      console.log(`Error: ${(e as Error).message}`);
    }
    return;
  }

  if (sub === "recent" || sub === "log") {
    const full = rest.includes("--full") || rest.includes("-f");
    const numArg = rest.find(a => !a.startsWith("-"));
    const limit = parseInt(numArg || "", 10) || 20;
    try {
      const results = await daemonCall("ocr.recent", { limit }, 5000) as any[];
      if (!results.length) {
        console.log("No history yet. The first scan runs ~60s after launch.");
        return;
      }
      console.log(`\x1b[1mRecent\x1b[0m  (${results.length} entries)\n`);
      for (const r of results) {
        const ts = new Date(r.timestamp * 1000).toLocaleTimeString();
        const src = r.source === "accessibility" ? "\x1b[33mAX\x1b[0m" : "\x1b[35mOCR\x1b[0m";
        const lines = (r.fullText || "").split("\n").filter(Boolean);
        console.log(`  \x1b[90m${ts}\x1b[0m  ${src}  \x1b[1m${r.app}\x1b[0m  wid:${r.wid}`);
        console.log(`    \x1b[36m"${r.title || "(untitled)"}"\x1b[0m`);
        if (full) {
          for (const line of lines) {
            console.log(`    \x1b[90m${line}\x1b[0m`);
          }
        } else {
          const maxPreview = 5;
          const preview = lines.slice(0, maxPreview).map((l: string) => l.length > 100 ? l.slice(0, 97) + "..." : l);
          for (const line of preview) {
            console.log(`    \x1b[90m${line}\x1b[0m`);
          }
          if (lines.length > maxPreview) {
            console.log(`    \x1b[90m… ${lines.length - maxPreview} more lines\x1b[0m`);
          }
        }
        console.log();
      }
    } catch {
      console.log("Daemon not running. Start with: lattices app");
    }
    return;
  }

  if (sub === "deep" || sub === "now" || sub === "scan") {
    try {
      console.log("Triggering deep scan (Vision OCR)...");
      await daemonCall("ocr.scan", null, 30000);
      console.log("Done.");
    } catch (e: unknown) {
      console.log(`Error: ${(e as Error).message}`);
    }
    return;
  }

  if (sub === "history") {
    const wid = parseInt(rest[0], 10);
    if (isNaN(wid)) {
      console.log("Usage: lattices scan history <wid>");
      return;
    }
    try {
      const results = await daemonCall("ocr.history", { wid }, 5000) as any[];
      if (!results.length) {
        console.log(`No history for wid:${wid}.`);
        return;
      }
      console.log(`\x1b[1mHistory\x1b[0m  wid:${wid}  (${results.length} entries)\n`);
      for (const r of results) {
        const ts = new Date(r.timestamp * 1000).toLocaleTimeString();
        const src = r.source === "accessibility" ? "\x1b[33mAX\x1b[0m" : "\x1b[35mOCR\x1b[0m";
        const lines = (r.fullText || "").split("\n").filter(Boolean);
        const preview = lines.slice(0, 2).map((l: string) => l.length > 80 ? l.slice(0, 77) + "..." : l);
        console.log(`  \x1b[90m${ts}\x1b[0m  ${src}  \x1b[1m${r.app}\x1b[0m — "${r.title}"`);
        for (const line of preview) {
          console.log(`    \x1b[90m${line}\x1b[0m`);
        }
        console.log();
      }
    } catch (e: unknown) {
      console.log(`Error: ${(e as Error).message}`);
    }
    return;
  }

  // Unknown subcommand
  console.log(`lattices scan — Screen text recognition

Usage:
  lattices scan               Show text from all visible windows
  lattices scan --full        Full text dump
  lattices scan --json        JSON output
  lattices scan search <q>    Full-text search across scanned windows
  lattices scan recent [n]    Show recent scans chronologically (default 20)
  lattices scan deep          Trigger a deep Vision OCR scan
  lattices scan history <wid> Show scan timeline for a window
`);
}

function printUsage(): void {
  console.log(`lattices — workspace launcher for tmux, windows, layers, and the menu bar app

Usage:
  lattices                    Show workspace status and common commands
  lattices start              Start or reattach the current directory's tmux workspace
  lattices tmux               Alias for lattices start
  lattices init               Generate .lattices.json config for this project
  lattices ls                 List active tmux sessions
  lattices status             Show managed vs unmanaged session inventory
  lattices kill [name]        Kill a session (defaults to current project)
  lattices sync               Reconcile session to match declared config
  lattices restart [pane]     Restart a pane's process (by name or index)
  lattices group [id]         List tab groups or launch/attach a group
  lattices groups             List all tab groups with status
  lattices tab <group> [tab]  Switch tab within a group (by label or index)
  lattices search <query>     Search windows by title, app, session, OCR
  lattices search <q> --deep  Deep search: index + live terminal inspection
  lattices search <q> --wid   Print matching window IDs only (pipeable)
  lattices search <q> --json  JSON output
  lattices place <query> [pos]  Deep search + focus + tile (default: bottom-right)
  lattices focus <session>    Raise a session's window
  lattices windows [--json]   List all desktop windows (daemon required)
  lattices sessions [--json]  List active tmux sessions via daemon
  lattices tile <position>    Tile the frontmost window (left, right, top, etc.)
  lattices tile family [app] [region]  Smart-grid the frontmost app family, or a named app
  lattices distribute [app] [region]   Smart-grid visible windows or just one app (daemon required)
  lattices layer [name|index]  List layers or switch by name/index (daemon required)
  lattices layer create <name> [wid:N ...] [--json '<specs>']  Create a session layer
  lattices layer snap [name]   Snapshot visible windows into a session layer
  lattices layer session [n]   List or switch session layers (runtime, no restart)
  lattices layer delete <name> Delete a session layer
  lattices layer clear         Clear all session layers
  lattices voice status       Voice provider status
  lattices voice simulate <t> Parse and execute a voice command
  lattices voice intents      List all available intents
  lattices actor app <app> [message]  Show a clickable app-icon actor
  lattices actor switcher [apps...]   Show a clickable app switcher row
  lattices actor hud <id> <url>       Attach a hover web HUD to an actor
  lattices actor toggle       Hide/show the sticky actor layer
  lattices hud register [manifest]    Register a .lattices/hud/manifest.json
  lattices hud publish [id|manifest]  Publish a registered/static HUD actor
  lattices assistant plan <t> Preview the TS assistant planner
  lattices call <method> [p]  Raw daemon API call (params as JSON)
  lattices scan               Show text from all visible windows
  lattices scan --full        Full text dump
  lattices scan search <q>    Full-text search across scanned windows
  lattices scan recent [n]    Show recent scans chronologically
  lattices scan deep          Trigger a deep Vision OCR scan
  lattices scan history <wid> Scan timeline for a specific window
  lattices dev                Run dev server (auto-detected)
  lattices dev build          Build the project (swift/node/rust/go/make)
  lattices dev restart        Build + restart (swift app) or just build
  lattices dev placement-smoke [a] [b]  Move two named sessions through verified placements
  lattices dev type           Print detected project type
  lattices mouse              Find mouse — sonar pulse at cursor position
  lattices mouse summon       Summon mouse to screen center
  lattices daemon status      Show daemon status
  lattices logs [limit]       Show activity log entries (aliases: log, activity, diag)
  lattices app                Launch the menu bar companion app
  lattices app update         Download the latest menu bar app and relaunch
  lattices app build          Rebuild the menu bar app
  lattices app restart        Rebuild and relaunch the menu bar app
  lattices app quit           Stop the menu bar app
  lattices help               Show this help

Config (.lattices.json):
  Place in your project root to customize the layout:

  {
    "ensure": true,
    "panes": [
      { "name": "shell", "size": 60 },
      { "name": "server", "cmd": "pnpm dev" },
      { "name": "tests",  "cmd": "pnpm test --watch" }
    ]
  }

  size      Width % for the first pane (default: 60)
  cmd       Command to run in the pane
  name      Label (for your reference)
  ensure    Auto-restart exited commands on reattach
  prefill   Type commands into idle panes on reattach (you hit Enter)

Recovery:
  lattices sync       Recreates missing panes, restores commands, fixes layout.
                    Use when a pane was killed and you want to get back to the
                    declared state without killing the whole session.

  lattices restart    Kills the process in a pane and re-runs its declared command.
                    Accepts a pane name or 0-based index (default: 0 / first pane).
                    Examples:  lattices restart         (restarts the first pane)
                               lattices restart server  (restarts "server" by name)
                               lattices restart 1       (restarts pane at index 1)

Layouts:
  1 pane   →  single full-width (default when no dev server detected)
  2 panes  →  side-by-side split
  3+ panes →  main-vertical (first pane left, rest stacked right)

  ┌────────────────────┐    ┌──────────┬─────────┐    ┌──────────┬─────────┐
  │      shell          │    │  shell    │ server  │    │  shell    │ server  │
  │                     │    │  (60%)   │ (40%)   │    │  (60%)   ├─────────┤
  └────────────────────┘    └──────────┴─────────┘    │          │ tests   │
                                                       └──────────┴─────────┘
`);
}

function printHome(): void {
  const dir = process.cwd();
  const sessionName = toSessionName(dir);
  const config = readConfig(dir);
  const panes = resolvePanes(dir);
  const tmuxReady = hasTmux();
  const sessionRunning = tmuxReady && sessionExists(sessionName);
  const appRunning = runQuiet("pgrep -x Lattices >/dev/null 2>&1 && echo yes") === "yes";

  console.log(`lattices — let's get you situated

Current directory:
  ${dir}

Workspace:
  session   ${sessionName}
  config    ${config ? ".lattices.json" : "none yet"}
  panes     ${panes.map((p) => p.name || "pane").join(", ")}
  tmux      ${tmuxReady ? (sessionRunning ? "running" : "ready") : "missing"}
  app       ${appRunning ? "running" : "not running"}

Common commands:
  lattices start        Start or reattach this directory's tmux workspace
  lattices init         Create a .lattices.json for this project
  lattices app          Launch the menu bar app
  lattices ls           List active sessions
  lattices help         Show the full command reference
`);

  if (!tmuxReady) {
    console.log("tmux is not installed. Run: brew install tmux");
  }
}

function initConfig(): void {
  const dir = process.cwd();
  const configPath = resolve(dir, ".lattices.json");

  if (existsSync(configPath)) {
    console.log(".lattices.json already exists.");
    return;
  }

  const panes = defaultPanes(dir);
  const config = {
    ensure: true,
    panes,
  };

  writeFileSync(configPath, JSON.stringify(config, null, 2) + "\n");
  console.log("Created .lattices.json");
  console.log(JSON.stringify(config, null, 2));
}

function listSessions(): void {
  const out = runQuiet(
    "tmux list-sessions -F '#{session_name}  (#{session_windows} windows, created #{session_created_string})'"
  );
  if (!out) {
    console.log("No active tmux sessions.");
    return;
  }

  // Annotate sessions that belong to tab groups
  const ws = readWorkspaceConfig();
  const sessionGroupMap = new Map<string, { group: string; tab: string }>();
  if (ws?.groups) {
    for (const g of ws.groups) {
      for (const tab of g.tabs || []) {
        const tabSession = toSessionName(resolve(tab.path));
        sessionGroupMap.set(tabSession, {
          group: g.label || g.id,
          tab: tab.label || basename(tab.path),
        });
      }
    }
  }

  const lines = out.split("\n").map((line: string) => {
    const sessionName = line.split("  ")[0];
    const info = sessionGroupMap.get(sessionName);
    return info
      ? `${line}  \x1b[36m[${info.group}: ${info.tab}]\x1b[0m`
      : line;
  });

  console.log("Sessions:\n");
  console.log(lines.join("\n"));
}

function killSession(name?: string): void {
  if (!name) name = toSessionName(process.cwd());
  if (!sessionExists(name)) {
    console.log(`No session "${name}".`);
    return;
  }
  run(`tmux kill-session -t "${name}"`);
  console.log(`Killed "${name}".`);
}

// ── Window tiling ────────────────────────────────────────────────────

interface ScreenBounds {
  x: number;
  y: number;
  w: number;
  h: number;
}

function getScreenBounds(): ScreenBounds {
  // Get the visible area (excludes menu bar and dock) in AppleScript coordinates (top-left origin)
  const script = `
    tell application "Finder"
      set db to bounds of window of desktop
    end tell
    -- db = {left, top, right, bottom} of usable desktop
    return (item 1 of db) & "," & (item 2 of db) & "," & (item 3 of db) & "," & (item 4 of db)`;
  const out = runQuiet(`osascript -e '${esc(script)}'`);
  if (!out) return { x: 0, y: 25, w: 1920, h: 1055 };
  const [x, y, right, bottom] = out.split(",").map(s => parseInt(s.trim()));
  return { x, y, w: right - x, h: bottom - y };
}

// Presets return AppleScript bounds: [left, top, right, bottom] within the visible area
const tilePresets: Record<string, (s: ScreenBounds) => number[]> = {
  "left":         (s) => [s.x, s.y, s.x + s.w / 2, s.y + s.h],
  "left-half":    (s) => [s.x, s.y, s.x + s.w / 2, s.y + s.h],
  "right":        (s) => [s.x + s.w / 2, s.y, s.x + s.w, s.y + s.h],
  "right-half":   (s) => [s.x + s.w / 2, s.y, s.x + s.w, s.y + s.h],
  "top":          (s) => [s.x, s.y, s.x + s.w, s.y + s.h / 2],
  "top-half":     (s) => [s.x, s.y, s.x + s.w, s.y + s.h / 2],
  "bottom":       (s) => [s.x, s.y + s.h / 2, s.x + s.w, s.y + s.h],
  "bottom-half":  (s) => [s.x, s.y + s.h / 2, s.x + s.w, s.y + s.h],
  "top-left":     (s) => [s.x, s.y, s.x + s.w / 2, s.y + s.h / 2],
  "top-right":    (s) => [s.x + s.w / 2, s.y, s.x + s.w, s.y + s.h / 2],
  "bottom-left":  (s) => [s.x, s.y + s.h / 2, s.x + s.w / 2, s.y + s.h],
  "bottom-right": (s) => [s.x + s.w / 2, s.y + s.h / 2, s.x + s.w, s.y + s.h],
  "maximize":     (s) => [s.x, s.y, s.x + s.w, s.y + s.h],
  "max":          (s) => [s.x, s.y, s.x + s.w, s.y + s.h],
  "center":       (s) => {
    const mw = Math.round(s.w * 0.7);
    const mh = Math.round(s.h * 0.8);
    const mx = s.x + Math.round((s.w - mw) / 2);
    const my = s.y + Math.round((s.h - mh) / 2);
    return [mx, my, mx + mw, my + mh];
  },
  "left-third":   (s) => [s.x, s.y, s.x + Math.round(s.w * 0.333), s.y + s.h],
  "center-third": (s) => [s.x + Math.round(s.w * 0.333), s.y, s.x + Math.round(s.w * 0.667), s.y + s.h],
  "right-third":  (s) => [s.x + Math.round(s.w * 0.667), s.y, s.x + s.w, s.y + s.h],
};

type SpaceOptimizeScope = "visible" | "active-app" | "app";

interface SpaceOptimizeRequest {
  scope: SpaceOptimizeScope;
  app?: string;
  region?: string;
}

function isPlacementToken(value?: string): boolean {
  if (!value) return false;
  const normalized = value.toLowerCase();
  return normalized in tilePresets || /^grid:\d+x\d+:\d+,\d+$/i.test(normalized);
}

function parseSpaceOptimizeArgs(rawArgs: string[], defaultScope: SpaceOptimizeScope): SpaceOptimizeRequest {
  const parts = rawArgs.filter(Boolean);
  if (!parts.length) return { scope: defaultScope };

  const last = parts[parts.length - 1];
  const region = isPlacementToken(last) ? last : undefined;
  const appParts = region ? parts.slice(0, -1) : parts;
  const app = appParts.length ? appParts.join(" ") : undefined;

  if (app) return { scope: "app", app, region };
  return { scope: defaultScope, region };
}

function formatOptimizeTarget(request: SpaceOptimizeRequest): string {
  if (request.app) return `"${request.app}"`;
  return request.scope === "active-app" ? "the frontmost app" : "all visible windows";
}

async function optimizeWindowsCommand(
  request: SpaceOptimizeRequest,
  successVerb: string
): Promise<void> {
  try {
    const { daemonCall } = await getDaemonClient();
    const params: Record<string, unknown> = {
      scope: request.scope,
      strategy: "balanced",
    };
    if (request.app) params.app = request.app;
    if (request.region) params.region = request.region;

    const result = await daemonCall("space.optimize", params) as any;
    const count = result?.windowCount ?? 0;
    const target = formatOptimizeTarget(request);
    const regionSuffix = request.region ? ` in the ${request.region} region` : "";

    if (count === 0) {
      console.log(`No eligible windows found for ${target}${regionSuffix}.`);
      return;
    }

    console.log(
      `${successVerb} ${count} window${count === 1 ? "" : "s"} for ${target}${regionSuffix}.`
    );
  } catch {
    console.log("Daemon not running. Start with: lattices app");
  }
}

function tileWindow(position: string): void {
  const preset = tilePresets[position];
  if (!preset) {
    console.log(`Unknown position: ${position}`);
    console.log(`Available: ${Object.keys(tilePresets).filter(k => !k.includes("-half") && k !== "max").join(", ")}`);
    return;
  }
  const screen = getScreenBounds();
  const [x1, y1, x2, y2] = preset(screen).map(Math.round);
  const script = `
    tell application "System Events"
      set frontApp to name of first application process whose frontmost is true
    end tell
    tell application frontApp
      set bounds of front window to {${x1}, ${y1}, ${x2}, ${y2}}
    end tell`;
  runQuiet(`osascript -e '${esc(script)}'`);
  console.log(`Tiled → ${position}`);
}

function createOrAttach(): void {
  const dir = process.cwd();
  const name = toSessionName(dir);

  if (sessionExists(name)) {
    console.log(`Reattaching to "${name}"...`);
    const config = readConfig(dir);
    if (config?.ensure) {
      restoreCommands(name, dir, "ensure");
    } else if (config?.prefill) {
      restoreCommands(name, dir, "prefill");
    }
    attach(name);
    return;
  }

  console.log(`Creating "${name}"...`);
  createSession(dir);
  attach(name);
}

function attach(name: string): void {
  if (isInsideTmux()) {
    execSync(`tmux switch-client -t "${name}"`, { stdio: "inherit" });
  } else {
    execSync(`tmux attach -t "${name}"`, { stdio: "inherit" });
  }
}

// ── Status / Inventory ───────────────────────────────────────────────

function statusInventory(): void {
  // Query all tmux sessions
  const sessionsRaw = runQuiet(
    'tmux list-sessions -F "#{session_name}\t#{session_windows}\t#{session_attached}"'
  );
  if (!sessionsRaw) {
    console.log("No active tmux sessions.");
    return;
  }

  // Query all panes
  const panesRaw = runQuiet(
    'tmux list-panes -a -F "#{session_name}\t#{pane_title}\t#{pane_current_command}"'
  );

  // Parse panes grouped by session
  const panesBySession = new Map<string, { title: string; cmd: string }[]>();
  if (panesRaw) {
    for (const line of panesRaw.split("\n").filter(Boolean)) {
      const [sess, title, cmd] = line.split("\t");
      if (!panesBySession.has(sess)) panesBySession.set(sess, []);
      panesBySession.get(sess)!.push({ title, cmd });
    }
  }

  // Build managed session name set
  const managed = new Map<string, string>(); // name -> label

  // From workspace groups
  const ws = readWorkspaceConfig();
  if (ws?.groups) {
    for (const g of ws.groups) {
      for (const tab of g.tabs || []) {
        const name = toSessionName(resolve(tab.path));
        const label = `${g.label || g.id}: ${tab.label || basename(tab.path)}`;
        managed.set(name, label);
      }
    }
  }

  // From scanning .lattices.json files
  const scanRoot =
    process.env.LATTICE_SCAN_ROOT ||
    resolve(homedir(), "dev");
  const findResult = runQuiet(
    `find "${scanRoot}" -name .lattices.json -maxdepth 3 -not -path "*/.git/*" -not -path "*/node_modules/*" 2>/dev/null`
  );
  if (findResult) {
    for (const configPath of findResult.split("\n").filter(Boolean)) {
      const dir = resolve(configPath, "..");
      const name = toSessionName(dir);
      if (!managed.has(name)) {
        managed.set(name, basename(dir));
      }
    }
  }

  // Parse sessions and classify
  const sessions = sessionsRaw.split("\n").filter(Boolean).map((line: string) => {
    const [name, windows, attached] = line.split("\t");
    return { name, windows: parseInt(windows) || 1, attached: attached !== "0" };
  });

  const managedSessions = sessions.filter((s) => managed.has(s.name));
  const orphanSessions = sessions.filter((s) => !managed.has(s.name));

  // Print managed
  if (managedSessions.length > 0) {
    console.log(`\x1b[32m●\x1b[0m Managed Sessions (${managedSessions.length})\n`);
    for (const s of managedSessions) {
      const label = managed.get(s.name);
      const attachTag = s.attached ? "  \x1b[33m[attached]\x1b[0m" : "";
      console.log(`  \x1b[1m${s.name}\x1b[0m  (${s.windows} window${s.windows === 1 ? "" : "s"})${attachTag}  \x1b[36m[${label}]\x1b[0m`);
      const panes = panesBySession.get(s.name) || [];
      for (const p of panes) {
        const name = p.title || "pane";
        console.log(`    ${name}: ${p.cmd}`);
      }
      console.log();
    }
  } else {
    console.log("\x1b[90m○\x1b[0m No managed sessions running.\n");
  }

  // Print orphans
  if (orphanSessions.length > 0) {
    console.log(`\x1b[33m○\x1b[0m Unmanaged Sessions (${orphanSessions.length})\n`);
    for (const s of orphanSessions) {
      const attachTag = s.attached ? "  \x1b[33m[attached]\x1b[0m" : "";
      console.log(`  \x1b[1m${s.name}\x1b[0m  (${s.windows} window${s.windows === 1 ? "" : "s"})${attachTag}`);
      const panes = panesBySession.get(s.name) || [];
      for (const p of panes) {
        const name = p.title || "pane";
        console.log(`    ${name}: ${p.cmd}`);
      }
      console.log();
    }
  } else {
    console.log("\x1b[90m○\x1b[0m No unmanaged sessions.\n");
  }
}

// ── Main ─────────────────────────────────────────────────────────────

requireTmux(command);

switch (command) {
  case undefined:
    printHome();
    break;
  case "start":
  case "tmux":
    createOrAttach();
    break;
  case "init":
    initConfig();
    break;
  case "ls":
  case "list":
    // Try daemon first, fall back to direct tmux
    if (!(await daemonLsCommand())) {
      listSessions();
    }
    break;
  case "kill":
  case "rm":
    killSession(args[1]);
    break;
  case "sync":
  case "reconcile":
    syncSession();
    break;
  case "restart":
  case "respawn":
    restartPane(args[1]);
    break;
  case "group":
    groupCommand(args[1]);
    break;
  case "groups":
    listGroups();
    break;
  case "tab":
    tabCommand(args[1], args[2]);
    break;
  case "status":
  case "inventory":
    // Try daemon first, fall back to direct tmux
    if (!(await daemonStatusInventory())) {
      statusInventory();
    }
    break;
  case "distribute":
    await distributeCommand(args.slice(1));
    break;
  case "tile":
  case "t":
    if (args[1] === "family" || args[1] === "app") {
      await tileFamilyCommand(args.slice(2));
    } else if (args[1] === "all") {
      await distributeCommand(args.slice(2));
    } else if (args[1]) {
      tileWindow(args[1]);
    } else {
      console.log("Usage:");
      console.log("  lattices tile <position>");
      console.log("  lattices tile family [app-name] [region]");
      console.log("  lattices tile all [app-name] [region]\n");
      console.log("Examples:");
      console.log("  lattices tile left");
      console.log("  lattices tile family");
      console.log("  lattices tile family right");
      console.log("  lattices tile family iTerm2");
      console.log("  lattices tile all Google Chrome left\n");
      console.log("Positions: left, right, top, bottom, top-left, top-right,");
      console.log("           bottom-left, bottom-right, maximize, center,");
      console.log("           left-third, center-third, right-third");
    }
    break;
  case "windows":
    await windowsCommand(args[1] === "--json");
    break;
  case "window":
    if (args[1] === "assign") {
      await windowAssignCommand(args[2], args[3]);
    } else if (args[1] === "map") {
      await windowLayerMapCommand(args[2] === "--json");
    } else {
      console.log("Usage:");
      console.log("  lattices window assign <wid> <layer-id>   Tag a window to a layer");
      console.log("  lattices window map [--json]               Show all layer tags");
    }
    break;
  case "search":
  case "s":
    await searchCommand(args[1], new Set(args.slice(2)));
    break;
  case "focus":
    await focusCommand(args[1]);
    break;
  case "place":
    await placeCommand(args[1], args[2]);
    break;
  case "sessions":
    await sessionsCommand(args[1] === "--json");
    break;
  case "voice":
    await voiceCommand(args[1], ...args.slice(2));
    break;
  case "actor":
  case "actors":
    await actorCommand(args[1], ...args.slice(2));
    break;
  case "hud":
  case "huds":
    await hudCommand(args[1], ...args.slice(2));
    break;
  case "assistant":
    await assistantCommand(args[1], ...args.slice(2));
    break;
  case "call":
    await callCommand(args[1], ...args.slice(2));
    break;
  case "layer":
  case "layers":
    await layerCommand(args[1], ...args.slice(2));
    break;
  case "diag":
  case "diagnostics":
  case "log":
  case "logs":
  case "activity":
    await diagCommand(args[1]);
    break;
  case "scan":
  case "ocr":
    await scanCommand(args[1], ...args.slice(2));
    break;
  case "mouse":
    await mouseCommand(args[1]);
    break;
  case "daemon":
    if (args[1] === "status") {
      await daemonStatusCommand();
    } else {
      console.log("Usage: lattices daemon status");
    }
    break;
  case "dev":
    await devCommand(args[1], ...args.slice(2));
    break;
  case "app": {
    const { execFileSync } = await import("node:child_process");
    const dir = process.cwd();
    const first = args[1];
    const appSubcommand = first && !first.startsWith("-") ? first : "launch";
    const appFlags = first && !first.startsWith("-") ? args.slice(2) : args.slice(1);
    const devAppCommands = new Set(["launch", "start", "build", "restart", "quit", "stop"]);

    if (detectProjectType(dir) === "lattices-app" && devAppCommands.has(appSubcommand)) {
      console.log("Using local dev app bundle so macOS permissions stay attached across rebuilds.");
      await forwardToLatticesDevHelper(dir, appSubcommand, appFlags);
      break;
    }

    // Forward release/package app commands to lattices-app script.
    const appScript = resolve(import.meta.dir, "lattices-app.ts");
    try {
      execFileSync("bun", [appScript, ...args.slice(1)], { stdio: "inherit" });
    } catch { /* exit code forwarded */ }
    break;
  }
  case "-h":
  case "--help":
  case "help":
    printUsage();
    break;
  default:
    console.log(`Unknown command: ${command}`);
    console.log("Run `lattices help` for the full command reference.");
}
