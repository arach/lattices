"use client";

import { useState, type ReactNode } from "react";
import { PERMISSIONS, SESSIONS } from "@/studio/action/fixtures";
import { QuietButton } from "@/studio/action/Surface";

/**
 * Agents: the registry that writes itself, and the boundaries you draw on it
 * afterwards.
 *
 * Today an agent is a string. `Claude Code` appears in a table cell on Traces
 * and nowhere else, in an app whose entire purpose is supervising software that
 * moves your cursor and types into your apps. This page makes it an object with
 * standing.
 *
 * THE ONE MOVE. Settings gates the machine; Agents gates the agent. Settings'
 * readiness ledger says which of the four capabilities — Observe, Drive, Act,
 * Record — this Mac currently permits. This page says which of those each agent
 * may use, in the same four words, in fixed columns, so scope reads straight
 * down the registry. A capability is live for an agent only where the machine
 * has it *and* the agent is scoped for it, and the whole design is built around
 * drawing that intersection rather than describing it.
 *
 * THE ROW IS EVIDENCE AND POLICY ON ONE AXIS. Each capability is a lane. The
 * *baseline* of the lane is your decision — solid where the agent is scoped,
 * dotted where it is not. The *bar standing on that baseline* is what the agent
 * has actually done — its call count in that family, to the registry's own
 * scale. Cause and effect in one mark, which is what makes retrospective
 * scoping a gesture rather than a form: you look at what an agent has been
 * doing and take the line out from under it. The two states that matter are
 * both visible at a glance and neither could be shown by a history page and a
 * settings page standing side by side:
 *
 *   ink bar on a dotted baseline  — it has been doing something you no longer
 *                                   permit. Nothing else on the page looks
 *                                   like ink resting on nothing.
 *   solid baseline, empty lane    — you have granted something it has never
 *                                   once used. Over-granted, and silently.
 *
 * TWO MARKS, NOT ONE, AND THE STRIKE KEEPS SETTINGS' MEANING EXACTLY. Settings
 * strikes a tool that cannot run. Here a strike would be ambiguous — "you did
 * not permit it" and "the Mac cannot deliver it" are opposite facts with
 * opposite remedies, and one mark for both would be the page telling you to go
 * fix a permission when what happened is that you revoked something. So:
 * absence of a grant is drawn as *absence* — the baseline simply is not there,
 * dotted where it would have been. The strike is reserved, and it appears only
 * on a lane the agent is scoped for, because a strike is a broken promise and
 * there is no promise to break in a lane you never granted. That constraint is
 * what makes the two vocabularies compose instead of collide.
 *
 * COLOUR. Coral on the agent holding the lease right now, and nowhere else, as
 * everywhere else in this app. Amber on a pending capability request, because a
 * request from an agent that is waiting to act is the one thing on this page
 * that expires, and Settings already spends amber on "a run is still open".
 * Nothing else is coloured — the machine's denial is stated once in the meta
 * line under the headline rather than repeated as a red dot on every row it
 * touches.
 *
 * -------------------------------------------------------------------------
 * REAL, AND VERIFIED IN THE SOURCE BEFORE IT WAS DRAWN
 *
 * - Agent identity. `driver_identify` (packages/mcp/src/index.ts) sets a label
 *   for the connection; `inferDriverIdentity` in driver-identity.ts resolves one
 *   from `ACTION_DRIVER_LABEL`, `ACTION_AGENT_LABEL`, `OPENSCOUT_AGENT` or
 *   `CODEX_THREAD_ID`, and stamps the result with `source: handshake |
 *   environment | fallback`. That source is drawn on every expanded row.
 * - `Unidentified MCP caller` is a real string, not a placeholder: it is
 *   `inferDriverIdentity`'s fallback. The Swift lease reader has its own,
 *   `Unidentified agent`, for a record with an empty `agent`.
 * - An unidentified agent can drive today without ever naming itself. The MCP's
 *   act path calls `driveClient.begin({ agent: identity.agent, implicit: true })`
 *   when no lease is held, so the first `act.execute` opens a lease under
 *   whatever label was inferred. That row is not a hypothetical.
 * - The live lease: `agent`, `task`, `mode`, `startedAt`, `lastActAt`,
 *   `pointerControl`, `showSupervisionLabel` are all fields on `ActionHomeLease`
 *   (native/engine/Sources/ActionHomeSurface.swift). `pointerControl` defaults
 *   to false and is granted per drive at `drive.begin`, which is why the pointer
 *   row in POLICY says "asked per drive" as the present tense.
 * - Per-agent history is `SESSIONS` grouped by `agent` — computed below, not
 *   typed in.
 * - The approval seam. `ActionDriveLeaseStore.begin` already refuses
 *   `mode: "attention"` with a persisted denied lease and the reason "Attention
 *   mode requires operator approval, which is not available yet. Use background
 *   mode." The runtime has the slot, the denial and the record; what it does not
 *   have is the operator. This page is that operator.
 *
 * PROPOSED, AND MARKED AS SUCH AT EVERY CALL SITE
 *
 * - Per-agent capability scope, and therefore every lane baseline on the page.
 * - The request flow: an agent asking for a capability, and granting it as a
 *   scope change. The seam is real; the mechanism is invented here.
 * - Requiring `driver_identify` before driving. Today the MCP instructions say
 *   to call it "once when the connection label is not already supplied by the
 *   environment" — optional by construction.
 * - A pointer-control policy per agent, and what happens to an agent that has
 *   never been seen before.
 * - The per-agent split of the call counts. The totals are `TOOL_GROUPS`; the
 *   division between agents is not something the tool ledger records, because
 *   its entries carry `at`, `tool`, `verb` and `ok` and no lease id.
 *
 * There are no trust levels and no tiers on this page. A named trust level is a
 * word that stands in front of the four capabilities and hides which ones it
 * means; the four are already the vocabulary, and four lanes are shorter to
 * read than the sentence explaining what "trusted" was defined as this week.
 */

const mono = "var(--act-mono)";

/* ----------------------------------------------------------- local fixtures --
 * Everything in this block belongs in `fixtures.ts` beside `SESSIONS` and
 * `TOOL_GROUPS`; it lives here because that file is owned elsewhere this round.
 * Each one names what it maps onto in the runtime, and which parts the runtime
 * does not have yet.
 */

/**
 * The vocabulary, and it is deliberately Settings' vocabulary and not a new one.
 * Four families, in the app's own pipeline order: see, take the wheel, touch
 * something, keep a copy.
 */
const CAPABILITIES = ["Observe", "Drive", "Act", "Record"] as const;
type Capability = (typeof CAPABILITIES)[number];

/**
 * Which macOS permissions each family rests on, collapsed to family
 * granularity from the same trail Settings' `TOOL_GATES` documents tool by
 * tool. A lane is 56pt wide and cannot hold thirteen tool names, so the page
 * states the gates once and lets the lane carry the consequence.
 *
 * `full` is the gate every tool in the family needs; `partial` is a gate that
 * only some of them need, which is the difference between a family that goes
 * dark and one that goes thin. Observe keeps `ax` without Screen Recording;
 * Record keeps nothing, because `start` fails the preflight and `stop` and
 * `status` can then only answer about takes already on disk.
 */
const CAPABILITY_GATES: Record<Capability, { full: string | null; partial: string | null }> = {
  Observe: { full: null, partial: "Screen Recording" },
  Drive: { full: null, partial: "Accessibility" },
  Act: { full: "Accessibility", partial: null },
  Record: { full: "Screen Recording", partial: null },
};

/**
 * The tools each family contains, transcribed from `ActionToolLedger`'s own
 * lists in ActionHomeSurface.swift. Shown in an expanded row so "Observe" is
 * never a word the reader has to take on faith.
 */
const CAPABILITY_TOOLS: Record<Capability, string[]> = {
  Observe: ["snapshot", "resolve.target", "ax", "ocr", "vision"],
  Drive: ["begin", "aim", "note", "play", "release"],
  Act: ["click", "type", "press-key", "focus-window", "open-app", "scroll", "drag"],
  Record: ["record.start", "record.stop", "stage.set", "stage.clear"],
};

type IdentitySource = "handshake" | "environment" | "fallback";

type Agent = {
  name: string;
  /** `DriverIdentity.source`. The fallback case is the anonymous drive. */
  source: IdentitySource;
  /** How that label was arrived at, in the source's own terms. */
  sourceDetail: string;
  /** The task on the most recent lease — `ActionHomeLease.task`. */
  lastTask: string;
  /** Absent means dormant; present is the live lease, coral. */
  driving?: { elapsed: string; mode: string; lease: string; pointerControl: boolean; showSupervisionLabel: boolean };
  /** When this agent last held a lease. */
  lastSeen: string;
  firstSeen: string;
  /** PROPOSED. Nothing in the runtime stores a per-agent scope. */
  scope: Capability[];
  /**
   * Observed calls per family. The four column totals sum exactly to
   * `TOOL_GROUPS` — the totals are recorded, the split between agents is the
   * proposal. One seam worth naming: `TOOL_GROUPS` files `resolve` under Act
   * while `ActionToolLedger` files `resolve.target` under Observe, so the
   * counts here follow the fixture and the tool names in `CAPABILITY_TOOLS`
   * follow the Swift. Home already ruled that where the two disagree the Swift
   * wins; when this migrates, the fixture is the thing to fix.
   */
  used: Record<Capability, number>;
  /** `pointerControl` grants across this agent's leases: granted of asked. */
  pointer: { granted: number; of: number };
  /** PROPOSED: a capability this agent is waiting on you for. */
  request?: { capability: Capability; because: string; waiting: string };
};

/** `SESSIONS` grouped by `agent` — the only per-agent history the app has. */
const DRIVES = SESSIONS.reduce<Record<string, number>>((acc, s) => {
  acc[s.agent] = (acc[s.agent] ?? 0) + 1;
  return acc;
}, {});

const AGENTS: Agent[] = [
  {
    name: "Claude Code",
    source: "handshake",
    sourceDetail: "driver_identify",
    lastTask: "Add 12 and 30 in Calculator and read the result",
    driving: { elapsed: "02:14", mode: "background", lease: "8f21c4d0", pointerControl: true, showSupervisionLabel: true },
    lastSeen: "now",
    firstSeen: "6 Aug",
    scope: ["Observe", "Drive", "Act"],
    used: { Observe: 58, Drive: 149, Act: 140, Record: 6 },
    pointer: { granted: 4, of: 6 },
  },
  {
    name: "mira",
    source: "handshake",
    sourceDetail: "driver_identify",
    lastTask: "Desktop drape check",
    lastSeen: "Today 13:40",
    firstSeen: "11 Aug",
    // Scoped for Act and has never once used it: the over-granted case, and the
    // reason an empty lane with a solid baseline had to be a state of its own.
    scope: ["Observe", "Drive", "Act", "Record"],
    used: { Observe: 2, Drive: 11, Act: 0, Record: 49 },
    pointer: { granted: 0, of: 2 },
  },
  {
    name: "scout",
    source: "environment",
    sourceDetail: "OPENSCOUT_AGENT",
    lastTask: "Terminal — run build",
    lastSeen: "Yesterday 17:02",
    firstSeen: "14 Aug",
    scope: ["Observe", "Drive"],
    used: { Observe: 6, Drive: 24, Act: 0, Record: 0 },
    pointer: { granted: 0, of: 1 },
    request: {
      capability: "Act",
      because: "Click Send in the build report",
      waiting: "0:24",
    },
  },
  {
    // The anonymous drive, and it is a real state rather than a warning about
    // one: an MCP client that never calls driver_identify and sets none of the
    // environment labels still opens an implicit lease on its first act, under
    // this exact string.
    name: "Unidentified MCP caller",
    source: "fallback",
    sourceDetail: "no handshake, no environment label",
    lastTask: "focus-window",
    lastSeen: "2 days ago",
    firstSeen: "2 days ago",
    scope: [],
    used: { Observe: 1, Drive: 2, Act: 0, Record: 0 },
    pointer: { granted: 0, of: 0 },
  },
];

/**
 * The agent that has not arrived. Used only by the first-run page, so it can
 * draw a real row rather than a picture of one — an empty scope, no usage, and
 * therefore every lane in the state a first agent starts in.
 */
const NOBODY: Agent = {
  name: "",
  source: "fallback",
  sourceDetail: "",
  lastTask: "",
  lastSeen: "",
  firstSeen: "",
  scope: [],
  used: { Observe: 0, Drive: 0, Act: 0, Record: 0 },
  pointer: { granted: 0, of: 0 },
};

/** Local, because two of the four never appear in `SESSIONS`. */
const DRIVE_COUNT: Record<string, number> = {
  ...DRIVES,
  "Unidentified MCP caller": 1,
};

/**
 * PROPOSED, all three. These are the settings that are not about one agent, and
 * they sit on this page rather than in Settings because they are the defaults
 * every row above inherits — the question "what happens when an agent I have
 * never seen starts driving" is a question about the registry, and a person
 * with that question walks to the page where the agents are.
 *
 * Each carries what is true today, because two of the three describe behaviour
 * the runtime already has and would be changing.
 */
const POLICIES: { title: string; today: string; options: string[]; on: string }[] = [
  {
    title: "An agent with no standing starts driving",
    today: "Today it drives. The first act opens an implicit lease under whatever label was inferred.",
    options: ["Refuse", "Ask me", "Observe only"],
    on: "Ask me",
  },
  {
    title: "Identify before driving",
    today: "Today driver_identify is optional — the server asks for it only when the environment supplies no label.",
    options: ["Required", "Optional"],
    on: "Required",
  },
  {
    title: "Pointer control",
    today: "Today it is asked per drive at drive.begin and defaults to false; the lease records the grant.",
    options: ["Per drive", "Per agent", "Never"],
    on: "Per drive",
  },
];

/* ---------------------------------------------------------------- helpers -- */

const statusOf = (name: string) => PERMISSIONS.find((p) => p.name === name)?.status ?? "Unknown";

/**
 * What the machine can do about a capability, before any agent is considered.
 * `dark` is nothing survives, `thin` is the main path is gone and something
 * lesser remains — the same two states Settings marks as struck and dimmed,
 * lifted to family granularity.
 */
type MachineState = "full" | "thin" | "dark";

function machineState(c: Capability): MachineState {
  const { full, partial } = CAPABILITY_GATES[c];
  if (full && statusOf(full) === "Denied") return "dark";
  if (partial && statusOf(partial) === "Denied") return "thin";
  return "full";
}

/**
 * A lane's four states, which are the whole design.
 *
 * `open` is the only one that says something about your decision; the other
 * three all say the agent is scoped and differ on what the Mac can do about it.
 * That asymmetry is deliberate — a lane you did not grant has nothing further
 * to report.
 */
type LaneState = "open" | "granted" | "thin" | "dark";

function laneState(agent: Agent, c: Capability): LaneState {
  if (!agent.scope.includes(c)) return "open";
  const m = machineState(c);
  return m === "full" ? "granted" : m;
}

/** One scale for the whole registry, so a bar means the same thing on every row. */
const PEAK = Math.max(...AGENTS.flatMap((a) => CAPABILITIES.map((c) => a.used[c])));

/** Small counts are words in a 34pt sentence and numerals in a 9pt cell. */
const NUMBERS = ["No", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine"];
const spell = (n: number) => NUMBERS[n] ?? String(n);

/** "a, b and c" — Settings' own join, kept identical so the legends read alike. */
function list(names: string[]): string {
  if (names.length <= 1) return names[0] ?? "";
  return `${names.slice(0, -1).join(", ")} and ${names[names.length - 1]}`;
}

/* ------------------------------------------------------------------- page -- */

export type AgentsState = "registry" | "request" | "empty";

export function AgentsSection({ state = "registry" }: { state?: AgentsState } = {}) {
  // One open row at a time. Two open rows put two capability blow-ups on screen
  // at once and the lanes stop lining up with the column heads they belong to,
  // which is the one thing this page's structure is for.
  const [open, setOpen] = useState<string | null>(null);

  if (state === "empty") return <FirstRun />;

  const pending = state === "request" ? AGENTS.find((a) => a.request) : undefined;

  return (
    // The ledger measure, not Settings' 720. This page carries six columns and
    // four of them are lanes that have to be wide enough to hold a bar with a
    // readable length; at 720 the lanes fall to 38pt and every count above
    // about forty renders as the same full block.
    <div style={{ maxWidth: "var(--act-ledger-width)" }}>
      <PulseKeyframes />
      <Standing pending={pending} />

      <div style={{ marginTop: 24 }}>
        <ColumnHeads />
        {AGENTS.map((agent, i) => (
          <div key={agent.name}>
            {i > 0 && <div style={{ height: 1, background: "var(--act-rule-soft)" }} />}
            <AgentRow
              agent={agent}
              pending={pending?.name === agent.name ? pending.request : undefined}
              open={open === agent.name}
              onToggle={() => setOpen(open === agent.name ? null : agent.name)}
            />
          </div>
        ))}
        <div style={{ height: 1, background: "var(--act-rule-soft)" }} />
        <Legend />
      </div>

      <Policy />
    </div>
  );
}

/* --------------------------------------------------------------- standing -- */

/**
 * The page's opening line, and it follows Settings' readiness geometry exactly:
 * one 34pt sentence with the single primary action on its own baseline, a
 * full-measure rule under it, then a row of 9pt mono facts. Two pages that are
 * one idea seen from two ends should open the same way, and a reader who has
 * been to Settings already knows how to read this.
 *
 * The sentence is the most urgent true thing about the registry. At rest that
 * is its size — how many agents have standing here — and there is no button,
 * because a registry at rest asks nothing of its owner, exactly as idle Home
 * carries no page-scale control. When an agent is waiting on a decision the
 * sentence becomes the request and the button appears, which is the same trade
 * Settings makes when a permission is missing.
 */
function Standing({ pending }: { pending?: Agent }) {
  // A request is the only object on this page that can arrive while the
  // operator is somewhere else in the window, so the shell would need to carry
  // it: an amber mark on the Agents rail item, which is the one signal slot the
  // sidebar has left — blue is selection and coral is a live drive.
  const driving = AGENTS.find((a) => a.driving);

  return (
    <div style={{ marginTop: 8 }}>
      <div style={{ display: "flex", alignItems: "flex-end", gap: 20 }}>
        <span
          style={{
            fontSize: "var(--act-headline)",
            fontWeight: 300,
            letterSpacing: "var(--act-track-headline)",
            lineHeight: 1.12,
            color: "var(--act-ink)",
          }}
        >
          {pending ? (
            <>
              {/* The requesting agent's name is the subject of the sentence and
                  is set in the same weight as the rest of it. A bolded name
                  inside a 34/300 line reads as a link, and this line is not one. */}
              {pending.name} is asking to {pending.request!.capability.toLowerCase()}.
            </>
          ) : (
            `${spell(AGENTS.length)} agents have driven this Mac.`
          )}
        </span>
        <span style={{ flex: 1 }} />
        {pending && (
          <span style={{ flex: "0 0 auto", display: "flex", alignItems: "center", gap: 16, paddingBottom: 3 }}>
            {/* Refusing is text, not a second button — the same shape Settings
                gives "Check again". Both answers are one click; only one of
                them changes what this Mac will let happen, and that is the one
                that gets the frame. */}
            <span style={{ fontSize: "var(--act-caption)", color: "var(--act-ink-muted)", cursor: "pointer" }}>
              Refuse
            </span>
            <QuietButton>Grant {pending.request!.capability}</QuietButton>
          </span>
        )}
      </div>

      <div style={{ marginTop: 14, height: 1, background: "var(--act-rule)" }} />

      <div style={{ marginTop: 9, display: "flex", alignItems: "center", gap: 24, flexWrap: "wrap" }}>
        {pending ? (
          <>
            {/* Time is the first fact about a request because it is the only
                one that is changing while you read it: the agent is holding a
                background lease and doing nothing with it. */}
            <Fact label="WAITING" alert>
              {pending.request!.waiting}
            </Fact>
            <Fact label="FOR">{pending.request!.because}</Fact>
            {/* Granting here is a scope change, not a one-time pass, and the
                page has to say so before you press it rather than after. */}
            <Fact label="GRANTING">
              adds {pending.request!.capability} to {pending.name}&apos;s scope
            </Fact>
          </>
        ) : (
          <>
            <Fact label="DRIVING NOW">{driving ? driving.name : "nobody"}</Fact>
            <Fact label="SCOPED">
              {`${AGENTS.filter((a) => a.scope.length > 0).length} of ${AGENTS.length}`}
            </Fact>
          </>
        )}

        <span style={{ flex: 1 }} />

        {/* The machine's side of the composition, stated once for the whole
            page. Every struck lane below is caused by this line, and repeating
            the cause on each of them would be four copies of one fact — the
            habit Settings spent a round deleting.

            Set as a fact in sans rather than in tracked mono caps: at 9pt caps
            across sixty characters it was the loudest thing on a page whose
            subject is the rows underneath it, and it was shouting a fact that
            belongs to a different page. */}
        <MachineFact />
      </div>
    </div>
  );
}

/**
 * What this Mac takes away from every agent at once, in one sentence, drawn on
 * both the registry and the first-run page. Silent when the machine is whole,
 * because a page that congratulates you on nothing being wrong is furniture.
 */
function MachineFact() {
  const dark = CAPABILITIES.filter((c) => machineState(c) === "dark");
  const thin = CAPABILITIES.filter((c) => machineState(c) === "thin");
  const blocked = PERMISSIONS.filter((p) => p.status === "Denied");
  if (blocked.length === 0 || (dark.length === 0 && thin.length === 0)) return null;

  return (
    <Fact label="THIS MAC">
      {list(blocked.map((p) => p.name.toLowerCase()))} denied
      {dark.length > 0 && ` — ${list(dark)} dark`}
      {thin.length > 0 && `${dark.length > 0 ? ", " : " — "}${list(thin)} reduced`} for every agent
    </Fact>
  );
}

/** A labelled fact on paper. Label first at 9pt, value beside it at 12. */
function Fact({ label, children, alert = false }: { label: string; children: ReactNode; alert?: boolean }) {
  return (
    <span style={{ display: "inline-flex", alignItems: "baseline", gap: 8, minWidth: 0 }}>
      <span
        style={{
          fontFamily: mono,
          fontSize: "var(--act-label)",
          fontWeight: 600,
          letterSpacing: "var(--act-track-label)",
          textTransform: "uppercase",
          color: "var(--act-ink-muted)",
          flex: "0 0 auto",
        }}
      >
        {label}
      </span>
      <span
        style={{
          fontSize: "var(--act-body)",
          color: alert ? "var(--act-status-running)" : "var(--act-ink-2)",
          whiteSpace: "nowrap",
          overflow: "hidden",
          textOverflow: "ellipsis",
        }}
      >
        {children}
      </span>
    </span>
  );
}

/* ---------------------------------------------------------------- columns -- */

/* One grid string driving the heads and every row, for the reason `action.css`
   states: a column head over a different edge than its values is not a column.
   The lane block is fixed rather than fluid because the four lanes have to hold
   still under their four names while the agent column takes the slack. */
const LANE = 58;
const LANE_GAP = 10;
const LANE_H = 13;
/** The bar stands on the baseline; the strike crosses it at half height. */
const BAR_H = 7;
const LANES_W = LANE * 4 + LANE_GAP * 3;
/* LAST holds "Yesterday 17:02" at 11pt mono, which is 100pt and was the column
   that overran into DRIVES when it was sized by eye. */
const GRID = `3px minmax(200px, 1fr) ${LANES_W}px 48px 112px`;

const head = {
  fontFamily: mono,
  fontSize: "var(--act-label)",
  fontWeight: 600,
  letterSpacing: "var(--act-track-label)",
  textTransform: "uppercase",
  color: "var(--act-ink-muted)",
} as const;

function ColumnHeads() {
  return (
    <>
      <div style={{ display: "grid", gridTemplateColumns: GRID, alignItems: "center", paddingBottom: 7 }}>
        <span />
        <span style={{ ...head, paddingLeft: 9 }}>Agent</span>
        <div style={{ display: "flex", gap: LANE_GAP }}>
          {CAPABILITIES.map((c) => (
            // The capability names appear once, here, and the lanes below
            // inherit their positions. Printing four labels per row would have
            // cost more ink than the bars they label.
            <span key={c} style={{ ...head, width: LANE }}>
              {c}
            </span>
          ))}
        </div>
        <span style={{ ...head, textAlign: "right" }}>Drives</span>
        <span style={{ ...head, textAlign: "right", paddingRight: 10 }}>Last</span>
      </div>
      <div style={{ height: 1, background: "var(--act-rule)" }} />
    </>
  );
}

/* ------------------------------------------------------------------- row -- */

/**
 * One agent at rest: who it is, what it last said it was doing, its scope and
 * its usage on one axis, how many drives it has held, and when.
 *
 * Nothing here is a control except the row itself. The five facts are the five
 * an operator needs to decide whether this thing should keep its standing, and
 * each one is doing work: the name is the identity the runtime resolved, the
 * task is the promise it made at `drive.begin`, the lanes are the argument, the
 * drive count is how much evidence there is behind that argument, and the time
 * is whether any of it is still current. An agent seen once two days ago and an
 * agent holding the lease right now are the same object with different tenses,
 * so they get the same row and differ only in the tense column and the pulse.
 */
function AgentRow({
  agent,
  pending,
  open,
  onToggle,
}: {
  agent: Agent;
  pending?: Agent["request"];
  open: boolean;
  onToggle: () => void;
}) {
  const [hover, setHover] = useState(false);
  const live = Boolean(agent.driving);

  return (
    <div>
      <div
        onClick={onToggle}
        onMouseEnter={() => setHover(true)}
        onMouseLeave={() => setHover(false)}
        style={{
          display: "grid",
          gridTemplateColumns: GRID,
          alignItems: "center",
          // 34 rather than the window's 30. The lane is the row's content, not
          // a decoration on it, and a 12pt lane inside a 30pt row leaves the
          // bars touching the hairlines above and below them.
          minHeight: 34,
          cursor: "pointer",
          // The tint lands on the head only, never on the expansion — PlanRow's
          // rule, and the reason this page has no cards in it.
          background: open || hover ? "var(--act-row-hover)" : "transparent",
        }}
      >
        <span
          style={{
            width: 3,
            alignSelf: "stretch",
            background: open ? "var(--act-review-accent)" : "transparent",
          }}
        />

        <div style={{ display: "flex", alignItems: "center", gap: 8, minWidth: 0, paddingLeft: 9, paddingRight: 18 }}>
          {live ? (
            <Pulse />
          ) : (
            // The reserved slot. Without it the three dormant names start 16pt
            // left of the live one and the column has a step in it.
            <span style={{ width: 8, flex: "0 0 auto" }} />
          )}
          <span
            style={{
              fontSize: "var(--act-row)",
              fontWeight: 500,
              // An identity the runtime could not resolve is not a name, and
              // setting it in full ink beside three real ones would be the page
              // vouching for it.
              color: agent.source === "fallback" ? "var(--act-ink-muted)" : "var(--act-ink)",
              whiteSpace: "nowrap",
              flex: "0 0 auto",
            }}
          >
            {agent.name}
          </span>
          {/* The task sits against the name for the same reason Traces puts the
              agent against the title: apart they are two columns, together they
              are a sentence about whether this agent has been doing what it
              said it would. */}
          <span
            style={{
              fontSize: "var(--act-caption)",
              color: "var(--act-ink-muted)",
              whiteSpace: "nowrap",
              overflow: "hidden",
              textOverflow: "ellipsis",
              minWidth: 0,
            }}
          >
            {agent.lastTask}
          </span>
        </div>

        <div style={{ display: "flex", gap: LANE_GAP }}>
          {CAPABILITIES.map((c) => (
            <Lane
              key={c}
              state={laneState(agent, c)}
              used={agent.used[c]}
              requested={pending?.capability === c}
            />
          ))}
        </div>

        <span
          style={{
            textAlign: "right",
            fontFamily: mono,
            fontSize: "var(--act-caption)",
            color: "var(--act-ink-muted)",
            fontVariantNumeric: "tabular-nums",
          }}
        >
          {DRIVE_COUNT[agent.name] ?? 0}
        </span>

        {/* The only place on the page a dormant agent and a live one differ in
            words. Coral, because it is the same fact the Home console spends it
            on, reported from the other end. */}
        <span
          style={{
            textAlign: "right",
            paddingRight: 10,
            fontFamily: mono,
            fontSize: "var(--act-caption)",
            color: live ? "var(--act-coral)" : "var(--act-ink-muted)",
            fontVariantNumeric: "tabular-nums",
            whiteSpace: "nowrap",
          }}
        >
          {live ? agent.driving!.elapsed : agent.lastSeen}
        </span>
      </div>

      {open && <Detail agent={agent} pending={pending} />}
    </div>
  );
}

/**
 * The mark this page is built on.
 *
 * A 58pt lane, 12pt tall. The baseline along the bottom is your decision; the
 * bar standing on it is the agent's record. Both are drawn to the same edge and
 * the same origin, so the eye reads the relationship before it reads either
 * one.
 *
 * The four drawings, and why each is what it is:
 *
 *   open    dotted baseline, and the bar is still drawn in full ink if the
 *           agent has used the capability. Ink resting on a line that is not
 *           there is the whole point — the page must not quietly erase what an
 *           agent did just because you have since decided against it.
 *   granted solid baseline, solid bar. The quiet case.
 *   thin    solid baseline, hollow bar. The capability stands but what the
 *           machine can deliver of it is thinner than the record suggests, and
 *           a hollow bar says "this figure no longer buys what it bought"
 *           without claiming the capability is gone.
 *   dark    solid baseline, muted bar, struck through at bar height. Settings'
 *           strike, meaning what it means there: this cannot run. It appears
 *           only on a granted lane, because a strike is a broken promise.
 */
function Lane({ state, used, requested }: { state: LaneState; used: number; requested?: boolean }) {
  const bar = barWidth(used, LANE);
  const scoped = state !== "open";

  return (
    <div style={{ width: LANE, height: LANE_H, position: "relative", flex: "0 0 auto" }}>
      <div style={{ position: "absolute", left: 0, width: LANE, bottom: 0, height: 1, ...baseline(scoped) }} />

      {bar > 0 && <div style={{ position: "absolute", left: 0, bottom: 1, width: bar, height: BAR_H, ...fill(state) }} />}

      {state === "dark" && (
        <div
          style={{
            position: "absolute",
            left: 0,
            width: LANE,
            bottom: 1 + Math.floor(BAR_H / 2),
            height: 1,
            background: "var(--act-ink)",
          }}
        />
      )}

      {/* A request is drawn on the lane it is about, so the sentence at the top
          of the page and the row it concerns are one object rather than two
          announcements. Amber, and it is the only amber on the registry. */}
      {requested && (
        <span
          style={{
            position: "absolute",
            left: 0,
            top: 0,
            width: 5,
            height: 5,
            borderRadius: "50%",
            background: "var(--act-status-running)",
          }}
        />
      )}
    </div>
  );
}

/**
 * The three drawings a lane is made of, written once because the row and the
 * expanded row have to draw the identical mark at two widths. The moment they
 * were two copies of the same style block they were free to drift, which is the
 * same defect `action.css` records about column widths.
 */
function baseline(scoped: boolean) {
  return scoped
    ? { background: "var(--act-border-quiet)" }
    : {
        // Dotted rather than dashed, and lighter than a grant: an ungranted
        // lane is an absence, and an absence drawn at the strength of a grant
        // reads as a second kind of grant.
        backgroundImage:
          "repeating-linear-gradient(to right, var(--act-ink-muted) 0 1px, transparent 1px 3px)",
        opacity: 0.6,
      };
}

function fill(state: LaneState) {
  if (state === "thin") return { border: "1px solid var(--act-ink-2)" };
  // Under the strike the bar drops to a ghost of itself. At full ink the strike
  // read as a rule sitting on top of a live bar; at a quarter it reads as what
  // it is, a figure that no longer buys anything.
  if (state === "dark") return { background: "var(--act-ink)", opacity: 0.22 };
  return { background: "var(--act-ink)" };
}

/** One scale for every lane on the page, floored so a handful of calls is still
 *  a mark rather than nothing. Linear on purpose: a bar four pixels long beside
 *  one that fills its lane is the true reading of 6 calls against 149. */
function barWidth(used: number, width: number) {
  return used > 0 ? Math.max(4, Math.round((used / PEAK) * width)) : 0;
}

/**
 * The marks in words, generated from the registry's own state so it can never
 * describe a lane the table is not currently drawing. Settings' legend, same
 * shape, same voice.
 */
function Legend() {
  const overreach = AGENTS.filter((a) => CAPABILITIES.some((c) => laneState(a, c) === "open" && a.used[c] > 0));
  const idle = AGENTS.filter((a) => CAPABILITIES.some((c) => laneState(a, c) !== "open" && a.used[c] === 0));
  const dark = CAPABILITIES.filter((c) => machineState(c) === "dark");
  const thin = CAPABILITIES.filter((c) => machineState(c) === "thin");

  return (
    <div
      style={{
        marginTop: 11,
        fontSize: "var(--act-caption)",
        color: "var(--act-ink-muted)",
        lineHeight: 1.65,
        maxWidth: 720,
      }}
    >
      A bar is what the agent has called; the line under it is what you allow.{" "}
      {overreach.length > 0 && (
        <>
          <span style={{ color: "var(--act-ink-2)" }}>{list(overreach.map((a) => a.name))}</span>{" "}
          {overreach.length === 1 ? "has" : "have"} called something no longer scoped, so the bar stands
          on a dotted line.{" "}
        </>
      )}
      {idle.length > 0 && (
        <>
          <span style={{ color: "var(--act-ink-2)" }}>{list(idle.map((a) => a.name))}</span>{" "}
          {idle.length === 1 ? "holds" : "hold"} scope never used.{" "}
        </>
      )}
      {dark.length > 0 && (
        <>
          A <Struck>struck</Struck> lane is granted and this Mac cannot deliver it — {list(dark)}.{" "}
        </>
      )}
      {thin.length > 0 && <>A hollow bar is {list(thin)}, running on what survives the missing permission.</>}
    </div>
  );
}

function Struck({ children }: { children: ReactNode }) {
  return (
    <span style={{ color: "var(--act-ink-2)", textDecoration: "line-through", textDecorationThickness: 1 }}>
      {children}
    </span>
  );
}

/* -------------------------------------------------------------- expansion -- */

/**
 * What a row opens into, and what it deliberately does not.
 *
 * It does not open into this agent's traces. Traces is a whole section with a
 * filter strip, two views and a day structure, and rebuilding a worse copy of
 * it inside a 34pt row is how a window ends up with the same object drawn three
 * ways. It opens into one line out to Traces and stops.
 *
 * What it does open into is the scope decision at working size: the same four
 * lanes, wide enough to carry the count and the tool names inside the family,
 * with the grant stated in words on the right. The lane *is* the control —
 * clicking it in here is what moves the boundary. That is why the page needs no
 * checkbox, no switch and no third button style: the mark you read the policy
 * from is the mark you change it with.
 */
function Detail({ agent, pending }: { agent: Agent; pending?: Agent["request"] }) {
  return (
    // Bare paper, held by an indent that lands under the AGENT column — the
    // expansion belongs to the row, and a second ground under it would make it
    // a card.
    <div style={{ paddingLeft: 28, paddingTop: 4, paddingBottom: 18, display: "grid", gap: 14 }}>
      <div>
        {CAPABILITIES.map((c) => (
          <ScopeRow key={c} agent={agent} capability={c} requested={pending?.capability === c} />
        ))}
      </div>

      <div style={{ display: "flex", alignItems: "center", gap: 26, flexWrap: "wrap" }}>
        {/* `DriverIdentity.source` shown plainly. How this Mac came to believe
            the name at the top of the row is the first thing that matters about
            standing, and the runtime records it in three grades. Handshake
            needs no gloss — the word is the mechanism — so only the two weaker
            grades name where the label came from. */}
        <Fact label="IDENTITY">
          {agent.source === "handshake" ? agent.source : `${agent.source} · ${agent.sourceDetail}`}
        </Fact>
        <Fact label="FIRST SEEN">{agent.firstSeen}</Fact>
        {/* Pointer control today is a per-drive grant on the lease, so what the
            page can honestly show is the tally of those grants — not a policy,
            because there is no per-agent policy to read. */}
        <Fact label="POINTER">
          {agent.pointer.of === 0
            ? "never asked"
            : `granted on ${agent.pointer.granted} of ${agent.pointer.of} drives`}
        </Fact>
        {agent.driving && (
          <Fact label="LEASE">
            {agent.driving.lease} · {agent.driving.mode}
          </Fact>
        )}
        {/* The way out, and the only thing this expansion says about history
            beyond the bars: Traces is a section with a filter strip, two views
            and a day structure, and a worse copy of it inside a 34pt row is how
            a window ends up drawing one object three ways. It flows after the
            last fact rather than being pushed to the right edge — pinned right,
            it orphaned onto its own line the moment the facts wrapped. */}
        <span style={{ fontSize: "var(--act-caption)", color: "var(--act-ink-2)", cursor: "pointer" }}>
          {DRIVE_COUNT[agent.name] ?? 0} traces →
        </span>
      </div>
    </div>
  );
}

/**
 * One capability at working size. The lane runs to 200pt so a count of six and
 * a count of a hundred and forty are visibly different lengths, the tools
 * inside the family are named so the word above is never taken on faith, and
 * the grant is stated in words at the right edge — the marks are a shorthand
 * for scanning, not a code the reader has to have memorised to act.
 */
function ScopeRow({
  agent,
  capability,
  requested,
}: {
  agent: Agent;
  capability: Capability;
  requested?: boolean;
}) {
  const [hover, setHover] = useState(false);
  const state = laneState(agent, capability);
  const used = agent.used[capability];
  const width = 200;
  const bar = barWidth(used, width);
  const scoped = state !== "open";

  const verdict = requested
    ? "asking"
    : state === "open"
      ? "not granted"
      : state === "dark"
        ? "granted · this Mac cannot"
        : state === "thin"
          ? "granted · reduced"
          : "granted";

  return (
    <div
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      style={{
        display: "flex",
        alignItems: "center",
        gap: 16,
        height: 30,
        cursor: "pointer",
        background: hover ? "var(--act-row-hover)" : "transparent",
        borderTop: capability === CAPABILITIES[0] ? 0 : "1px solid var(--act-rule-soft)",
      }}
    >
      <span
        style={{
          width: 74,
          flex: "0 0 auto",
          fontSize: "var(--act-row)",
          fontWeight: scoped ? 600 : 400,
          color: scoped ? "var(--act-ink)" : "var(--act-ink-muted)",
        }}
      >
        {capability}
      </span>

      <div style={{ width, height: LANE_H, position: "relative", flex: "0 0 auto" }}>
        <div style={{ position: "absolute", left: 0, right: 0, bottom: 0, height: 1, ...baseline(scoped) }} />
        {bar > 0 && <div style={{ position: "absolute", left: 0, bottom: 1, width: bar, height: BAR_H, ...fill(state) }} />}
        {state === "dark" && (
          <div
            style={{
              position: "absolute",
              left: 0,
              right: 0,
              bottom: 1 + Math.floor(BAR_H / 2),
              height: 1,
              background: "var(--act-ink)",
            }}
          />
        )}
      </div>

      <span
        style={{
          width: 54,
          flex: "0 0 auto",
          fontFamily: mono,
          fontSize: "var(--act-caption)",
          color: used > 0 ? "var(--act-ink-2)" : "var(--act-ink-muted)",
          fontVariantNumeric: "tabular-nums",
        }}
      >
        {used > 0 ? `${used}` : "—"}
      </span>

      {/* The vocabulary underneath the word, muted, so "Act" is legible as
          seven verbs that touch your machine rather than as a category. */}
      <span
        style={{
          flex: 1,
          minWidth: 0,
          fontFamily: mono,
          fontSize: "var(--act-caption)",
          color: "var(--act-ink-muted)",
          whiteSpace: "nowrap",
          overflow: "hidden",
          textOverflow: "ellipsis",
        }}
      >
        {CAPABILITY_TOOLS[capability].join("  ·  ")}
      </span>

      <span
        style={{
          flex: "0 0 auto",
          paddingRight: 10,
          fontFamily: mono,
          fontSize: "var(--act-label)",
          fontWeight: 600,
          letterSpacing: "var(--act-track-label)",
          textTransform: "uppercase",
          whiteSpace: "nowrap",
          color: requested
            ? "var(--act-status-running)"
            : scoped
              ? "var(--act-ink-2)"
              : "var(--act-ink-muted)",
        }}
      >
        {verdict}
      </span>
    </div>
  );
}

/* ---------------------------------------------------------------- policy -- */

/**
 * The rules that are not about one agent.
 *
 * Drawn as Settings' group — a 9pt mono label, a rule to the measure, a
 * definition list under it — on purpose and not by habit: the reader has to see
 * that the registry above is a record and this is a setting, and borrowing the
 * shape of the page where settings live is the cheapest way to say so.
 *
 * Why here and not in Settings. Settings answers "what can this Mac do"; every
 * row on it is gated by macOS and fixed by a trip to System Settings. Nothing
 * below is: these are defaults about a class of agents, inherited by every row
 * above, and the question that brings someone to them — what happens the first
 * time something I have never seen starts moving my cursor — is a question
 * about the registry. Putting them at the foot of the registry also means the
 * first-run page has something true on it.
 */
function Policy() {
  return (
    <div style={{ marginTop: 32 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 8, paddingBottom: 7 }}>
        <span style={{ ...head, color: "var(--act-ink-2)" }}>Policy</span>
        <span style={{ flex: 1, height: 1, background: "var(--act-rule)" }} />
      </div>

      {POLICIES.map((p, i) => (
        <div key={p.title}>
          {i > 0 && <div style={{ height: 1, background: "var(--act-rule-soft)" }} />}
          <div
            style={{
              display: "grid",
              gridTemplateColumns: "minmax(240px, 300px) minmax(200px, 1fr) auto",
              alignItems: "center",
              gap: 24,
              minHeight: 44,
              paddingRight: 10,
            }}
          >
            <span style={{ fontSize: "var(--act-row)" }}>{p.title}</span>
            {/* What is true today, beside what you are choosing. Two of these
                three describe behaviour the runtime already has, and a policy
                control with no statement of the status quo is a switch whose
                off position is a guess. */}
            <span style={{ fontSize: "var(--act-caption)", color: "var(--act-ink-muted)", lineHeight: 1.5 }}>
              {p.today}
            </span>
            <Choice options={p.options} on={p.on} />
          </div>
        </div>
      ))}
    </div>
  );
}

/**
 * Settings' `ActionSegmentedControl`, token for token — 24 tall, the quiet
 * border every control in this window carries, `--act-row-open` under the
 * selected segment, dividers painted as segment borders so selecting never
 * re-lays the control. Sized to its contents here rather than to a fixed 220,
 * because these three controls have two, three and three options of very
 * different lengths and a common width would leave "Required / Optional"
 * floating in half a control.
 */
function Choice({ options, on }: { options: string[]; on: string }) {
  const [sel, setSel] = useState(on);
  return (
    <div
      style={{
        display: "flex",
        height: 24,
        borderRadius: 6,
        border: "1px solid var(--act-border-quiet)",
        overflow: "hidden",
        flex: "0 0 auto",
      }}
    >
      {options.map((o, i) => (
        <button
          key={o}
          type="button"
          onClick={() => setSel(o)}
          style={{
            padding: "0 12px",
            border: 0,
            borderLeft: i > 0 ? "1px solid var(--act-rule)" : 0,
            background: sel === o ? "var(--act-row-open)" : "transparent",
            cursor: "pointer",
            fontSize: "var(--act-caption)",
            fontWeight: sel === o ? 600 : 400,
            color: sel === o ? "var(--act-ink)" : "var(--act-ink-2)",
            whiteSpace: "nowrap",
          }}
        >
          {o}
        </button>
      ))}
    </div>
  );
}

/* -------------------------------------------------------------- first run -- */

/**
 * Before any agent has ever driven.
 *
 * There is no button here and there is nothing to add, because this registry is
 * observational: an agent appears in it because it ran. The honest first-run
 * page is therefore not an empty table with an invitation over it — it is the
 * page saying where its rows will come from, and then the one thing that *is*
 * decidable in advance, which is what happens to the first agent that arrives.
 * So Policy is not a footnote on this state; it is the whole page, and that is
 * the strongest argument that Policy belongs on Agents at all.
 *
 * Connecting an agent is not offered here. Home already owns that block for
 * exactly one install's lifetime, and a second copy of the MCP command would be
 * the third place one fact is drawn.
 */
function FirstRun() {
  return (
    <div style={{ maxWidth: "var(--act-ledger-width)" }}>
      <div style={{ marginTop: 8 }}>
        <span
          style={{
            fontSize: "var(--act-headline)",
            fontWeight: 300,
            letterSpacing: "var(--act-track-headline)",
            lineHeight: 1.12,
          }}
        >
          No agent has driven this Mac.
        </span>

        <div style={{ marginTop: 14, height: 1, background: "var(--act-rule)" }} />

        <div style={{ marginTop: 9, display: "flex", alignItems: "center", gap: 24 }}>
          <span style={{ ...head }}>The registry writes itself</span>
          <span style={{ flex: 1 }} />
          {/* The machine's limits are true before any agent exists, and they are
              the reason two of the four lanes below already carry a mark. */}
          <MachineFact />
        </div>

        <div
          style={{
            marginTop: 16,
            maxWidth: 520,
            fontSize: "var(--act-row)",
            color: "var(--act-ink-2)",
            lineHeight: 1.6,
          }}
        >
          An agent appears here the first time it drives, under the name it gives at{" "}
          <span style={{ fontFamily: mono, fontSize: "var(--act-caption)" }}>driver_identify</span> or
          the one its environment supplies. There is nothing to add by hand — you scope an agent
          after you have watched it work, not before.
        </div>

        {/* Not four empty lanes with their names over them: at 58pt with
            nothing on them they read as a dropped element rather than as a
            teaching device. This is the row a first agent will get, at the
            working size a row opens into — the four families with the verbs
            inside them, every lane ungranted, and the machine's own limits
            already applied. It teaches the mark before there is anything to
            read with it, and it is the honest answer to "what will the first
            agent be allowed": nothing, until you have watched it work. */}
        <div style={{ marginTop: 28 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 8, paddingBottom: 9 }}>
            <span style={{ ...head, color: "var(--act-ink-2)" }}>What an agent can be scoped for</span>
            <span style={{ flex: 1, height: 1, background: "var(--act-rule)" }} />
          </div>
          {CAPABILITIES.map((c) => (
            <ScopeRow key={c} agent={NOBODY} capability={c} />
          ))}
          <div
            style={{
              marginTop: 12,
              fontSize: "var(--act-caption)",
              color: "var(--act-ink-muted)",
              maxWidth: 620,
              lineHeight: 1.65,
            }}
          >
            The same four capabilities Settings gates on this Mac. Settings says what the machine
            permits; this page says what each agent may use of it.
          </div>
        </div>
      </div>

      <Policy />
    </div>
  );
}

/* ---------------------------------------------------------------- shared -- */

/** Home's live mark at row scale. It breathes for the same reason it does there. */
function Pulse() {
  return (
    <span style={{ position: "relative", width: 8, height: 8, flex: "0 0 auto", display: "inline-block" }}>
      <span
        style={{
          position: "absolute",
          inset: 0,
          borderRadius: "50%",
          background: "var(--act-coral)",
          animation: "act-pulse 2.4s ease-out infinite",
        }}
      />
      <span style={{ position: "absolute", inset: 0, borderRadius: "50%", background: "var(--act-coral)" }} />
    </span>
  );
}

function PulseKeyframes() {
  return (
    <style>{`@keyframes act-pulse {
      0%   { transform: scale(1);   opacity: 0.55; }
      70%  { transform: scale(2.6); opacity: 0; }
      100% { transform: scale(2.6); opacity: 0; }
    }`}</style>
  );
}
