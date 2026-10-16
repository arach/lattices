import { execFile } from "node:child_process";

/** Run a command and resolve with stdout; rejects with stderr on failure. */
export function run(
  command: string,
  args: string[],
  options: { input?: string | Buffer; timeoutMs?: number; encoding?: "utf8" | "buffer" } = {}
): Promise<string> {
  return new Promise((resolve, reject) => {
    const child = execFile(
      command,
      args,
      { timeout: options.timeoutMs ?? 10_000, maxBuffer: 64 * 1024 * 1024 },
      (error, stdout, stderr) => {
        if (error) {
          const detail = String(stderr || error.message).trim();
          reject(new Error(`${command}: ${detail}`));
          return;
        }
        resolve(String(stdout));
      }
    );
    if (options.input !== undefined) child.stdin?.end(options.input);
  });
}

/** Run a command and resolve with raw stdout bytes. */
export function runBuffer(command: string, args: string[], timeoutMs = 15_000): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    execFile(
      command,
      args,
      { timeout: timeoutMs, maxBuffer: 256 * 1024 * 1024, encoding: "buffer" },
      (error, stdout, stderr) => {
        if (error) {
          reject(new Error(`${command}: ${String(stderr || error.message).trim()}`));
          return;
        }
        resolve(stdout as Buffer);
      }
    );
  });
}

/** Check current PATH, not a cached shell result, so re-probes are honest. */
export function hasCommand(command: string): boolean {
  return Bun.which(command) !== null;
}
