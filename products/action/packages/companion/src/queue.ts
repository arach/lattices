import { spawn, type ChildProcess } from "node:child_process";
import { resolve } from "node:path";
import { randomUUID } from "node:crypto";

import type { ActionCompanionDatabase, JobRecord } from "./db.js";

export interface QueueConfig {
  actionRoot: string;
  companionBaseUrl: string;
  maxConcurrent?: number;
  pollMs?: number;
  leaseMs?: number;
}

interface RunningWorker {
  workerId: string;
  jobId: string;
  child: ChildProcess;
}

const TERMINAL_STATES = new Set(["completed", "failed", "cancelled"]);

function sleep(ms: number): Promise<void> {
  return new Promise((resolvePromise) => setTimeout(resolvePromise, ms));
}

export class ActionCompanionQueue {
  private readonly running = new Map<string, RunningWorker>();
  private timer: ReturnType<typeof setInterval> | undefined;
  private stopping = false;

  constructor(
    private readonly db: ActionCompanionDatabase,
    private readonly config: QueueConfig,
  ) {}

  start(): void {
    if (this.timer) {
      return;
    }
    this.db.recoverInterruptedJobs();
    this.timer = setInterval(() => {
      void this.pump();
    }, this.config.pollMs ?? 500);
    void this.pump();
  }

  stop(): void {
    this.stopping = true;
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = undefined;
    }
    for (const worker of this.running.values()) {
      worker.child.kill("SIGTERM");
    }
  }

  stats(): { running: number; maxConcurrent: number; jobs: Record<string, number> } {
    return {
      running: this.running.size,
      maxConcurrent: this.maxConcurrent(),
      jobs: this.db.counts(),
    };
  }

  enqueue(input: Parameters<ActionCompanionDatabase["enqueueJob"]>[0]): JobRecord {
    const job = this.db.enqueueJob(input);
    void this.pump();
    return job;
  }

  cancel(jobId: string, reason?: string): JobRecord {
    const job = this.db.cancelJob(jobId, reason);
    const worker = this.running.get(jobId);
    if (worker) {
      worker.child.kill("SIGTERM");
    }
    return job;
  }

  async wait(jobId: string, timeoutMs = 60_000): Promise<JobRecord> {
    const startedAt = Date.now();
    while (Date.now() - startedAt <= timeoutMs) {
      const job = this.db.requireJob(jobId);
      if (TERMINAL_STATES.has(job.state)) {
        return job;
      }
      await sleep(250);
    }
    return this.db.requireJob(jobId);
  }

  private maxConcurrent(): number {
    const configured = this.config.maxConcurrent ?? Number(process.env.ACTION_COMPANION_MAX_WORKERS ?? 1);
    return Math.max(1, Number.isFinite(configured) ? configured : 1);
  }

  private async pump(): Promise<void> {
    if (this.stopping) {
      return;
    }

    while (this.running.size < this.maxConcurrent()) {
      const job = this.db.claimNextJob(this.config.leaseMs ?? 5 * 60_000);
      if (!job) {
        return;
      }
      this.spawnWorker(job);
    }
  }

  private spawnWorker(job: JobRecord): void {
    const workerId = `worker_${randomUUID()}`;
    const workerPath = resolve(this.config.actionRoot, "packages/runtime/src/companion-worker.ts");
    const bunExecutable = process.execPath || "bun";
    const child = spawn(bunExecutable, [workerPath, "--job", job.id, "--base-url", this.config.companionBaseUrl, "--root", this.config.actionRoot], {
      cwd: this.config.actionRoot,
      env: {
        ...process.env,
        ACTION_ROOT: this.config.actionRoot,
        ACTION_COMPANION_BASE_URL: this.config.companionBaseUrl,
      },
      stdio: ["ignore", "pipe", "pipe"],
    });

    this.running.set(job.id, { workerId, jobId: job.id, child });
    this.db.setWorkerPid(job.id, workerId, child.pid);
    this.db.addJobEvent(job.id, {
      level: "info",
      type: "worker.spawned",
      message: `Spawned worker ${workerId}`,
      data: { pid: child.pid, workerPath },
    });

    child.stdout?.on("data", (data: Buffer) => {
      const text = data.toString("utf8").trim();
      if (text) {
        this.db.addJobEvent(job.id, { level: "debug", type: "worker.stdout", message: text.slice(0, 4000) });
      }
    });

    child.stderr?.on("data", (data: Buffer) => {
      const text = data.toString("utf8").trim();
      if (text) {
        this.db.addJobEvent(job.id, { level: "warn", type: "worker.stderr", message: text.slice(0, 4000) });
      }
    });

    child.on("exit", (code, signal) => {
      this.running.delete(job.id);
      const current = this.db.getJob(job.id);
      this.db.setWorkerState(workerId, code === 0 ? "exited" : "failed");
      if (current && !TERMINAL_STATES.has(current.state)) {
        const message = current.state === "cancelling"
          ? "job cancelled"
          : `worker exited before reporting completion (code=${code ?? "null"}, signal=${signal ?? "null"})`;
        this.db.finishJob(job.id, {
          state: current.state === "cancelling" ? "cancelled" : "failed",
          error: message,
        });
      }
      void this.pump();
    });

    child.on("error", (error) => {
      this.running.delete(job.id);
      this.db.setWorkerState(workerId, "failed");
      this.db.finishJob(job.id, { state: "failed", error: error.message });
      void this.pump();
    });
  }
}
