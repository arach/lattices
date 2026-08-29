"use client";

import { TOOL_GROUPS } from "@/studio/action/fixtures";
import { Chip } from "@/studio/action/Surface";
import { Mira } from "@/studio/action/Mira";

/**
 * Home is the state of this Mac. It is not a dashboard of the other pages.
 *
 * The version this replaces was assembled out of things that already existed
 * elsewhere: its Recent Activity ledger was the first four rows of Traces, its
 * permissions state was in the window footer, and its connect block was a
 * one-time setup task pinned to the primary surface forever. A front door made
 * of other rooms is not a front door, and the page was nearly deleted for it.
 *
 * It is kept because the app needs a presence, and it earns the slot by
 * answering the one question no other page in the window answers: *who has this
 * Mac right now, and what are they doing with it.* That question has exactly two
 * answers, so Home has exactly two states.
 *
 * IDLE is you. Paper, two ruled bands, no page-scale button at all — an idle
 * machine asks nothing of its owner — and Mira standing in the slot that counts
 * the clock while a drive is live. The point of the state is that the app is at
 * rest, not switched off.
 *
 * DRIVING is an agent, and it is the screen this whole file exists for. Today
 * the live state of a computer-use product is a 7px coral dot on an eyebrow,
 * while something types into your Calculator and moves your cursor. Here it is
 * the largest object in the window: a graphite console whose headline is the
 * agent's own current sentence, set at the size a page name normally gets,
 * because on a supervision surface the sentence *is* the page. Underneath it a
 * cadence rule plots one tick per beat across the elapsed time, so the rhythm
 * of the drive — busy, thinking, hung — is readable without reading a word.
 *
 * The graphite is not decoration and it is not new: `ActionHomeView.drivingPanel`
 * already argues that dark means something is happening to this Mac, and the
 * only reason Home could not spend it on the drive was that the connect command
 * was wearing it. Demoting connect frees the app's heaviest surface for the app's
 * loudest fact. That is the whole trade: one dark object on Home, and it is the
 * machine being driven.
 *
 * Colour: coral, and nothing else, on the driving state only — the live pulse,
 * the word DRIVING, the leading edge of the cadence rule, and the one control
 * that ends it. Idle spends zero accent. Every fact drawn on either state comes
 * from `ActionHomeLease`, the note stream `ActionSupervisionRegistry` writes on
 * every `drive_note`, or the tool ledger's own vocabulary. Nothing here is
 * derived from data the runtime does not record.
 */

const mono = "var(--act-mono)";

/* ----------------------------------------------------------- local fixtures --
 * All four belong in `fixtures.ts`; they live here because another agent owns
 * that file this round. Every field maps onto something the runtime already
 * writes — the mapping is named on each one.
 */

/** `ActionHomeLease`, field for field, with `elapsed`/staleness pre-derived. */
const LIVE_LEASE = {
  id: "8f21c4d0",
  agent: "Claude Code",
  task: "Add 12 and 30 in Calculator and read the result",
  mode: "background",
  /** `Date.now() - startedAt`, which is exactly `ActionHomeLease.elapsed`. */
  elapsedSeconds: 134,
  /** `Date.now() - lastActAt`. The only supervision fact that says "still alive". */
  sinceLastActSeconds: 3,
  pointerControl: true,
  showSupervisionLabel: true,
};

/**
 * The note stream. `ActionSupervisionRegistry` appends `{at, line, leaseId}` to
 * `runtime/supervision/notes.jsonl` on every `drive_note` call, and already
 * exposes `latestNote(forLease:)` and `recentNotes(limit:)` — so this is a
 * recorded, timestamped, lease-scoped log, not just the single line Home reads
 * today. `atSeconds` is the note's `at` minus the lease's `startedAt`.
 */
const BEATS: { atSeconds: number; line: string }[] = [
  { atSeconds: 129, line: "Pressing equals" },
  { atSeconds: 112, line: "Typing 30" },
  { atSeconds: 100, line: "Clicking the plus key" },
  { atSeconds: 81, line: "Typing 12" },
  { atSeconds: 71, line: "Clearing the display" },
  { atSeconds: 58, line: "Reading the accessibility tree for Calculator" },
  { atSeconds: 47, line: "Bringing Calculator to the front" },
  { atSeconds: 33, line: "Opening Calculator" },
  { atSeconds: 19, line: "Aiming at the Calculator icon in the Dock" },
  { atSeconds: 12, line: "Taking a snapshot of the screen" },
];

/**
 * The vocabulary, transcribed from `ActionToolLedger` — `actVerbs`,
 * `observeTools`, `driveTools`, `stageTools`. The existing `TOOL_GROUPS` fixture
 * is a shorter paraphrase of the same four groups ("execute", "resolve",
 * "status"), and where the two disagree the Swift wins. This list is what the
 * Mac answers to; the fixture's numbers are how often it has.
 */
const VOCABULARY: { group: string; verbs: string[] }[] = [
  { group: "ACT", verbs: ["click", "type", "press-key", "focus-window", "open-app", "scroll", "drag"] },
  { group: "OBSERVE", verbs: ["snapshot", "resolve.target", "ax", "ocr", "vision"] },
  { group: "DRIVE", verbs: ["begin", "aim", "note", "play", "release"] },
  { group: "STAGE", verbs: ["stage.set", "stage.clear", "record.start", "record.stop"] },
];

/**
 * `ActionToolCounts.hasData` — true once the ledger holds one settled call in
 * the window, which is also the only honest way the app knows an agent has ever
 * connected. Flip it to see the first-run connect block.
 */
const HAS_CONNECTED = true;

/** Past this, `lastActAt` stops meaning "working" and starts meaning "check on it". */
const STALE_AFTER_SECONDS = 30;

/* ---------------------------------------------------------------- helpers -- */

function clock(seconds: number) {
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
}

/** Summed from the fixture rather than written down, so it cannot drift from it. */
const ACTIONS_THIS_WEEK = TOOL_GROUPS.reduce(
  (total, group) => total + group.items.reduce((n, item) => n + item.count, 0),
  0,
);

/* ------------------------------------------------------------------- page -- */

export type HomeState = "idle" | "driving";

export function HomeSection({
  state = "idle",
  onOpenRuns,
}: {
  state?: HomeState;
  onOpenRuns?: () => void;
}) {
  return (
    // The ledger measure, kept from the page this replaces: at Wide the console
    // would otherwise put the agent's name at the left edge and the elapsed
    // clock 1300pt away, and a status line that wide stops being one object.
    <div style={{ maxWidth: "var(--act-ledger-width)" }}>
      <PulseKeyframes />
      {state === "driving" ? <Driving /> : <Idle onOpenRuns={onOpenRuns} />}
    </div>
  );
}

/* ------------------------------------------------------------------ idle -- */

/**
 * Two bands, in the order an owner reads them: this machine is mine → here is
 * what it can be asked for. On a first run a third appears underneath and then
 * leaves for good, which is the correct lifespan for a setup task and the
 * opposite of what it had.
 */
function Idle({ onOpenRuns }: { onOpenRuns?: () => void }) {
  return (
    <div>
      {/* Deliberately the same height and the same slot as the driving console,
          so the two states are one page with two values in it rather than two
          layouts. It is also what stops idle reading as an unfinished screen:
          without the weight up here, a short vocabulary table floats at the top
          of 400pt of blank paper. */}
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: 24,
          minHeight: 186,
          paddingBottom: 20,
        }}
      >
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 9 }}>
            {/* The hollow counterpart to the live pulse, in the same 9px slot.
                Idle is the drive mark with nothing in it, which is a truer
                drawing of "the lease is free" than any word would be. */}
            <span
              style={{
                width: 9,
                height: 9,
                borderRadius: "50%",
                border: "1px solid var(--act-field-ink-meta)",
              }}
            />
            <Label tint="var(--act-field-ink-2)">IDLE</Label>
          </div>

          {/* The headline slot on this page always answers "who has this Mac".
              Driving fills it with the agent's sentence; idle fills it with the
              owner. "You", never "Nobody" — the page is not reporting a vacancy,
              and an absence where the live state puts a name reads as the
              feature being switched off rather than as the machine being yours. */}
          <div
            style={{
              marginTop: 8,
              fontSize: "var(--act-headline)",
              fontWeight: 300,
              letterSpacing: "var(--act-track-headline)",
              lineHeight: 1.1,
              color: "var(--act-field-ink)",
            }}
          >
            You
          </div>

          <div
            style={{
              marginTop: 9,
              fontSize: "var(--act-row)",
              color: "var(--act-field-ink-2)",
              maxWidth: 460,
            }}
          >
            No agent holds a lease. The pointer, the keyboard and the screen are
            yours, and Action is watching for the next one to ask.
          </div>
        </div>

        {/* Mira stands where the elapsed clock counts during a drive. The slot
            is the same one in both states because it holds the same thing: the
            other party. When that is an agent it is a running number; when it
            is nobody it is the companion, and the swap is the calmest way this
            page has of saying which state it is in. */}
        <div style={{ flex: "0 0 auto", display: "flex", paddingRight: 8 }}>
          {/* Big enough to be a presence rather than an icon, small enough that
              her flat ten-shape avatar does not start looking like a balloon.
              The Swift draws a 12fps sprite sheet here and should keep doing so;
              this is the browser's honest stand-in for it. */}
          <Mira size={112} />
        </div>
      </div>

      <Band>
        <div style={{ display: "flex", alignItems: "baseline", gap: 10 }}>
          <Label>WHAT AN AGENT CAN ASK OF THIS MAC</Label>
          <span style={{ flex: 1 }} />
          {/* The one number left of the old ACTIONS grid. Fifteen counts across
              four columns was a week of usage statistics wearing the clothes of
              a capability list — diagnostics, on the surface that is supposed to
              be presence. The verbs are the presence; the tally is a fact about
              history, so it is one line and it links to where the traces live.
              Absent entirely before the first call, because "0 actions this
              week" is a wall of confident nothing on a Mac that has simply never
              been asked — the same argument `ActionToolCounts.hasData` makes. */}
          {HAS_CONNECTED && (
            <button
              type="button"
              onClick={onOpenRuns}
              style={{
                border: 0,
                background: "transparent",
                cursor: onOpenRuns ? "pointer" : "default",
                padding: 0,
                fontFamily: mono,
                fontSize: "var(--act-caption)",
                color: "var(--act-field-ink-meta)",
                fontVariantNumeric: "tabular-nums",
              }}
            >
              {ACTIONS_THIS_WEEK} actions this week →
            </button>
          )}
        </div>

        <div style={{ marginTop: 12 }}>
          {VOCABULARY.map((row, i) => (
            <div
              key={row.group}
              style={{
                display: "flex",
                alignItems: "baseline",
                gap: 18,
                padding: "8px 0",
                borderTop: i === 0 ? 0 : "1px solid var(--act-rule-soft)",
              }}
            >
              <span style={{ width: 74, flex: "0 0 auto" }}>
                <Label tint="var(--act-field-ink-meta)">{row.group}</Label>
              </span>
              {/* Interpuncts, not a table. A verb this Mac has never been asked
                  for is still a verb it answers to, so the list must not look
                  like a leaderboard with zeroes at the bottom of it. */}
              <span
                style={{
                  fontFamily: mono,
                  fontSize: "var(--act-caption)",
                  color: "var(--act-field-ink-2)",
                  lineHeight: 1.7,
                }}
              >
                {row.verbs.join("  ·  ")}
              </span>
            </div>
          ))}
        </div>
      </Band>

      {/* Connect appears on Home exactly once in the life of an install, and
          then never again. The window footer already carries "Agent ·
          Connected" on every page, so a row on Home saying the same thing would
          be the third place one fact is drawn — which is the habit this whole
          rewrite exists to break. The command itself belongs in Settings, beside
          the other things you set up once. */}
      {!HAS_CONNECTED && (
        <Band>
          <FirstConnect />
        </Band>
      )}
    </div>
  );
}

/**
 * The first-run state, which is the only time the block deserves any size at
 * all: the tool ledger is empty, nothing has ever driven this Mac, and the one
 * useful thing the page can do is hand over a line to paste. `hasData` on
 * `ActionToolCounts` is already the flag — a settled call in the window is the
 * only honest evidence the app has that an agent ever found it.
 */
function FirstConnect() {
  return (
    <div>
      <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
        <Label>CONNECT AN AGENT</Label>
        <span style={{ flex: 1 }} />
        <Label tint="var(--act-field-ink-meta)">MCP · STDIO</Label>
      </div>
      <div style={{ marginTop: 10, display: "flex", alignItems: "center", gap: 12 }}>
        <div
          style={{
            width: "fit-content",
            maxWidth: "100%",
            padding: "10px 14px",
            borderRadius: 8,
            background: "var(--act-field-deep)",
            fontFamily: mono,
            fontSize: "var(--act-caption)",
            lineHeight: 1.65,
            color: "var(--act-field-deep-meta)",
          }}
        >
          claude mcp add{" "}
          <span style={{ color: "var(--act-field-deep-text)", fontWeight: 600 }}>action</span> --
          action-agent stdio
        </div>
        <Chip>Copy</Chip>
      </div>
    </div>
  );
}

/* --------------------------------------------------------------- driving -- */

function Driving() {
  const live = BEATS[0];
  const earlier = BEATS.slice(1);
  const stale = LIVE_LEASE.sinceLastActSeconds >= STALE_AFTER_SECONDS;

  return (
    <div>
      <Console live={live} stale={stale} />

      <Band>
        <div style={{ display: "flex", alignItems: "baseline", gap: 10 }}>
          {/* "Earlier", because the beat happening now is the console's headline
              and printing it twice on one screen would teach the reader that the
              big line and the top row are two different facts. */}
          <Label>EARLIER BEATS</Label>
          <span style={{ flex: 1 }} />
          <span
            style={{
              fontFamily: mono,
              fontSize: "var(--act-caption)",
              color: "var(--act-field-ink-meta)",
            }}
          >
            {`${earlier.length} more · the agent's own words`}
          </span>
        </div>

        <div style={{ marginTop: 8 }}>
          {earlier.map((beat, i) => (
            <div
              key={beat.atSeconds}
              style={{
                display: "flex",
                alignItems: "baseline",
                gap: 18,
                height: 28,
                borderTop: i === 0 ? 0 : "1px solid var(--act-rule-soft)",
              }}
            >
              {/* Elapsed at the moment it was written, not a wall clock: on this
                  page every number is measured from the start of the drive, so
                  the log and the cadence rule above it share one axis. */}
              <span
                style={{
                  width: 46,
                  flex: "0 0 auto",
                  fontFamily: mono,
                  fontSize: "var(--act-caption)",
                  color: "var(--act-field-ink-meta)",
                  fontVariantNumeric: "tabular-nums",
                }}
              >
                {clock(beat.atSeconds)}
              </span>
              <span
                style={{
                  fontSize: "var(--act-row)",
                  color: "var(--act-field-ink-2)",
                  whiteSpace: "nowrap",
                  overflow: "hidden",
                  textOverflow: "ellipsis",
                }}
              >
                {beat.line}
              </span>
            </div>
          ))}
        </div>
      </Band>
    </div>
  );
}

/**
 * The console. One graphite object, the largest thing in the window, holding
 * every fact the lease carries and nothing it does not.
 *
 * The reading order is deliberately upside-down from a normal page: the loudest
 * line is not who or how long, it is *what is happening to my Mac in this
 * second*, because that is the only thing a person is actually supervising. Who
 * and how long frame it; the machine's grip on the pointer and the freshness of
 * the last act sit along the bottom, where you check them rather than read them.
 */
function Console({ live, stale }: { live: { atSeconds: number; line: string }; stale: boolean }) {
  return (
    <div
      style={{
        borderRadius: 10,
        background: "var(--act-field-deep)",
        padding: "18px 24px 16px",
      }}
    >
      <div style={{ display: "flex", alignItems: "center", gap: 9 }}>
        <Pulse stale={stale} />
        <Label tint={stale ? "var(--act-status-running)" : "var(--act-coral)"}>DRIVING</Label>
        <span
          style={{
            fontFamily: mono,
            fontSize: "var(--act-caption)",
            color: "var(--act-field-deep-meta)",
          }}
        >
          lease {LIVE_LEASE.id} · {LIVE_LEASE.mode}
        </span>
      </div>

      <div style={{ marginTop: 9, display: "flex", alignItems: "baseline", gap: 10 }}>
        <span
          style={{
            fontSize: "var(--act-subhead)",
            fontWeight: 600,
            color: "var(--act-field-deep-text)",
            flex: "0 0 auto",
          }}
        >
          {LIVE_LEASE.agent}
        </span>
        {/* The task is the promise the agent made at `drive_begin`; the headline
            below is what it is doing about it. Keeping them one above the other
            is the whole supervision question — does the thing it is doing look
            like the thing it said it would. */}
        <span
          style={{
            fontSize: "var(--act-row)",
            color: "var(--act-field-deep-meta)",
            whiteSpace: "nowrap",
            overflow: "hidden",
            textOverflow: "ellipsis",
          }}
        >
          {LIVE_LEASE.task}
        </span>
      </div>

      {/* The page's headline slot, spent on the agent's current sentence, with
          the elapsed clock on its baseline. This is the line `drive_note` exists
          to write — its documented purpose is "so the supervision HUD shows what
          you are doing" — and until now the app printed it at code size in a
          corner. At 34/300 in paper on graphite it is legible from across a
          room, which is the actual posture of someone watching an agent work.
          The clock sits beside it rather than up in the status line because
          *what* and *for how long* are the two facts a glance wants together;
          apart, the top-right of the console was a hole. */}
      <div
        style={{
          marginTop: 24,
          display: "flex",
          alignItems: "baseline",
          gap: 24,
        }}
      >
        <div
          style={{
            flex: 1,
            minWidth: 0,
            fontSize: "var(--act-headline)",
            fontWeight: 300,
            letterSpacing: "var(--act-track-headline)",
            lineHeight: 1.15,
            color: "var(--act-field-deep-text)",
            whiteSpace: "nowrap",
            overflow: "hidden",
            textOverflow: "ellipsis",
          }}
        >
          {live.line}
        </div>
        {/* Mono and tabular so the last digit does not jitter once a second on a
            surface whose whole job is to stay calm while being watched. */}
        <div
          style={{
            flex: "0 0 auto",
            fontFamily: mono,
            fontSize: "var(--act-display)",
            fontWeight: 500,
            color: "var(--act-field-deep-text)",
            fontVariantNumeric: "tabular-nums",
          }}
        >
          {clock(LIVE_LEASE.elapsedSeconds)}
        </div>
      </div>

      <Cadence />

      <div
        style={{
          marginTop: 14,
          paddingTop: 12,
          borderTop: "1px solid rgba(243, 235, 221, 0.10)",
          display: "flex",
          alignItems: "center",
          gap: 22,
        }}
      >
        {/* Pointer control is the one lease field that describes something
            physical happening to the person reading it — their cursor is being
            moved by someone else. It gets a sentence, not a chip: a chip reads
            as a setting, and this is a condition. */}
        <DeepFact label="POINTER" on={LIVE_LEASE.pointerControl}>
          {LIVE_LEASE.pointerControl ? "the cursor is being moved" : "yours"}
        </DeepFact>
        <DeepFact label="ON SCREEN" on={LIVE_LEASE.showSupervisionLabel}>
          {LIVE_LEASE.showSupervisionLabel ? "supervision label shown" : "no label"}
        </DeepFact>
        {/* `lastActAt` is the only field that separates "working" from "hung",
            which makes it the most load-bearing number on the screen after the
            sentence itself — and the only place the palette's amber is allowed
            here, because a stalled drive is news. */}
        <DeepFact label="LAST ACT" on={!stale} alert={stale}>
          {LIVE_LEASE.sinceLastActSeconds}s ago
        </DeepFact>

        <span style={{ flex: 1 }} />

        <TakeBack />
      </div>
    </div>
  );
}

/**
 * One tick per recorded beat, placed on the drive's own elapsed axis.
 *
 * This is not a progress bar and must never be mistaken for one: there is no
 * total, no fill and no destination, because the runtime records none of those.
 * What it does record is *when* every note was written, and the spacing of those
 * marks is the single most useful thing on the screen for a person who is not
 * reading — even ticks mean the agent is working, a widening gap means it is
 * thinking or stuck.
 *
 * The coral head is now, and it sits at the right edge whether or not a beat
 * landed there. The distance between the last ink tick and that head is
 * therefore the silence since the agent last said anything, drawn to scale — the
 * same fact the LAST ACT line states in words, except that this one you can see
 * growing without looking at it.
 */
function Cadence() {
  const total = LIVE_LEASE.elapsedSeconds;

  return (
    <div style={{ marginTop: 20 }}>
      {/* The marks stand *on* the axis rather than crossing or hanging from it.
          Crossing turned the whole thing into a ruler with a handle on it — a
          control you could drag — and hanging below a rule of the same weight
          just read as a dashed line. Standing on a baseline is how a chart of
          events in time is drawn, which is what this is. */}
      <div style={{ position: "relative", height: 14 }}>
        <div
          style={{
            position: "absolute",
            left: 0,
            right: 0,
            top: 10,
            height: 1,
            background: "rgba(243, 235, 221, 0.10)",
          }}
        />
        {/* Older marks are dimmer. The ramp claims nothing the positions do not
            already say — it just lets the eye find the busy end of the drive
            without counting. */}
        {BEATS.map((beat, i) => (
          <span
            key={beat.atSeconds}
            style={{
              position: "absolute",
              left: `${(beat.atSeconds / total) * 100}%`,
              top: 3,
              width: 1,
              height: 7,
              background: "var(--act-field-deep-text)",
              opacity: 0.85 - Math.min(i, 9) * 0.06,
            }}
          />
        ))}
        <span
          style={{
            position: "absolute",
            right: 0,
            top: 7,
            width: 7,
            height: 7,
            borderRadius: "50%",
            background: "var(--act-coral)",
          }}
        />
      </div>
      <div
        style={{
          marginTop: 7,
          display: "flex",
          justifyContent: "space-between",
          fontFamily: mono,
          fontSize: "var(--act-label)",
          fontWeight: 600,
          letterSpacing: "var(--act-track-label)",
          color: "var(--act-field-deep-meta)",
        }}
      >
        <span>00:00</span>
        <span>NOW</span>
      </div>
    </div>
  );
}

/** A labelled condition on graphite. Label above, value below, no box. */
function DeepFact({
  label,
  children,
  on,
  alert = false,
}: {
  label: string;
  children: React.ReactNode;
  on: boolean;
  alert?: boolean;
}) {
  return (
    <div>
      <div
        style={{
          fontFamily: mono,
          fontSize: "var(--act-label)",
          fontWeight: 600,
          letterSpacing: "var(--act-track-label)",
          color: "var(--act-field-deep-meta)",
        }}
      >
        {label}
      </div>
      <div
        style={{
          marginTop: 3,
          fontSize: "var(--act-body)",
          color: alert
            ? "var(--act-status-running)"
            : on
              ? "var(--act-field-deep-text)"
              : "var(--act-field-deep-meta)",
        }}
      >
        {children}
      </div>
    </div>
  );
}

/**
 * The one page-scale action the driving state has, and the only control on the
 * whole of Home that is not row-scale. It wears coral because it belongs to the
 * live state rather than because it wants attention: the button exists only
 * while a drive does, so its colour is the same signal as the pulse and not a
 * second meaning for it. Unfilled — a solid coral slab on graphite would be the
 * heaviest object in the app, and taking your Mac back should read as calm.
 *
 * `QuietButton` from Surface is the right component and the wrong palette: it
 * is hard-coded to chrome ink on paper. This is its graphite twin, geometry for
 * geometry, and Surface should grow a tone instead.
 */
function TakeBack() {
  return (
    <span
      style={{
        display: "inline-flex",
        alignItems: "center",
        height: 30,
        padding: "0 15px",
        border: "1px solid rgba(239, 106, 71, 0.55)",
        borderRadius: 6,
        fontSize: "var(--act-row)",
        fontWeight: 600,
        color: "var(--act-coral)",
        flex: "0 0 auto",
      }}
    >
      Take back
    </span>
  );
}

/**
 * The live mark. It breathes, because a still dot and a stopped agent look
 * identical, and the one question this page answers is whether anything is
 * still happening. When the lease goes stale the breathing stops — which is the
 * honest drawing of "nothing has come in", far more so than a colour change on
 * its own.
 */
function Pulse({ stale }: { stale: boolean }) {
  return (
    <span
      style={{
        position: "relative",
        width: 9,
        height: 9,
        flex: "0 0 auto",
        display: "inline-block",
      }}
    >
      {!stale && (
        <span
          style={{
            position: "absolute",
            inset: 0,
            borderRadius: "50%",
            background: "var(--act-coral)",
            animation: "act-pulse 2.4s ease-out infinite",
          }}
        />
      )}
      <span
        style={{
          position: "absolute",
          inset: 0,
          borderRadius: "50%",
          background: stale ? "var(--act-status-running)" : "var(--act-coral)",
        }}
      />
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

/* ---------------------------------------------------------------- shared -- */

/**
 * The band below the lead: a full-strength rule and the air around it. Home has
 * no cards in either state — the graphite console is the single exception, and
 * it is a state, not a container.
 */
function Band({ children }: { children: React.ReactNode }) {
  return (
    <div style={{ marginTop: 22 }}>
      <div style={{ height: 1, background: "var(--act-field-rule)" }} />
      <div style={{ paddingTop: 13 }}>{children}</div>
    </div>
  );
}

function Label({
  children,
  tint = "var(--act-field-ink-2)",
}: {
  children: React.ReactNode;
  tint?: string;
}) {
  return (
    <span
      style={{
        fontFamily: mono,
        fontSize: "var(--act-label)",
        fontWeight: 600,
        letterSpacing: "var(--act-track-eyebrow)",
        color: tint,
      }}
    >
      {children}
    </span>
  );
}
