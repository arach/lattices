/**
 * Key chords for press-key. An agent writes a shortcut however it reads it: "cmd+l",
 * "Cmd-Shift-T", "⌘⇧T", ["cmd", "l"], or key + modifiers. All of them come out as one
 * named key and canonical modifiers, so the host never sees a chord it would type as text.
 */

export type KeyModifier = "cmd" | "shift" | "opt" | "ctrl";

export interface KeyChord {
  key: string;
  modifiers: KeyModifier[];
}

/** The host's key table (`keyCodes` in native/engine/Sources/ActionHostMain.swift). */
const NAMED_KEYS = [
  "return", "tab", "space", "delete", "forwarddelete", "escape",
  "up", "down", "left", "right", "home", "end", "pageup", "pagedown",
  "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12",
] as const;
const CHARACTER_KEYS = "abcdefghijklmnopqrstuvwxyz0123456789=-][';\\,/.`";

const KEY_ALIASES: Record<string, string> = {
  enter: "return", ret: "return", cr: "return", "↵": "return", "⏎": "return", "↩": "return",
  esc: "escape", "⎋": "escape",
  backspace: "delete", del: "delete", "⌫": "delete",
  fwddelete: "forwarddelete", "forward-delete": "forwarddelete", "⌦": "forwarddelete",
  spacebar: "space", " ": "space", "␣": "space",
  "⇥": "tab",
  arrowup: "up", arrowdown: "down", arrowleft: "left", arrowright: "right",
  "↑": "up", "↓": "down", "←": "left", "→": "right",
  pgup: "pageup", pgdn: "pagedown", pgdown: "pagedown",
  "page-up": "pageup", "page-down": "pagedown", page_up: "pageup", page_down: "pagedown",
  "↖": "home", "↘": "end", "⇞": "pageup", "⇟": "pagedown",
};

const MODIFIER_ALIASES: Record<string, KeyModifier> = {
  cmd: "cmd", command: "cmd", meta: "cmd", super: "cmd", "⌘": "cmd",
  shift: "shift", "⇧": "shift",
  opt: "opt", option: "opt", alt: "opt", "⌥": "opt",
  ctrl: "ctrl", control: "ctrl", "⌃": "ctrl",
};

const MODIFIER_ORDER: KeyModifier[] = ["ctrl", "opt", "shift", "cmd"];
const MODIFIER_SYMBOLS = /[⌘⇧⌥⌃]/g;

/** Splits on + or -, keeping a literal "-" or "+" key: "cmd+-" is cmd and "-". */
function splitChord(chord: string): string[] {
  const parts: string[] = [];
  let current = "";
  for (const char of chord) {
    if ((char === "+" || char === "-") && current.trim() !== "") {
      parts.push(current.trim());
      current = "";
    } else {
      current += char;
    }
  }
  if (current.trim() !== "" || current === " ") {
    parts.push(current === " " ? " " : current.trim());
  }
  return parts;
}

function canonicalKey(token: string): string | undefined {
  const lower = token.toLowerCase();
  const key = KEY_ALIASES[lower] ?? lower;
  if ((NAMED_KEYS as readonly string[]).includes(key)) {
    return key;
  }
  return key.length === 1 && CHARACTER_KEYS.includes(key) ? key : undefined;
}

function unknownKey(token: string): Error {
  return new Error(
    `press-key: unknown key "${token}". Use a letter, digit or one of ${NAMED_KEYS.join(", ")}, ` +
      `with modifiers cmd, shift, opt, ctrl ("cmd+l", "cmd+shift+t", "⌘L"). ` +
      `To enter text, use a type act instead.`,
  );
}

/**
 * Reads a press-key input into one chord. `key` may itself be a chord, `keys` is a
 * list of parts (each of which may be a chord too), and `modifiers` adds to either.
 */
export function parseKeyChord(input: { key?: unknown; keys?: unknown; modifiers?: unknown }): KeyChord {
  const tokens: string[] = [];
  const pushChord = (value: unknown) => {
    if (typeof value !== "string" || value === "") {
      return;
    }
    // "⌘⇧T" → "⌘+⇧+T"
    const spaced = value.replace(MODIFIER_SYMBOLS, (symbol) => `${symbol}+`);
    tokens.push(...splitChord(spaced));
  };
  if (Array.isArray(input.keys)) {
    for (const part of input.keys) {
      pushChord(part);
    }
  }
  pushChord(input.key);

  const modifiers = new Set<KeyModifier>();
  if (Array.isArray(input.modifiers)) {
    for (const value of input.modifiers) {
      const modifier = typeof value === "string" ? MODIFIER_ALIASES[value.toLowerCase()] : undefined;
      if (!modifier) {
        throw new Error(`press-key: unknown modifier "${String(value)}". Use cmd, shift, opt or ctrl.`);
      }
      modifiers.add(modifier);
    }
  }

  let key: string | undefined;
  for (const token of tokens) {
    const modifier = MODIFIER_ALIASES[token.toLowerCase()];
    if (modifier) {
      modifiers.add(modifier);
      continue;
    }
    if (key !== undefined) {
      throw new Error(`press-key: "${tokens.join("+")}" names two keys (${key}, ${token}). Press one key per act.`);
    }
    key = canonicalKey(token);
    if (!key) {
      throw unknownKey(token);
    }
  }
  if (!key) {
    throw new Error('press-key needs a key: input.key such as "return" or "cmd+l".');
  }
  return { key, modifiers: MODIFIER_ORDER.filter((modifier) => modifiers.has(modifier)) };
}
