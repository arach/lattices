import { afterAll, beforeAll, expect, test } from "bun:test";
import { configuredHosts, parseHostSpec, resolveHost } from "../../../hosts.ts";
import { callHostTool } from "./index.ts";

test("host specs: name, name:port, name=address:port", () => {
  expect(parseHostSpec("archie", "env")).toEqual({ name: "archie", address: "archie", port: 9399, source: "env" });
  expect(parseHostSpec("archie:9400", "env")).toMatchObject({ name: "archie", address: "archie", port: 9400 });
  expect(parseHostSpec("box=100.1.2.3:9500", "env")).toMatchObject({ name: "box", address: "100.1.2.3", port: 9500 });
  expect(parseHostSpec("  ", "env")).toBeNull();
});

test("hosts come from the local daemon, the config file, then LATTICES_HOSTS", () => {
  const hosts = configuredHosts(
    { LATTICES_HOSTS: "studio:9401", LATTICES_DAEMON_HOST: "127.0.0.1" },
    () => JSON.stringify({ hosts: { archie: { address: "100.119.71.19" } } })
  );
  expect(hosts.map((h) => [h.name, h.address, h.port, h.source])).toEqual([
    ["local", "127.0.0.1", 9399, "local"],
    ["archie", "100.119.71.19", 9399, "config"],
    ["studio", "studio", 9401, "env"],
  ]);
  expect(resolveHost("archie", hosts).address).toBe("100.119.71.19");
  expect(resolveHost(undefined, hosts).name).toBe("local");
  expect(resolveHost("10.0.0.5:9500", hosts)).toMatchObject({ address: "10.0.0.5", port: 9500 });
});

// A fake lattices host for the tool calls.
const calls: { method: string; params: Record<string, unknown> }[] = [];
let server: ReturnType<typeof Bun.serve>;
let host: string;

beforeAll(() => {
  server = Bun.serve({
    port: 0,
    hostname: "127.0.0.1",
    fetch: (req, srv) => (srv.upgrade(req, { data: undefined }) ? undefined : new Response("no")),
    websocket: {
      message(ws, raw) {
        const { id, method, params } = JSON.parse(String(raw));
        calls.push({ method, params });
        const results: Record<string, unknown> = {
          "host.describe": { platform: "linux", capabilities: ["capture.still", "input.pointer"] },
          "windows.list": [{ wid: 7, app: "foot" }],
          "windows.search": [{ wid: 7, app: "foot", matchSource: "app" }],
          "capture.still": { data: Buffer.from("jpeg").toString("base64"), width: 640, height: 268 },
          "ocr.find": { matches: [{ text: "Save", point: { x: 5, y: 6 } }] },
          "computer.click": { ok: true, status: "executed" },
          "windows.place": { ok: true, frame: { x: 0, y: 24, w: 1720, h: 1416 } },
        };
        ws.send(JSON.stringify(method in results ? { id, result: results[method], error: null } : { id, result: null, error: `Unknown method: ${method}` }));
      },
    },
  });
  host = `127.0.0.1:${server.port}`;
});

afterAll(() => server.stop(true));

const last = (method: string) => [...calls].reverse().find((c) => c.method === method)?.params;

test("host tools address the named host", async () => {
  const described = await callHostTool("host_describe", { host });
  expect(described.structuredContent).toMatchObject({ platform: "linux" });

  await callHostTool("host_windows", { host, query: "foot" });
  expect(last("windows.search")).toEqual({ query: "foot" });

  const shot = await callHostTool("host_screenshot", { host, wid: 7 });
  expect(shot.content[0]).toEqual({ type: "image", data: Buffer.from("jpeg").toString("base64"), mimeType: "image/jpeg" });
  expect(last("capture.still")).toEqual({ wid: 7, maxWidth: 1280 });

  await callHostTool("host_read", { host, wid: 7, find: "Save" });
  expect(last("ocr.find")).toEqual({ text: "Save", wid: 7 });

  await callHostTool("host_place", { host, app: "foot", placement: "left" });
  expect(last("windows.place")).toEqual({ app: "foot", placement: "left" });
});

test("host_act executes, keeping only the fields its action uses", async () => {
  await callHostTool("host_act", { host, action: "click", x: 5, y: 6, text: "ignored" });
  expect(last("computer.click")).toEqual({ x: 5, y: 6, treatment: "execute" });
  await expect(callHostTool("host_act", { host, action: "teleport" })).rejects.toThrow("Unknown action");
});

test("host errors surface as tool errors through the toolset", async () => {
  const { hostsToolset } = await import("./index.ts");
  const result = await hostsToolset.callTool("host_call", { host, method: "nope.nothing" });
  expect(result.isError).toBe(true);
  expect(result.content[0]).toMatchObject({ text: "Unknown method: nope.nothing" });
});
