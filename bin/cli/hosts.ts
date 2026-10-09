import { configuredHosts, discoverTailnetHosts, hostStatuses, HOSTS_FILE, resolveHost, callHost } from "../hosts.ts";
import { hasFlag } from "./helpers.ts";

/**
 * lats hosts [--discover] [--json]   list reachable lattices hosts (LAT-013)
 * lats hosts describe <name>         host.describe for one host
 */
export async function hostsCommand(args: string[]): Promise<void> {
  const json = hasFlag(args, "--json");
  if (args[0] === "describe") {
    const host = resolveHost(args[1]);
    console.log(JSON.stringify(await callHost(host, "host.describe"), null, 2));
    return;
  }
  let hosts = configuredHosts();
  if (hasFlag(args, "--discover")) {
    const names = new Set(hosts.map((h) => h.name));
    hosts = [...hosts, ...(await discoverTailnetHosts()).filter((h) => !names.has(h.name))];
  }
  const statuses = await hostStatuses(hosts);
  if (json) {
    console.log(JSON.stringify(statuses, null, 2));
    return;
  }
  for (const s of statuses) {
    const state = s.reachable ? "\x1b[32m●\x1b[0m" : "\x1b[31m○\x1b[0m";
    const detail = s.reachable ? `${s.platform ?? "?"}${s.capabilities ? `  ${s.capabilities.length} capabilities` : ""}` : `unreachable (${s.error})`;
    console.log(`${state} ${s.name.padEnd(14)} ${`${s.address}:${s.port}`.padEnd(22)} ${s.source.padEnd(8)} ${detail}`);
  }
  if (statuses.length === 1 && !hasFlag(args, "--discover")) {
    console.log(`\nAdd hosts in ${HOSTS_FILE} ({"hosts":{"archie":{"address":"archie"}}}), LATTICES_HOSTS=archie,..., or run with --discover.`);
  }
}
