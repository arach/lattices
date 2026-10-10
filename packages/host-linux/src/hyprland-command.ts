// Hyprland socket1 is request/reply, with EOF delimiting the reply. The
// compositor closes each connection: one socket per request, no subprocess
// and no persistent-connection pool. Socket2 is the separate event stream.
import { connect } from "node:net";
import { join } from "node:path";

export function commandSocketPath(env: NodeJS.ProcessEnv = process.env): string {
  if (!env.HYPRLAND_INSTANCE_SIGNATURE) throw new Error("hyprctl: HYPRLAND_INSTANCE_SIGNATURE is not set");
  if (!env.XDG_RUNTIME_DIR) throw new Error("hyprctl: XDG_RUNTIME_DIR is not set");
  return join(env.XDG_RUNTIME_DIR, "hypr", env.HYPRLAND_INSTANCE_SIGNATURE, ".socket.sock");
}

interface RequestOptions {
  path?: string;
  timeoutMs?: number;
  maxBytes?: number;
}

/** No retries: an interrupted dispatch may already have executed. */
export function request(command: string, options: RequestOptions = {}): Promise<string> {
  return new Promise((resolve, reject) => {
    const path = options.path ?? commandSocketPath();
    const socket = connect(path);
    const chunks: Buffer[] = [];
    let bytes = 0;
    let settled = false;
    const finish = (error?: Error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      socket.destroy();
      if (error) reject(new Error("hyprctl: " + error.message));
      else resolve(Buffer.concat(chunks, bytes).toString("utf8"));
    };
    // A request deadline, not a polling/reconnect timer. Match exec.ts's limits.
    const timer = setTimeout(() => finish(new Error("command socket timed out")), options.timeoutMs ?? 10_000);
    socket.once("connect", () => socket.end(command));
    socket.on("data", (chunk: Buffer) => {
      bytes += chunk.length;
      if (bytes > (options.maxBytes ?? 64 * 1024 * 1024)) {
        finish(new Error("command socket reply exceeds byte limit"));
      } else chunks.push(chunk);
    });
    socket.once("end", () => finish());
    socket.once("error", finish);
    socket.once("close", () => {
      if (!settled) finish(new Error("command socket closed before reply EOF"));
    });
  });
}

/** One compositor batch; success only when every dispatcher answers ok. */
export async function dispatchBatch(commands: string[], options: RequestOptions = {}): Promise<void> {
  if (commands.length === 0) return;
  const out = (await request("[[BATCH]]" + commands.map((c) => "dispatch " + c).join(" ; "), options)).trim();
  const replies = out.split(/\n+/).map((line) => line.trim()).filter(Boolean);
  const failures = replies.filter((line) => line !== "ok");
  if (failures.length) throw new Error("hyprctl: " + failures.join("; "));
  if (replies.length !== commands.length) throw new Error("hyprctl: expected " + commands.length + " batch replies, received " + replies.length);
  // Hyprland batches are not rollback transactions: earlier commands can have
  // executed even if a later dispatcher fails. Never retry the batch.
}
