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
const durationInFrames = 102

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

const transformGestureInto = (points: Point[], rect: { x: number; y: number; width: number; height: number }, inset = 18): Point[] => {
  const xs = points.map(([x]) => x)
  const ys = points.map(([, y]) => y)
  const minX = Math.min(...xs)
  const maxX = Math.max(...xs)
  const minY = Math.min(...ys)
  const maxY = Math.max(...ys)
  const sourceWidth = maxX - minX
  const sourceHeight = maxY - minY
  const scale = Math.min((rect.width - inset * 2) / sourceWidth, (rect.height - inset * 2) / sourceHeight)
  const offsetX = rect.x + rect.width / 2 - (sourceWidth * scale) / 2
  const offsetY = rect.y + rect.height / 2 - (sourceHeight * scale) / 2

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
  const inputRect = { x: 176, y: 176, width: 368, height: 96 }
  const matrixRect = { x: width / 2 - 112, y: height / 2 - 116, width: 224, height: 224 }
  const inputGesturePoints = transformGestureInto(capturedGesture, inputRect, 26)
  const gesturePoints = transformGestureInto(capturedGesture, matrixRect, 65)
  const inputLength = pathLength(inputGesturePoints)
  const matrixLength = pathLength(gesturePoints)
  const inputReveal = spring({
    frame: frame - 4,
    fps: configFps,
    config: { damping: 17, mass: 0.72, stiffness: 80 },
    durationInFrames: 28,
  })
  const inputExit = interpolate(frame, [34, 47], [1, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' })
  const matrixIntro = spring({
    frame: frame - 30,
    fps: configFps,
    config: { damping: 18, mass: 0.78, stiffness: 96 },
    durationInFrames: 18,
  })
  const replay = spring({
    frame: frame - 43,
    fps: configFps,
    config: { damping: 18, mass: 0.72, stiffness: 86 },
    durationInFrames: 29,
  })
  const settle = spring({
    frame: frame - 67,
    fps: configFps,
    config: { damping: 16, mass: 0.7, stiffness: 130 },
    durationInFrames: 14,
  })
  const confirmation = spring({
    frame: frame - 70,
    fps: configFps,
    config: { damping: 15, mass: 0.65, stiffness: 150 },
    durationInFrames: 13,
  })
  const fade = interpolate(frame, [91, 101], [1, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' })
  const shownPoints = visiblePoints(gesturePoints, replay)
  const inputShownPoints = visiblePoints(inputGesturePoints, inputReveal)
  const activeCells = cellsTouched(shownPoints)
  const tip = shownPoints[shownPoints.length - 1] ?? gesturePoints[0]
  const inputTip = inputShownPoints[inputShownPoints.length - 1] ?? inputGesturePoints[0]
  const pulse = 1 + Math.sin(frame * 0.65) * 0.08
  const gridCell = 24
  const gridGap = 14
  const gridSize = gridCell * 3 + gridGap * 2
  const gridStartX = width / 2 - gridSize / 2
  const gridStartY = height / 2 - gridSize / 2 - 4
  const matrixOpacity = easeOut(matrixIntro)
  const matrixScale = 0.92 + matrixOpacity * 0.08

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

        <g opacity={inputExit}>
          <rect
            x={inputRect.x}
            y={inputRect.y}
            width={inputRect.width}
            height={inputRect.height}
            rx="24"
            fill="rgba(28,28,30,0.74)"
            stroke="rgba(255,255,255,0.10)"
          />
          <rect x={inputRect.x + 24} y={inputRect.y + 32} width="34" height="32" rx="10" fill="rgba(244,255,248,0.08)" />
          <circle cx={inputRect.x + 41} cy={inputRect.y + 48} r="4" fill="rgba(51,199,115,0.78)" />
          <path
            d={`M ${inputRect.x + 82} ${inputRect.y + 48} L ${inputRect.x + 250} ${inputRect.y + 48}`}
            stroke="rgba(244,255,248,0.10)"
            strokeWidth="2"
            strokeLinecap="round"
            strokeDasharray="1 12"
          />
          <path
            d={pointsToPath(inputGesturePoints)}
            fill="none"
            stroke="#33c773"
            strokeWidth="18"
            strokeLinecap="round"
            strokeLinejoin="round"
            opacity="0.12"
            strokeDasharray={inputLength}
            strokeDashoffset={inputLength * (1 - inputReveal)}
          />
          <path
            d={pointsToPath(inputGesturePoints)}
            fill="none"
            stroke="#33c773"
            strokeWidth="6"
            strokeLinecap="round"
            strokeLinejoin="round"
            opacity="0.76"
            strokeDasharray={inputLength}
            strokeDashoffset={inputLength * (1 - inputReveal)}
          />
          <path
            d={pointsToPath(inputGesturePoints)}
            fill="none"
            stroke="#f4fff8"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
            opacity="0.88"
            strokeDasharray={inputLength}
            strokeDashoffset={inputLength * (1 - inputReveal)}
          />
          <circle cx={inputTip[0]} cy={inputTip[1]} r={8 * pulse} fill="rgba(51,199,115,0.24)" />
          <circle cx={inputTip[0]} cy={inputTip[1]} r="3" fill="#f4fff8" />
        </g>

        <g
          opacity={matrixOpacity}
          transform={`translate(${width / 2} ${height / 2}) scale(${matrixScale}) translate(${-width / 2} ${-height / 2})`}
        >
          <rect
            x={matrixRect.x}
            y={matrixRect.y}
            width={matrixRect.width}
            height={matrixRect.height}
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
            strokeDasharray={matrixLength}
            strokeDashoffset={matrixLength * (1 - replay)}
          />
          <path
            d={pointsToPath(gesturePoints)}
            fill="none"
            stroke="#33c773"
            strokeWidth="9"
            strokeLinecap="round"
            strokeLinejoin="round"
            opacity="0.76"
            strokeDasharray={matrixLength}
            strokeDashoffset={matrixLength * (1 - replay)}
          />
          <path
            d={pointsToPath(gesturePoints)}
            fill="none"
            stroke="#f4fff8"
            strokeWidth="3"
            strokeLinecap="round"
            strokeLinejoin="round"
            opacity="0.92"
            strokeDasharray={matrixLength}
            strokeDashoffset={matrixLength * (1 - replay)}
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
