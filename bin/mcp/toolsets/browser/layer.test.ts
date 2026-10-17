import { expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { mkdtemp, mkdir, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { HeadedBrowserLayer, browserWorkspace, readBrowserCapabilities, requireBrowserSafety, requireBrowserWorkspace } from "./layer.ts";
import { withDeadline } from "./transport.ts";
const runtimeURL = new URL("../../../../products/action/packages/runtime/src/agent-layer.ts", import.meta.url);
const { AgentLayerDirector, agentWorkspaceSerial } = await import(runtimeURL.href);
const acceptanceURL = new URL("../../../../products/action/packages/runtime/src/layer-acceptance.ts", import.meta.url);
const { layerAcceptance } = await import(acceptanceURL.href);

test("browser safety requires matching host evidence and rejects changed or expired evidence", async () => {
  const root = await mkdtemp(join(tmpdir(), "browser-safety-test-"));
  const path = join(root, "acceptance.json");
  const evidence = join(root, "evidence.json");
  const now = Date.parse("2026-10-15T12:00:00Z");
  const digest = (value: string) => createHash("sha256").update(value).digest("hex");
  const binding = { executableSha256: digest("app"), nativeSourceDigest: digest("native"), orchestrationSourceDigest: digest("runtime"), hostFingerprint: digest("host"), osBuild: "test-os", displayConfigurationDigest: digest("displays") };
  const base = {
    runtimeParity: { state: "matched-source-digest" },
    native: { privateLayer: "declared-by-build", manifest: { features: { persistentAgentDisplay: true, namedWorkspaces: true } } },
    safety: { privateLayer: { blocked: false } },
  };
  const check = (currentBinding = binding, at = now) => requireBrowserSafety({ ...base, acceptance: { privateLayer: layerAcceptance(currentBinding, { path, now: at }) } });
  try {
    expect(() => check()).toThrow("acceptance is missing");
    await writeFile(evidence, "fixture evidence");
    await writeFile(path, JSON.stringify({
      schemaVersion: 1, outcome: "passed", acceptedAt: new Date(now - 1000).toISOString(), expiresAt: new Date(now + 1000).toISOString(), reviewer: "unit-test", binding,
      checks: Object.fromEntries(["physicalDisplayMode", "scale", "arrangement", "frontmostApp", "pointer", "unrelatedWindowFrames"].map(key => [key, "unchanged-throughout"])),
      phases: ["open", "interaction", "close"], evidence: [{ path: evidence, sha256: digest("fixture evidence") }],
    }));
    expect(() => check()).not.toThrow();
    expect(() => check(binding, now + 1001)).toThrow("expired");
    for (const key of Object.keys(binding) as (keyof typeof binding)[]) {
      expect(() => check({ ...binding, [key]: key === "osBuild" ? "other-os" : digest("other") })).toThrow(`binding changed: ${key}`);
    }
    const accepted = { ...base, acceptance: { privateLayer: layerAcceptance(binding, { path, now }) } };
    expect(() => requireBrowserSafety({ ...accepted, safety: { privateLayer: { blocked: true, reason: "quarantined host" } } })).toThrow("quarantined host");
    expect(() => requireBrowserSafety({ ...accepted, runtimeParity: { state: "source-digest-mismatch" } })).toThrow("matched app/runtime");
    expect(() => requireBrowserSafety({ ...accepted, native: { ...base.native, manifest: { features: { persistentAgentDisplay: true, namedWorkspaces: false } } } })).toThrow("persistent named workspaces");
    expect(() => requireBrowserSafety({ ...accepted, acceptance: { privateLayer: layerAcceptance(binding, { path, now, contextError: "native context unavailable" }) } })).toThrow("unverified");
    await writeFile(evidence, "changed fixture");
    expect(() => check()).toThrow("evidence digest changed");
    await writeFile(path, "invalid JSON");
    expect(() => check()).toThrow("acceptance is invalid");
  } finally { await rm(root, { recursive: true, force: true }); }
});

test("browser profiles select stable, independent, CLI-addressable workspaces", () => {
  const workspace = browserWorkspace("/tmp/profiles/a");
  expect(workspace).toMatch(/^browser-[a-f0-9]{12}$/);
  expect(browserWorkspace("/tmp/profiles/./a")).toBe(workspace);
  expect(browserWorkspace("/tmp/profiles/b")).not.toBe(workspace);
  expect(browserWorkspace("/tmp/profiles/a", "prepared-browser")).toBe("prepared-browser");
  expect(() => browserWorkspace("/tmp/a", "../default")).toThrow("ACTION_BROWSER_WORKSPACE");
});

test("real director preflight uses named prepared displays without launching a native host", async () => {
  const root = await mkdtemp(join(tmpdir(), "browser-preparation-test-"));
  const workspace = browserWorkspace(join(root, "profile"));
  let hostCalls = 0;
  let alive = true;
  const director = new AgentLayerDirector("unused", {
    root, workspace, isAlive: () => alive,
    runHost: async () => { hostCalls++; throw new Error("Native launch forbidden in this test"); },
  });
  try {
    await expect(requireBrowserWorkspace(director, workspace)).rejects.toThrow(`lats action layer prepare --workspace ${workspace}`);
    const manifest = director.paths().displayState;
    expect(manifest).toBe(join(root, "workspaces", workspace, "display.json"));
    await mkdir(dirname(manifest), { recursive: true });
    await writeFile(manifest, JSON.stringify({
      schemaVersion: 1, pid: 12345, displayId: 42, width: 1440, height: 900,
      serialNumber: agentWorkspaceSerial(workspace), workspace, startedAt: new Date().toISOString(),
    }));
    await requireBrowserWorkspace(director, workspace);
    alive = false;
    await expect(requireBrowserWorkspace(director, workspace)).rejects.toThrow("stale");
    await writeFile(manifest, "broken JSON");
    await expect(requireBrowserWorkspace(director, workspace)).rejects.toThrow("invalid");
    expect(hostCalls).toBe(0);
  } finally { await rm(root, { recursive: true, force: true }); }
});

test("browser launch refuses a prepared workspace occupied by another task", async () => {
  await expect(requireBrowserWorkspace({
    displayStatus: async () => ({ active: true, state: "ready" }),
    status: async () => ({ active: true, subject: { pid: 12345 } }),
  }, "occupied")).rejects.toThrow("already has an active task");
});

test("failed safety preflight blocks launch, attachment and reuse before side effects", async () => {
  const layer = new HeadedBrowserLayer("/unused", "/unused-profile");
  let unsafeCalls = 0;
  const forbidden = async (): Promise<never> => { unsafeCalls++; throw new Error("unsafe operation reached"); };
  layer.prepare = async () => ({
    requireSafety: async () => requireBrowserSafety({ safety: { privateLayer: { blocked: true, reason: "fixture quarantine" } } }),
    director: { open: forbidden, status: forbidden, actRefusal: forbidden, displayStatus: forbidden },
    openWindow: forbidden, browserConfig: () => { throw new Error("browser config reached"); }, spacesBinding: forbidden,
  });
  await expect(layer.launchApp()).rejects.toThrow("fixture quarantine");
  await expect(layer.open(12345)).rejects.toThrow("fixture quarantine");
  await expect(layer.status(12345)).rejects.toThrow("fixture quarantine");
  expect(unsafeCalls).toBe(0);
});

test("read-only safety discovery retains the selected bundle and obeys the browser deadline", async () => {
  const root = await mkdtemp(join(tmpdir(), "browser-capability-probe-"));
  const runtime = join(root, "packages/runtime/src");
  try {
    await mkdir(runtime, { recursive: true });
    await writeFile(join(runtime, "capabilities.ts"), `
      export function actionCapabilities(root, options) { return { selected: options.bundlePath, root }; }
      export function refreshActionCapabilities(previous) { return { ...previous, refreshed: true }; }
    `);
    const selected = join(root, "custom/Action.app");
    const first = await withDeadline(2000, "preflight", () => readBrowserCapabilities(root, selected));
    expect(first).toMatchObject({ selected, root });
    const next = await withDeadline(2000, "preflight", () => readBrowserCapabilities(root, selected, first));
    expect(next).toMatchObject({ selected, root, refreshed: true });
    await writeFile(join(runtime, "capabilities.ts"), "export async function actionCapabilities() { await Bun.sleep(3000); return {}; }");
    const started = performance.now();
    await expect(withDeadline(100, "preflight", () => readBrowserCapabilities(root, selected))).rejects.toThrow("timed out");
    expect(performance.now() - started).toBeLessThan(1000);
  } finally { await rm(root, { recursive: true, force: true }); }
});

test("background reuse with zero windows and newTab always creates through the layer", async () => {
  const root = await mkdtemp(join(tmpdir(), "browser-layer-target-test-"));
  const profile = join(root, "profile");
  let layerCreates = 0;
  let unplacedCreates = 0;
  const targets: Record<string, unknown>[] = [];
  const server = Bun.serve({ port: 0, hostname: "127.0.0.1",
    fetch(request, server) {
      const path = new URL(request.url).pathname;
      if (path.startsWith("/devtools/")) { if (server.upgrade(request)) return; }
      if (path === "/json/version") return Response.json({ Browser: "Fixture" });
      if (path === "/json/list") return Response.json(targets);
      if (path === "/json/new") { unplacedCreates++; return Response.json({}, { status: 500 }); }
      if (path === "/test/create-window") {
        const id = `target-${++layerCreates}`;
        targets.push({ id, type: "page", url: "about:blank", webSocketDebuggerUrl: `ws://127.0.0.1:${server.port}/devtools/${id}` });
        return Response.json({ id });
      }
      return Response.json({});
    },
    websocket: { message(ws, raw) {
      const request = JSON.parse(String(raw));
      const result = request.method === "Page.getFrameTree" ? { frameTree: { frame: {} } }
        : request.method === "Runtime.evaluate" ? { result: { value: { readyState: "complete", documentUrl: "https://example.com/", title: "Fixture" } } } : {};
      ws.send(JSON.stringify({ id: request.id, result }));
    } },
  });
  const script = `
    import { mock } from "bun:test";
    import { mkdirSync, symlinkSync } from "node:fs";
    const profile = ${JSON.stringify(profile)};
    mkdirSync(profile);
    symlinkSync("fixture-" + process.pid, profile + "/SingletonLock");
    mock.module(${JSON.stringify(new URL("./layer.ts", import.meta.url).pathname)}, () => ({
      HeadedBrowserLayer: class {
        requiredFor() { return true; }
        async status() { return {}; }
        async verify() {}
        async createWindow() { return (await (await fetch("http://127.0.0.1:${server.port}/test/create-window")).json()).id; }
      },
    }));
    const { browserToolset } = await import(${JSON.stringify(new URL("./index.ts", import.meta.url).href)});
    const replies = [];
    for (const newTab of [false, true]) replies.push(await browserToolset.callTool("browser_open", { url: "https://example.com/", background: true, newTab, waitMs: 2000 }));
    process.stdout.write(JSON.stringify(replies));
  `;
  const child = Bun.spawn([process.execPath, "-e", script, "--", `--user-data-dir=${profile}`], {
    stdout: "pipe", stderr: "pipe",
    env: { ...process.env, ACTION_BROWSER_PROFILE_DIR: profile, ACTION_BROWSER_PROFILE_ROOT: root,
      ACTION_BROWSER_DEBUG_PORT: String(server.port), ACTION_BROWSER_SESSION_DIR: join(root, "sessions"),
      ACTION_BROWSER_ARTIFACT_DIR: join(root, "artifacts"), ACTION_BROWSER_IDLE_TIMEOUT_MS: "0" },
  });
  try {
    const [stdout, stderr, code] = await Promise.all([new Response(child.stdout).text(), new Response(child.stderr).text(), child.exited]);
    if (code !== 0) throw new Error(`Browser fixture exited ${code}: ${stderr}`);
    const replies = JSON.parse(stdout);
    expect(replies.map((reply: { structuredContent: { ok: boolean } }) => reply.structuredContent.ok)).toEqual([true, true]);
    expect(layerCreates).toBe(2);
    expect(unplacedCreates).toBe(0);
  } finally {
    child.kill();
    server.stop(true);
    await child.exited;
    await rm(root, { recursive: true, force: true });
  }
}, 10000);
