import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import { parseScenarioDocument, type ScenarioDocument } from "@action/compiler";

export function resolveScenarioPath(idOrPath: string): string {
  if (idOrPath.endsWith(".json")) {
    return resolve(process.cwd(), idOrPath);
  }

  return resolve(process.cwd(), "scenarios", `${idOrPath}.json`);
}

export async function loadScenario(idOrPath: string): Promise<ScenarioDocument> {
  const path = resolveScenarioPath(idOrPath);
  const raw = await readFile(path, "utf8");
  return parseScenarioDocument(JSON.parse(raw));
}
