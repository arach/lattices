import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { McpRouter } from "./router.ts";
import { TOOLSET_NAMES, loadToolsets } from "./registry.ts";

function packageVersion(): string {
  try {
    const manifest = JSON.parse(
      readFileSync(fileURLToPath(new URL("../../package.json", import.meta.url)), "utf8"),
    ) as { version?: string };
    return manifest.version ?? "0.0.0";
  } catch {
    return "0.0.0";
  }
}

/**
 * The config snippet for each harness. The load-bearing property is that none of
 * these contains a path: not to a checkout, not to a version-pinned plugin
 * cache. Resolution follows the installed `lattices` binary, so moving the repo
 * or bumping the version leaves agent config correct.
 */
const CONFIG_SNIPPETS: Record<string, string> = {
  claude: [
    "# ~/.claude.json, or:",
    "claude mcp add lattices -s user -- lattices mcp",
    "",
    '{ "mcpServers": { "lattices": { "command": "lattices", "args": ["mcp"] } } }',
  ].join("\n"),
  codex: [
    "# ~/.codex/config.toml",
    "",
    "[mcp_servers.lattices]",
    'command = "lattices"',
    'args = ["mcp"]',
  ].join("\n"),
  kimi: [
    "# ~/.kimi-code/ MCP config",
    "",
    '{ "mcpServers": { "lattices": { "command": "lattices", "args": ["mcp"] } } }',
  ].join("\n"),
};

export const MCP_USAGE = `
lattices mcp — run the lattices MCP server over stdio

  lattices mcp                          Serve every toolset (${TOOLSET_NAMES.join(", ")})
  lattices mcp --toolsets browser       Serve only the named toolsets
  lattices mcp --list                   List toolsets and tools, then exit
  lattices mcp --print-config <harness> Print the agent config snippet
                                        (${Object.keys(CONFIG_SNIPPETS).join(", ")})

Agent config should name the binary, never a path:

  { "command": "lattices", "args": ["mcp"] }
`.trim();

function parseToolsets(args: readonly string[]): string[] | undefined {
  const index = args.findIndex((arg) => arg === "--toolsets" || arg === "--toolset");
  if (index === -1) return undefined;
  const value = args[index + 1];
  if (!value || value.startsWith("-")) {
    throw new Error(`--toolsets needs a comma-separated list. Available: ${TOOLSET_NAMES.join(", ")}.`);
  }
  return value.split(",").map((name) => name.trim()).filter(Boolean);
}

export async function mcpCommand(args: readonly string[]): Promise<void> {
  if (args.includes("--help") || args.includes("-h") || args.includes("help")) {
    console.log(MCP_USAGE);
    return;
  }

  const printConfigIndex = args.indexOf("--print-config");
  if (printConfigIndex !== -1) {
    const harness = args[printConfigIndex + 1];
    if (!harness || !(harness in CONFIG_SNIPPETS)) {
      console.error(`Usage: lattices mcp --print-config <${Object.keys(CONFIG_SNIPPETS).join("|")}>`);
      process.exit(1);
    }
    console.log(CONFIG_SNIPPETS[harness]);
    return;
  }

  const selection = parseToolsets(args);
  const toolsets = await loadToolsets(selection);
  const router = new McpRouter(toolsets, packageVersion());

  if (args.includes("--list")) {
    for (const toolset of toolsets) {
      console.log(`${toolset.name}${toolset.title ? `  (${toolset.title})` : ""}`);
      for (const tool of toolset.tools) console.log(`  ${tool.name}`);
    }
    return;
  }

  // The router owns the process, so it owns the signals. Owner dies, browser
  // dies: the async path releases Chrome within each toolset's budget, and the
  // `exit` handler is the synchronous backstop for every path that skips it.
  let exiting = false;
  const stop = (reason: string) => {
    if (exiting) return;
    exiting = true;
    void router.shutdown(reason).then(() => process.exit(0));
  };
  for (const signal of ["SIGTERM", "SIGINT", "SIGHUP"] as const) {
    process.on(signal, () => stop(signal));
  }
  process.on("exit", () => router.shutdownSync());

  await router.start();
  await router.serve(Bun.stdin.stream(), (line) => process.stdout.write(line));

  // stdin closed: the harness that owned this server is gone.
  await router.shutdown("stdin-eof");
  process.exit(0);
}

if (import.meta.main) {
  mcpCommand(process.argv.slice(2)).catch((error) => {
    console.error(error instanceof Error ? error.stack ?? error.message : String(error));
    process.exit(1);
  });
}
