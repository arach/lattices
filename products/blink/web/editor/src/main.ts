import { EditorState } from "@codemirror/state";
import {
  EditorView,
  keymap,
  drawSelection,
  dropCursor,
  rectangularSelection,
  crosshairCursor,
} from "@codemirror/view";
import {
  history,
  historyKeymap,
  defaultKeymap,
  indentWithTab,
} from "@codemirror/commands";
import { markdown, markdownLanguage } from "@codemirror/lang-markdown";
import { syntaxHighlighting, defaultHighlightStyle } from "@codemirror/language";

import { blinkEditorTheme } from "./theme";
import {
  postToNative,
  installBlinkGlobal,
  isReportableUserEdit,
} from "./bridge";
import type { Mode, ModeController } from "./bridge";
import { Reader } from "./reader";
import { applySheet, DEFAULT_SHEET } from "./sheet";
import { typeOnExtension } from "./type-on";

/**
 * Blink v2 editor entry point.
 *
 * Minimal-chrome CodeMirror 6 markdown editor designed to be hosted inside a
 * native macOS NSPanel via WKWebView. NO line-number gutter, NO fold gutter,
 * word wrap ON, transparent surface.
 *
 * Two surfaces flip in place on the same glass:
 *   - "edit": the CM6 editor (the single EditorView instance, always alive)
 *   - "read": the note rendered as markdown typography in `.blink-reader`
 *
 * The EditorView is never destroyed on flip — it is hidden and shown. Read mode
 * re-renders its content from the current document.
 */

function mount(): void {
  const parent = document.getElementById("editor");
  if (!parent) {
    throw new Error("[BLINK] #editor mount point not found");
  }
  const readerEl = document.getElementById("reader");
  if (!readerEl) {
    throw new Error("[BLINK] #reader mount point not found");
  }
  const reader = new Reader(readerEl);
  reader.hide();

  // Establish a default sheet before native pushes its choice (which lands via
  // window.blink.setSheet after `ready`). Keeps the page well-defined if it ever
  // runs without a native host.
  applySheet(DEFAULT_SHEET);

  // The mode state machine. `mode` starts in "edit". `flip` is the single
  // internal transition; `postEcho` decides whether native is told (only for
  // user-initiated flips, never programmatic setMode — same no-echo discipline
  // as setContent).
  let mode: Mode = "edit";

  const view = new EditorView({
    parent,
    state: EditorState.create({
      doc: "",
      extensions: [
        // Language: markdown (GFM base, no gutters requested by design).
        markdown({ base: markdownLanguage }),

        // Word wrap ON — long lines wrap instead of scrolling horizontally.
        EditorView.lineWrapping,

        // Standard history + keymaps (no gutter-related extensions).
        history(),
        drawSelection(),
        dropCursor(),
        rectangularSelection(),
        crosshairCursor(),

        // Typed reveal decorations hide only the not-yet-visible suffix. The
        // CodeMirror document beneath is complete from frame zero.
        typeOnExtension,

        // Fallback syntax highlighting for anything the theme does not cover.
        syntaxHighlighting(defaultHighlightStyle, { fallback: true }),

        keymap.of([
          // ⌘S / Ctrl-S -> ask native to save; swallow the browser default.
          {
            key: "Mod-s",
            preventDefault: true,
            run: () => {
              postToNative({ type: "saveRequested" });
              return true;
            },
          },
          // ⌘⇧P -> user-initiated flip to read mode (echoes modeChanged).
          {
            key: "Mod-Shift-p",
            preventDefault: true,
            run: () => {
              toggleMode();
              return true;
            },
          },
          ...defaultKeymap,
          ...historyKeymap,
          indentWithTab,
        ]),

        // Report ONLY real user edits back to native (never programmatic sets).
        EditorView.updateListener.of((update) => {
          if (!update.docChanged) return;
          const isUser = update.transactions.some(isReportableUserEdit);
          if (!isUser) return;
          // A real user edit wins over presentation: remove the reveal mask
          // before notifying native. The underlying doc was already complete,
          // so this text contains the append and the user's edit in order.
          window.blink?.finishTypeOn();
          postToNative({
            type: "contentChanged",
            text: update.state.doc.toString(),
          });
        }),

        // Blink theme: transparent surface, system font, markdown token colors.
        blinkEditorTheme,
      ],
    }),
  });

  /**
   * Apply a mode transition. Preserves scroll position proportionally between
   * the two surfaces (best effort). When entering read mode, re-render from the
   * live document. When `echo` is true (user-initiated), tell native.
   */
  function applyMode(next: Mode, echo: boolean): void {
    if (next === mode) return;

    if (next === "read") {
      // edit -> read: capture the editor's proportional scroll, render, restore.
      const scroller = view.scrollDOM;
      const editMax = scroller.scrollHeight - scroller.clientHeight;
      const fraction = editMax > 0 ? scroller.scrollTop / editMax : 0;

      reader.renderCurrent(view.state.doc.toString());
      parent!.style.display = "none";
      reader.show();
      reader.setScrollFraction(fraction);
    } else {
      // read -> edit: map the reader's proportional scroll back onto the editor.
      const fraction = reader.getScrollFraction();
      reader.hide();
      parent!.style.display = "block";

      const scroller = view.scrollDOM;
      const editMax = scroller.scrollHeight - scroller.clientHeight;
      scroller.scrollTop = editMax > 0 ? Math.round(fraction * editMax) : 0;
    }

    mode = next;
    if (echo) {
      postToNative({ type: "modeChanged", mode });
    }
  }

  /** User-initiated toggle (double-click / ⌘⇧P): flips and echoes to native. */
  function toggleMode(): void {
    applyMode(mode === "edit" ? "read" : "edit", true);
  }

  // Double-click anywhere in the reader -> user-initiated switch to edit + focus.
  readerEl.addEventListener("dblclick", () => {
    if (mode !== "read") return;
    applyMode("edit", true);
    view.focus();
  });

  // ⌘⇧P in READ mode: CM's keymap is inert when the editor is hidden, so we need
  // a window-level listener. Guard it to fire ONLY in read mode (edit mode is
  // handled by the CM keymap entry above) to avoid double-toggling.
  window.addEventListener("keydown", (e) => {
    if (mode !== "read") return;
    // Mod = ⌘ on macOS, Ctrl elsewhere. WKWebView host is macOS -> metaKey.
    const mod = e.metaKey || e.ctrlKey;
    if (mod && e.shiftKey && e.key.toLowerCase() === "p") {
      e.preventDefault();
      toggleMode();
    }
  });

  // Mode controller handed to the bridge so setContent can re-render the reader
  // and setMode/getMode can drive the flip. setMode here is PROGRAMMATIC: it
  // never echoes modeChanged (native is the source of truth).
  const modeController: ModeController = {
    getMode: () => mode,
    setMode: (m) => applyMode(m, false),
    renderRead: (text) => reader.render(text),
    beginReadTypeOn: (base, suffix) => reader.beginTypeOn(base, suffix),
    updateReadTypeOn: (text) => reader.updateTypeOn(text),
  };

  // Expose window.blink (native -> JS API) around this view.
  installBlinkGlobal(view, modeController);

  // Focus on load, then announce readiness to native.
  view.focus();
  postToNative({ type: "ready" });
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", mount, { once: true });
} else {
  mount();
}
