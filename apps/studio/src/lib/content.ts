import { findEntryBySourcePath, type EngDocEntry } from "./eng-docs";

const DOC_MODULES = import.meta.glob("../../../../docs/**/*.md", {
  query: "?raw",
  import: "default",
  eager: false,
}) as Record<string, () => Promise<string>>;

function moduleKeyForEntry(entry: EngDocEntry): string {
  return `../../../../${entry.sourcePath}`;
}

export async function loadDoc(entry: EngDocEntry): Promise<string> {
  const key = moduleKeyForEntry(entry);
  const loader = DOC_MODULES[key];
  if (!loader) {
    throw new Error(`No markdown module found for ${entry.sourcePath}`);
  }
  return loader();
}

export function availableSourcePaths(): string[] {
  return Object.keys(DOC_MODULES).map((key) =>
    key.replace(/^\.\.\/\.\.\/\.\.\/\.\.\//, ""),
  );
}

export function entryForRepoPath(path: string): EngDocEntry | undefined {
  return findEntryBySourcePath(path);
}
