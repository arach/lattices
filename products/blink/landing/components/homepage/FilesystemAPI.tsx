import { useEffect, useRef, useState } from 'react'
import { SectionHeader, Reveal, MockTitleBar } from './shared'

interface TermLine {
  kind: 'cmd' | 'out' | 'json'
  text: string
}

export default function FilesystemAPI() {
  const [term, setTerm] = useState<TermLine[]>([])
  const [cmd, setCmd] = useState('')
  const [note, setNote] = useState<string[]>([])
  const [noteTyping, setNoteTyping] = useState('')
  const [badge, setBadge] = useState(false)
  const [noteCaret, setNoteCaret] = useState(false)
  const cancelledRef = useRef(false)

  useEffect(() => {
    cancelledRef.current = false
    const timeouts: number[] = []
    const reduced =
      typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches
    const wait = (ms: number) =>
      new Promise<void>((res) => {
        const id = window.setTimeout(res, reduced ? Math.min(ms, 80) : ms)
        timeouts.push(id)
      })
    const typeInto = async (text: string, set: (s: string) => void, cps = 34) => {
      if (reduced) {
        set(text)
        return
      }
      for (let i = 1; i <= text.length; i++) {
        if (cancelledRef.current) return
        set(text.slice(0, i))
        await wait(cps + Math.random() * 22)
      }
    }
    const push = (l: TermLine) => setTerm((t) => [...t, l])

    const run = async () => {
      while (!cancelledRef.current) {
        setTerm([])
        setCmd('')
        setNote([])
        setNoteTyping('')
        setBadge(false)
        setNoteCaret(false)
        await wait(900)

        await typeInto('blink new "# Standup"', setCmd)
        if (cancelledRef.current) return
        await wait(240)
        push({ kind: 'cmd', text: 'blink new "# Standup"' })
        setCmd('')
        await wait(120)
        push({ kind: 'out', text: '→ created standup · ~/Notes/standup.md' })
        setNote(['# Standup'])
        await wait(900)

        await typeInto('blink append standup "shipped the landing ✓"', setCmd)
        if (cancelledRef.current) return
        await wait(240)
        push({ kind: 'cmd', text: 'blink append standup "shipped the landing ✓"' })
        setCmd('')
        await wait(120)
        push({ kind: 'out', text: '→ standup · reconciled live' })
        setBadge(true)
        setNoteCaret(true)
        await typeInto('- shipped the landing ✓', setNoteTyping, 46)
        if (cancelledRef.current) return
        setNote((n) => [...n, '- shipped the landing ✓'])
        setNoteTyping('')
        setNoteCaret(false)
        await wait(1000)

        await typeInto('blink search "roadmap" --json', setCmd)
        if (cancelledRef.current) return
        await wait(240)
        push({ kind: 'cmd', text: 'blink search "roadmap" --json' })
        setCmd('')
        await wait(150)
        push({ kind: 'json', text: '[{ "id": "roadmap", "title": "Roadmap" }]' })
        await wait(reduced ? 2400 : 4200)
      }
    }
    run()
    return () => {
      cancelledRef.current = true
      timeouts.forEach((t) => clearTimeout(t))
    }
  }, [])

  return (
    <section id="how" className="scroll-mt-16 py-20 md:py-28 border-t border-linex">
      <div className="mx-auto max-w-5xl px-4 md:px-6">
        <SectionHeader
          tag="AGENT-FIRST"
          title={
            <>
              The filesystem <span className="text-acc">is the API</span>.
            </>
          }
          sub="Notes are markdown files in a folder you own. Agents and the CLI write the same files the panels render — live, no plugins."
        />

        <Reveal className="grid items-stretch gap-5 lg:grid-cols-2">
          <div className="flex flex-col overflow-hidden rounded-[8px] border border-linex bg-panelx">
            <MockTitleBar dots title="blink CLI" />
            <div
              className="min-h-[200px] flex-1 p-4 text-[12px] leading-[1.9] md:p-5 md:text-[12.5px]"
              aria-live="polite"
              aria-atomic="false"
            >
              {term.map((l, i) => (
                <div key={i} className="whitespace-pre-wrap break-all">
                  {l.kind === 'cmd' && (
                    <span>
                      <span className="text-acc font-bold">❯ </span>
                      <span className="text-[var(--text)]">{l.text}</span>
                    </span>
                  )}
                  {l.kind === 'out' && <span className="text-dimx">  {l.text}</span>}
                  {l.kind === 'json' && <span className="text-[var(--syn-key)]">  {l.text}</span>}
                </div>
              ))}
              <div>
                <span className="text-acc font-bold">❯ </span>
                <span className="text-[var(--text)]">{cmd}</span>
                <span className="caret-blink text-acc" aria-hidden>
                  ▊
                </span>
              </div>
            </div>
          </div>

          <div className="flex flex-col overflow-hidden rounded-[8px] border border-linex bg-panelx">
            <MockTitleBar
              title="standup.md"
              trailing={
                <span className={`transition-opacity duration-300 ${badge ? 'opacity-100' : 'opacity-0'}`}>
                  <span className="inline-flex h-5 items-center gap-1.5 rounded-[4px] border border-[rgba(var(--acc-rgb),0.35)] bg-[var(--acc-soft)] px-2 text-[9px] text-acc">
                    <span className="inline-block h-1 w-1 rounded-full bg-[var(--acc)]" />
                    typed by agent
                  </span>
                </span>
              }
            />
            <div className="flex-1 p-4 md:p-5 min-h-[200px]">
              {note.map((l, i) => (
                <div
                  key={i}
                  className={`leading-[1.9] ${
                    l.startsWith('# ')
                      ? 'text-[15px] font-bold text-[var(--text)]'
                      : 'text-[12.5px] text-dimx'
                  }`}
                >
                  {l.startsWith('# ') ? l.slice(2) : l}
                </div>
              ))}
              {(noteTyping || noteCaret) && (
                <div className="text-[12.5px] text-[var(--text)] leading-[1.9]">
                  {noteTyping}
                  <span className="caret-blink text-acc">▊</span>
                </div>
              )}
              {note.length === 0 && !noteTyping && (
                <div className="text-[11px] text-faintx italic">waiting for filesystem events…</div>
              )}
            </div>
            <div className="border-t border-linex px-4 py-2.5 text-[10px] leading-[1.6] text-faintx">
              Outside edits type themselves in — caret and all — so you notice without a notification.
            </div>
          </div>
        </Reveal>
      </div>
    </section>
  )
}
