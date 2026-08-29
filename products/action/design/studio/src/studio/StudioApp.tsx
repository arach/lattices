"use client";

import { createElement } from "react";
import { Play, Compass } from "lucide-react";
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
        id: "action-studio",
        name: "Action Studio",
        description: "Design studio for Action — computer use on macOS.",
        icon: createElement(Play, { size: 14 }),
        leftPanel: {
          title: "Action",
          icon: createElement(Compass, { size: 12 }),
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
        storageKey: "studio.app.theme",
        defaultTheme: "dark",
        defaultTemplate: "hudson",
      }}
    />
  );
}
