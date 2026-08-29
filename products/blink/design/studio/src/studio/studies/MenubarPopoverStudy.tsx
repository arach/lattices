"use client";

import { DesktopScene, glassHeavy } from "./DesktopScene";

/**
 * Study: the menubar popover — home base for the triad.
 *
 * One field does everything: type = search, ⌘↵ = create, mic = dictate into a
 * new note. Recents can be flung onto the desktop as panels (⤢ on hover).
 * Footer is palette + settings only — triad-only means no Library entry.
 */
export function MenubarPopoverStudy() {
  return (
    <DesktopScene menubar height={560}>
      {/* Anchor caret under the status item */}
      <div className="absolute right-[104px] top-[26px] z-30 h-3 w-3 rotate-45 border-l border-t border-white/[0.12] bg-[#1a1d2e]/80" />

      <div
        className={
          "absolute right-[16px] top-[32px] z-30 w-[312px] rounded-xl " + glassHeavy
        }
      >
        {/* Capture / search field */}
        <div className="flex items-center gap-2 border-b border-white/[0.08] px-3.5 py-3">
          <span className="text-[13px] text-white/40">⌕</span>
          <span className="flex-1 text-[13px] text-white/45">
            Search or capture…
            <span className="animate-pulse text-white/80">▏</span>
          </span>
          <span className="cursor-default rounded p-1 text-[13px] text-white/60 hover:bg-white/10 hover:text-white/90">
            🎙
          </span>
        </div>

        {/* Recents */}
        <div className="px-2 py-2">
          <div className="px-2 pb-1.5 pt-1 font-mono text-[9px] uppercase tracking-[0.2em] text-white/35">
            Recent
          </div>
          {[
            { title: "Meeting notes", when: "2m" },
            { title: "Roadmap Q3", when: "1h" },
            { title: "Grocery", when: "3h" },
            { title: "Ideas parking lot", when: "1d" },
          ].map((note) => (
            <div
              key={note.title}
              className="group flex cursor-default items-center gap-2 rounded-md px-2 py-[7px] hover:bg-white/[0.07]"
            >
              <span className="text-[11px] text-white/35">▸</span>
              <span className="flex-1 truncate text-[13px] text-white/85">
                {note.title}
              </span>
              <span className="text-[11px] tabular-nums text-white/35">
                {note.when}
              </span>
              <span
                className="text-[12px] text-white/0 transition-colors group-hover:text-white/60 hover:!text-white/95"
                title="Open as floating panel"
              >
                ⤢
              </span>
            </div>
          ))}
        </div>

        {/* Footer — palette + settings only (triad-only: no Library) */}
        <div className="flex items-center justify-between border-t border-white/[0.08] px-3.5 py-2.5 text-[11px] text-white/45">
          <span className="cursor-default hover:text-white/80">⌘K palette</span>
          <span className="cursor-default text-[12px] hover:text-white/80">⚙</span>
        </div>
      </div>

      {/* Caption chip */}
      <div className="absolute bottom-4 left-4 rounded-md bg-black/40 px-3 py-1.5 font-mono text-[10px] uppercase tracking-[0.18em] text-white/60 backdrop-blur-sm">
        one field: type = search · ⌘↵ = new note · mic = dictate
      </div>
    </DesktopScene>
  );
}
