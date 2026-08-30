import type { Metadata } from "next";
import { getHudsonThemeScript } from "hudsonkit/theme-script";
import "./globals.css";

export const metadata: Metadata = {
  title: "Blink Studio",
  description:
    "Design studio for Blink v2 — spatial note panels, menubar capture, and command-flow studies before the Swift/AppKit build.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <script
          dangerouslySetInnerHTML={{
            __html: getHudsonThemeScript({
              storageKey: "blink.studio.theme",
              defaultTheme: "dark",
              defaultTemplate: "hudson",
            }),
          }}
        />
      </head>
      <body>{children}</body>
    </html>
  );
}
