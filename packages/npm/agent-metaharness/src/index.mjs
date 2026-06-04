// @openscout/agent-metaharness — SDK surface.
//
// One uniform interface to instantiate and operate *any* harnessable agent
// (pi, codex, claude-code, opencode, echo) via @openscout/agent-sessions
// adapters. All per-harness details — binary discovery, RPC framing, env/auth,
// event normalization — are handled here so callers only deal with
// start → prompt → events → stop.
//
// Requires the Bun runtime: the underlying adapters use Bun.spawn.

import * as agentSessions from "@openscout/agent-sessions";
import { HARNESS_CATALOG, harnessById, resolveAgentExecutable } from "./catalog.mjs";

export * from "@openscout/agent-sessions";
export { HARNESS_CATALOG, harnessById, resolveAgentExecutable };

export const METAHARNESS_VERSION = "0.0.0";

// Map catalog adapter types → agent-sessions factories.
export function adapterFactories(pkg = agentSessions) {
  return {
    pi: pkg.createPiAdapter,
    codex: pkg.createCodexAdapter,
    "claude-code": pkg.createClaudeCodeAdapter,
    opencode: pkg.createOpencodeAdapter,
    echo: pkg.createEchoAdapter,
  };
}

// Describe the catalog with live binary availability.
export function describeCatalog(env = process.env) {
  return HARNESS_CATALOG.map((agent) => {
    const resolved = agent.builtin ? null : resolveAgentExecutable(agent, env);
    return {
      id: agent.id,
      name: agent.name,
      adapterType: agent.adapterType,
      builtin: Boolean(agent.builtin),
      available: Boolean(agent.builtin) || (resolved?.executable ?? false),
      binary: resolved?.path ?? null,
      binarySource: resolved?.source ?? (agent.builtin ? "builtin" : null),
    };
  });
}

export class Metaharness {
  constructor({ env = process.env } = {}) {
    this.env = env;
    this.registry = new agentSessions.SessionRegistry({ adapters: adapterFactories() });
    this.listeners = new Set();
    this.registry.onEvent((sequenced) => {
      for (const listener of this.listeners) listener(sequenced);
    });
  }

  onEvent(listener) {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  catalog() {
    return describeCatalog(this.env);
  }

  // Instantiate one agent session. `provider`/`model`/`systemPrompt` are
  // convenience top-level fields folded into adapter `options`.
  async start(harness, { sessionId, name, cwd, provider, model, systemPrompt, options } = {}) {
    const entry = harnessById(harness);
    if (!entry) {
      throw new Error(`Unknown harness: "${harness}". Known: ${HARNESS_CATALOG.map((h) => h.id).join(", ")}`);
    }
    const mergedOptions = { ...(options ?? {}) };
    if (provider !== undefined) mergedOptions.provider = provider;
    if (model !== undefined) mergedOptions.model = model;
    if (systemPrompt !== undefined) mergedOptions.systemPrompt = systemPrompt;

    return this.registry.createSession(entry.adapterType, {
      sessionId,
      name,
      cwd,
      env: this.env,
      options: mergedOptions,
    });
  }

  // Send a user turn to a live session.
  prompt({ sessionId, text, images }) {
    return this.registry.send({ sessionId, text, images });
  }

  // Interrupt an in-flight turn.
  interrupt(sessionId) {
    return this.registry.interrupt(sessionId);
  }

  async shutdown() {
    return this.registry.shutdown();
  }
}

export function createMetaharness(options) {
  return new Metaharness(options);
}
