import { defineStudio, type StudioPage } from "studio/registry";

/**
 * Blink product studio registry.
 *
 * Buckets follow the recommended split:
 * - foundations — North Star, locked decisions, the v1 spec (scope contract)
 * - plans      — the build plan and the design pass it came from
 * - studies    — live UI studies for the v2.0 triad surfaces
 */

export type Bucket = "foundations" | "plans" | "studies";
export type Surface = "vision" | "doc" | "ios" | "macos";
export type Status = "locked" | "study" | "open";

export type BlinkStudioPage = StudioPage<Bucket, Surface, Status>;

export const HOME_HREF = "/studio";

export const pages: readonly BlinkStudioPage[] = [
  {
    href: HOME_HREF,
    label: "North Star",
    bucket: "foundations",
    surface: "vision",
    status: "locked",
    blurb:
      "The note is the window. The desktop stays spatial; the iOS companion is the offline-first pocket view over the same Markdown truth.",
  },
  {
    href: "/studio/foundations/decisions",
    label: "Decisions & defaults",
    bucket: "foundations",
    surface: "vision",
    status: "locked",
    blurb:
      "Everything locked on 2026-07-14: surface set, repo strategy, spatial feel, overflow story — plus the veto-able defaults.",
    source: ["docs/v2-plan.md"],
  },
  {
    href: "/studio/foundations/functionality-v1",
    label: "v1 spec (scope contract)",
    bucket: "foundations",
    surface: "doc",
    status: "locked",
    blurb:
      "The accurate inventory of everything v1 shipped. v2's guard against rewrite creep — if it's not here or in the plan, it waits.",
    source: ["docs/functionality-v1.md"],
  },
  {
    href: "/studio/foundations/notes-representation",
    label: "Notes representation",
    bucket: "foundations",
    surface: "doc",
    status: "open",
    blurb:
      "The bigger conversation: files as truth, a disposable .blink/ cache, JSON index, and the agent surface (conventions → CLI → MCP). Annotate to decide.",
    source: ["docs/notes-representation.md"],
  },
  {
    href: "/studio/plans/v2-plan",
    label: "Build plan (M0–M5)",
    bucket: "plans",
    surface: "doc",
    status: "locked",
    blurb:
      "Architecture, milestones with exit criteria, v1 lessons as hard requirements, risks. The working contract for the Swift build.",
    source: ["docs/v2-plan.md"],
  },
  {
    href: "/studio/plans/ui-map",
    label: "UI map (design pass)",
    bucket: "plans",
    surface: "doc",
    status: "study",
    blurb:
      "The design-studio pass: surface inventory, wireframes, key interactions, principles. Feeds the studies; superseded where decisions moved on.",
    source: ["docs/v2-ui-map.md"],
  },
  {
    href: "/studio/studies/ios-design-directions",
    label: "iOS design directions",
    bucket: "studies",
    surface: "ios",
    status: "study",
    blurb:
      "Opus, Grok, and Kimi design the same notes companion independently; Grok then synthesizes Paper Tape × Ledger into Index Tape. One controlled matrix compares four directions across list, reader, light, and dark.",
    source: [
      "apps/ios/BlinkMobile/ContentView.swift",
      "design/studio/specs/ios-paper-tape.md",
      "design/studio/specs/ios-field-log.md",
      "design/studio/specs/ios-ledger.md",
      "design/studio/specs/ios-index-tape.md",
    ],
  },
  {
    href: "/studio/studies/note-panel",
    label: "Floating note panel",
    bucket: "studies",
    surface: "macos",
    status: "study",
    blurb:
      "The atomic unit: a glass NSPanel that is nothing but the note. Chrome earned on hover; shade to a 28px bar.",
  },
  {
    href: "/studio/studies/menubar-popover",
    label: "Menubar popover",
    bucket: "studies",
    surface: "macos",
    status: "study",
    blurb:
      "Home base. One field that searches, creates, and dictates; recents you can fling onto the desktop as panels.",
  },
  {
    href: "/studio/studies/command-palette",
    label: "Command palette",
    bucket: "studies",
    surface: "macos",
    status: "study",
    blurb:
      "⌘K over notes and verbs. ⌘↵ opens the hit as a spatial panel, not just a selection.",
  },
  {
    href: "/studio/studies/grid-overlay",
    label: "Grid overlay HUD",
    bucket: "studies",
    surface: "macos",
    status: "study",
    blurb:
      "Hyper+B: the 3×3 deploy grid made visible — slot occupancy, QWERTY chord keys, teachable spatial placement.",
  },
  {
    href: "/studio/studies/editor-modes",
    label: "Edit ↔ read mode",
    bucket: "studies",
    surface: "macos",
    status: "study",
    blurb:
      "Reading and writing are two faces of one surface: read mode is rendered typography on glass, edit mode is the source. Double-click or ⌘⇧P flips in place.",
  },
  {
    href: "/studio/studies/settings",
    label: "Settings",
    bucket: "studies",
    surface: "macos",
    status: "study",
    blurb:
      "Deliberately tiny. Three sections, one screen, no duplicated controls — the antidote to v1's 1,600-line settings panel.",
  },
  {
    href: "/studio/studies/style-permutations",
    label: "Style permutations",
    bucket: "studies",
    surface: "macos",
    status: "study",
    blurb:
      "Every sheet under one set of controls — accent, tint, radius, type, motion — with a live config.json you can copy straight into the app.",
  },
  {
    href: "/studio/studies/stacks",
    label: "Stacks in see-all",
    bucket: "studies",
    surface: "macos",
    status: "study",
    blurb:
      "Where idle notes go to be left alone: four metaphors for the pile on the corner of the desk — card pile, stacked sheets, shelf, messy desk. Visible, countable, leaf-through-able.",
  },
];

const defined = defineStudio({
  pages,
  surfaceOrder: ["vision", "doc", "ios", "macos"],
  defaultSurface: "macos",
  buckets: [
    { key: "foundations" },
    { key: "plans" },
    { key: "studies" },
  ],
  statuses: {
    locked: { tone: "ok", label: "LOCKED" },
    study: { tone: "info", label: "STUDY" },
    open: { tone: "warn", label: "OPEN" },
  },
  // Full human + local-agent iteration loop (annotations, pins, dictation →
  // sidecars under .studio/annotations that terminal agents read back).
  iteration: {},
});

export const {
  registry,
  buckets: BUCKETS,
  statusColors: STATUS_COLORS,
  StatusPill,
  renderStatusPill,
  palette: statusPalette,
  createIterationCommands,
  persistAnnotations,
  annotationsToDecisions,
  createWinnerDecision,
  createTurnDecision,
  getActiveTreatment,
} = defined;
