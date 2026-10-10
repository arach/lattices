import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { boundedWait, checkDeadline, deadlineSleep, type CDPSession } from "./transport.ts";

type Bounds = { x: number; y: number; width: number; height: number };
type Status = { active: boolean; subject?: { pid?: number }; layer?: { bounds: Bounds; paused?: boolean; windows: unknown[] } };
type Director = {
  open(input: Record<string, unknown>): Promise<Status>;
  status(): Promise<Status>;
  actRefusal(): Promise<string | undefined>;
  close(): Promise<Status>;

};
type Runtime = {
  director: Director;
  openWindow: (port: number, bounds: Bounds) => Promise<string>;
  browserConfig: () => { app: string; bundleId: string };
  spacesBinding: (bundleId: string) => Promise<string | undefined>;
};

export function windowIsOnLayer(window: { left: number; top: number; width: number; height: number }, layer: Bounds): boolean {
  return window.width > 0 && window.height > 0
    && window.left >= layer.x && window.top >= layer.y
    && window.left + window.width <= layer.x + layer.width
    && window.top + window.height <= layer.y + layer.height;
}

export function assertUnpinnedBrowser(bundleId: string, binding: string | undefined): void {
  if (binding) throw new Error(`${bundleId} is assigned to a Desktop and cannot stay on the Action virtual display. Set Dock > Options > Assign To: None, or install/select Action's Chrome for Testing. No browser was launched.`);
}

/** Reuse Action's layer director and browser window creation, not a second display implementation.
 * A profile-local state root avoids replacing an operator's unrelated Action layer.
 * The native layer watches Chrome's PID, so shared MCP owners can exit independently.
 */
export class HeadedBrowserLayer {
  private runtime?: Runtime;
  private chromePid?: number;
  constructor(private actionRoot: string, private profileDir: string) {}

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
    const director: Director = new AgentLayerDirector("unused", {
      root: join(this.profileDir, ".agent-layer"),
      runHost: async (args: string[]) => {
        checkDeadline();
        // Run the installed signed app via Launch Services, never auto-build/reinstall it.
        // Chrome, not this MCP caller, owns the display's lifetime.
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
    return this.runtime = { director, openWindow: openBrowserWindow, browserConfig: layerBrowserConfig, spacesBinding };
  }

  async launchApp(override?: string): Promise<string> {
    const runtime = await this.prepare();
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
    const { director } = await this.prepare();
    const refusal = await director.actRefusal();
    if (refusal) throw new Error(refusal);
    const status = await director.status();
    if (!status.active || !status.layer || status.subject?.pid !== pid) {
      throw new Error("Chrome is not on its Action virtual display. Close this Action browser and reopen it; refusing to browse on the operator's displays.");
    }
    return status;
  }

  async open(pid: number): Promise<void> {
    this.chromePid = pid;
    // Outlive the state file: a closed/lost layer must not silently permit on-screen acts.
    writeFileSync(join(this.profileDir, ".action-layer-pid"), String(pid));
    const { director } = await this.prepare();
    const existing = await director.status();
    if (existing.active) {
      if (existing.subject?.pid === pid) { await this.status(pid); return; }
      const previous = existing.subject?.pid;
      let alive = true;
      if (previous) { try { process.kill(previous, 0); } catch { alive = false; } }
      if (alive) throw new Error("This profile's Action layer has a different live owner; refusing to replace it.");
      // Chrome exited but its layer's owner watcher has not ticked yet.
      await director.close();
    }
    checkDeadline();
    await director.open({ pid, windowless: true, width: 1600, height: 1200, pip: false, owner: "detached" });
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
