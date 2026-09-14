import { expect, test } from "bun:test";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
const skillsRoot = join(repoRoot, "skills");
const marketplacePath = join(repoRoot, ".claude-plugin", "marketplace.json");
const actionBrowserSkill = join(
  repoRoot,
  "products/action/plugins/action-browser/skills/action-browser/SKILL.md",
);

const catalog = ["action", "blink", "lattices", "speech"] as const;

function frontmatter(source: string): string {
  const match = source.match(/^---\n([\s\S]*?)\n---\n/);
  if (!match) throw new Error("missing YAML frontmatter");
  return match[1];
}

function skillName(directory: string): string {
  const source = readFileSync(join(skillsRoot, directory, "SKILL.md"), "utf8");
  const name = frontmatter(source).match(/^name:\s*([^\n]+)$/m)?.[1]?.trim();
  if (!name) throw new Error(`${directory}: missing frontmatter name`);
  return name;
}

test("skills/ is the family catalog", () => {
  const directories = readdirSync(skillsRoot)
    .filter((entry) => statSync(join(skillsRoot, entry)).isDirectory())
    .sort();

  expect(directories).toEqual([...catalog]);

  for (const directory of catalog) {
    expect(skillName(directory)).toBe(directory);
  }
});

test("lattices skill teaches current workspace commands", () => {
  const source = readFileSync(join(skillsRoot, "lattices", "SKILL.md"), "utf8");
  expect(source).toContain("lattices daemon status");
  expect(source).toContain("window.place");
});

test("action skill teaches the native drive loop", () => {
  const source = readFileSync(join(skillsRoot, "action", "SKILL.md"), "utf8");
  expect(source).toContain("action.drive.begin");
  expect(source).toContain("action.observe.snapshot");
  expect(source).toContain("action-browser@action");
});

test("speech skill teaches voice simulate and intents", () => {
  const source = readFileSync(join(skillsRoot, "speech", "SKILL.md"), "utf8");
  expect(source).toContain("lattices voice simulate");
  expect(source).toContain("lattices voice intents");
  expect(source).toContain("window.place");
});

test("blink skill teaches the shipped notes CLI", () => {
  const source = readFileSync(join(skillsRoot, "blink", "SKILL.md"), "utf8");
  expect(source).toContain("blink present");
  expect(source).toContain("blink ls --json");
  expect(source).not.toContain("MCP waits");
});

test("Action Browser skill stays plugin-local", () => {
  const meta = frontmatter(readFileSync(actionBrowserSkill, "utf8"));
  expect(meta).toContain("internal: true");
});

test("Action plugin marketplace stays standalone", () => {
  const marketplace = JSON.parse(readFileSync(marketplacePath, "utf8"));
  const pluginNames = marketplace.plugins.map((plugin: { name: string }) => plugin.name);

  expect(marketplace.name).toBe("action");
  expect(pluginNames).toEqual(["action-browser"]);
});
