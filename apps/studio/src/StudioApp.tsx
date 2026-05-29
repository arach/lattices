import { useEffect, useState } from "react";
import { StudioChrome } from "./components/StudioChrome";
import { DocPage } from "./components/DocPage";
import { HomePage } from "./components/HomePage";
import { StudioPage } from "./components/StudioPage";

type Route =
  | { kind: "home" }
  | { kind: "doc"; slug: string }
  | { kind: "studio"; slug: string; exhibit?: string }
  | { kind: "not-found" };

function normalizePath(path: string): string {
  if (!path) return "/";
  const trimmed = path.replace(/\/+$/, "");
  return trimmed === "" ? "/" : trimmed;
}

function resolveRoute(path: string): Route {
  if (path === "/" || path === "") return { kind: "home" };
  const docMatch = path.match(/^\/eng\/([a-z0-9-]+)$/i);
  if (docMatch) return { kind: "doc", slug: docMatch[1] };
  const studioMatch = path.match(/^\/studio\/([a-z0-9-]+)(?:\/([a-z0-9-]+))?$/i);
  if (studioMatch)
    return {
      kind: "studio",
      slug: studioMatch[1],
      exhibit: studioMatch[2] || undefined,
    };
  return { kind: "not-found" };
}

function shouldIgnoreClick(event: MouseEvent): boolean {
  return (
    event.defaultPrevented ||
    event.button !== 0 ||
    event.metaKey ||
    event.ctrlKey ||
    event.shiftKey ||
    event.altKey
  );
}

function shouldIgnoreAnchor(anchor: HTMLAnchorElement): boolean {
  if (anchor.target && anchor.target !== "_self") return true;
  if (anchor.hasAttribute("download")) return true;
  return false;
}

export default function StudioApp() {
  const [path, setPath] = useState(() => normalizePath(window.location.pathname));
  const route = resolveRoute(path);

  useEffect(() => {
    const syncPath = () => setPath(normalizePath(window.location.pathname));
    window.addEventListener("popstate", syncPath);
    return () => window.removeEventListener("popstate", syncPath);
  }, []);

  useEffect(() => {
    const handleClick = (event: MouseEvent) => {
      if (shouldIgnoreClick(event)) return;
      const target = event.target instanceof Element ? event.target : null;
      const anchor = target?.closest<HTMLAnchorElement>("a[href]");
      if (!anchor || shouldIgnoreAnchor(anchor)) return;

      const url = new URL(anchor.href, window.location.href);
      if (url.origin !== window.location.origin) return;

      const nextPath = normalizePath(url.pathname);
      if (resolveRoute(nextPath).kind === "not-found") return;

      event.preventDefault();
      window.history.pushState({}, "", `${url.pathname}${url.search}${url.hash}`);
      setPath(nextPath);
      if (!url.hash) window.scrollTo({ top: 0, behavior: "instant" });
    };
    document.addEventListener("click", handleClick);
    return () => document.removeEventListener("click", handleClick);
  }, []);

  let body;
  if (route.kind === "home") body = <HomePage />;
  else if (route.kind === "doc") body = <DocPage slug={route.slug} />;
  else if (route.kind === "studio")
    body = <StudioPage slug={route.slug} exhibit={route.exhibit} />;
  else
    body = (
      <main className="px-8 py-12">
        <h1 className="font-mono text-xs uppercase tracking-[0.18em] text-studio-ink-faint">
          Not found
        </h1>
        <p className="mt-3 text-sm">
          <a className="underline" href="/">
            Back home
          </a>
        </p>
      </main>
    );

  return <StudioChrome pathname={path}>{body}</StudioChrome>;
}
