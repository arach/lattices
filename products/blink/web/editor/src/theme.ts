import { EditorView } from "@codemirror/view";
import { HighlightStyle, syntaxHighlighting } from "@codemirror/language";
import { tags as t } from "@lezer/highlight";
import type { Extension } from "@codemirror/state";

/**
 * Blink v2 editor theme.
 *
 * Design intent ("the note is the window"): the editor draws NO surface of its
 * own. The native glass NSPanel behind the WKWebView provides the background,
 * blur, and shadow. So html/body and every CodeMirror background layer are fully
 * transparent, and we only paint text, caret, and selection.
 *
 * THEMING: every visual value below is expressed as a `var(--blink-…)` CSS
 * custom property. `var(...)` strings are valid values in CodeMirror theme specs
 * and in HighlightStyle inline styles (both render to plain CSS), so the whole
 * theme is runtime-themable. The variables are DECLARED with their defaults on
 * `:root` in the bundled stylesheet (see build.mjs PAGE_CSS); native code
 * overrides them via `window.blink.setTheme(...)`.
 *
 * NOTE on heading sizes: `--blink-h1-size` etc. are the READER sizes (20/17/15).
 * The editor renders markdown *source* at a slightly smaller scale, so editor
 * heading sizes are derived as `calc(var(--blink-hN-size) - 3px)` -> 17/14/12.
 * Font weights are hard-coded (not themable this pass).
 */

/** Base view theme: transparent everywhere, themed font, generous line height. */
export const blinkTheme: Extension = EditorView.theme(
  {
    "&": {
      color: "var(--blink-text)",
      backgroundColor: "transparent",
      fontFamily: "var(--blink-font-family)",
      fontSize: "var(--blink-font-size)",
      height: "100%",
    },
    ".cm-scroller": {
      fontFamily: "var(--blink-font-family)",
      lineHeight: "var(--blink-line-height)",
      // Content padding driven by --blink-pad-y (vertical) / --blink-pad-x.
      padding: "var(--blink-pad-y) var(--blink-pad-x)",
      overflow: "auto",
    },
    ".cm-content": {
      backgroundColor: "transparent",
      caretColor: "var(--blink-caret)",
      // padding lives on the scroller; keep content flush.
      padding: "0",
    },
    "&.cm-editor": {
      backgroundColor: "transparent",
      height: "100%",
    },
    "&.cm-focused": {
      outline: "none",
    },
    ".cm-line": {
      padding: "0",
    },
    // Caret color for the drawn cursor (drawSelection).
    ".cm-cursor, .cm-dropCursor": {
      borderLeftColor: "var(--blink-caret)",
    },
    "&.cm-focused .cm-cursor": {
      borderLeftColor: "var(--blink-caret)",
    },
    // `drawSelection()` ships a dark fallback that wins on translucent/light
    // panels unless we override its painted layer explicitly. Keep native
    // selection transparent (CodeMirror's base rule does that) and make the
    // drawn rectangles use Blink's scheme-aware color.
    "&.cm-focused > .cm-scroller > .cm-selectionLayer .cm-selectionBackground, .cm-selectionBackground": {
      backgroundColor: "var(--blink-selection) !important",
    },
    ".cm-selectionMatch": {
      backgroundColor: "var(--blink-selection)",
    },
    // No gutters at all in v2, but keep them transparent if ever present.
    ".cm-gutters": {
      backgroundColor: "transparent",
      border: "none",
      color: "var(--blink-text-muted)",
    },
    ".cm-activeLine": {
      backgroundColor: "transparent",
    },
    ".cm-activeLineGutter": {
      backgroundColor: "transparent",
    },
    ".cm-panels": {
      backgroundColor: "transparent",
      color: "var(--blink-text)",
    },
  },
  { dark: true }
);

/**
 * Markdown syntax highlighting.
 *
 * Tag → construct mapping (from @lezer/markdown's `markdownHighlighting`
 * styleTags; @codemirror/lang-markdown reuses these):
 *
 *   heading1..heading6  ATXHeadingN / SetextHeadingN body text
 *   processingInstruction  ALL formatting markers: HeaderMark (#), EmphasisMark
 *                          (* _), CodeMark (`), QuoteMark (>), ListMark (bullet/
 *                          number), LinkMark ([ ] ( )). One shared tag, so every
 *                          marker gets the same dim treatment (spec asks for the
 *                          same --blink-marker for all of them).
 *   strong / emphasis / strikethrough   inline styling (marks excluded — they
 *                          are separate processingInstruction nodes)
 *   monospace           InlineCode + fenced/indented CodeText
 *   link                Link/Image body (the visible text)
 *   url                 URL / Autolink (the target)
 *   quote               Blockquote content
 *   list                OrderedList/BulletList content (the LIST MARKER itself is
 *                          processingInstruction, not this tag)
 *   contentSeparator    HorizontalRule (---, ***, ___)
 *
 * A more specific/inner node wins, so a HeaderMark inside a heading is dimmed
 * even though the surrounding heading is bright — exactly what we want.
 *
 * Editor heading sizes derive from the reader `--blink-hN-size` vars minus 3px
 * (see file header note). All heading colors map to `--blink-text-strong`.
 */
export const blinkHighlight: Extension = syntaxHighlighting(
  HighlightStyle.define([
    // Headings. Editor sizes = reader size - 3px.
    {
      tag: t.heading1,
      color: "var(--blink-text-strong)",
      fontFamily: "var(--blink-title-family)",
      fontWeight: "700",
      fontSize: "calc(var(--blink-h1-size) - 3px)",
    },
    {
      tag: t.heading2,
      color: "var(--blink-text-strong)",
      fontFamily: "var(--blink-title-family)",
      fontWeight: "650",
      fontSize: "calc(var(--blink-h2-size) - 3px)",
    },
    {
      tag: t.heading3,
      color: "var(--blink-text-strong)",
      fontFamily: "var(--blink-title-family)",
      fontWeight: "600",
      fontSize: "calc(var(--blink-h3-size) - 3px)",
    },
    {
      tag: t.heading4,
      color: "var(--blink-text-strong)",
      fontFamily: "var(--blink-title-family)",
      fontWeight: "600",
      fontSize: "calc(var(--blink-h3-size) - 3px)",
    },
    {
      tag: t.heading5,
      color: "var(--blink-text-strong)",
      fontFamily: "var(--blink-title-family)",
      fontWeight: "600",
      fontSize: "calc(var(--blink-h3-size) - 3px)",
    },
    {
      tag: t.heading6,
      color: "var(--blink-text-strong)",
      fontFamily: "var(--blink-title-family)",
      fontWeight: "600",
      fontSize: "calc(var(--blink-h3-size) - 3px)",
    },
    // Generic heading fallback (Setext bodies not covered above).
    {
      tag: t.heading,
      color: "var(--blink-text-strong)",
      fontFamily: "var(--blink-title-family)",
      fontWeight: "600",
    },

    // Formatting markers (#, *, _, `, >, list bullets, link brackets) — dimmed.
    // Reset weight/size to base so a marker inside a heading stays small & light.
    {
      tag: t.processingInstruction,
      color: "var(--blink-marker)",
      fontWeight: "normal",
      fontSize: "var(--blink-font-size)",
    },

    // Inline emphasis. strong/emphasis map to --blink-text-strong / --blink-text.
    { tag: t.strong, color: "var(--blink-text-strong)", fontWeight: "650" },
    { tag: t.emphasis, color: "var(--blink-text)", fontStyle: "italic" },
    {
      tag: t.strikethrough,
      color: "var(--blink-text-muted)",
      textDecoration: "line-through",
    },

    // Code — inline and block. HighlightStyle spans support background/padding,
    // so inline code gets a subtle chip; the mono font + size apply to blocks too.
    {
      tag: t.monospace,
      color: "var(--blink-code-text)",
      fontFamily: "var(--blink-mono-family)",
      fontSize: "12px",
      background: "var(--blink-code-bg)",
      borderRadius: "3px",
      padding: "1px 3px",
    },

    // Links: soft blue, no underline; the URL/target part dimmer.
    { tag: t.link, color: "var(--blink-accent)", textDecoration: "none" },
    { tag: t.url, color: "var(--blink-accent-dim)", textDecoration: "none" },

    // Blockquote content.
    { tag: t.quote, color: "var(--blink-quote-text)", fontStyle: "italic" },

    // List content (markers are handled by processingInstruction above).
    { tag: t.list, color: "var(--blink-text-muted)" },

    // Horizontal rule.
    { tag: t.contentSeparator, color: "var(--blink-rule)" },
  ])
);

export const blinkEditorTheme: Extension = [blinkTheme, blinkHighlight];
