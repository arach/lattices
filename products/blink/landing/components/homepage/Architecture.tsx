/* Spec strip only — architecture deep-dive removed from the landing distill. */

const SPECS = [
  { k: 'hotkeys', v: 'carbon', d: 'global chords, no accessibility grant' },
  { k: 'runtime', v: 'native', d: 'Swift + AppKit, zero Electron' },
  { k: 'format', v: '.md', d: 'yaml frontmatter, files you own' },
  { k: 'cloud', v: 'none', d: 'no account — notes stay local' },
]

export function SpecStrip() {
  return (
    <section className="border-y border-linex bg-[rgba(var(--bg-rgb),0.6)]" aria-label="Technical highlights">
      <div className="mx-auto max-w-5xl px-4 md:px-6">
        <div className="grid grid-cols-2 lg:grid-cols-4">
          {SPECS.map((s, i) => (
            <div
              key={s.k}
              className={[
                'px-4 py-6 first:pl-0 lg:last:pr-0',
                i % 2 === 1 ? 'border-l border-[rgba(var(--line-rgb),0.7)]' : '',
                i >= 2 ? 'border-t border-[rgba(var(--line-rgb),0.7)] lg:border-t-0' : '',
                i >= 1 ? 'lg:border-l lg:border-[rgba(var(--line-rgb),0.7)]' : '',
              ]
                .filter(Boolean)
                .join(' ')}
            >
              <div className="text-[9px] tracking-[0.18em] text-faintx uppercase">{s.k}</div>
              <div className="mt-2 text-[19px] font-bold tracking-[-0.01em] text-acc">{s.v}</div>
              <div className="mt-1 text-[10.5px] leading-[1.55] text-dimx">{s.d}</div>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
