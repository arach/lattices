#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const appDir = resolve(scriptDir, "..");
const repoRoot = resolve(appDir, "../..");
const image = process.env.DEWEY_AGENT_CONTAINER_IMAGE ?? "node:24-bookworm-slim";
const platform = process.env.DEWEY_AGENT_CONTAINER_PLATFORM ?? "linux/arm64";
const port = process.env.PORT ?? "8787";
const stateDir = process.env.DEWEY_AGENT_STATE_DIR ?? join(homedir(), ".lattices", "dewey-agent");
const hostDnsName = process.env.DEWEY_AGENT_HOST_DNS ?? "host.container.internal";
const hostDnsIp = process.env.DEWEY_AGENT_HOST_DNS_IP ?? "203.0.113.113";

function printHelp() {
  console.log(`Usage: node scripts/apple-container.mjs <command>

Commands:
  status      Check Apple container service and base image state
  build       Pull/verify the base image used by the local Eve runner
  run         Run Eve at http://127.0.0.1:${port}
  shell       Open a shell after preparing the Eve app
  smoke       Run the deterministic docs smoke check in the container
  host-dns    Create the host DNS alias for local model servers

Environment:
  DEWEY_AGENT_CONTAINER_IMAGE    Base image, default ${image}
  DEWEY_AGENT_CONTAINER_PLATFORM Image platform, default ${platform}
  DEWEY_AGENT_STATE_DIR          Persistent Eve state dir, default ${stateDir}
  DEWEY_AGENT_BASE_URL           Local model endpoint for the agent
  DEWEY_AGENT_HOST_DNS           Host alias, default ${hostDnsName}
  DEWEY_AGENT_HOST_DNS_IP        Alias IP, default ${hostDnsIp}
  PORT                           Host/app port, default ${port}`);
}

function run(cmd, args, options = {}) {
  const result = spawnSync(cmd, args, {
    cwd: appDir,
    stdio: "inherit",
    ...options,
  });

  if (result.error) {
    throw result.error;
  }

  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

function probe(cmd, args) {
  return spawnSync(cmd, args, {
    cwd: appDir,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
}

function ensureContainerCli() {
  const result = probe("container", ["--version"]);
  if (result.status !== 0) {
    console.error("Apple container CLI is required. Install it with Fabric setup or Apple's container installer.");
    process.exit(1);
  }
}

function ensureContainerSystem() {
  ensureContainerCli();
  const result = probe("container", ["system", "status"]);
  if (result.status === 0) {
    return;
  }

  run("container", [
    "system",
    "start",
    "--enable-kernel-install",
    "--timeout",
    "120",
  ]);
}

function ensureStateDirs() {
  for (const name of ["workflow", "eve", "npm"]) {
    mkdirSync(join(stateDir, name), { recursive: true });
  }
}

function imageExists() {
  return probe("container", ["image", "inspect", image]).status === 0;
}

function prepareImage() {
  ensureContainerSystem();
  if (!imageExists()) {
    run("container", ["image", "pull", "--platform", platform, image]);
  }
}

function prepCommand(finalCommand) {
  return [
    "set -eu",
    "mkdir -p /work",
    "find /work -mindepth 1 -maxdepth 1 ! -name .workflow-data ! -name .eve -exec rm -rf {} +",
    "tar --exclude='./node_modules' --exclude='./.output' --exclude='./.eve' --exclude='./.workflow-data' -C /source -cf - . | tar -C /work -xf -",
    "cd /work",
    "npm ci --ignore-scripts",
    "npm run build",
    finalCommand,
  ].join(" && ");
}

function commonRunArgs() {
  const baseUrl = process.env.DEWEY_AGENT_BASE_URL ?? `http://${hostDnsName}:11434/v1`;
  return [
    "run",
    "--rm",
    "--init",
    "--progress",
    "plain",
    "--platform",
    platform,
    "--publish",
    `127.0.0.1:${port}:8787/tcp`,
    "--volume",
    `${appDir}:/source:ro`,
    "--volume",
    `${repoRoot}:/repo`,
    "--volume",
    `${join(stateDir, "workflow")}:/work/.workflow-data`,
    "--volume",
    `${join(stateDir, "eve")}:/work/.eve`,
    "--volume",
    `${join(stateDir, "npm")}:/root/.npm`,
    "--env",
    `PORT=${port}`,
    "--env",
    "LATTICES_REPO=/repo",
    "--env",
    `DEWEY_AGENT_PROVIDER=${process.env.DEWEY_AGENT_PROVIDER ?? "local"}`,
    "--env",
    `DEWEY_AGENT_BASE_URL=${baseUrl}`,
    "--env",
    `DEWEY_AGENT_MODEL=${process.env.DEWEY_AGENT_MODEL ?? "llama3.1:8b"}`,
    "--env",
    `DEWEY_AGENT_API_KEY=${process.env.DEWEY_AGENT_API_KEY ?? "local"}`,
    "--env",
    `DEWEY_AGENT_CONTEXT_WINDOW_TOKENS=${process.env.DEWEY_AGENT_CONTEXT_WINDOW_TOKENS ?? "131072"}`,
    image,
    "sh",
    "-lc",
  ];
}

function runPrepared(finalCommand) {
  ensureContainerSystem();
  prepareImage();
  ensureStateDirs();
  run("container", [...commonRunArgs(), prepCommand(finalCommand)]);
}

function printStatus() {
  ensureContainerCli();
  const status = probe("container", ["system", "status"]);
  if (status.stdout.trim()) {
    console.log(status.stdout.trim());
  }
  if (status.stderr.trim()) {
    console.error(status.stderr.trim());
  }

  if (status.status === 0 && imageExists()) {
    console.log(`Base image ready: ${image}`);
  } else {
    console.log(`Base image not verified: ${image}`);
  }
}

function createHostDns() {
  ensureContainerCli();
  console.log(`Creating ${hostDnsName} -> host localhost alias via Apple container DNS.`);
  run("sudo", [
    "container",
    "system",
    "dns",
    "create",
    hostDnsName,
    "--localhost",
    hostDnsIp,
  ]);
}

const command = process.argv[2] ?? "help";

try {
  switch (command) {
    case "status":
      printStatus();
      break;
    case "build":
      prepareImage();
      break;
    case "run":
      runPrepared("exec npm run start");
      break;
    case "shell":
      runPrepared("exec sh");
      break;
    case "smoke":
      runPrepared("npm run smoke");
      break;
    case "host-dns":
      createHostDns();
      break;
    case "help":
    case "--help":
    case "-h":
      printHelp();
      break;
    default:
      console.error(`Unknown command: ${command}`);
      printHelp();
      process.exit(1);
  }
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
}
