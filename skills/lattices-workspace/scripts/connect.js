#!/usr/bin/env node

// Quick connection test for the Lattices daemon.
// Run: node scripts/connect.js
//
// Verifies the daemon is reachable and prints workspace status.

import { daemonCall, isDaemonRunning } from '@lattices/cli'

async function main() {
  if (!(await isDaemonRunning())) {
    console.error('Lattices daemon is not running.')
    console.error('Start it with: lattices app')
    process.exit(1)
  }

  const status = await daemonCall('daemon.status')
  console.log(`Daemon up for ${Math.round(status.uptime)}s`)
  console.log(`  Windows: ${status.windowCount}`)
  console.log(`  Sessions: ${status.tmuxSessionCount}`)
  console.log(`  Clients: ${status.clientCount}`)

  const projects = await daemonCall('projects.list')
  const running = projects.filter(p => p.isRunning)
  console.log(`\nProjects: ${projects.length} discovered, ${running.length} running`)

  for (const p of running) {
    console.log(`  ${p.name} (${p.paneCount} panes) — ${p.path}`)
  }

  const { layers, activeIndex } = await daemonCall('session.layers.list')
  if (layers.length > 0) {
    console.log(`\nSession layers: ${layers.length}`)
    for (let i = 0; i < layers.length; i++) {
      const marker = i === activeIndex ? ' *' : ''
      console.log(`  ${layers[i].name} (${layers[i].windows.length} windows)${marker}`)
    }
  }
}

main().catch(err => {
  console.error('Error:', err.message)
  process.exit(1)
})
