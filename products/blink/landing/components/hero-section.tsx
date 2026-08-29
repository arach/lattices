import { Button } from "@/components/ui/button"
import { Download, Github } from "lucide-react"
import { Chord, Keycap } from "@/components/kit"

export default function HeroSection() {
  return (
    <section className="relative min-h-screen flex flex-col items-center justify-center px-4 pt-28 pb-16 overflow-hidden">
      {/* Spatial desk: dot-grid + a soft glow where the notes live */}
      <div className="absolute inset-0 dot-grid opacity-60" />
      <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_50%_-10%,rgba(80,140,235,0.16),transparent_55%)]" />
      <div className="absolute inset-x-0 bottom-0 h-64 bg-gradient-to-t from-[#08090b] to-transparent" />

      <div className="relative z-10 w-full max-w-5xl mx-auto text-center">
        <div className="inline-flex items-center gap-2 mb-8 rounded-full border border-white/10 bg-white/[0.04] px-3.5 py-1.5 text-[13px] text-white/60 backdrop-blur-sm">
          <span className="w-1.5 h-1.5 rounded-full bg-emerald-400" />
          Native macOS · lives in your menubar · no dock icon
        </div>

        <h1 className="font-display text-6xl md:text-8xl font-medium tracking-tight text-white leading-[0.95] mb-4">
          Blink
        </h1>
        <p className="font-display text-2xl md:text-4xl font-light tracking-tight mb-7">
          <span className="bg-gradient-to-r from-white to-white/55 bg-clip-text text-transparent">
            Spatial notes for your Mac.
          </span>
        </p>

        <p className="font-text text-lg text-white/55 max-w-2xl mx-auto leading-relaxed mb-9">
          A menubar app for macOS. Press <span className="text-white/80">⌃⌥⇧⌘N</span> anywhere and a
          borderless glass note lands on your screen — placed in space and remembered there. Plain markdown
          you own, keyboard-first, and open to your agents.
        </p>

        <div className="flex flex-col sm:flex-row gap-3 justify-center mb-14">
          <Button
            asChild
            size="lg"
            className="bg-white text-slate-900 hover:bg-white/90 px-7 py-4 text-base font-medium rounded-xl shadow-lg"
          >
            <a href="https://github.com/arach/blink/releases/latest" target="_blank" rel="noopener noreferrer">
              <Download className="mr-2 w-4 h-4" />
              Download for macOS
            </a>
          </Button>
          <Button
            asChild
            size="lg"
            variant="outline"
            className="border-white/15 text-white/80 hover:bg-white/[0.06] hover:text-white px-7 py-4 text-base bg-transparent rounded-xl"
          >
            <a href="https://github.com/arach/blink" target="_blank" rel="noopener noreferrer">
              <Github className="mr-2 w-4 h-4" />
              View on GitHub
            </a>
          </Button>
        </div>

        {/* The real thing: a borderless glass note on the desktop */}
        <div className="relative max-w-4xl mx-auto">
          <div className="absolute -inset-x-8 -top-8 bottom-0 bg-[radial-gradient(ellipse_at_center,rgba(90,150,240,0.14),transparent_70%)] blur-2xl" />
          <img
            src="/hero-desk.png"
            alt="A Blink note floating over the desktop — borderless dark glass, edge-to-edge markdown"
            className="relative w-full rounded-2xl border border-white/10 shadow-2xl shadow-black/60"
          />
        </div>

        {/* Honest, real specs */}
        <div className="mt-12 flex flex-wrap items-center justify-center gap-x-10 gap-y-4 text-sm text-white/45">
          <span className="inline-flex items-center gap-2">
            <Chord keys={["⌃⌥⇧⌘", "N"]} /> new note, anywhere
          </span>
          <span className="inline-flex items-center gap-2">
            <Keycap>&lt; 100ms</Keycap> from keystroke to note
          </span>
          <span className="inline-flex items-center gap-2">
            <Keycap>.md</Keycap> your files, plain markdown
          </span>
        </div>
      </div>
    </section>
  )
}
