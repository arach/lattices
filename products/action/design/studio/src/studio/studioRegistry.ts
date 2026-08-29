import { defineStudio, type StudioPage } from "studio/registry";

/**
 * Action studio registry — the single source of truth for the sidebar nav.
 * Each study is one route; add an entry here and it surfaces automatically.
 *
 * The `source` array on a page is the point of the whole studio: a study sits
 * beside the code it describes, so the mock and the Swift it argues about are
 * one click apart.
 */

export type Bucket = "foundations" | "studies";
export type Surface = "launcher" | "overlay";
export type Status = "concept" | "in-flight" | "shipped";

export type ActionPage = StudioPage<Bucket, Surface, Status>;

export const HOME_HREF = "/studio";

export const pages: readonly ActionPage[] = [
  {
    href: HOME_HREF,
    label: "Action Studio",
    bucket: "foundations",
    surface: "launcher",
    status: "concept",
    blurb:
      "Design surface for Action, the computer-use module for macOS. Studies land here before SwiftUI gets touched.",
  },
  {
    href: "/studio/foundations/tokens",
    label: "Tokens — palette and type",
    bucket: "foundations",
    surface: "launcher",
    status: "shipped",
    blurb:
      "Three surfaces, one ink ramp each, and exactly three colours that each mean something. Plus the named type roles — reaching past them is how a surface ends up with ten sizes two points apart.",
    source: [
      "native/engine/Sources/ActionThemeBuiltin.swift",
      "native/engine/Sources/ActionTypography.swift",
      "design/tokens/action.css",
    ],
  },
  {
    href: "/studio/studies/window",
    label: "The window — five sections",
    bucket: "studies",
    // Was SHIPPED while it transcribed the app. It now argues with it in three
    // structural ways — Runs and Library merged into Traces, Settings' pane
    // enum replaced by one scrolling page, and Home given a driving state the
    // app has never drawn — so the badge has to say so. A studio that keeps
    // calling itself shipped while it runs ahead of the code is the exact
    // failure the SHIPPED/CONCEPT rule exists to prevent.
    status: "in-flight",
    blurb:
      "The launcher at true pixel geometry, navigable, at all three window sizes. Now ahead of the Swift in three places: Traces is Runs and Library merged, Settings is one page instead of five panes, and Home has a live drive state the app does not yet draw.",
    source: [
      "native/engine/Sources/ActionLauncherRootView.swift",
      "native/engine/Sources/ActionHomeView.swift",
      "native/engine/Sources/ActionWorkspaceView.swift",
      "native/engine/Sources/ActionWindowChrome.swift",
    ],
  },
  {
    href: "/studio/studies/scenarios",
    label: "Scenarios — one table, three states",
    bucket: "studies",
    surface: "launcher",
    status: "shipped",
    blurb:
      "A scenario is a list of instructions and stays one the whole way through. Plan, running and review are three states of one ruled table, not three different objects. Replaced four nested cards and a 280pt notes rail.",
    source: [
      "native/engine/Sources/ActionWorkspaceView.swift",
      "native/engine/Sources/ActionSettingsComponents.swift",
    ],
  },
  {
    href: "/studio/studies/step-telemetry",
    label: "Step telemetry — the missing fact",
    bucket: "studies",
    surface: "launcher",
    status: "concept",
    blurb:
      "Which step is executing, and what each one cost. The runtime knows and nothing records it, so the plan cannot be annotated with its own run. Writing it unlocks the live row, a truthful TOOK column, and click-a-row-to-scrub — with no new layout.",
    source: [
      "native/engine/Sources/ActionScenarioModels.swift",
      "native/engine/Sources/ActionLauncherViewModel.swift",
    ],
  },
];

const defined = defineStudio({
  pages,
  surfaceOrder: ["launcher", "overlay"],
  defaultSurface: "launcher",
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

export { StatusPill as ActionStatusPill };
