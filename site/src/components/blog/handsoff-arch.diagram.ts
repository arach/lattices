import type { ArcDiagramData } from '@arach/arc'

const diagram: ArcDiagramData = {
  id: 'HANDSOFF.ARCH.001',
  layout: { width: 900, height: 380 },

  nodes: {
    talkie:   { x: 40,  y: 50,  size: 'm' },
    swift:    { x: 40,  y: 180, size: 'l' },
    worker:   { x: 320, y: 150, size: 'l' },
    prompt:   { x: 320, y: 290, size: 's' },
    cache:    { x: 320, y: 50,  size: 's' },
    groq:     { x: 600, y: 50,  size: 'm' },
    xai:      { x: 600, y: 170, size: 'm' },
    openai:   { x: 600, y: 290, size: 'm' },
    ffplay:   { x: 790, y: 290, size: 's' },
  },

  nodeData: {
    talkie:   { icon: 'Mic',       name: 'Talkie',      subtitle: 'Push-to-talk',     description: 'Voice capture + STT', color: 'violet' },
    swift:    { icon: 'Monitor',   name: 'Swift App',   subtitle: 'Menu bar + AX',    description: 'Desktop control',     color: 'amber' },
    worker:   { icon: 'Terminal',  name: 'Bun Worker',  subtitle: 'stdin/stdout',      description: 'Inference + TTS',     color: 'emerald' },
    prompt:   { icon: 'FileText',  name: 'System Prompt', subtitle: 'Hot-reload .md',                                     color: 'amber' },
    cache:    { icon: 'HardDrive', name: 'TTS Cache',   subtitle: '~/.lattices/',                                          color: 'emerald' },
    groq:     { icon: 'Zap',       name: 'Groq',        subtitle: 'Llama 3.3 70B',    description: '~600ms',              color: 'blue' },
    xai:      { icon: 'Brain',     name: 'xAI',         subtitle: 'Grok',             description: '~1.2s',               color: 'blue' },
    openai:   { icon: 'Volume2',   name: 'OpenAI',      subtitle: 'TTS-1',            description: 'Streaming PCM',       color: 'blue' },
    ffplay:   { icon: 'Play',      name: 'ffplay',      subtitle: 'PCM audio',                                             color: 'sky' },
  },

  connectors: [
    { from: 'talkie', to: 'swift',   fromAnchor: 'bottom',     toAnchor: 'top',   style: 'ws' },
    { from: 'swift',  to: 'worker',  fromAnchor: 'right',      toAnchor: 'left',  style: 'json' },
    { from: 'worker', to: 'swift',   fromAnchor: 'bottomLeft', toAnchor: 'bottomRight', style: 'actions' },
    { from: 'worker', to: 'groq',    fromAnchor: 'right',      toAnchor: 'left',  style: 'inference' },
    { from: 'worker', to: 'xai',     fromAnchor: 'right',      toAnchor: 'left',  style: 'inference' },
    { from: 'worker', to: 'openai',  fromAnchor: 'right',      toAnchor: 'left',  style: 'tts' },
    { from: 'openai', to: 'ffplay',  fromAnchor: 'right',      toAnchor: 'left',  style: 'pcm' },
    { from: 'prompt', to: 'worker',  fromAnchor: 'top',        toAnchor: 'bottom', style: 'config' },
    { from: 'worker', to: 'cache',   fromAnchor: 'top',        toAnchor: 'bottom', style: 'cached' },
  ],

  connectorStyles: {
    ws:        { color: 'violet',  strokeWidth: 2, label: 'WebSocket' },
    json:      { color: 'emerald', strokeWidth: 2, label: 'JSON lines' },
    actions:   { color: 'amber',   strokeWidth: 2, label: 'actions', dashed: true },
    inference: { color: 'blue',    strokeWidth: 2, dashed: true },
    tts:       { color: 'blue',    strokeWidth: 2, label: 'TTS stream' },
    pcm:       { color: 'sky',     strokeWidth: 2, label: 'PCM pipe' },
    config:    { color: 'amber',   strokeWidth: 1, dashed: true },
    cached:    { color: 'emerald', strokeWidth: 1, dashed: true, label: 'cached audio' },
  },
}

export default diagram
