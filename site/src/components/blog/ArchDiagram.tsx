import { useState } from 'react'

const mono = "'JetBrains Mono', monospace"
const ff = "-apple-system, BlinkMacSystemFont, 'Inter', sans-serif"

interface Node {
  id: string
  label: string
  sublabel?: string
  x: number
  y: number
  color: string
  size: 'lg' | 'md' | 'sm'
}

interface Edge {
  from: string
  to: string
  label?: string
  style?: 'solid' | 'dashed'
}

const nodes: Node[] = [
  { id: 'swift', label: 'Swift App', sublabel: 'Menu bar + AX APIs', x: 120, y: 180, color: '#f59e0b', size: 'lg' },
  { id: 'worker', label: 'Bun Worker', sublabel: 'stdin/stdout JSON', x: 360, y: 180, color: '#33c773', size: 'lg' },
  { id: 'vox', label: 'Vox', sublabel: 'Push-to-talk', x: 120, y: 60, color: '#a78bfa', size: 'md' },
  { id: 'groq', label: 'Groq', sublabel: 'Llama 3.3 70B', x: 540, y: 60, color: '#60a5fa', size: 'sm' },
  { id: 'xai', label: 'xAI', sublabel: 'Grok', x: 600, y: 140, color: '#60a5fa', size: 'sm' },
  { id: 'openai', label: 'OpenAI', sublabel: 'TTS', x: 600, y: 220, color: '#60a5fa', size: 'sm' },
  { id: 'ffplay', label: 'ffplay', sublabel: 'PCM stream', x: 540, y: 300, color: '#34d399', size: 'sm' },
  { id: 'cache', label: 'TTS cache', sublabel: '~/.lattices/', x: 360, y: 310, color: '#34d399', size: 'sm' },
  { id: 'prompt', label: 'Prompt', sublabel: 'Hot-reload .md', x: 360, y: 60, color: '#f59e0b', size: 'sm' },
]

const edges: Edge[] = [
  { from: 'vox', to: 'swift', label: 'WebSocket' },
  { from: 'swift', to: 'worker', label: 'JSON lines' },
  { from: 'worker', to: 'groq', label: 'inference', style: 'dashed' },
  { from: 'worker', to: 'xai', style: 'dashed' },
  { from: 'worker', to: 'openai', label: 'TTS stream' },
  { from: 'openai', to: 'ffplay', label: 'PCM pipe' },
  { from: 'worker', to: 'cache', label: 'cached audio' },
  { from: 'prompt', to: 'worker' },
  { from: 'worker', to: 'swift', label: 'actions' },
]

const sizeMap = { lg: 34, md: 26, sm: 20 }

export default function ArchDiagram() {
  const [hovered, setHovered] = useState<string | null>(null)

  const connectedIds = new Set<string>()
  if (hovered) {
    connectedIds.add(hovered)
    edges.forEach(e => {
      if (e.from === hovered) connectedIds.add(e.to)
      if (e.to === hovered) connectedIds.add(e.from)
    })
  }

  return (
    <div style={{ margin: '32px 0', fontFamily: ff }}>
      <div style={{ fontSize: 12, fontWeight: 500, textTransform: 'uppercase', letterSpacing: '0.08em', color: '#33c773', marginBottom: 16 }}>
        System architecture
      </div>

      <div style={{
        borderRadius: 12, border: '1px solid rgba(255,255,255,0.05)',
        background: 'rgba(255,255,255,0.015)', padding: '20px 10px', overflow: 'hidden',
      }}>
        <svg viewBox="0 0 700 370" style={{ width: '100%', height: 'auto' }}>
          {/* Zone backgrounds */}
          <rect x="40" y="30" width="220" height="280" rx="12" fill="rgba(245,166,35,0.02)" stroke="rgba(245,166,35,0.06)" strokeDasharray="4 4" />
          <text x="50" y="22" fill="rgba(245,166,35,0.25)" fontSize="8" fontWeight="500" letterSpacing="0.1em" fontFamily={ff}>NATIVE (SWIFT)</text>

          <rect x="280" y="30" width="160" height="300" rx="12" fill="rgba(51,199,115,0.02)" stroke="rgba(51,199,115,0.06)" strokeDasharray="4 4" />
          <text x="290" y="22" fill="rgba(51,199,115,0.25)" fontSize="8" fontWeight="500" letterSpacing="0.1em" fontFamily={ff}>WORKER (BUN)</text>

          <rect x="470" y="30" width="200" height="300" rx="12" fill="rgba(96,165,250,0.02)" stroke="rgba(96,165,250,0.06)" strokeDasharray="4 4" />
          <text x="480" y="22" fill="rgba(96,165,250,0.25)" fontSize="8" fontWeight="500" letterSpacing="0.1em" fontFamily={ff}>CLOUD APIs</text>

          {/* Edges */}
          {edges.map((edge, i) => {
            const from = nodes.find(n => n.id === edge.from)!
            const to = nodes.find(n => n.id === edge.to)!
            const isConn = !hovered || (connectedIds.has(edge.from) && connectedIds.has(edge.to))
            return (
              <g key={i} opacity={isConn ? 0.5 : 0.08} style={{ transition: 'opacity 0.2s' }}>
                <line x1={from.x} y1={from.y} x2={to.x} y2={to.y}
                  stroke="rgba(255,255,255,0.25)" strokeWidth={1}
                  strokeDasharray={edge.style === 'dashed' ? '4 3' : undefined} />
                {edge.label && (
                  <text x={(from.x + to.x) / 2} y={(from.y + to.y) / 2 - 6}
                    fill="rgba(255,255,255,0.2)" fontSize="7" textAnchor="middle" fontFamily={mono} fontWeight="400">
                    {edge.label}
                  </text>
                )}
              </g>
            )
          })}

          {/* Nodes */}
          {nodes.map(node => {
            const r = sizeMap[node.size]
            const isHov = hovered === node.id
            const isConn = !hovered || connectedIds.has(node.id)
            const labelSize = node.size === 'sm' ? 9 : node.size === 'md' ? 10 : 11

            return (
              <g key={node.id}
                onMouseEnter={() => setHovered(node.id)}
                onMouseLeave={() => setHovered(null)}
                style={{ cursor: 'pointer', transition: 'opacity 0.2s' }}
                opacity={isConn ? 1 : 0.2}>
                <circle cx={node.x} cy={node.y} r={r}
                  fill={isHov ? `${node.color}12` : 'rgba(255,255,255,0.025)'}
                  stroke={isHov ? `${node.color}80` : 'rgba(255,255,255,0.08)'}
                  strokeWidth={1} style={{ transition: 'all 0.2s' }} />
                {/* Abbreviated text in circle */}
                <text x={node.x} y={node.y + 1} textAnchor="middle" dominantBaseline="middle"
                  fontSize={node.size === 'sm' ? 7 : 8} fontFamily={mono} fontWeight="400"
                  fill={isHov ? node.color : 'rgba(255,255,255,0.35)'}
                  style={{ transition: 'fill 0.15s' }}>
                  {node.label.slice(0, node.size === 'sm' ? 4 : 5)}
                </text>
                <text x={node.x} y={node.y + r + 13} textAnchor="middle"
                  fill={isHov ? 'rgba(255,255,255,0.85)' : 'rgba(255,255,255,0.5)'}
                  fontSize={labelSize} fontWeight="400" fontFamily={ff}
                  style={{ transition: 'fill 0.15s' }}>
                  {node.label}
                </text>
                {node.sublabel && (
                  <text x={node.x} y={node.y + r + 25} textAnchor="middle"
                    fill="rgba(255,255,255,0.2)" fontSize={Math.max(7, labelSize - 2)}
                    fontFamily={mono} fontWeight="400">
                    {node.sublabel}
                  </text>
                )}
              </g>
            )
          })}
        </svg>
      </div>

      <div style={{ marginTop: 8, textAlign: 'center', fontSize: 10, fontWeight: 400, color: 'rgba(255,255,255,0.2)' }}>
        Hover nodes to explore connections
      </div>
    </div>
  )
}
