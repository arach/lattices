#!/usr/bin/env node
/**
 * Generate SVG from Arc diagram definition.
 * Usage: node diagrams/generate-svg.mjs
 */
import { readFileSync, writeFileSync } from 'fs'
import { dirname, join } from 'path'
import { fileURLToPath } from 'url'

const __dirname = dirname(fileURLToPath(import.meta.url))

// Inline the needed constants and functions from @arach/arc
const NODE_SIZES = {
  xs: { width: 80, height: 36 },
  s: { width: 95, height: 42 },
  m: { width: 145, height: 68 },
  l: { width: 210, height: 85 },
}

const nodeColors = {
  violet: { bg: '#8b5cf6', text: '#ffffff' },
  emerald: { bg: '#34d399', text: '#ffffff' },
  blue: { bg: '#60a5fa', text: '#ffffff' },
  amber: { bg: '#fbbf24', text: '#1f2937' },
  zinc: { bg: '#71717a', text: '#ffffff' },
  sky: { bg: '#38bdf8', text: '#ffffff' },
  rose: { bg: '#f43f5e', text: '#ffffff' },
  orange: { bg: '#fb923c', text: '#ffffff' },
}

function escapeXml(str) {
  if (!str) return ''
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')
}

function getAnchorPosition(x, y, width, height, position) {
  switch (position) {
    case 'left':        return { x: x, y: y + height / 2 }
    case 'right':       return { x: x + width, y: y + height / 2 }
    case 'top':         return { x: x + width / 2, y: y }
    case 'bottom':      return { x: x + width / 2, y: y + height }
    case 'bottomRight': return { x: x + width, y: y + height - 15 }
    case 'bottomLeft':  return { x: x, y: y + height - 15 }
    case 'topRight':    return { x: x + width, y: y + 15 }
    case 'topLeft':     return { x: x, y: y + 15 }
    default:            return { x: x + width / 2, y: y + height / 2 }
  }
}

function getConnectorPath(from, to, fromAnchor, toAnchor) {
  const dx = to.x - from.x
  const dy = to.y - from.y
  let cp1x = from.x, cp1y = from.y, cp2x = to.x, cp2y = to.y
  const offset = Math.min(Math.abs(dx), Math.abs(dy), 50)

  if (['right', 'bottomRight', 'topRight'].includes(fromAnchor)) cp1x = from.x + offset
  else if (['left', 'bottomLeft', 'topLeft'].includes(fromAnchor)) cp1x = from.x - offset
  else if (fromAnchor === 'bottom') cp1y = from.y + offset
  else if (fromAnchor === 'top') cp1y = from.y - offset

  if (['left', 'bottomLeft', 'topLeft'].includes(toAnchor)) cp2x = to.x - offset
  else if (['right', 'bottomRight', 'topRight'].includes(toAnchor)) cp2x = to.x + offset
  else if (toAnchor === 'top') cp2y = to.y - offset
  else if (toAnchor === 'bottom') cp2y = to.y + offset

  return `M ${from.x} ${from.y} C ${cp1x} ${cp1y}, ${cp2x} ${cp2y}, ${to.x} ${to.y}`
}

function generateSVG(diagram, options = {}) {
  const { backgroundColor = 'transparent', padding = 20 } = options
  const bounds = { x: 0, y: 0, width: diagram.layout.width, height: diagram.layout.height }
  const viewBox = `${bounds.x - padding} ${bounds.y - padding} ${bounds.width + padding * 2} ${bounds.height + padding * 2}`
  const svgWidth = bounds.width + padding * 2
  const svgHeight = bounds.height + padding * 2

  let svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${svgWidth}" height="${svgHeight}" viewBox="${viewBox}">\n`

  if (backgroundColor !== 'transparent') {
    svg += `  <rect x="${bounds.x - padding}" y="${bounds.y - padding}" width="${svgWidth}" height="${svgHeight}" fill="${backgroundColor}"/>\n`
  }

  // Connectors
  for (const connector of diagram.connectors) {
    const fromNode = diagram.nodes[connector.from]
    const toNode = diagram.nodes[connector.to]
    if (!fromNode || !toNode) continue

    const fromSize = NODE_SIZES[fromNode.size] || NODE_SIZES.m
    const toSize = NODE_SIZES[toNode.size] || NODE_SIZES.m
    const style = diagram.connectorStyles?.[connector.style] || { color: 'zinc', strokeWidth: 2 }
    const strokeColor = nodeColors[style.color]?.bg || '#71717a'

    const fromPos = getAnchorPosition(fromNode.x, fromNode.y, fromSize.width, fromSize.height, connector.fromAnchor)
    const toPos = getAnchorPosition(toNode.x, toNode.y, toSize.width, toSize.height, connector.toAnchor)
    const path = getConnectorPath(fromPos, toPos, connector.fromAnchor, connector.toAnchor)

    svg += `  <path d="${path}" fill="none" stroke="${strokeColor}" stroke-width="${style.strokeWidth || 2}"${style.dashed ? ' stroke-dasharray="6 3"' : ''} opacity="0.7"/>\n`
    svg += `  <circle cx="${toPos.x}" cy="${toPos.y}" r="3.5" fill="${strokeColor}" opacity="0.7"/>\n`

    if (style.label) {
      const midX = (fromPos.x + toPos.x) / 2
      const midY = (fromPos.y + toPos.y) / 2
      svg += `  <text x="${midX}" y="${midY - 8}" text-anchor="middle" fill="${strokeColor}" font-size="10" font-family="ui-sans-serif, system-ui, sans-serif" opacity="0.8">${escapeXml(style.label)}</text>\n`
    }
  }

  // Nodes
  for (const [nodeId, node] of Object.entries(diagram.nodes)) {
    const data = diagram.nodeData[nodeId]
    if (!data) continue

    const size = NODE_SIZES[node.size] || NODE_SIZES.m
    const width = size.width
    const height = size.height
    const colors = nodeColors[data.color] || nodeColors.zinc

    svg += `  <rect x="${node.x}" y="${node.y}" width="${width}" height="${height}" rx="12" fill="${colors.bg}"/>\n`

    const fontSize = node.size === 'xs' ? 10 : node.size === 's' ? 11 : 13
    const nameY = data.subtitle ? node.y + height / 2 : node.y + height / 2 + fontSize / 3
    svg += `  <text x="${node.x + width / 2}" y="${nameY}" text-anchor="middle" fill="${colors.text}" font-size="${fontSize}" font-weight="600" font-family="ui-sans-serif, system-ui, sans-serif">${escapeXml(data.name)}</text>\n`

    if (data.subtitle && height >= 60) {
      svg += `  <text x="${node.x + width / 2}" y="${nameY + fontSize + 4}" text-anchor="middle" fill="${colors.text}" opacity="0.75" font-size="${fontSize - 2}" font-family="ui-sans-serif, system-ui, sans-serif">${escapeXml(data.subtitle)}</text>\n`
    }
  }

  svg += `</svg>`
  return svg
}

// Load and generate
const diagram = (await import('./architecture.diagram.js')).default
const svg = generateSVG(diagram)
const outPath = join(__dirname, '..', 'public', 'architecture.svg')
writeFileSync(outPath, svg)
console.log(`Generated ${outPath}`)
