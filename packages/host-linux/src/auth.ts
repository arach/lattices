// Who may connect. The host listens only on its tailnet address, and each
// connection is identified with `tailscale whois`: by default only devices
// owned by the same Tailscale user as this machine get in. Loopback is
// trusted, like the Mac daemon, so local tools work without Tailscale.

import { run } from "./exec.ts";

export interface Identity {
  user: string;
  node: string;
  os?: string;
  local?: boolean;
}

export interface Policy {
  /** Tailscale user ids (numeric) or login names allowed in. Default: this machine's owner. */
  allowUsers: string[];
  /** Tailscale ACL tags (tag:foo) allowed in. */
  allowTags: string[];
}

interface WhoIs {
  Node?: { Name?: string; User?: number; Tags?: string[]; Hostinfo?: { OS?: string; Hostname?: string } };
  UserProfile?: { ID?: number; LoginName?: string };
}

export function isLoopback(address: string): boolean {
  const a = address.replace(/^::ffff:/, "");
  return a === "::1" || a.startsWith("127.");
}

export async function selfIdentity(): Promise<{ userId: string; login: string; ips: string[]; hostname: string }> {
  const status = JSON.parse(await run("tailscale", ["status", "--json"])) as {
    Self: { UserID: number; HostName: string; TailscaleIPs: string[] };
    User?: Record<string, { LoginName?: string }>;
  };
  const userId = String(status.Self.UserID);
  return {
    userId,
    login: status.User?.[userId]?.LoginName ?? "",
    ips: status.Self.TailscaleIPs,
    hostname: status.Self.HostName,
  };
}

/** Decide from a whois answer. Pure, so the rule is testable. */
export function admit(whois: WhoIs, policy: Policy): Identity | null {
  const userId = whois.Node?.User ?? whois.UserProfile?.ID;
  const login = whois.UserProfile?.LoginName ?? "";
  const tags = whois.Node?.Tags ?? [];
  const byUser =
    userId !== undefined &&
    tags.length === 0 &&
    (policy.allowUsers.includes(String(userId)) || (login !== "" && policy.allowUsers.includes(login)));
  const byTag = tags.some((t) => policy.allowTags.includes(t));
  if (!byUser && !byTag) return null;
  return {
    user: login || String(userId),
    node: whois.Node?.Hostinfo?.Hostname ?? whois.Node?.Name ?? "unknown",
    os: whois.Node?.Hostinfo?.OS,
  };
}

const cache = new Map<string, { at: number; identity: Identity | null }>();

export async function identify(address: string, policy: Policy): Promise<Identity | null> {
  if (isLoopback(address)) return { user: "local", node: "localhost", local: true };
  const ip = address.replace(/^::ffff:/, "");
  const hit = cache.get(ip);
  if (hit && Date.now() - hit.at < 60_000) return hit.identity;
  let identity: Identity | null = null;
  try {
    identity = admit(JSON.parse(await run("tailscale", ["whois", "--json", ip])) as WhoIs, policy);
  } catch {
    identity = null;
  }
  cache.set(ip, { at: Date.now(), identity });
  return identity;
}
