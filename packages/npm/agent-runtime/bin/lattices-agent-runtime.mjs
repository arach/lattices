#!/usr/bin/env node
import * as runtime from '../index.mjs';

const command = process.argv[2] ?? 'doctor';

switch (command) {
  case 'doctor':
    doctor();
    break;
  default:
    console.error(`Unsupported command: ${command}`);
    console.error('Usage: lattices-agent-runtime doctor');
    process.exit(64);
}

function doctor() {
  const adapters = [
    ['codex', runtime.createCodexAdapter],
    ['claude-code', runtime.createClaudeCodeAdapter],
    ['opencode', runtime.createOpencodeAdapter],
    ['pi', runtime.createPiAdapter],
    ['echo', runtime.createEchoAdapter],
  ];
  const missing = adapters
    .filter(([, factory]) => typeof factory !== 'function')
    .map(([name]) => name);

  if (typeof runtime.SessionRegistry !== 'function' || missing.length > 0) {
    console.error('Lattices Agent Runtime is installed, but required adapters are missing.');
    if (missing.length > 0) {
      console.error(`Missing adapters: ${missing.join(', ')}`);
    }
    process.exit(1);
  }

  console.log('Lattices Agent Runtime ready.');
  console.log(`Adapters: ${adapters.map(([name]) => name).join(', ')}`);
}
