export type DaemonClient = typeof import("../daemon-client.ts");

export async function withDaemon<T>(
  fn: (client: DaemonClient) => Promise<T>,
  opts?: { message?: string; exitCode?: number }
): Promise<T> {
  const message = opts?.message ?? "Daemon not running. Start with: lattices app";
  const exitCode = opts?.exitCode ?? 1;

  const client = await import("../daemon-client.ts");
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