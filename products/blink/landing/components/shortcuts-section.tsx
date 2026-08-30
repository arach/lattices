import { Glass, SectionHeading, Keycap } from "@/components/kit"

function Row({ keys, label }: { keys: string[]; label: string }) {
  return (
    <div className="flex items-center justify-between py-3 border-b border-white/[0.06] last:border-0">
      <span className="font-text text-[15px] text-white/70">{label}</span>
      <span className="flex items-center gap-1">
        {keys.map((k) => (
          <Keycap key={k}>{k}</Keycap>
        ))}
      </span>
    </div>
  )
}

export default function ShortcutsSection() {
  return (
    <section id="shortcuts" className="relative py-28 px-4">
      <div className="max-w-4xl mx-auto">
        <SectionHeading
          eyebrow="Keyboard-first"
          title="Everything is a keystroke away."
          lede="Three global chords reach Blink from any app; the rest act on the note you're in. All of them rebindable in the config file."
        />

        <div className="grid grid-cols-1 md:grid-cols-2 gap-5">
          <Glass className="p-6">
            <div className="font-mono text-[12px] uppercase tracking-[0.16em] text-sky-300/60 mb-3">
              Global
            </div>
            <Row keys={["⌃⌥⇧⌘", "N"]} label="New note, anywhere" />
            <Row keys={["⌃⌥⇧⌘", "B"]} label="Blink — all notes / none" />
            <Row keys={["⌃⌥⇧⌘", "C"]} label="Grid overlay" />
          </Glass>

          <Glass className="p-6">
            <div className="font-mono text-[12px] uppercase tracking-[0.16em] text-sky-300/60 mb-3">
              In a panel
            </div>
            <Row keys={["⌘", "⇧", "P"]} label="Flip read / edit" />
            <Row keys={["⌘", "."]} label="Focus — quiet everything else" />
            <Row keys={["⎋"]} label="Step down — leave edit, drop focus" />
            <Row keys={["⌘", "W"]} label="Close panel" />
          </Glass>
        </div>

        <p className="text-center font-text text-[13px] text-white/35 mt-6">
          Hyper is <span className="text-white/55">⌃⌥⇧⌘</span> — set every chord in{" "}
          <span className="font-mono text-white/55">config.json</span>.
        </p>
      </div>
    </section>
  )
}
