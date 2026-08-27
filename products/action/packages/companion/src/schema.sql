PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;
PRAGMA busy_timeout = 5000;

CREATE TABLE IF NOT EXISTS schema_meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS jobs (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL,
  state TEXT NOT NULL,
  priority INTEGER NOT NULL DEFAULT 0,
  payload_json TEXT NOT NULL DEFAULT '{}',
  result_json TEXT,
  error TEXT,
  session_id TEXT,
  idempotency_key TEXT,
  attempts INTEGER NOT NULL DEFAULT 0,
  max_attempts INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  started_at TEXT,
  finished_at TEXT,
  worker_pid INTEGER,
  lease_until TEXT
);

CREATE UNIQUE INDEX IF NOT EXISTS jobs_idempotency_key_idx
  ON jobs(idempotency_key)
  WHERE idempotency_key IS NOT NULL;

CREATE INDEX IF NOT EXISTS jobs_state_priority_idx
  ON jobs(state, priority DESC, created_at ASC);
CREATE INDEX IF NOT EXISTS jobs_session_idx ON jobs(session_id, created_at DESC);

CREATE TABLE IF NOT EXISTS job_events (
  id TEXT PRIMARY KEY,
  job_id TEXT NOT NULL,
  at TEXT NOT NULL,
  level TEXT NOT NULL,
  type TEXT NOT NULL,
  message TEXT,
  data_json TEXT,
  FOREIGN KEY(job_id) REFERENCES jobs(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS job_events_job_idx ON job_events(job_id, at ASC);

CREATE TABLE IF NOT EXISTS sessions (
  id TEXT PRIMARY KEY,
  mode TEXT,
  state TEXT,
  goal TEXT,
  artifact_root TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS observations (
  id TEXT PRIMARY KEY,
  session_id TEXT,
  job_id TEXT,
  surface_id TEXT,
  kind TEXT NOT NULL,
  source TEXT NOT NULL,
  captured_at TEXT NOT NULL,
  summary TEXT,
  data_json TEXT,
  artifact_id TEXT,
  FOREIGN KEY(job_id) REFERENCES jobs(id) ON DELETE SET NULL,
  FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS observations_time_idx ON observations(captured_at DESC);
CREATE INDEX IF NOT EXISTS observations_session_idx ON observations(session_id, captured_at DESC);

CREATE TABLE IF NOT EXISTS vision_timeline (
  id TEXT PRIMARY KEY,
  session_id TEXT,
  job_id TEXT,
  image_artifact_id TEXT,
  provider TEXT,
  model TEXT,
  prompt_hash TEXT,
  summary TEXT,
  result_json TEXT,
  captured_at TEXT NOT NULL,
  FOREIGN KEY(job_id) REFERENCES jobs(id) ON DELETE SET NULL,
  FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS vision_timeline_time_idx ON vision_timeline(captured_at DESC);
CREATE INDEX IF NOT EXISTS vision_timeline_session_idx ON vision_timeline(session_id, captured_at DESC);

CREATE TABLE IF NOT EXISTS artifacts (
  id TEXT PRIMARY KEY,
  session_id TEXT,
  job_id TEXT,
  kind TEXT NOT NULL,
  path TEXT NOT NULL,
  bytes INTEGER,
  sha256 TEXT,
  metadata_json TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY(job_id) REFERENCES jobs(id) ON DELETE SET NULL,
  FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE SET NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS artifacts_path_job_idx ON artifacts(path, job_id);
CREATE INDEX IF NOT EXISTS artifacts_session_idx ON artifacts(session_id, created_at DESC);
CREATE INDEX IF NOT EXISTS artifacts_kind_idx ON artifacts(kind, created_at DESC);

CREATE TABLE IF NOT EXISTS operator_history (
  id TEXT PRIMARY KEY,
  at TEXT NOT NULL,
  actor TEXT,
  client TEXT,
  command TEXT NOT NULL,
  request_json TEXT,
  job_id TEXT,
  result_summary TEXT,
  FOREIGN KEY(job_id) REFERENCES jobs(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS operator_history_time_idx ON operator_history(at DESC);

CREATE TABLE IF NOT EXISTS secret_status (
  name TEXT PRIMARY KEY,
  present INTEGER NOT NULL,
  source TEXT,
  loaded_at TEXT NOT NULL,
  fingerprint TEXT
);

CREATE TABLE IF NOT EXISTS workers (
  id TEXT PRIMARY KEY,
  pid INTEGER,
  job_id TEXT,
  state TEXT NOT NULL,
  started_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(job_id) REFERENCES jobs(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS workers_job_idx ON workers(job_id, updated_at DESC);
