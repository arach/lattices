#!/usr/bin/env bun

import { join } from "node:path";
import { fileURLToPath } from "node:url";
import {
  loadCharacterCatalog,
  resolveCharacterContext,
  resolveSpriteState,
} from "../../runtime/src/characters.ts";

const repoRoot = fileURLToPath(new URL("../../..", import.meta.url));
const catalog = loadCharacterCatalog(repoRoot);

const scenarios = [
  {
    name: "Recording take",
    context: { sessionPhase: "session.recording" },
  },
  {
    name: "Inspection analyze",
    context: { sessionPhase: "session.analyzing" },
  },
  {
    name: "Chrome companion idle",
    context: { application: "chrome-companion" },
  },
  {
    name: "CLI operator",
    context: { application: "action-cli" },
  },
];

for (const scenario of scenarios) {
  const resolved = resolveCharacterContext(catalog, scenario.context);
  const sprite = resolveSpriteState(resolved.treatment, resolved.state);
  console.log(`\n=== ${scenario.name} ===`);
  console.log(`  context:     ${JSON.stringify(scenario.context)}`);
  console.log(`  treatment:   ${resolved.treatment.displayName} (${resolved.treatment.id})`);
  console.log(`  surface:     ${resolved.treatment.surface}`);
  console.log(`  state:       ${resolved.state}`);
  console.log(`  accessories: ${resolved.treatment.accessories.join(", ") || "(none)"}`);
  if (sprite) {
    console.log(`  sprite:      pet=${sprite.petId} state=${sprite.sheetState}`);
  } else {
    console.log(`  sprite:      avatar ${resolved.treatment.variant}`);
  }
}