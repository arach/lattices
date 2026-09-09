import { expect, test } from "bun:test";
import { chmod, mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

test("launcher finds the user Bun with a GUI PATH and preserves paths containing spaces", async () => {
  const directory = await mkdtemp(join(tmpdir(), "action launcher "));
  try {
    const bin = join(directory, ".bun/bin");
    await mkdir(bin, { recursive: true });
    const executable = join(bin, "bun");
    await writeFile(executable, '#!/bin/sh\nprintf "%s\\n" "$1"\n');
    await chmod(executable, 0o755);
    const script = resolve(import.meta.dir, "../scripts/run-action-browser-mcp.sh");
    const run = (override?: string) => Bun.spawn(["/bin/bash", script], {
      env: { HOME: directory, PATH: "/usr/bin:/bin", ...(override ? { ACTION_BUN_BIN: override } : {}) }, stdout: "pipe", stderr: "pipe",
    });
    const child = run();
    expect(await new Response(child.stdout).text()).toBe(resolve(import.meta.dir, "index.ts") + "\n");
    expect(await child.exited).toBe(0);
    const invalid = run(join(directory, "missing"));
    expect(await invalid.exited).toBe(1);
    expect(await new Response(invalid.stderr).text()).toContain("ACTION_BUN_BIN");
    const explicit = run(executable);
    expect(await explicit.exited).toBe(0);
  } finally { await rm(directory, { recursive: true, force: true }); }
});
