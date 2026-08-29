import type React from "react"
import { SectionHeading, Glass } from "@/components/kit"

/** One line of the faux terminal. */
function Line({
  prompt,
  cmd,
  out,
}: {
  prompt?: boolean
  cmd?: React.ReactNode
  out?: React.ReactNode
}) {
  if (prompt) {
    return (
      <div className="flex gap-2">
        <span className="text-emerald-400/80 select-none">❯</span>
        <span className="text-white/90">{cmd}</span>
      </div>
    )
  }
  return <div className="text-white/45 pl-4">{out}</div>
}

export default function AgentSection() {
  return (
    <section id="agents" className="relative py-28 px-4">
      <div className="max-w-6xl mx-auto">
        <SectionHeading
          eyebrow="Agent-first"
          title="The filesystem is the API."
          lede="Blink was built to be driven by more than a keyboard. A CLI, a hot-reloading config file, and live reconciliation mean your agents read and write the same notes you do — no plugins, no integrations."
        />

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-5 items-stretch">
          {/* The CLI */}
          <Glass className="overflow-hidden flex flex-col">
            <div className="flex items-center gap-2 px-4 py-3 border-b border-white/8">
              <span className="w-3 h-3 rounded-full bg-red-400/70" />
              <span className="w-3 h-3 rounded-full bg-yellow-400/70" />
              <span className="w-3 h-3 rounded-full bg-green-400/70" />
              <span className="ml-2 font-mono text-[12px] text-white/40">blink — the notes CLI</span>
            </div>
            <div className="p-5 font-mono text-[12.5px] leading-[1.9] flex-1">
              <Line prompt cmd={<>blink new &quot;Standup&quot; --content &quot;## Fri&quot;</>} />
              <Line out={<>created <span className="text-sky-300/80">standup</span> · ~/…/Notes/standup.md</>} />
              <Line prompt cmd={<>blink append standup &quot;shipped the landing ✓&quot;</>} />
              <Line out={<>appended 18 chars → <span className="text-sky-300/80">standup</span></>} />
              <Line prompt cmd={<>blink search &quot;roadmap&quot; --json</>} />
              <Line out={<>[&#123; &quot;title&quot;: &quot;Roadmap&quot;, &quot;matches&quot;: 3 &#125;]</>} />
              <div className="flex gap-2 pt-1">
                <span className="text-emerald-400/80 select-none">❯</span>
                <span className="caret" />
              </div>
            </div>
          </Glass>

          {/* Visible Hand: an agent typing into an open note */}
          <Glass className="overflow-hidden flex flex-col bg-white/[0.05]">
            <div className="flex items-center justify-between px-4 py-3 border-b border-white/8">
              <span className="font-text text-[13px] text-white/70">standup.md</span>
              <span className="inline-flex items-center gap-1.5 rounded-full bg-sky-400/10 border border-sky-300/20 px-2 py-0.5 text-[11px] text-sky-200/80">
                <span className="w-1.5 h-1.5 rounded-full bg-sky-300 animate-pulse" />
                typed by claude
              </span>
            </div>
            <div className="p-5 font-text text-[14px] leading-relaxed flex-1">
              <div className="text-white/90 text-[16px] font-medium mb-2">Standup</div>
              <div className="text-white/60">## Fri</div>
              <div className="text-white/60">- ship the landing page</div>
              <div className="text-white/60">
                - shipped the landing ✓<span className="caret ml-0.5" />
              </div>
              <div className="mt-6 text-[12px] text-white/30">
                External edits don&apos;t just appear — they type themselves in, with a caret and a soft
                tick, so you notice without a notification stealing focus.
              </div>
            </div>
          </Glass>
        </div>

        {/* config.json */}
        <Glass className="mt-5 p-6 md:p-7">
          <div className="grid grid-cols-1 md:grid-cols-[1fr_1.1fr] gap-6 items-center">
            <div>
              <h3 className="font-display text-lg font-medium text-white mb-2">
                Configured by a file, not a settings pane
              </h3>
              <p className="font-text text-[15px] text-white/55 leading-relaxed">
                Theme, hotkeys, motion, sheets — all live in one JSON file. Any process can edit it; Blink
                watches the directory and hot-applies changes to every panel. The settings window is just a
                view over it.
              </p>
            </div>
            <div className="rounded-xl bg-black/40 border border-white/8 p-4 font-mono text-[12.5px] leading-[1.8] overflow-x-auto">
              <div className="text-white/40">~/Library/Application Support/Blink/config.json</div>
              <div className="mt-2">
                <span className="text-white/50">&#123;</span>
              </div>
              <div className="pl-4">
                <span className="text-sky-300/80">&quot;hotkeys&quot;</span>: &#123;{" "}
                <span className="text-sky-300/80">&quot;newNote&quot;</span>:{" "}
                <span className="text-emerald-300/70">&quot;hyper+n&quot;</span> &#125;,
              </div>
              <div className="pl-4">
                <span className="text-sky-300/80">&quot;panel&quot;</span>: &#123;{" "}
                <span className="text-sky-300/80">&quot;sheet&quot;</span>:{" "}
                <span className="text-emerald-300/70">&quot;dotted&quot;</span> &#125;,
              </div>
              <div className="pl-4">
                <span className="text-sky-300/80">&quot;motion&quot;</span>: &#123;{" "}
                <span className="text-sky-300/80">&quot;entrance&quot;</span>:{" "}
                <span className="text-emerald-300/70">&quot;shimmer&quot;</span> &#125;
              </div>
              <div>
                <span className="text-white/50">&#125;</span>
              </div>
            </div>
          </div>
        </Glass>
      </div>
    </section>
  )
}
