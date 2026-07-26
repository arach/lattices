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
  {
    href: "/studio/studies/deck-builder",
    label: "Deck Builder — companion cockpit",
    bucket: "studies",
    surface: "macos",
    status: "in-flight",
    blurb:
      "Span-aware grid editor for the companion deck: tap an empty cell to add, drag to move, pull the corner to span 2×1 / 2×2. Interactive prototype for the Mac-side builder — the iPad just receives the layout and renders it.",
    source: [
      "docs/companion-deck-builder-spec.md",
      "apps/mac/Sources/Core/Companion/LatticesCompanionCockpit.swift",
    ],
  },
  {
    href: "/studio/studies/cross-app-tabs",
    label: "Cross-app tabs — one topic, many tools",
    bucket: "studies",
    surface: "cross",
    status: "in-flight",
    blurb:
      "A native-window tab rail for grouping Chrome, terminal, and editor surfaces around one topic. Tabs preserve real app identity; Grid temporarily fans the same windows out for comparison.",
    source: [
      "apps/mac/Sources/Core/Workspace/LiveTabGroupStore.swift",
      "apps/mac/Sources/Core/Overlays/HUD/HUDWindowHints.swift",
    ],
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
