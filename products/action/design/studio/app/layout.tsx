import type { Metadata } from "next";
import { getHudsonThemeScript } from "hudsonkit/theme-script";
import "./globals.css";

export const metadata: Metadata = {
  title: "Action Studio",
  description:
    "Design studio for Action — the computer-use module for macOS. Studies land here before any Swift is touched.",
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
