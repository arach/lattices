#!/usr/bin/env bun

import { createHash } from "node:crypto";
import { execSync } from "node:child_process";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { basename, resolve } from "node:path";
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
  "init", "ls", "list", "kill", "rm", "sync", "reconcile",
  "restart", "respawn", "group", "groups", "tab", "status",
  "inventory", "distribute", "sessions",
]);

function requireTmux(command: string | undefined): void {
  if (hasTmux()) return;

  const isImplicitCreate = command && !tmuxRequiredCommands.has(command)
    && !["search", "s", "focus", "place", "tile", "t", "windows", "window",
         "voice", "call", "layer", "layers", "diag", "diagnostics", "scan",
         "ocr", "daemon", "dev", "app", "mouse", "help", "-h", "--help"].includes(command);

  if (command && !tmuxRequiredCommands.has(command) && !isImplicitCreate) return;

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
  if (existsSync(resolve(dir, "pnpm-lock.yaml"))) return "pnpm";
  if (existsSync(resolve(dir, "bun.lockb")) || existsSync(resolve(dir, "bun.lock")))
    return "bun";
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
  if (existsSync(resolve(dir, "app/Package.swift")) && existsSync(resolve(dir, "bin/lattices-app.ts")))
    return "lattices-app";
  if (existsSync(resolve(dir, "Package.swift"))) return "swift";
  if (existsSync(resolve(dir, "Cargo.toml"))) return "rust";
  if (existsSync(resolve(dir, "go.mod"))) return "go";
  if (existsSync(resolve(dir, "package.json"))) return "node";
  if (existsSync(resolve(dir, "Makefile"))) return "make";
  return null;
}

async function devCommand(sub?: string, ...flags: string[]): Promise<void> {
  const dir = process.cwd();
  const type = detectProjectType(dir);

  // Helper to forward to lattices-app.ts
  async function forwardToAppScript(cmd: string, extraFlags: string[] = []): Promise<void> {
    const appScript = resolve(import.meta.dir, "lattices-app.ts");
    const { execFileSync } = await import("node:child_process");
    try {
      execFileSync("bun", [appScript, cmd, ...extraFlags], { stdio: "inherit" });
    } catch { /* exit code forwarded */ }
  }

  if (!sub) {
    // bare `lattices dev` — run dev server
    if (!type) {
      console.log("No recognized project in current directory.");
      return;
    }
    console.log(`Detected: ${type} project`);
    if (type === "lattices-app") {
      await forwardToAppScript("restart", flags);
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

  if (sub === "build") {
    if (!type) {
      console.log("No recognized project in current directory.");
      return;
    }
    if (type === "lattices-app") {
      await forwardToAppScript("build");
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
      await forwardToAppScript("restart", flags);
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
      { name: "claude", cmd: "claude", size: 60 },
      { name: "server", cmd: devCmd },
    ];
  }
  // No dev server detected → single pane
  return [{ name: "claude", cmd: "claude" }];
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
    // Default: first pane (claude)
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

async function distributeCommand(): Promise<void> {
  try {
    const { daemonCall } = await getDaemonClient();
    await daemonCall("space.optimize", { scope: "visible", strategy: "balanced" });
    console.log("Distributed visible windows into grid");
  } catch {
    console.log("Daemon not running. Start with: lattices app");
  }
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
  console.log(`lattices — Claude Code + dev server in tmux

Usage:
  lattices                    Create session (or reattach) for current project
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
  lattices distribute         Smart-grid all visible windows (daemon required)
  lattices layer [name|index]  List layers or switch by name/index (daemon required)
  lattices layer create <name> [wid:N ...] [--json '<specs>']  Create a session layer
  lattices layer snap [name]   Snapshot visible windows into a session layer
  lattices layer session [n]   List or switch session layers (runtime, no restart)
  lattices layer delete <name> Delete a session layer
  lattices layer clear         Clear all session layers
  lattices voice status       Voice provider status
  lattices voice simulate <t> Parse and execute a voice command
  lattices voice intents      List all available intents
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
  lattices dev type           Print detected project type
  lattices mouse              Find mouse — sonar pulse at cursor position
  lattices mouse summon       Summon mouse to screen center
  lattices daemon status      Show daemon status
  lattices diag [limit]       Show diagnostic log entries
  lattices app                Launch the menu bar companion app
  lattices app build          Rebuild the menu bar app
  lattices app restart        Rebuild and relaunch the menu bar app
  lattices app quit           Stop the menu bar app
  lattices help               Show this help

Config (.lattices.json):
  Place in your project root to customize the layout:

  {
    "ensure": true,
    "panes": [
      { "name": "claude", "cmd": "claude", "size": 60 },
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
                    Examples:  lattices restart         (restarts "claude")
                               lattices restart server  (restarts "server" by name)
                               lattices restart 1       (restarts pane at index 1)

Layouts:
  1 pane   →  single full-width (default when no dev server detected)
  2 panes  →  side-by-side split
  3+ panes →  main-vertical (first pane left, rest stacked right)

  ┌────────────────────┐    ┌──────────┬─────────┐    ┌──────────┬─────────┐
  │      claude         │    │  claude   │ server  │    │  claude   │ server  │
  │                     │    │  (60%)   │ (40%)   │    │  (60%)   ├─────────┤
  └────────────────────┘    └──────────┴─────────┘    │          │ tests   │
                                                       └──────────┴─────────┘
`);
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
    await distributeCommand();
    break;
  case "tile":
  case "t":
    if (args[1]) {
      tileWindow(args[1]);
    } else {
      console.log("Usage: lattices tile <position>\n");
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
  case "call":
    await callCommand(args[1], ...args.slice(2));
    break;
  case "layer":
  case "layers":
    await layerCommand(args[1], ...args.slice(2));
    break;
  case "diag":
  case "diagnostics":
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
    // Forward to lattices-app script
    const { execFileSync } = await import("node:child_process");
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
    createOrAttach();
}
