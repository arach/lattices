// Read-only end-to-end burst: a test instance, never the everyday :9399 host.
// Run on each revision: bun packages/host-linux/scripts/benchmark.ts [port]
import { capabilities, refreshCapabilities, registerEndpoints } from "../src/endpoints.ts";
import { Router } from "../src/router.ts";
import { serve } from "../src/server.ts";

const port = Number(process.argv[2] ?? 19499);
if (port === 9399) throw new Error("Refusing to benchmark the everyday host port");
await refreshCapabilities();
const router = new Router(() => capabilities);
registerEndpoints(router, { bindHost: "127.0.0.1", startedAt: Date.now(), clientCount: () => 1 });
const server = serve({ hosts: ["127.0.0.1"], port, policy: { allowUsers: [], allowTags: [] }, router, pairing: null, log: () => {} });
const ws = new WebSocket(`ws://127.0.0.1:${port}`);
const waiting = new Map<string, { resolve: () => void; reject: (err: Error) => void }>();
ws.onmessage = ({ data }) => {
  const reply = JSON.parse(String(data));
  const task = waiting.get(reply.id);
  if (!task) return;
  waiting.delete(reply.id);
  if (reply.error) task.reject(new Error(reply.error));
  else task.resolve();
};
let id = 0;
function call() {
  const key = String(++id);
  return new Promise<void>((resolve, reject) => {
    waiting.set(key, { resolve, reject });
    ws.send(JSON.stringify({ id: key, method: "windows.list" }));
  });
}
try {
  await new Promise<void>((resolve, reject) => { ws.onopen = () => resolve(); ws.onerror = () => reject(new Error("WebSocket failed")); });
  for (let i = 0; i < 10; i++) await call();
  const results: Record<string, unknown>[] = [];
  for (const concurrency of [1, 2]) {
    const samples: number[] = [];
    for (let round = 0; round < 5; round++) {
      const start = performance.now();
      for (let i = 0; i < 100; i += concurrency) await Promise.all(Array.from({ length: concurrency }, call));
      samples.push(performance.now() - start);
    }
    results.push({ method: "windows.list", calls: 100, queriesPerCall: 4, concurrency, rounds: 5, samplesMs: samples.map((n) => Number(n.toFixed(2))), medianMs: Number([...samples].sort((a,b) => a-b)[2].toFixed(2)) });
  }
  console.log(JSON.stringify({ bun: Bun.version, port, results }, null, 2));
} finally {
  ws.close();
  server.stop();
}
