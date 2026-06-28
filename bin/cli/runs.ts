import { hasFlag, nonFlagArgs, parseFlagValue } from "./helpers.ts";
import { withDaemon } from "./daemon.ts";

function runLine(run: any): string {
  const count = Array.isArray(run.artifacts) ? run.artifacts.length : 0;
  const completed = run.completedAt ? ` completed=${run.completedAt}` : "";
  return `  ${run.id}  ${run.state || "?"}  artifacts=${count}  ${run.title || "Untitled run"}${completed}`;
}

export async function runsCommand(rawArgs: string[] = []): Promise<void> {
  const jsonFlag = hasFlag(rawArgs, "json");
  const positional = nonFlagArgs(rawArgs);
  const sub = positional[0];

  await withDaemon(async ({ daemonCall }) => {
    if (sub && sub !== "list") {
      const run = await daemonCall("runs.get", { id: sub }) as any;
      if (jsonFlag) {
        console.log(JSON.stringify(run, null, 2));
        return;
      }
      console.log(runLine(run));
      console.log(`  artifacts: ${run.artifactDirectoryPath}`);
      for (const artifact of run.artifacts || []) {
        console.log(`    ${artifact.kind}  ${artifact.path}`);
      }
      return;
    }

    const limit = Number(parseFlagValue(rawArgs, "limit") || 20);
    const runs = await daemonCall("runs.list", { limit }) as any[];
    if (jsonFlag) {
      console.log(JSON.stringify(runs, null, 2));
      return;
    }
    if (!runs.length) {
      console.log("No runs yet.");
      return;
    }
    console.log(`Runs (${runs.length}):\n`);
    for (const run of runs) console.log(runLine(run));
  });
}
