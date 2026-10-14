import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";

import { parentAlive } from "./lifecycle.js";

const lifecyclePath = fileURLToPath(new URL("./lifecycle.ts", import.meta.url));

describe("parentAlive", () => {
  test("true for the live parent", () => {
    assert.equal(parentAlive(process.ppid), true);
  });

  test("false for a pid that is not our parent", () => {
    assert.equal(parentAlive(process.pid), false);
    assert.equal(parentAlive(1), false);
  });
});

describe("exitWithParent", () => {
  test("child exits when its stdin closes", async () => {
    // stdin only emits "end" while flowing; the MCP transport's reader keeps it flowing, so mirror it.
    const child = spawn(process.execPath, [
      "-e",
      `import(${JSON.stringify(lifecyclePath)}).then((m) => { process.stdin.on("data", () => {}); m.exitWithParent(); setInterval(() => {}, 1000); });`,
    ], { stdio: ["pipe", "ignore", "inherit"] });
    const exited = new Promise<number | null>((resolve) => child.once("exit", resolve));
    await new Promise((resolve) => setTimeout(resolve, 300));
    child.stdin.end();
    const code = await Promise.race([
      exited,
      new Promise<string>((resolve) => setTimeout(() => resolve("timeout"), 3000)),
    ]);
    if (code === "timeout") child.kill("SIGKILL");
    assert.equal(code, 0);
  });
});
