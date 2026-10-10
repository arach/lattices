import { spawn, type ChildProcess } from "node:child_process";
import { chmodSync, mkdtempSync, rmSync } from "node:fs";
import { createServer, type Server, type Socket } from "node:net";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import type { VisitorOverlay, VisitorState } from "./visit.ts";

const CONFIG = fileURLToPath(new URL("../../visitor/", import.meta.url));
export const OVERLAY_IDLE_MS = 60_000;

/** Starts only on enter. One private unix stream carries all position updates. */
export class QuickshellVisitorOverlay implements VisitorOverlay {
  onFailure?: (error: Error) => void;
  private state: VisitorState = { visible: false, name: "", x: 0, y: 0, screens: [] };
  private child: ChildProcess | null = null;
  private server: Server | null = null;
  private socket: Socket | null = null;
  private dir: string | null = null;
  private idle: ReturnType<typeof setTimeout> | null = null;
  private starting: Promise<void> | null = null;
  private stopping: Promise<void> | null = null;
  private pending = false;
  constructor(private log: (line: string) => void = console.error, private idleMs = OVERLAY_IDLE_MS) {}

  async show(state: VisitorState) {
    if (this.idle) clearTimeout(this.idle);
    this.idle = null;
    await this.stopping;
    this.state = state;
    if (!this.child) {
      this.starting ??= this.start().finally(() => { this.starting = null; });
      await this.starting;
    }
    this.write();
  }

  update(state: VisitorState) { this.state = state; this.write(); }

  hide() {
    this.state = { ...this.state, visible: false };
    this.write();
    if (this.child && !this.idle) this.idle = setTimeout(() => void this.stop(), this.idleMs);
  }

  private write() {
    if (!this.socket || this.pending) return;
    // Coalesce while a reader is backpressured; never accumulate mouse history.
    if (!this.socket.write(JSON.stringify(this.state) + "\n")) {
      this.pending = true;
      this.socket.once("drain", () => { this.pending = false; this.write(); });
    }
  }

  private async start() {
    const runtime = process.env.LATTICES_VISITOR_RUNTIME_DIR ?? process.env.XDG_RUNTIME_DIR;
    if (!runtime) throw new Error("XDG_RUNTIME_DIR is not set");
    this.dir = mkdtempSync(join(runtime, "lattices-visitor-"));
    const path = join(this.dir, "positions.sock");
    try {
      let connected!: () => void;
      const connection = new Promise<void>((resolve) => { connected = resolve; });
      this.server = createServer((socket) => {
        this.socket?.destroy();
        this.socket = socket;
        this.pending = false;
        socket.on("error", () => {});
        socket.on("close", () => { if (this.socket === socket) this.socket = null; });
        this.write();
        connected();
      });
      await new Promise<void>((resolve, reject) => {
        this.server!.once("error", reject);
        this.server!.listen(path, resolve);
      });
      chmodSync(path, 0o600);
      const child = spawn("quickshell", ["-p", CONFIG], {
        env: { ...process.env, LATTICES_VISITOR_SOCKET: path,
          ...(process.env.LATTICES_VISITOR_RUNTIME_DIR ? {
            XDG_RUNTIME_DIR: runtime,
            WAYLAND_DISPLAY: process.env.WAYLAND_DISPLAY?.startsWith("/") ? process.env.WAYLAND_DISPLAY
              : join(process.env.XDG_RUNTIME_DIR ?? runtime, process.env.WAYLAND_DISPLAY ?? "wayland-0"),
          } : {}),
        }, stdio: ["ignore", "pipe", "pipe"],
      });
      this.child = child;
      for (const stream of [child.stdout, child.stderr]) stream?.on("data", (data) => this.log(`[visitor] ${String(data).trim()}`));
      let timer!: ReturnType<typeof setTimeout>;
      try {
        await Promise.race([connection, new Promise<never>((_, reject) => {
          timer = setTimeout(() => reject(new Error("Visitor overlay did not connect")), 5000);
          child.once("error", reject);
          child.once("exit", (code) => reject(new Error(`Visitor overlay exited (${code})`)));
        })]);
      } finally { clearTimeout(timer); }
      child.on("exit", () => {
        if (this.child === child) {
          this.log("Visitor overlay exited");
          this.onFailure?.(new Error("Visitor overlay exited"));
          void this.stop();
        }
      });
    } catch (error) { await this.stop(); throw error; }
  }

  stop(): Promise<void> {
    this.stopping ??= this.doStop().finally(() => { this.stopping = null; });
    return this.stopping;
  }

  private async doStop() {
    if (this.idle) clearTimeout(this.idle);
    this.idle = null;
    const child = this.child;
    this.child = null;
    const dir = this.dir;
    this.dir = null;
    this.socket?.destroy();
    this.socket = null;
    this.pending = false;
    const server = this.server;
    this.server = null;
    if (server) await new Promise<void>((resolve) => server.close(() => resolve()));
    if (child && child.exitCode === null && child.signalCode === null) {
      await new Promise<void>((resolve) => {
        const timer = setTimeout(() => { child.kill("SIGKILL"); resolve(); }, 1500);
        child.once("exit", () => { clearTimeout(timer); resolve(); });
        child.kill("SIGTERM");
      });
    }
    if (dir) rmSync(dir, { recursive: true, force: true });
  }
}
