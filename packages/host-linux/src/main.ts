#!/usr/bin/env bun
// lattices-host: expose this Linux desktop to other lattices machines (LAT-013).
//
//   lattices-host                      listen on the tailnet address and loopback
//   lattices-host --bind 127.0.0.1     loopback only
//   lattices-host --allow-user you@github --allow-tag tag:lattices
//   lattices-host --describe           print capabilities and exit

import { selfIdentity, type Policy } from "./auth.ts";
import { VERSION, capabilities, refreshCapabilities, registerEndpoints } from "./endpoints.ts";
import * as hypr from "./hyprland.ts";
import * as live from "./live.ts";
import { Router } from "./router.ts";
import { serve } from "./server.ts";

const DEFAULT_PORT = 9399;

function parseArgs(argv: string[]) {
  const opts = { binds: [] as string[], port: DEFAULT_PORT, allowUsers: [] as string[], allowTags: [] as string[], describe: false, quiet: false };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    const value = () => {
      const v = argv[++i];
      if (v === undefined) throw new Error(`${arg} needs a value`);
      return v;
    };
    if (arg === "--bind") opts.binds.push(value());
    else if (arg === "--port") opts.port = Number(value());
    else if (arg === "--allow-user") opts.allowUsers.push(value());
    else if (arg === "--allow-tag") opts.allowTags.push(value());
    else if (arg === "--describe") opts.describe = true;
    else if (arg === "--quiet") opts.quiet = true;
    else if (arg === "--version") {
      console.log(VERSION);
      process.exit(0);
    } else if (arg === "--help" || arg === "-h") {
      console.log(`lattices-host ${VERSION}

Usage: lattices-host [--bind ADDR]... [--port N] [--allow-user ID|LOGIN]... [--allow-tag TAG]... [--describe]

By default listens on this machine's tailnet IPv4 address and on 127.0.0.1,
port ${DEFAULT_PORT}, and admits only devices owned by this machine's Tailscale user.`);
      process.exit(0);
    } else throw new Error(`Unknown argument: ${arg}`);
  }
  return opts;
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  await refreshCapabilities();

  const router = new Router(() => capabilities);
  let clientCount = () => 0;
  const policy: Policy = { allowUsers: [...opts.allowUsers], allowTags: [...opts.allowTags] };

  let binds = opts.binds;
  let self: Awaited<ReturnType<typeof selfIdentity>> | null = null;
  try {
    self = await selfIdentity();
  } catch {
    self = null;
  }
  if (binds.length === 0) {
    const tailnet = self?.ips.find((ip) => ip.includes("."));
    binds = tailnet ? [tailnet, "127.0.0.1"] : ["127.0.0.1"];
  }
  if (policy.allowUsers.length === 0 && self) policy.allowUsers.push(self.userId);

  const primary = binds.find((b) => b !== "127.0.0.1") ?? binds[0];
  registerEndpoints(router, { bindHost: primary, tailnetName: self?.hostname, startedAt: Date.now(), clientCount: () => clientCount() });

  if (opts.describe) {
    console.log(JSON.stringify(await router.dispatch("host.describe", {}), null, 2));
    process.exit(0);
  }

  const log = (line: string) => {
    if (!opts.quiet) console.log(`[lattices-host] ${line}`);
  };
  const server = serve({ hosts: binds, port: opts.port, policy, router, log });
  clientCount = server.clientCount;

  // Hyprland events become the daemon's windows.changed / spaces.changed.
  let pending: ReturnType<typeof setTimeout> | null = null;
  const changed = new Set<string>();
  const stopEvents = hypr.onEvents((event) => {
    if (/^(openwindow|closewindow|movewindow|windowtitle|activewindow|changefloatingmode|fullscreen)/.test(event)) changed.add("windows.changed");
    if (/^(workspace|createworkspace|destroyworkspace|focusedmon|monitoradded|monitorremoved|moveworkspace)/.test(event)) changed.add("spaces.changed");
    if (changed.size === 0 || pending) return;
    pending = setTimeout(() => {
      for (const name of changed) server.broadcast(name, { source: "hyprland" });
      changed.clear();
      pending = null;
    }, 150);
  });

  log(`v${VERSION} listening on ${binds.map((b) => `ws://${b}:${opts.port}`).join(", ")}`);
  log(`capabilities: ${[...capabilities].sort().join(", ") || "none"}`);
  log(`admits: ${[...policy.allowUsers, ...policy.allowTags].join(", ") || "loopback only"}${self?.login ? ` (owner ${self.login})` : ""}`);

  const shutdown = () => {
    stopEvents();
    live.stop();
    server.stop();
    process.exit(0);
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
}

main().catch((err) => {
  console.error(`lattices-host: ${(err as Error).message}`);
  process.exit(1);
});
