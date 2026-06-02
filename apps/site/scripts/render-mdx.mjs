// Static-render the MDX blog components to plain HTML so the SEO/JS-disabled
// view of the blog isn't a wall of blank space. The React side hydrates the
// same placeholders with the interactive components.

const escapeHtml = (value) =>
  String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')

// Shared visual tokens — kept in sync with the live React components in
// apps/site/src/components/blog/*. The static output is meant to look like a
// frozen, non-interactive snapshot of the same UI.
const ff = "-apple-system, BlinkMacSystemFont, 'Inter', sans-serif"
const mono = "'JetBrains Mono', monospace"
const green = '#33c773'

function statsRow() {
  const stats = [
    { value: '~1s first', label: 'Response time' },
    { value: '~2,000', label: 'Context tokens' },
    { value: '97%', label: 'Test accuracy' },
    { value: '5', label: 'AI providers' },
  ]
  const cards = stats
    .map(
      (s) => `
        <div style="padding:16px 14px;border-radius:10px;border:1px solid rgba(255,255,255,0.06);background:rgba(255,255,255,0.02);text-align:center;">
          <div style="font-family:${mono};font-size:17px;font-weight:500;color:${green};margin-bottom:4px;">${escapeHtml(s.value)}</div>
          <div style="font-size:11px;color:rgba(255,255,255,0.5);">${escapeHtml(s.label)}</div>
        </div>`,
    )
    .join('')
  return `<div data-mdx-component="StatsRow" style="margin:32px 0;display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:12px;font-family:${ff};">${cards}</div>`
}

function latencyJourney() {
  const iterations = [
    { id: 1, label: 'Naive approach', timeLabel: '~7s', time: 7000, color: '#ef4444' },
    { id: 2, label: 'Direct API (Vercel AI SDK)', timeLabel: '~3.5s', time: 3500, color: '#f59e0b' },
    { id: 3, label: 'Long-running worker', timeLabel: '~2.5s', time: 2500, color: '#f59e0b' },
    { id: 4, label: 'Streaming TTS', timeLabel: '~1s to first audio', time: 2000, color: '#22c55e' },
    { id: 5, label: 'Pre-cached phrases', timeLabel: '<50ms ack', time: 50, color: '#22c55e' },
    { id: 6, label: 'Speak first, then act', timeLabel: '~2s e2e', time: 2000, color: '#33c773' },
  ]
  const max = 7000
  const rows = iterations
    .map((iter) => {
      const width = Math.max(2, (iter.time / max) * 100)
      return `
        <div style="display:grid;grid-template-columns:24px 1fr auto;align-items:center;gap:12px;padding:10px 14px;border-radius:8px;border:1px solid rgba(255,255,255,0.04);background:transparent;">
          <span style="width:20px;height:20px;border-radius:50%;display:inline-flex;align-items:center;justify-content:center;font-size:10px;background:${iter.color}12;color:${iter.color};border:1px solid ${iter.color}25;">${iter.id}</span>
          <div>
            <div style="font-size:13px;color:rgba(255,255,255,0.65);margin-bottom:6px;">${escapeHtml(iter.label)}</div>
            <div style="height:3px;border-radius:2px;background:rgba(255,255,255,0.025);overflow:hidden;">
              <div style="height:100%;width:${width}%;background:linear-gradient(90deg, ${iter.color}cc, ${iter.color}33);"></div>
            </div>
          </div>
          <span style="font-family:${mono};font-size:12px;color:${iter.color};">${escapeHtml(iter.timeLabel)}</span>
        </div>`
    })
    .join('')
  return `
    <div data-mdx-component="LatencyJourney" style="margin:32px 0;font-family:${ff};">
      <div style="display:flex;align-items:baseline;gap:12px;margin-bottom:20px;">
        <span style="font-size:12px;font-weight:500;text-transform:uppercase;letter-spacing:0.08em;color:${green};">Performance journey</span>
      </div>
      <div style="display:grid;gap:4px;">${rows}</div>
      <div style="margin-top:10px;padding:10px 14px;border-radius:8px;background:rgba(51,199,115,0.03);border:1px solid rgba(51,199,115,0.08);display:flex;align-items:center;justify-content:space-between;">
        <span style="font-size:12px;color:rgba(255,255,255,0.5);">Total improvement</span>
        <span style="font-family:${mono};font-size:13px;color:${green};">~7s → ~2s <span style="color:rgba(51,199,115,0.5);font-size:11px;">(first response at ~1s)</span></span>
      </div>
    </div>`
}

function turnPipeline() {
  const stages = [
    { label: 'Hotkey', time: '0ms', color: '#a78bfa' },
    { label: 'Vox (STT)', time: '~400ms', color: '#60a5fa' },
    { label: 'Ack sound', time: '<50ms', color: '#34d399' },
    { label: 'LLM inference', time: '500–1200ms', color: '#f59e0b' },
    { label: 'TTS narration', time: '~1s start', color: '#33c773' },
    { label: 'Execute', time: '<1ms', color: '#33c773' },
    { label: 'Done', time: '<50ms', color: '#33c773' },
  ]
  const rows = stages
    .map(
      (s) => `
        <div style="display:grid;grid-template-columns:38px 1fr auto;align-items:center;gap:12px;padding:8px 0;">
          <span style="width:38px;height:38px;border-radius:50%;display:inline-flex;align-items:center;justify-content:center;border:1.5px solid ${s.color}50;background:${s.color}10;color:${s.color};">●</span>
          <span style="font-size:13px;color:rgba(255,255,255,0.75);">${escapeHtml(s.label)}</span>
          <span style="font-family:${mono};font-size:11px;color:${s.color};">${escapeHtml(s.time)}</span>
        </div>`,
    )
    .join('')
  return `
    <div data-mdx-component="TurnPipeline" style="margin:32px 0;font-family:${ff};">
      <div style="font-size:12px;font-weight:500;text-transform:uppercase;letter-spacing:0.08em;color:${green};margin-bottom:20px;">Anatomy of a voice turn</div>
      <div>${rows}</div>
    </div>`
}

function archDiagram() {
  // The interactive diagram uses @arach/arc — heavy and dynamic. For the
  // static/SEO view, surface the structure as a labelled stack.
  const layers = [
    { label: 'Swift menu bar app', note: 'Hotkeys · AX · CG · SkyLight · visual feedback' },
    { label: 'bun worker (persistent)', note: 'JSON over stdin/stdout · system prompts on disk' },
    { label: 'Inference + TTS', note: 'Vercel AI SDK · 5 providers · streaming PCM' },
  ]
  const cards = layers
    .map(
      (l) => `
        <div style="padding:14px 16px;border-radius:10px;border:1px solid rgba(51,199,115,0.18);background:rgba(51,199,115,0.04);">
          <div style="font-family:${mono};font-size:13px;color:${green};margin-bottom:4px;">${escapeHtml(l.label)}</div>
          <div style="font-size:12px;color:rgba(255,255,255,0.5);">${escapeHtml(l.note)}</div>
        </div>`,
    )
    .join('')
  return `
    <div data-mdx-component="ArchDiagram" style="margin:32px 0;font-family:${ff};">
      <div style="font-size:12px;font-weight:500;text-transform:uppercase;letter-spacing:0.08em;color:${green};margin-bottom:12px;">System architecture</div>
      <div style="display:grid;gap:8px;">${cards}</div>
      <p style="margin-top:10px;font-size:11px;color:rgba(255,255,255,0.35);">The interactive diagram is available in the live blog post.</p>
    </div>`
}

function contextExplorer() {
  const before = [
    { app: 'iTerm2', title: 'Claude Code', position: '0,0 1440×900' },
    { app: 'iTerm2', title: 'Claude Code', position: '720,0 720×900' },
    { app: 'Google Chrome', title: 'GitHub — PR #42', position: '0,0 720×900' },
  ]
  const afterScreens = [
    { name: 'Built-in', res: '1728×1117' },
    { name: 'LG UltraFine', res: '2560×1440' },
  ]
  const afterWindows = [
    { app: 'iTerm2', title: 'Claude Code', cwd: '~/dev/lattices' },
    { app: 'iTerm2', title: 'Claude Code', cwd: '~/dev/vox' },
    { app: 'Google Chrome', title: 'GitHub — lattices PR #42', cwd: '—' },
    { app: 'Finder', title: 'Downloads', cwd: '—' },
  ]
  const beforeBlock = before
    .map(
      (w) =>
        `<div style="padding-left:16px;">{ <span style="color:#7ec8e3;">"app"</span>: <span style="color:${green};">"${escapeHtml(w.app)}"</span>, <span style="color:#7ec8e3;">"title"</span>: <span style="color:${green};">"${escapeHtml(w.title)}"</span>, <span style="color:#7ec8e3;">"position"</span>: <span style="color:${green};">"${escapeHtml(w.position)}"</span> }</div>`,
    )
    .join('')
  const afterWindowsBlock = afterWindows
    .map(
      (w) =>
        `<div style="padding-left:16px;">{ <span style="color:#7ec8e3;">"app"</span>: <span style="color:${green};">"${escapeHtml(w.app)}"</span>, <span style="color:#7ec8e3;">"title"</span>: <span style="color:${green};">"${escapeHtml(w.title)}"</span>${
          w.cwd !== '—' ? `, <span style="color:#c792ea;">// cwd</span> <span style="color:${green};">"${escapeHtml(w.cwd)}"</span>` : ''
        } }</div>`,
    )
    .join('')
  const afterScreensBlock = afterScreens
    .map(
      (s) =>
        `<div style="padding-left:16px;">{ <span style="color:#7ec8e3;">"name"</span>: <span style="color:${green};">"${escapeHtml(s.name)}"</span>, <span style="color:#7ec8e3;">"res"</span>: <span style="color:${green};">"${escapeHtml(s.res)}"</span> }</div>`,
    )
    .join('')
  return `
    <div data-mdx-component="ContextExplorer" style="margin:32px 0;font-family:${ff};">
      <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:16px;">
        <span style="font-size:13px;font-weight:500;text-transform:uppercase;letter-spacing:0.08em;color:${green};">What the AI sees (v2 — full context)</span>
        <span style="font-family:${mono};font-size:11px;color:rgba(255,255,255,0.4);">~2,000 tokens</span>
      </div>
      <div style="border-radius:12px;border:1px solid rgba(255,255,255,0.06);background:#0d0d0f;overflow:hidden;font-family:${mono};font-size:12px;color:rgba(255,255,255,0.55);">
        <div style="padding:14px 16px;line-height:1.7;">
          <div>{</div>
          <div style="padding-left:16px;"><span style="color:#7ec8e3;">"screens"</span>: [${afterScreensBlock}],</div>
          <div style="padding-left:16px;"><span style="color:#7ec8e3;">"windows"</span>: [${afterWindowsBlock}]</div>
          <div>}</div>
        </div>
      </div>
      <p style="margin-top:10px;font-size:11px;color:rgba(255,255,255,0.35);">Compared to the v1 baseline, every window now ships with frame, Z-order, terminal cwd, processes, and tmux session — making "focus on the lattices Claude Code" resolve to a specific window id.</p>
    </div>`
}

function testResults() {
  const categories = [
    { name: 'Awareness', score: 100 },
    { name: 'Tiling', score: 100 },
    { name: 'Layouts', score: 100 },
    { name: 'Focus', score: 96 },
    { name: 'Context', score: 94 },
    { name: 'Intelligence', score: 100 },
    { name: 'Error handling', score: 67 },
    { name: 'Speech quality', score: 100 },
  ]
  const rows = categories
    .map((c) => {
      const color = c.score === 100 ? '#33c773' : c.score >= 90 ? '#22c55e' : '#ef4444'
      return `
        <div style="display:grid;grid-template-columns:140px 1fr 56px;align-items:center;gap:12px;padding:10px 14px;border-radius:8px;border:1px solid rgba(255,255,255,0.04);">
          <span style="font-size:13px;color:rgba(255,255,255,0.7);">${escapeHtml(c.name)}</span>
          <div style="height:8px;border-radius:4px;background:rgba(255,255,255,0.04);overflow:hidden;">
            <div style="height:100%;width:${c.score}%;background:${color};"></div>
          </div>
          <span style="font-family:${mono};font-size:12px;color:${color};text-align:right;">${c.score}%</span>
        </div>`
    })
    .join('')
  return `
    <div data-mdx-component="TestResults" style="margin:32px 0;font-family:${ff};">
      <div style="display:flex;align-items:baseline;justify-content:space-between;margin-bottom:20px;">
        <span style="font-size:13px;font-weight:500;text-transform:uppercase;letter-spacing:0.08em;color:${green};">Test results</span>
        <div style="display:flex;align-items:baseline;gap:8px;">
          <span style="font-family:${mono};font-size:24px;color:${green};">95%</span>
          <span style="font-size:12px;color:rgba(255,255,255,0.35);">202/202 checks</span>
        </div>
      </div>
      <div style="display:grid;gap:6px;">${rows}</div>
    </div>`
}

const renderers = {
  StatsRow: statsRow,
  LatencyJourney: latencyJourney,
  TurnPipeline: turnPipeline,
  ArchDiagram: archDiagram,
  ContextExplorer: contextExplorer,
  TestResults: testResults,
}

export function renderMdxComponent(name) {
  const render = renderers[name]
  if (!render) {
    return `<div data-mdx-component="${name}" data-mdx-static="unknown"></div>`
  }
  return render()
}
