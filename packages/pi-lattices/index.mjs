import { daemonCall, daemonConfig, isDaemonUnavailable } from "./daemon-client.mjs";

const TOOL_PREFIX = "lattices_";
const DEFAULT_SOURCE = "pi-lattices";

const string = (description) => ({ type: "string", description });
const boolean = (description) => ({ type: "boolean", description });
const number = (description) => ({ type: "number", description });
const integer = (description) => ({ type: "integer", minimum: 1, description });
const optionalEnum = (values, description) => ({ type: "string", enum: values, description });
const object = (properties = {}, required = []) => ({
  type: "object",
  additionalProperties: false,
  properties,
  ...(required.length > 0 ? { required } : {}),
});

const treatment = optionalEnum(
  ["observe", "stage", "present", "execute"],
  "Lattices computer-use treatment. Pi tools default to stage where that avoids mutation."
);

const source = string("Calling surface label recorded in Lattices runs/traces. Defaults to pi-lattices.");
const dryRun = boolean("Legacy alias for treatment=stage where supported by the daemon.");
const capture = boolean("Whether Lattices should capture before/after artifacts when supported.");
const wid = integer("CGWindowID / kCGWindowNumber.");
const session = string("Lattices tmux/session name, such as myapp-a1b2c3.");
const app = string("macOS application name, such as Finder, Notes, Terminal, iTerm2, or Scout.");
const title = string("Optional window title substring for target selection.");
const x = number("Absolute screen X coordinate.");
const y = number("Absolute screen Y coordinate.");
const ratio = (description) => ({ type: "number", minimum: 0, maximum: 1, description });
const text = string("Text payload. Pass treatment=execute to actually insert it.");
const windowStateMode = optionalEnum(
  ["ax", "both", "screenshot"],
  "Snapshot mode. ax avoids Screen Recording; both includes AX plus screenshot capture; screenshot skips AX."
);

const emptyParams = object();
const runSourceParams = {
  source,
};
const targetParams = {
  wid,
  session,
  app,
  title,
};
const windowPointParams = {
  x,
  y,
  xRatio: ratio("Window-relative X ratio, where 0 is the left edge and 1 is the right edge."),
  yRatio: ratio("Window-relative Y ratio, where 0 is the top edge and 1 is the bottom edge."),
};
const computerBaseParams = {
  treatment,
  dryRun,
  capture,
  source,
};

export const LATTICES_TOOLS = [
  {
    name: `${TOOL_PREFIX}status`,
    method: "daemon.status",
    description: "Return Lattices daemon health, uptime, tracked windows, and tmux session counts.",
    parameters: emptyParams,
  },
  {
    name: `${TOOL_PREFIX}api_schema`,
    method: "api.schema",
    description: "Return the live Lattices daemon API schema for self-discovery.",
    parameters: emptyParams,
  },
  {
    name: `${TOOL_PREFIX}windows_list`,
    method: "windows.list",
    description: "List visible windows tracked by Lattices, including app/title/frame/session metadata.",
    parameters: emptyParams,
  },
  {
    name: `${TOOL_PREFIX}windows_search`,
    method: "windows.search",
    description: "Search windows by title, app, Lattices session tag, and optionally OCR text.",
    parameters: object({
      query: string("Search query."),
      ocr: boolean("Include OCR text in search. Defaults to true in the daemon."),
      limit: integer("Maximum results to return."),
    }, ["query"]),
  },
  {
    name: `${TOOL_PREFIX}window_get`,
    method: "windows.get",
    description: "Get one tracked window by CGWindowID.",
    parameters: object({ wid }, ["wid"]),
  },
  {
    name: `${TOOL_PREFIX}runs_list`,
    method: "runs.list",
    description: "List recent Lattices runs from the local run store.",
    parameters: object({
      limit: integer("Maximum runs to return. Daemon default is 20."),
    }),
  },
  {
    name: `${TOOL_PREFIX}runs_get`,
    method: "runs.get",
    description: "Inspect one Lattices run, including artifacts and trace events.",
    parameters: object({
      id: string("Run id, such as run_20260617-120000_a1b2c3."),
    }, ["id"]),
  },
  {
    name: `${TOOL_PREFIX}ocr_snapshot`,
    method: "ocr.snapshot",
    description: "Return current in-memory OCR results for visible windows.",
    parameters: emptyParams,
  },
  {
    name: `${TOOL_PREFIX}ocr_search`,
    method: "ocr.search",
    description: "Search Lattices OCR history or the live OCR snapshot.",
    parameters: object({
      query: string("FTS5 search query."),
      app: string("Optional application-name filter."),
      limit: integer("Maximum results to return. Daemon default is 50."),
      live: boolean("Search the live OCR snapshot instead of history."),
    }, ["query"]),
  },
  {
    name: `${TOOL_PREFIX}computer_window_state`,
    method: "computer.windowState",
    description: "Inspect a target window's Accessibility tree and return snapshot-local element ids for semantic computer use.",
    parameters: object({
      ...targetParams,
      mode: windowStateMode,
      capture: boolean("Capture a screenshot artifact. Defaults true for both/screenshot and false for ax."),
      maxDepth: integer("Maximum AX tree depth to traverse. Daemon default is 8."),
      maxElements: integer("Maximum elements to return. Daemon default is 250."),
      timeoutMs: integer("Traversal timeout in milliseconds. Daemon default is 1200."),
      source,
    }),
    defaultSource: DEFAULT_SOURCE,
  },
  {
    name: `${TOOL_PREFIX}window_focus`,
    method: "computer.focusWindow",
    description: "Resolve and focus/present a target window through Lattices computer-use runs. Defaults to treatment=stage; pass present or execute to focus.",
    parameters: object({
      ...targetParams,
      ...computerBaseParams,
    }),
    defaultTreatment: "stage",
    defaultSource: DEFAULT_SOURCE,
  },
  {
    name: `${TOOL_PREFIX}window_place`,
    method: "window.place",
    description: "Place a target window/session using Lattices' typed placement runtime and return the action receipt.",
    parameters: object({
      ...targetParams,
      display: integer("Target display index."),
      placement: {
        description: "Placement shorthand (left, right, maximize, grid:3x2:0,0, etc.) or typed placement object.",
        anyOf: [
          { type: "string" },
          { type: "object", additionalProperties: true },
        ],
      },
    }, ["placement"]),
  },
  {
    name: `${TOOL_PREFIX}capture_window`,
    method: "capture.screenshotWindow",
    description: "Capture a target window as a Lattices run artifact. Defaults to frontmost non-Lattices window if no target is provided.",
    parameters: object({
      ...targetParams,
      runId: string("Existing run id to append to."),
      filename: string("Optional artifact filename."),
      ...runSourceParams,
    }),
    defaultSource: DEFAULT_SOURCE,
  },
  {
    name: `${TOOL_PREFIX}computer_prepare`,
    method: "computer.prepare",
    description: "Resolve and stage/observe a safe terminal target for later computer-use actions without typing by default.",
    parameters: object({
      wid,
      tty: string("Specific terminal TTY."),
      app: string("Preferred terminal app, such as Terminal or iTerm2."),
      text: string("Optional text to stage in the run trace."),
      ...computerBaseParams,
    }),
    defaultTreatment: "stage",
    defaultSource: DEFAULT_SOURCE,
  },
  {
    name: `${TOOL_PREFIX}computer_launch_app`,
    method: "computer.launchApp",
    description: "Launch or focus a normal macOS app through a Lattices run. Defaults to treatment=stage; pass present or execute to launch/focus.",
    parameters: object({
      app,
      bundleId: string("Bundle identifier fallback for precise launch."),
      path: string("Explicit .app bundle path."),
      title,
      ...computerBaseParams,
    }, ["app"]),
    defaultTreatment: "stage",
    defaultSource: DEFAULT_SOURCE,
  },
  {
    name: `${TOOL_PREFIX}computer_click`,
    method: "computer.click",
    description: "Stage, present, or execute a window-relative click. Defaults to treatment=stage; pass execute to click.",
    parameters: object({
      ...targetParams,
      ...windowPointParams,
      button: optionalEnum(["left", "right", "secondary", "context"], "Mouse button. Defaults to left."),
      transport: optionalEnum(["auto", "ax", "accessibility", "pointer", "mouse", "hardware"], "Click transport. auto prefers AXPress when possible."),
      axLabel: string("Optional AX title/label hint, such as Send."),
      targetText: string("Optional visible target text hint."),
      noFocus: boolean("Require no-focus AX execution and disable pointer fallback."),
      label: string("Optional label recorded with the click/cursor target."),
      ...computerBaseParams,
    }),
    defaultTreatment: "stage",
    defaultSource: DEFAULT_SOURCE,
  },
  {
    name: `${TOOL_PREFIX}computer_type_window_text`,
    method: "computer.typeWindowText",
    description: "Type into a normal app window, optionally after a click. Defaults to treatment=stage; pass execute to insert text.",
    parameters: object({
      wid,
      app,
      title,
      text,
      enter: boolean("Press Enter after typing. Defaults to false."),
      send: boolean("Alias for enter in chat-style demos."),
      ...windowPointParams,
      ...computerBaseParams,
    }, ["text"]),
    defaultTreatment: "stage",
    defaultSource: DEFAULT_SOURCE,
  },
  {
    name: `${TOOL_PREFIX}computer_type_text`,
    method: "computer.typeText",
    description: "Insert text into a safe terminal through Lattices transports. Defaults to treatment=stage; pass execute to type.",
    parameters: object({
      wid,
      tty: string("Specific terminal TTY."),
      app: string("Preferred terminal app, such as Terminal or iTerm2."),
      text,
      enter: boolean("Press Enter after typing. Defaults to false."),
      transport: optionalEnum(["auto", "tmux", "pasteboard"], "Terminal text transport. Defaults to auto."),
      ...computerBaseParams,
    }, ["text"]),
    defaultTreatment: "stage",
    defaultSource: DEFAULT_SOURCE,
  },
  {
    name: `${TOOL_PREFIX}call`,
    method: null,
    description: "Escape hatch for calling any Lattices daemon method by name. Prefer typed lattices_* tools when available.",
    parameters: object({
      method: string("Daemon method name, such as windows.list or computer.prepare."),
      params: {
        type: "object",
        additionalProperties: true,
        description: "Method-specific JSON params.",
      },
      timeoutMs: {
        type: "integer",
        minimum: 1,
        description: "Optional per-call timeout in milliseconds.",
      },
    }, ["method"]),
    escapeHatch: true,
  },
];

export default function latticesPiExtension(pi) {
  pi.on("session_start", async (_event, ctx) => {
    for (const tool of LATTICES_TOOLS) {
      pi.registerTool(createPiTool(tool, ctx));
    }
  });
}

function createPiTool(definition, sessionContext) {
  return {
    name: definition.name,
    label: definition.name,
    description: definition.description,
    parameters: definition.parameters,
    async execute(_toolCallId, params = {}, _signal, _onUpdate, ctx) {
      const executionContext = ctx ?? sessionContext;
      const call = daemonRequestForTool(definition, params ?? {});

      try {
        const result = await daemonCall(call.method, call.params, call.options);
        return formatSuccess(result);
      } catch (error) {
        notifyError(executionContext, definition.name, error);
        return formatError(definition.name, error);
      }
    },
  };
}

function daemonRequestForTool(definition, params) {
  if (definition.escapeHatch) {
    const { method, params: callParams = null, timeoutMs } = params;
    return {
      method,
      params: callParams,
      options: timeoutMs ? { timeoutMs } : {},
    };
  }

  const callParams = { ...params };
  if (definition.defaultSource && callParams.source === undefined) {
    callParams.source = definition.defaultSource;
  }
  if (definition.defaultTreatment
    && callParams.treatment === undefined
    && callParams.dryRun === undefined) {
    callParams.treatment = definition.defaultTreatment;
  }

  return {
    method: definition.method,
    params: Object.keys(callParams).length === 0 ? null : callParams,
    options: {},
  };
}

function formatSuccess(result) {
  return {
    content: [{ type: "text", text: stringifyResult(result) }],
    details: result,
  };
}

function formatError(toolName, error) {
  const config = daemonConfig();
  const original = error instanceof Error ? error.message : String(error);
  const text = isDaemonUnavailable(error)
    ? [
        `Lattices daemon is not reachable at ws://${config.host}:${config.port}.`,
        "Start Lattices with: lattices app",
        "Then retry the Pi tool.",
        `Tool: ${toolName}`,
        `Original error: ${original}`,
      ].join("\n")
    : [
        `Lattices daemon returned an error for ${toolName}:`,
        original,
      ].join("\n");

  return {
    content: [{ type: "text", text }],
    details: {
      tool: toolName,
      daemon: `ws://${config.host}:${config.port}`,
      error: original,
      daemonUnavailable: isDaemonUnavailable(error),
    },
    isError: true,
  };
}

function notifyError(ctx, toolName, error) {
  if (!isDaemonUnavailable(error)) return;
  try {
    ctx?.ui?.notify?.(`pi-lattices: ${toolName} cannot reach the Lattices daemon. Start it with: lattices app`, "warning");
  } catch {
    // Notification is best-effort; tool output remains the source of truth.
  }
}

function stringifyResult(result) {
  if (result === undefined) return "undefined";
  if (typeof result === "string") return result;
  return JSON.stringify(result, null, 2);
}
