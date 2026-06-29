import assert from "node:assert/strict";

import latticesPiExtension, { LATTICES_TOOLS } from "../index.mjs";

const args = new Set(process.argv.slice(2));
const live = args.has("--live");
const noDaemon = args.has("--no-daemon");

const registeredTools = [];
const handlers = new Map();
const notifications = [];
const ctx = {
  cwd: process.cwd(),
  ui: {
    notify(message, level) {
      notifications.push({ message, level });
    },
  },
};

const pi = {
  registerTool(tool) {
    registeredTools.push(tool);
  },
  on(event, handler) {
    handlers.set(event, handler);
  },
};

latticesPiExtension(pi);
assert.equal(typeof handlers.get("session_start"), "function", "extension registers a session_start hook");
await handlers.get("session_start")({}, ctx);

const names = registeredTools.map((tool) => tool.name).sort();
for (const required of [
  "lattices_status",
  "lattices_api_schema",
  "lattices_windows_list",
  "lattices_window_place",
  "lattices_computer_window_state",
  "lattices_computer_launch_app",
  "lattices_computer_click",
  "lattices_call",
]) {
  assert.ok(names.includes(required), `registered ${required}`);
}
assert.equal(names.length, LATTICES_TOOLS.length, "registered tool count matches metadata");

if (!live && !noDaemon) {
  console.log(`Registered ${names.length} pi-lattices tools.`);
  console.log("Use --no-daemon to verify graceful daemon errors, or --live with `lattices app` running.");
  process.exit(0);
}

function tool(name) {
  const found = registeredTools.find((entry) => entry.name === name);
  assert.ok(found, `missing tool ${name}`);
  return found;
}

async function execute(name, params = {}) {
  return tool(name).execute(`smoke-${name}`, params, undefined, undefined, ctx);
}

if (noDaemon) {
  const result = await execute("lattices_status");
  assert.equal(result.isError, true, "daemon-down status returns isError");
  assert.match(result.content[0].text, /Start Lattices with: lattices app/);
  assert.ok(notifications.some((entry) => entry.level === "warning"), "warning notification emitted");
  console.log("No-daemon smoke passed: lattices_status returned friendly guidance instead of throwing.");
  process.exit(0);
}

const status = await execute("lattices_status");
if (status.isError) {
  console.error(status.content[0].text);
  process.exit(1);
}
console.log("lattices_status OK");

const staged = await execute("lattices_computer_launch_app", {
  app: "Finder",
  treatment: "stage",
  capture: false,
  source: "pi-lattices-smoke",
});
if (staged.isError) {
  console.error(staged.content[0].text);
  process.exit(1);
}
console.log("lattices_computer_launch_app staged OK");
console.log("Live smoke passed.");
