"use client";

import { useState } from "react";
import type { CSSProperties, ReactNode } from "react";

/**
 * Action's own look, in the browser.
 *
 * The studio shell is dark Hudson chrome; a study of a paper-and-graphite Mac
 * app has to draw its own world inside that. `ActionFrame` opens that world —
 * canvas, ink, both faces — and everything below it is the app's real
 * geometry, read from `design/tokens/action.css`, which is itself transcribed
 * from `native/engine/Sources/ActionThemeBuiltin.swift`.
 *
 * These are deliberately the same components as the Claude Design previews in
 * `design/kit`. If the two ever disagree, the tokens file is the tiebreak and
 * the Swift is the tiebreak above that.
 */

const mono = "var(--act-mono)";
const sans = "var(--act-sans)";

/* ---------------------------------------------------------------- frame -- */

export function ActionFrame({
  children,
  pad = 30,
}: {
  children: ReactNode;
  pad?: number;
}) {
  return (
    <div
      style={{
        background: "var(--act-canvas)",
        color: "var(--act-ink)",
        fontFamily: sans,
        border: "1px solid var(--act-rule)",
        borderRadius: 10,
        padding: pad,
        overflowX: "auto",
      }}
    >
      <div style={{ minWidth: 700 }}>{children}</div>
    </div>
  );
}

export function Caption({ children }: { children: ReactNode }) {
  return (
    <p
      style={{
        margin: "10px 0 0",
        fontFamily: mono,
        fontSize: 10,
        letterSpacing: "0.07em",
        textTransform: "uppercase",
        color: "var(--act-ink-muted)",
      }}
    >
      {children}
    </p>
  );
}

/* --------------------------------------------------------------- heading -- */

export function PageHeading({
  eyebrow,
  title,
  switcher = false,
  counter,
}: {
  eyebrow: string;
  title: string;
  /** The name carries the chevron and owns the menu — it *is* the switcher. */
  switcher?: boolean;
  counter?: string;
}) {
  return (
    <div>
      <div
        style={{
          fontFamily: mono,
          fontSize: 9,
          fontWeight: 600,
          letterSpacing: "var(--act-track-eyebrow)",
          textTransform: "uppercase",
          color: "var(--act-ink-muted)",
        }}
      >
        {eyebrow}
      </div>
      <div
        style={{
          display: "flex",
          alignItems: "baseline",
          gap: 9,
          marginTop: 3,
          fontSize: "var(--act-headline)",
          fontWeight: 300,
          letterSpacing: "var(--act-track-headline)",
          lineHeight: 1.1,
        }}
      >
        <span>{title}</span>
        {switcher && (
          <span style={{ fontSize: 14, color: "var(--act-ink-muted)" }}>▾</span>
        )}
        {counter && (
          <span
            style={{
              fontFamily: mono,
              fontSize: 11,
              color: "var(--act-ink-muted)",
            }}
          >
            {counter}
          </span>
        )}
      </div>
    </div>
  );
}

/* ----------------------------------------------------------------- rules -- */

export function Rule({ soft = false }: { soft?: boolean }) {
  return (
    <div
      style={{
        height: 1,
        background: soft ? "var(--act-rule-soft)" : "var(--act-rule)",
      }}
    />
  );
}

/* ----------------------------------------------------------------- table -- */

export type Step = {
  index: number;
  verb: string;
  step: string;
  target: string;
  note?: string;
  skipped?: boolean;
};

function grid(withNotes: boolean): CSSProperties {
  return {
    display: "grid",
    gridTemplateColumns: withNotes
      ? "var(--act-col-index) var(--act-col-verb) minmax(140px, 1fr) var(--act-col-target) var(--act-col-notes)"
      : "var(--act-col-index) var(--act-col-verb) minmax(140px, 1fr) var(--act-col-target)",
    alignItems: "baseline",
  };
}

const headCell: CSSProperties = {
  fontFamily: mono,
  fontSize: 9,
  fontWeight: 600,
  letterSpacing: "var(--act-track-label)",
  textTransform: "uppercase",
  color: "var(--act-ink-muted)",
};

/**
 * The one table. `openIndex` opens a step's notes under it; `interactive`
 * false is running (a run must not be annotated out from under itself) and the
 * start page (nothing saved yet to annotate).
 */
export function PlanTable({
  steps,
  openIndex,
  onToggle,
  interactive = true,
}: {
  steps: Step[];
  openIndex?: number | null;
  onToggle?: (index: number) => void;
  interactive?: boolean;
}) {
  // The notes column earns its header only once something has been said. A
  // heading over four blank cells is furniture describing an absence.
  const withNotes = steps.some((s) => s.skipped || s.note);

  return (
    <div>
      <div style={{ ...grid(withNotes), paddingBottom: 7 }}>
        <div style={headCell}>#</div>
        <div style={headCell}>Verb</div>
        <div style={headCell}>Step</div>
        <div style={{ ...headCell, textAlign: "right" }}>Target</div>
        {withNotes && (
          <div style={{ ...headCell, textAlign: "right" }}>Notes</div>
        )}
      </div>

      <Rule />

      {steps.map((s) => (
        <PlanRow
          key={s.index}
          step={s}
          open={interactive && openIndex === s.index}
          interactive={interactive}
          withNotes={withNotes}
          onToggle={onToggle}
        />
      ))}

      <Rule soft />
    </div>
  );
}

/**
 * One row. Hover is its own state and it is ink at 3.5% — the token existed and
 * this table never used it, so rows were `cursor: pointer` with no feedback at
 * all. The band also does the work Home's ACTIONS list does with a dot leader:
 * it bridges the long unaided gap between STEP and TARGET. Two solutions to one
 * problem in one app is one too many, and the band is the cheaper one.
 *
 * No horizontal bleed. The ground used to overhang 12pt each side, so it stuck
 * out past the header rule above it and the soft rule below it.
 *
 * The tint lands on the row head only, never on the expansion. Stretched over a
 * 270pt open step with a corner radius it stopped being a pointer state and
 * became the largest filled card in the window — the exact object Home spent a
 * whole pass deleting. Home's ledger already gets this right: tint the head,
 * leave what it opened on bare paper, held by the indent.
 */
function PlanRow({
  step: s,
  open,
  interactive,
  withNotes,
  onToggle,
}: {
  step: Step;
  open: boolean;
  interactive: boolean;
  withNotes: boolean;
  onToggle?: (index: number) => void;
}) {
  const [hovered, setHovered] = useState(false);

  const headFill = open
    ? "var(--act-row-open)"
    : interactive && hovered
      ? "var(--act-row-hover)"
      : "transparent";

  return (
    <div
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
    >
      <div
        style={{
          ...grid(withNotes),
          padding: "10px 0",
          background: headFill,
          cursor: interactive ? "pointer" : "default",
        }}
        onClick={() => interactive && onToggle?.(s.index)}
      >
        <span
          style={{
            fontFamily: mono,
            fontSize: 11,
            color: "var(--act-ink-muted)",
          }}
        >
          {String(s.index).padStart(2, "0")}
        </span>
        <span
          style={{ fontFamily: mono, fontSize: 11, color: "var(--act-ink-2)" }}
        >
          {s.verb}
        </span>
        <span
          style={{
            fontSize: "var(--act-row)",
            color: s.skipped ? "var(--act-ink-muted)" : "var(--act-ink)",
            textDecoration: s.skipped ? "line-through" : "none",
          }}
        >
          {s.step}
        </span>
        <span
          style={{
            fontFamily: mono,
            fontSize: 11,
            color: "var(--act-ink-muted)",
            textAlign: "right",
            overflow: "hidden",
            whiteSpace: "nowrap",
            textOverflow: "ellipsis",
          }}
        >
          {s.target}
        </span>
        {withNotes && (
          <span
            style={{
              fontFamily: mono,
              fontSize: 11,
              color: "var(--act-ink-muted)",
              textAlign: "right",
            }}
          >
            {s.skipped ? "skipped" : s.note ? "1 note" : ""}
          </span>
        )}
      </div>

      {open && <StepNotes step={s} />}
    </div>
  );
}

/** Aligned under the STEP column it belongs to — 26 + 86. */
function StepNotes({ step }: { step: Step }) {
  return (
    <div
      style={{
        paddingLeft: "calc(var(--act-col-index) + var(--act-col-verb))",
        paddingTop: 2,
        paddingBottom: 16,
        display: "grid",
        gap: 12,
      }}
    >
      {step.note && (
        <div style={{ display: "flex", gap: 9, alignItems: "baseline" }}>
          <span
            style={{
              fontFamily: mono,
              fontSize: 11,
              color: "var(--act-ink-muted)",
            }}
          >
            —
          </span>
          <span style={{ fontSize: "var(--act-row)" }}>{step.note}</span>
        </div>
      )}
      <Field label="Note" placeholder="Wait for Calculator to finish opening" />
      {/* One field, one chip. There is no Add-note affordance in the Swift —
          the field commits the note — and a control disabled in every state the
          study can draw is furniture competing with Skip. */}
      <div style={{ display: "flex", gap: 8 }}>
        <Chip>{step.skipped ? "Include" : "Skip"}</Chip>
      </div>
    </div>
  );
}

/* ----------------------------------------------------------------- field -- */

export function Field({
  label,
  value,
  placeholder,
}: {
  label: string;
  value?: string;
  placeholder?: string;
}) {
  return (
    <div>
      <div
        style={{
          fontFamily: mono,
          fontSize: 9,
          fontWeight: 600,
          letterSpacing: "var(--act-track-label)",
          textTransform: "uppercase",
          color: "var(--act-ink-muted)",
        }}
      >
        {label}
      </div>
      <div
        style={{
          fontSize: "var(--act-row)",
          color: value ? "var(--act-ink)" : "var(--act-ink-muted)",
          padding: "6px 0 8px",
          borderBottom: "1px solid var(--act-rule)",
        }}
      >
        {value ?? placeholder}
      </div>
    </div>
  );
}

/* --------------------------------------------------------------- buttons -- */

export function QuietButton({
  children,
  shortcut,
  disabled,
}: {
  children: ReactNode;
  shortcut?: string;
  disabled?: boolean;
}) {
  return (
    <span
      style={{
        display: "inline-flex",
        alignItems: "center",
        gap: 8,
        height: 30,
        padding: "0 15px",
        border: "1px solid var(--act-border-quiet)",
        borderRadius: 6,
        fontSize: "var(--act-row)",
        fontWeight: 600,
        color: "var(--act-ink)",
        opacity: disabled ? 0.45 : 1,
      }}
    >
      {children}
      {shortcut && (
        <span
          style={{
            fontFamily: mono,
            fontSize: 11,
            opacity: 0.55,
            fontWeight: 400,
          }}
        >
          {shortcut}
        </span>
      )}
    </span>
  );
}

/**
 * The row-scale control. `QuietButton` at 30pt is the page-scale one — Run,
 * Stop, Run again — and this is its 24pt counterpart for actions that live
 * inside a table row: Skip, Grant, Reveal. Two steps, and the app needs no
 * third: a component with this geometry and QuietButton's typography is what
 * makes the window look like it has two quiet-button sizes.
 */
export function Chip({
  children,
  disabled,
}: {
  children: ReactNode;
  disabled?: boolean;
}) {
  const [hovered, setHovered] = useState(false);
  return (
    <span
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      style={{
        background: hovered && !disabled ? "var(--act-row-hover)" : "transparent",
        display: "inline-flex",
        alignItems: "center",
        height: 24,
        padding: "0 10px",
        border: "1px solid var(--act-border-quiet)",
        borderRadius: 5,
        fontFamily: mono,
        fontSize: 9,
        fontWeight: 600,
        letterSpacing: "var(--act-track-label)",
        textTransform: "uppercase",
        color: "var(--act-ink-2)",
        opacity: disabled ? 0.45 : 1,
      }}
    >
      {children}
    </span>
  );
}

/** Coral means a drive is live, and means it nowhere else. */
export function LiveDot() {
  return (
    <span
      style={{
        width: 7,
        height: 7,
        borderRadius: "50%",
        background: "var(--act-coral)",
        display: "inline-block",
      }}
    />
  );
}

export function Meta({ children }: { children: ReactNode }) {
  return (
    <span
      style={{ fontFamily: mono, fontSize: 11, color: "var(--act-ink-muted)" }}
    >
      {children}
    </span>
  );
}
