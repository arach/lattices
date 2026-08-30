import { EditorView } from "@codemirror/view";
import { EditorSelection } from "@codemirror/state";
import type { Transaction } from "@codemirror/state";
import { applySheet } from "./sheet";
import { runEntrance } from "./entrance";
import { TypeOnController } from "./type-on";

/**
 * Native bridge for the Blink v2 editor.
 *
 * Two directions:
 *   JS  -> native : window.webkit.messageHandlers.blink.postMessage(obj)
 *   native -> JS  : window.blink.{ setContent, getContent, focus, setMode, getMode }
 *
 * The webkit handler is GUARDED so the page runs standalone in a plain browser
 * during development (postMessage becomes a no-op that logs to the console).
 */

/** The two editor surfaces. */
export type Mode = "edit" | "read";

/** Messages posted from JS to native. */
export type ReadyMessage = { type: "ready" };
export type ContentChangedMessage = { type: "contentChanged"; text: string };
export type SaveRequestedMessage = { type: "saveRequested" };
export type ModeChangedMessage = { type: "modeChanged"; mode: Mode };
export type OutboundMessage =
  | ReadyMessage
  | ContentChangedMessage
  | SaveRequestedMessage
  | ModeChangedMessage;

/** The global object native code calls into. */
export interface BlinkGlobal {
  setContent(text: string): void;
  getContent(): string;
  focus(): void;
  /**
   * Programmatically switch surface. Does NOT post a `modeChanged` message
   * (same no-echo discipline as setContent): native is the source of truth, so
   * telling it what it already knows would be a feedback loop.
   */
  setMode(mode: Mode): void;
  /** Current surface, "edit" | "read". */
  getMode(): Mode;
  /**
   * Apply theme overrides. For each entry, sets the CSS custom property on the
   * document root (`:root`). Keys arrive as full var names (e.g.
   * `"--blink-font-size": "14px"`). Unknown keys are set anyway (harmless).
   * Calling with `{}` is a no-op. No echo message is posted.
   */
  setTheme(vars: Record<string, string>): void;
  /**
   * Remove all inline `--blink-*` custom properties from `:root`, restoring the
   * stylesheet defaults. No echo message is posted.
   */
  resetTheme(): void;
  /**
   * Select the sheet template — the note's whole visual identity, drawn by the
   * web layer. Sets `data-sheet` on `<body>`. Idempotent; unknown names fall
   * back to `"glass"`. No echo message is posted (same no-echo discipline as
   * setContent/setMode/setTheme).
   */
  setSheet(name: string): void;
  /**
   * Play a content entrance effect (Arrival): "shimmer" | "drop" | "draw" |
   * "none". The native panel animates its own window (alpha, and the frame for
   * "drop"); this choreographs the content inside. `durationMs` is the base
   * duration. Unknown kinds and "none" are instant no-ops. No echo message.
   */
  enter(kind: string, durationMs: number): void;
  /**
   * Reveal an externally appended suffix at typing cadence. The complete
   * document is installed programmatically before the visual reveal starts,
   * so this never echoes contentChanged and a user edit always sees full text.
   */
  typeOn(base: string, suffix: string, source?: string | null): void;
  /** Snap any in-flight typed reveal to its complete document. */
  finishTypeOn(): void;
}

/** Minimal shape of the WKWebView message handler we depend on. */
interface WebkitMessageHandler {
  postMessage(message: unknown): void;
}
interface WebkitBridge {
  messageHandlers?: {
    blink?: WebkitMessageHandler;
  };
}

declare global {
  interface Window {
    webkit?: WebkitBridge;
    blink?: BlinkGlobal;
  }
}

/**
 * Post a message to the native side. If the webkit handler is absent (running in
 * a normal browser for dev), this is a harmless no-op with a console trace.
 */
export function postToNative(message: OutboundMessage): void {
  const handler = window.webkit?.messageHandlers?.blink;
  if (handler) {
    handler.postMessage(message);
  } else {
    // Standalone/dev mode: no native host. Never throw.
    // eslint-disable-next-line no-console
    console.debug("[BLINK] (no native host) postMessage:", message);
  }
}

/**
 * Marks a dispatched transaction as a programmatic content replacement so the
 * update listener can distinguish it from real user edits. Any transaction
 * carrying this annotation-equivalent user event is treated as non-user.
 *
 * We implement the "don't echo programmatic sets" rule purely via user-event
 * inspection: setContent dispatches with NO user event, so isUserEvent(...) is
 * false for all of them and contentChanged is not posted.
 */
const USER_EDIT_EVENTS = ["input", "delete", "move", "undo", "redo"] as const;

/** True if a transaction represents a user-initiated edit we should report. */
export function isReportableUserEdit(tr: Transaction): boolean {
  return USER_EDIT_EVENTS.some((ev) => tr.isUserEvent(ev));
}

/**
 * Mode machinery the bridge coordinates with. Implemented in main.ts (it owns
 * the reader element and the editor DOM), passed in here so `setContent` can
 * re-render the reader while in read mode and `setMode`/`getMode` can drive the
 * flip without echoing a `modeChanged` message.
 */
export interface ModeController {
  getMode(): Mode;
  /** Programmatic (no `modeChanged` echo). */
  setMode(mode: Mode): void;
  /** Re-render the read surface from the given source (used by setContent). */
  renderRead(text: string): void;
  /** Begin/update read mode's in-place typed reveal. */
  beginReadTypeOn(base: string, suffix: string): void;
  updateReadTypeOn(text: string): void;
}

/**
 * Install `window.blink` (native -> JS API) around a live EditorView.
 *
 * setContent:
 *   - replaces the whole document
 *   - dispatches WITHOUT a user event, so the change listener will NOT post
 *     contentChanged (this is the exact stale-feedback loop that corrupted
 *     notes in v1)
 *   - preserves scroll position
 *   - places the cursor at the end ONLY on the very first set
 *   - re-renders the reader if we are currently in read mode
 *
 * setMode / getMode delegate to the ModeController. setMode is programmatic and
 * never posts `modeChanged` (native already knows).
 */
export function installBlinkGlobal(
  view: EditorView,
  modes: ModeController
): BlinkGlobal {
  let hasSetOnce = false;
  const typeOn = new TypeOnController(view, {
    beginTypeOn: (base, suffix) => modes.beginReadTypeOn(base, suffix),
    updateTypeOn: (text) => modes.updateReadTypeOn(text),
    render: (text) => modes.renderRead(text),
  });

  /** Programmatic whole-document replacement shared by setContent/typeOn. */
  function replaceContent(text: string): void {
    const current = view.state.doc.toString();
    const firstSet = !hasSetOnce;
    hasSetOnce = true;

    // Preserve scroll position across the replacement.
    const scroller = view.scrollDOM;
    const prevScrollTop = scroller.scrollTop;
    const prevScrollLeft = scroller.scrollLeft;

    if (current === text && !firstSet) {
      return;
    }

    const docLength = text.length;
    const selection = firstSet
      ? EditorSelection.cursor(docLength)
      : // Keep the caret in bounds; clamp existing selection to new length.
        view.state.selection.main.head <= docLength
        ? undefined
        : EditorSelection.cursor(docLength);

    view.dispatch({
      changes: { from: 0, to: view.state.doc.length, insert: text },
      // Deliberately NO userEvent annotation -> not a reportable edit.
      ...(selection ? { selection } : {}),
      scrollIntoView: false,
    });

    // Restore scroll after the DOM settles.
    scroller.scrollTop = prevScrollTop;
    scroller.scrollLeft = prevScrollLeft;
  }

  const api: BlinkGlobal = {
    setContent(text: string): void {
      typeOn.finish();
      replaceContent(text);

      // If the reader is currently on screen, keep it in sync with the doc.
      if (modes.getMode() === "read") {
        modes.renderRead(text);
      }
    },

    getContent(): string {
      return view.state.doc.toString();
    },

    focus(): void {
      view.focus();
    },

    setMode(mode: Mode): void {
      modes.setMode(mode);
    },

    getMode(): Mode {
      return modes.getMode();
    },

    setTheme(vars: Record<string, string>): void {
      const root = document.documentElement.style;
      // Full var names arrive as keys; set each as-is. Unknown keys are harmless.
      for (const [key, value] of Object.entries(vars)) {
        root.setProperty(key, value);
      }
    },

    resetTheme(): void {
      const root = document.documentElement.style;
      // Collect first (mutating the list mid-iteration skips entries).
      const toRemove: string[] = [];
      for (let i = 0; i < root.length; i++) {
        const name = root.item(i);
        if (name.startsWith("--blink-")) {
          toRemove.push(name);
        }
      }
      for (const name of toRemove) {
        root.removeProperty(name);
      }
    },

    setSheet(name: string): void {
      applySheet(name);
    },

    enter(kind: string, durationMs: number): void {
      runEntrance(kind, durationMs);
    },

    typeOn(base: string, suffix: string, source?: string | null): void {
      // Two rapid appends: complete the old reveal first, then install the new
      // full truth before hiding its suffix. No programmatic dispatch echoes.
      typeOn.finish();
      const full = base + suffix;
      replaceContent(full);
      typeOn.start(base, suffix, source);
    },

    finishTypeOn(): void {
      typeOn.finish();
    },
  };

  window.blink = api;
  return api;
}
