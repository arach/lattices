// Live view through wayvnc. The host starts it on demand, bound to the same
// address as the host itself, so it is reachable only where the host is.
// macOS Screen Sharing opens the returned vnc:// URL directly.

import { spawn, type ChildProcess } from "node:child_process";
import { connect } from "node:net";

let child: ChildProcess | null = null;
let current: { host: string; port: number; output?: string } | null = null;

function portOpen(host: string, port: number, timeoutMs = 300): Promise<boolean> {
  return new Promise((resolve) => {
    const socket = connect({ host, port });
    const done = (open: boolean) => {
      socket.destroy();
      resolve(open);
    };
    socket.setTimeout(timeoutMs, () => done(false));
    socket.once("connect", () => done(true));
    socket.once("error", () => done(false));
  });
}

export function status() {
  return current && child && child.exitCode === null
    ? { running: true, ...current, url: `vnc://${current.host}:${current.port}` }
    : { running: false };
}

export async function start(host: string, port = 5900, output?: string) {
  if (current && child && child.exitCode === null) return status();
  if (await portOpen(host, port)) {
    // Someone else's VNC server is already there; report it rather than fight it.
    return { running: true, host, port, external: true, url: `vnc://${host}:${port}` };
  }
  const args = [...(output ? ["-o", output] : []), host, String(port)];
  child = spawn("wayvnc", args, { stdio: ["ignore", "ignore", "pipe"] });
  let stderr = "";
  child.stderr?.on("data", (d) => (stderr += String(d)));
  current = { host, port, output };
  for (let i = 0; i < 30; i++) {
    if (child.exitCode !== null) throw new Error(`wayvnc exited: ${stderr.trim() || child.exitCode}`);
    if (await portOpen(host, port)) return status();
    await new Promise((r) => setTimeout(r, 100));
  }
  throw new Error("wayvnc did not start listening within 3s");
}

export function stop() {
  const was = status();
  child?.kill("SIGTERM");
  child = null;
  current = null;
  return { ok: true, wasRunning: was.running };
}
