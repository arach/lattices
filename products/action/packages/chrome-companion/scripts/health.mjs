#!/usr/bin/env bun

const bridgeURL = process.env.ACTION_CHROME_COMPANION_BRIDGE_URL || "http://127.0.0.1:4321";

try {
  const response = await fetch(`${bridgeURL}/health`);
  const health = await response.json();
  console.log(JSON.stringify(health, null, 2));
  process.exit(health.connected ? 0 : 1);
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
}
