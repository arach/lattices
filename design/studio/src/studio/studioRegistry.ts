import { defineStudio, type StudioPage } from "studio/registry";

/**
 * Lattices studio registry — the single source of truth for the sidebar nav.
 * Each study is one route; add an entry here and it surfaces automatically.
 */

export type Bucket = "foundations" | "studies";
export type Surface = "macos" | "cross";
export type Status = "concept" | "in-flight" | "shipped";

export type LatticesPage = StudioPage<Bucket, Surface, Status>;

export const HOME_HREF = "/studio";

export const pages: readonly LatticesPage[] = [
  {
    href: HOME_HREF,
    label: "Lattices Studio",
    bucket: "foundations",
    surface: "macos",
    status: "concept",
    blurb:
      "Design surface for the Lattices macOS workspace manager — studies land here before SwiftUI gets touched.",
  },
  {
    href: "/studio/studies/nexus",
    label: "Nexus — command bar",
    bucket: "studies",
    surface: "macos",
    status: "concept",
    blurb:
      "One slim bar: search · /commands · voice → act inline or hand off to the assistant. Six states on the registration grid.",
    source: ["apps/mac/Sources/Core/Overlays/Nexus/"],
  },
];

const defined = defineStudio({
  pages,
  surfaceOrder: ["macos", "cross"],
  defaultSurface: "macos",
  buckets: [{ key: "foundations" }, { key: "studies" }],
  statuses: {
    concept: { tone: "info", label: "CONCEPT" },
    "in-flight": { tone: "warn", label: "IN-FLIGHT" },
    shipped: { tone: "ok", label: "SHIPPED" },
  },
  iteration: {},
});

export const {
  registry,
  buckets: BUCKETS,
  statusColors: STATUS_COLORS,
  StatusPill,
  palette: statusPalette,
} = defined;

export { StatusPill as LatticesStatusPill };
