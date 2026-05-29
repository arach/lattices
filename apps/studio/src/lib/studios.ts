export interface StudioEntry {
  slug: string;
  title: string;
  caption: string;
  status: "live" | "draft";
}

export const STUDIO_ENTRIES: StudioEntry[] = [
  {
    slug: "tiling",
    title: "Tiling playground",
    caption: "Every preset, on a real screen",
    status: "live",
  },
  {
    slug: "intents",
    title: "Intent Explorer",
    caption: "The closed set — every phrase that's guaranteed to bind",
    status: "live",
  },
  {
    slug: "handsoff",
    title: "Handsoff",
    caption: "The open-ended path — model in the loop",
    status: "live",
  },
];

const STUDIO_BY_SLUG = new Map<string, StudioEntry>();
for (const entry of STUDIO_ENTRIES) STUDIO_BY_SLUG.set(entry.slug, entry);

export function findStudioBySlug(slug: string): StudioEntry | undefined {
  return STUDIO_BY_SLUG.get(slug);
}
