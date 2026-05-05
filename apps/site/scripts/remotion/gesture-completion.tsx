import React from 'react'
import {
  AbsoluteFill,
  Audio,
  Composition,
  interpolate,
  registerRoot,
  Sequence,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion'

const width = 720
const height = 450
const fps = 30
const durationInFrames = 360

type Point = [number, number]
type Rect = { x: number; y: number; width: number; height: number }

const startDictationGesture: Point[] = [
  [506, 268],
  [507, 244],
  [505, 218],
  [506, 194],
  [508, 174],
]

const stopDictationGesture: Point[] = [
  [512, 178],
  [512, 205],
  [510, 230],
  [512, 254],
  [514, 274],
]

const enterGesture: Point[] = [
  [520, 292],
  [522, 318],
  [519, 342],
  [498, 354],
  [466, 354],
  [438, 352],
]

const logoCells = new Set([0, 3, 6, 7, 8])
const transcriptText = 'Lattices supports mouse gestures, dictation, and shortcuts without touching the keyboard.'

const clamp = (value: number, min: number, max: number) => Math.min(max, Math.max(min, value))
const easeOut = (value: number) => 1 - Math.pow(1 - clamp(value, 0, 1), 3)

const pathLength = (points: Point[]) =>
  points.slice(1).reduce((total, point, index) => {
    const previous = points[index]
    return total + Math.hypot(point[0] - previous[0], point[1] - previous[1])
  }, 0)

const pointsToPath = (points: Point[]) => points.map(([x, y], index) => `${index === 0 ? 'M' : 'L'} ${x} ${y}`).join(' ')

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

const transformGestureInto = (points: Point[], rect: Rect, inset = 20): Point[] => {
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

const cellsTouched = (points: Point[], rect: Rect) => {
  const cells = new Set<number>()
  const cell = 17
  const gap = 9
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

const DrawGesturePath: React.FC<{ points: Point[]; progress: number; width?: number; glow?: number; opacity?: number }> = ({
  points,
  progress,
  width: strokeWidth = 5,
  glow = 18,
  opacity = 1,
}) => {
  const length = pathLength(points)
  return (
    <g opacity={opacity}>
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
    </g>
  )
}

const ClickRipple: React.FC<{ x: number; y: number; frameOffset: number; label?: string }> = ({ x, y, frameOffset, label }) => {
  const frame = useCurrentFrame()
  const progress = easeOut((frame - frameOffset) / 15)
  const opacity = interpolate(frame, [frameOffset, frameOffset + 15, frameOffset + 30], [0, 1, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  })

  return (
    <g opacity={opacity}>
      <circle cx={x} cy={y} r={6 + progress * 24} fill="none" stroke="rgba(51,199,115,0.42)" strokeWidth="2" />
      <circle cx={x} cy={y} r="4" fill="#f4fff8" />
      {label ? (
        <text x={x} y={y + 36} textAnchor="middle" fill="rgba(255,255,255,0.38)" fontFamily="ui-monospace, SFMono-Regular, Menlo, monospace" fontSize="10">
          {label}
        </text>
      ) : null}
    </g>
  )
}

const RecognitionPill: React.FC<{ x: number; y: number; label: string; start: number; end: number }> = ({ x, y, label, start, end }) => {
  const frame = useCurrentFrame()
  const opacity = interpolate(frame, [start, start + 8, end - 8, end], [0, 1, 1, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  })
  const lift = interpolate(frame, [start, start + 14], [6, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' })

  return (
    <g opacity={opacity} transform={`translate(0 ${lift})`}>
      <rect x={x - 54} y={y - 15} width="108" height="30" rx="9" fill="rgba(17,17,19,0.92)" stroke="rgba(51,199,115,0.34)" />
      <text x={x} y={y + 4} textAnchor="middle" fill="#f4fff8" fontFamily="ui-monospace, SFMono-Regular, Menlo, monospace" fontSize="11" fontWeight="700">
        {label}
      </text>
    </g>
  )
}

const VoiceParticles: React.FC<{ active: number }> = ({ active }) => {
  const frame = useCurrentFrame()
  return (
    <g opacity={active}>
      {Array.from({ length: 18 }, (_, index) => {
        const angle = index * 1.24
        const radius = 18 + ((frame * 1.7 + index * 13) % 54)
        const x = 276 + Math.cos(angle) * radius
        const y = 166 + Math.sin(angle * 0.72) * radius * 0.42
        const dotOpacity = 0.18 + 0.38 * Math.abs(Math.sin(frame * 0.08 + index))
        return <circle key={index} cx={x} cy={y} r={1.5 + (index % 3) * 0.7} fill={`rgba(51,199,115,${dotOpacity})`} />
      })}
    </g>
  )
}

const wrapWords = (text: string, maxLineLength: number) => {
  const lines: string[] = []
  let current = ''

  for (const word of text.split(' ')) {
    const next = current ? `${current} ${word}` : word
    if (next.length > maxLineLength && current) {
      lines.push(current)
      current = word
    } else {
      current = next
    }
  }

  if (current) {
    lines.push(current)
  }

  return lines
}

const WrappedPromptText: React.FC<{ text: string; characters: number; x: number; y: number }> = ({ text, characters, x, y }) => {
  const shown = text.slice(0, characters)
  const lines = wrapWords(shown, 50)

  return (
    <>
      {lines.slice(0, 3).map((line, index) => (
        <text key={index} x={x} y={y + index * 19} fill="rgba(255,255,255,0.66)" fontFamily="-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" fontSize="12.5">
          {line}
        </text>
      ))}
    </>
  )
}

const GestureCompletion: React.FC = () => {
  const frame = useCurrentFrame()
  const { fps: configFps } = useVideoConfig()
  const shell = { x: 86, y: 46, width: 548, height: 358 }
  const prompt = { x: 132, y: 270, width: 456, height: 82 }
  const matrixRect = { x: 452, y: 122, width: 118, height: 118 }

  const startProgress = spring({ frame: frame - 17, fps: configFps, config: { damping: 17, mass: 0.72, stiffness: 88 }, durationInFrames: 24 })
  const stopProgress = spring({ frame: frame - 224, fps: configFps, config: { damping: 17, mass: 0.72, stiffness: 88 }, durationInFrames: 24 })
  const transcriptProgress = interpolate(frame, [276, 306], [0, 1], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' })
  const enterProgress = spring({ frame: frame - 318, fps: configFps, config: { damping: 17, mass: 0.72, stiffness: 92 }, durationInFrames: 19 })
  const confirmation = spring({ frame: frame - 337, fps: configFps, config: { damping: 14, mass: 0.65, stiffness: 150 }, durationInFrames: 10 })
  const fade = interpolate(frame, [352, 359], [1, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' })
  const recording = interpolate(frame, [49, 60, 213, 224], [0, 1, 1, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' })
  const thinking = interpolate(frame, [246, 256, 270, 280], [0, 1, 1, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' })
  const promptReview = interpolate(frame, [306, 316, 334, 344], [0, 1, 1, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' })
  const matrixIntro = spring({ frame: frame - 312, fps: configFps, config: { damping: 16, mass: 0.7, stiffness: 118 }, durationInFrames: 12 })
  const shownCharacters = Math.floor(transcriptText.length * transcriptProgress)
  const enterPoints = transformGestureInto(enterGesture, matrixRect, 28)
  const shownEnter = visiblePoints(enterPoints, enterProgress)
  const activeCells = cellsTouched(shownEnter, matrixRect)
  const matrixOpacity = easeOut(matrixIntro)

  return (
    <AbsoluteFill style={{ backgroundColor: '#111113', opacity: fade }}>
      <Sequence from={60}>
        <Audio src={staticFile('blog/gesture-recording-voice.mp3')} volume={0.7} />
      </Sequence>
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

        <rect x={132} y={108} width="330" height="116" rx="14" fill="rgba(255,255,255,0.035)" stroke="rgba(255,255,255,0.06)" />
        <text x={154} y={141} fill="rgba(255,255,255,0.46)" fontFamily="-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" fontSize="13">
          {recording > 0.1 ? 'Recording voice prompt' : 'Ready for dictation'}
        </text>
        <g opacity={recording}>
          <circle cx={154} cy={178} r="5" fill="#33c773" />
          {[0, 1, 2, 3, 4, 5].map((index) => {
            const waveHeight = 10 + Math.abs(Math.sin((frame + index * 5) * 0.25)) * 24
            return <rect key={index} x={172 + index * 12} y={178 - waveHeight / 2} width="5" height={waveHeight} rx="2.5" fill="rgba(51,199,115,0.72)" />
          })}
          <text x={258} y={183} fill="rgba(255,255,255,0.56)" fontFamily="ui-monospace, SFMono-Regular, Menlo, monospace" fontSize="11">
            recording
          </text>
        </g>
        <VoiceParticles active={recording} />
        <g opacity={thinking}>
          <circle cx={154} cy={178} r="5" fill="rgba(255,255,255,0.32)" />
          <text x={172} y={183} fill="rgba(255,255,255,0.48)" fontFamily="ui-monospace, SFMono-Regular, Menlo, monospace" fontSize="11">
            transcribing...
          </text>
        </g>

        <ClickRipple x={startDictationGesture[0][0]} y={startDictationGesture[0][1]} frameOffset={9} />
        <DrawGesturePath points={startDictationGesture} progress={startProgress} width={4.5} glow={15} opacity={interpolate(frame, [12, 20, 45, 56], [0, 1, 1, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' })} />
        <RecognitionPill x={508} y={155} label="dictation" start={42} end={64} />

        <ClickRipple x={stopDictationGesture[0][0]} y={stopDictationGesture[0][1]} frameOffset={216} />
        <DrawGesturePath points={stopDictationGesture} progress={stopProgress} width={4.5} glow={15} opacity={interpolate(frame, [218, 226, 248, 258], [0, 1, 1, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' })} />
        <RecognitionPill x={514} y={294} label="stop" start={249} end={271} />

        <rect x={prompt.x} y={prompt.y} width={prompt.width} height={prompt.height} rx="18" fill="rgba(17,17,19,0.95)" stroke="rgba(255,255,255,0.10)" />
        <circle cx={prompt.x + 28} cy={prompt.y + 42} r="10" fill="rgba(51,199,115,0.12)" stroke="rgba(51,199,115,0.36)" />
        <WrappedPromptText text={transcriptText} characters={shownCharacters} x={prompt.x + 54} y={prompt.y + 36} />
        <g opacity={promptReview}>
          <circle
            cx={prompt.x + 112 + Math.sin(frame * 0.09) * 86}
            cy={prompt.y + 48 + Math.cos(frame * 0.11) * 18}
            r="5"
            fill="rgba(51,199,115,0.18)"
            stroke="rgba(51,199,115,0.55)"
          />
          <rect
            x={prompt.x + 50}
            y={prompt.y + 20}
            width="300"
            height="44"
            rx="12"
            fill="none"
            stroke="rgba(51,199,115,0.16)"
          />
        </g>
        <rect x={prompt.x + prompt.width - 48} y={prompt.y + 24} width="34" height="34" rx="10" fill={confirmation > 0.25 ? 'rgba(51,199,115,0.72)' : 'rgba(255,255,255,0.08)'} />
        <path d={`M ${prompt.x + prompt.width - 34} ${prompt.y + 41} L ${prompt.x + prompt.width - 24} ${prompt.y + 31} L ${prompt.x + prompt.width - 14} ${prompt.y + 41}`} fill="none" stroke="rgba(244,255,248,0.84)" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" />

        <ClickRipple x={enterGesture[0][0]} y={enterGesture[0][1]} frameOffset={309} />
        <DrawGesturePath points={enterGesture} progress={enterProgress} width={4.5} glow={15} opacity={interpolate(frame, [311, 318, 332, 342], [0, 1, 0.7, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' })} />

        <g opacity={matrixOpacity}>
          <rect x={matrixRect.x} y={matrixRect.y} width={matrixRect.width} height={matrixRect.height} rx="18" fill="rgba(28,28,30,0.90)" stroke="rgba(255,255,255,0.08)" />
          {Array.from({ length: 9 }, (_, index) => {
            const cell = 17
            const gap = 9
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
          <DrawGesturePath points={transformGestureInto(enterGesture, matrixRect, 28)} progress={enterProgress} width={4.5} glow={14} />
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
