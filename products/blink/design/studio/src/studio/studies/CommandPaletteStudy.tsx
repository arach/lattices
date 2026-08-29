"use client";

import { DesktopScene, glassHeavy } from "./DesktopScene";

/**
 * Study: the command palette — one input to reach any note or verb.
 *
 * The spatial twist: ⌘↵ opens the hit as a floating panel instead of just
 * selecting it. The palette can *place* notes, not only find them.
 */
export function CommandPaletteStudy() {
  return (
    <DesktopScene height={560}>
      <div className="pointer-events-none absolute inset-0 z-10 bg-black/35" />

      <div
        className={
          "absolute left-1/2 top-[16%] z-30 w-[560px] -translate-x-1/2 rounded-xl " +
          glassHeavy
        }
      >
        {/* Input */}
        <div className="flex items-center gap-3 border-b border-white/[0.1] px-4 py-3.5">
          <span className="rounded border border-white/[0.15] bg-white/[0.06] px-1.5 py-0.5 font-mono text-[10px] text-white/50">
            ⌘K
          </span>
          <span className="flex-1 text-[14px] text-white/50">
            type a note or a command…
            <span className="animate-pulse text-white/80">▏</span>
          </span>
        </div>

        {/* Notes group */}
        <div className="px-2 pt-2">
          <GroupLabel>Notes</GroupLabel>
          <Row selected icon="📄" label="Meeting notes" />
          <Row icon="📄" label="Roadmap Q3" />
        </div>

        {/* Actions group */}
        <div className="px-2 pb-2 pt-1">
          <GroupLabel>Actions</GroupLabel>
          <Row icon="✦" label="New note" kbd="⌘N" />
          <Row icon="⤢" label="Deploy note → grid slot…" />
          <Row icon="◧" label="Toggle preview" kbd="⌘⇧P" />
          <Row icon="🎙" label="Dictate into current note" />
        </div>

        {/* Key legend */}
        <div className="flex items-center gap-4 border-t border-white/[0.1] px-4 py-2.5 text-[11px] text-white/40">
          <span>↑↓ navigate</span>
          <span>↵ open</span>
          <span className="text-white/60">⌘↵ open as panel</span>
          <span className="ml-auto">esc dismiss</span>
        </div>
      </div>

      {/* Caption chip */}
      <div className="absolute bottom-4 left-4 z-30 rounded-md bg-black/40 px-3 py-1.5 font-mono text-[10px] uppercase tracking-[0.18em] text-white/60 backdrop-blur-sm">
        ⌘↵ spawns a spatial panel — the palette places notes, not just finds them
      </div>
    </DesktopScene>
  );
}

function GroupLabel({ children }: { children: string }) {
  return (
    <div className="px-2 pb-1 pt-1.5 font-mono text-[9px] uppercase tracking-[0.2em] text-white/35">
      {children}
    </div>
  );
}

function Row({
  icon,
  label,
  kbd,
  selected = false,
}: {
  icon: string;
  label: string;
  kbd?: string;
  selected?: boolean;
}) {
  return (
    <div
      className={
        "flex cursor-default items-center gap-3 rounded-md px-2.5 py-[7px] " +
        (selected ? "bg-white/[0.1]" : "hover:bg-white/[0.06]")
      }
    >
      <span className="w-5 text-center text-[13px]">{icon}</span>
      <span
        className={
          "flex-1 text-[13.5px] " + (selected ? "text-white" : "text-white/80")
        }
      >
        {label}
      </span>
      {kbd && (
        <span className="rounded border border-white/[0.12] bg-white/[0.05] px-1.5 py-0.5 font-mono text-[10px] text-white/45">
          {kbd}
        </span>
      )}
    </div>
  );
}
