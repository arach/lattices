"use client";

import type { ReactNode } from "react";
import { DesktopScene, TrafficLights, glassHeavy } from "./DesktopScene";

/**
 * Study: settings — deliberately tiny.
 *
 * One small native window, three grouped sections, one screen. No duplicated
 * controls: if it has a good default, it isn't a setting. The antidote to v1's
 * 1,600-line settings panel.
 */
export function SettingsStudy() {
  return (
    <DesktopScene height={520}>
      <div
        className={
          "absolute left-1/2 top-1/2 flex w-[420px] -translate-x-1/2 -translate-y-1/2 flex-col rounded-xl " +
          glassHeavy
        }
        style={{ height: 400 }}
      >
        {/* Title bar */}
        <div className="flex h-7 shrink-0 items-center justify-between border-b border-white/[0.08] px-3">
          <TrafficLights />
          <span className="pointer-events-none absolute left-1/2 -translate-x-1/2 text-[11px] font-medium text-white/40">
            Settings
          </span>
          <span className="w-[38px]" />
        </div>

        <div className="flex-1 overflow-hidden px-5 py-3">
          {/* General */}
          <SectionLabel>General</SectionLabel>
          <Row label="Notes folder">
            <span className="truncate font-mono text-[10.5px] text-white/40">
              ~/Library/Application Support/Blink/Notes
            </span>
            <Chip>Reveal</Chip>
          </Row>
          <Row label="Restore panels at launch">
            <Pill on />
          </Row>

          {/* Editor */}
          <div className="mt-3 border-t border-white/[0.08] pt-3">
            <SectionLabel>Editor</SectionLabel>
            <Row label="Open notes in">
              <Segmented options={["Read", "Edit"]} selected="Read" />
            </Row>
            <Row label="Typewriter mode" dim>
              <span className="rounded border border-white/[0.1] px-1.5 py-0.5 font-mono text-[9px] uppercase tracking-[0.15em] text-white/35">
                later
              </span>
              <Pill on={false} />
            </Row>
          </div>

          {/* Shortcuts */}
          <div className="mt-3 border-t border-white/[0.08] pt-3">
            <SectionLabel>Shortcuts</SectionLabel>
            <ShortcutRow label="New note" keys="Hyper+N" />
            <ShortcutRow label="Command palette" keys="⌘K (soon)" />
            <ShortcutRow label="Flip mode" keys="⌘⇧P" />
          </div>
        </div>
      </div>

      {/* Caption chip */}
      <div className="absolute bottom-4 left-4 rounded-md bg-black/40 px-3 py-1.5 font-mono text-[10px] uppercase tracking-[0.18em] text-white/60 backdrop-blur-sm">
        three sections, one screen — if it has a good default, it isn't a setting
      </div>
    </DesktopScene>
  );
}

function SectionLabel({ children }: { children: string }) {
  return (
    <div className="px-1 pb-1 font-mono text-[9px] uppercase tracking-[0.2em] text-white/35">
      {children}
    </div>
  );
}

function Row({
  label,
  children,
  dim = false,
}: {
  label: string;
  children: ReactNode;
  dim?: boolean;
}) {
  return (
    <div className="flex items-center gap-3 px-1 py-[7px]">
      <span
        className={
          "shrink-0 text-[12.5px] " + (dim ? "text-white/45" : "text-white/80")
        }
      >
        {label}
      </span>
      <span className="ml-auto flex items-center gap-2 overflow-hidden">
        {children}
      </span>
    </div>
  );
}

function ShortcutRow({ label, keys }: { label: string; keys: string }) {
  return (
    <div className="flex items-center gap-3 px-1 py-[7px]">
      <span className="text-[12.5px] text-white/80">{label}</span>
      <span className="ml-auto rounded border border-white/[0.12] bg-white/[0.05] px-1.5 py-0.5 font-mono text-[10px] text-white/45">
        {keys}
      </span>
    </div>
  );
}

function Chip({ children }: { children: string }) {
  return (
    <span className="shrink-0 cursor-default rounded border border-white/[0.15] bg-white/[0.06] px-2 py-0.5 text-[10.5px] text-white/60 hover:text-white/90">
      {children}
    </span>
  );
}

function Pill({ on }: { on: boolean }) {
  return (
    <span
      className={
        "flex h-[16px] w-[28px] items-center rounded-full px-[2px] " +
        (on ? "justify-end bg-emerald-400/80" : "justify-start bg-white/[0.12]")
      }
    >
      <span className="h-[12px] w-[12px] rounded-full bg-white shadow-sm" />
    </span>
  );
}

function Segmented({
  options,
  selected,
}: {
  options: string[];
  selected: string;
}) {
  return (
    <span className="flex items-center rounded-md border border-white/[0.12] bg-white/[0.04] p-[2px]">
      {options.map((opt) => (
        <span
          key={opt}
          className={
            "cursor-default rounded px-2.5 py-[3px] text-[11px] " +
            (opt === selected
              ? "bg-white/[0.14] text-white"
              : "text-white/45 hover:text-white/70")
          }
        >
          {opt}
        </span>
      ))}
    </span>
  );
}
