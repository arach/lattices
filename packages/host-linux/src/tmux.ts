// tmux sessions, named the way the Mac names them
// (WorkspaceManager.sessionName: <basename>-<first 3 bytes of sha256(path)>).

import { createHash } from "node:crypto";
import { existsSync, statSync } from "node:fs";
import { basename, resolve } from "node:path";
import { run } from "./exec.ts";
import type { Json } from "./router.ts";

export function sessionName(path: string): string {
  const base = basename(path).replace(/[^a-zA-Z0-9_-]/g, "-");
  const short = createHash("sha256").update(path, "utf8").digest("hex").slice(0, 6);
  return `${base}-${short}`;
}

const SEP = "\u001f";

async function tmux(args: string[]): Promise<string> {
  try {
    return await run("tmux", args);
  } catch (err) {
    // No server running means no sessions, not a failure.
    if (/no server running|error connecting/i.test((err as Error).message)) return "";
    throw err;
  }
}

export async function listSessions(): Promise<Json[]> {
  const sessionsOut = await tmux([
    "list-sessions",
    "-F",
    ["#{session_name}", "#{session_windows}", "#{session_attached}", "#{session_path}"].join(SEP),
  ]);
  const panesOut = await tmux([
    "list-panes",
    "-a",
    "-F",
    [
      "#{session_name}",
      "#{pane_id}",
      "#{window_index}",
      "#{window_name}",
      "#{pane_title}",
      "#{pane_current_command}",
      "#{pane_pid}",
      "#{pane_active}",
      "#{pane_current_path}",
    ].join(SEP),
  ]);
  const panes = new Map<string, Json[]>();
  for (const line of panesOut.split("\n").filter(Boolean)) {
    const [session, id, windowIndex, windowName, title, command, pid, active, cwd] = line.split(SEP);
    const list = panes.get(session) ?? [];
    list.push({
      id,
      windowIndex: Number(windowIndex),
      windowName,
      title,
      currentCommand: command,
      pid: Number(pid),
      isActive: active === "1",
      cwd,
    });
    panes.set(session, list);
  }
  return sessionsOut
    .split("\n")
    .filter(Boolean)
    .map((line) => {
      const [name, windows, attached, path] = line.split(SEP);
      return {
        name,
        windowCount: Number(windows),
        attached: Number(attached) > 0,
        path,
        panes: panes.get(name) ?? [],
      };
    });
}

export async function launch(path: string, name?: string): Promise<{ session: string; created: boolean }> {
  const dir = resolve(path);
  if (!existsSync(dir) || !statSync(dir).isDirectory()) throw new Error(`Not a directory: ${dir}`);
  const session = name ?? sessionName(dir);
  const exists = (await tmux(["list-sessions", "-F", "#{session_name}"])).split("\n").includes(session);
  if (!exists) await run("tmux", ["new-session", "-d", "-s", session, "-c", dir]);
  return { session, created: !exists };
}

export async function kill(name: string) {
  await run("tmux", ["kill-session", "-t", `=${name}`]);
}

export async function detach(name: string) {
  await run("tmux", ["detach-client", "-s", `=${name}`]);
}

/** Send literal text to a pane, optionally followed by Enter. */
export async function sendText(target: string, text: string, enter = false) {
  if (text) await run("tmux", ["send-keys", "-t", target, "-l", "--", text]);
  if (enter) await run("tmux", ["send-keys", "-t", target, "Enter"]);
}

export async function capturePane(target: string, lines = 200): Promise<string> {
  return run("tmux", ["capture-pane", "-p", "-J", "-t", target, "-S", `-${Math.max(1, Math.round(lines))}`]);
}
