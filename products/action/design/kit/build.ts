/**
 * Builds the Action design-system previews for Claude Design.
 *
 *   bun design/kit/build.ts
 *
 * Each card is a standalone HTML file: the token block from
 * design/tokens/action.css is inlined so the preview renders correctly with no
 * network and no sibling files, and the first line carries the `@dsCard`
 * marker the Design System pane indexes on.
 *
 * The bodies below are the only place the components are drawn for the web.
 * The studio (design/studio) renders the same components as React for the
 * interactive studies; both read the same tokens, so a colour can only be
 * wrong in one place at a time.
 */

import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..", "..");
const outDir = join(here, "dist");

const tokens = await readFile(join(root, "design/tokens/action.css"), "utf8");

type Card = {
  path: string;
  group: string;
  title: string;
  subtitle: string;
  body: string;
};

const base = `
  * { box-sizing: border-box; }
  body {
    margin: 0;
    padding: 28px;
    background: var(--act-canvas);
    color: var(--act-ink);
    font-family: var(--act-sans);
    font-size: var(--act-row);
    line-height: 1.5;
    -webkit-font-smoothing: antialiased;
  }
  .eyebrow {
    font-family: var(--act-mono);
    font-size: var(--act-label);
    font-weight: 600;
    letter-spacing: var(--act-track-eyebrow);
    text-transform: uppercase;
    color: var(--act-ink-muted);
  }
  .headline {
    font-size: var(--act-headline);
    font-weight: 300;
    letter-spacing: var(--act-track-headline);
    line-height: 1.1;
    margin: 3px 0 0;
  }
  .rule { height: var(--act-hairline); background: var(--act-rule); }
  .rule.soft { background: var(--act-rule-soft); }
  .note {
    margin-top: 18px;
    font-family: var(--act-mono);
    font-size: var(--act-caption);
    color: var(--act-ink-muted);
    line-height: 1.7;
    max-width: 76ch;
  }
  .caption {
    font-family: var(--act-mono);
    font-size: var(--act-label);
    letter-spacing: var(--act-track-label);
    text-transform: uppercase;
    color: var(--act-ink-muted);
    margin: 0 0 10px;
  }
`;

/* ---- shared component markup ------------------------------------------ */

const planTableCSS = `
  .tbl { --cols: var(--act-col-index) var(--act-col-verb) minmax(140px, 1fr) var(--act-col-target); }
  .tbl.notes { --cols: var(--act-col-index) var(--act-col-verb) minmax(140px, 1fr) var(--act-col-target) var(--act-col-notes); }
  .trow { display: grid; grid-template-columns: var(--cols); align-items: baseline; padding: 10px 0; }
  .thead {
    padding-bottom: 7px;
    font-family: var(--act-mono); font-size: var(--act-label); font-weight: 600;
    letter-spacing: var(--act-track-label); text-transform: uppercase; color: var(--act-ink-muted);
  }
  .c-num    { font-family: var(--act-mono); font-size: var(--act-caption); color: var(--act-ink-muted); }
  .c-verb   { font-family: var(--act-mono); font-size: var(--act-caption); color: var(--act-ink-2); }
  .c-step   { font-size: var(--act-row); color: var(--act-ink); }
  .c-target { font-family: var(--act-mono); font-size: var(--act-caption); color: var(--act-ink-muted); text-align: right; }
  .c-notes  { font-family: var(--act-mono); font-size: var(--act-caption); color: var(--act-ink-muted); text-align: right; }
  .openband { background: var(--act-row-open); margin: 0 -12px; padding: 0 12px; border-radius: 4px; }
  .opennotes { padding: 2px 0 16px calc(var(--act-col-index) + var(--act-col-verb)); }
  .fieldline .lbl {
    font-family: var(--act-mono); font-size: var(--act-label); font-weight: 600;
    letter-spacing: var(--act-track-label); text-transform: uppercase; color: var(--act-ink-muted);
  }
  .fieldline .val { font-size: var(--act-row); padding: 6px 0 8px; border-bottom: 1px solid var(--act-rule); }
  .fieldline .val.ghost { color: var(--act-ink-muted); }
`;

const controlsCSS = `
  .btn {
    display: inline-flex; align-items: center; gap: 8px;
    height: 30px; padding: 0 15px;
    border: var(--act-hairline) solid var(--act-border-quiet); border-radius: 6px;
    font-size: var(--act-row); font-weight: 600; color: var(--act-ink); background: transparent;
  }
  .btn .k { font-family: var(--act-mono); font-size: var(--act-caption); opacity: 0.55; font-weight: 400; }
  .btn.hover { background: rgba(32,40,43,0.05); border-color: rgba(32,40,43,0.5); }
  .btn.press { background: var(--act-deep); color: var(--act-on-deep); border-color: transparent; }
  .btn.off { opacity: 0.45; }
  .chip {
    display: inline-flex; align-items: center; height: 24px; padding: 0 10px;
    border: var(--act-hairline) solid var(--act-border-quiet); border-radius: 5px;
    font-family: var(--act-mono); font-size: var(--act-label); font-weight: 600;
    letter-spacing: var(--act-track-label); text-transform: uppercase; color: var(--act-ink-2);
  }
  .chip.off { opacity: 0.45; }
  .row { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
  .stack { display: grid; gap: 22px; }
  .dot { width: 7px; height: 7px; border-radius: 50%; display: inline-block; background: var(--act-coral); }
`;

function planRows(opts: { notes?: boolean } = {}) {
  const n = opts.notes;
  const cell = n ? `<div class="c-notes"></div>` : "";
  return `
    <div class="trow"><div class="c-num">01</div><div class="c-verb">type</div><div class="c-step">Enter 12</div><div class="c-target">keyboard</div>${cell}</div>
    <div class="trow"><div class="c-num">02</div><div class="c-verb">click</div><div class="c-step">Click plus</div><div class="c-target">calculator.operator.plus</div>${n ? `<div class="c-notes">1 note</div>` : ""}</div>
    <div class="trow"><div class="c-num">03</div><div class="c-verb">type</div><div class="c-step">Enter 30</div><div class="c-target">keyboard</div>${cell}</div>
    <div class="trow"><div class="c-num">04</div><div class="c-verb">press-key</div><div class="c-step">Press equals</div><div class="c-target">calculator.operator.equals</div>${cell}</div>`;
}

function planHead(opts: { notes?: boolean } = {}) {
  return `
    <div class="trow thead">
      <div>#</div><div>Verb</div><div>Step</div><div style="text-align:right">Target</div>${opts.notes ? `<div style="text-align:right">Notes</div>` : ""}
    </div>
    <div class="rule"></div>`;
}

/* ---- cards ------------------------------------------------------------- */

const cards: Card[] = [
  {
    path: "foundations/palette.html",
    group: "Foundations",
    title: "Palette",
    subtitle: "Three surfaces, three colours",
    body: `
      <style>
        .swatches { display: grid; grid-template-columns: repeat(auto-fill, minmax(132px, 1fr)); gap: 12px; margin-top: 12px; }
        .sw { border: 1px solid var(--act-rule); border-radius: 6px; overflow: hidden; background: var(--act-panel); }
        .sw .chip { display: block; height: 54px; border: 0; border-radius: 0; }
        .sw .meta { padding: 7px 9px 9px; }
        .sw .nm { font-size: var(--act-caption); color: var(--act-ink); }
        .sw .hx { font-family: var(--act-mono); font-size: var(--act-label); color: var(--act-ink-muted); letter-spacing: 0.04em; }
        section { margin-top: 26px; }
      </style>
      <div class="eyebrow">Foundations</div>
      <div class="headline">Palette</div>

      <section>
        <p class="caption">Chrome — the frame around the work</p>
        <div class="swatches">
          ${sw("Canvas", "var(--act-canvas)", "#F3EBDD")}
          ${sw("Band", "var(--act-band)", "#ECE2CF")}
          ${sw("Panel", "var(--act-panel)", "#FAF5EB")}
          ${sw("Raised", "var(--act-panel-raised)", "#FFFDF6")}
          ${sw("Deep", "var(--act-deep)", "#25231F")}
        </div>
      </section>

      <section>
        <p class="caption">Ink ramp</p>
        <div class="swatches">
          ${sw("Ink", "var(--act-ink)", "#20282B")}
          ${sw("Secondary", "var(--act-ink-2)", "#596261")}
          ${sw("Row", "var(--act-ink-row)", "#3D4241")}
          ${sw("Muted", "var(--act-ink-muted)", "#877F76")}
          ${sw("Meta", "var(--act-ink-meta)", "#8A8175")}
        </div>
      </section>

      <section>
        <p class="caption">The three colours, and what each one means</p>
        <div class="swatches">
          ${sw("Coral — live", "var(--act-coral)", "#EF6A47")}
          ${sw("Blue — selected", "var(--act-review-accent)", "#3078E6")}
          ${sw("Cyan — result", "var(--act-signal)", "#1FB9C6")}
          ${sw("Field tan", "var(--act-field-ink-muted)", "#A77850")}
        </div>
      </section>

      <p class="note">
        Colour is spent on meaning, never on emphasis. Coral means a drive is live and appears
        nowhere else — not on a Copy button, not on a selected theme card. Blue means selected and
        never leaves the 2pt sidebar rail. Everything a pointer touches is ink at 3.5%.
      </p>`,
  },
  {
    path: "foundations/type.html",
    group: "Foundations",
    title: "Type scale",
    subtitle: "Named roles · SF Pro + JetBrains Mono",
    body: `
      <style>
        .spec { width: 100%; border-collapse: collapse; margin-top: 14px; }
        .spec th {
          text-align: left; font-family: var(--act-mono); font-size: var(--act-label); font-weight: 600;
          letter-spacing: var(--act-track-label); text-transform: uppercase; color: var(--act-ink-muted);
          padding: 0 16px 8px 0; border-bottom: 1px solid var(--act-rule); white-space: nowrap;
        }
        .spec td { padding: 13px 16px 13px 0; border-bottom: 1px solid var(--act-rule-soft); vertical-align: baseline; }
        .spec td.k { font-family: var(--act-mono); font-size: var(--act-caption); color: var(--act-ink-2); white-space: nowrap; }
        .spec td.d { font-size: var(--act-caption); color: var(--act-ink-muted); }
      </style>
      <div class="eyebrow">Foundations</div>
      <div class="headline">Type scale</div>

      <table class="spec">
        <thead><tr><th style="width:150px">Role</th><th style="width:340px">Specimen</th><th>Where</th></tr></thead>
        <tbody>
          ${ty("uiHeadline", "34 / 300 / -0.7", "Calculator demo", "font-size:34px;font-weight:300;letter-spacing:-0.7px", "The one line a page opens with. Light, because at this size weight is not what makes a line read.")}
          ${ty("uiTitle", "22 / 400 / -0.25", "Scenarios", "font-size:22px;font-weight:400;letter-spacing:-0.25px", "Page and section titles. Regular — the mono eyebrow above it already separates them.")}
          ${ty("uiSubhead", "15 / 600", "Panel heading", "font-size:15px;font-weight:600", "Headings inside a page.")}
          ${ty("uiRow", "13 / 400", "Press equals", "font-size:13px", "Content: a step, a take — the thing itself, not chrome around it.")}
          ${ty("uiNav", "13 / 500", "Scenarios", "font-size:13px;font-weight:500", "Navigation. Medium at rest and medium when selected, so the label never changes width.")}
          ${ty("uiBody", "12 / 400", "Chrome prose", "font-size:12px", "A sentence read as chrome.")}
          ${ty("uiCaption", "11 / 400", "4 mins ago", "font-size:11px", "Supporting text.")}
          ${ty("code", "mono 11", "calculator.operator.plus", "font-family:var(--act-mono);font-size:11px", "Commands, counts, durations, selectors.")}
          ${ty("label", "mono 9 / 600 / +0.9", "TARGET", "font-family:var(--act-mono);font-size:9px;font-weight:600;letter-spacing:0.9px", "Eyebrows, chips, column headers. Always tracked.")}
        </tbody>
      </table>

      <p class="note">
        Two families per surface. The serif sets exactly one line in the whole app — the sentence on
        Home that says who is driving this Mac — and appears in none of these studies.
      </p>`,
  },
  {
    path: "components/plan-table.html",
    group: "Components",
    title: "Plan table",
    subtitle: "Plan / running / review — one grid",
    body: `
      <style>${planTableCSS}${controlsCSS}
        .state { margin-top: 30px; }
        .state:first-of-type { margin-top: 16px; }
      </style>
      <div class="eyebrow">Components</div>
      <div class="headline">Plan table</div>

      <div class="state">
        <p class="caption">Plan — a step is open, its note hangs under the step column</p>
        <div class="tbl">
          ${planHead()}
          <div class="trow"><div class="c-num">01</div><div class="c-verb">type</div><div class="c-step">Enter 12</div><div class="c-target">keyboard</div></div>
          <div class="openband">
            <div class="trow"><div class="c-num">02</div><div class="c-verb">click</div><div class="c-step">Click plus</div><div class="c-target">calculator.operator.plus</div></div>
            <div class="opennotes">
              <div class="fieldline"><div class="lbl">Note</div><div class="val ghost">Wait for Calculator to finish opening</div></div>
              <div class="row" style="margin-top:12px"><span class="chip off">Add note</span><span class="chip">Skip</span></div>
            </div>
          </div>
          <div class="trow"><div class="c-num">03</div><div class="c-verb">type</div><div class="c-step">Enter 30</div><div class="c-target">keyboard</div></div>
          <div class="trow"><div class="c-num">04</div><div class="c-verb">press-key</div><div class="c-step">Press equals</div><div class="c-target">calculator.operator.equals</div></div>
          <div class="rule soft"></div>
        </div>
      </div>

      <div class="state">
        <p class="caption">Running — rows inert, one coral dot, Stop in the slot Run had</p>
        <div class="tbl">
          ${planHead()}
          ${planRows()}
          <div class="rule soft"></div>
        </div>
        <div class="row" style="margin-top:18px"><span class="dot"></span>
          <span style="font-family:var(--act-mono);font-size:var(--act-caption);color:var(--act-ink-2)">Driving Calculator</span>
          <span class="chip">Stop</span>
        </div>
      </div>

      <div class="state">
        <p class="caption">Review — with notes, the fifth column earns its header</p>
        <div class="tbl notes">
          ${planHead({ notes: true })}
          ${planRows({ notes: true })}
          <div class="rule soft"></div>
        </div>
      </div>

      <p class="note">
        The grid never rearranges. A state appends a column rather than redrawing the table, so the
        row you read before the run is the row you watch during it and the row you judge after it —
        same place, same width, same face. The notes column appears only once some step has one: a
        heading over four blank cells is furniture describing an absence.
      </p>`,
  },
  {
    path: "components/controls.html",
    group: "Components",
    title: "Controls",
    subtitle: "Quiet primary, chip, field on a rule",
    body: `
      <style>${controlsCSS}${planTableCSS}
        .grp { margin-top: 26px; }
      </style>
      <div class="eyebrow">Components</div>
      <div class="headline">Controls</div>

      <div class="grp">
        <p class="caption">Primary — one per state, four states</p>
        <div class="row">
          <span class="btn">Run <span class="k">&#9166;</span></span>
          <span class="btn hover">Run <span class="k">&#9166;</span></span>
          <span class="btn press">Run <span class="k">&#9166;</span></span>
          <span class="btn off">Run <span class="k">&#9166;</span></span>
        </div>
        <p class="note" style="margin-top:12px">
          Rest · hover · press · disabled. A filled black pill is the loudest object on a page that
          has nothing else on it, and it makes the one thing you can do look like a warning. The
          emphasis arrives at the click instead of sitting on the page waiting for it.
        </p>
      </div>

      <div class="grp">
        <p class="caption">Chip — the secondary everywhere</p>
        <div class="row">
          <span class="chip">Plan</span>
          <span class="chip">Replay</span>
          <span class="chip">Finder</span>
          <span class="chip">Skip</span>
          <span class="chip off">Add note</span>
        </div>
      </div>

      <div class="grp">
        <p class="caption">Field — on a rule, not in a box</p>
        <div class="fieldline" style="max-width:420px">
          <div class="lbl">Goal</div>
          <div class="val">Calculator, keyboard and click</div>
        </div>
        <div class="fieldline" style="max-width:420px;margin-top:18px">
          <div class="lbl">Note</div>
          <div class="val ghost">Wait for Calculator to finish opening</div>
        </div>
        <p class="note" style="margin-top:12px">
          A filled, bordered, rounded field is four pieces of furniture around one line of text. A
          hairline under the text says the same thing and leaves the page made of one kind of mark.
        </p>
      </div>`,
  },
  {
    path: "components/rows.html",
    group: "Components",
    title: "Rows and rails",
    subtitle: "Sidebar item, ledger row, open row",
    body: `
      <style>${controlsCSS}
        .rail { width: 200px; background: var(--act-band); border-radius: 8px; padding: 8px; }
        .nav { display: flex; align-items: center; gap: 10px; height: 32px; padding: 0 10px; border-radius: 6px;
               font-size: var(--act-nav); font-weight: 500; color: var(--act-ink-2); position: relative; }
        .nav .g { width: 14px; height: 14px; border-radius: 3px; border: 1.5px solid currentColor; opacity: 0.75; }
        .nav.on { background: rgba(32,40,43,0.055); color: var(--act-ink); }
        .nav.on::before { content: ""; position: absolute; left: 0; top: 8px; bottom: 8px; width: 2px;
                          border-radius: 1px; background: var(--act-review-accent); }
        .nav.hov { background: rgba(32,40,43,0.03); }

        .ledger { flex: 1; min-width: 340px; }
        .lrow { display: grid; grid-template-columns: 8px 1fr 62px 48px 70px; align-items: center; gap: 12px; height: 40px; }
        .lrow.on { background: var(--act-row-open); margin: 0 -12px; padding: 0 12px; border-radius: 4px; }
        .lt { font-size: var(--act-row); font-weight: 600; color: var(--act-ink-row); }
        .lk { font-family: var(--act-mono); font-size: var(--act-label); font-weight: 600; letter-spacing: var(--act-track-label);
              text-transform: uppercase; color: var(--act-ink-2); text-align: center; }
        .ld { font-family: var(--act-mono); font-size: var(--act-caption); color: var(--act-ink-meta); text-align: right; }
        .lo { width: 6px; height: 6px; border-radius: 50%; border: 1px solid var(--act-ink-muted); }
        .lo.done { background: #3E7A4E; border-color: #3E7A4E; }
        .ldetail { padding: 0 0 13px; }
        .fact { font-family: var(--act-mono); font-size: var(--act-label); font-weight: 600; letter-spacing: var(--act-track-label);
                text-transform: uppercase; color: var(--act-ink-meta); }
        .factv { font-size: var(--act-caption); color: var(--act-ink-row); }
        .split { display: flex; gap: 30px; align-items: flex-start; margin-top: 16px; flex-wrap: wrap; }
      </style>
      <div class="eyebrow">Components</div>
      <div class="headline">Rows and rails</div>

      <div class="split">
        <div>
          <p class="caption">Sidebar</p>
          <div class="rail">
            <div class="nav"><span class="g"></span>Home</div>
            <div class="nav on"><span class="g"></span>Scenarios</div>
            <div class="nav hov"><span class="g"></span>Runs</div>
            <div class="nav"><span class="g"></span>Library</div>
          </div>
        </div>

        <div class="ledger">
          <p class="caption">Ledger — a click opens the row, not a window</p>
          <div class="rule"></div>
          <div class="lrow">
            <span class="lo done"></span><span class="lt">Final look at Settings</span>
            <span class="lk">Drive</span><span class="ld">27s</span><span class="ld">28 mins ago</span>
          </div>
          <div class="rule soft"></div>
          <div class="lrow on">
            <span class="lo"></span><span class="lt">Look at the ruled Runs ledger</span>
            <span class="lk">Drive</span><span class="ld">41s</span><span class="ld"></span>
          </div>
          <div class="lrow on" style="height:auto">
            <span></span>
            <div class="ldetail" style="grid-column: 2 / -1">
              <div style="font-family:var(--act-mono);font-size:var(--act-caption);color:var(--act-ink-meta)">drive_20260820_051922770</div>
              <div class="row" style="gap:14px;margin-top:5px">
                <span><span class="fact">When</span> <span class="factv">Thu, Aug 20 at 01:19</span></span>
                <span><span class="fact">By</span> <span class="factv">Claude Code</span></span>
                <span><span class="fact">Outcome</span> <span class="factv">Unfinished</span></span>
                <span style="margin-left:auto"><span class="chip">Trace</span> <span class="chip">Finder</span></span>
              </div>
            </div>
          </div>
          <div class="rule soft"></div>
          <div class="lrow">
            <span class="lo"></span><span class="lt">Check Runs, Library and Settings</span>
            <span class="lk">Drive</span><span class="ld">12s</span><span class="ld">31 mins ago</span>
          </div>
          <div class="rule soft"></div>
        </div>
      </div>

      <p class="note">
        Ruled rows on paper, not zebra stripes in a bordered card: banding paints two tones of
        furniture behind every row and still needs the box to say where the day ends. Nothing sits
        behind a row but the two states an operator creates — pointing at it, and having opened it.
      </p>`,
  },
];

function sw(name: string, value: string, hex: string) {
  return `<div class="sw"><span class="chip" style="background:${value}"></span><span class="meta"><span class="nm">${name}</span><br><span class="hx">${hex}</span></span></div>`;
}

function ty(role: string, spec: string, sample: string, style: string, where: string) {
  return `<tr><td class="k">${role}<br><span style="opacity:0.6">${spec}</span></td><td><span style="${style}">${sample}</span></td><td class="d">${where}</td></tr>`;
}

/* ---- emit -------------------------------------------------------------- */

await mkdir(join(outDir, "foundations"), { recursive: true });
await mkdir(join(outDir, "components"), { recursive: true });

for (const card of cards) {
  const html = `<!-- @dsCard group="${card.group}" name="${card.title}" subtitle="${card.subtitle}" -->
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Action · ${card.title}</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;600&display=swap">
<style>
${tokens}
${base}
</style>
</head>
<body>
${card.body}
</body>
</html>
`;
  await writeFile(join(outDir, card.path), html, "utf8");
  console.log(`  ${card.path}`);
}

console.log(`\n${cards.length} cards → design/kit/dist`);
