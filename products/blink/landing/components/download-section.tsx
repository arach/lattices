import { Button } from "@/components/ui/button"
import { Download, Github } from "lucide-react"
import { Glass, Eyebrow } from "@/components/kit"

const facts = [
  { value: "Free & open source", label: "MIT-spirited, on GitHub" },
  { value: "≈ 50 MB native", label: "Swift + AppKit, no Electron" },
  { value: "No account, no cloud", label: "Your notes never leave your Mac" },
]

export default function DownloadSection() {
  return (
    <section id="download" className="relative py-28 px-4">
      <div className="max-w-4xl mx-auto text-center">
        <div className="flex justify-center mb-5">
          <Eyebrow>Get Blink</Eyebrow>
        </div>
        <h2 className="font-display text-4xl md:text-5xl font-light tracking-tight text-white mb-5 leading-[1.05]">
          Free, open source, and yours.
        </h2>
        <p className="font-text text-lg text-white/55 max-w-xl mx-auto leading-relaxed mb-10">
          A single native app for macOS. No account, no sign-in — download it, press{" "}
          <span className="text-white/80">⌃⌥⇧⌘N</span>, and start.
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

        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-16">
          {facts.map((f) => (
            <Glass key={f.value} className="p-6">
              <div className="font-display text-lg font-medium text-white mb-1">{f.value}</div>
              <div className="font-text text-[13px] text-white/45">{f.label}</div>
            </Glass>
          ))}
        </div>

        <Glass className="p-7 text-left">
          <h3 className="font-text font-medium text-white/70 mb-5 text-center text-xs uppercase tracking-[0.16em]">
            Requirements
          </h3>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-12 gap-y-2.5 max-w-xl mx-auto font-text text-sm text-white/50">
            {[
              ["macOS 13 (Ventura) or later", "Apple Silicon or Intel", "~50 MB free disk space"],
              [
                "Lives in the menubar — no dock icon",
                "Global hotkeys, no extra permissions",
                "Notes are plain markdown you own",
              ],
            ].map((col, i) => (
              <ul key={i} className="space-y-2.5">
                {col.map((item) => (
                  <li key={item} className="flex gap-2.5 leading-5">
                    <span className="text-sky-300/40 select-none">•</span>
                    <span>{item}</span>
                  </li>
                ))}
              </ul>
            ))}
          </div>
        </Glass>
      </div>

      <footer className="max-w-6xl mx-auto mt-24 pt-8 border-t border-white/[0.06] flex flex-col sm:flex-row items-center justify-between gap-4">
        <div className="font-display text-white/70">
          Blink<span className="text-white/30"> — spatial notes for your Mac</span>
        </div>
        <div className="flex items-center gap-6 font-text text-[13px] text-white/40">
          <a href="https://github.com/arach/blink" className="hover:text-white/70 transition-colors">
            GitHub
          </a>
          <a
            href="https://github.com/arach/blink/releases/latest"
            className="hover:text-white/70 transition-colors"
          >
            Releases
          </a>
          <span>Native · open source</span>
        </div>
      </footer>
    </section>
  )
}
