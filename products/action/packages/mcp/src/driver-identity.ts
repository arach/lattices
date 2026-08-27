export interface DriverIdentity {
  agent: string;
  task?: string;
  source: "handshake" | "environment" | "fallback";
}

const clean = (value: string | undefined): string | undefined => {
  const result = value?.trim().replace(/\s+/g, " ");
  return result ? result.slice(0, 96) : undefined;
};

/** Resolve a stable label without pretending an unidentified caller is known. */
export function inferDriverIdentity(env: NodeJS.ProcessEnv = process.env): DriverIdentity {
  const explicit = clean(env.ACTION_DRIVER_LABEL ?? env.ACTION_AGENT_LABEL);
  if (explicit) {
    return {
      agent: explicit,
      task: clean(env.ACTION_DRIVER_TASK),
      source: "environment",
    };
  }

  const scout = clean(env.OPENSCOUT_AGENT);
  if (scout) {
    return { agent: scout, source: "environment" };
  }

  const codex = clean(env.CODEX_THREAD_ID);
  if (codex) {
    return { agent: `Codex ${codex.slice(0, 8)}`, source: "environment" };
  }

  return { agent: "Unidentified MCP caller", source: "fallback" };
}

export class DriverIdentityContext {
  private identity: DriverIdentity;

  constructor(env: NodeJS.ProcessEnv = process.env) {
    this.identity = inferDriverIdentity(env);
  }

  get(): DriverIdentity {
    return this.identity;
  }

  identify(agent: string, task?: string): DriverIdentity {
    const resolved = clean(agent);
    if (!resolved) {
      throw new Error("agent must be a non-empty human-readable label");
    }
    this.identity = {
      agent: resolved,
      task: clean(task),
      source: "handshake",
    };
    return this.identity;
  }
}
