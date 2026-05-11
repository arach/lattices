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

const width = 1280
const height = 720
const fps = 30
const durationInFrames = 396

type Point = [number, number]
type KeyPoint = { frame: number; point: Point }

const utterance = 'Add the stop gesture, insert the text, and send it with enter.'

const startGesture: Point[] = [
  [864, 590],
  [864, 560],
  [863, 530],
  [864, 498],
  [865, 470],
]

const stopGesture: Point[] = [
  [866, 468],
  [866, 502],
  [865, 535],
  [866, 565],
  [868, 592],
]

const enterGesture: Point[] = [
  [1098, 590],
  [1098, 628],
  [1062, 628],
  [1018, 628],
  [978, 625],
]

const cursorTrack: KeyPoint[] = [
  { frame: 0, point: [770, 410] },
  { frame: 22, point: [530, 256] },
  { frame: 42, point: [820, 560] },
  { frame: 54, point: startGesture[0] },
  { frame: 74, point: startGesture[startGesture.length - 1] },
  { frame: 106, point: [1028, 438] },
  { frame: 146, point: [920, 612] },
  { frame: 182, point: [720, 408] },
  { frame: 194, point: stopGesture[0] },
  { frame: 218, point: stopGesture[stopGesture.length - 1] },
  { frame: 246, point: [912, 612] },
  { frame: 292, point: [1064, 592] },
  { frame: 306, point: enterGesture[0] },
  { frame: 330, point: enterGesture[enterGesture.length - 1] },
  { frame: 360, point: [1080, 610] },
  { frame: 395, point: [1114, 628] },
]

const clamp = (value: number, min = 0, max = 1) => Math.min(max, Math.max(min, value))
const easeOut = (value: number) => 1 - Math.pow(1 - clamp(value), 3)
const easeInOut = (value: number) => {
  const t = clamp(value)
  return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2
}

const pointAt = (track: KeyPoint[], frame: number): Point => {
  for (let index = 1; index < track.length; index += 1) {
    const previous = track[index - 1]
    const current = track[index]
    if (frame <= current.frame) {
      const local = easeInOut((frame - previous.frame) / Math.max(1, current.frame - previous.frame))
      return [
        previous.point[0] + (current.point[0] - previous.point[0]) * local,
        previous.point[1] + (current.point[1] - previous.point[1]) * local,
      ]
    }
  }
  return track[track.length - 1].point
}

const pathLength = (points: Point[]) =>
  points.slice(1).reduce((total, point, index) => {
    const previous = points[index]
    return total + Math.hypot(point[0] - previous[0], point[1] - previous[1])
  }, 0)

const pointsToPath = (points: Point[]) => points.map(([x, y], index) => `${index === 0 ? 'M' : 'L'} ${x} ${y}`).join(' ')

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

  if (current) lines.push(current)
  return lines
}

const visibleChars = (text: string, progress: number) => text.slice(0, Math.floor(text.length * clamp(progress)))

const DrawGesturePath: React.FC<{ points: Point[]; progress: number; opacity: number; color?: string }> = ({
  points,
  progress,
  opacity,
  color = '#48d987',
}) => {
  const length = pathLength(points)
  return (
    <g opacity={opacity}>
      <path
        d={pointsToPath(points)}
        fill="none"
        stroke={color}
        strokeWidth="18"
        strokeLinecap="round"
        strokeLinejoin="round"
        opacity="0.13"
        strokeDasharray={length}
        strokeDashoffset={length * (1 - clamp(progress))}
      />
      <path
        d={pointsToPath(points)}
        fill="none"
        stroke={color}
        strokeWidth="5.5"
        strokeLinecap="round"
        strokeLinejoin="round"
        opacity="0.86"
        strokeDasharray={length}
        strokeDashoffset={length * (1 - clamp(progress))}
      />
      <path
        d={pointsToPath(points)}
        fill="none"
        stroke="#f5fff8"
        strokeWidth="1.7"
        strokeLinecap="round"
        strokeLinejoin="round"
        opacity="0.86"
        strokeDasharray={length}
        strokeDashoffset={length * (1 - clamp(progress))}
      />
    </g>
  )
}

const Cursor: React.FC<{ x: number; y: number }> = ({ x, y }) => (
  <g transform={`translate(${x} ${y})`}>
    <path d="M 0 0 L 0 24 L 7 18 L 12 30 L 18 27 L 13 15 L 22 15 Z" fill="#f7f8fb" stroke="rgba(0,0,0,0.55)" strokeWidth="1.25" />
    <path d="M 0 0 L 0 24 L 7 18 L 12 30" fill="none" stroke="rgba(255,255,255,0.55)" strokeWidth="1" />
  </g>
)

const Hud: React.FC<{ title: string; detail: string; start: number; end: number; tone?: 'green' | 'amber' | 'blue' }> = ({
  title,
  detail,
  start,
  end,
  tone = 'green',
}) => {
  const frame = useCurrentFrame()
  const opacity = interpolate(frame, [start, start + 8, end - 10, end], [0, 1, 1, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  })
  const lift = interpolate(frame, [start, start + 10], [8, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' })
  const color = tone === 'amber' ? '#e4ad49' : tone === 'blue' ? '#73b5ff' : '#48d987'

  return (
    <g opacity={opacity} transform={`translate(0 ${lift})`}>
      <rect x="478" y="78" width="324" height="74" rx="16" fill="rgba(17,20,23,0.78)" stroke={`${color}66`} />
      <rect x="498" y="101" width="8" height="31" rx="4" fill={color} />
      <text x="524" y="108" fill="rgba(255,255,255,0.56)" fontFamily="ui-monospace, SFMono-Regular, Menlo, monospace" fontSize="12">
        LATTICES INPUT
      </text>
      <text x="524" y="132" fill="#ffffff" fontFamily="-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" fontSize="20" fontWeight="700">
        {title}
      </text>
      <text x="684" y="132" fill="rgba(255,255,255,0.48)" fontFamily="-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" fontSize="14">
        {detail}
      </text>
    </g>
  )
}

const Caption: React.FC<{ text: string; start: number; end: number }> = ({ text, start, end }) => {
  const frame = useCurrentFrame()
  const opacity = interpolate(frame, [start, start + 8, end - 8, end], [0, 1, 1, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  })
  return (
    <g opacity={opacity}>
      <rect x="438" y="644" width="404" height="36" rx="12" fill="rgba(9,11,14,0.76)" stroke="rgba(255,255,255,0.12)" />
      <text x="640" y="667" textAnchor="middle" fill="rgba(255,255,255,0.78)" fontFamily="ui-monospace, SFMono-Regular, Menlo, monospace" fontSize="14">
        {text}
      </text>
    </g>
  )
}

const TranscriptOverlay: React.FC<{ text: string; opacity: number }> = ({ text, opacity }) => {
  const lines = wrapWords(text, 42)

  return (
    <g opacity={opacity}>
      <rect x="360" y="584" width="560" height="50" rx="14" fill="rgba(7,9,12,0.76)" stroke="rgba(72,217,135,0.26)" />
      <text x="386" y="606" fill="rgba(72,217,135,0.82)" fontFamily="ui-monospace, SFMono-Regular, Menlo, monospace" fontSize="11" fontWeight="700">
        LIVE TRANSCRIPT
      </text>
      {lines.slice(0, 2).map((line, index) => (
        <text key={index} x="506" y={606 + index * 16} fill="rgba(255,255,255,0.74)" fontFamily="ui-monospace, SFMono-Regular, Menlo, monospace" fontSize="12">
          {line}
        </text>
      ))}
    </g>
  )
}

const BrowserMock: React.FC = () => (
  <g>
    <rect x="56" y="82" width="608" height="574" rx="14" fill="rgba(13,17,23,0.96)" stroke="rgba(255,255,255,0.10)" />
    <rect x="56" y="82" width="608" height="42" rx="14" fill="rgba(255,255,255,0.035)" />
    <circle cx="82" cy="103" r="5" fill="#ff5f57" opacity="0.75" />
    <circle cx="100" cy="103" r="5" fill="#febc2e" opacity="0.75" />
    <circle cx="118" cy="103" r="5" fill="#28c840" opacity="0.75" />
    <text x="146" y="108" fill="rgba(255,255,255,0.58)" fontFamily="-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" fontSize="13" fontWeight="600">
      Lattices pull request
    </text>
    <rect x="92" y="154" width="440" height="20" rx="5" fill="rgba(180,124,255,0.34)" />
    <rect x="92" y="190" width="510" height="16" rx="4" fill="rgba(255,255,255,0.14)" />
    <rect x="92" y="220" width="464" height="10" rx="3" fill="rgba(255,255,255,0.18)" />
    <rect x="92" y="242" width="392" height="10" rx="3" fill="rgba(255,255,255,0.10)" />
    <rect x="92" y="264" width="502" height="10" rx="3" fill="rgba(255,255,255,0.10)" />
    <rect x="92" y="312" width="220" height="14" rx="4" fill="rgba(255,255,255,0.18)" />
    {Array.from({ length: 8 }, (_, index) => (
      <g key={index}>
        <circle cx="106" cy={354 + index * 26} r="3" fill="rgba(255,255,255,0.28)" />
        <rect x="122" y={349 + index * 26} width={330 + (index % 3) * 42} height="9" rx="3" fill="rgba(255,255,255,0.105)" />
      </g>
    ))}
  </g>
)

const TerminalMock: React.FC = () => (
  <g>
    <rect x="718" y="82" width="506" height="214" rx="14" fill="rgba(12,27,18,0.92)" stroke="rgba(83,196,116,0.26)" />
    <rect x="718" y="82" width="506" height="36" rx="14" fill="rgba(255,255,255,0.035)" />
    <text x="742" y="106" fill="rgba(188,255,206,0.78)" fontFamily="ui-monospace, SFMono-Regular, Menlo, monospace" fontSize="12" fontWeight="700">
      lattices logs
    </text>
    {Array.from({ length: 7 }, (_, index) => (
      <text key={index} x="742" y={146 + index * 20} fill={`rgba(188,255,206,${0.34 + index * 0.05})`} fontFamily="ui-monospace, SFMono-Regular, Menlo, monospace" fontSize="12">
        {index === 4 ? '[voice] dictation pipeline ready' : index === 5 ? '[mouse] gesture listener active' : 'event tap healthy - input passthrough ok'}
      </text>
    ))}
  </g>
)

const CodexMock: React.FC<{ draftText: string; submittedText: string; submitted: boolean; recording: number; transcribing: number }> = ({
  draftText,
  submittedText,
  submitted,
  recording,
  transcribing,
}) => {
  const frame = useCurrentFrame()
  const draftLines = wrapWords(draftText, 48)
  const submittedLines = wrapWords(submittedText, 48)
  const workingOpacity = interpolate(frame, [332, 350], [0, 1], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' })
  const submittedOpacity = interpolate(frame, [324, 340], [0, 1], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' })

  return (
    <g>
      <rect x="718" y="328" width="506" height="328" rx="18" fill="rgba(18,19,24,0.96)" stroke="rgba(255,255,255,0.11)" />
      <rect x="718" y="328" width="506" height="42" rx="18" fill="rgba(255,255,255,0.035)" />
      <text x="744" y="355" fill="rgba(255,255,255,0.68)" fontFamily="-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" fontSize="14" fontWeight="700">
        Codex
      </text>
      <text x="1156" y="355" fill="rgba(255,255,255,0.34)" fontFamily="ui-monospace, SFMono-Regular, Menlo, monospace" fontSize="11">
        ready
      </text>

      <g opacity={recording}>
        <rect x="766" y="392" width="410" height="60" rx="15" fill="rgba(72,217,135,0.08)" stroke="rgba(72,217,135,0.30)" />
        <circle cx="794" cy="422" r="7" fill="#48d987" />
        {Array.from({ length: 10 }, (_, index) => {
          const bar = 8 + Math.abs(Math.sin(frame * 0.21 + index * 0.7)) * 26
          return <rect key={index} x={822 + index * 12} y={422 - bar / 2} width="5" height={bar} rx="2.5" fill="rgba(72,217,135,0.76)" />
        })}
        <text x="966" y="427" fill="rgba(255,255,255,0.68)" fontFamily="ui-monospace, SFMono-Regular, Menlo, monospace" fontSize="13">
          recording
        </text>
      </g>

      <g opacity={transcribing}>
        <rect x="766" y="392" width="410" height="60" rx="15" fill="rgba(115,181,255,0.08)" stroke="rgba(115,181,255,0.30)" />
        <circle cx="794" cy="422" r={6 + Math.sin(frame * 0.22) * 2} fill="rgba(115,181,255,0.82)" />
        <text x="820" y="427" fill="rgba(255,255,255,0.68)" fontFamily="ui-monospace, SFMono-Regular, Menlo, monospace" fontSize="13">
          transcribing recorded audio...
        </text>
      </g>

      <g opacity={submittedOpacity}>
        <rect x="766" y="398" width="410" height="74" rx="15" fill="rgba(72,217,135,0.07)" stroke="rgba(72,217,135,0.28)" />
        <text x="792" y="424" fill="rgba(255,255,255,0.54)" fontFamily="ui-monospace, SFMono-Regular, Menlo, monospace" fontSize="12">
          submitted request
        </text>
        {submittedLines.slice(0, 2).map((line, index) => (
          <text key={index} x="792" y={448 + index * 18} fill="rgba(255,255,255,0.82)" fontFamily="-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" fontSize="14">
            {line}
          </text>
        ))}
      </g>

      <rect x="766" y="492" width="410" height="104" rx="18" fill="rgba(8,10,13,0.82)" stroke={draftText ? 'rgba(72,217,135,0.36)' : 'rgba(255,255,255,0.12)'} />
      <circle cx="794" cy="544" r="11" fill="rgba(72,217,135,0.12)" stroke="rgba(72,217,135,0.36)" />
      {draftText ? (
        draftLines.slice(0, 3).map((line, index) => (
          <text key={index} x="820" y={526 + index * 22} fill="rgba(255,255,255,0.74)" fontFamily="-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" fontSize="16">
            {line}
          </text>
        ))
      ) : (
        <text x="820" y="550" fill="rgba(255,255,255,0.32)" fontFamily="-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" fontSize="16">
          {submitted ? 'Ready for the next request...' : 'Dictate a request...'}
        </text>
      )}
      <rect x="1132" y="532" width="30" height="30" rx="9" fill={submitted ? 'rgba(72,217,135,0.72)' : 'rgba(255,255,255,0.08)'} />
      <path d="M 1140 548 L 1152 538 L 1162 548" fill="none" stroke="rgba(245,255,248,0.84)" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" />

      <g opacity={workingOpacity}>
        <rect x="766" y="604" width="410" height="34" rx="12" fill="rgba(255,255,255,0.045)" stroke="rgba(255,255,255,0.11)" />
        <text x="792" y="626" fill="rgba(255,255,255,0.84)" fontFamily="-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" fontSize="15" fontWeight="700">
          Codex is working...
        </text>
        <text x="982" y="626" fill="rgba(255,255,255,0.46)" fontFamily="ui-monospace, SFMono-Regular, Menlo, monospace" fontSize="12">
          request submitted from mouse gesture
        </text>
      </g>
    </g>
  )
}

const StateRail: React.FC = () => {
  const frame = useCurrentFrame()
  const steps = [
    ['start', 54],
    ['record', 74],
    ['stop', 194],
    ['transcribe', 224],
    ['insert', 256],
    ['enter', 306],
  ] as const

  return (
    <g>
      <rect x="56" y="28" width="1168" height="30" rx="11" fill="rgba(5,7,10,0.58)" stroke="rgba(255,255,255,0.08)" />
      {steps.map(([label, start], index) => {
        const active = frame >= start
        return (
          <g key={label} transform={`translate(${82 + index * 184} 0)`}>
            <circle cx="0" cy="43" r="5" fill={active ? '#48d987' : 'rgba(255,255,255,0.18)'} />
            <text x="14" y="47" fill={active ? 'rgba(255,255,255,0.82)' : 'rgba(255,255,255,0.34)'} fontFamily="ui-monospace, SFMono-Regular, Menlo, monospace" fontSize="12">
              {label}
            </text>
          </g>
        )
      })}
    </g>
  )
}

const DictationStateDemo: React.FC = () => {
  const frame = useCurrentFrame()
  const { fps: configFps } = useVideoConfig()
  const cursor = pointAt(cursorTrack, frame)

  const startProgress = spring({ frame: frame - 56, fps: configFps, config: { damping: 17, mass: 0.72, stiffness: 92 }, durationInFrames: 24 })
  const stopProgress = spring({ frame: frame - 196, fps: configFps, config: { damping: 17, mass: 0.72, stiffness: 92 }, durationInFrames: 24 })
  const enterProgress = spring({ frame: frame - 308, fps: configFps, config: { damping: 17, mass: 0.72, stiffness: 92 }, durationInFrames: 22 })
  const voiceProgress = interpolate(frame, [82, 186], [0, 1], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' })
  const insertProgress = interpolate(frame, [254, 282], [0, 1], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' })
  const promptText = frame >= 254 && frame < 332 ? visibleChars(utterance, insertProgress) : ''
  const submittedText = frame >= 332 ? utterance : ''
  const recording = interpolate(frame, [74, 88, 190, 204], [0, 1, 1, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' })
  const transcribing = interpolate(frame, [220, 230, 250, 260], [0, 1, 1, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' })
  const liveText = visibleChars(utterance, voiceProgress)
  const fade = interpolate(frame, [384, 395], [1, 0.92], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' })

  return (
    <AbsoluteFill style={{ backgroundColor: '#080b0f', opacity: fade }}>
      <Sequence from={58}>
        <Audio src={staticFile('blog/dictation-state-demo-v8-confirm.mp3')} volume={0.9} />
      </Sequence>
      <Sequence from={78}>
        <Audio src={staticFile('blog/dictation-state-demo-v8-recording.mp3')} volume={1.0} />
      </Sequence>
      <Sequence from={204}>
        <Audio src={staticFile('blog/dictation-state-demo-v8-stop.mp3')} volume={0.9} />
      </Sequence>
      <Sequence from={322}>
        <Audio src={staticFile('blog/dictation-state-demo-v8-confirm.mp3')} volume={0.9} />
      </Sequence>

      <svg width={width} height={height} viewBox={`0 0 ${width} ${height}`} role="img">
        <defs>
          <radialGradient id="bgGlow" cx="68%" cy="48%" r="74%">
            <stop offset="0%" stopColor="#2a9b68" stopOpacity="0.13" />
            <stop offset="45%" stopColor="#1d4065" stopOpacity="0.08" />
            <stop offset="100%" stopColor="#080b0f" stopOpacity="0" />
          </radialGradient>
          <filter id="softShadow" x="-50%" y="-50%" width="220%" height="220%">
            <feDropShadow dx="0" dy="10" stdDeviation="14" floodColor="#000000" floodOpacity="0.42" />
          </filter>
        </defs>

        <rect width={width} height={height} fill="#080b0f" />
        <rect width={width} height={height} fill="url(#bgGlow)" />
        <StateRail />

        <g filter="url(#softShadow)">
          <BrowserMock />
          <TerminalMock />
          <CodexMock draftText={promptText} submittedText={submittedText} submitted={frame >= 330} recording={recording} transcribing={transcribing} />
        </g>

        <TranscriptOverlay text={liveText} opacity={recording} />

        <DrawGesturePath
          points={startGesture}
          progress={startProgress}
          opacity={interpolate(frame, [54, 64, 98, 112], [0, 1, 1, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' })}
        />
        <DrawGesturePath
          points={stopGesture}
          progress={stopProgress}
          opacity={interpolate(frame, [194, 204, 236, 250], [0, 1, 1, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' })}
          color="#73b5ff"
        />
        <DrawGesturePath
          points={enterGesture}
          progress={enterProgress}
          opacity={interpolate(frame, [306, 316, 340, 354], [0, 1, 1, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' })}
        />

        <Hud title="Dictation started" detail="middle click up" start={62} end={120} />
        <Hud title="Recording stopped" detail="middle click down" start={206} end={262} tone="blue" />
        <Hud title="Enter sent" detail="mouse gesture" start={322} end={372} />

        <Caption text="middle click up -> record" start={58} end={118} />
        <Caption text="recorded voice -> transcript" start={118} end={206} />
        <Caption text="middle click down -> stop + transcribe" start={206} end={268} />
        <Caption text="gesture -> Enter -> submitted" start={320} end={360} />

        <Cursor x={cursor[0]} y={cursor[1]} />
      </svg>
    </AbsoluteFill>
  )
}

const Root: React.FC = () => (
  <Composition
    id="DictationStateDemo"
    component={DictationStateDemo}
    durationInFrames={durationInFrames}
    fps={fps}
    width={width}
    height={height}
  />
)

registerRoot(Root)
