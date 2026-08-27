"use client";

import type { CSSProperties, ReactNode } from "react";
import { Clock8, House, LayoutList, Play, PanelLeft, Settings, Users } from "lucide-react";
import { PERMISSIONS, PERMISSIONS_OK } from "@/studio/action/fixtures";

/**
 * The launcher window, drawn at true pixel geometry.
 *
 * Every number in here is read from the Swift: 38pt title bar, 78pt traffic
 * light inset, 36pt footer, a 200pt sidebar that collapses to 56, and a 22pt
 * icon rail inside it so the labels start on one hard vertical and the glyph
 * does not move when the rail collapses. Drawing the window at anything other
 * than its real size would make every judgement about density a guess.
 *
 * The window is scaled to fit the page by `ScaledWindow`, not resized. A
 * scaled screenshot is still honest about proportion; a re-laid-out one is not.
 */

const mono = "var(--act-mono)";
const sans = "var(--act-sans)";

/**
 * Four sections, not five. Runs and Library were one object — Library was a
 * `filter()` over the same array with no facet the ledger lacked — so the
 * second nav slot was buying a layout, not a place. They are one Traces now,
 * with the layout as a toggle inside it.
 */
export type Section = "home" | "scenarios" | "traces" | "agents" | "settings";

export const SECTIONS: { key: Section; label: string; eyebrow: string }[] = [
  { key: "home", label: "Home", eyebrow: "COMPUTER USE" },
  { key: "scenarios", label: "Scenarios", eyebrow: "PLANS" },
  { key: "traces", label: "Traces", eyebrow: "HISTORY" },
  { key: "agents", label: "Agents", eyebrow: "REGISTRY" },
  { key: "settings", label: "Settings", eyebrow: "SETUP" },
];

const ICONS: Record<Section, typeof House> = {
  home: House,
  scenarios: LayoutList,
  traces: Clock8,
  agents: Users,
  settings: Settings,
};

/* ---------------------------------------------------------------- window -- */

export function ActionWindow({
  width,
  height,
  section,
  onSection,
  collapsed,
  onToggleCollapse,
  pendingRequest,
  /** Home is the one page painted on the field canvas rather than on chrome. */
  fieldCanvas,
  permissionsOk,
  children,
}: {
  width: number;
  height: number;
  section: Section;
  onSection: (s: Section) => void;
  collapsed: boolean;
  onToggleCollapse: () => void;
  /** An agent is waiting on the operator to decide. Chrome carries it because
   *  the request can arrive while you are on any other page. */
  pendingRequest?: boolean;
  fieldCanvas?: boolean;
  /** The frame reports the same permission state the Settings page reads. */
  permissionsOk?: boolean;
  children: ReactNode;
}) {
  return (
    <div
      style={{
        width,
        height,
        display: "flex",
        flexDirection: "column",
        borderRadius: 10,
        overflow: "hidden",
        border: "1px solid var(--act-rule)",
        boxShadow: "0 18px 50px rgba(0,0,0,0.28)",
        background: "var(--act-canvas)",
        color: "var(--act-ink)",
        fontFamily: sans,
      }}
    >
      <TitleBar collapsed={collapsed} onToggleCollapse={onToggleCollapse} />

      <div style={{ flex: 1, display: "flex", minHeight: 0 }}>
        <Sidebar
          section={section}
          onSection={onSection}
          collapsed={collapsed}
          pendingRequest={pendingRequest}
        />
        <div
          style={{
            flex: 1,
            minWidth: 0,
            display: "flex",
            flexDirection: "column",
            background: fieldCanvas ? "var(--act-field-canvas)" : "var(--act-canvas)",
          }}
        >
          {children}
        </div>
      </div>

      <FooterBar permissionsOk={permissionsOk ?? PERMISSIONS_OK} />
    </div>
  );
}

/* -------------------------------------------------------------- titlebar -- */

/**
 * One connected band across the very top. The wordmark and the collapse
 * control live here rather than in the rail, so collapsing moves only the nav
 * while the identity and the control that acts on it stay put.
 */
function TitleBar({
  collapsed,
  onToggleCollapse,
}: {
  collapsed: boolean;
  onToggleCollapse: () => void;
}) {
  return (
    <div
      style={{
        height: "var(--act-titlebar-h)",
        flex: "0 0 auto",
        display: "flex",
        alignItems: "center",
        gap: 10,
        paddingLeft: 14,
        paddingRight: 16,
        background: "var(--act-rail)",
        borderBottom: "1px solid var(--act-rule)",
      }}
    >
      <TrafficLights />
      <div style={{ display: "flex", alignItems: "center", gap: 9, marginLeft: 18 }}>
        <LogoMark />
        <span style={{ fontSize: "var(--act-subhead)", fontWeight: 600 }}>Action</span>
      </div>
      <button
        type="button"
        onClick={onToggleCollapse}
        title={collapsed ? "Expand sidebar" : "Collapse sidebar"}
        style={{
          width: 26,
          height: 26,
          display: "grid",
          placeItems: "center",
          border: 0,
          background: "transparent",
          color: "var(--act-ink-muted)",
          cursor: "pointer",
        }}
      >
        <PanelLeft size={15} />
      </button>
    </div>
  );
}

function TrafficLights() {
  const dot = (color: string): CSSProperties => ({
    width: 11,
    height: 11,
    borderRadius: "50%",
    background: color,
  });
  return (
    <div style={{ display: "flex", gap: 8 }}>
      <span style={dot("#FF5F57")} />
      <span style={dot("#FEBC2E")} />
      <span style={dot("#28C840")} />
    </div>
  );
}

function LogoMark() {
  return (
    <span
      style={{
        width: 26,
        height: 26,
        borderRadius: 6,
        display: "grid",
        placeItems: "center",
        background: "rgba(48,120,230,0.14)",
        border: "1px solid rgba(48,120,230,0.2)",
        color: "var(--act-review-accent)",
      }}
    >
      <Play size={10} fill="currentColor" />
    </span>
  );
}

/* --------------------------------------------------------------- sidebar -- */

/**
 * Selection is one ink ground with a single 2pt accent rail. It used to be a
 * tinted pill, which made the accent the loudest colour in the chrome on every
 * screen, permanently.
 */
function Sidebar({
  section,
  onSection,
  collapsed,
  pendingRequest,
}: {
  section: Section;
  onSection: (s: Section) => void;
  collapsed: boolean;
  pendingRequest?: boolean;
}) {
  const top = SECTIONS.filter((s) => s.key !== "settings");
  return (
    <div
      style={{
        width: collapsed ? "var(--act-sidebar-compact-w)" : "var(--act-sidebar-w)",
        flex: "0 0 auto",
        display: "flex",
        flexDirection: "column",
        background:
          "linear-gradient(rgba(32,40,43,0.035), rgba(32,40,43,0)) , var(--act-rail)",
        borderRight: "1px solid var(--act-rule)",
        transition: "width 160ms ease",
      }}
    >
      <div style={{ padding: "12px 8px 0", display: "grid", gap: 1 }}>
        <SidebarItem s={top[0]} active={section === top[0].key} onSection={onSection} collapsed={collapsed} />
        {/* Home is the overview; the three below are the surfaces you work in.
            One hairline says that much without spending a section header. */}
        <div
          style={{
            height: 1,
            background: "var(--act-rule)",
            opacity: 0.7,
            margin: `7px ${collapsed ? 6 : 10}px`,
          }}
        />
        {top.slice(1).map((s) => (
          <SidebarItem
            key={s.key}
            s={s}
            active={section === s.key}
            onSection={onSection}
            collapsed={collapsed}
            mark={s.key === "agents" && pendingRequest}
          />
        ))}
      </div>

      <div style={{ flex: 1 }} />

      {!collapsed && <CompanionBadge />}

      <div style={{ padding: "0 8px 12px" }}>
        <SidebarItem
          s={SECTIONS[4]}
          active={section === "settings"}
          onSection={onSection}
          collapsed={collapsed}
        />
      </div>
    </div>
  );
}

function SidebarItem({
  s,
  active,
  onSection,
  collapsed,
  mark,
}: {
  s: { key: Section; label: string };
  active: boolean;
  onSection: (s: Section) => void;
  collapsed: boolean;
  /** Amber: the last signal slot. Blue is selection, coral is a live drive. */
  mark?: boolean;
}) {
  const Icon = ICONS[s.key];
  return (
    <button
      type="button"
      onClick={() => onSection(s.key)}
      title={collapsed ? s.label : undefined}
      style={{
        position: "relative",
        display: "flex",
        alignItems: "center",
        justifyContent: collapsed ? "center" : "flex-start",
        minHeight: 32,
        width: "100%",
        padding: 0,
        border: 0,
        borderRadius: 6,
        cursor: "pointer",
        textAlign: "left",
        background: active ? "rgba(32,40,43,0.055)" : "transparent",
        color: active ? "var(--act-ink)" : "var(--act-ink-2)",
      }}
    >
      {active && (
        <span
          style={{
            position: "absolute",
            left: 0,
            top: 8,
            bottom: 8,
            width: 2,
            borderRadius: 1,
            background: "var(--act-review-accent)",
          }}
        />
      )}
      <span
        style={{
          width: "var(--act-sidebar-rail-w)",
          display: "grid",
          placeItems: "center",
          color: active ? "var(--act-ink)" : "var(--act-ink-muted)",
        }}
      >
        <Icon size={14} strokeWidth={active ? 2.4 : 1.8} />
      </span>
      {!collapsed && (
        <span
          style={{
            marginLeft: 8,
            fontSize: "var(--act-nav)",
            fontWeight: 500,
            whiteSpace: "nowrap",
          }}
        >
          {s.label}
        </span>
      )}
      {mark && (
        <>
          <span style={{ flex: 1 }} />
          <span
            style={{
              width: 6,
              height: 6,
              borderRadius: "50%",
              marginRight: collapsed ? 0 : 10,
              background: "var(--act-status-running)",
            }}
          />
        </>
      )}
    </button>
  );
}

function CompanionBadge() {
  return (
    <div
      style={{
        margin: "0 12px 14px",
        padding: "8px 10px",
        borderRadius: 8,
        border: "1px solid var(--act-rule)",
        background: "var(--act-panel)",
        display: "flex",
        alignItems: "center",
        gap: 8,
      }}
    >
      <span
        style={{
          width: 18,
          height: 18,
          borderRadius: 5,
          background: "var(--act-field-console)",
          border: "1px solid var(--act-rule)",
        }}
      />
      <span style={{ fontSize: "var(--act-caption)", color: "var(--act-ink-2)" }}>Mira</span>
      <span style={{ flex: 1 }} />
      <span style={{ fontFamily: mono, fontSize: 9, color: "var(--act-ink-muted)" }}>IDLE</span>
    </div>
  );
}

/* ---------------------------------------------------------------- footer -- */

function FooterBar({ permissionsOk }: { permissionsOk: boolean }) {
  return (
    <div
      style={{
        height: "var(--act-footer-h)",
        flex: "0 0 auto",
        display: "flex",
        alignItems: "center",
        gap: 16,
        padding: "0 20px",
        background: "var(--act-footer)",
        borderTop: "1px solid var(--act-rule)",
      }}
    >
      <FooterChip label="Agent" value="Connected" ok />
      {/* Derived, not hardcoded. A footer that says "All granted" above a pane
          showing a denied permission is the chrome contradicting the page. */}
      <FooterChip
        label="Permissions"
        value={
          permissionsOk
            ? "All granted"
            : `${PERMISSIONS.filter((p) => p.status !== "Granted").length} needs attention`
        }
        ok={permissionsOk}
      />
      <span style={{ flex: 1 }} />
      <span style={{ fontSize: "var(--act-caption)", fontWeight: 600, color: "var(--act-ink-2)" }}>
        Keyboard
      </span>
      <span style={{ fontSize: "var(--act-caption)", fontWeight: 600, color: "var(--act-ink-2)" }}>
        Docs
      </span>
    </div>
  );
}

/**
 * A healthy chip carries no dot. Status is spent when the status is news —
 * the same rule the Permissions pane and the Runs ledger follow, so a green
 * pip beside the word "Connected" would be the one place in the window that
 * still paints the unexceptional. The slot stays reserved so the labels hold
 * one edge whichever state they are in.
 */
function FooterChip({ label, value, ok }: { label: string; value: string; ok: boolean }) {
  return (
    <span style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
      <span
        style={{
          width: 6,
          height: 6,
          flex: "0 0 auto",
          borderRadius: "50%",
          background: ok ? "transparent" : "var(--act-status-failed)",
        }}
      />
      <span style={{ fontSize: "var(--act-caption)", color: "var(--act-ink-muted)" }}>{label}</span>
      <span style={{ fontSize: "var(--act-caption)", fontWeight: 600 }}>{value}</span>
    </span>
  );
}

/* ------------------------------------------------------------ page frame -- */

/**
 * The shape every page opens with: eyebrow, title, optional subtitle, and
 * whatever the page puts on the right. Fixed everywhere so moving between
 * pages does not re-flow the top of the window.
 */
export function WindowPageHeader({
  eyebrow,
  eyebrowMark,
  title,
  subtitle,
  switcher,
  counter,
  right,
  onField,
}: {
  eyebrow: string;
  /** A live mark that belongs to the state the eyebrow names, e.g. the coral drive dot. */
  eyebrowMark?: ReactNode;
  title: string;
  subtitle?: string;
  switcher?: boolean;
  counter?: string;
  right?: ReactNode;
  onField?: boolean;
}) {
  const ink = onField ? "var(--act-field-ink)" : "var(--act-ink)";
  const muted = onField ? "var(--act-field-ink-meta)" : "var(--act-ink-muted)";
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
      <div style={{ minWidth: 0 }}>
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: 7,
            fontFamily: mono,
            fontSize: "var(--act-label)",
            fontWeight: 600,
            letterSpacing: "var(--act-track-eyebrow)",
            color: muted,
          }}
        >
          {eyebrowMark}
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
            color: ink,
          }}
        >
          <span style={{ whiteSpace: "nowrap" }}>{title}</span>
          {switcher && <span style={{ fontSize: 14, color: muted }}>▾</span>}
          {counter && (
            <span style={{ fontFamily: mono, fontSize: 11, color: muted }}>{counter}</span>
          )}
        </div>
        {subtitle && (
          <div style={{ marginTop: 4, fontSize: "var(--act-body)", color: muted }}>{subtitle}</div>
        )}
      </div>
      <span style={{ flex: 1 }} />
      {right}
    </div>
  );
}

/** The page body: the app's own 28pt gutter, its own scroll. */
export function WindowPageBody({ children }: { children: ReactNode }) {
  return (
    <div style={{ flex: 1, minHeight: 0, overflow: "auto", padding: "0 28px 28px" }}>{children}</div>
  );
}
