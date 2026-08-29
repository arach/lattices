import { appendFile, mkdir, readFile, rename, stat } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";

/**
 * One line per MCP tool call, appended after the call settles. Home reads this
 * to answer "what can an agent ask this Mac to do, and how often has it" with
 * measured numbers instead of a hand-written list. Nothing else consumes it, so
 * a lost line costs a count and never a tool call: every write is best-effort.
 */
export interface ToolLedgerEntry {
  at: string;
  /** Canonical tool name, e.g. `action.act.execute`. */
  tool: string;
  /**
   * The act kind for `action.act.execute` (`click`, `type`, …). The tool name
   * alone collapses every act into one row, which is the one distinction the
   * Actions panel exists to draw.
   */
  verb?: string;
  ok: boolean;
  ms: number;
  leaseId?: string;
}

/** Past this the file is rolled to `log.1.jsonl`, keeping at most two windows. */
const MAX_LEDGER_BYTES = 512 * 1024;

/**
 * `ACTION_TOOL_LEDGER_DIR` redirects the ledger. Tests set it so a test run
 * never lands fake calls in the counts Home shows the operator.
 */
export function toolLedgerDirectory(): string {
  const override = process.env.ACTION_TOOL_LEDGER_DIR;
  if (override && override.length > 0) {
    return override;
  }
  return join(homedir(), "Library/Application Support/Action/runtime/tools");
}

export function toolLedgerPath(): string {
  return join(toolLedgerDirectory(), "log.jsonl");
}

function previousToolLedgerPath(): string {
  return join(toolLedgerDirectory(), "log.1.jsonl");
}

/**
 * The act kind an entry should be filed under, or undefined for tools whose
 * name is already the whole story. Deliberately tolerant: a malformed argument
 * bag means an uncounted verb, not a thrown tool call.
 */
export function verbForTool(tool: string, args: unknown): string | undefined {
  if (tool !== "action.act.execute") {
    return undefined;
  }
  const action = (args as { action?: unknown } | undefined)?.action;
  const kind = (action as { kind?: unknown } | undefined)?.kind;
  return typeof kind === "string" && kind.length > 0 ? kind : undefined;
}

async function rollIfLarge(path: string): Promise<void> {
  try {
    const info = await stat(path);
    if (info.size < MAX_LEDGER_BYTES) {
      return;
    }
    await rename(path, previousToolLedgerPath());
  } catch {
    // No file yet, or a concurrent roll won. Either way the append below is
    // still correct.
  }
}

/**
 * Append one settled tool call. Never throws — a ledger failure must not turn a
 * successful tool call into an error the agent has to reason about.
 */
export async function recordToolCall(entry: ToolLedgerEntry): Promise<void> {
  try {
    await mkdir(toolLedgerDirectory(), { recursive: true });
    const path = toolLedgerPath();
    await rollIfLarge(path);
    await appendFile(path, `${JSON.stringify(entry)}\n`);
  } catch {
    // Best effort by design.
  }
}

/** Reads both windows, oldest first. Used by tests and diagnostics. */
export async function readToolLedger(): Promise<ToolLedgerEntry[]> {
  const entries: ToolLedgerEntry[] = [];
  for (const path of [previousToolLedgerPath(), toolLedgerPath()]) {
    let raw: string;
    try {
      raw = await readFile(path, "utf8");
    } catch {
      continue;
    }
    for (const line of raw.split("\n")) {
      if (!line.trim()) {
        continue;
      }
      try {
        entries.push(JSON.parse(line) as ToolLedgerEntry);
      } catch {
        // Torn final line from a crashed write.
      }
    }
  }
  return entries;
}
