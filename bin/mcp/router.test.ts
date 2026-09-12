import { expect, test } from "bun:test";

import { McpRouter } from "./router.ts";
import { TOOLSET_NAMES, loadToolsets } from "./registry.ts";
import type { JsonObject, Toolset } from "./types.ts";

function fakeToolset(name: string, toolNames: string[], calls: string[] = []): Toolset {
  return {
    name,
    tools: toolNames.map((tool) => ({
      name: tool,
      description: tool,
      inputSchema: { type: "object", properties: {}, additionalProperties: false },
    })),
    onToolCall(tool) {
      calls.push(`${name}:${tool}`);
    },
    async callTool(tool) {
      return { content: [{ type: "text", text: tool }] };
    },
  };
}

/**
 * These names appear verbatim in standing agent instructions across several
 * harnesses. Folding Action Browser into the lattices MCP moved the client-side
 * prefix; it must not have moved these.
 */
test("the browser tools keep the exact names agents are instructed to call", async () => {
  const [browser] = await loadToolsets(["browser"]);
  const names = browser!.tools.map((tool) => tool.name);
  for (const required of ["browser_open", "browser_screenshot", "browser_close"]) {
    expect(names).toContain(required);
  }
  const close = browser!.tools.find((tool) => tool.name === "browser_close")!;
  const scope = (close.inputSchema.properties as JsonObject).scope as JsonObject;
  expect(scope.enum).toEqual(["tab", "browser"]);
});

test("initialize reports the lattices server and carries toolset instructions", async () => {
  const router = new McpRouter([fakeToolset("a", ["a_one"])], "1.2.3");
  const response = await router.handleRequest({ jsonrpc: "2.0", id: 1, method: "initialize" });
  const result = (response as JsonObject).result as JsonObject;
  expect(result.serverInfo).toEqual({ name: "lattices", version: "1.2.3" });
});

test("two toolsets claiming one tool name is a startup error, not a coin flip", () => {
  expect(() => new McpRouter([fakeToolset("a", ["shared"]), fakeToolset("b", ["shared"])], "0"))
    .toThrow(/both define the tool "shared"/);
});

test("per-call bookkeeping is scoped to the toolset that owns the tool", async () => {
  const calls: string[] = [];
  const router = new McpRouter([fakeToolset("a", ["a_one"], calls), fakeToolset("b", ["b_one"], calls)], "0");
  await router.callTool("b_one", {});
  // The browser toolset's idle timer rides on this hook: a call into some other
  // toolset must not postpone the 15-minute close.
  expect(calls).toEqual(["b:b_one"]);
});

test("an unknown toolset fails loudly rather than serving an empty tool list", async () => {
  await expect(loadToolsets(["browsr"])).rejects.toThrow(/Unknown toolset: browsr/);
  expect(TOOLSET_NAMES).toContain("browser");
});

test("a failing tool call comes back as a readable result, not a protocol error", async () => {
  const router = new McpRouter([fakeToolset("a", ["a_one"])], "0");
  const response = await router.handleRequest({
    jsonrpc: "2.0",
    id: 7,
    method: "tools/call",
    params: { name: "a_missing", arguments: {} },
  }) as JsonObject;
  expect(response.error).toBeUndefined();
  const result = response.result as JsonObject;
  expect(result.isError).toBe(true);
  expect((result.structuredContent as JsonObject).error).toContain("Unknown tool: a_missing");
});

/**
 * Every documented default should be machine-readable. Prose-only defaults make a
 * caller either guess or send a value it did not need to send.
 */
test("every optional param that documents a default carries a schema default", async () => {
  const [browser] = await loadToolsets(["browser"]);
  const expected: Record<string, Record<string, unknown>> = {
    browser_open: { mode: "action", background: true, waitMs: 15_000, newTab: false },
    browser_snapshot: { maxTextChars: 12_000, maxElements: 80 },
    browser_click: { waitMs: 10_000, settle: "paint", waitForSelectorGone: false },
    browser_fill: { waitMs: 10_000, settle: "none", waitForSelectorGone: false },
    browser_resize: { target: "tab", deviceScaleFactor: 1, mobile: false, reset: false },
    browser_screenshot: { fullPage: false, includeImage: true, padding: 0 },
    browser_console: { limit: 50, clear: false, waitMs: 10_000 },
    browser_close: { scope: "tab" },
    browser_import_cookies: { confirm: false, listSourceProfiles: false },
  };

  for (const [toolName, defaults] of Object.entries(expected)) {
    const tool = browser!.tools.find((candidate) => candidate.name === toolName);
    expect(tool, `${toolName} is missing`).toBeDefined();
    const properties = tool!.inputSchema.properties as Record<string, JsonObject>;
    for (const [param, value] of Object.entries(defaults)) {
      expect(properties[param]?.default, `${toolName}.${param}`).toEqual(value);
    }
  }
});

test("browser_resize states the constraint its required list cannot express", async () => {
  const [browser] = await loadToolsets(["browser"]);
  const resize = browser!.tools.find((tool) => tool.name === "browser_resize")!;
  // "width and height are required unless reset is true" has no flat encoding, so
  // without this an empty call fails at runtime rather than at the schema.
  expect(resize.inputSchema.anyOf).toEqual([
    { required: ["width", "height"] },
    { required: ["reset"], properties: { reset: { const: true } } },
  ]);
});

test("an interaction can be given a postcondition to wait on", async () => {
  const [browser] = await loadToolsets(["browser"]);
  for (const toolName of ["browser_click", "browser_fill"]) {
    const tool = browser!.tools.find((candidate) => candidate.name === toolName)!;
    const properties = tool.inputSchema.properties as Record<string, JsonObject>;
    // Without these, an agent loop is click -> screenshot -> hope.
    expect(properties.settle?.enum).toEqual(["none", "paint", "navigation", "network-idle"]);
    expect(properties.waitForSelector).toBeDefined();
    expect(properties.waitMs).toBeDefined();
  }
});

test("a screenshot can name one element instead of the whole viewport", async () => {
  const [browser] = await loadToolsets(["browser"]);
  const shot = browser!.tools.find((tool) => tool.name === "browser_screenshot")!;
  const properties = shot.inputSchema.properties as Record<string, JsonObject>;
  expect(properties.selector).toBeDefined();
  expect(properties.clip).toBeDefined();
  expect(properties.padding).toBeDefined();
});
