import { useState, useRef } from 'react'
import '../styles/concept-experiment.css'

interface FleetHost {
  id: string
  name: string
  sub: string
  model: string
  badge?: string
  icon: string
  specs: string
}

interface SpatialWindow {
  id: number
  slot: string
  label: string
  app: string
  role: string
  bounds: string
  pid: string
  state: string
  isOrange: boolean // 5 signature terracotta keys forming the "L"
  isAgent?: boolean
}

const FLEET_HOSTS: FleetHost[] = [
  {
    id: 'studio',
    name: 'Studio · M2 Ultra',
    sub: '3 windows · 1 agent needs review',
    model: 'Mac14,14 (Apple Silicon)',
    badge: 'ATTN',
    icon: '🖥️',
    specs: 'macOS 15.1 · 128 GB Unified · 10GbE local',
  },
  {
    id: 'macbook',
    name: 'MacBook Pro · M3 Max',
    sub: '5 windows · 2 subagents idle',
    model: 'Mac15,9 (Apple Silicon)',
    icon: '💻',
    specs: 'macOS 15.1 · 64 GB Unified · Wi-Fi 6E',
  },
  {
    id: 'mini',
    name: 'Mac mini · M4 Pro',
    sub: '2 windows · Build suite passing',
    model: 'Mac16,10 (Apple Silicon)',
    icon: '📦',
    specs: 'macOS 15.0 · 32 GB Unified · 10GbE local',
  },
]

// 3x3 Key Matrix: 5 terracotta keys forming the signature "L" (1, 4, 7, 8, 9), 4 cream keys (2, 3, 5, 6)
const WINDOWS_BY_HOST: Record<string, SpatialWindow[]> = {
  studio: [
    {
      id: 1,
      slot: 'NW',
      label: 'North-West',
      app: 'Claude Code',
      role: 'Autonomous Reasoning Subagent',
      bounds: '0, 0, 1280, 720',
      pid: 'PID 88201',
      state: 'BLOCKED // WAITING APPROVAL',
      isOrange: true,
      isAgent: true,
    },
    {
      id: 2,
      slot: 'N',
      label: 'North',
      app: 'Terminal: Vite Dev',
      role: 'Background Build Runner',
      bounds: '1280, 0, 1280, 720',
      pid: 'PID 71042',
      state: 'STREAMING // 60HZ',
      isOrange: false,
    },
    {
      id: 3,
      slot: 'NE',
      label: 'North-East',
      app: 'Activity & Audit',
      role: 'Kernel Stream & Telemetry',
      bounds: '2560, 0, 1280, 720',
      pid: 'PID 90431',
      state: 'IDLE // PERSISTED',
      isOrange: false,
    },
    {
      id: 4,
      slot: 'W',
      label: 'West',
      app: 'Cursor / NeoVim',
      role: 'Primary Human Code Editor',
      bounds: '0, 720, 1280, 720',
      pid: 'PID 54190',
      state: 'FOCUSED // KEYBOARD CAPTURED',
      isOrange: true,
    },
    {
      id: 5,
      slot: 'C',
      label: 'Core',
      app: 'Lattices Arbiter',
      role: 'Spatial Controller & Bridge',
      bounds: '1280, 720, 1280, 720',
      pid: 'PID 1104',
      state: 'ACTIVE // HARDWARE LINK',
      isOrange: false,
    },
    {
      id: 6,
      slot: 'E',
      label: 'East',
      app: 'Blink Notes',
      role: 'Spatial Thought Canvas',
      bounds: '2560, 720, 1280, 720',
      pid: 'PID 61288',
      state: 'SYNCED // 12 NOTES',
      isOrange: false,
    },
    {
      id: 7,
      slot: 'SW',
      label: 'South-West',
      app: 'Terminal: SQLite DB',
      role: 'Local Database Engine',
      bounds: '0, 1440, 1280, 720',
      pid: 'PID 93420',
      state: 'READY // PORT 5432',
      isOrange: true,
    },
    {
      id: 8,
      slot: 'S',
      label: 'South',
      app: 'Ghostty (tmux)',
      role: 'Microservices & Worker Daemons',
      bounds: '1280, 1440, 1280, 720',
      pid: 'PID 93421',
      state: '3 SESSIONS // ATTACHED',
      isOrange: true,
    },
    {
      id: 9,
      slot: 'SE',
      label: 'South-East',
      app: 'Chromium Surface',
      role: 'Headless Browser & E2E Tests',
      bounds: '2560, 1440, 1280, 720',
      pid: 'PID 44901',
      state: 'RENDER // 2.5K RETINA',
      isOrange: true,
    },
  ],
  macbook: [
    {
      id: 1,
      slot: 'NW',
      label: 'North-West',
      app: 'Xcode 16',
      role: 'Swift Compiler & Build Suite',
      bounds: '0, 0, 1728, 558',
      pid: 'PID 2291',
      state: 'BUILD SUCCEEDED',
      isOrange: true,
    },
    {
      id: 2,
      slot: 'N',
      label: 'North',
      app: 'Safari Specs',
      role: 'Apple Developer Documentation',
      bounds: '1728, 0, 1728, 558',
      pid: 'PID 3301',
      state: 'IDLE',
      isOrange: false,
    },
    {
      id: 3,
      slot: 'NE',
      label: 'North-East',
      app: 'Simulator Canvas',
      role: 'Touch & Pointer Testing',
      bounds: '3456, 0, 1728, 558',
      pid: 'PID 5501',
      state: 'RUNNING // 120HZ',
      isOrange: false,
    },
    {
      id: 4,
      slot: 'W',
      label: 'West',
      app: 'Terminal Shell',
      role: 'Git Worktree & Diff Runner',
      bounds: '0, 558, 1728, 558',
      pid: 'PID 7712',
      state: 'READY',
      isOrange: true,
    },
    {
      id: 5,
      slot: 'C',
      label: 'Core',
      app: 'Lattices Arbiter',
      role: 'Companion Server',
      bounds: '1728, 558, 1728, 558',
      pid: 'PID 1021',
      state: 'LISTENING',
      isOrange: false,
    },
    {
      id: 6,
      slot: 'E',
      label: 'East',
      app: 'Slack / Discord',
      role: 'Team Communication',
      bounds: '3456, 558, 1728, 558',
      pid: 'PID 8810',
      state: 'IDLE',
      isOrange: false,
    },
    {
      id: 7,
      slot: 'SW',
      label: 'South-West',
      app: 'Figma Canvas',
      role: 'Interface Architecture',
      bounds: '0, 1116, 1728, 558',
      pid: 'PID 9920',
      state: 'SYNCED',
      isOrange: true,
    },
    {
      id: 8,
      slot: 'S',
      label: 'South',
      app: 'Codex Subagent',
      role: 'Code Review Specialist',
      bounds: '1728, 1116, 1728, 558',
      pid: 'PID 4410',
      state: 'IDLE // COMPLETED',
      isOrange: true,
      isAgent: true,
    },
    {
      id: 9,
      slot: 'SE',
      label: 'South-East',
      app: 'Console Logs',
      role: 'System Logger',
      bounds: '3456, 1116, 1728, 558',
      pid: 'PID 1209',
      state: 'STREAMING',
      isOrange: true,
    },
  ],
  mini: [
    {
      id: 1,
      slot: 'NW',
      label: 'North-West',
      app: 'CI Pipeline (Bun)',
      role: 'Automated Test Runner',
      bounds: '0, 0, 1920, 540',
      pid: 'PID 10101',
      state: 'ALL 148 TESTS PASSING',
      isOrange: true,
    },
    {
      id: 2,
      slot: 'N',
      label: 'North',
      app: 'Docker Engine',
      role: 'Container Daemon',
      bounds: '1920, 0, 1920, 540',
      pid: 'PID 10102',
      state: '0 CONTAINERS',
      isOrange: false,
    },
    {
      id: 3,
      slot: 'NE',
      label: 'North-East',
      app: 'Telemetry Monitor',
      role: 'Server Resource Graph',
      bounds: '3840, 0, 1920, 540',
      pid: 'PID 10103',
      state: 'LOAD 0.42 · CPU 8%',
      isOrange: false,
    },
    {
      id: 4,
      slot: 'W',
      label: 'West',
      app: 'Postgres Server',
      role: 'Test DB Instance',
      bounds: '0, 540, 1920, 540',
      pid: 'PID 10104',
      state: 'READY',
      isOrange: true,
    },
    {
      id: 5,
      slot: 'C',
      label: 'Core',
      app: 'Lattices Arbiter',
      role: 'Companion Server',
      bounds: '1920, 540, 1920, 540',
      pid: 'PID 10105',
      state: 'LISTENING',
      isOrange: false,
    },
    {
      id: 6,
      slot: 'E',
      label: 'East',
      app: 'Redis Cache',
      role: 'Fast Key-Value Store',
      bounds: '3840, 540, 1920, 540',
      pid: 'PID 10106',
      state: 'READY',
      isOrange: false,
    },
    {
      id: 7,
      slot: 'SW',
      label: 'South-West',
      app: 'Scout Broker',
      role: 'Agent Fleet Coordinator',
      bounds: '0, 1080, 1920, 540',
      pid: 'PID 10107',
      state: 'CONNECTED',
      isOrange: true,
    },
    {
      id: 8,
      slot: 'S',
      label: 'South',
      app: 'Artifact Store',
      role: 'Build Output Mirror',
      bounds: '1920, 1080, 1920, 540',
      pid: 'PID 10108',
      state: 'IDLE',
      isOrange: true,
    },
    {
      id: 9,
      slot: 'SE',
      label: 'South-East',
      app: 'Kernel Audit',
      role: 'OS Log Collector',
      bounds: '3840, 1080, 1920, 540',
      pid: 'PID 10109',
      state: 'LOGGING',
      isOrange: true,
    },
  ],
}

export default function ConceptExperimentPage() {
  const [material, setMaterial] = useState<'paper' | 'anodized'>('paper')
  const [selectedHostId, setSelectedHostId] = useState<string>('studio')
  const [activeWindowId, setActiveWindowId] = useState<number>(4) // Default to West (Cursor)
  const [activeKeyDepressed, setActiveKeyDepressed] = useState<number | null>(null)
  const [agentDecisionState, setAgentDecisionState] = useState<'pending' | 'approved' | 'rejected'>('pending')
  const [knobAngle, setKnobAngle] = useState<number>(0)
  const [toggleMesh, setToggleMesh] = useState<boolean>(false)
  const [lastReceipt, setLastReceipt] = useState<string>('SYS. 01 ONLINE · USB-C HID BUS 12Mbps · Ed25519 Authenticated')
  const [soundEnabled, setSoundEnabled] = useState<boolean>(true)
  const audioCtxRef = useRef<AudioContext | null>(null)

  const activeHost = FLEET_HOSTS.find((h) => h.id === selectedHostId) || FLEET_HOSTS[0]
  const currentWindows = WINDOWS_BY_HOST[selectedHostId] || WINDOWS_BY_HOST.studio
  const activeWindow = currentWindows.find((w) => w.id === activeWindowId) || currentWindows[3]

  // Web Audio Synthesizer for Physical Mechanical Sounds
  const getAudioContext = (): AudioContext | null => {
    if (!soundEnabled) return null
    try {
      const AudioCtx = window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext
      if (!audioCtxRef.current) {
        audioCtxRef.current = new AudioCtx()
      }
      const ctx = audioCtxRef.current
      if (ctx.state === 'suspended') {
        ctx.resume()
      }
      return ctx
    } catch {
      return null
    }
  }

  // Authentic mechanical keyboard "thock"
  const playMechanicalKey = (isOrange: boolean, id: number) => {
    const ctx = getAudioContext()
    if (!ctx) return

    const t = ctx.currentTime
    const osc = ctx.createOscillator()
    const gain = ctx.createGain()
    const filter = ctx.createBiquadFilter()

    // Base frequency: terracotta keys have a deeper, weightier body (240Hz), cream keys are crisper (340Hz)
    const baseFreq = isOrange ? 230 + (id % 3) * 15 : 320 + (id % 3) * 20
    osc.type = 'triangle'
    osc.frequency.setValueAtTime(baseFreq, t)
    osc.frequency.exponentialRampToValueAtTime(55, t + 0.055)

    filter.type = 'lowpass'
    filter.frequency.setValueAtTime(isOrange ? 1200 : 1800, t)
    filter.frequency.exponentialRampToValueAtTime(300, t + 0.05)

    gain.gain.setValueAtTime(0.28, t)
    gain.gain.exponentialRampToValueAtTime(0.001, t + 0.06)

    osc.connect(filter)
    filter.connect(gain)
    gain.connect(ctx.destination)

    osc.start(t)
    osc.stop(t + 0.065)

    // Short contact click noise
    const noiseBuffer = ctx.createBuffer(1, ctx.sampleRate * 0.008, ctx.sampleRate)
    const output = noiseBuffer.getChannelData(0)
    for (let i = 0; i < noiseBuffer.length; i++) {
      output[i] = Math.random() * 2 - 1
    }
    const noise = ctx.createBufferSource()
    noise.buffer = noiseBuffer
    const noiseGain = ctx.createGain()
    noiseGain.gain.setValueAtTime(0.12, t)
    noiseGain.gain.exponentialRampToValueAtTime(0.001, t + 0.008)
    noise.connect(noiseGain)
    noiseGain.connect(ctx.destination)
    noise.start(t)
  }

  // Rotary encoder ratchet tick
  const playRotaryTick = () => {
    const ctx = getAudioContext()
    if (!ctx) return
    const t = ctx.currentTime
    const osc = ctx.createOscillator()
    const gain = ctx.createGain()
    osc.type = 'sine'
    osc.frequency.setValueAtTime(1900, t)
    osc.frequency.exponentialRampToValueAtTime(300, t + 0.015)
    gain.gain.setValueAtTime(0.18, t)
    gain.gain.exponentialRampToValueAtTime(0.001, t + 0.016)
    osc.connect(gain)
    gain.connect(ctx.destination)
    osc.start(t)
    osc.stop(t + 0.02)
  }

  // Heavy metal toggle switch clack
  const playToggleClack = () => {
    const ctx = getAudioContext()
    if (!ctx) return
    const t = ctx.currentTime
    const osc = ctx.createOscillator()
    const gain = ctx.createGain()
    osc.type = 'square'
    osc.frequency.setValueAtTime(450, t)
    osc.frequency.exponentialRampToValueAtTime(90, t + 0.035)
    gain.gain.setValueAtTime(0.2, t)
    gain.gain.exponentialRampToValueAtTime(0.001, t + 0.04)
    osc.connect(gain)
    gain.connect(ctx.destination)
    osc.start(t)
    osc.stop(t + 0.045)
  }

  // Micro push button click
  const playButtonPop = () => {
    const ctx = getAudioContext()
    if (!ctx) return
    const t = ctx.currentTime
    const osc = ctx.createOscillator()
    const gain = ctx.createGain()
    osc.type = 'triangle'
    osc.frequency.setValueAtTime(520, t)
    osc.frequency.exponentialRampToValueAtTime(120, t + 0.025)
    gain.gain.setValueAtTime(0.18, t)
    gain.gain.exponentialRampToValueAtTime(0.001, t + 0.03)
    osc.connect(gain)
    gain.connect(ctx.destination)
    osc.start(t)
    osc.stop(t + 0.035)
  }

  const handleKeyClick = (win: SpatialWindow) => {
    playMechanicalKey(win.isOrange, win.id)
    setActiveKeyDepressed(win.id)
    setActiveWindowId(win.id)
    setLastReceipt(`SYS.01 KEY 0${win.id} -> focused ${win.app} (${win.pid}) on ${activeHost.name} [1.8ms]`)
    setTimeout(() => setActiveKeyDepressed(null), 120)
  }

  const handleKnobClick = () => {
    playRotaryTick()
    const nextAngle = (knobAngle + 30) % 360
    setKnobAngle(nextAngle)
    const nextWindowId = (activeWindowId % 9) + 1
    setActiveWindowId(nextWindowId)
    const nextWin = currentWindows.find((w) => w.id === nextWindowId) || currentWindows[0]
    setLastReceipt(`ROTARY ROTATED 30° -> stepped layer to 0${nextWindowId} (${nextWin.app})`)
  }

  const handleToggleClick = () => {
    playToggleClack()
    const nextState = !toggleMesh
    setToggleMesh(nextState)
    setLastReceipt(nextState ? 'TOGGLE: Mesh Bonjour Relay Active (_lattices-fleet._tcp.)' : 'TOGGLE: USB-C Direct Zero-Latency HID Mode')
  }

  const handleApproveAgent = () => {
    playButtonPop()
    setAgentDecisionState('approved')
    setLastReceipt(`SYS.01 [KEY A: APPROVE] -> Authorized Claude Code schema change on ${activeHost.name} · Resuming turn`)
  }

  const handleRejectAgent = () => {
    playButtonPop()
    setAgentDecisionState('rejected')
    setLastReceipt(`SYS.01 [KEY B: REJECT] -> Blocked schema write on ${activeHost.name} · Agent parked`)
  }

  return (
    <div className="concept-exp-page" data-material={material}>
      <div className="concept-exp-bg-grid" />

      <div className="concept-exp-shell">
        {/* Top Technical Masthead */}
        <header className="concept-exp-header">
          <div className="concept-exp-brand">
            <div className="concept-exp-logo-glyph" aria-hidden="true">
              <span className="concept-exp-glyph-dot active" />
              <span className="concept-exp-glyph-dot" />
              <span className="concept-exp-glyph-dot" />
              <span className="concept-exp-glyph-dot active" />
              <span className="concept-exp-glyph-dot" />
              <span className="concept-exp-glyph-dot" />
              <span className="concept-exp-glyph-dot active" />
              <span className="concept-exp-glyph-dot active" />
              <span className="concept-exp-glyph-dot active" />
            </div>
            <div className="concept-exp-brand-text">
              <span>lattices</span>
              <span className="concept-exp-brand-meta">SYS. 01 // PHYSICAL ARBITER</span>
            </div>
          </div>

          <div className="concept-exp-telemetry">
            <span className={`concept-exp-led ${agentDecisionState === 'pending' ? 'amber' : 'green'}`} />
            <span>
              {agentDecisionState === 'pending'
                ? 'SYS. 01 ATTN: 1 AGENT BLOCKED ON SCHEMA WRITE'
                : 'SYS. 01 ONLINE: 3 TRUSTED MACS LINKED [1.8ms]'}
            </span>
          </div>

          <div className="concept-exp-controls">
            <button
              type="button"
              className="concept-exp-btn-toggle"
              onClick={() => setSoundEnabled(!soundEnabled)}
              title="Toggle tactile haptic audio"
            >
              <span>{soundEnabled ? '🔊 HAPTICS ON' : '🔇 HAPTICS OFF'}</span>
            </button>

            <button
              type="button"
              className="concept-exp-btn-toggle"
              onClick={() => setMaterial(material === 'paper' ? 'anodized' : 'paper')}
              title="Toggle between archival paper and anodized noir"
            >
              <span>{material === 'paper' ? '◻ ARCHIVAL PAPER' : '◼ ANODIZED NOIR'}</span>
            </button>

            <a href="/" className="concept-exp-backlink">
              ← Standard Site
            </a>
          </div>
        </header>

        {/* Hero Section (Poster Style) */}
        <section className="concept-exp-hero">
          <div className="concept-exp-crosshair top-left">+</div>
          <div className="concept-exp-crosshair top-right">+</div>
          <div className="concept-exp-crosshair bottom-left">+</div>
          <div className="concept-exp-crosshair bottom-right">+</div>

          <div className="concept-exp-kicker">
            SYS. 01 · Industrial Design &amp; Architectural Hardware Study
          </div>

          <h1 className="concept-exp-title">
            The physical workspace controller<br />
            for macOS &amp; autonomous agents.
          </h1>

          <p className="concept-exp-subtitle">
            Your primary keyboard belongs to typing code. Your mouse belongs to navigating text.
            <strong> SYS. 01 sits beside your desk to physically anchor your workspace</strong>: sculpted mechanical keys
            for instantaneous 3×3 spatial window recall, dedicated rotary arbitration, and a glanceable hardware attention deck for autonomous agents.
          </p>
        </section>

        {/* ══════════════════════════════════════════════════════════
            SYS. 01 PHYSICAL DESK CONTROLLER CENTERPIECE
            ══════════════════════════════════════════════════════════ */}
        <section className="concept-exp-console-showcase" aria-label="Interactive SYS. 01 Physical Console">
          <div className="concept-exp-console-meta-bar">
            <div className="concept-exp-console-meta-title">
              SYS. 01 — WORKSPACE CONTROLLER // PHYSICAL CONSOLE PROTOTYPE
            </div>
            <div className="concept-exp-console-meta-badge">
              <span>CNC 6061-T6 ALUMINUM</span>
              <span>&bull;</span>
              <span>KAILH CHOC LINEAR 45gf</span>
              <span>&bull;</span>
              <span>USB-C / BLE 5.3</span>
            </div>
          </div>

          {/* Heavy Milled Aluminum Enclosure */}
          <div className="concept-exp-chassis-unit">
            {/* Recessed corner screws */}
            <span className="concept-exp-chassis-screw tl" />
            <span className="concept-exp-chassis-screw tr" />
            <span className="concept-exp-chassis-screw bl" />
            <span className="concept-exp-chassis-screw br" />

            <div className="concept-exp-faceplate-grid">
              {/* ── Left Ergonomic Zone: Mechanical Key Matrix & Controls ── */}
              <div className="concept-exp-keys-zone">
                {/* Console Top Rail: Engraved Model + Host Selector */}
                <div className="concept-exp-keys-toprail">
                  <div className="concept-exp-engraving">
                    SYS. 01 // LATTICES MAC-ARBITER
                  </div>

                  <div className="concept-exp-host-pills" role="tablist" aria-label="Host Selection">
                    {FLEET_HOSTS.map((host) => {
                      const isActive = host.id === selectedHostId
                      const hasWarn = host.badge === 'ATTN' && agentDecisionState === 'pending'
                      return (
                        <button
                          key={host.id}
                          type="button"
                          className={`concept-exp-host-pill ${isActive ? 'active' : ''}`}
                          onClick={() => {
                            playButtonPop()
                            setSelectedHostId(host.id)
                            setLastReceipt(`SYS.01 HOST SELECT -> switched target host to ${host.name}`)
                          }}
                        >
                          <span className={`concept-exp-pill-led ${hasWarn ? 'warn' : ''}`} />
                          <span>{host.name.split(' · ')[0].toUpperCase()}</span>
                        </button>
                      )
                    })}
                  </div>
                </div>

                {/* 3×3 Sculpted Mechanical Key Matrix */}
                <div className="concept-exp-keypad-matrix" role="group" aria-label="3x3 Spatial Mechanical Key Matrix">
                  {currentWindows.map((win) => {
                    const isFocused = win.id === activeWindowId
                    const isPressed = activeKeyDepressed === win.id
                    return (
                      <button
                        key={win.id}
                        type="button"
                        className={`concept-exp-mech-key ${win.isOrange ? 'orange' : 'cream'} ${isFocused ? 'focused' : ''} ${isPressed ? 'pressed' : ''}`}
                        onClick={() => handleKeyClick(win)}
                        title={`Focus ${win.app} (${win.role})`}
                      >
                        <div className="concept-exp-key-top">
                          <span className="concept-exp-key-slot">0{win.id} // {win.slot}</span>
                          <span className="concept-exp-key-pip" />
                        </div>

                        <div className="concept-exp-key-center">
                          <div className="concept-exp-key-app">{win.app}</div>
                        </div>

                        <div className="concept-exp-key-bottom">
                          <div className="concept-exp-key-role">
                            {isFocused ? '● FOCUSED' : win.role.split(' ')[0]}
                          </div>
                        </div>
                      </button>
                    )
                  })}
                </div>

                {/* Hardware Auxiliary Controls: Knurled Dial & Toggle Switch */}
                <div className="concept-exp-aux-controls">
                  {/* Knurled Metal Rotary Dial */}
                  <div className="concept-exp-knob-cluster">
                    <div
                      className="concept-exp-knob-dial"
                      style={{ transform: `rotate(${knobAngle}deg)` }}
                      onClick={handleKnobClick}
                      title="Click or turn rotary dial to step windows and cycle layers"
                    />
                    <div className="concept-exp-knob-meta">
                      <span className="concept-exp-knob-label">ROTARY // ENCODER</span>
                      <span className="concept-exp-knob-sub">CLICK TO CYCLE WINDOWS</span>
                    </div>
                  </div>

                  {/* Metal Toggle Switch */}
                  <div className="concept-exp-toggle-cluster">
                    <div className="concept-exp-knob-meta" style={{ textAlign: 'right' }}>
                      <span className="concept-exp-toggle-label">TRANSPORT LINK</span>
                      <span className="concept-exp-knob-sub">{toggleMesh ? 'MESH BONJOUR' : 'USB-C DIRECT'}</span>
                    </div>
                    <div
                      className={`concept-exp-toggle-switch ${toggleMesh ? 'on' : ''}`}
                      onClick={handleToggleClick}
                      title="Toggle between USB-C direct link and Fleet mesh relay"
                    >
                      <span className="concept-exp-toggle-handle" />
                    </div>
                  </div>
                </div>
              </div>

              {/* ── Right Ergonomic Zone: Embedded High-Contrast OLED Screen ── */}
              <div className="concept-exp-screen-zone">
                <div className="concept-exp-oled-screen">
                  {/* Screen Header */}
                  <div className="concept-exp-screen-header">
                    <span className="concept-exp-screen-title">DISP. 01 // REALTIME MAC DESKTOP TOPOLOGY</span>
                    <span className="concept-exp-screen-status">
                      {toggleMesh ? 'MESH 60HZ' : 'DIRECT HID 1000HZ'}
                    </span>
                  </div>

                  {/* 3x3 Spatial Partition Wireframe on Screen */}
                  <div className="concept-exp-spatial-wireframe">
                    {currentWindows.map((win) => {
                      const isFocused = win.id === activeWindowId
                      return (
                        <div
                          key={win.id}
                          className={`concept-exp-wire-cell ${isFocused ? 'active-cell' : ''}`}
                          onClick={() => handleKeyClick(win)}
                        >
                          <span className="concept-exp-wire-slot">0{win.id} {win.slot}</span>
                          <span className="concept-exp-wire-app">{win.app}</span>
                        </div>
                      )
                    })}
                  </div>

                  {/* Agent Attention Module on OLED Screen */}
                  <div className={`concept-exp-screen-attention-box ${agentDecisionState === 'approved' ? 'settled' : ''}`}>
                    <div className={`concept-exp-screen-attn-hdr ${agentDecisionState === 'approved' ? 'settled' : ''}`}>
                      <span className={`concept-exp-led ${agentDecisionState === 'pending' ? 'amber' : 'green'}`} />
                      <span>
                        {agentDecisionState === 'pending'
                          ? 'ATTN: AGENT BLOCKED · HUMAN APPROVAL REQUIRED'
                          : agentDecisionState === 'approved'
                          ? 'DECISION RECORDED · MIGRATION APPLIED'
                          : 'DECISION REJECTED · AGENT PARKED'}
                      </span>
                    </div>

                    <p className="concept-exp-screen-attn-query">
                      {agentDecisionState === 'pending'
                        ? '“Claude Code requested permission to apply SQLite migration and rotate secret session keys in ~/.lattices/sessions.db. Grant schema write?”'
                        : agentDecisionState === 'approved'
                        ? '“Schema write authorized. Claude Code successfully executed database migration and resumed task #8820.”'
                        : '“Action rejected. The agent will not touch ~/.lattices/sessions.db.”'}
                    </p>

                    <div className="concept-exp-screen-attn-actions">
                      {agentDecisionState === 'pending' ? (
                        <>
                          <button
                            type="button"
                            className="concept-exp-screen-btn"
                            onClick={handleApproveAgent}
                          >
                            [KEY A: APPROVE &rarr;]
                          </button>
                          <button
                            type="button"
                            className="concept-exp-screen-btn secondary"
                            onClick={handleRejectAgent}
                          >
                            [KEY B: REJECT]
                          </button>
                        </>
                      ) : (
                        <button
                          type="button"
                          className="concept-exp-screen-btn secondary"
                          onClick={() => {
                            playButtonPop()
                            setAgentDecisionState('pending')
                            setLastReceipt('SYS.01 Reset agent attention fixture to pending')
                          }}
                        >
                          Reset Decision Fixture ↺
                        </button>
                      )}
                    </div>
                  </div>

                  {/* Telemetry Readouts */}
                  <div className="concept-exp-telemetry-grid">
                    <div className="concept-exp-screen-readout">
                      <span className="concept-exp-screen-readout-lbl">Active Window</span>
                      <span className="concept-exp-screen-readout-val">{activeWindow.app}</span>
                    </div>

                    <div className="concept-exp-screen-readout">
                      <span className="concept-exp-screen-readout-lbl">Topology Slot</span>
                      <span className="concept-exp-screen-readout-val">0{activeWindow.id} // {activeWindow.slot}</span>
                    </div>

                    <div className="concept-exp-screen-readout">
                      <span className="concept-exp-screen-readout-lbl">Attached PID</span>
                      <span className="concept-exp-screen-readout-val">{activeWindow.pid}</span>
                    </div>

                    <div className="concept-exp-screen-readout">
                      <span className="concept-exp-screen-readout-lbl">Bounds</span>
                      <span className="concept-exp-screen-readout-val">{activeWindow.bounds}</span>
                    </div>

                    <div className="concept-exp-screen-readout">
                      <span className="concept-exp-screen-readout-lbl">Target Host</span>
                      <span className="concept-exp-screen-readout-val">{activeHost.name}</span>
                    </div>

                    <div className="concept-exp-screen-readout">
                      <span className="concept-exp-screen-readout-lbl">HID Latency</span>
                      <span className="concept-exp-screen-readout-val">1.8 ms</span>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            {/* Bottom Hardware Execution Receipt */}
            <div className="concept-exp-console-receipt">
              <span className="concept-exp-receipt-led" />
              <span>{lastReceipt}</span>
            </div>
          </div>
        </section>

        {/* 3 Design Modules (Dieter Rams Spec Sheet Style) */}
        <section className="concept-exp-modules-section">
          <div className="concept-exp-section-header">
            <h2 className="concept-exp-section-title">Principles of the Physical Console</h2>
            <span className="concept-exp-section-num">SECT. 02 // THREE PILLARS</span>
          </div>

          <div className="concept-exp-modules-grid">
            <div className="concept-exp-module-card">
              <span className="concept-exp-module-num">01 / TACTILE RESISTANCE</span>
              <h3 className="concept-exp-module-heading">Mechanical Muscle Memory</h3>
              <p className="concept-exp-module-body">
                Screen-based hotkeys require cognitive recall. SYS. 01 uses low-profile mechanical switches
                with 45gf linear resistance and sculpted PBT keycaps. Your hand learns the physical 3×3
                grid without glancing down, recalling windows like chords on an instrument.
              </p>
              <div className="concept-exp-code-snippet">
                SWITCHES: Custom Kailh Choc V2 (45gf)<br />
                KEYCAPS: Double-Shot PBT (Terracotta / Cream)<br />
                TRAVEL: 3.2mm full travel · 1.2mm actuation
              </div>
            </div>

            <div className="concept-exp-module-card">
              <span className="concept-exp-module-num">02 / SPATIAL DUALITY</span>
              <h3 className="concept-exp-module-heading">1:1 Screen-to-Key Mapping</h3>
              <p className="concept-exp-module-body">
                The 3×3 physical matrix corresponds directly to your primary display&rsquo;s normalized coordinate grid.
                The terracotta &ldquo;L&rdquo; anchors the primary coding quadrant, while surrounding keys focus auxiliary
                terminals, headless browser surfaces, and build pipelines without hunting through window alt-tab stacks.
              </p>
              <div className="concept-exp-code-snippet">
                GEOMETRY: 3×3 Normalized Matrix<br />
                SIGNATURE: 5-Key Terracotta &ldquo;L&rdquo;<br />
                FEEDBACK: Zero-latency hardware window focus
              </div>
            </div>

            <div className="concept-exp-module-card">
              <span className="concept-exp-module-num">03 / ATTENTION AT ARM&rsquo;S LENGTH</span>
              <h3 className="concept-exp-module-heading">Zero-Intrusion Agent Supervision</h3>
              <p className="concept-exp-module-body">
                When background autonomous agents hit critical checkpoints or require schema permissions,
                they don&rsquo;t steal cursor focus or pop dialogs on your Mac. The embedded OLED softly illuminates,
                allowing you to approve or hold with dedicated physical hardware buttons at arm&rsquo;s length.
              </p>
              <div className="concept-exp-code-snippet">
                PROTOCOL: Local Ed25519 Link<br />
                ATTENTION: Pulsing Amber Jewel Diode<br />
                INPUT: Physical [KEY A: APPROVE] / [KEY B: REJECT]
              </div>
            </div>
          </div>
        </section>

        {/* Archival Poster Artifact Showcase */}
        <section className="concept-exp-poster-banner">
          <div className="concept-exp-poster-thumb-wrapper">
            <img
              src="/lattices-poster-sys01.png"
              alt="Archival Print: Lattices SYS. 01 Workspace Controller Poster"
              width="1024"
              height="1536"
              className="concept-exp-poster-thumb-img"
            />
          </div>

          <div className="concept-exp-poster-copy">
            <div className="concept-exp-kicker">Archival Exhibition Edition</div>
            <h3>SYS. 01 Workspace Controller Poster</h3>
            <p>
              The original advertising study for the physical Lattices hardware console.
              Rendered in the visual tradition of Swiss graphic design, Dieter Rams&rsquo; functional minimalism,
              and Teenage Engineering&rsquo;s tactile craft. Features the true 3×3 mechanical matrix,
              knurled rotary dial, and embedded telemetry screen.
            </p>
            <div className="concept-exp-poster-links">
              <a
                href="/lattices-poster-sys01.png"
                download="lattices-poster-sys01.png"
                className="concept-exp-btn-primary"
              >
                Download Archival Poster (High-Res) ↓
              </a>
              <a
                href="/lattices-poster-sys01.png"
                target="_blank"
                rel="noreferrer"
                className="concept-exp-btn-secondary"
              >
                Inspect Artwork in Fullscreen →
              </a>
            </div>
          </div>
        </section>

        {/* Technical Specification Ledger Table */}
        <section className="concept-exp-spec-table-wrap">
          <div className="concept-exp-spec-header">
            <span className="concept-exp-spec-header-title">Technical Ledger // SYS. 01 Hardware Specification</span>
            <span className="concept-exp-unit-serial">SPEC-DOC // SYS01-REV3</span>
          </div>
          <table className="concept-exp-spec-table">
            <tbody>
              <tr>
                <td className="col-prop">Chassis &amp; Materials</td>
                <td className="col-val">CNC Milled 6061-T6 Aluminum with bead-blasted surface finish · Archival Cream / Anodized Noir</td>
              </tr>
              <tr>
                <td className="col-prop">Key Matrix</td>
                <td className="col-val">3×3 (9-key) physical matrix with custom PBT double-shot dye-sublimated sculpted keycaps</td>
              </tr>
              <tr>
                <td className="col-prop">Key Switches</td>
                <td className="col-val">Kailh Choc V2 Low-Profile Linear Switches (45gf actuation, 3.2mm travel, hot-swappable sockets)</td>
              </tr>
              <tr>
                <td className="col-prop">Rotary Encoder</td>
                <td className="col-val">Machined aluminum knurled dial with 24-step mechanical detents and push-button actuation</td>
              </tr>
              <tr>
                <td className="col-prop">Embedded Display</td>
                <td className="col-val">4.2-inch Monochrome High-Contrast OLED (400×240 resolution, 60Hz refresh, matte anti-glare glass)</td>
              </tr>
              <tr>
                <td className="col-prop">Connectivity &amp; Power</td>
                <td className="col-val">USB-C Direct HID (1000Hz polling, &lt; 1.8ms latency) + Bluetooth LE 5.3 Mesh · Internal 1200mAh LiPo</td>
              </tr>
              <tr>
                <td className="col-prop">Dimensions &amp; Weight</td>
                <td className="col-val">180 mm (W) × 140 mm (D) × 22 mm (H) · 480 g solid desktop mass with silicone anti-slip feet</td>
              </tr>
              <tr>
                <td className="col-prop">Host Security</td>
                <td className="col-val">Ed25519 local cryptographic pairing · Hardware SHA-256 fingerprint verification on Mac</td>
              </tr>
            </tbody>
          </table>
        </section>

        {/* Colophon & Manifest Footer */}
        <footer className="concept-exp-footer">
          <div className="concept-exp-colophon-quote">
            &ldquo;Good design is unobtrusive. Products fulfilling a purpose are like tools. They are neither decorative objects nor works of art. Their design should therefore be both neutral and restrained, to leave room for the user’s self-expression.&rdquo;
            <br />
            — Dieter Rams, Ten Principles for Good Design
          </div>

          <div className="concept-exp-footer-meta">
            <strong>LATTICES // SYS. 01 CONSOLE</strong>
            <span>PHYSICAL WORKSPACE ARBITER FOR MACOS</span>
            <span>PRODUCED IN SAN FRANCISCO &bull; ARCHIVAL PRINTING</span>
          </div>
        </footer>
      </div>
    </div>
  )
}
