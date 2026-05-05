import React from 'react'
import {
  AbsoluteFill,
  Composition,
  interpolate,
  registerRoot,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion'

const width = 720
const height = 450
const fps = 30
const durationInFrames = 78

type Point = [number, number]

const capturedGesture: Point[] = [
  [472, 138],
  [475, 172],
  [470, 214],
  [474, 254],
  [458, 284],
  [407, 291],
  [350, 288],
  [294, 292],
  [248, 288],
]

const logoCells = new Set([0, 3, 6, 7, 8])

const clamp = (value: number, min: number, max: number) => Math.min(max, Math.max(min, value))
const easeOut = (value: number) => 1 - Math.pow(1 - clamp(value, 0, 1), 3)

const pathLength = (points: Point[]) =>
  points.slice(1).reduce((total, point, index) => {
    const previous = points[index]
    return total + Math.hypot(point[0] - previous[0], point[1] - previous[1])
  }, 0)

const transformGesture = (points: Point[]): Point[] => {
  const xs = points.map(([x]) => x)
  const ys = points.map(([, y]) => y)
  const minX = Math.min(...xs)
  const maxX = Math.max(...xs)
  const minY = Math.min(...ys)
  const maxY = Math.max(...ys)
  const sourceWidth = maxX - minX
  const sourceHeight = maxY - minY
  const target = 94
  const scale = Math.min(target / sourceWidth, target / sourceHeight)
  const offsetX = width / 2 - (sourceWidth * scale) / 2
  const offsetY = height / 2 - (sourceHeight * scale) / 2 - 4

  return points.map(([x, y]) => [offsetX + (x - minX) * scale, offsetY + (y - minY) * scale])
}

const visiblePoints = (points: Point[], progress: number): Point[] => {
  const targetLength = pathLength(points) * clamp(progress, 0, 1)
  const visible: Point[] = [points[0]]
  let walked = 0

  for (let index = 1; index < points.length; index += 1) {
    const previous = points[index - 1]
    const current = points[index]
    const length = Math.hypot(current[0] - previous[0], current[1] - previous[1])

    if (walked + length <= targetLength) {
      visible.push(current)
      walked += length
      continue
    }

    const local = length === 0 ? 0 : (targetLength - walked) / length
    visible.push([
      previous[0] + (current[0] - previous[0]) * local,
      previous[1] + (current[1] - previous[1]) * local,
    ])
    break
  }

  return visible
}

const cellsTouched = (points: Point[]) => {
  const cells = new Set<number>()
  const cell = 24
  const gap = 14
  const grid = cell * 3 + gap * 2
  const startX = width / 2 - grid / 2
  const startY = height / 2 - grid / 2 - 4
  const step = cell + gap

  for (const [x, y] of points) {
    const col = clamp(Math.round((x - startX - cell / 2) / step), 0, 2)
    const row = clamp(Math.round((y - startY - cell / 2) / step), 0, 2)
    cells.add(row * 3 + col)
  }

  return cells
}

const pointsToPath = (points: Point[]) => points.map(([x, y], index) => `${index === 0 ? 'M' : 'L'} ${x} ${y}`).join(' ')

const GestureCompletion: React.FC = () => {
  const frame = useCurrentFrame()
  const { fps: configFps } = useVideoConfig()
  const gesturePoints = transformGesture(capturedGesture)
  const length = pathLength(gesturePoints)
  const reveal = spring({
    frame: frame - 5,
    fps: configFps,
    config: { damping: 18, mass: 0.72, stiffness: 86 },
    durationInFrames: 34,
  })
  const settle = spring({
    frame: frame - 38,
    fps: configFps,
    config: { damping: 16, mass: 0.7, stiffness: 130 },
    durationInFrames: 14,
  })
  const confirmation = spring({
    frame: frame - 36,
    fps: configFps,
    config: { damping: 15, mass: 0.65, stiffness: 150 },
    durationInFrames: 13,
  })
  const fade = interpolate(frame, [66, 77], [1, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' })
  const shownPoints = visiblePoints(gesturePoints, reveal)
  const activeCells = cellsTouched(shownPoints)
  const tip = shownPoints[shownPoints.length - 1] ?? gesturePoints[0]
  const pulse = 1 + Math.sin(frame * 0.65) * 0.08
  const gridCell = 24
  const gridGap = 14
  const gridSize = gridCell * 3 + gridGap * 2
  const gridStartX = width / 2 - gridSize / 2
  const gridStartY = height / 2 - gridSize / 2 - 4

  return (
    <AbsoluteFill style={{ backgroundColor: '#111113', opacity: fade }}>
      <svg width={width} height={height} viewBox={`0 0 ${width} ${height}`} role="img">
        <defs>
          <radialGradient id="glow" cx="50%" cy="50%" r="58%">
            <stop offset="0%" stopColor="#33c773" stopOpacity="0.16" />
            <stop offset="52%" stopColor="#33c773" stopOpacity="0.04" />
            <stop offset="100%" stopColor="#000" stopOpacity="0" />
          </radialGradient>
          <filter id="softGlow" x="-80%" y="-80%" width="260%" height="260%">
            <feGaussianBlur stdDeviation="7" result="blur" />
            <feMerge>
              <feMergeNode in="blur" />
              <feMergeNode in="SourceGraphic" />
            </feMerge>
          </filter>
        </defs>

        <rect width={width} height={height} fill="#111113" />
        <rect width={width} height={height} fill="url(#glow)" />
        <rect
          x={width / 2 - 112}
          y={height / 2 - 116}
          width="224"
          height="224"
          rx="26"
          fill="rgba(28,28,30,0.80)"
          stroke="rgba(255,255,255,0.08)"
        />

        {Array.from({ length: 9 }, (_, index) => {
          const row = Math.floor(index / 3)
          const col = index % 3
          const x = gridStartX + col * (gridCell + gridGap)
          const y = gridStartY + row * (gridCell + gridGap)
          const active = activeCells.has(index)
          const markCell = logoCells.has(index)
          const base = markCell ? 0.22 + settle * 0.24 : 0.11
          const activeOpacity = 0.74 + settle * 0.22

          return (
            <g key={index}>
              {active ? (
                <rect
                  x={x - 5}
                  y={y - 5}
                  width={gridCell + 10}
                  height={gridCell + 10}
                  rx="8"
                  fill="rgba(51,199,115,0.14)"
                  filter="url(#softGlow)"
                />
              ) : null}
              <rect
                x={x}
                y={y}
                width={gridCell}
                height={gridCell}
                rx="6"
                fill={active ? `rgba(51,199,115,${activeOpacity})` : `rgba(244,255,248,${base})`}
              />
              {active ? (
                <rect x={x + 5} y={y + 5} width={gridCell - 10} height={gridCell - 10} rx="3" fill="rgba(244,255,248,0.44)" />
              ) : null}
            </g>
          )
        })}

        <path
          d={pointsToPath(gesturePoints)}
          fill="none"
          stroke="#33c773"
          strokeWidth="26"
          strokeLinecap="round"
          strokeLinejoin="round"
          opacity="0.14"
          strokeDasharray={length}
          strokeDashoffset={length * (1 - reveal)}
        />
        <path
          d={pointsToPath(gesturePoints)}
          fill="none"
          stroke="#33c773"
          strokeWidth="9"
          strokeLinecap="round"
          strokeLinejoin="round"
          opacity="0.76"
          strokeDasharray={length}
          strokeDashoffset={length * (1 - reveal)}
        />
        <path
          d={pointsToPath(gesturePoints)}
          fill="none"
          stroke="#f4fff8"
          strokeWidth="3"
          strokeLinecap="round"
          strokeLinejoin="round"
          opacity="0.92"
          strokeDasharray={length}
          strokeDashoffset={length * (1 - reveal)}
        />

        <circle cx={tip[0]} cy={tip[1]} r={11 * pulse} fill="rgba(51,199,115,0.26)" />
        <circle cx={tip[0]} cy={tip[1]} r="4" fill="#f4fff8" />

        <g opacity={easeOut(confirmation)}>
          <path
            d={`M ${width / 2 + 56} ${height / 2 - 70} L ${width / 2 + 56} ${height / 2 + 66} L ${width / 2 - 50} ${height / 2 + 66}`}
            fill="none"
            stroke="#33c773"
            strokeWidth="6"
            strokeLinecap="round"
            strokeLinejoin="round"
          />
          <path
            d={`M ${width / 2 - 50} ${height / 2 + 66} L ${width / 2 - 32} ${height / 2 + 52} M ${width / 2 - 50} ${height / 2 + 66} L ${width / 2 - 32} ${height / 2 + 80}`}
            fill="none"
            stroke="#33c773"
            strokeWidth="4"
            strokeLinecap="round"
            strokeLinejoin="round"
          />
          <rect x={width / 2 - 50} y={height / 2 + 113} width="100" height="36" rx="10" fill="rgba(17,17,19,0.88)" stroke="rgba(51,199,115,0.36)" />
          <text
            x={width / 2}
            y={height / 2 + 136}
            textAnchor="middle"
            fill="#f4fff8"
            fontFamily="ui-monospace, SFMono-Regular, Menlo, monospace"
            fontSize="16"
            fontWeight="700"
          >
            Return
          </text>
        </g>
      </svg>
    </AbsoluteFill>
  )
}

const Root: React.FC = () => (
  <Composition
    id="GestureCompletion"
    component={GestureCompletion}
    durationInFrames={durationInFrames}
    fps={fps}
    width={width}
    height={height}
  />
)

registerRoot(Root)
