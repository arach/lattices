type Theme = "light" | "dark";

export function ThemeToggle({
  theme,
  onToggle,
}: {
  theme: Theme;
  onToggle: () => void;
}) {
  const next = theme === "dark" ? "light" : "dark";

  return (
    <button
      type="button"
      className="theme-toggle"
      onClick={onToggle}
      role="switch"
      aria-label="Dark theme"
      aria-checked={theme === "dark"}
      title={`Switch to ${next} theme`}
    >
      <span className={`theme-toggle-option${theme === "light" ? " is-active" : ""}`}>
        <SunIcon />
      </span>
      <span className={`theme-toggle-option${theme === "dark" ? " is-active" : ""}`}>
        <MoonIcon />
      </span>
    </button>
  );
}

function SunIcon() {
  return (
    <svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round">
      <circle cx="12" cy="12" r="4" />
      <path d="M12 3v2M12 19v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M3 12h2M19 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4" />
    </svg>
  );
}

function MoonIcon() {
  return (
    <svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
      <path d="M16.5 3.5A8 8 0 1 0 20.5 14 6.5 6.5 0 0 1 16.5 3.5z" />
    </svg>
  );
}
