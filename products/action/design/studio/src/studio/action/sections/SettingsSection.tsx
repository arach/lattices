"use client";

import { useState, type ReactNode } from "react";
import { CheckCircle2 } from "lucide-react";
import { PERMISSIONS, TOOL_GROUPS, type PermissionStatus } from "@/studio/action/fixtures";
import { Chip, QuietButton } from "@/studio/action/Surface";

/**
 * Settings is the page that teaches Action. Its eyebrow says SETUP and it now
 * answers all four of the questions a setup surface owes a person: what can this
 * Mac do right now, how does the thing work at all, what is the order of
 * operations the first time, and what do I do when it does not work.
 *
 * PROPOSAL, NOT TRANSCRIPTION — almost none of the page below exists in the
 * Swift. `settingsPermissionsPage` draws two rows with the word `Granted` or
 * `Denied` in them and a "Needs attention" banner above; the rest of the pane is
 * five more ruled bands of read-only facts. This page proposes replacing all of
 * that with a sentence, a ledger of the tool families, a taught model, a first
 * run, a troubleshooting list and a keyboard sheet.
 *
 * Why the readiness block leads. Action is not a preferences pane. Without Screen
 * Recording it cannot see the screen; without Accessibility it cannot touch
 * anything. The app is then not degraded, it is dark, and the previous layout
 * gave that fact one of seven equal bands — the same weight as `Bundle ID`. So
 * the page opens with a 34pt sentence naming the consequence, the permissions
 * demoted to a 9pt meta line, and a ledger showing which calls the missing grant
 * costs. That block is the reason Settings is worth a slot in the sidebar and
 * nothing may be placed above it.
 *
 * What this round adds, and why it was missing. The page could tell you Action
 * was dark and could hand you the MCP command, and then it stopped. It never said
 * what the machine *does* — an agent connects, takes a lease, drives while it
 * narrates beats, and everything it did is written to a trace — which is the one
 * model that explains every other surface in this window. Worth stating plainly:
 * that model is written down nowhere in the product, nowhere in `docs/*.md`, and
 * nowhere in `AGENTS.md` — which never uses the word lease at all. The one place
 * it is stated plainly is the `instructions` string the MCP server hands to
 * connecting agents. The agents have been told; the owner of the Mac has not.
 * HOW IT WORKS below is the first place a human is told, so it is authoring canon
 * rather than restating it, and every clause in it is sourced to Swift or to a
 * tool description.
 *
 * And it had no troubleshooting at all, anywhere in the app. The ledger catches
 * exactly one failure — a permission is missing — and every other way a drive
 * dies was undiagnosable from inside the product. The worst of them is silent:
 * Screen Recording has a hard preflight that throws a sentence with the word
 * "permission" in it, and Accessibility has no preflight anywhere, so a missing
 * Accessibility grant surfaces as `No accessibility windows found for <bundle>`,
 * which names no permission and reads like a bug in the target app. "The drive
 * begins and nothing moves" was the single most likely first experience of this
 * product and the app could not say a word about it.
 *
 * Where education sits, and why it moves. Education is wanted most when nothing
 * works yet and least once everything does, so it is not given a fixed slot: HOW
 * IT WORKS and FIRST RUN ride directly under the readiness block while any
 * permission is missing or unchecked, and drop below the two appearance choices
 * once the machine is ready. They are never removed. Help you cannot find on the
 * day it starts working is the bug this round exists to fix, and a person who has
 * granted everything still has four steps of the first run left to do.
 *
 * Troubleshooting and the keyboard sheet always sit low, because you arrive at
 * them by going looking. Troubleshooting opens the entry that matches this Mac's
 * current state rather than the first one — a machine with Screen Recording
 * denied is about to hit the relaunch trap, so that is the entry already open.
 *
 * The ledger is still the structural move underneath all of it. The app has a
 * vocabulary for what it can do — the tool families — and every one of those
 * tools is gated, or not gated, by exactly one of the two macOS permissions.
 * Drawing the families against their gates turns "Denied" into "these four calls
 * fail". `TOOL_GATES` below is the mapping, read out of the runtime rather than
 * assumed, with the source noted per tool.
 *
 * Also proposals, marked at their call sites: the segmented control's
 * Light / Dark / System order (`allCases` is System / Light / Dark); the Agent
 * group, which is the Swift's Runtime section with the MCP command moved into it
 * and Status dropped; the About colophon, which is the Swift's Action, Files and
 * Help sections drawn as one dense block; and the keyboard sheet, which the Swift
 * presents modally on ⌘/ and which is drawn here in the page instead.
 *
 * The page header, the gutter and the scroll come from the shell. This file owns
 * only the column.
 */

const mono = "var(--act-mono)";

type Permission = { name: string; status: PermissionStatus; why: string };

/**
 * What each permission costs when it is missing, as a verb phrase the headline
 * completes. The Swift's own `detail` strings are "Focus, click, type, read UI"
 * and "Screenshots and recording"; these say the same thing as a consequence
 * rather than as a feature list, because the headline's job is to tell someone
 * what their machine cannot do.
 *
 * PROPOSAL. Should migrate to `fixtures.ts` beside `PERMISSIONS`, so the studio
 * and any future copy review read one list.
 */
const CANNOT: Record<string, string> = {
  // Ordered, and the headline reads them in this order rather than in the
  // fixture's: seeing comes before driving, in the app's own pipeline and in the
  // sentence. "Cannot drive this Mac or see this screen" describes the same two
  // facts backwards.
  "Screen Recording": "see this screen",
  Accessibility: "drive this Mac",
};

export function SettingsSection({
  // Defaulted, so the window study renders the mixed state that ships in the
  // fixtures. The parameter exists so the all-granted state — the calm one — can
  // be drawn side by side with it in a scratch page without editing fixtures.
  permissions = PERMISSIONS,
}: {
  permissions?: Permission[];
} = {}) {
  // The one derived fact the whole page's ordering turns on. Unknown counts as
  // not ready on purpose: a Mac the app has not looked at is a Mac in setup, and
  // the person reading it needs the same help as one with a denied grant.
  const ready = permissions.every((p) => p.status === "Granted");

  return (
    // The measure lives in the token file so Settings and the ledger can be
    // re-measured together rather than one literal at a time. Left-pinned, not
    // centred: every page in this window reads down its left edge.
    <div style={{ maxWidth: "var(--act-settings-width)" }}>
      <Readiness permissions={permissions} />

      {/* Education earns its position rather than holding one. While anything is
          missing the page is a setup page and the model belongs directly under
          the sentence that says the machine is dark; once everything is granted
          the two genuine choices come first and the teaching drops below them.
          It is never removed — the four steps after "grant what it needs" are
          still ahead of a person whose permissions are all green, and help you
          cannot find on the day it starts working is the bug this page had. */}
      {!ready && <Teaching permissions={permissions} />}

      <Group title="Mode">
        <ModeGroup />
      </Group>

      <Group title="Theme">
        <ThemeGroup />
      </Group>

      <Group title="Agent">
        <AgentGroup />
      </Group>

      {/* The demoted slot is directly under AGENT rather than anywhere else in
          the tail, and that adjacency is the reason it is here and not below
          troubleshooting: the group above ends with the command that connects an
          agent, and the block below opens with the word AGENT and says what
          connecting one gets you. Read in sequence they are a sentence. */}
      {ready && <Teaching permissions={permissions} />}

      {/* Always low, in both states, because nobody scrolls to troubleshooting
          by accident — you arrive at it having already failed at something, and
          a symptom list above the theme picker would be the app leading with its
          own defects on the day everything works. */}
      <Group title="When it doesn't work">
        <Troubleshooting permissions={permissions} />
      </Group>

      <Group title="Keyboard">
        <KeyboardGroup />
      </Group>

      <Group title="About">
        <AboutColophon />
      </Group>
    </div>
  );
}

/* ------------------------------------------------------------- readiness -- */

/**
 * Every tool the four families contain, against the permission that gates it.
 *
 * Verified rather than assumed, and the trail is worth keeping because the
 * obvious guesses are wrong in both directions:
 *
 * - Screen Recording is a hard preflight. `shareableContent()` in
 *   ActionHostMain.swift guards on `screenRecordingStatus() == .granted` and
 *   throws, so every capture and every recording — `screenshot-app-window`,
 *   `record-app-window`, `record-region` — fails at the check rather than
 *   returning a blank frame.
 * - Accessibility has no preflight anywhere. The AX paths just fail at the API:
 *   `ActionNativeAutomation.accessibilityNodes` throws "No accessibility windows
 *   found", and the HID paths post CGEvents that an untrusted process cannot
 *   deliver. Same outcome, later and with a worse error.
 * - `resolve` is gated by nothing at all, because `MacOSCommandEngine.resolveTarget`
 *   echoes the query back and performs no lookup — its own comment says so. It
 *   survives every permission state, which is honest and slightly damning.
 * - `note`, `begin` and `aim` are Action's own overlay windows. Nothing about
 *   drawing a HUD on your own screen needs a macOS permission.
 *
 * `reduced` is the path that survives when the gate is denied. A tool with a
 * reduced path is dimmed rather than struck, and the legend under the ledger
 * prints the reduced paths in full — the marks are not a code the reader has to
 * carry.
 *
 * PROPOSAL. Should migrate to `fixtures.ts` next to `TOOL_GROUPS`, which is
 * where the tool names themselves already live.
 */
const TOOL_GATES: Record<string, { needs: string | null; reduced?: string }> = {
  // observe.snapshot → screenshot-app-window → shareableContent().
  snapshot: { needs: "Screen Recording" },
  // observe.ax → inspect-app-ui → ActionNativeAutomation.accessibilityNodes.
  ax: { needs: "Accessibility" },
  // Both take an `imagePath` and only capture when they are not given one, so
  // an image already on disk still goes through Vision or the provider.
  ocr: { needs: "Screen Recording", reduced: "read an image you already have" },
  vision: { needs: "Screen Recording", reduced: "read an image you already have" },

  begin: { needs: null },
  aim: { needs: null },
  note: { needs: null },
  // drive.play dispatches note, wait and aim itself and hands `act` beats to
  // act.execute, so the sequence runs and stops at the first beat that touches
  // anything.
  play: { needs: "Accessibility", reduced: "runs its note, aim and wait beats" },

  // Every verb but one is an AX call or a posted CGEvent. `open-app` is
  // NSWorkspace, which is why it is the survivor.
  execute: { needs: "Accessibility", reduced: "still opens an app" },
  resolve: { needs: null },

  start: { needs: "Screen Recording" },
  // stop and status make no capture call of their own — they write a stop file
  // and read the finished marker. They are dimmed rather than live because
  // `resolveRecording` also loads takes off disk: with no new take possible,
  // what they answer about is the ones already there.
  stop: { needs: "Screen Recording", reduced: "answer for takes already on disk" },
  status: { needs: "Screen Recording", reduced: "answer for takes already on disk" },
};

type ToolState = "live" | "reduced" | "dark" | "unknown";

/**
 * The block the page opens with, and the only reason Settings is worth a slot in
 * the sidebar.
 *
 * The order is consequence, then mechanism, then cost: a sentence saying what
 * this Mac cannot do, the permission that caused it demoted to a mono meta line
 * at a third the size, and then the ledger showing exactly which calls that buys
 * you. The button sits on the headline's own line because it is the answer to it.
 */
function Readiness({ permissions }: { permissions: Permission[] }) {
  const statusOf = (name: string) =>
    permissions.find((p) => p.name === name)?.status ?? "Unknown";

  const denied = permissions.filter((p) => p.status === "Denied");
  const unknown = permissions.filter((p) => p.status === "Unknown");
  const blocked = permissions.filter((p) => p.status !== "Granted");

  const headline = denied.length
    ? `Action cannot ${Object.keys(CANNOT)
        .filter((name) => denied.some((p) => p.name === name))
        .map((name) => CANNOT[name])
        .join(" or ")}.`
    : unknown.length
      ? "Action has not checked what it can do here."
      : // Not a boast and not a summary of the ledger under it: the two verbs are
        // the two permissions, so the calm state still says which facts it rests
        // on. Short enough to hold one line at the 720pt measure.
        "Action can see and drive this Mac.";

  // One primary action per state, and it is always the same action — the Swift's
  // `requestPermissions` asks for both in one pass, so the label narrows to the
  // single missing one when there is only one.
  const action = denied.length
    ? denied.length === 1
      ? `Grant ${denied[0].name}`
      : "Grant both"
    : unknown.length
      ? "Check permissions"
      : null;

  const rows = TOOL_GROUPS.map((group) => {
    const tools = group.items.map((item) => {
      // `TOOL_GROUPS` carries a week's call count per tool. Not read here: how
      // often a tool was used last week is not evidence about whether it works
      // now, and mixing the two is what made the old Home panel a capability
      // list wearing a leaderboard's clothes.
      const gate = TOOL_GATES[item.name] ?? { needs: null };
      const status = gate.needs === null ? "Granted" : statusOf(gate.needs);
      // Unknown is its own state and never borrows Denied's marks. Striking a
      // tool through because the app has not looked yet would be the page
      // telling someone their machine is broken on no evidence, which is the
      // one failure this rewrite cannot afford.
      const state: ToolState =
        status === "Granted"
          ? "live"
          : status === "Unknown"
            ? "unknown"
            : gate.reduced
              ? "reduced"
              : "dark";
      return { name: item.name, gate, state };
    });
    // Named in the order the tools introduce them, so the first gate listed is
    // the one that holds up the first tool.
    const gates: string[] = [];
    for (const tool of tools) {
      if (tool.gate.needs && !gates.includes(tool.gate.needs)) gates.push(tool.gate.needs);
    }
    // Damaged, not empty: Observe keeps `ax` under a denied Screen Recording and
    // Record keeps its two file readers, so a dimmed row still has to be legible.
    // The test is any tool off its main path, not only the ones that fail
    // outright — a Drive whose `play` cannot act is not a Drive in full health,
    // and drawing its name in full ink beside a red dot said two things at once.
    const dark = tools.some((t) => t.state !== "live");
    return { title: group.title, tools, gates, dark };
  });

  const struck = rows.flatMap((r) => r.tools.filter((t) => t.state === "dark"));
  const dimmed = rows.flatMap((r) => r.tools.filter((t) => t.state === "reduced"));

  return (
    // 8 under the shell header's own 16. The headline is larger than the page
    // title above it and lighter than everything else on the page, so it needs
    // enough air to read as the page's opening statement rather than as a
    // second, competing title.
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
          {headline}
        </span>
        <span style={{ flex: 1 }} />
        {/* Page-scale, so 30pt QuietButton. The whole page has one of these and
            it only exists when something is wrong. */}
        {action && (
          <span style={{ flex: "0 0 auto", paddingBottom: 3 }}>
            <QuietButton>{action}</QuietButton>
          </span>
        )}
      </div>

      {/* Home's cadence rule: a full-measure hairline directly under the one
          line the page opens with, so the sentence reads as a heading rather
          than as the first line of a paragraph. */}
      <div style={{ marginTop: 14, height: 1, background: "var(--act-rule)" }} />

      <div style={{ marginTop: 9, display: "flex", alignItems: "center", gap: 26 }}>
        {permissions.map((p) => (
          <PermissionMeta key={p.name} permission={p} />
        ))}
        <span style={{ flex: 1 }} />
        {/* Text, not a second button. Re-checking is not the thing this page is
            asking you to do, and in the state where it is — Unknown — it is the
            primary above instead. */}
        {/* Hidden in the one state where the primary button is already the
            same verb. Two ways to re-check, eleven points apart, is the third
            rung the app spent a round deleting. */}
        {action !== "Check permissions" && (
          <span
            style={{
              fontSize: "var(--act-caption)",
              color: "var(--act-ink-muted)",
              cursor: "pointer",
            }}
          >
            Check again
          </span>
        )}
      </div>

      <div style={{ marginTop: 20 }}>
        <Table
          // The tools column is capped rather than fluid. Thirteen mono words
          // never fill a 720pt measure, so a `1fr` here opened a four-inch hole
          // in the middle of every row and pushed `Needs` onto an edge nothing
          // else in the window shares. Capped at 300 the two live columns sit
          // next to each other and the slack falls where slack belongs, at the
          // end of the line.
          columns="104px minmax(200px, 300px) 1fr"
          headers={["Capability", "Tools", "Needs"]}
          rows={rows.map((row) => [
            // The name of a damaged capability recedes with its tools, so the
            // four rows sort themselves into live and dark before anyone reads a
            // word of them. This is the whole reason the ledger is a table: two
            // rows in full ink, two rows greyed, and the ink in the greyed ones
            // has moved to the right-hand column that says why.
            <span
              key="n"
              style={{
                fontSize: "var(--act-row)",
                fontWeight: 600,
                color: row.dark ? "var(--act-ink-muted)" : "var(--act-ink)",
              }}
            >
              {row.title}
            </span>,
            <div key="t" style={{ display: "flex", alignItems: "center", gap: 13 }}>
              {row.tools.map((t) => (
                <ToolName key={t.name} name={t.name} state={t.state} />
              ))}
            </div>,
            <span key="g" style={{ display: "flex", alignItems: "center", gap: 10 }}>
              {/* Drawn in every state, granted included: which permission a
                  capability needs is a fact about the capability, not a status.
                  Only the missing one is drawn as news.
                  The interpunct is Home's own separator for a run of mono
                  tokens — two tracked caps strings with only a gap between them
                  read as one string. */}
              {row.gates.map((gate, i) => (
                <span key={gate} style={{ display: "inline-flex", alignItems: "center", gap: 10 }}>
                  {i > 0 && <span style={{ color: "var(--act-ink-muted)" }}>·</span>}
                  <GateName name={gate} status={statusOf(gate)} />
                </span>
              ))}
            </span>,
          ])}
        />
      </div>

      {(struck.length > 0 || dimmed.length > 0) && (
        <Legend struck={struck} dimmed={dimmed} />
      )}
    </div>
  );
}

/**
 * `Granted` / `Denied` / `Unknown` are the only three strings
 * `permissionStatusLabel` can return, so they are the only three that may appear
 * here — at 9pt mono, under a 34pt sentence that already said what they mean.
 */
function PermissionMeta({ permission }: { permission: Permission }) {
  const failed = permission.status === "Denied";
  return (
    <span
      style={{
        display: "inline-flex",
        alignItems: "center",
        gap: 7,
        fontFamily: mono,
        fontSize: "var(--act-label)",
        fontWeight: 600,
        letterSpacing: "var(--act-track-label)",
        textTransform: "uppercase",
        color: "var(--act-ink-muted)",
      }}
    >
      {permission.name}
      {/* No mark up here. The sentence above already said what the missing
          permission costs, and the ledger below marks the capabilities it costs
          it to — a third statement of the same fact on the same screen is the
          habit this page exists to break. */}
      <span style={{ color: failed ? "var(--act-ink)" : "var(--act-ink-2)" }}>
        {permission.status}
      </span>
    </span>
  );
}

/**
 * The permission a capability rests on, in the `Needs` column.
 *
 * Granted or Unknown it is muted structure; denied it is ink with a dot, and
 * those dots are the only colour on the page. There is one per damaged
 * capability, which is the count that means something: a person scanning the
 * column is counting what they have lost, not how many permissions exist.
 */
function GateName({ name, status }: { name: string; status: PermissionStatus }) {
  const failed = status === "Denied";
  return (
    <span
      style={{
        display: "inline-flex",
        alignItems: "center",
        gap: 6,
        fontFamily: mono,
        fontSize: "var(--act-label)",
        fontWeight: 600,
        letterSpacing: "var(--act-track-label)",
        textTransform: "uppercase",
        whiteSpace: "nowrap",
        color: failed ? "var(--act-ink)" : "var(--act-ink-muted)",
      }}
    >
      {failed && (
        <span
          style={{
            width: 6,
            height: 6,
            borderRadius: "50%",
            flex: "0 0 auto",
            background: "var(--act-status-failed)",
          }}
        />
      )}
      {name}
    </span>
  );
}

/**
 * Three weights of one word and no colour: normal for a tool that works, dimmer
 * for one that has lost its main path, dimmer and struck for one that fails.
 *
 * The strike is drawn in the word's own ink rather than in a hairline from the
 * rule ladder: a strike is not a rule, it is part of the word, and at
 * `--act-border-quiet` over 11pt mono it was so faint that a dead tool and a
 * working one looked the same from two feet away — which is the one thing this
 * ledger may not do.
 */
function ToolName({ name, state }: { name: string; state: ToolState }) {
  return (
    <span
      style={{
        fontFamily: mono,
        fontSize: "var(--act-caption)",
        color: state === "live" ? "var(--act-ink-2)" : "var(--act-ink-muted)",
        textDecoration: state === "dark" ? "line-through" : "none",
        textDecorationThickness: 1,
      }}
    >
      {name}
    </span>
  );
}

/**
 * The marks explained in words, and only while there is something to explain.
 *
 * Written out of the state rather than hard-coded, so it can never describe a
 * tool the ledger above is not currently marking. The reduced paths are grouped
 * by what survives, because "ocr and vision read an image you already have" is
 * one fact and printing it twice would read as two.
 */
function Legend({
  struck,
  dimmed,
}: {
  struck: { name: string }[];
  dimmed: { name: string; gate: { reduced?: string } }[];
}) {
  const byPath = new Map<string, string[]>();
  for (const tool of dimmed) {
    const path = tool.gate.reduced!;
    byPath.set(path, [...(byPath.get(path) ?? []), tool.name]);
  }

  return (
    <div
      style={{
        marginTop: 11,
        fontSize: "var(--act-caption)",
        color: "var(--act-ink-muted)",
        lineHeight: 1.6,
      }}
    >
      {struck.length > 0 && (
        <>
          <Struck>{list(struck.map((t) => t.name))}</Struck> fail at the permission
          check.{" "}
        </>
      )}
      {byPath.size > 0 && (
        <>
          {[...byPath.entries()].map(([path, names], i) => (
            <span key={path}>
              {i > 0 && "; "}
              <span style={{ color: "var(--act-ink-2)" }}>{list(names)}</span> {path}
            </span>
          ))}
          .
        </>
      )}
    </div>
  );
}

function Struck({ children }: { children: ReactNode }) {
  return (
    <span
      style={{
        color: "var(--act-ink-2)",
        textDecoration: "line-through",
        textDecorationThickness: 1,
      }}
    >
      {children}
    </span>
  );
}

/** "a, b and c" — an Oxford-less join, because this is a sentence and not a cell. */
function list(names: string[]): string {
  if (names.length <= 1) return names[0] ?? "";
  return `${names.slice(0, -1).join(", ")} and ${names[names.length - 1]}`;
}

/* -------------------------------------------------------------- teaching -- */

/**
 * The two education groups, kept adjacent and moved as one.
 *
 * They are a pair rather than two independent blocks: the model names the four
 * words — agent, lease, drive, trace — and the first run is the same four words
 * in the imperative, with the page and the app told where each one happens. Read
 * in that order they are one lesson; separated by the theme picker they would be
 * two unrelated tables that happen to share a vocabulary.
 */
function Teaching({ permissions }: { permissions: Permission[] }) {
  return (
    <>
      <Group title="How it works">
        <Model />
      </Group>
      <Group title="First run">
        <FirstRun permissions={permissions} />
      </Group>
    </>
  );
}

/**
 * The model, in the app's own four words.
 *
 * Sourced, clause by clause, and worth stating where from: there is no prose
 * definition of a lease anywhere in `docs/*.md`, and `AGENTS.md` never uses the
 * word. The one place this model is stated plainly is the `instructions` string
 * `packages/mcp/src/index.ts` hands to every connecting agent — "Before multi-step UI work, call action.drive.begin with an agent
 * identity and short task. Pass the returned leaseId to observe and act calls,
 * then call action.drive.release when the work ends." The agents have been told.
 * The owner of the Mac has not. Everything below is read out of
 * `ActionDriveLeaseStore.swift`, the tool descriptions, and `persistDriveSession`.
 *
 * Two things are deliberately not claimed. A lease is *not* exclusive — the store
 * counts `activeCount` and several can be driving at once — so this says what a
 * lease contains rather than what it excludes. And `attention` mode is named
 * nowhere here except as the constraint under the diagram, because `drive.begin`
 * denies it in every case today.
 */
const MODEL: { stage: string; line: string; call: string }[] = [
  {
    stage: "Agent",
    // `driver.identify` — "Set a stable human-readable identity for implicit
    // drive leases on this MCP connection."
    line: "An MCP client connects to Action over a local socket and says which agent it is.",
    call: "driver.identify",
  },
  {
    stage: "Lease",
    // `drive.begin` — "Announce that an automation client is driving the Mac and
    // show its identity and task in the supervision HUD." The three nouns are
    // `agent`, `task` and `startedAt` on `ActionDriveLease`. Not said here: that
    // `ensureDriveLeaseForAct` opens an implicit lease when an agent forgets to.
    // It is true and it is worth knowing, but it is a caveat on the rule and it
    // cost this column a fourth line, so it lives in the troubleshooting entry
    // where somebody actually needs it.
    line: "Before it touches anything it takes a lease: one agent, one task, one clock.",
    call: "drive.begin",
  },
  {
    stage: "Drive",
    // `drive.note` — "Write a short beat to the floating supervision HUD so the
    // operator can see what this client is doing without watching the console."
    line: "It aims and acts, and notes each beat so the drive can be read as it happens.",
    call: "drive.note · act.execute",
  },
  {
    stage: "Trace",
    // `persistDriveSession` appends to `drive-trace.json` under
    // `artifacts/sessions/<sessionId>` on every act and every observe, and
    // `session.create` writes an empty `trace.json` up front. There is no flag
    // anywhere that turns it off, which is a supervision fact worth printing.
    line: "Every beat is appended to the session's trace as it runs. Nothing turns that off.",
    call: "drive.release",
  },
];

function Model() {
  return (
    <div>
      <div
        style={{
          // 6 on top of `Group`'s own 7pt shoulder. The rail is a hairline at the
          // same weight as the group rule directly above it, and at sixteen points
          // apart the two read as a double rule rather than as a heading and a
          // diagram.
          marginTop: 6,
          display: "grid",
          gridTemplateColumns: "repeat(4, 1fr)",
          columnGap: 20,
          // Stretch, so every column is the height of the tallest and the mono
          // call lines can hold one baseline across all four.
          alignItems: "stretch",
        }}
      >
        {MODEL.map((station, i) => (
          <div key={station.stage} style={{ display: "flex", flexDirection: "column" }}>
            {/* The rail is Home's cadence rule with the beats replaced by the
                four stages — the same hairline, the same nodes on it, read left
                to right along elapsed order. That is the whole reason this page
                is allowed a diagram at all: it is not an illustration style, it
                is the one drawing idiom the app already owns, spent on the one
                thing the app has never explained. */}
            <div style={{ position: "relative", height: 9 }}>
              {i < MODEL.length - 1 && (
                // Bridged across the 20pt column gap so the rail is continuous.
                // Integer offsets only: a hairline on a half pixel is the blur
                // that makes a ruled page look printed badly rather than finely.
                <div
                  style={{
                    position: "absolute",
                    left: 0,
                    right: -20,
                    top: 4,
                    height: 1,
                    background: "var(--act-rule)",
                  }}
                />
              )}
              {/* The hollow mark, at the size and weight Home draws its idle
                  lease with. Filled on the canvas so the rail passes behind it
                  rather than through it. */}
              <div
                style={{
                  position: "absolute",
                  left: 0,
                  top: 0,
                  width: 9,
                  height: 9,
                  borderRadius: "50%",
                  border: "1px solid var(--act-ink-muted)",
                  background: "var(--act-canvas)",
                }}
              />
            </div>

            <div
              style={{
                marginTop: 10,
                fontFamily: mono,
                fontSize: "var(--act-label)",
                fontWeight: 600,
                letterSpacing: "var(--act-track-label)",
                textTransform: "uppercase",
                color: "var(--act-ink-2)",
              }}
            >
              {station.stage}
            </div>

            {/* Content size, not chrome size. These four sentences are the
                substance of the block — the labels above them are the index. */}
            <div
              style={{
                marginTop: 7,
                fontSize: "var(--act-body)",
                lineHeight: 1.5,
                color: "var(--act-ink)",
              }}
            >
              {station.line}
            </div>

            {/* Pushed to the foot of the column rather than trailing its own
                sentence. Four mono strings ending at four different heights read
                as four unrelated captions; on one baseline they read as a row —
                which is what they are, the calls the four stages are made of. */}
            <div
              style={{
                marginTop: "auto",
                paddingTop: 10,
                fontFamily: mono,
                fontSize: "var(--act-caption)",
                color: "var(--act-ink-muted)",
              }}
            >
              {station.call}
            </div>
          </div>
        ))}
      </div>

      {/* The line that makes the diagram worth its height: it maps the four
          words onto the sidebar, so the model stops being vocabulary and starts
          being a legend for the rest of the window. The constraint is stapled to
          it because `attention` mode is denied in every case today and a person
          reading "drive" for the first time should not have to discover that
          from an error. */}
      <div
        style={{
          marginTop: 18,
          fontSize: "var(--act-body)",
          lineHeight: 1.6,
          color: "var(--act-ink-2)",
        }}
      >
        <span style={{ color: "var(--act-ink)" }}>Agents</span> is who may take a
        lease, <span style={{ color: "var(--act-ink)" }}>Home</span> is the lease
        while it is held, and <span style={{ color: "var(--act-ink)" }}>Traces</span>{" "}
        is what it left behind. Background is the only mode Action grants today.
      </div>
    </div>
  );
}

/**
 * `ActionToolCounts.hasData` — true once the ledger holds one settled call, which
 * is also the only honest way the app knows an agent has ever connected. Home
 * already reads exactly this to decide whether to draw its connect block, and the
 * window footer draws it as `Agent · Connected`.
 *
 * PROPOSAL. Belongs in `fixtures.ts` beside `PERMISSIONS`, so this page and Home
 * read one value rather than two constants that can disagree.
 */
const HAS_CONNECTED = true;

/**
 * The order of operations, once.
 *
 * Two of these five steps genuinely know whether they are done and three of them
 * cannot, and the column is honest about which is which rather than drawing five
 * checkboxes and lying about three of them. Connect is `ActionToolCounts.hasData`;
 * grant is the same `permissions` the headline reads. Whether a scenario has been
 * written, run, or watched is not a fact this page holds, so those three rows
 * carry a destination instead of a state — which is the more useful cell anyway,
 * because a person on step three does not want to be told they are on step three.
 *
 * The clauses point inward for the two steps this page can do something about and
 * outward for the three it cannot, which is what stops the block reading as a
 * generic onboarding checklist bolted onto a settings pane.
 */
function FirstRun({ permissions }: { permissions: Permission[] }) {
  const granted = permissions.filter((p) => p.status === "Granted").length;

  const steps: { step: string; clause: string; state?: string; done?: boolean; go?: string }[] = [
    {
      step: "Connect an agent",
      clause: "one line in a terminal — the command is under AGENT on this page",
      state: HAS_CONNECTED ? "Connected" : "Not yet",
      done: HAS_CONNECTED,
    },
    {
      step: "Grant what it needs",
      clause: "Screen Recording to see the screen, Accessibility to touch it",
      // Counted rather than named. "1 of 2" is the state; which one is missing is
      // already the largest sentence on the page and does not need saying twice.
      state: granted === permissions.length ? "Granted" : `${granted} of ${permissions.length}`,
      done: granted === permissions.length,
    },
    {
      step: "Write a scenario",
      clause: "a named plan of beats — note, aim, wait, act",
      go: "Scenarios",
    },
    {
      step: "Run it",
      clause: "from the plan, or let the agent call drive.play itself",
      go: "Scenarios",
    },
    {
      step: "Watch it happen",
      clause: "Home draws the lease, the beats and the elapsed clock",
      go: "Home",
    },
  ];

  return (
    <Table
      columns="26px 1fr 120px"
      align={["left", "left", "right"]}
      rows={steps.map((s, i) => [
        // Zero-padded, because `PlanTable` pads its step index and a run of
        // numbers only lines up if they are the same width.
        <span
          key="i"
          style={{ fontFamily: mono, fontSize: "var(--act-caption)", color: "var(--act-ink-muted)" }}
        >
          {String(i + 1).padStart(2, "0")}
        </span>,
        <span key="s" style={{ display: "flex", alignItems: "baseline", gap: 10, minWidth: 0 }}>
          <span style={{ fontSize: "var(--act-row)", whiteSpace: "nowrap" }}>{s.step}</span>
          <span
            style={{
              fontSize: "var(--act-caption)",
              color: "var(--act-ink-muted)",
              overflow: "hidden",
              textOverflow: "ellipsis",
              whiteSpace: "nowrap",
              minWidth: 0,
            }}
          >
            {s.clause}
          </span>
        </span>,
        // A state and a destination are different kinds of answer, so they are
        // drawn as different kinds of object: the state in the tracked mono the
        // whole page uses for status, the destination in sans with the arrow the
        // window uses for a jump. Nothing here fakes a state it cannot know.
        s.state ? (
          <span
            key="e"
            style={{
              fontFamily: mono,
              fontSize: "var(--act-label)",
              fontWeight: 600,
              letterSpacing: "var(--act-track-label)",
              textTransform: "uppercase",
              color: s.done ? "var(--act-ink-2)" : "var(--act-ink)",
            }}
          >
            {s.state}
          </span>
        ) : (
          <span
            key="e"
            style={{
              fontSize: "var(--act-caption)",
              color: "var(--act-ink-muted)",
              cursor: "pointer",
              whiteSpace: "nowrap",
            }}
          >
            {s.go} →
          </span>
        ),
      ])}
    />
  );
}

/* ------------------------------------------------------- troubleshooting -- */

/**
 * Symptom, cause, remedy — derived from the failure paths, never invented.
 *
 * The list exists because the readiness ledger catches exactly one failure and
 * the app has no answer for any other. Every entry below quotes a string the
 * runtime actually produces, and the source is named on each one so a copy review
 * can check it against the file rather than against a memory of it.
 *
 * The first entry is the reason the whole group was built. Screen Recording has a
 * hard preflight and fails loudly; Accessibility has no preflight anywhere, so
 * `observe.ax` fails at the API with a message that names no permission, and the
 * HID paths are worse than that — `ActionHostMain` and `ActionNativeAutomation`
 * build a `CGEventSource` and post, with no `AXIsProcessTrusted` check in front
 * of it, so an untrusted click *reports success* while macOS drops the event.
 * "The drive begins and nothing moves" is not a mystery, it is the shape of a
 * missing Accessibility grant, and until this list existed the app could not say
 * so anywhere.
 *
 * `gate` is why the group opens on state rather than on the first row: a Mac with
 * Screen Recording denied is one grant away from the relaunch trap, so that is
 * the entry already open when the page is drawn. Nothing is auto-opened on a
 * healthy machine.
 */
const SYMPTOMS: {
  symptom: string;
  tag: string;
  gate?: string;
  means: ReactNode;
  fix: ReactNode;
}[] = [
  {
    symptom: "The drive begins and nothing moves.",
    tag: "Accessibility",
    gate: "Accessibility",
    // ActionNativeAutomation.swift:151 for the ax message; ActionHostMain.swift
    // 484-600 and ActionNativeAutomation.swift 198-600 for the unchecked post.
    means: (
      <>
        Accessibility is the one permission nothing checks first. <Mono>observe.ax</Mono> fails at
        the API with <Mono>No accessibility windows found for …</Mono>, which names no permission —
        and <Mono>click</Mono>, <Mono>type</Mono>, <Mono>scroll</Mono> and <Mono>drag</Mono> post
        their events, report success, and are dropped by macOS. The agent is told the work landed.
      </>
    ),
    fix: (
      <>
        Grant Accessibility. It is the grant that takes effect in place — no relaunch, no re-check.
      </>
    ),
  },
  {
    symptom: "You granted Screen Recording and this page still says Denied.",
    tag: "Screen Recording",
    gate: "Screen Recording",
    // ActionHostMain.swift:253 reads CGPreflightScreenCaptureAccess; there is no
    // relaunch handling anywhere in the tree, which is the finding.
    means: (
      <>
        Screen Recording is read with <Mono>CGPreflightScreenCaptureAccess</Mono>, which does not
        change its answer inside a process that was already running when you granted it. Nothing in
        Action models that today.
      </>
    ),
    fix: (
      <>
        Quit Action and open it again. Until then every capture keeps failing with{" "}
        <Mono>Screen Recording permission has not been granted yet.</Mono>
      </>
    ),
  },
  {
    symptom: "The agent cannot reach Action at all.",
    tag: "Transport",
    // drive-client.ts:216, :194, :70. The client spawns the agent itself, so a
    // failure here is almost always the launcher path, not a dead process.
    means: (
      <>
        <Mono>Action agent is unavailable</Mono>, then{" "}
        <Mono>Action agent did not start within 120000ms</Mono>. Nothing is listening on{" "}
        <Mono>127.0.0.1:4319</Mono>. The client starts the agent itself, so this is the launcher not
        being where the MCP entry points rather than Action being closed.
      </>
    ),
    fix: <>Re-add the entry with the command under AGENT, and check the endpoint beside it.</>,
  },
  {
    symptom: "The drive stopped on its own, part way through.",
    tag: "Lease",
    // ActionDriveLeaseStore.swift:82-83 for the two bounds, :352-354 for the
    // summaries, and the comment at :75-81 for the "finds out on the next call".
    means: (
      <>
        A lease is swept after five minutes with no act, or thirty minutes in all. The trace's last
        line is <Mono>Lease expired after idle silence</Mono> or{" "}
        <Mono>Lease exceeded maximum duration</Mono>, and the driver only learns of it on its next
        call, as <Mono>Unknown drive lease: …</Mono>.
      </>
    ),
    fix: (
      <>
        Nothing is broken. The agent calls <Mono>drive.begin</Mono> again; everything up to the sweep
        is already in Traces.
      </>
    ),
  },
  {
    symptom: "Drive lease … belongs to another client.",
    tag: "Lease",
    // ActionDriveLeaseStore.swift:19 and :23; the implicit clause is
    // ensureDriveLeaseForAct in packages/mcp/src/index.ts:418-461.
    means: (
      <>
        A lease belongs to one MCP connection. A reconnect is a new client — and an agent that acted
        without calling <Mono>drive.begin</Mono> is holding an implicit lease it never named, which
        is also what{" "}
        <Mono>Multiple drive leases are active for this client; pass leaseId explicitly</Mono> means.
      </>
    ),
    fix: (
      <>
        Pass the <Mono>leaseId</Mono> that <Mono>drive.begin</Mono> returned on every call, and
        release it when the work ends.
      </>
    ),
  },
  {
    symptom: "It asked for the pointer and was refused.",
    tag: "Drive mode",
    // ActionDriveLeaseStore.swift:25, :161, and the pointerControl note at :41-49.
    means: (
      <>
        <Mono>Foreground keyboard or pointer control requires an approved attention lease</Mono>.
        Attention mode is not implemented — <Mono>drive.begin</Mono> denies it every time, with{" "}
        <Mono>Attention mode requires operator approval, which is not available yet.</Mono>
      </>
    ),
    fix: (
      <>
        Drive in background mode. Work that is coordinate-only by nature — a drag across the desktop
        — declares <Mono>pointerControl</Mono> on the lease instead.
      </>
    ),
  },
  {
    symptom: "The agent clicked something it never looked up.",
    tag: "Targets",
    // packages/runtime/src/macos.ts:717-726 — resolveTarget builds its result out
    // of the query and returns confidence 0. It performs no lookup at all.
    means: (
      <>
        <Mono>resolve.target</Mono> does not resolve anything yet. It echoes the query back with{" "}
        <Mono>confidence: 0</Mono>, so a &ldquo;resolved&rdquo; target is a restatement of what was
        asked for, not something found on screen.
      </>
    ),
    fix: (
      <>
        Have the agent read <Mono>observe.ax</Mono> or <Mono>observe.snapshot</Mono> and act on an
        element it actually found.
      </>
    ),
  },
];

function Troubleshooting({ permissions }: { permissions: Permission[] }) {
  const denied = new Set(
    permissions.filter((p) => p.status !== "Granted").map((p) => p.name),
  );
  // Opened from state, not from position. On a healthy Mac nothing is open and
  // the group is seven scannable lines; on a damaged one the entry that is about
  // to bite is already reading.
  //
  // Initial value only, deliberately. If a grant lands while this page is open
  // the row does not close itself and no other row opens — a list that
  // rearranges under a person mid-sentence is worse than one that is briefly out
  // of date, and the headline above has already announced the change.
  const [open, setOpen] = useState<string | null>(
    SYMPTOMS.find((s) => s.gate && denied.has(s.gate))?.symptom ?? null,
  );

  return (
    <div>
      {SYMPTOMS.map((entry, i) => {
        const isOpen = open === entry.symptom;
        return (
          <div key={entry.symptom}>
            {i > 0 && <div style={{ height: 1, background: "var(--act-rule-soft)" }} />}
            {/* The tint lands on the head only and never on the body it opened —
                `PlanRow` settled that argument, and a filled card wrapped around
                six lines of prose would be the largest object on a page whose
                largest object is supposed to be the readiness sentence. */}
            <button
              type="button"
              onClick={() => setOpen(isOpen ? null : entry.symptom)}
              style={{
                width: "100%",
                display: "flex",
                alignItems: "center",
                gap: 14,
                minHeight: 30,
                padding: 0,
                border: 0,
                textAlign: "left",
                cursor: "pointer",
                background: isOpen ? "var(--act-row-open)" : "transparent",
              }}
            >
              <span
                style={{
                  fontSize: "var(--act-row)",
                  color: "var(--act-ink)",
                  fontWeight: isOpen ? 600 : 400,
                }}
              >
                {entry.symptom}
              </span>
              <span style={{ flex: 1 }} />
              <span
                style={{
                  fontFamily: mono,
                  fontSize: "var(--act-label)",
                  fontWeight: 600,
                  letterSpacing: "var(--act-track-label)",
                  textTransform: "uppercase",
                  color: "var(--act-ink-muted)",
                  whiteSpace: "nowrap",
                }}
              >
                {entry.tag}
              </span>
            </button>

            {isOpen && (
              <div style={{ paddingTop: 4, paddingBottom: 14, display: "grid", gap: 8 }}>
                <Answer label="Means">{entry.means}</Answer>
                <Answer label="Do">{entry.fix}</Answer>
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}

/**
 * One half of an opened symptom. The two labels are a fixed 44pt column so the
 * cause and the remedy start on the same vertical — the pair is meant to be read
 * as two lines of one answer, and a ragged left edge would make it two answers.
 *
 * The remedy is in full ink and the cause is not, because a person who opened
 * this row is looking for the second line.
 */
function Answer({ label, children }: { label: string; children: ReactNode }) {
  const isFix = label === "Do";
  return (
    <div style={{ display: "flex", gap: 12, alignItems: "baseline" }}>
      <span
        style={{
          flex: "0 0 44px",
          fontFamily: mono,
          fontSize: "var(--act-label)",
          fontWeight: 600,
          letterSpacing: "var(--act-track-label)",
          textTransform: "uppercase",
          color: "var(--act-ink-muted)",
        }}
      >
        {label}
      </span>
      <span
        style={{
          flex: 1,
          minWidth: 0,
          fontSize: "var(--act-body)",
          lineHeight: 1.6,
          color: isFix ? "var(--act-ink)" : "var(--act-ink-2)",
        }}
      >
        {children}
      </span>
    </div>
  );
}

/**
 * A string the runtime actually emits, set inside a sentence.
 *
 * Mono at caption size and no box: these are quotations, not code the reader is
 * being handed to run, and the one boxed mono object on this page is the connect
 * command — which is the only string here anyone pastes anywhere.
 */
function Mono({ children }: { children: ReactNode }) {
  return (
    <span style={{ fontFamily: mono, fontSize: "var(--act-caption)", color: "var(--act-ink)" }}>
      {children}
    </span>
  );
}

/* -------------------------------------------------------------- keyboard -- */

/**
 * The shortcuts, out of the colophon and into a block.
 *
 * They were one label — "Shortcuts · App navigation, library, and Takes review" —
 * in the block on this page explicitly designed to be skimmed past, which is the
 * wrong home for the only place the app documents the key that stops a running
 * agent. The Swift keeps them in a modal sheet on ⌘/ and should keep doing so;
 * this is the same list at rest, where a person setting the app up can meet them
 * before they need them.
 *
 * Two edits against `ActionKeyboardCheatSheetView`, both for honesty. Its
 * Scenarios and Library groups are not keyboard shortcuts at all — they are mouse
 * gestures and button names drawn in the same keycap style — so they are dropped
 * rather than reprinted. And its ⌘1–⌘5 rows name Home / Scenarios / Runs /
 * Library / Settings, which predates Runs and Library becoming one Traces; the
 * row here states the binding and lets the sidebar name the sections, so it
 * cannot drift again.
 *
 * The stop pair is the substantive addition and it is documented nowhere in the
 * product. `ActionSupervisionOverlayController.isSupervisorShortcut` matches
 * ⌃⌘. and a double Escape inside 0.45s, and both call `triggerStopAll`. On a
 * computer-use product that is the most important key on the machine.
 */
type Shortcut = { caps: string[]; sep?: string; label: string };

// ActionSupervisionOverlayController.swift:713-733.
const STOP: Shortcut[] = [
  { caps: ["⌃⌘."], label: "Stop every agent driving this Mac" },
  { caps: ["esc", "esc"], label: "The same, tapped twice inside half a second" },
];

// ActionLauncherRootView.swift:515-539 and ActionLauncherController.swift:132.
const ANYWHERE: Shortcut[] = [
  { caps: ["⌘1", "⌘5"], sep: "–", label: "Jump to a section, in sidebar order" },
  { caps: ["⌘,"], label: "Settings window" },
  { caps: ["⌘/", "?"], sep: "or", label: "The shortcut sheet" },
];

// ActionSessionPreviewView.swift:94-135 and :757-759.
const REVIEW: Shortcut[] = [
  { caps: ["space"], label: "Play or pause" },
  { caps: ["N"], label: "Open the note composer" },
  { caps: ["1", "2", "3", "4"], label: "Point · Range · Region · Draw" },
  { caps: ["⌘↩"], label: "Save the note" },
  { caps: ["[", "]"], label: "Previous, next note" },
  { caps: ["esc"], label: "Cancel the selection, or close the composer" },
];

function KeyboardGroup() {
  return (
    <div>
      {/* Full width and first, at row size while the two columns under it are at
          body size. One step up the named scale is the whole emphasis — no fill,
          no rule, no colour. Coral would be wrong here even though this is the
          panic key: coral means a drive is live, and a page about setup has no
          live drive on it. */}
      <Band label="Stop everything">
        {STOP.map((s) => (
          <ShortcutRow key={s.label} shortcut={s} size="var(--act-row)" />
        ))}
        <div
          style={{
            marginTop: 9,
            fontSize: "var(--act-caption)",
            color: "var(--act-ink-muted)",
            lineHeight: 1.6,
          }}
        >
          Both are watched by the supervision overlay, so they are live exactly while an agent holds
          the machine — and they stop every session, not the one in front of you.
        </div>
      </Band>

      {/* Two up. Neither list is long enough to earn a full measure of its own,
          and stacking them would have put twelve keycaps down a 720pt column and
          made the foot of the page taller than the readiness block at the top. */}
      <div style={{ marginTop: 22, display: "grid", gridTemplateColumns: "1fr 1fr", gap: 30 }}>
        <Band label="Anywhere">
          {ANYWHERE.map((s) => (
            <ShortcutRow key={s.label} shortcut={s} />
          ))}
        </Band>
        <Band label="Reviewing a take">
          {REVIEW.map((s) => (
            <ShortcutRow key={s.label} shortcut={s} />
          ))}
        </Band>
      </div>
    </div>
  );
}

/**
 * A sub-heading inside a group. Muted and ruleless, where `Group`'s own label is
 * ink-2 with a full-measure hairline — the same distinction the ledger already
 * makes between its group label and its column headers, so the page has two
 * levels of eyebrow and not two competing ones.
 */
function Band({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div>
      <div
        style={{
          fontFamily: mono,
          fontSize: "var(--act-label)",
          fontWeight: 600,
          letterSpacing: "var(--act-track-label)",
          textTransform: "uppercase",
          color: "var(--act-ink-muted)",
          paddingBottom: 4,
        }}
      >
        {label}
      </div>
      {children}
    </div>
  );
}

function ShortcutRow({ shortcut, size }: { shortcut: Shortcut; size?: string }) {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 10, minHeight: 26 }}>
      {/* Fixed, not auto. The widest binding in each band is four keys wide and
          the narrowest is one, so an auto width started every label on its own
          vertical and the block stopped being a list. 84 clears `1 2 3 4`, which
          is the widest run in the app, and the same value is used in all three
          bands so the two columns read as one table rather than two. */}
      <span style={{ display: "inline-flex", alignItems: "center", gap: 4, flex: "0 0 86px" }}>
        {shortcut.caps.map((cap, i) => (
          <span key={cap + i} style={{ display: "inline-flex", alignItems: "center", gap: 5 }}>
            {i > 0 && shortcut.sep && (
              <span style={{ fontSize: "var(--act-caption)", color: "var(--act-ink-muted)" }}>
                {shortcut.sep}
              </span>
            )}
            <Keycap>{cap}</Keycap>
          </span>
        ))}
      </span>
      <span style={{ fontSize: size ?? "var(--act-body)", color: "var(--act-ink)" }}>
        {shortcut.label}
      </span>
    </div>
  );
}

/**
 * A key, not a control.
 *
 * Deliberately not a `Chip`: a chip is the row-scale button and this is never
 * pressable, so it carries the structural hairline rather than the control one
 * and sits on the same ground a selected row does. Same reasoning as the theme
 * card's border — the moment a read-only object borrows a control's edge, the
 * page grows a third button size nobody asked for.
 */
function Keycap({ children }: { children: ReactNode }) {
  return (
    <span
      style={{
        display: "inline-flex",
        alignItems: "center",
        justifyContent: "center",
        // 18, not 20. Four of these plus their gaps is the widest binding the
        // app has, and at 20 the run overflowed the fixed slot above and pushed
        // one label out of the column it shares with five others.
        minWidth: 18,
        height: 20,
        padding: "0 5px",
        borderRadius: 4,
        border: "1px solid var(--act-rule)",
        background: "var(--act-row-open)",
        fontFamily: mono,
        fontSize: "var(--act-caption)",
        color: "var(--act-ink-2)",
        whiteSpace: "nowrap",
      }}
    >
      {children}
    </span>
  );
}

/* ---------------------------------------------------------------- groups -- */

/**
 * Runs' day line, reused verbatim: label, 8pt gap, rule to the right edge.
 *
 * 24pt above each group is the only vertical space in the page — a group is
 * separated from the one before it, never from its own contents, so the label
 * belongs to the table under it and not to the whitespace over it. The 7pt
 * shoulder under the label is `DayHeader`'s own inset, kept identical so the two
 * idioms are the same idiom.
 *
 * The readiness block carries no label of its own: it opens with a 34pt
 * sentence, and a 9pt eyebrow over that would be a caption on a headline.
 */
function Group({
  title,
  children,
}: {
  title: string;
  children: ReactNode;
}) {
  return (
    <div style={{ marginTop: 28 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 8, paddingBottom: 7 }}>
        <span
          style={{
            fontFamily: mono,
            fontSize: "var(--act-label)",
            fontWeight: 600,
            letterSpacing: "var(--act-track-label)",
            textTransform: "uppercase",
            color: "var(--act-ink-2)",
          }}
        >
          {title}
        </span>
        <span style={{ flex: 1, height: 1, background: "var(--act-rule)" }} />
      </div>
      {children}
    </div>
  );
}

/* ----------------------------------------------------------------- table -- */

/**
 * One grid string, written once, driving both the column headers and the rows.
 *
 * `action.css` states the rule the old code broke: the moment a column header
 * sits over a different edge than its values, the table stops being a table. It
 * broke because the same `gridTemplateColumns` literal was typed into two
 * components that were free to drift apart.
 *
 * Only the capability ledger passes `headers`. Everything else on this page is a
 * definition list — a label and the one value beside it — which is what
 * `ActionSettingsRow(title:subtitle:)` has always been.
 */
function Table({
  columns,
  headers,
  rows,
  align,
}: {
  columns: string;
  headers?: string[];
  rows: ReactNode[][];
  align?: ("left" | "right")[];
}) {
  const right = (i: number) => align?.[i] === "right";
  return (
    <div>
      {headers && (
        <>
          <div
            style={{
              display: "grid",
              gridTemplateColumns: columns,
              paddingBottom: 7,
              fontFamily: mono,
              fontSize: "var(--act-label)",
              fontWeight: 600,
              letterSpacing: "var(--act-track-label)",
              textTransform: "uppercase",
              color: "var(--act-ink-muted)",
            }}
          >
            {headers.map((h, i) => (
              <span key={i} style={{ textAlign: right(i) ? "right" : "left" }}>
                {h}
              </span>
            ))}
          </div>
          <div style={{ height: 1, background: "var(--act-rule)" }} />
        </>
      )}
      {rows.map((cells, r) => (
        <div key={r}>
          {r > 0 && <div style={{ height: 1, background: "var(--act-rule-soft)" }} />}
          {/* 30 is the window's row unit: `RunRow` is 30, `ShowMore` is 30,
              `QuietButton` is 30, and the Swift's subnav item is 32. The
              capability rows sit on it too — a ledger of what the machine can do
              is not a reason to invent a taller row than the ledger of what it
              did. */}
          <div
            style={{
              display: "grid",
              gridTemplateColumns: columns,
              alignItems: "center",
              minHeight: 30,
            }}
          >
            {cells.map((c, i) => (
              <div
                key={i}
                style={{
                  display: "flex",
                  justifyContent: right(i) ? "flex-end" : "flex-start",
                  minWidth: 0,
                }}
              >
                {c}
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}

/** A row title that gives way rather than pushing the columns to its right. */
function Name({ children }: { children: ReactNode }) {
  return (
    <span
      style={{
        fontSize: "var(--act-row)",
        overflow: "hidden",
        textOverflow: "ellipsis",
        whiteSpace: "nowrap",
        minWidth: 0,
      }}
    >
      {children}
    </span>
  );
}

function Path({ children }: { children: ReactNode }) {
  return (
    <span
      style={{
        fontFamily: mono,
        fontSize: "var(--act-caption)",
        color: "var(--act-ink-2)",
        overflow: "hidden",
        textOverflow: "ellipsis",
        whiteSpace: "nowrap",
        minWidth: 0,
      }}
    >
      {children}
    </span>
  );
}

/* ------------------------------------------------------------------ mode -- */

const MODES = ["Light", "Dark", "System"] as const;

/**
 * `ActionSegmentedControl` at the width the Swift gives it, drawn from tokens
 * only so it does not become a fourth button style: the hairline is
 * `--act-border-quiet`, the same edge every quiet control in the window carries,
 * and the selected segment is `--act-row-open`, the same ground a selected row or
 * a selected theme card sits on. Nothing new is introduced.
 *
 * PROPOSAL: the order is Light / Dark / System, dimmest to brightest to deferred.
 * `ActionAppearanceMode.allCases` is System / Light / Dark, which puts the "no
 * opinion" option first in a control whose whole job is to state one.
 *
 * The dividers are painted as segment borders on the left of every segment but
 * the first, so selecting a segment never re-lays the control.
 */
function Segmented() {
  const [on, setOn] = useState<string>("System");
  return (
    <div
      style={{
        display: "flex",
        width: 220,
        height: 24,
        borderRadius: 6,
        border: "1px solid var(--act-border-quiet)",
        overflow: "hidden",
      }}
    >
      {MODES.map((m, i) => (
        <button
          key={m}
          type="button"
          onClick={() => setOn(m)}
          style={{
            flex: 1,
            padding: 0,
            border: 0,
            borderLeft: i > 0 ? "1px solid var(--act-rule)" : 0,
            background: on === m ? "var(--act-row-open)" : "transparent",
            cursor: "pointer",
            fontSize: "var(--act-caption)",
            fontWeight: on === m ? 600 : 400,
            color: on === m ? "var(--act-ink)" : "var(--act-ink-2)",
          }}
        >
          {m}
        </button>
      ))}
    </div>
  );
}

/**
 * One row, and the Swift's own row: `ActionSettingsControlRow(title: "Light and
 * dark")` with a 220pt segmented control.
 */
function ModeGroup() {
  return (
    <Table
      columns="minmax(180px, 260px) minmax(140px, 1fr) 220px"
      align={["left", "left", "right"]}
      rows={[[<Name key="n">Light and dark</Name>, null, <Segmented key="c" />]]}
    />
  );
}

/* ----------------------------------------------------------------- theme -- */

/**
 * Eight values per theme, exactly the eight `ActionThemePreview` carries, all
 * light appearance.
 *
 * Action is transcribed slot for slot from `ActionThemeBuiltin.swift`. Porcelain
 * is the shipped `themes/scout-porcelain.json`: seven of its eight are stated
 * outright in the file, and `deep` is the one the seed derives, so it was
 * computed with `ActionSurfaceSeed.surface()`'s own move — ink at −2 L*, mixed
 * 10% toward #8A6A3C — rather than eyeballed.
 *
 * Two themes and not three: every other theme on disk is seeded, and a third card
 * would have meant inventing a palette and then reporting it as a shipping
 * theme's.
 */
const THEMES = [
  {
    name: "Action",
    on: true,
    band: "#ECE2CF",
    canvas: "#F3EBDD",
    panel: "#FAF5EB",
    edge: "rgba(32, 40, 43, 0.12)",
    ink: "#20282B",
    inkSecondary: "#596261",
    accent: "#EF6A47",
    deep: "#25231F",
  },
  {
    name: "Porcelain",
    on: false,
    band: "#EEEEEC",
    canvas: "#F8F8F7",
    panel: "#FFFFFF",
    edge: "#DBDAD7",
    ink: "#161514",
    inkSecondary: "#666461",
    accent: "#3E66CC",
    deep: "#1D1914",
  },
] as const;

type Theme = (typeof THEMES)[number];

/**
 * The app in miniature, in the app's own order: the band across the top, the page
 * under it, a card on the page, two weights of ink on the card, the accent as a
 * rule down the side.
 *
 * Four flat colour slabs recited four hexes and painted the loudest colour in the
 * window on the page with the least to say. This shows each value at the area it
 * actually occupies in a window, which is an order of magnitude less paint and
 * strictly more information.
 */
function Specimen({ t }: { t: Theme }) {
  return (
    <div
      style={{
        height: 76,
        borderRadius: 7,
        border: "1px solid var(--act-rule)",
        overflow: "hidden",
        display: "flex",
        flexDirection: "column",
      }}
    >
      <div
        style={{
          height: 13,
          flex: "0 0 auto",
          background: t.band,
          padding: "0 6px",
          display: "flex",
          alignItems: "center",
          gap: 2.5,
        }}
      >
        {[0, 1, 2].map((i) => (
          <span
            key={i}
            style={{
              width: 3.5,
              height: 3.5,
              borderRadius: "50%",
              background: t.inkSecondary,
              opacity: 0.3,
            }}
          />
        ))}
      </div>

      <div style={{ flex: 1, minHeight: 0, display: "flex", background: t.canvas }}>
        <div style={{ width: 3, flex: "0 0 auto", background: t.accent, margin: "7px 0" }} />
        <div
          style={{
            flex: 1,
            minWidth: 0,
            // 6 rather than the Swift's 8: at 8 the column's content is 66pt
            // inside a 63pt body and SwiftUI clips the command well's bottom
            // radius off. Every element keeps the size the Swift gives it; the
            // padding is what gives, so the block reads as a block.
            padding: "6px 8px",
            display: "flex",
            flexDirection: "column",
            gap: 5,
          }}
        >
          <div style={{ display: "flex", alignItems: "center", gap: 4 }}>
            <span style={{ width: 30, height: 4, borderRadius: 2, background: t.ink }} />
            <span style={{ flex: 1 }} />
            {/* The accent at the size it is actually used: the fastest thing to
                tell two palettes apart by, so the specimen has to show enough of
                it to judge. */}
            <span style={{ width: 16, height: 6, borderRadius: 3, background: t.accent }} />
          </div>

          <div
            style={{
              padding: 7,
              borderRadius: 4,
              background: t.panel,
              border: `1px solid ${t.edge}`,
              display: "flex",
              flexDirection: "column",
              gap: 4,
            }}
          >
            <div style={{ display: "flex", alignItems: "center", gap: 4 }}>
              <span style={{ width: 4, height: 4, borderRadius: "50%", background: t.accent }} />
              <span
                style={{ width: 42, height: 3, borderRadius: 1.5, background: t.ink, opacity: 0.75 }}
              />
            </div>
            <span
              style={{ width: 32, height: 3, borderRadius: 1.5, background: t.inkSecondary }}
            />
          </div>

          {/* The command well, which stays dark in both appearances and is the
              fastest tell that a theme understood the recess. */}
          <div style={{ height: 9, flex: "0 0 auto", borderRadius: 3, background: t.deep }} />
        </div>
      </div>
    </div>
  );
}

/**
 * The grid, the subtitle the Swift prints under it, and the Themes folder row —
 * `settingsAppearancePage`'s remaining elements, in the Swift's own order.
 *
 * The folder row lives here and not in the colophon because the Swift puts it
 * here: it is the escape hatch for the control directly above it, and Reveal is
 * one of the four things on this page a person can actually do.
 */
function ThemeGroup() {
  const [selected, setSelected] = useState<string>("Action");
  return (
    <div>
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(auto-fill, minmax(132px, 190px))",
          gap: 10,
        }}
      >
        {THEMES.map((t) => {
          const on = selected === t.name;
          return (
            <button
              key={t.name}
              type="button"
              onClick={() => setSelected(t.name)}
              style={{
                padding: 6,
                borderRadius: 10,
                textAlign: "left",
                cursor: "pointer",
                // 1px in both states, so moving the selection does not re-lay the
                // grid by half a pixel. Ink and never the accent: every card here
                // is a colour sample, and a tinted mark would compete with the
                // thing being sampled. Selection is already said three times —
                // the ground, the semibold name, the check.
                border: `1px solid ${on ? "var(--act-border-quiet)" : "var(--act-rule)"}`,
                background: on ? "var(--act-row-open)" : "transparent",
                display: "flex",
                flexDirection: "column",
                gap: 7,
              }}
            >
              <Specimen t={t} />
              <span
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 5,
                  fontSize: "var(--act-body)",
                  fontWeight: on ? 600 : 400,
                  color: "var(--act-ink)",
                }}
              >
                {t.name}
                <span style={{ flex: 1 }} />
                {on && <CheckCircle2 size={13} style={{ color: "var(--act-ink)" }} />}
              </span>
            </button>
          );
        })}
      </div>

      {/* `themeSubtitle`, which says where the selected theme came from. One line
          of chrome prose, not a row: it describes the grid above it rather than
          naming a value of its own. */}
      <div style={{ marginTop: 10, fontSize: "var(--act-body)", color: "var(--act-ink-2)" }}>
        Built in.
      </div>

      {/* `ActionSettingsDivider`, drawn at the same weight this page's tables use
          between rows, because that is what it separates: the grid block from the
          last row of the same section. */}
      <div style={{ marginTop: 12, height: 1, background: "var(--act-rule-soft)" }} />
      <Table
        columns="minmax(180px, 260px) minmax(200px, 1fr) 96px"
        align={["left", "left", "right"]}
        rows={[
          [
            <Name key="n">Themes folder</Name>,
            <Path key="p">~/Library/Application Support/Action/Themes</Path>,
            <Chip key="a">Reveal</Chip>,
          ],
        ]}
      />
    </div>
  );
}

/* ----------------------------------------------------------------- agent -- */

/**
 * The label-and-value grid the Agent group is set on, held at the same measures
 * the Mode and Themes-folder rows use so the three read as one kind of row from
 * three inches apart.
 */
const DEF_COLS = "minmax(180px, 260px) minmax(200px, 1fr)";

/**
 * The MCP command's permanent home, and the Swift's Runtime section folded in
 * around it.
 *
 * PROPOSAL, on two counts. Home now draws the connect command only until this Mac
 * has been driven once — after the first run it is gone from there forever — so
 * the line has to live somewhere it can be found on purpose, and this is the only
 * page that is about setting the machine up. And Status is dropped: the window
 * footer carries "Agent · Connected" on every page of the app, so a row here
 * repeating it would be the same fact in two places on one screen.
 *
 * The well is graphite because it is a thing you paste into a terminal and the
 * window has exactly one idiom for that. It is kept to `fit-content` at 11pt so
 * it stays the darkest object on the page without becoming the loudest one — the
 * headline is four times its type size, and that ordering is the whole point.
 */
function AgentGroup() {
  return (
    <Table
      columns={DEF_COLS}
      rows={[
        [
          <Name key="n">Connect an agent</Name>,
          <div key="v" style={{ display: "flex", alignItems: "center", gap: 10, minWidth: 0 }}>
            <span
              style={{
                padding: "6px 11px",
                borderRadius: 6,
                background: "var(--act-deep)",
                fontFamily: mono,
                fontSize: "var(--act-caption)",
                color: "var(--act-on-deep-meta)",
                whiteSpace: "nowrap",
              }}
            >
              claude mcp add{" "}
              <span style={{ color: "var(--act-on-deep)", fontWeight: 600 }}>action</span> --
              action-agent stdio
            </span>
            <Chip>Copy</Chip>
          </div>,
        ],
        [
          <Name key="n">Endpoint</Name>,
          <div key="v" style={{ display: "flex", alignItems: "baseline", gap: 10, minWidth: 0 }}>
            <Path>ws://127.0.0.1:4319</Path>
            {/* Transport and Launch were two rows saying one thing about the same
                socket. As a clause they cost a line instead of sixty points. */}
            <span style={{ fontSize: "var(--act-caption)", color: "var(--act-ink-muted)" }}>
              local WebSocket, starts with Action
            </span>
          </div>,
        ],
      ]}
    />
  );
}

/* -------------------------------------------------------------- colophon -- */

/**
 * Version, bundle id, the scenarios path and the docs URL — the Swift's Action,
 * Files and Help sections, which were three of the seven bands on the old page
 * and are none of the reasons anyone opens it.
 *
 * PROPOSAL: drawn as a colophon rather than three ruled tables. Nothing here is
 * actionable and nothing here is read twice, so it gets the treatment a
 * colophon gets — one dense block at caption size, no row rules, no columns to
 * scan down.
 *
 * Shorter than it was by one entry. The shortcuts line lived here, and a
 * colophon is where facts go to be ignored — which was the wrong home for the
 * only place the app writes down the key that stops a running agent. It has a
 * block of its own above, and the compression argument that justified this
 * colophon is exactly the argument for taking it out.
 */
const COLOPHON: { label: string; value: string; mono?: boolean }[] = [
  // What the app actually reports: `Info.plist` ships 0.0.0 (1) and
  // `build-app.sh` only overwrites it when ACTION_VERSION is exported.
  { label: "Version", value: "0.0.0 (1)", mono: true },
  { label: "Bundle", value: "dev.action.Action", mono: true },
  { label: "Docs", value: "arach.github.io/action", mono: true },
  // The store's own directory, from ActionScenarioModels — not the
  // process-relative path `openScenariosFolder` reveals. No button: the Swift
  // makes the whole row the target and draws none.
  { label: "Scenarios", value: "~/Library/Application Support/Action/scenarios", mono: true },
  // Traces have no row here on purpose. `sessionOutputDir` resolves
  // `artifacts/sessions` against `ACTION_ROOT`, which defaults to wherever the
  // MCP package was installed — so there is no single path the app could print
  // that would be true on the reader's machine. HOW IT WORKS teaches what a
  // trace is and Traces is where you read one; a fabricated path would be worse
  // than the absence.
];

function AboutColophon() {
  return (
    <div
      style={{
        display: "flex",
        flexWrap: "wrap",
        columnGap: 30,
        rowGap: 8,
        alignItems: "baseline",
      }}
    >
      {COLOPHON.map((entry) => (
        <span
          key={entry.label}
          style={{ display: "inline-flex", alignItems: "baseline", gap: 8, minWidth: 0 }}
        >
          <span
            style={{
              fontFamily: mono,
              fontSize: "var(--act-label)",
              fontWeight: 600,
              letterSpacing: "var(--act-track-label)",
              textTransform: "uppercase",
              color: "var(--act-ink-muted)",
            }}
          >
            {entry.label}
          </span>
          <span
            style={{
              fontFamily: entry.mono ? mono : "inherit",
              fontSize: "var(--act-caption)",
              color: "var(--act-ink-2)",
            }}
          >
            {entry.value}
          </span>
        </span>
      ))}
    </div>
  );
}
