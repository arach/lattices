"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";

import { SCENARIOS } from "@/studio/action/fixtures";
import { LiveDot } from "@/studio/action/Surface";
import { HomeSection, type HomeState } from "@/studio/action/sections/HomeSection";
import { AgentsSection, type AgentsState } from "@/studio/action/sections/AgentsSection";
import { TracesSection } from "@/studio/action/sections/TracesSection";
import {
  ScenariosSection,
  type ScenarioState,
} from "@/studio/action/sections/ScenariosSection";
import { PERMISSIONS } from "@/studio/action/fixtures";
import { SettingsSection } from "@/studio/action/sections/SettingsSection";
import {
  ActionWindow,
  SECTIONS,
  WindowPageBody,
  WindowPageHeader,
  type Section,
} from "@/studio/action/Window";
import { Note, Prose, StudyShell } from "@/studio/studies/StudyShell";
import type { ActionPage } from "@/studio/studioRegistry";

/**
 * The whole window, at true size, navigable.
 *
 * The other studies take one surface at a time, which is how a page ends up
 * beautiful on its own and wrong next to the four it lives beside. This one
 * draws the actual window — title bar, rail, footer, all five sections — so a
 * change can be judged where it will actually be seen.
 *
 * Two controls sit above it and both drive real behaviour: the window size
 * (the app's own minimum, default and a wide desk) and the rail collapse. What
 * reflows in here reflows in AppKit for the same reason.
 */

/** From ActionLauncherController (default) and the root view's frame floor. */
const SIZES = [
  { key: "min", label: "Minimum", w: 1100, h: 720, note: "the frame floor — the window cannot go smaller" },
  { key: "default", label: "Default", w: 1240, h: 820, note: "what opens on first launch" },
  { key: "wide", label: "Wide", w: 1600, h: 940, note: "a full-height half of a 32in desk" },
] as const;

type SizeKey = (typeof SIZES)[number]["key"];

export function AppStudy({ page }: { page: ActionPage }) {
  const [section, setSection] = useState<Section>("home");
  const [sizeKey, setSizeKey] = useState<SizeKey>("default");
  const [collapsed, setCollapsed] = useState(false);
  const [scenarioState, setScenarioState] = useState<ScenarioState>("plan");
  const [homeState, setHomeState] = useState<HomeState>("idle");
  // Settings reads completely differently depending on whether anything is
  // wrong, and the healthy state is the one a mock never shows you.
  const [permsOk, setPermsOk] = useState(false);
  const [agentsState, setAgentsState] = useState<AgentsState>("registry");

  const size = SIZES.find((s) => s.key === sizeKey)!;
  const { ref, scale } = useFitScale(size.w);
  const compact = size.w <= 1100;

  return (
    <StudyShell page={page} wide>
      <Prose>
        Every other study in here draws one surface on a white page. That is how
        a page ends up beautiful on its own and wrong beside the four it lives
        next to — a heading that is right at 760px, a filter strip that only
        fits on a wide desk, two different answers to &ldquo;which one is
        selected&rdquo; eighteen inches apart. This one draws the window.
      </Prose>

      <div style={{ marginTop: 26 }}>
        <Controls
          sizeKey={sizeKey}
          onSize={setSizeKey}
          section={section}
          scenarioState={scenarioState}
          onScenarioState={setScenarioState}
          homeState={homeState}
          onHomeState={setHomeState}
          permsOk={permsOk}
          onPermsOk={setPermsOk}
          agentsState={agentsState}
          onAgentsState={setAgentsState}
        />

        <div ref={ref} style={{ marginTop: 14 }}>
          <div style={{ height: size.h * scale, overflow: "hidden" }}>
            <div
              style={{
                width: size.w,
                transform: `scale(${scale})`,
                transformOrigin: "top left",
              }}
            >
              <ActionWindow
                width={size.w}
                height={size.h}
                section={section}
                onSection={setSection}
                collapsed={collapsed}
                onToggleCollapse={() => setCollapsed((c) => !c)}
                fieldCanvas={section === "home"}
                permissionsOk={permsOk}
                pendingRequest={agentsState === "request"}
              >
                <SectionContent
                  section={section}
                  compact={compact}
                  scenarioState={scenarioState}
                  homeState={homeState}
                  permsOk={permsOk}
                  agentsState={agentsState}
                  onOpenRuns={() => setSection("traces")}
                />
              </ActionWindow>
            </div>
          </div>
        </div>

        <p
          style={{
            marginTop: 12,
            fontFamily: "var(--act-mono)",
            fontSize: 10,
            letterSpacing: "0.07em",
            textTransform: "uppercase",
            color: "var(--studio-ink-faint, #8a8f98)",
          }}
        >
          {size.w} × {size.h} · shown at {Math.round(scale * 100)}% · {size.note}
        </p>
      </div>

      <Note title="What the rail does and does not do">
        The collapse is a manual toggle stored in <code>@AppStorage</code>, not a
        breakpoint — at the 1100pt floor the window still opens with a 200pt
        rail, and nothing in the app narrows it for you. That is defensible:
        macOS windows are dragged, not queried, and a rail that collapsed itself
        while you were resizing would move the thing you were aiming at. It is
        worth knowing it is a choice, though, because at 1100 with the rail open
        the Runs search field is already at its 150pt minimum.
      </Note>

      <Note title="Where the width actually goes">
        Only one page genuinely reflows: Library, whose grid is{" "}
        <code>adaptive(minimum: 220, maximum: 300)</code> and so gains a column
        somewhere past 1400. Runs compresses one control — the search field
        between 150 and 240 — and everything else holds. Scenarios does not move
        at all: it is capped at a 760pt measure and left-aligned, so the extra
        500pt of a wide window is margin. That is deliberate for a reading
        surface, and it is the thing to look at hardest here, because it is also
        the emptiest the window ever looks.
      </Note>

      <Note title="What is drawn from fixtures">
        Nine runs across two days, three scenarios, four tool groups. Every
        field exists on <code>ActionSessionSummary</code> — kind, outcome,
        agent, destination. Nothing was invented to fill a column: where the
        runtime writes no value the cell holds a dash, which is why the
        unfinished inspection has no destination and no take.
      </Note>
    </StudyShell>
  );
}

/* -------------------------------------------------------------- sections -- */

function SectionContent({
  section,
  compact,
  scenarioState,
  homeState,
  permsOk,
  agentsState,
  onOpenRuns,
}: {
  section: Section;
  compact: boolean;
  scenarioState: ScenarioState;
  homeState: HomeState;
  permsOk: boolean;
  agentsState: AgentsState;
  onOpenRuns: () => void;
}) {
  const meta = SECTIONS.find((s) => s.key === section)!;

  // Runs owns its own scroll so the control strip stays pinned above a
  // 260-row ledger instead of scrolling away with it.
  // Traces draws its own header. It is the one page whose header carries a
  // control that must line up with the columns below it — the view toggle sits
  // on the same right edge as OPENS and the day rule — so the header is held to
  // the ledger measure rather than the pane width the shell would give it.
  if (section === "traces") {
    return <TracesSection compact={compact} />;
  }

  return (
    <>
      <Header section={section} eyebrow={meta.eyebrow} scenarioState={scenarioState} />
      <WindowPageBody>
        {section === "home" && <HomeSection state={homeState} onOpenRuns={onOpenRuns} />}
        {section === "scenarios" && <ScenariosSection state={scenarioState} />}
        {section === "agents" && <AgentsSection state={agentsState} />}
        {section === "settings" && (
          <SettingsSection
            permissions={
              permsOk ? PERMISSIONS.map((p) => ({ ...p, status: "Granted" as const })) : PERMISSIONS
            }
          />
        )}
      </WindowPageBody>
    </>
  );
}

function Header({
  section,
  eyebrow,
  scenarioState,
  right,
}: {
  section: Section;
  eyebrow: string;
  scenarioState?: ScenarioState;
  right?: ReactNode;
}) {
  const onField = section === "home";

  // On Scenarios the page name *is* the switcher, and the launcher header steps
  // aside for it: a second "New scenario" up here put two ways to make the same
  // thing four inches apart.
  const scenario = section === "scenarios";
  return (
    <div
      style={{ padding: "20px 28px 16px" }}
    >
      <WindowPageHeader
        onField={onField}
        // The eyebrow is already the state line, so the running target goes in
        // it rather than into a subtitle. A subtitle that appears in one state
        // only grows the header by 22pt and pushes the table down with it —
        // which broke the page's own claim that the table never moves.
        eyebrow={
          scenario && scenarioState === "running"
            ? "RUNNING · CALCULATOR"
            : scenario && scenarioState === "review"
              ? "TAKE · 2 MINS AGO"
              : eyebrow
        }
        // One coral dot, against the word RUNNING. It used to sit 480pt below
        // the eyebrow in the action row, so a supervision surface split its two
        // live facts across the height of the page.
        eyebrowMark={scenario && scenarioState === "running" ? <LiveDot /> : undefined}
        title={scenario ? SCENARIOS[0] : SECTIONS.find((s) => s.key === section)!.label}
        switcher={scenario}
        counter={scenario ? "1 of 3" : undefined}
        right={right}
      />

    </div>
  );
}

/* -------------------------------------------------------------- controls -- */

function Controls({
  sizeKey,
  onSize,
  section,
  scenarioState,
  onScenarioState,
  homeState,
  onHomeState,
  permsOk,
  onPermsOk,
  agentsState,
  onAgentsState,
}: {
  sizeKey: SizeKey;
  onSize: (k: SizeKey) => void;
  section: Section;
  scenarioState: ScenarioState;
  onScenarioState: (s: ScenarioState) => void;
  homeState: HomeState;
  onHomeState: (s: HomeState) => void;
  permsOk: boolean;
  onPermsOk: (v: boolean) => void;
  agentsState: AgentsState;
  onAgentsState: (s: AgentsState) => void;
}) {
  return (
    <div className="flex flex-wrap items-center gap-x-6 gap-y-3">
      <Segmented
        label="Window"
        options={SIZES.map((s) => ({ key: s.key, label: s.label }))}
        value={sizeKey}
        onChange={(k) => onSize(k as SizeKey)}
      />
      {section === "home" && (
        <Segmented
          label="Machine"
          options={[
            { key: "idle", label: "Idle" },
            { key: "driving", label: "Driving" },
          ]}
          value={homeState}
          onChange={(k) => onHomeState(k as HomeState)}
        />
      )}
      {section === "agents" && (
        <Segmented
          label="Registry"
          options={[
            { key: "registry", label: "Populated" },
            { key: "request", label: "Pending request" },
            { key: "empty", label: "First run" },
          ]}
          value={agentsState}
          onChange={(k) => onAgentsState(k as AgentsState)}
        />
      )}
      {section === "agents" && (
        <Segmented
          label="Registry"
          options={[
            { key: "registry", label: "Populated" },
            { key: "request", label: "Pending request" },
            { key: "empty", label: "First run" },
          ]}
          value={agentsState}
          onChange={(k) => onAgentsState(k as AgentsState)}
        />
      )}
      {section === "settings" && (
        <Segmented
          label="Permissions"
          options={[
            { key: "denied", label: "One denied" },
            { key: "ok", label: "All granted" },
          ]}
          value={permsOk ? "ok" : "denied"}
          onChange={(k) => onPermsOk(k === "ok")}
        />
      )}
      {section === "scenarios" && (
        <Segmented
          label="Scenario state"
          options={[
            { key: "plan", label: "Plan" },
            { key: "running", label: "Running" },
            { key: "review", label: "Review" },
          ]}
          value={scenarioState}
          onChange={(k) => onScenarioState(k as ScenarioState)}
        />
      )}
      <span className="font-mono text-[10px] uppercase tracking-eyebrow text-studio-ink-faint">
        Rail collapse lives in the window&apos;s own title bar
      </span>
    </div>
  );
}

function Segmented({
  label,
  options,
  value,
  onChange,
}: {
  label: string;
  options: { key: string; label: string }[];
  value: string;
  onChange: (key: string) => void;
}) {
  return (
    <div className="flex items-center gap-3">
      <span className="font-mono text-[10px] uppercase tracking-eyebrow text-studio-ink-faint">
        {label}
      </span>
      <div className="flex rounded-md border border-studio-rule p-0.5">
        {options.map((o) => (
          <button
            key={o.key}
            type="button"
            onClick={() => onChange(o.key)}
            className={
              "rounded px-3 py-1 text-[12.5px] transition-colors " +
              (value === o.key
                ? "bg-studio-chip-bg font-medium text-studio-ink-strong"
                : "text-studio-ink hover:text-studio-ink-strong")
            }
          >
            {o.label}
          </button>
        ))}
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ fit -- */

/**
 * Scale the window down to fit the page rather than resizing it. A scaled
 * screenshot is still honest about proportion and density; a re-laid-out one
 * is a different design.
 */
function useFitScale(width: number) {
  const ref = useRef<HTMLDivElement>(null);
  const [scale, setScale] = useState(1);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const measure = () => setScale(Math.min(1, el.clientWidth / width));
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(el);
    return () => ro.disconnect();
  }, [width]);

  return { ref, scale };
}
