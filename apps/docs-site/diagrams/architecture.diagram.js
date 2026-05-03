/** @type {import('@arach/arc').ArcDiagramData} */
const diagram = {
  layout: { width: 720, height: 340 },
  nodes: {
    agents:  { x: 255, y: 20,  size: 'l' },
    app:     { x: 255, y: 130, size: 'l' },
    cli:     { x: 255, y: 240, size: 'l' },
    tmux:    { x: 510, y: 240, size: 'm' },
    ocr:     { x: 510, y: 130, size: 'm' },
    daemon:  { x: 30,  y: 130, size: 'm' },
  },
  nodeData: {
    agents:  { icon: 'Bot',      name: 'AI Agents / Scripts',  subtitle: 'Daemon API consumers',     color: 'violet' },
    app:     { icon: 'Monitor',  name: 'Menu Bar App',         subtitle: 'Swift / AppKit',           color: 'blue' },
    cli:     { icon: 'Terminal', name: 'CLI',                  subtitle: 'Node.js',                  color: 'emerald' },
    tmux:    { icon: 'Columns',  name: 'tmux',                 subtitle: 'optional',                 color: 'zinc' },
    ocr:     { icon: 'Eye',      name: 'OCR Engine',           subtitle: 'Vision + FTS5',            color: 'amber' },
    daemon:  { icon: 'Radio',    name: 'Daemon',               subtitle: 'WebSocket :9399',          color: 'sky' },
  },
  connectors: [
    { from: 'agents', to: 'daemon',  fromAnchor: 'left',   toAnchor: 'top',    style: 'api' },
    { from: 'app',    to: 'daemon',  fromAnchor: 'left',   toAnchor: 'right',  style: 'runs' },
    { from: 'app',    to: 'ocr',     fromAnchor: 'right',  toAnchor: 'left',   style: 'reads' },
    { from: 'app',    to: 'cli',     fromAnchor: 'bottom',  toAnchor: 'top',   style: 'calls' },
    { from: 'cli',    to: 'tmux',    fromAnchor: 'right',  toAnchor: 'left',   style: 'optional' },
  ],
  connectorStyles: {
    api:      { color: 'violet',  strokeWidth: 2, label: '30 RPC methods' },
    runs:     { color: 'sky',     strokeWidth: 2, label: 'runs' },
    reads:    { color: 'amber',   strokeWidth: 2, label: 'Vision scans' },
    calls:    { color: 'emerald', strokeWidth: 2, label: 'calls' },
    optional: { color: 'zinc',    strokeWidth: 2, label: 'optional', dashed: true },
  },
}

export default diagram
