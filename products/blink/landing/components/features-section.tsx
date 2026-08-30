import { Layers, Command, FileText } from "lucide-react"
import { Glass, SectionHeading, Keycap } from "@/components/kit"

const pillars = [
  {
    icon: Layers,
    title: "Spatial by default",
    body: "Place a note and it stays — every panel remembers its size and spot on screen, so your desk becomes muscle memory. Blink them all in and out at once, or lay them on a grid to see the whole board.",
    detail: (
      <>
        <Keycap>⌃⌥⇧⌘B</Keycap>
        <span className="text-white/40">blink all / none</span>
        <Keycap>⌃⌥⇧⌘C</Keycap>
        <span className="text-white/40">grid</span>
      </>
    ),
  },
  {
    icon: Command,
    title: "Native, not Electron",
    body: "A real AppKit app that lives in your menubar — no dock icon, no main window, around 50MB. Borderless panels with genuine macOS glass, summoned from anywhere in under 100 milliseconds.",
    detail: (
      <>
        <Keycap>Swift</Keycap>
        <span className="text-white/40">AppKit + WKWebView</span>
      </>
    ),
  },
  {
    icon: FileText,
    title: "Yours in plain markdown",
    body: "Notes are frontmatter markdown files in a folder you own. Nothing you can't open in any editor, no lock-in — and Blink reconciles changes made from outside the app, live.",
    detail: (
      <>
        <Keycap>~/…/Blink/Notes</Keycap>
        <span className="text-white/40">.md files</span>
      </>
    ),
  },
]

export default function FeaturesSection() {
  return (
    <section id="features" className="relative py-28 px-4">
      <div className="max-w-6xl mx-auto">
        <SectionHeading
          eyebrow="The idea"
          title="Notes that live where you put them."
          lede="Blink borrows the good parts of a whiteboard and a text editor — space you can arrange, files you can own — and makes them instant."
        />

        <div className="grid grid-cols-1 md:grid-cols-3 gap-5">
          {pillars.map((p) => (
            <Glass key={p.title} className="p-7">
              <p.icon className="w-6 h-6 text-sky-300/80 mb-5" strokeWidth={1.5} />
              <h3 className="font-display text-xl font-medium text-white mb-3">{p.title}</h3>
              <p className="font-text text-[15px] text-white/55 leading-relaxed mb-6">{p.body}</p>
              <div className="flex flex-wrap items-center gap-2 text-xs">{p.detail}</div>
            </Glass>
          ))}
        </div>
      </div>
    </section>
  )
}
