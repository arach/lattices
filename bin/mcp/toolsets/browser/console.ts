/**
 * "Did this page actually work?" answered without a screenshot.
 *
 * A page that failed to load captures as a blank white box, and a PNG cannot say
 * why. Two sources answer between them:
 *
 *   1. A page-side recorder, installed before the document parses, that keeps
 *      console calls, uncaught errors, and unhandled rejections in a bounded
 *      in-page ring. It lives in the page, so it survives between tool calls
 *      without holding a socket open, and it resets per document -- which is what
 *      "errors on this page" should mean.
 *   2. Chrome's Log domain, which replays what it has already stored when
 *      enabled. That is where the failures the page never saw live: blocked
 *      requests, 404s for subresources, CSP violations, mixed content.
 */

export type ConsoleLevel = "error" | "warn" | "info" | "log" | "debug";

export const CONSOLE_LEVELS: readonly ConsoleLevel[] = ["error", "warn", "info", "log", "debug"];

export const DEFAULT_CONSOLE_LIMIT = 50;
export const MAX_CONSOLE_LIMIT = 500;

/** Milliseconds to let Chrome replay stored Log entries after enabling. */
export const LOG_REPLAY_MS = 200;

export type ConsoleEntry = {
  level: ConsoleLevel;
  source: string;
  text: string;
  at?: number;
  url?: string;
  /** Set when the same entry arrived more than once; absent means exactly once. */
  repeated?: number;
};

export type ConsoleRequest = {
  levels: readonly ConsoleLevel[];
  limit: number;
  clear: boolean;
};

export function parseConsoleRequest(args: Record<string, unknown>): ConsoleRequest {
  let levels: readonly ConsoleLevel[] = CONSOLE_LEVELS;
  if (args.levels !== undefined) {
    if (!Array.isArray(args.levels) || args.levels.length === 0) {
      throw new Error(`levels must be a non-empty array drawn from ${CONSOLE_LEVELS.join(", ")}.`);
    }
    const unknown = args.levels.filter((level) => !CONSOLE_LEVELS.includes(level as ConsoleLevel));
    if (unknown.length > 0) {
      throw new Error(`Unknown console level${unknown.length > 1 ? "s" : ""}: ${unknown.join(", ")}.`);
    }
    levels = args.levels as ConsoleLevel[];
  }

  let limit = DEFAULT_CONSOLE_LIMIT;
  if (args.limit !== undefined) {
    if (typeof args.limit !== "number" || !Number.isInteger(args.limit) || args.limit < 1 || args.limit > MAX_CONSOLE_LIMIT) {
      throw new Error(`limit must be an integer between 1 and ${MAX_CONSOLE_LIMIT}.`);
    }
    limit = args.limit;
  }

  if (args.clear !== undefined && typeof args.clear !== "boolean") {
    throw new Error("clear must be a boolean.");
  }

  return { levels, limit, clear: args.clear === true };
}

/** Chrome's Log domain levels do not line up one-to-one with console's. */
export function normalizeLevel(value: unknown): ConsoleLevel {
  switch (value) {
    case "error":
    case "severe":
      return "error";
    case "warning":
    case "warn":
      return "warn";
    case "debug":
    case "verbose":
      return "debug";
    case "info":
      return "info";
    default:
      return "log";
  }
}

function text(value: unknown): string {
  if (typeof value === "string") return value;
  try {
    return JSON.stringify(value) ?? String(value);
  } catch {
    return String(value);
  }
}

export function toConsoleEntry(raw: Record<string, unknown>, fallbackSource: string): ConsoleEntry {
  return {
    level: normalizeLevel(raw.level),
    source: typeof raw.source === "string" ? raw.source : fallbackSource,
    text: text(raw.text).slice(0, 2_000),
    ...(typeof raw.at === "number" ? { at: raw.at } : {}),
    ...(typeof raw.url === "string" && raw.url ? { url: raw.url } : {}),
  };
}

/**
 * Merge the two sources into one time-ordered list. Entries without a timestamp
 * (Chrome replays some that way) keep their relative order at the front rather
 * than being sorted to an invented position.
 */
export function mergeEntries(page: readonly ConsoleEntry[], log: readonly ConsoleEntry[]): ConsoleEntry[] {
  const merged = [...page, ...log];
  return merged
    .map((entry, index) => ({ entry, index }))
    .sort((a, b) => {
      const at = (a.entry.at ?? 0) - (b.entry.at ?? 0);
      return at !== 0 ? at : a.index - b.index;
    })
    .map(({ entry }) => entry);
}

/** Merge, then collapse the double-reports the merge exposes. */
export function mergeAndDedupe(page: readonly ConsoleEntry[], log: readonly ConsoleEntry[]): ConsoleEntry[] {
  return dedupeEntries(mergeEntries(page, log));
}

/** How close two identical entries must be to count as one event double-reported. */
export const DEDUPE_WINDOW_MS = 1_500;

/**
 * An unhandled rejection reaches us twice -- once from the page recorder, once
 * from Runtime.exceptionThrown -- and Chrome replays some Log entries it also
 * emits live. Collapse identical text that lands within a moment of itself, and
 * count the collapses, so a page that genuinely logs the same line ten times over
 * a minute still reads as ten entries.
 */
export function dedupeEntries(entries: readonly ConsoleEntry[]): ConsoleEntry[] {
  const output: ConsoleEntry[] = [];
  for (const entry of entries) {
    const previous = output.find((candidate) =>
      candidate.level === entry.level
      && candidate.text === entry.text
      && Math.abs((candidate.at ?? 0) - (entry.at ?? 0)) <= DEDUPE_WINDOW_MS);
    if (previous) {
      previous.repeated = (previous.repeated ?? 1) + 1;
      continue;
    }
    output.push({ ...entry });
  }
  return output;
}

export function selectEntries(entries: readonly ConsoleEntry[], request: ConsoleRequest): ConsoleEntry[] {
  const wanted = new Set(request.levels);
  const matching = entries.filter((entry) => wanted.has(entry.level));
  // Keep the newest, because that is what explains the state the page is in now.
  return matching.slice(-request.limit);
}

export type ConsoleSummary = {
  errors: number;
  warnings: number;
  total: number;
  clean: boolean;
};

export function summarize(entries: readonly ConsoleEntry[]): ConsoleSummary {
  const errors = entries.filter((entry) => entry.level === "error").length;
  const warnings = entries.filter((entry) => entry.level === "warn").length;
  return { errors, warnings, total: entries.length, clean: errors === 0 };
}

export const RECORDER_KEY = "__latticesBrowserConsole";

/**
 * Installed with Page.addScriptToEvaluateOnNewDocument, so it is in place before
 * any page script runs. Everything it does is wrapped: a recorder that throws
 * inside a console call would break the page it is meant to observe.
 */
export const RECORDER_SOURCE = `(() => {
  if (window.${RECORDER_KEY}) return;
  var MAX = 200;
  var buffer = [];
  var push = function (entry) {
    buffer.push(entry);
    if (buffer.length > MAX) buffer.splice(0, buffer.length - MAX);
  };
  var text = function (value) {
    try {
      if (typeof value === "string") return value;
      if (value instanceof Error) return value.stack || (value.name + ": " + value.message);
      if (value === undefined) return "undefined";
      return JSON.stringify(value);
    } catch (error) { return String(value); }
  };
  var record = function (level, source, args) {
    try {
      push({
        level: level,
        source: source,
        text: Array.prototype.map.call(args, text).join(" ").slice(0, 2000),
        at: Date.now(),
        url: location.href
      });
    } catch (error) { /* never let observation break the page */ }
  };
  ["log", "info", "warn", "error", "debug"].forEach(function (level) {
    var original = console[level];
    if (typeof original !== "function") return;
    console[level] = function () {
      record(level, "console", arguments);
      return original.apply(console, arguments);
    };
  });
  window.addEventListener("error", function (event) {
    // Capture phase also sees resource-load failures, which are plain Events with
    // no message, filename or line. Recording those produced entries reading
    // "undefined (undefined:undefined)"; Chrome's Log domain reports the same
    // failures with a status code, so leave them to it.
    if (event.target && event.target !== window) return;
    if (!event.error && !event.message) return;
    record("error", "exception", [event.error || (event.message + " (" + event.filename + ":" + event.lineno + ")")]);
  }, true);
  window.addEventListener("unhandledrejection", function (event) {
    record("error", "unhandledrejection", [event.reason]);
  });
  window.${RECORDER_KEY} = {
    buffer: buffer,
    // Recorded at install time: "loading" means we were in place before the
    // document parsed, so the buffer is the page's whole history.
    fromDocumentStart: document.readyState === "loading"
  };
})()`;

export function readRecorderExpression(clear: boolean): string {
  return `(() => {
    var state = window.${RECORDER_KEY};
    if (!state) return { installed: false, url: location.href };
    var entries = state.buffer.slice();
    ${clear ? "state.buffer.length = 0;" : ""}
    return { installed: true, fromDocumentStart: state.fromDocumentStart === true, url: location.href, entries: entries };
  })()`;
}
