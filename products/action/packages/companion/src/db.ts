import { mkdirSync, readFileSync, statSync } from "node:fs";
import { createHash, randomUUID } from "node:crypto";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { Database } from "bun:sqlite";

export const DB_SCHEMA_VERSION = 1;
export const RPC_VERSION = 1;

export type JobState = "queued" | "running" | "cancelling" | "cancelled" | "completed" | "failed";
export type JobEventLevel = "debug" | "info" | "warn" | "error";

export interface JobRecord {
  id: string;
  kind: string;
  state: JobState;
  priority: number;
  payload: Record<string, unknown>;
  result?: unknown;
  error?: string;
  sessionId?: string;
  idempotencyKey?: string;
  attempts: number;
  maxAttempts: number;
  createdAt: string;
  updatedAt: string;
  startedAt?: string;
  finishedAt?: string;
  workerPid?: number;
  leaseUntil?: string;
}

export interface JobEventRecord {
  id: string;
  jobId: string;
  at: string;
  level: JobEventLevel;
  type: string;
  message?: string;
  data?: unknown;
}

export interface SecretStatusRecord {
  name: string;
  present: boolean;
  source?: string;
  loadedAt: string;
  fingerprint?: string;
}

export interface ArtifactRecord {
  id: string;
  sessionId?: string;
  jobId?: string;
  kind: string;
  path: string;
  bytes?: number;
  sha256?: string;
  metadata?: unknown;
  createdAt: string;
}

export interface TimelineRecord {
  id: string;
  sessionId?: string;
  jobId?: string;
  imageArtifactId?: string;
  provider?: string;
  model?: string;
  promptHash?: string;
  summary?: string;
  result?: unknown;
  capturedAt: string;
}

interface JobRow {
  id: string;
  kind: string;
  state: JobState;
  priority: number;
  payload_json: string;
  result_json: string | null;
  error: string | null;
  session_id: string | null;
  idempotency_key: string | null;
  attempts: number;
  max_attempts: number;
  created_at: string;
  updated_at: string;
  started_at: string | null;
  finished_at: string | null;
  worker_pid: number | null;
  lease_until: string | null;
}

function now(): string {
  return new Date().toISOString();
}

function schemaPath(): string {
  return resolve(dirname(fileURLToPath(import.meta.url)), "schema.sql");
}

function jsonParse<T>(raw: string | null | undefined, fallback: T): T {
  if (!raw) {
    return fallback;
  }
  try {
    return JSON.parse(raw) as T;
  } catch {
    return fallback;
  }
}

function jsonString(value: unknown): string {
  return JSON.stringify(value ?? null);
}

function optionalText(value: unknown): string | undefined {
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

function asJob(row: JobRow | null): JobRecord | undefined {
  if (!row) {
    return undefined;
  }

  return {
    id: row.id,
    kind: row.kind,
    state: row.state,
    priority: row.priority,
    payload: jsonParse<Record<string, unknown>>(row.payload_json, {}),
    result: jsonParse<unknown>(row.result_json, undefined),
    error: row.error ?? undefined,
    sessionId: row.session_id ?? undefined,
    idempotencyKey: row.idempotency_key ?? undefined,
    attempts: row.attempts,
    maxAttempts: row.max_attempts,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    startedAt: row.started_at ?? undefined,
    finishedAt: row.finished_at ?? undefined,
    workerPid: row.worker_pid ?? undefined,
    leaseUntil: row.lease_until ?? undefined,
  };
}

function eventRowToRecord(row: Record<string, unknown>): JobEventRecord {
  return {
    id: String(row.id),
    jobId: String(row.job_id),
    at: String(row.at),
    level: String(row.level) as JobEventLevel,
    type: String(row.type),
    message: optionalText(row.message),
    data: jsonParse(String(row.data_json ?? "null"), undefined),
  };
}

function sha256File(path: string): { bytes?: number; sha256?: string } {
  try {
    const stats = statSync(path);
    if (!stats.isFile()) {
      return {};
    }
    const hash = createHash("sha256");
    hash.update(readFileSync(path));
    return { bytes: stats.size, sha256: hash.digest("hex") };
  } catch {
    return {};
  }
}

export class ActionCompanionDatabase {
  readonly database: Database;

  constructor(readonly path: string) {
    mkdirSync(dirname(path), { recursive: true });
    this.database = new Database(path);
    this.initialize();
  }

  close(): void {
    this.database.close();
  }

  initialize(): void {
    this.database.exec(readFileSync(schemaPath(), "utf8"));
    this.database.exec(`PRAGMA user_version = ${DB_SCHEMA_VERSION}`);
    this.database
      .query("INSERT OR REPLACE INTO schema_meta (key, value, updated_at) VALUES (?, ?, ?)")
      .run("schema_version", String(DB_SCHEMA_VERSION), now());
  }

  recoverInterruptedJobs(): void {
    const at = now();
    this.database
      .query(`UPDATE jobs
              SET state = 'failed', error = COALESCE(error, 'companion restarted while job was running'), finished_at = ?, updated_at = ?, lease_until = NULL, worker_pid = NULL
              WHERE state IN ('running', 'cancelling')`)
      .run(at, at);
    this.database
      .query("UPDATE workers SET state = 'orphaned', updated_at = ? WHERE state = 'running'")
      .run(at);
  }

  enqueueJob(input: {
    kind: string;
    payload?: Record<string, unknown>;
    priority?: number;
    sessionId?: string;
    idempotencyKey?: string;
    maxAttempts?: number;
  }): JobRecord {
    if (input.idempotencyKey) {
      const existing = this.database
        .query<JobRow>("SELECT * FROM jobs WHERE idempotency_key = ?")
        .get(input.idempotencyKey);
      const job = asJob(existing);
      if (job) {
        return job;
      }
    }

    const at = now();
    const id = `job_${randomUUID()}`;
    this.database
      .query(`INSERT INTO jobs
        (id, kind, state, priority, payload_json, session_id, idempotency_key, attempts, max_attempts, created_at, updated_at)
        VALUES (?, ?, 'queued', ?, ?, ?, ?, 0, ?, ?, ?)`)
      .run(
        id,
        input.kind,
        input.priority ?? 0,
        jsonString(input.payload ?? {}),
        input.sessionId ?? null,
        input.idempotencyKey ?? null,
        input.maxAttempts ?? 1,
        at,
        at,
      );
    this.addJobEvent(id, {
      level: "info",
      type: "job.queued",
      message: `Queued ${input.kind}`,
      data: { kind: input.kind },
    });
    return this.requireJob(id);
  }

  claimNextJob(leaseMs: number): JobRecord | undefined {
    const candidate = this.database
      .query<JobRow>(`SELECT * FROM jobs
        WHERE state = 'queued'
        ORDER BY priority DESC, created_at ASC
        LIMIT 1`)
      .get();
    const job = asJob(candidate);
    if (!job) {
      return undefined;
    }

    const at = now();
    const leaseUntil = new Date(Date.now() + leaseMs).toISOString();
    this.database
      .query(`UPDATE jobs
        SET state = 'running', attempts = attempts + 1, started_at = COALESCE(started_at, ?), updated_at = ?, lease_until = ?
        WHERE id = ? AND state = 'queued'`)
      .run(at, at, leaseUntil, job.id);
    const claimed = this.requireJob(job.id);
    this.addJobEvent(job.id, {
      level: "info",
      type: "job.started",
      message: `Started ${job.kind}`,
      data: { leaseUntil },
    });
    return claimed;
  }

  requireJob(id: string): JobRecord {
    const job = this.getJob(id);
    if (!job) {
      throw new Error(`Unknown job ${id}`);
    }
    return job;
  }

  getJob(id: string): JobRecord | undefined {
    return asJob(this.database.query<JobRow>("SELECT * FROM jobs WHERE id = ?").get(id));
  }

  listJobs(input: { state?: string; limit?: number } = {}): JobRecord[] {
    const limit = Math.max(1, Math.min(input.limit ?? 50, 500));
    if (input.state) {
      return this.database
        .query<JobRow>("SELECT * FROM jobs WHERE state = ? ORDER BY created_at DESC LIMIT ?")
        .all(input.state, limit)
        .map((row) => asJob(row)!);
    }
    return this.database
      .query<JobRow>("SELECT * FROM jobs ORDER BY created_at DESC LIMIT ?")
      .all(limit)
      .map((row) => asJob(row)!);
  }

  setWorkerPid(jobId: string, workerId: string, pid: number | undefined): void {
    const at = now();
    this.database.query("UPDATE jobs SET worker_pid = ?, updated_at = ? WHERE id = ?").run(pid ?? null, at, jobId);
    this.database
      .query("INSERT OR REPLACE INTO workers (id, pid, job_id, state, started_at, updated_at) VALUES (?, ?, ?, 'running', COALESCE((SELECT started_at FROM workers WHERE id = ?), ?), ?)")
      .run(workerId, pid ?? null, jobId, workerId, at, at);
  }

  setWorkerState(workerId: string, state: string): void {
    this.database.query("UPDATE workers SET state = ?, updated_at = ? WHERE id = ?").run(state, now(), workerId);
  }

  cancelJob(id: string, reason = "cancel requested"): JobRecord {
    const job = this.requireJob(id);
    const at = now();
    if (job.state === "queued") {
      this.database
        .query("UPDATE jobs SET state = 'cancelled', error = ?, finished_at = ?, updated_at = ?, lease_until = NULL WHERE id = ?")
        .run(reason, at, at, id);
      this.addJobEvent(id, { level: "warn", type: "job.cancelled", message: reason });
    } else if (job.state === "running") {
      this.database
        .query("UPDATE jobs SET state = 'cancelling', error = ?, updated_at = ? WHERE id = ?")
        .run(reason, at, id);
      this.addJobEvent(id, { level: "warn", type: "job.cancelling", message: reason });
    }
    return this.requireJob(id);
  }

  finishJob(id: string, input: { result?: unknown; error?: string; state: "completed" | "failed" | "cancelled" }): JobRecord {
    const at = now();
    this.database
      .query(`UPDATE jobs
        SET state = ?, result_json = ?, error = ?, finished_at = ?, updated_at = ?, lease_until = NULL, worker_pid = NULL
        WHERE id = ?`)
      .run(input.state, input.result === undefined ? null : jsonString(input.result), input.error ?? null, at, at, id);
    this.addJobEvent(id, {
      level: input.state === "completed" ? "info" : "error",
      type: `job.${input.state}`,
      message: input.error ?? `Job ${input.state}`,
    });
    return this.requireJob(id);
  }

  addJobEvent(jobId: string, input: { level?: JobEventLevel; type: string; message?: string; data?: unknown }): JobEventRecord {
    const id = `evt_${randomUUID()}`;
    const at = now();
    this.database
      .query("INSERT INTO job_events (id, job_id, at, level, type, message, data_json) VALUES (?, ?, ?, ?, ?, ?, ?)")
      .run(id, jobId, at, input.level ?? "info", input.type, input.message ?? null, input.data === undefined ? null : jsonString(input.data));
    return {
      id,
      jobId,
      at,
      level: input.level ?? "info",
      type: input.type,
      message: input.message,
      data: input.data,
    };
  }

  jobEvents(jobId: string, limit = 200): JobEventRecord[] {
    return this.database
      .query<Record<string, unknown>>("SELECT * FROM job_events WHERE job_id = ? ORDER BY at ASC LIMIT ?")
      .all(jobId, Math.max(1, Math.min(limit, 1000)))
      .map(eventRowToRecord);
  }

  upsertSecretStatus(status: SecretStatusRecord): void {
    this.database
      .query("INSERT OR REPLACE INTO secret_status (name, present, source, loaded_at, fingerprint) VALUES (?, ?, ?, ?, ?)")
      .run(status.name, status.present ? 1 : 0, status.source ?? null, status.loadedAt, status.fingerprint ?? null);
  }

  secretStatuses(): SecretStatusRecord[] {
    return this.database
      .query<Record<string, unknown>>("SELECT * FROM secret_status ORDER BY name ASC")
      .all()
      .map((row) => ({
        name: String(row.name),
        present: Number(row.present) === 1,
        source: optionalText(row.source),
        loadedAt: String(row.loaded_at),
        fingerprint: optionalText(row.fingerprint),
      }));
  }

  recordOperatorHistory(input: {
    actor?: string;
    client?: string;
    command: string;
    request?: unknown;
    jobId?: string;
    resultSummary?: string;
  }): void {
    this.database
      .query("INSERT INTO operator_history (id, at, actor, client, command, request_json, job_id, result_summary) VALUES (?, ?, ?, ?, ?, ?, ?, ?)")
      .run(
        `hist_${randomUUID()}`,
        now(),
        input.actor ?? null,
        input.client ?? null,
        input.command,
        input.request === undefined ? null : jsonString(input.request),
        input.jobId ?? null,
        input.resultSummary ?? null,
      );
  }

  operatorHistory(limit = 100): unknown[] {
    return this.database
      .query<Record<string, unknown>>("SELECT * FROM operator_history ORDER BY at DESC LIMIT ?")
      .all(Math.max(1, Math.min(limit, 500)))
      .map((row) => ({
        id: row.id,
        at: row.at,
        actor: row.actor,
        client: row.client,
        command: row.command,
        request: jsonParse(String(row.request_json ?? "null"), undefined),
        jobId: row.job_id,
        resultSummary: row.result_summary,
      }));
  }

  upsertSession(input: { id: string; mode?: string; state?: string; goal?: string; artifactRoot?: string; createdAt?: string; updatedAt?: string }): void {
    const at = now();
    this.database
      .query(`INSERT INTO sessions (id, mode, state, goal, artifact_root, created_at, updated_at)
              VALUES (?, ?, ?, ?, ?, ?, ?)
              ON CONFLICT(id) DO UPDATE SET mode = excluded.mode, state = excluded.state, goal = COALESCE(excluded.goal, sessions.goal), artifact_root = COALESCE(excluded.artifact_root, sessions.artifact_root), updated_at = excluded.updated_at`)
      .run(input.id, input.mode ?? null, input.state ?? null, input.goal ?? null, input.artifactRoot ?? null, input.createdAt ?? at, input.updatedAt ?? at);
  }

  upsertArtifact(input: { id?: string; sessionId?: string; jobId?: string; kind: string; path: string; metadata?: unknown; createdAt?: string }): ArtifactRecord {
    const file = sha256File(input.path);
    const artifact: ArtifactRecord = {
      id: input.id ?? `art_${randomUUID()}`,
      sessionId: input.sessionId,
      jobId: input.jobId,
      kind: input.kind,
      path: input.path,
      bytes: file.bytes,
      sha256: file.sha256,
      metadata: input.metadata,
      createdAt: input.createdAt ?? now(),
    };
    this.database
      .query(`INSERT OR REPLACE INTO artifacts (id, session_id, job_id, kind, path, bytes, sha256, metadata_json, created_at)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`)
      .run(
        artifact.id,
        artifact.sessionId ?? null,
        artifact.jobId ?? null,
        artifact.kind,
        artifact.path,
        artifact.bytes ?? null,
        artifact.sha256 ?? null,
        artifact.metadata === undefined ? null : jsonString(artifact.metadata),
        artifact.createdAt,
      );
    return artifact;
  }

  artifacts(input: { sessionId?: string; kind?: string; limit?: number } = {}): ArtifactRecord[] {
    const limit = Math.max(1, Math.min(input.limit ?? 100, 500));
    let rows: Record<string, unknown>[];
    if (input.sessionId) {
      rows = this.database.query<Record<string, unknown>>("SELECT * FROM artifacts WHERE session_id = ? ORDER BY created_at DESC LIMIT ?").all(input.sessionId, limit);
    } else if (input.kind) {
      rows = this.database.query<Record<string, unknown>>("SELECT * FROM artifacts WHERE kind = ? ORDER BY created_at DESC LIMIT ?").all(input.kind, limit);
    } else {
      rows = this.database.query<Record<string, unknown>>("SELECT * FROM artifacts ORDER BY created_at DESC LIMIT ?").all(limit);
    }
    return rows.map((row) => ({
      id: String(row.id),
      sessionId: optionalText(row.session_id),
      jobId: optionalText(row.job_id),
      kind: String(row.kind),
      path: String(row.path),
      bytes: typeof row.bytes === "number" ? row.bytes : undefined,
      sha256: optionalText(row.sha256),
      metadata: jsonParse(String(row.metadata_json ?? "null"), undefined),
      createdAt: String(row.created_at),
    }));
  }

  addObservation(input: { sessionId?: string; jobId?: string; surfaceId?: string; kind: string; source: string; summary?: string; data?: unknown; artifactId?: string; capturedAt?: string }): void {
    this.database
      .query("INSERT INTO observations (id, session_id, job_id, surface_id, kind, source, captured_at, summary, data_json, artifact_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)")
      .run(
        `obs_${randomUUID()}`,
        input.sessionId ?? null,
        input.jobId ?? null,
        input.surfaceId ?? null,
        input.kind,
        input.source,
        input.capturedAt ?? now(),
        input.summary ?? null,
        input.data === undefined ? null : jsonString(input.data),
        input.artifactId ?? null,
      );
  }

  addVisionTimeline(input: { sessionId?: string; jobId?: string; imageArtifactId?: string; provider?: string; model?: string; promptHash?: string; summary?: string; result?: unknown; capturedAt?: string }): TimelineRecord {
    const record: TimelineRecord = {
      id: `vis_${randomUUID()}`,
      sessionId: input.sessionId,
      jobId: input.jobId,
      imageArtifactId: input.imageArtifactId,
      provider: input.provider,
      model: input.model,
      promptHash: input.promptHash,
      summary: input.summary,
      result: input.result,
      capturedAt: input.capturedAt ?? now(),
    };
    this.database
      .query("INSERT INTO vision_timeline (id, session_id, job_id, image_artifact_id, provider, model, prompt_hash, summary, result_json, captured_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)")
      .run(
        record.id,
        record.sessionId ?? null,
        record.jobId ?? null,
        record.imageArtifactId ?? null,
        record.provider ?? null,
        record.model ?? null,
        record.promptHash ?? null,
        record.summary ?? null,
        record.result === undefined ? null : jsonString(record.result),
        record.capturedAt,
      );
    return record;
  }

  visionTimeline(input: { sessionId?: string; limit?: number } = {}): TimelineRecord[] {
    const limit = Math.max(1, Math.min(input.limit ?? 100, 500));
    const rows = input.sessionId
      ? this.database.query<Record<string, unknown>>("SELECT * FROM vision_timeline WHERE session_id = ? ORDER BY captured_at DESC LIMIT ?").all(input.sessionId, limit)
      : this.database.query<Record<string, unknown>>("SELECT * FROM vision_timeline ORDER BY captured_at DESC LIMIT ?").all(limit);
    return rows.map((row) => ({
      id: String(row.id),
      sessionId: optionalText(row.session_id),
      jobId: optionalText(row.job_id),
      imageArtifactId: optionalText(row.image_artifact_id),
      provider: optionalText(row.provider),
      model: optionalText(row.model),
      promptHash: optionalText(row.prompt_hash),
      summary: optionalText(row.summary),
      result: jsonParse(String(row.result_json ?? "null"), undefined),
      capturedAt: String(row.captured_at),
    }));
  }

  counts(): Record<string, number> {
    const rows = this.database.query<Record<string, unknown>>("SELECT state, COUNT(*) AS count FROM jobs GROUP BY state").all();
    const result: Record<string, number> = {};
    for (const row of rows) {
      result[String(row.state)] = Number(row.count ?? 0);
    }
    return result;
  }
}
