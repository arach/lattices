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
const durationInFrames = 150

type Point = [number, number]
type Rect = { x: number; y: number; width: number; height: number }

const enterGesture: Point[] = [
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

const middleUpGesture: Point[] = [
  [0, 58],
  [1, 42],
  [-1, 26],
  [0, 11],
  [1, 0],
]

const logoCells = new Set([0, 3, 6, 7, 8])
const clamp = (value: number, min: number, max: number) => Math.min(max, Math.max(min, value))
const easeOut = (value: number) => 1 - Math.pow(1 - clamp(value, 0, 1), 3)

const pathLength = (points: Point[]) =>
  points.slice(1).reduce((total, point, index) => {
    const previous = points[index]
    return total + Math.hypot(point[0] - previous[0], point[1] - previous[1])
  }, 0)

const pointsToPath = (points: Point[]) => points.map(([x, y], index) => `${index === 0 ? 'M' : 'L'} ${x} ${y}`).join(' ')

const transformGestureInto = (points: Point[], rect: Rect, inset = 18): Point[] => {
  const xs = points.map(([x]) => x)
  const ys = points.map(([, y]) => y)
  const minX = Math.min(...xs)
  const maxX = Math.max(...xs)
  const minY = Math.min(...ys)
  const maxY = Math.max(...ys)
  const sourceWidth = Math.max(maxX - minX, 1)
  const sourceHeight = Math.max(maxY - minY, 1)
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

const cellsTouched = (points: Point[], rect: Rect) => {
  const cells = new Set<number>()
  const cell = 18
  const gap = 10
  const grid = cell * 3 + gap * 2
  const startX = rect.x + rect.width / 2 - grid / 2
  const startY = rect.y + rect.height / 2 - grid / 2
  const step = cell + gap

  for (const [x, y] of points) {
    const col = clamp(Math.round((x - startX - cell / 2) / step), 0, 2)
    const row = clamp(Math.round((y - startY - cell / 2) / step), 0, 2)
    cells.add(row * 3 + col)
  }

  return cells
}

const DrawGesturePath: React.FC<{ points: Point[]; progress: number; width?: number; glow?: number }> = ({
  points,
  progress,
  width: strokeWidth = 5,
  glow = 18,
}) => {
  const length = pathLength(points)
  return (
    <>
      <path
        d={pointsToPath(points)}
        fill="none"
        stroke="#33c773"
        strokeWidth={glow}
        strokeLinecap="round"
        strokeLinejoin="round"
        opacity="0.13"
        strokeDasharray={length}
        strokeDashoffset={length * (1 - progress)}
      />
      <path
        d={pointsToPath(points)}
        fill="none"
        stroke="#33c773"
        strokeWidth={strokeWidth}
        strokeLinecap="round"
        strokeLinejoin="round"
        opacity="0.82"
        strokeDasharray={length}
        strokeDashoffset={length * (1 - progress)}
      />
      <path
        d={pointsToPath(points)}
        fill="none"
        stroke="#f4fff8"
        strokeWidth={Math.max(1.5, strokeWidth * 0.34)}
        strokeLinecap="round"
        strokeLinejoin="round"
        opacity="0.88"
        strokeDasharray={length}
        strokeDashoffset={length * (1 - progress)}
      />
    </>
  )
}

const MouseGesture: React.FC<{ x: number; y: number; label: string; progress: number; opacity: number }> = ({
  x,
  y,
  label,
  progress,
  opacity,
}) => {
  const points = middleUpGesture.map(([px, py]) => [x + px, y + py] as Point)
  const shown = visiblePoints(points, progress)
  const tip = shown[shown.length - 1] ?? points[0]

  return (
    <g opacity={opacity}>
      <rect x={x - 19} y={y + 48} width="38" height="54" rx="19" fill="rgba(244,255,248,0.09)" stroke="rgba(244,255,248,0.16)" />
      <rect x={x - 4} y={y + 56} width="8" height="14" rx="4" fill="rgba(51,199,115,0.72)" />
      <DrawGesturePath points={points} progress={progress} width={4.5} glow={15} />
      <circle cx={tip[0]} cy={tip[1]} r="7" fill="rgba(51,199,115,0.22)" />
      <circle cx={tip[0]} cy={tip[1]} r="2.8" fill="#f4fff8" />
      <text x={x} y={y + 124} textAnchor="middle" fill="rgba(255,255,255,0.42)" fontFamily="ui-monospace, SFMono-Regular, Menlo, monospace" fontSize="10">
        {label}
      </text>
    </g>
  )
}

const GestureCompletion: React.FC = () => {
  const frame = useCurrentFrame()
  const { fps: configFps } = useVideoConfig()
  const shell = { x: 86, y: 46, width: 548, height: 358 }
  const prompt = { x: 132, y: 270, width: 456, height: 82 }
  const matrixRect = { x: 452, y: 130, width: 118, height: 118 }
  const startGesture = spring({ frame: frame - 8, fps: configFps, config: { damping: 16, mass: 0.7, stiffness: 88 }, durationInFrames: 18 })
  const stopGesture = spring({ frame: frame - 47, fps: configFps, config: { damping: 16, mass: 0.7, stiffness: 88 }, durationInFrames: 18 })
  const transcript = interpolate(frame, [65, 92], [0, 1], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' })
  const enterReplay = spring({ frame: frame - 100, fps: configFps, config: { damping: 17, mass: 0.72, stiffness: 92 }, durationInFrames: 22 })
  const confirmation = spring({ frame: frame - 122, fps: configFps, config: { damping: 14, mass: 0.65, stiffness: 150 }, durationInFrames: 12 })
  const fade = interpolate(frame, [140, 149], [1, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' })
  const recording = interpolate(frame, [18, 28, 48, 58], [0, 1, 1, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' })
  const thinking = interpolate(frame, [58, 68, 82, 92], [0, 1, 1, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' })
  const matrixIntro = spring({ frame: frame - 94, fps: configFps, config: { damping: 16, mass: 0.7, stiffness: 118 }, durationInFrames: 14 })
  const enterPoints = transformGestureInto(enterGesture, matrixRect, 30)
  const shownEnter = visiblePoints(enterPoints, enterReplay)
  const activeCells = cellsTouched(shownEnter, matrixRect)
  const typedText = 'Write a release note for the gesture flow.'
  const shownCharacters = Math.floor(typedText.length * transcript)
  const matrixOpacity = easeOut(matrixIntro)

  return (
    <AbsoluteFill style={{ backgroundColor: '#111113', opacity: fade }}>
      <svg width={width} height={height} viewBox={`0 0 ${width} ${height}`} role="img">
        <defs>
          <radialGradient id="stageGlow" cx="50%" cy="50%" r="64%">
            <stop offset="0%" stopColor="#33c773" stopOpacity="0.11" />
            <stop offset="48%" stopColor="#33c773" stopOpacity="0.028" />
            <stop offset="100%" stopColor="#000" stopOpacity="0" />
          </radialGradient>
          <filter id="softGlow" x="-80%" y="-80%" width="260%" height="260%">
            <feGaussianBlur stdDeviation="6" result="blur" />
            <feMerge>
              <feMergeNode in="blur" />
              <feMergeNode in="SourceGraphic" />
            </feMerge>
          </filter>
        </defs>

        <rect width={width} height={height} fill="#111113" />
        <rect width={width} height={height} fill="url(#stageGlow)" />

        <rect x={shell.x} y={shell.y} width={shell.width} height={shell.height} rx="18" fill="rgba(21,21,23,0.96)" stroke="rgba(255,255,255,0.08)" />
        <rect x={shell.x} y={shell.y} width={shell.width} height="44" rx="18" fill="rgba(255,255,255,0.025)" />
        <circle cx={shell.x + 24} cy={shell.y + 22} r="4" fill="rgba(255,255,255,0.20)" />
        <circle cx={shell.x + 40} cy={shell.y + 22} r="4" fill="rgba(255,255,255,0.14)" />
        <circle cx={shell.x + 56} cy={shell.y + 22} r="4" fill="rgba(255,255,255,0.10)" />
        <text x={shell.x + 86} y={shell.y + 27} fill="rgba(255,255,255,0.68)" fontFamily="-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" fontSize="13" fontWeight="600">
          Codex
        </text>
        <text x={shell.x + shell.width - 120} y={shell.y + 27} fill="rgba(255,255,255,0.30)" fontFamily="ui-monospace, SFMono-Regular, Menlo, monospace" fontSize="10">
          mouse-only prompt
        </text>

        <rect x={132} y={112} width="330" height="112" rx="14" fill="rgba(255,255,255,0.035)" stroke="rgba(255,255,255,0.06)" />
        <text x={154} y={145} fill="rgba(255,255,255,0.46)" fontFamily="-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" fontSize="13">
          Ready for dictation
        </text>
        <g opacity={recording}>
          <circle cx={154} cy={178} r="5" fill="#33c773" />
          {[0, 1, 2, 3, 4].map((index) => {
            const waveHeight = 10 + Math.abs(Math.sin((frame + index * 5) * 0.25)) * 22
            return (
              <rect
                key={index}
                x={172 + index * 12}
                y={178 - waveHeight / 2}
                width="5"
                height={waveHeight}
                rx="2.5"
                fill="rgba(51,199,115,0.72)"
              />
            )
          })}
          <text x={246} y={183} fill="rgba(255,255,255,0.56)" fontFamily="ui-monospace, SFMono-Regular, Menlo, monospace" fontSize="11">
            recording
          </text>
        </g>
        <g opacity={thinking}>
          <circle cx={154} cy={178} r="5" fill="rgba(255,255,255,0.32)" />
          <text x={172} y={183} fill="rgba(255,255,255,0.48)" fontFamily="ui-monospace, SFMono-Regular, Menlo, monospace" fontSize="11">
            transcribing...
          </text>
        </g>

        <MouseGesture x={510} y={84} label="middle + up" progress={startGesture} opacity={interpolate(frame, [0, 6, 34, 42], [0, 1, 1, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' })} />
        <MouseGesture x={510} y={84} label="middle + up" progress={stopGesture} opacity={interpolate(frame, [39, 45, 70, 78], [0, 1, 1, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' })} />

        <rect x={prompt.x} y={prompt.y} width={prompt.width} height={prompt.height} rx="18" fill="rgba(17,17,19,0.95)" stroke="rgba(255,255,255,0.10)" />
        <circle cx={prompt.x + 28} cy={prompt.y + 42} r="10" fill="rgba(51,199,115,0.12)" stroke="rgba(51,199,115,0.36)" />
        <text x={prompt.x + 54} y={prompt.y + 37} fill="rgba(255,255,255,0.62)" fontFamily="-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" fontSize="14">
          {typedText.slice(0, shownCharacters)}
        </text>
        <text x={prompt.x + 54 + Math.min(280, shownCharacters * 7.1)} y={prompt.y + 37} fill="rgba(51,199,115,0.75)" fontFamily="-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" fontSize="14" opacity={shownCharacters < typedText.length && transcript > 0 ? 1 : 0}>
          |
        </text>
        <rect x={prompt.x + prompt.width - 48} y={prompt.y + 24} width="34" height="34" rx="10" fill={confirmation > 0.25 ? 'rgba(51,199,115,0.72)' : 'rgba(255,255,255,0.08)'} />
        <path d={`M ${prompt.x + prompt.width - 34} ${prompt.y + 41} L ${prompt.x + prompt.width - 24} ${prompt.y + 31} L ${prompt.x + prompt.width - 14} ${prompt.y + 41}`} fill="none" stroke="rgba(244,255,248,0.84)" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" />

        <g opacity={matrixOpacity}>
          <rect x={matrixRect.x} y={matrixRect.y} width={matrixRect.width} height={matrixRect.height} rx="18" fill="rgba(28,28,30,0.88)" stroke="rgba(255,255,255,0.08)" />
          {Array.from({ length: 9 }, (_, index) => {
            const cell = 18
            const gap = 10
            const grid = cell * 3 + gap * 2
            const row = Math.floor(index / 3)
            const col = index % 3
            const x = matrixRect.x + matrixRect.width / 2 - grid / 2 + col * (cell + gap)
            const y = matrixRect.y + matrixRect.height / 2 - grid / 2 + row * (cell + gap)
            const active = activeCells.has(index)
            const mark = logoCells.has(index)
            return (
              <g key={index}>
                {active ? <rect x={x - 4} y={y - 4} width={cell + 8} height={cell + 8} rx="7" fill="rgba(51,199,115,0.14)" filter="url(#softGlow)" /> : null}
                <rect x={x} y={y} width={cell} height={cell} rx="5" fill={active ? 'rgba(51,199,115,0.88)' : `rgba(244,255,248,${mark ? 0.26 : 0.12})`} />
              </g>
            )
          })}
          <DrawGesturePath points={enterPoints} progress={enterReplay} width={5} glow={15} />
          <g opacity={easeOut(confirmation)}>
            <path d={`M ${matrixRect.x + 88} ${matrixRect.y + 24} L ${matrixRect.x + 88} ${matrixRect.y + 94} L ${matrixRect.x + 34} ${matrixRect.y + 94}`} fill="none" stroke="#33c773" strokeWidth="4" strokeLinecap="round" strokeLinejoin="round" />
            <path d={`M ${matrixRect.x + 34} ${matrixRect.y + 94} L ${matrixRect.x + 45} ${matrixRect.y + 86} M ${matrixRect.x + 34} ${matrixRect.y + 94} L ${matrixRect.x + 45} ${matrixRect.y + 102}`} fill="none" stroke="#33c773" strokeWidth="3" strokeLinecap="round" />
            <rect x={matrixRect.x + 28} y={matrixRect.y + 126} width="62" height="28" rx="8" fill="rgba(17,17,19,0.88)" stroke="rgba(51,199,115,0.36)" />
            <text x={matrixRect.x + 59} y={matrixRect.y + 144} textAnchor="middle" fill="#f4fff8" fontFamily="ui-monospace, SFMono-Regular, Menlo, monospace" fontSize="12" fontWeight="700">
              Enter
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
