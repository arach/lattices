import { SectionHeading } from "@/components/kit"

/** Sample note body, styled per sheet template. */
function NoteBody() {
  return (
    <div className="font-text text-[11px] leading-relaxed">
      <div className="text-white/90 font-medium text-[12.5px] mb-1.5">Weekly review</div>
      <div className="text-white/55">Ship v2 · port the palette</div>
      <div className="text-white/55">
        Notes land where you <span className="text-sky-300/80">leave them</span>.
      </div>
      <div className="text-white/35 mt-1.5">see [[roadmap]]</div>
    </div>
  )
}

const sheets = [
  {
    name: "glass",
    note: "The default — a HUD panel of real macOS blur.",
    wrap: "bg-white/[0.06] border border-white/12 backdrop-blur-xl",
    inner: null,
  },
  {
    name: "card",
    note: "Opaque paper. No blur — a solid surface that reads anywhere.",
    wrap: "bg-[#15171c] border border-white/10",
    inner: null,
  },
  {
    name: "dotted",
    note: "A flat sheet with a dotted margin, like a notebook.",
    wrap: "bg-white/[0.02] border border-white/10",
    inner: <div className="absolute left-0 top-0 bottom-0 w-6 border-r border-dashed border-white/15" />,
  },
  {
    name: "bracket",
    note: "Corner brackets frame the text and nothing else.",
    wrap: "bg-white/[0.015] border border-transparent",
    inner: (
      <>
        <span className="absolute left-1.5 top-1.5 w-3 h-3 border-l border-t border-white/30" />
        <span className="absolute right-1.5 top-1.5 w-3 h-3 border-r border-t border-white/30" />
        <span className="absolute left-1.5 bottom-1.5 w-3 h-3 border-l border-b border-white/30" />
        <span className="absolute right-1.5 bottom-1.5 w-3 h-3 border-r border-b border-white/30" />
      </>
    ),
  },
  {
    name: "marginalia",
    note: "A ruled left margin for annotations in the wild.",
    wrap: "bg-white/[0.025] border border-white/10",
    inner: <div className="absolute left-7 top-0 bottom-0 w-px bg-rose-300/25" />,
  },
]

export default function SheetsSection() {
  return (
    <section className="relative py-28 px-4">
      <div className="max-w-6xl mx-auto">
        <SectionHeading
          eyebrow="Sheets"
          title="Every note is its own surface."
          lede="Pick how a note looks — per note, or as your default. Set one key in a config file and Blink hot-applies it to every open panel in under a second."
        />

        <div className="grid grid-cols-2 md:grid-cols-5 gap-4">
          {sheets.map((s) => (
            <div key={s.name} className="flex flex-col">
              <div
                className={`relative h-36 rounded-xl p-3.5 overflow-hidden ${s.wrap}`}
              >
                {s.inner}
                <div className={s.name === "dotted" || s.name === "marginalia" ? "pl-6" : ""}>
                  <NoteBody />
                </div>
              </div>
              <div className="mt-3 px-0.5">
                <div className="font-mono text-[12px] text-white/80">{s.name}</div>
                <div className="font-text text-[12px] text-white/40 leading-snug mt-0.5">{s.note}</div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
