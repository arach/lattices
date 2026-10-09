import { expect, test } from "bun:test";
import { mkdtempSync, mkdirSync, rmSync } from "node:fs";
import { createServer, type Socket } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { commandSocketPath, dispatchBatch, request } from "../src/hyprland-command.ts";
import { apply, exec, hyprctlJson, plan } from "../src/hyprland.ts";

async function fixture(reply: (command: string, socket: Socket) => void, fn: (path: string) => Promise<void>) {
  const dir = mkdtempSync(join(tmpdir(), "lats-ipc-"));
  const instance = join(dir, "hypr", "test");
  mkdirSync(instance, { recursive: true });
  const path = join(instance, ".socket.sock");
  const sockets = new Set<Socket>();
  const server = createServer({ allowHalfOpen: true }, (socket) => {
    sockets.add(socket);
    socket.on("close", () => sockets.delete(socket));
    socket.on("error", () => {});
    let command = "";
    socket.on("data", (chunk) => command += chunk.toString());
    socket.on("end", () => reply(command, socket));
  });
  await new Promise<void>((resolve) => server.listen(path, resolve));
  try { await fn(path); }
  finally {
    for (const socket of sockets) socket.destroy();
    await new Promise<void>((resolve) => server.close(() => resolve()));
    rmSync(dir, { recursive: true, force: true });
  }
}

test("socket path requires both session variables", () => {
  expect(commandSocketPath({ XDG_RUNTIME_DIR: "/run/user/1", HYPRLAND_INSTANCE_SIGNATURE: "abc" })).toBe("/run/user/1/hypr/abc/.socket.sock");
  expect(() => commandSocketPath({})).toThrow("HYPRLAND_INSTANCE_SIGNATURE");
  expect(() => commandSocketPath({ HYPRLAND_INSTANCE_SIGNATURE: "abc" })).toThrow("XDG_RUNTIME_DIR");
});

test("reads every chunk through EOF, including split UTF-8 and a large reply", async () => {
  const expected = JSON.stringify({ title: "日本語", padding: "a".repeat(80_000) });
  await fixture((command, socket) => {
    expect(command).toBe("j/clients");
    const bytes = Buffer.from(expected);
    socket.write(bytes.subarray(0, 12));
    setImmediate(() => socket.end(bytes.subarray(12)));
  }, async (path) => {
    expect(await request("j/clients", { path })).toBe(expected);
  });
});

test("parallel requests have independent reply buffers", async () => {
  await fixture((command, socket) => socket.end(command), async (path) => {
    expect(await Promise.all(["clients", "monitors", "workspaces"].map((c) => request("j/" + c, { path })))).toEqual(["j/clients", "j/monitors", "j/workspaces"]);
  });
});

test("connection failures, deadlines and reply limits reject without retries", async () => {
  await expect(request("j/clients", { path: "/no-such-lats-socket" })).rejects.toThrow("hyprctl:");
  let attempts = 0;
  await fixture((_, socket) => { attempts++; socket.write("too long"); }, async (path) => {
    await expect(request("j/clients", { path, timeoutMs: 20, maxBytes: 2 })).rejects.toThrow("byte limit");
  });
  await fixture(() => { attempts++; }, async (path) => {
    await expect(request("j/clients", { path, timeoutMs: 20 })).rejects.toThrow("timed out");
  });
  expect(attempts).toBe(2);
});

test("one batch, all replies checked, empty and incomplete replies are not success", async () => {
  await fixture((command, socket) => {
    expect(command).toBe("[[BATCH]]dispatch first ; dispatch second");
    socket.end("ok\n\n\nok");
  }, async (path) => { await dispatchBatch(["first", "second"], { path }); });
  for (const reply of ["ok\n\n\nbad dispatcher", "ok\n\n\nerror one\nerror two", "", "ok"]) {
    await fixture((_, socket) => socket.end(reply), async (path) => {
      await expect(dispatchBatch(["first", "second"], { path })).rejects.toThrow("hyprctl:");
    });
  }
  await dispatchBatch([], { path: "/not-needed" });
});

test("public queries, exec, dry runs and apply keep both dispatcher dialects", async () => {
  const saved = { signature: process.env.HYPRLAND_INSTANCE_SIGNATURE, runtime: process.env.XDG_RUNTIME_DIR };
  try {
    for (const lua of [true, false]) {
      const received: string[] = [];
      await fixture((command, socket) => {
        received.push(command);
        if (command === "j/clients") socket.end("[]");
        else if (command === "/dispatch hl.dsp.no_op()") socket.end(lua ? "ok" : "Invalid dispatcher");
        else if (command.startsWith("[[BATCH]]")) socket.end("ok\n\n\nok");
        else socket.end("ok");
      }, async (path) => {
        process.env.XDG_RUNTIME_DIR = path.split("/hypr/")[0];
        process.env.HYPRLAND_INSTANCE_SIGNATURE = "test";
        expect(await hyprctlJson<unknown[]>("clients")).toEqual([]);
        const ops = [{ op: "focus" as const, address: "0xab" }, { op: "float" as const, address: "0xab" }];
        const commands = await plan(ops);
        expect(received.length).toBe(2);
        expect(await apply(ops)).toEqual(commands);
        expect(received[2]).toBe("[[BATCH]]" + commands.map((c) => "dispatch " + c).join(" ; "));
        await exec("echo /tmp/test");
        expect(received[3]).toBe(lua ? '/dispatch hl.dsp.exec_cmd("echo /tmp/test")' : "/dispatch exec echo /tmp/test");
        expect(received.filter((c) => c === "/dispatch hl.dsp.no_op()").length).toBe(1);
      });
    }
  } finally {
    if (saved.signature === undefined) delete process.env.HYPRLAND_INSTANCE_SIGNATURE;
    else process.env.HYPRLAND_INSTANCE_SIGNATURE = saved.signature;
    if (saved.runtime === undefined) delete process.env.XDG_RUNTIME_DIR;
    else process.env.XDG_RUNTIME_DIR = saved.runtime;
  }
});
