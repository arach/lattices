import { expect, test } from "bun:test";

import {
  CONSOLE_LEVELS,
  DEFAULT_CONSOLE_LIMIT,
  MAX_CONSOLE_LIMIT,
  RECORDER_SOURCE,
  dedupeEntries,
  mergeEntries,
  normalizeLevel,
  parseConsoleRequest,
  readRecorderExpression,
  selectEntries,
  summarize,
  toConsoleEntry,
  type ConsoleEntry,
} from "./console.ts";

test("a bare request returns every level, newest-bounded", () => {
  expect(parseConsoleRequest({})).toEqual({ levels: CONSOLE_LEVELS, limit: DEFAULT_CONSOLE_LIMIT, clear: false });
});

test("an unknown level is named rather than dropped", () => {
  expect(() => parseConsoleRequest({ levels: ["error", "trace"] })).toThrow(/Unknown console level: trace/);
  expect(() => parseConsoleRequest({ levels: [] })).toThrow(/non-empty array/);
  expect(() => parseConsoleRequest({ limit: 0 })).toThrow(/between 1 and/);
  expect(() => parseConsoleRequest({ limit: MAX_CONSOLE_LIMIT + 1 })).toThrow(/between 1 and/);
});

test("Chrome's log levels are folded onto the console's", () => {
  // Log.entryAdded says "warning" and "verbose"; console says "warn" and "debug".
  expect(normalizeLevel("warning")).toBe("warn");
  expect(normalizeLevel("verbose")).toBe("debug");
  expect(normalizeLevel("severe")).toBe("error");
  expect(normalizeLevel(undefined)).toBe("log");
});

test("the newest entries survive the limit, because they explain the current state", () => {
  const entries: ConsoleEntry[] = Array.from({ length: 10 }, (_, index) => ({
    level: "log", source: "console", text: `line ${index}`,
  }));
  const selected = selectEntries(entries, { levels: CONSOLE_LEVELS, limit: 3, clear: false });
  expect(selected.map((entry) => entry.text)).toEqual(["line 7", "line 8", "line 9"]);
});

test("level filtering happens before the limit, so 3 errors are not hidden by 50 logs", () => {
  const entries: ConsoleEntry[] = [
    ...Array.from({ length: 50 }, (): ConsoleEntry => ({ level: "log", source: "console", text: "noise" })),
    { level: "error", source: "console", text: "boom" },
  ];
  const selected = selectEntries(entries, { levels: ["error"], limit: 5, clear: false });
  expect(selected).toEqual([{ level: "error", source: "console", text: "boom" }]);
});

test("the two sources merge in time order, and untimed entries keep their own order", () => {
  const page: ConsoleEntry[] = [
    { level: "log", source: "console", text: "second", at: 200 },
    { level: "error", source: "exception", text: "fourth", at: 400 },
  ];
  const log: ConsoleEntry[] = [
    { level: "error", source: "network", text: "third", at: 300 },
    { level: "warn", source: "chrome", text: "untimed-a" },
    { level: "warn", source: "chrome", text: "untimed-b" },
  ];
  expect(mergeEntries(page, log).map((entry) => entry.text))
    .toEqual(["untimed-a", "untimed-b", "second", "third", "fourth"]);
});

test("a clean page is stated as such, not merely implied by an empty list", () => {
  expect(summarize([])).toEqual({ errors: 0, warnings: 0, total: 0, clean: true });
  expect(summarize([
    { level: "error", source: "console", text: "x" },
    { level: "warn", source: "console", text: "y" },
    { level: "log", source: "console", text: "z" },
  ])).toEqual({ errors: 1, warnings: 1, total: 3, clean: false });
});

test("an Error object survives the trip out of the page as its stack", () => {
  expect(toConsoleEntry({ level: "error", text: "TypeError: x is not a function\\n  at foo" }, "console").text)
    .toContain("TypeError");
  // Non-string payloads must not come back as "[object Object]".
  expect(toConsoleEntry({ level: "log", text: { a: 1 } }, "console").text).toBe('{"a":1}');
});

test("the recorder never breaks the page it observes", () => {
  // Every capture path is wrapped, and the original console function is still
  // called, so a page's own logging behaviour is unchanged.
  expect(RECORDER_SOURCE).toContain("original.apply(console, arguments)");
  expect(RECORDER_SOURCE).toContain("catch (error) { /* never let observation break the page */ }");
  expect(RECORDER_SOURCE).toContain("unhandledrejection");
  // Installed once per tab; a second injection must be a no-op.
  expect(RECORDER_SOURCE).toContain("if (window.__latticesBrowserConsole) return;");
});

test("reading only clears the buffer when the caller asked it to", () => {
  expect(readRecorderExpression(true)).toContain("state.buffer.length = 0;");
  expect(readRecorderExpression(false)).not.toContain("state.buffer.length = 0;");
});

test("dedupeEntries collapses a failure both sources reported", () => {
  const entries = dedupeEntries([
    { level: "error", source: "unhandledrejection", text: "Error: boom", at: 1_000 },
    { level: "error", source: "exception", text: "Error: boom", at: 1_040 },
  ]);
  expect(entries).toHaveLength(1);
  expect(entries[0]!.repeated).toBe(2);
  expect(entries[0]!.source).toBe("unhandledrejection");
});

test("dedupeEntries keeps a line the page genuinely logged again later", () => {
  const entries = dedupeEntries([
    { level: "log", source: "console", text: "tick", at: 1_000 },
    { level: "log", source: "console", text: "tick", at: 9_000 },
  ]);
  expect(entries).toHaveLength(2);
  expect(entries[0]!.repeated).toBeUndefined();
});

test("dedupeEntries does not merge different levels", () => {
  const entries = dedupeEntries([
    { level: "warn", source: "console", text: "same", at: 1_000 },
    { level: "error", source: "console", text: "same", at: 1_010 },
  ]);
  expect(entries).toHaveLength(2);
});

test("the recorder ignores resource-load error events", () => {
  // Resource failures arrive as plain Events in the capture phase, with no
  // message, filename or line -- they used to record as "undefined (undefined:undefined)".
  expect(RECORDER_SOURCE).toContain("event.target !== window");
  expect(RECORDER_SOURCE).toContain("!event.error && !event.message");
});
