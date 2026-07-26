import { cpSync, existsSync, mkdirSync, rmSync } from "node:fs";
import { resolve } from "node:path";

const studioRoot = resolve(import.meta.dir, "..");
const sourceHTML = resolve(studioRoot, ".next/server/app/embed/deck-builder.html");
const sourceStatic = resolve(studioRoot, ".next/static");
const outputRoot = resolve(studioRoot, "../../apps/mac/Resources/DeckBuilder");

if (!existsSync(sourceHTML) || !existsSync(sourceStatic)) {
  throw new Error("Deck Builder build output is missing. Run `bun run build` first.");
}

rmSync(outputRoot, { recursive: true, force: true });
mkdirSync(resolve(outputRoot, "_next"), { recursive: true });
cpSync(sourceHTML, resolve(outputRoot, "index.html"));
cpSync(sourceStatic, resolve(outputRoot, "_next/static"), { recursive: true });

console.log(`Exported embedded Deck Builder to ${outputRoot}`);
