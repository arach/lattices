import type { Metadata } from "next";
import { getHudsonThemeScript } from "hudsonkit/theme-script";
import "./globals.css";

export const metadata: Metadata = {
  title: "Lattices Studio",
  description:
    "Design studio for the Lattices macOS workspace manager — overlay, HUD, and command-flow studies before SwiftUI.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <script
          dangerouslySetInnerHTML={{
            __html: getHudsonThemeScript({
              storageKey: "studio.theme",
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
