#!/usr/bin/env bun
/** Build-time import only. Runtime uses WKURLSchemeHandler, never a server.
 * Usage: bun bin/import-editor-bundle.ts /path/to/hudson/apps/lattices-editor/dist
 * Run only after the Hudson owner approves that output for integration.
 */
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync, mkdirSync, lstatSync, readdirSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { validateEditorCSS } from "./editor-bundle-assets";

const input = process.argv[2];
if (!input) throw new Error("Usage: bun bin/import-editor-bundle.ts <Hudson editor dist directory>");
const source = resolve(input);
const destination = resolve(import.meta.dir, "../apps/mac/Resources/Editor");
// Import all flat, local assets, including font licenses. Reject unexpected
// files or directories rather than silently shipping an incomplete bundle.
const files = readdirSync(source).sort();
for (const required of ["index.html", "editor.js", "editor.css"]) {
  if (!files.includes(required)) throw new Error(`Missing bundle entry: ${required}`);
}
for (const name of files) {
  if (!/^[a-zA-Z0-9._-]+\.(html|js|css|woff2|txt)$/.test(name)) {
    throw new Error(`Unsupported bundle asset: ${name}`);
  }
}
const assets = files.map(name => {
  const path = resolve(source, name);
  if (!lstatSync(path).isFile()) throw new Error(`Expected a regular bundled file: ${path}`);
  const data = readFileSync(path);
  if (!data.length) throw new Error(`Empty bundle file: ${path}`);
  return { name, data, sha256: createHash("sha256").update(data).digest("hex") };
});
const css = assets.find(asset => asset.name === "editor.css")!.data.toString("utf8");
validateEditorCSS(css, files);
const revision = execFileSync("git", ["-C", dirname(source), "rev-parse", "HEAD"], { encoding: "utf8" }).trim();
const sourceDirty = execFileSync("git", ["-C", dirname(source), "status", "--porcelain"], { encoding: "utf8" }).trim().length > 0;
mkdirSync(destination, { recursive: true });
for (const asset of assets) writeFileSync(resolve(destination, asset.name), asset.data);
writeFileSync(resolve(destination, "provenance.json"), JSON.stringify({
  source: "arach/hudson:apps/lattices-editor", revision, sourceDirty,
  files: Object.fromEntries(assets.map(({ name, sha256 }) => [name, sha256])),
}, null, 2) + "\n");
console.log(`Imported Hudson Editor ${revision} into ${destination}`);
