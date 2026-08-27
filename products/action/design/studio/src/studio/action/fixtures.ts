/**
 * The window study needs a populated app, and a populated app is the only
 * honest way to judge a layout: an empty Runs page hides the fact that the
 * outcome column has to hold "Unfinished", and one scenario hides the switcher.
 *
 * Every field here exists on the real model — `ActionSessionSummary`,
 * `ActionScenarioStep`, `ActionToolCounts`. Nothing is invented for the
 * picture. Where the app has a fact the runtime does not write yet, the study
 * leaves the cell empty rather than filling it in.
 */

import type { Step } from "@/studio/action/Surface";

export type RunKind = "drive" | "inspection" | "capture";
export type Outcome = "ok" | "running" | "failed" | "stopped" | "unfinished";
/** Where this row's click lands. The column answers "did this leave anything". */
export type Destination = "take" | "trace" | "finder" | "none";

export type Session = {
  id: string;
  title: string;
  agent: string;
  kind: RunKind;
  outcome: Outcome;
  /** Local clock, as the ledger prints it. */
  clock: string;
  day: string;
  destination: Destination;
  /** Only takes carry these. */
  result?: string;
  duration?: string;
  notes?: number;
};

export const SESSIONS: Session[] = [
  { id: "run_8f21c4", title: "Calculator demo", agent: "Claude Code", kind: "drive", outcome: "ok", clock: "14:22", day: "Today", destination: "take", result: "= 42", duration: "0:05", notes: 1 },
  { id: "run_8f2109", title: "Finder window sweep", agent: "Claude Code", kind: "inspection", outcome: "ok", clock: "14:09", day: "Today", destination: "trace" },
  { id: "run_8f1e77", title: "Safari — open tab, read title", agent: "Claude Code", kind: "drive", outcome: "failed", clock: "13:51", day: "Today", destination: "trace" },
  { id: "run_8f1a02", title: "Menu bar snapshot", agent: "mira", kind: "capture", outcome: "ok", clock: "13:40", day: "Today", destination: "finder", duration: "0:02" },
  { id: "run_8f18b5", title: "Settings pane walk", agent: "Claude Code", kind: "drive", outcome: "stopped", clock: "11:58", day: "Today", destination: "take", result: "3 of 7 steps", duration: "0:11", notes: 2 },
  { id: "run_8ef930", title: "Calculator demo", agent: "Claude Code", kind: "drive", outcome: "ok", clock: "18:34", day: "Yesterday", destination: "take", result: "= 42", duration: "0:05" },
  { id: "run_8ef8a1", title: "Accessibility tree — Mail", agent: "Claude Code", kind: "inspection", outcome: "unfinished", clock: "18:20", day: "Yesterday", destination: "none" },
  { id: "run_8ef77c", title: "Terminal — run build", agent: "scout", kind: "drive", outcome: "ok", clock: "17:02", day: "Yesterday", destination: "take", result: "exit 0", duration: "1:47", notes: 4 },
  { id: "run_8ef510", title: "Desktop drape check", agent: "mira", kind: "capture", outcome: "ok", clock: "16:41", day: "Yesterday", destination: "finder", duration: "0:03" },
];

export const OUTCOME_LABEL: Record<Outcome, string> = {
  ok: "Completed",
  running: "Running",
  failed: "Failed",
  stopped: "Stopped",
  unfinished: "Unfinished",
};

/**
 * Status colours are their own family, separate from the three meaning colours.
 * These were three magic hexes that were also wrong — the app's green is
 * #218C54, not #3E7A4E, and a running row is amber, not coral. Coral means a
 * drive holds the machine right now; it does not mean "this list item is open".
 */
export const OUTCOME_COLOR: Record<Outcome, string> = {
  ok: "var(--act-status-ok)",
  running: "var(--act-status-running)",
  failed: "var(--act-status-failed)",
  stopped: "var(--act-status-stopped)",
  unfinished: "var(--act-ink-muted)",
};

/* ------------------------------------------------------------ permissions -- */

/**
 * The two permissions the app actually reads — `accessibilityStatus` and
 * `screenRecordingStatus` on ActionLauncherViewModel. There is no Automation
 * permission anywhere in the model; a study that draws one and then reports it
 * granted is inventing the very thing the page exists to be trusted about.
 *
 * Defaulted to a mixed state on purpose. All-granted is not the state a person
 * opens this page in — nobody goes to Permissions to confirm things work.
 */
export type PermissionStatus = "Granted" | "Denied" | "Unknown";

export const PERMISSIONS: { name: string; status: PermissionStatus; why: string }[] = [
  { name: "Accessibility", status: "Granted", why: "Driving windows and menus" },
  { name: "Screen Recording", status: "Denied", why: "Takes and snapshots" },
];

export const PERMISSIONS_OK = PERMISSIONS.every((p) => p.status === "Granted");

export const DESTINATION_LABEL: Record<Destination, string> = {
  take: "Take",
  trace: "Trace",
  finder: "Finder",
  // Empty, not a dash. The column's question is "did this leave anything I can
  // look at"; an empty cell is the honest answer and the fastest to scan down,
  // and a right-aligned em dash at 11px reads as a stray hyphen.
  none: "",
};

/* ------------------------------------------------------------ scenarios -- */

export const SCENARIOS = ["Calculator demo", "Safari tab walk", "Settings pane walk"];

export const PLAN: Step[] = [
  { index: 1, verb: "type", step: "Enter 12", target: "keyboard" },
  { index: 2, verb: "click", step: "Click plus", target: "calculator.operator.plus", note: "Calculator can be slow to open cold" },
  { index: 3, verb: "type", step: "Enter 30", target: "keyboard" },
  { index: 4, verb: "press-key", step: "Press equals", target: "calculator.operator.equals" },
];

/* ---------------------------------------------------------- tool counts -- */

export const TOOL_GROUPS: { title: string; items: { name: string; count: number }[] }[] = [
  { title: "Observe", items: [{ name: "snapshot", count: 41 }, { name: "ax", count: 18 }, { name: "ocr", count: 6 }, { name: "vision", count: 2 }] },
  { title: "Drive", items: [{ name: "begin", count: 23 }, { name: "aim", count: 88 }, { name: "play", count: 14 }, { name: "note", count: 61 }] },
  { title: "Act", items: [{ name: "execute", count: 96 }, { name: "resolve", count: 44 }] },
  { title: "Record", items: [{ name: "start", count: 12 }, { name: "stop", count: 12 }, { name: "status", count: 31 }] },
];

export const MCP_COMMAND = [
  "claude mcp add action -- action-agent stdio",
  "~/dev/lattices/products/action · dev.lattices.Action",
];
