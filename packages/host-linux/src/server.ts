import type { ServerWebSocket } from "bun";
import { identify, type Identity, type Policy } from "./auth.ts";
import type { Request, Router } from "./router.ts";

interface Conn {
  identity: Identity;
}

export interface ServeOptions {
  hosts: string[];
  port: number;
  policy: Policy;
  router: Router;
  log: (line: string) => void;
}

export function serve({ hosts, port, policy, router, log }: ServeOptions) {
  const sockets = new Set<ServerWebSocket<Conn>>();

  const servers = hosts.map((hostname) =>
    Bun.serve<Conn, never>({
      hostname,
      port,
      async fetch(req, server) {
        const address = server.requestIP(req)?.address ?? "";
        const identity = await identify(address, policy);
        if (!identity) {
          log(`denied ${address}`);
          return new Response("forbidden: not an allowed tailnet identity\n", { status: 403 });
        }
        if (server.upgrade(req, { data: { identity } })) return undefined;
        // Plain HTTP GET / answers a health check, like the companion bridge.
        return Response.json({ ok: true, service: "lattices-host", websocket: `ws://${hostname}:${port}` });
      },
      websocket: {
        // Recordings and captures come back as base64; leave room for them.
        maxPayloadLength: 64 * 1024 * 1024,
        open(ws) {
          sockets.add(ws);
          ws.subscribe("events");
          const { user, node } = ws.data.identity;
          log(`connected ${user}@${node}`);
        },
        close(ws) {
          sockets.delete(ws);
        },
        async message(ws, raw) {
          let request: Request;
          try {
            request = JSON.parse(String(raw));
            if (typeof request.method !== "string") throw new Error("missing method");
          } catch {
            ws.send(JSON.stringify({ id: "?", result: null, error: "Invalid request JSON" }));
            return;
          }
          const response = await router.handle({ ...request, id: String(request.id ?? "?") });
          if (response.error) log(`${request.method} -> ${response.error}`);
          ws.send(JSON.stringify(response));
        },
      },
    })
  );

  return {
    clientCount: () => sockets.size,
    broadcast(event: string, data: unknown) {
      const frame = JSON.stringify({ event, data });
      for (const server of servers) server.publish("events", frame);
    },
    stop() {
      for (const server of servers) server.stop(true);
    },
  };
}
