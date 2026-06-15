/**
 * Inline code samples shown in the package and recipe pages. Kept as
 * plain string constants so we can render them through CodeViewer
 * without filesystem I/O at request time.
 */

export const REGISTRY_SAMPLE = `import { createRegistry, type StudioPage } from "studio/registry";

export type Bucket = "foundations" | "package" | "recipes";
export type Surface = "vision" | "api" | "runtime";
export type Status = "stable" | "preview" | "wip";

type Page = StudioPage<Bucket, Surface, Status>;

export const pages: Page[] = [
  { href: "/studio", label: "What Studio is",
    bucket: "foundations", surface: "vision", status: "stable" },
  { href: "/studio/package/registry", label: "studio/registry",
    bucket: "package", surface: "api", status: "stable" },
];

export const registry = createRegistry<Bucket, Surface, Status>({
  pages,
  surfaceOrder: ["vision", "api", "runtime"],
  defaultSurface: "api",
  bucketLabel: (b) => ({
    foundations: "Foundations",
    package: "Package",
    recipes: "Recipes",
  }[b]),
  surfaceLabel: (s) => ({
    vision: "Vision",
    api: "API",
    runtime: "Runtime",
  }[s]),
});
`;

export const SHELL_SAMPLE = `import { StudioHudsonApp } from "studio/app-shell";
import { NextRouterProvider } from "studio/router/next";

export function MyStudioApp() {
  return (
    <StudioHudsonApp
      app={{ id: "my-studio", name: "My Studio" }}
      registry={registry}
      buckets={BUCKETS}
      statusColors={STATUS_COLORS}
      renderStatusPill={(s) => statusPalette.StatusPill({ status: s })}
      renderPage={renderPage}
      homeHref="/studio"
      routerProvider={NextRouterProvider}
    />
  );
}
`;

export const STATUS_SAMPLE = `import { createStatusPalette } from "studio/atoms";

type Status = "stable" | "preview" | "wip";

export const statusPalette = createStatusPalette<Status>({
  stable:  { tone: "ok",   label: "STABLE" },
  preview: { tone: "warn", label: "PREVIEW" },
  wip:     { tone: "info", label: "WIP" },
});

// statusPalette.StatusPill, statusToTone, statusToColor are now typed
// against the Status union — passing "foo" is a compile error.
`;

export const ROUTER_SAMPLE = `// layout.tsx
import { NextRouterProvider } from "studio/router/next";

export default function RootLayout({ children }) {
  return (
    <html>
      <body>
        <NextRouterProvider>{children}</NextRouterProvider>
      </body>
    </html>
  );
}

// Inside any studio component
import { useStudioRouter } from "studio/router";

function Crumb() {
  const { Link, usePathname } = useStudioRouter();
  const pathname = usePathname();
  return <Link href="/studio">home · {pathname}</Link>;
}
`;

export const THEME_SAMPLE = `import { getHudsonThemeScript } from "hudsonkit/theme-script";
import "hudsonkit/styles";
import "studio/theme.css";
import "studio/shell.css";

export default function RootLayout({ children }) {
  return (
    <html suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: getHudsonThemeScript({
          storageKey: "studio.theme",
          defaultTheme: "dark",
          defaultTemplate: "hudson",
        }) }} />
      </head>
      <body>{children}</body>
    </html>
  );
}
`;

export const DOC_SAMPLE = `import { EngMarkdown } from "studio/doc";

const body = \`
## ADR-007 - Use a typed registry

Studio's sidebar and page strip both read from the same source: a
\\\`createRegistry\\\` output keyed by \\\`href\\\`. We made it generic over
the consumer's \\\`Bucket\\\` / \\\`Surface\\\` / \\\`Status\\\` unions so the
package never has to know your taxonomy.
\`;

export function Page() {
  return <EngMarkdown body={body} />;
}
`;

export const CODE_SAMPLE = `import { CodeViewer } from "studio/code";

export function ViewSource({ content }: { content: string }) {
  return (
    <CodeViewer
      content={content}
      filename="studioRegistry.ts"
      themeDetection={{ mode: "data-attribute", attr: "data-hudson-theme" }}
    />
  );
}
`;

export const ADOPTION_RECIPE = `# Adopt Studio in 10 steps

1. Add \`studio\` and \`hudsonkit\` as bun workspace members at the
   consumer monorepo root.
2. Declare \`"studio": "workspace:*"\` in the consuming package.
3. Mount \`<HudsonThemeScript />\` in \`<head>\` and wrap children with
   \`<ThemeProvider>\`. Import \`hudsonkit/styles\` and \`studio/theme.css\`.
4. Add \`transpilePackages: ["studio", "hudsonkit"]\` in \`next.config.ts\`.
5. Extend the Tailwind \`content\` array to scan
   \`node_modules/studio/src/**\` and \`node_modules/hudsonkit/src/**\`.
6. Declare your \`Bucket\` / \`Surface\` / \`Status\` unions and call
   \`createRegistry\` with your pages.
7. Bind a typed \`StatusPalette\` with \`createStatusPalette\`.
8. Wrap the tree in \`<NextRouterProvider>\` so studio components can
   resolve \`Link\` and \`usePathname\`.
9. Compose the shell with \`StudioShell\` + \`StudioSidebar\` + \`PageStrip\`,
   or use \`StudioHudsonApp\` if you want the Hudson AppShell wiring done
   for you.
10. Replace any local \`--studio-*\` CSS vars, status pill component, or
    code-mirror theme with the package versions.
`;
