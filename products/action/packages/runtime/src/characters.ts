import { readFileSync } from "node:fs";
import { join } from "node:path";

export type CharacterFormat = "spritesheet" | "avatar";

export interface CharacterTreatment {
  id: string;
  displayName: string;
  surface: string;
  format: CharacterFormat;
  petId: string | null;
  variant: "full-color" | "silhouette" | "pixel";
  accessories: string[];
  scale: number;
  states?: string[];
  rowHints?: Record<string, string>;
  sizes?: number[];
  notes?: string;
}

export interface CharacterPhaseBinding {
  treatment: string;
  state: string;
}

export interface CharacterCatalog {
  schemaVersion: number;
  baseRig: string;
  applications: Record<string, string>;
  treatments: CharacterTreatment[];
  stateMap: Record<string, CharacterPhaseBinding>;
}

let cachedCatalog: CharacterCatalog | null = null;

export function loadCharacterCatalog(repoRoot?: string): CharacterCatalog {
  if (cachedCatalog) return cachedCatalog;
  const root = repoRoot ?? process.cwd();
  const path = join(root, "assets/characters/treatments.json");
  cachedCatalog = JSON.parse(readFileSync(path, "utf8")) as CharacterCatalog;
  return cachedCatalog;
}

export function treatmentById(catalog: CharacterCatalog, id: string): CharacterTreatment | undefined {
  return catalog.treatments.find((t) => t.id === id);
}

export function treatmentForApplication(
  catalog: CharacterCatalog,
  application: string,
): CharacterTreatment | undefined {
  const id = catalog.applications[application];
  return id ? treatmentById(catalog, id) : undefined;
}

export function resolveCharacterForPhase(
  catalog: CharacterCatalog,
  phase: string,
): CharacterPhaseBinding {
  return catalog.stateMap[phase] ?? { treatment: "mira", state: "idle" };
}

export function resolveSpriteState(
  treatment: CharacterTreatment,
  logicalState: string,
): { petId: string; sheetState: string } | null {
  if (treatment.format !== "spritesheet" || !treatment.petId) return null;
  return { petId: treatment.petId, sheetState: logicalState };
}

export interface CharacterContext {
  application?: string;
  sessionPhase?: string;
  surface?: string;
}

export interface ResolvedCharacterContext {
  treatment: CharacterTreatment;
  state: string;
}

export function resolveCharacterContext(
  catalog: CharacterCatalog,
  ctx: CharacterContext,
): ResolvedCharacterContext {
  if (ctx.sessionPhase && catalog.stateMap[ctx.sessionPhase]) {
    const binding = catalog.stateMap[ctx.sessionPhase];
    const treatment = treatmentById(catalog, binding.treatment) ?? catalog.treatments[0];
    return { treatment, state: binding.state };
  }

  if (ctx.application) {
    const treatment = treatmentForApplication(catalog, ctx.application);
    if (treatment) {
      const state = treatment.states?.[0] ?? "idle";
      return { treatment, state };
    }
  }

  const fallback = catalog.treatments[0];
  return { treatment: fallback, state: "idle" };
}
