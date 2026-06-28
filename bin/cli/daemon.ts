export type DaemonClient = typeof import("../daemon-client.ts");

let _client: DaemonClient | undefined;

/** Lazy-load daemon client — avoids import cost for pure tmux commands. */
export async function loadDaemonClient(): Promise<DaemonClient> {
  if (!_client) {
    _client = await import("../daemon-client.ts");
  }
  return _client;
}

/**
 * Run when the daemon is reachable. Returns null when the daemon is down or the
 * RPC fails — use for commands that fall back to tmux (ls, status).
 */
export async function tryDaemon<T>(
  fn: (client: DaemonClient) => Promise<T>
): Promise<T | null> {
  const client = await loadDaemonClient();
  if (!(await client.isDaemonRunning())) return null;
  try {
    return await fn(client);
  } catch {
    return null;
  }
}

export async function withDaemon<T>(
  fn: (client: DaemonClient) => Promise<T>,
  opts?: { message?: string; exitCode?: number }
): Promise<T> {
  const message = opts?.message ?? "Daemon not running. Start with: lattices app";
  const exitCode = opts?.exitCode ?? 1;

  const client = await loadDaemonClient();
  if (!(await client.isDaemonRunning())) {
    console.error(message);
    process.exit(exitCode);
  }

  try {
    return await fn(client);
  } catch (e: unknown) {
    console.error(`Error: ${(e as Error).message}`);
    process.exit(exitCode);
  }
}