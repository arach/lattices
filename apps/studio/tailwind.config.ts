import type { Config } from "tailwindcss";

export default {
  content: [
    "./index.html",
    "./src/**/*.{ts,tsx}",
    "../../node_modules/studio/src/**/*.{ts,tsx}",
  ],
  darkMode: ["class", '[data-theme="dark"]'],
  theme: {
    extend: {
      fontFamily: {
        sans: ['"Space Grotesk"', "system-ui", "sans-serif"],
        mono: ['"JetBrains Mono"', "ui-monospace", "monospace"],
      },
      colors: {
        studio: {
          canvas: "var(--studio-canvas)",
          edge: "var(--studio-edge)",
          ink: "var(--studio-ink)",
          "ink-faint": "var(--studio-ink-faint)",
        },
        status: {
          "ok-fg": "var(--status-ok-fg)",
          "ok-bg": "var(--status-ok-bg)",
          "warn-fg": "var(--status-warn-fg)",
          "warn-bg": "var(--status-warn-bg)",
          "error-fg": "var(--status-error-fg)",
          "error-bg": "var(--status-error-bg)",
          "info-fg": "var(--status-info-fg)",
          "info-bg": "var(--status-info-bg)",
          "neutral-fg": "var(--status-neutral-fg)",
          "neutral-bg": "var(--status-neutral-bg)",
        },
      },
      letterSpacing: {
        eyebrow: "0.22em",
      },
    },
  },
  plugins: [],
} satisfies Config;
