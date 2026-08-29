import type React from "react"

/** A single monospace keycap chip, dark-glass styled to match the app. */
export function Keycap({ children }: { children: React.ReactNode }) {
  return (
    <span className="inline-flex items-center justify-center min-w-[1.9rem] h-7 px-2 rounded-lg bg-white/[0.06] border border-white/15 shadow-[0_1px_0_rgba(255,255,255,0.06)_inset,0_1px_2px_rgba(0,0,0,0.4)] font-mono text-[13px] font-medium text-white/80">
      {children}
    </span>
  )
}

/** The Hyper chord, rendered as the four-glyph modifier cap + a key. */
export function Chord({ keys }: { keys: string[] }) {
  return (
    <span className="inline-flex items-center gap-1">
      {keys.map((k, i) => (
        <Keycap key={i}>{k}</Keycap>
      ))}
    </span>
  )
}

/** Small uppercase eyebrow label used above section titles. */
export function Eyebrow({ children }: { children: React.ReactNode }) {
  return (
    <div className="inline-flex items-center gap-2 text-[11px] font-medium uppercase tracking-[0.18em] text-sky-300/70">
      <span className="w-4 h-px bg-sky-300/40" />
      {children}
    </div>
  )
}

/** A glass surface — the app's signature: faint fill, hairline border, blur. */
export function Glass({
  children,
  className = "",
}: {
  children: React.ReactNode
  className?: string
}) {
  return (
    <div
      className={`rounded-2xl bg-white/[0.035] border border-white/10 backdrop-blur-xl shadow-[0_1px_0_rgba(255,255,255,0.05)_inset] ${className}`}
    >
      {children}
    </div>
  )
}

/** Centered section heading with eyebrow, title, and lede. */
export function SectionHeading({
  eyebrow,
  title,
  lede,
}: {
  eyebrow: string
  title: React.ReactNode
  lede?: React.ReactNode
}) {
  return (
    <div className="max-w-2xl mx-auto text-center mb-14">
      <div className="flex justify-center mb-5">
        <Eyebrow>{eyebrow}</Eyebrow>
      </div>
      <h2 className="font-display text-4xl md:text-5xl font-light tracking-tight text-white mb-5 leading-[1.05]">
        {title}
      </h2>
      {lede && <p className="font-text text-lg text-white/55 leading-relaxed">{lede}</p>}
    </div>
  )
}
