import { bringCursorHome, keepPointerSharing, pointerStatus, startPointerTrial, watchPointerTrial, type MouseDependencies } from "./mouse.ts";

export function parseMouseCommand(args: string[]) {
  const [command, ...options] = args;
  if (command === "mouse-share") {
    if (!options.length) return { command, duration: "5m" };
    if (options.length === 2 && options[0] === "--for" && options[1]) return { command, duration: options[1] };
    throw new Error("Usage: lattices-host mouse-share [--for 5m]");
  }
  if (command === "mouse-home" && options.length === 1 && options[0] === "--expired") return { command, expired: true };
  if (!["mouse-home", "mouse-keep", "mouse-status", "mouse-check"].includes(command)) throw new Error(`Unknown command: ${command}`);
  if (options.length) throw new Error(`Usage: lattices-host ${command}`);
  return { command };
}

export async function runMouseCommand(args: string[], deps?: MouseDependencies) {
  const command = parseMouseCommand(args);
  switch (command.command) {
    case "mouse-share": return startPointerTrial(command.duration, deps);
    case "mouse-keep": return keepPointerSharing(deps);
    case "mouse-status": return pointerStatus(deps);
    case "mouse-home": return bringCursorHome(deps, command.expired ? "expiry" : undefined);
    case "mouse-check": await watchPointerTrial(deps); return { ok: true };
  }
}
