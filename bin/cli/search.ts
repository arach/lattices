import { relativeTime } from "./helpers.ts";
import { withDaemon, type DaemonClient } from "./daemon.ts";

export interface SearchResult {
  score: number;
  window: any;
  tabs: { tab: number; cwd: string; title: string; hasClaude: boolean; tmuxSession: string }[];
  reasons: string[];
}

export interface SearchOptions {
  sources?: string[];
  after?: string;
  before?: string;
  recency?: boolean;
  mode?: string;
}

async function searchWithClient(client: DaemonClient, query: string, opts: SearchOptions = {}): Promise<SearchResult[]> {
  const { daemonCall } = client;
  const params: Record<string, any> = { query };
  if (opts.sources) params.sources = opts.sources;
  if (opts.after) params.after = opts.after;
  if (opts.before) params.before = opts.before;
  if (opts.recency !== undefined) params.recency = opts.recency;
  if (opts.mode) params.mode = opts.mode;
  const hits = await daemonCall("lattices.search", params, 10000) as any[];
  return hits.map((w: any) => ({
    score: w.score || 0,
    window: w,
    tabs: (w.terminalTabs || []).map((t: any) => ({
      tab: t.tabIndex, cwd: t.cwd, title: t.tabTitle, hasClaude: t.hasClaude, tmuxSession: t.tmuxSession,
    })),
    reasons: w.matchSources || [],
  }));
}

export async function search(query: string, opts: SearchOptions = {}): Promise<SearchResult[]> {
  return withDaemon(client => searchWithClient(client, query, opts));
}

export async function deepSearch(query: string): Promise<SearchResult[]> {
  return search(query, { sources: ["all"] });
}

export function printResults(ranked: SearchResult[]): void {
  if (!ranked.length) return;
  for (const r of ranked) {
    const w = r.window;
    const age = w.lastInteraction ? ` \x1b[2m${relativeTime(w.lastInteraction)}\x1b[0m` : "";
    console.log(`  \x1b[1m${w.app}\x1b[0m  "${w.title}"  wid:${w.wid}  score:${r.score}  (${r.reasons.join(", ")})${age}`);
    for (const t of r.tabs) {
      const claude = t.hasClaude ? " \x1b[32m●\x1b[0m" : "";
      const tmux = t.tmuxSession ? ` \x1b[36m[${t.tmuxSession}]\x1b[0m` : "";
      console.log(`    tab ${t.tab}: ${t.cwd || t.title}${claude}${tmux}`);
    }
    if (w.ocrSnippet) console.log(`    ocr: "${w.ocrSnippet}"`);
  }
  console.log();
}

export async function searchCommand(
  query: string | undefined,
  flags: Set<string>,
  rawArgs: string[] = []
): Promise<void> {
  if (!query) {
    console.log("Usage: lattices search <query> [--quick | --terminal | --all | --deep | --sources=... | --after=... | --before=... | --json | --wid]");
    return;
  }

  const opts: SearchOptions = {};

  const sourcesFlag = rawArgs.find(a => a.startsWith("--sources="));
  if (sourcesFlag) {
    opts.sources = sourcesFlag.slice("--sources=".length).split(",");
  } else if (flags.has("--all") || flags.has("--deep")) {
    opts.sources = ["all"];
  } else if (flags.has("--quick")) {
    opts.sources = ["titles", "apps", "sessions"];
  } else if (flags.has("--terminal")) {
    opts.sources = ["terminals"];
  }

  const afterFlag = rawArgs.find(a => a.startsWith("--after="));
  if (afterFlag) opts.after = afterFlag.slice("--after=".length);
  const beforeFlag = rawArgs.find(a => a.startsWith("--before="));
  if (beforeFlag) opts.before = beforeFlag.slice("--before=".length);

  if (flags.has("--no-recency")) opts.recency = false;

  const ranked = await search(query, opts);
  const jsonOut = flags.has("--json");
  const widOnly = flags.has("--wid");

  if (jsonOut) {
    console.log(JSON.stringify(ranked.map(r => ({
      wid: r.window.wid, app: r.window.app, title: r.window.title,
      score: r.score, reasons: r.reasons, tabs: r.tabs, ocrSnippet: r.window.ocrSnippet,
    })), null, 2));
    return;
  }

  if (widOnly) {
    for (const r of ranked) console.log(r.window.wid);
    return;
  }

  if (!ranked.length) {
    console.log(`No results for "${query}"`);
    return;
  }

  printResults(ranked);
}

export async function placeCommand(query?: string, tilePosition?: string): Promise<void> {
  if (!query) {
    console.log("Usage: lattices place <query> [position]");
    return;
  }

  await withDaemon(async (client) => {
    const { daemonCall } = client;
    const ranked = await searchWithClient(client, query, { sources: ["all"] });

    if (!ranked.length) {
      console.log(`No window matching "${query}"`);
      return;
    }

    const pos = tilePosition || "bottom-right";
    const win = ranked[0].window;
    await daemonCall("window.focus", { wid: win.wid });
    await daemonCall("intents.execute", {
      intent: "tile_window",
      slots: { position: pos, wid: win.wid }
    }, 3000);
    console.log(`${win.app} "${win.title}" (wid:${win.wid}) → ${pos}`);
  });
}