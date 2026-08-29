"use client";

import { ActionFrame, Caption } from "@/studio/action/Surface";
import { Note, Prose, StudyShell } from "@/studio/studies/StudyShell";
import type { ActionPage } from "@/studio/studioRegistry";

/**
 * Foundations. Everything here is transcribed from the Swift theme, not
 * invented for the web — see design/tokens/action.css for the note on why
 * nothing generates it.
 */

const CHROME = [
  ["Canvas", "--act-canvas", "#F3EBDD"],
  ["Band", "--act-band", "#ECE2CF"],
  ["Panel", "--act-panel", "#FAF5EB"],
  ["Raised", "--act-panel-raised", "#FFFDF6"],
  ["Deep", "--act-deep", "#25231F"],
] as const;

const INK = [
  ["Ink", "--act-ink", "#20282B"],
  ["Secondary", "--act-ink-2", "#596261"],
  ["Row", "--act-ink-row", "#3D4241"],
  ["Muted", "--act-ink-muted", "#877F76"],
  ["Meta", "--act-ink-meta", "#8A8175"],
] as const;

const MEANING = [
  ["Coral", "--act-coral", "#EF6A47", "a drive is live"],
  ["Blue", "--act-review-accent", "#3078E6", "selected"],
  ["Cyan", "--act-signal", "#1FB9C6", "a result"],
  ["Field tan", "--act-field-ink-muted", "#A77850", "Home's accent voice"],
] as const;

const TYPE = [
  ["uiHeadline", "34 / 300 / −0.7", "Calculator demo", { fontSize: 34, fontWeight: 300, letterSpacing: "-0.7px" }],
  ["uiTitle", "22 / 400 / −0.25", "Scenarios", { fontSize: 22, fontWeight: 400, letterSpacing: "-0.25px" }],
  ["uiSubhead", "15 / 600", "Panel heading", { fontSize: 15, fontWeight: 600 }],
  ["uiRow", "13 / 400", "Press equals", { fontSize: 13 }],
  ["uiNav", "13 / 500", "Scenarios", { fontSize: 13, fontWeight: 500 }],
  ["uiBody", "12 / 400", "Chrome prose", { fontSize: 12 }],
  ["uiCaption", "11 / 400", "4 mins ago", { fontSize: 11 }],
  ["code", "mono 11", "calculator.operator.plus", { fontFamily: "var(--act-mono)", fontSize: 11 }],
  ["label", "mono 9 / 600 / +0.9", "TARGET", { fontFamily: "var(--act-mono)", fontSize: 9, fontWeight: 600, letterSpacing: "0.9px" }],
] as const;

export function TokensStudy({ page }: { page: ActionPage }) {
  return (
    <StudyShell page={page}>
      <section>
        <h2>Palette</h2>
        <Prose>
          Three surfaces, each with its own ink ramp, exactly as the app has them: chrome is the
          frame around the work, field is Home speaking in the brand&apos;s own voice, review is a
          cool sheet where warm paper would fight the take.
        </Prose>
        <ActionFrame>
          <Group title="Chrome" swatches={CHROME} />
          <Group title="Ink ramp" swatches={INK} />
          <Group title="The three colours, and what each one means" swatches={MEANING} />
        </ActionFrame>
        <Caption>Light appearance</Caption>
      </section>

      <section>
        <h2>Type</h2>
        <Prose>
          The named roles are the whole scale. Reaching past them for an ad-hoc size is how a
          surface ends up with ten sizes that are each two points apart and none of which mean
          anything — which is exactly what happened before these existed.
        </Prose>
        <ActionFrame>
          <table style={{ width: "100%", borderCollapse: "collapse" }}>
            <tbody>
              {TYPE.map(([role, spec, sample, style]) => (
                <tr key={role} style={{ borderBottom: "1px solid var(--act-rule-soft)" }}>
                  <td
                    style={{
                      width: 170,
                      padding: "13px 16px 13px 0",
                      fontFamily: "var(--act-mono)",
                      fontSize: 11,
                      color: "var(--act-ink-2)",
                      verticalAlign: "baseline",
                      whiteSpace: "nowrap",
                    }}
                  >
                    {role}
                    <br />
                    <span style={{ opacity: 0.6 }}>{spec}</span>
                  </td>
                  <td style={{ padding: "13px 0", verticalAlign: "baseline" }}>
                    <span style={style as React.CSSProperties}>{sample}</span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </ActionFrame>
        <Caption>SF Pro + JetBrains Mono — two families per surface</Caption>
      </section>

      <Note title="Colour is spent on meaning">
        Coral means a drive is live and appears nowhere else — not on a Copy button, not as a ring
        round a selected theme card, not behind a row you are pointing at. Blue means selected and
        never leaves the 2pt sidebar rail. Everything a pointer touches is ink at 3.5%. The app had
        four decorative hues in one panel on Home before this rule existed.
      </Note>
    </StudyShell>
  );
}

function Group({
  title,
  swatches,
}: {
  title: string;
  swatches: readonly (readonly [string, string, string] | readonly [string, string, string, string])[];
}) {
  return (
    <div style={{ marginBottom: 26 }}>
      <p
        style={{
          margin: "0 0 10px",
          fontFamily: "var(--act-mono)",
          fontSize: 9,
          fontWeight: 600,
          letterSpacing: "var(--act-track-label)",
          textTransform: "uppercase",
          color: "var(--act-ink-muted)",
        }}
      >
        {title}
      </p>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(132px, 1fr))", gap: 12 }}>
        {swatches.map(([name, varName, hex, means]) => (
          <div
            key={name}
            style={{
              border: "1px solid var(--act-rule)",
              borderRadius: 6,
              overflow: "hidden",
              background: "var(--act-panel)",
            }}
          >
            <div style={{ height: 54, background: `var(${varName})` }} />
            <div style={{ padding: "7px 9px 9px" }}>
              <div style={{ fontSize: 11, color: "var(--act-ink)" }}>{name}</div>
              <div
                style={{
                  fontFamily: "var(--act-mono)",
                  fontSize: 9,
                  color: "var(--act-ink-muted)",
                  letterSpacing: "0.04em",
                }}
              >
                {means ? `${hex} · ${means}` : hex}
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
