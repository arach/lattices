"use client";

import { createElement } from "react";
import { Eye, StickyNote } from "lucide-react";
import { StudioHudsonApp } from "studio/app-shell";
import { NextRouterProvider } from "studio/router/next";
import { renderStudioPage } from "@/studio/StudioPages";
import {
  BUCKETS,
  HOME_HREF,
  STATUS_COLORS,
  registry,
  statusPalette,
} from "@/studio/studioRegistry";

export function StudioApp() {
  return (
    <StudioHudsonApp
      app={{
        id: "blink",
        name: "Blink Studio",
        description:
          "Design studio for Blink across macOS and iOS — spatial note panels on the desk, offline-first recall in the pocket.",
        icon: createElement(StickyNote, { size: 14 }),
        leftPanel: {
          title: "Blink",
          icon: createElement(Eye, { size: 12 }),
        },
      }}
      registry={registry}
      buckets={BUCKETS}
      statusColors={STATUS_COLORS}
      renderStatusPill={(status) => statusPalette.StatusPill({ status })}
      renderPage={renderStudioPage}
      homeHref={HOME_HREF}
      routerProvider={NextRouterProvider}
      theme={{
        storageKey: "blink.studio.theme",
        defaultTheme: "dark",
        defaultTemplate: "hudson",
      }}
    />
  );
}
