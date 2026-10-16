import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

if (process.platform !== "linux") throw new Error("The Linux app needs a Linux desktop.");
const quickshell = Bun.which("quickshell");
if (!quickshell) throw new Error("Install Quickshell to run the Linux app.");
const child = spawn(quickshell, ["--path", fileURLToPath(new URL("./", import.meta.url)), "--no-duplicate"], {
  stdio: "inherit",
  env: { ...process.env, LATTICES_LINUX_BUN: process.execPath },
});
process.on("SIGINT", () => child.kill("SIGINT"));
process.on("SIGTERM", () => child.kill("SIGTERM"));
child.on("error", (error) => { console.error(error.message); process.exitCode = 1; });
child.on("exit", (code) => { process.exitCode = code ?? 0; });
