import { watch } from "node:fs";
import { connect, type Socket } from "node:net";
import { join } from "node:path";

/** lan-mouse's newline-delimited frontend events; no polling or config writes. */
export function watchLanMouse(changed: () => void): () => void {
  const runtime = process.env.XDG_RUNTIME_DIR;
  if (!runtime) return () => {};
  const filename = "lan-mouse-socket.sock";
  const path = join(runtime, filename);
  let socket: Socket | null = null;
  let stopped = false;
  let pending: ReturnType<typeof setTimeout> | undefined;
  const open = () => {
    if (stopped) return;
    socket?.destroy();
    socket = connect(path);
    socket.setEncoding("utf8");
    let buffer = "";
    socket.on("connect", () => { socket?.write('"Sync"\n'); changed(); });
    socket.on("data", (chunk: string) => {
      buffer += chunk;
      if (buffer.length > 1024 * 1024) { socket?.destroy(); return; }
      let newline: number;
      while ((newline = buffer.indexOf("\n")) !== -1) {
        const line = buffer.slice(0, newline);
        buffer = buffer.slice(newline + 1);
        try {
          const event = JSON.parse(line);
          if (event && typeof event === "object" && ["State", "Created", "Deleted", "Enumerate", "CaptureStatus"].some((key) => key in event)) changed();
        } catch { /* Ignore unknown IPC versions; CLI remains authoritative. */ }
      }
    });
    socket.on("error", () => {});
    socket.on("close", changed);
  };
  // Reconnect only on socket lifecycle events (including a late service start).
  let watcher: ReturnType<typeof watch> | undefined;
  try {
    watcher = watch(runtime, (_event, name) => {
      if (String(name) !== filename || stopped) return;
      clearTimeout(pending);
      pending = setTimeout(open, 80);
    });
    watcher.on("error", () => {});
  } catch { /* Menu opens and systemd events still refresh state. */ }
  open();
  return () => { stopped = true; clearTimeout(pending); watcher?.close(); socket?.destroy(); };
}
