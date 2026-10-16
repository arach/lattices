import { createHash } from "node:crypto";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { boundedWait, checkDeadline, deadlineSleep, type CDPSession } from "./transport.ts";

type Bounds = { x: number; y: number; width: number; height: number };
type Status = { active: boolean; subject?: { pid?: number }; layer?: { bounds: Bounds; paused?: boolean; windows: unknown[] } };
type Director = {
  open(input: Record<string, unknown>): Promise<Status>;
  status(): Promise<Status>;
  actRefusal(): Promise<string | undefined>;
  displayStatus(): Promise<{ active: boolean; state: string }>;
};
type Runtime = {
  requireSafety: () => Promise<void>;
  director: Director;
  openWindow: (port: number, bounds: Bounds) => Promise<string>;
  browserConfig: () => { app: string; bundleId: string };
  spacesBinding: (bundleId: string) => Promise<string | undefined>;
};

type BrowserSafety = {
  runtimeParity?: { state?: string };
  native?: { privateLayer?: string; manifest?: { features?: { persistentAgentDisplay?: boolean; namedWorkspaces?: boolean } } | null };
  safety?: { privateLayer?: { blocked?: boolean; reason?: string } };
  acceptance?: { privateLayer?: { state?: string; reasons?: string[] } };
};

/** Consume Action's evidence verification; prepared display state alone is not acceptance. */
export function requireBrowserSafety(capabilities: BrowserSafety): void {
  const safety = capabilities.safety?.privateLayer;
  if (safety?.blocked !== false) {
    throw new Error(`Action private-layer safety is blocked or unverified: ${safety?.reason ?? "missing safety evidence"}. Refusing background browser work.`);
  }
  if (capabilities.runtimeParity?.state !== "matched-source-digest"
    || capabilities.native?.privateLayer !== "declared-by-build"
    || capabilities.native.manifest?.features?.persistentAgentDisplay !== true
    || capabilities.native.manifest.features.namedWorkspaces !== true) {
    throw new Error("Action browser requires a matched app/runtime with persistent named workspaces. Resolve the selected Action app's provenance before background browser work.");
  }
  const acceptance = capabilities.acceptance?.privateLayer;
  if (acceptance?.state !== "accepted") {
    throw new Error(`Action private-layer acceptance is ${acceptance?.state ?? "unverified"}: ${acceptance?.reasons?.join(" ") ?? "matching host evidence is required"}. Refusing background browser work.`);
  }
}

/** Capability discovery hashes the bundle and invokes a synchronous native context probe.
 * Keep that read-only work outside the MCP event loop so its deadline can cancel it.
 */
export async function readBrowserCapabilities(actionRoot: string, app: string, previous?: BrowserSafety): Promise<BrowserSafety> {
  checkDeadline();
  const moduleURL = pathToFileURL(join(actionRoot, "packages/runtime/src/capabilities.ts")).href;
  const script = `
    const { actionCapabilities, refreshActionCapabilities } = await import(${JSON.stringify(moduleURL)});
    const previous = ${JSON.stringify(previous ?? null)};
    const value = await (previous ? refreshActionCapabilities(previous) : actionCapabilities(${JSON.stringify(actionRoot)}, {
      bundlePath: ${JSON.stringify(app)}, nativeHostPath: ${JSON.stringify(resolve(actionRoot, "native/engine/scripts/run-app-host.sh"))}
    }));
    process.stdout.write(JSON.stringify(value));
  `;
  const child = Bun.spawn([process.execPath, "-e", script], { stdout: "pipe", stderr: "pipe" });
  return boundedWait((async () => {
    const [stdout, stderr, code] = await Promise.all([new Response(child.stdout).text(), new Response(child.stderr).text(), child.exited]);
    if (code !== 0) throw new Error(`Action browser safety discovery failed: ${stderr.trim() || `exit ${code}`}`);
    return JSON.parse(stdout) as BrowserSafety;
  })(), "Verify Action browser safety", () => child.kill());
}

export function windowIsOnLayer(window: { left: number; top: number; width: number; height: number }, layer: Bounds): boolean {
  return window.width > 0 && window.height > 0
    && window.left >= layer.x && window.top >= layer.y
    && window.left + window.width <= layer.x + layer.width
    && window.top + window.height <= layer.y + layer.height;
}

export function assertUnpinnedBrowser(bundleId: string, binding: string | undefined): void {
  if (binding) throw new Error(`${bundleId} is assigned to a Desktop and cannot stay on the Action virtual display. Set Dock > Options > Assign To: None, or install/select Action's Chrome for Testing. No browser was launched.`);
}

export function browserWorkspace(profileDir: string, override?: string): string {
  const workspace = override ?? `browser-${createHash("sha256").update(resolve(profileDir)).digest("hex").slice(0, 12)}`;
  if (!/^[a-z][a-z0-9-]{0,31}$/.test(workspace)) {
    throw new Error("ACTION_BROWSER_WORKSPACE must be 1–32 lowercase letters, digits, or hyphens, starting with a letter.");
  }
  return workspace;
}

/** Read-only preflight: never provision a monitor or replace another task. */
export async function requireBrowserWorkspace(director: Pick<Director, "displayStatus" | "status">, workspace: string): Promise<void> {
  const display = await director.displayStatus();
  if (!display.active || display.state !== "ready") {
    throw new Error(`Action browser workspace ${workspace} has no ready display (${display.state}). During an explicit display setup interval, run: lats action layer prepare --workspace ${workspace}. No browser was launched.`);
  }
  if ((await director.status()).active) {
    throw new Error(`Action workspace ${workspace} already has an active task. Close it explicitly or select another prepared ACTION_BROWSER_WORKSPACE. No browser was launched.`);
  }
}

/** Reuse Action's layer director and browser window creation, not a second display implementation.
 * Use a named workspace in the same registry as explicit Action preparation.
 * Chrome owns the task's lifetime; the prepared monitor has a separate owner.
 */
export class HeadedBrowserLayer {
  private runtime?: Runtime;
  private chromePid?: number;
  readonly workspace: string;
  constructor(private actionRoot: string, private profileDir: string) {
    this.workspace = browserWorkspace(profileDir, process.env.ACTION_BROWSER_WORKSPACE);
  }

  requiredFor(pid: number | undefined): boolean {
    if (!pid) return false;
    try { return Number(readFileSync(join(this.profileDir, ".action-layer-pid"), "utf8")) === pid; }
    catch { return false; }
  }

  async prepare(): Promise<Runtime> {
    if (this.runtime) return this.runtime;
    const runtimeRoot = join(this.actionRoot, "packages/runtime/src");
    const app = process.env.ACTION_BROWSER_ACTION_APP ?? join(this.actionRoot, "native/dist/Action.app");
    if (!existsSync(join(runtimeRoot, "agent-layer.ts")) || !existsSync(join(app, "Contents/MacOS/Action"))) {
      throw new Error("Background browsing requires Action's agent-layer runtime and signed Action.app. Set ACTION_ROOT to the Action product checkout (and ACTION_BROWSER_ACTION_APP if installed elsewhere). No headless or on-screen fallback is used; background:false explicitly opts into a visible browser.");
    }
    const { AgentLayerDirector } = await import(pathToFileURL(join(runtimeRoot, "agent-layer.ts")).href);
    const { openBrowserWindow, layerBrowserConfig, spacesBinding } = await import(pathToFileURL(join(runtimeRoot, "agent-layer-browser.ts")).href);
    // Verify the exact app that runHost launches, including custom app paths.
    // Discovery only reads provenance and invokes the read-only isolation-context command.
    let capabilities: BrowserSafety | undefined;
    const requireSafety = async () => {
      capabilities = await readBrowserCapabilities(this.actionRoot, app, capabilities);
      requireBrowserSafety(capabilities);
      checkDeadline();
    };
    const director: Director = new AgentLayerDirector("unused", {
      workspace: this.workspace,
      runHost: async (args: string[]) => {
        checkDeadline();
        // Run the installed signed app via Launch Services, never auto-build/reinstall it.
        // Chrome, not this MCP caller, owns the task's lifetime.
        const owners = args.indexOf("--owner-pids");
        if (owners >= 0) args.splice(owners, 2);
        args.push("--owner-pids", String(this.chromePid), "--idle-timeout", "0");
        const dir = await mkdtemp(join(tmpdir(), "action-browser-layer-"));
        const reply = join(dir, "reply.json");
        try {
          const launch = Bun.spawn(["/usr/bin/open", "-n", "-g", app, "--args", ...args, "--reply-file", reply], { stdout: "ignore", stderr: "pipe" });
          if (await boundedWait(launch.exited, "Launch Action layer", () => launch.kill()) !== 0) {
            throw new Error(await new Response(launch.stderr).text());
          }
          for (let attempt = 0; attempt < 100; attempt++) {
            checkDeadline();
            const stdout = await readFile(reply, "utf8").catch(() => "");
            if (stdout.trim()) return { stdout };
            await deadlineSleep(50);
          }
          throw new Error("Action layer did not reply. Check Action's Accessibility permission and installed version.");
        } finally { await rm(dir, { recursive: true, force: true }); }
      },
    });
    return this.runtime = { director, requireSafety, openWindow: openBrowserWindow, browserConfig: layerBrowserConfig, spacesBinding };
  }

  async launchApp(override?: string): Promise<string> {
    const runtime = await this.prepare();
    await runtime.requireSafety();
    await requireBrowserWorkspace(runtime.director, this.workspace);
    const app = override ?? runtime.browserConfig().app;
    // Ask Launch Services for the actual bundle identity without launching it.
    const identity = Bun.spawn(["/usr/bin/osascript", "-e", `id of application ${JSON.stringify(app)}`], { stdout: "pipe", stderr: "pipe" });
    if (await boundedWait(identity.exited, "Resolve Chrome identity", () => identity.kill()) !== 0) {
      throw new Error(`Could not resolve Chrome application: ${app}`);
    }
    const bundleId = (await new Response(identity.stdout).text()).trim();
    assertUnpinnedBrowser(bundleId, await runtime.spacesBinding(bundleId));
    return app;
  }

  async status(pid: number): Promise<Status> {
    const { director, requireSafety } = await this.prepare();
    await requireSafety();
    const refusal = await director.actRefusal();
    if (refusal) throw new Error(refusal);
    const status = await director.status();
    if (!status.active || !status.layer || status.subject?.pid !== pid) {
      throw new Error("Chrome is not on its Action virtual display. Close this Action browser and reopen it; refusing to browse on the operator's displays.");
    }
    return status;
  }

  async open(pid: number): Promise<void> {
    const { director, requireSafety } = await this.prepare();
    await requireSafety();
    this.chromePid = pid;
    // Outlive the state file: a closed/lost layer must not silently permit on-screen acts.
    writeFileSync(join(this.profileDir, ".action-layer-pid"), String(pid));
    const existing = await director.status();
    if (existing.active) {
      if (existing.subject?.pid === pid) { await this.status(pid); return; }
      throw new Error(`Action workspace ${this.workspace} has a different active task; refusing to replace it.`);
    }
    checkDeadline();
    await director.open({ pid, windowless: true, pip: false, owner: "detached" });
    checkDeadline();
    await this.status(pid);
    // A hidden app does not draw even on the layer. It still has no windows here.
    const show = Bun.spawn(["/usr/bin/osascript", "-e", `tell application "System Events" to set visible of (first process whose unix id is ${pid}) to true`], { stdout: "ignore", stderr: "pipe" });
    if (await boundedWait(show.exited, "Unhide layer browser", () => show.kill()) !== 0) {
      throw new Error("Could not unhide Chrome on its virtual display. Check Automation permission for System Events.");
    }
  }

  async createWindow(pid: number, port: number): Promise<string> {
    const status = await this.status(pid);
    checkDeadline();
    return boundedWait((await this.prepare()).openWindow(port, status.layer!.bounds), "Create headed browser window");
  }

  async verify(pid: number, session: Pick<CDPSession, "call">): Promise<void> {
    const status = await this.status(pid);
    const { bounds } = await session.call("Browser.getWindowForTarget");
    if (!windowIsOnLayer(bounds as Parameters<typeof windowIsOnLayer>[0], status.layer!.bounds)) {
      throw new Error("Chrome window is outside its Action virtual display; refusing to interact on the operator's displays.");
    }
  }

}
