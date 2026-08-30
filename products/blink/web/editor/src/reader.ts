import { marked, type TokenizerAndRendererExtension } from "marked";

/** Minimal HTML-escape for text we interpolate into rendered link markup. */
function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/**
 * `[[note-id]]` and `[[note-id|Label]]` render as internal links that open the
 * target note as a panel. The href uses `blink://open/<id>`, a scheme the native
 * navigation policy intercepts (`WebBridge.decidePolicyFor`) and routes to
 * `NoteStore` — it never actually navigates the webview. Registered once, below.
 */
const wikiLinkExtension: TokenizerAndRendererExtension = {
  name: "wikilink",
  level: "inline",
  start(src: string) {
    return src.indexOf("[[");
  },
  tokenizer(src: string) {
    const match = /^\[\[([^\]|]+?)(?:\|([^\]]+?))?\]\]/.exec(src);
    if (!match) return undefined;
    const id = match[1].trim();
    return {
      type: "wikilink",
      raw: match[0],
      id,
      label: (match[2] ?? match[1]).trim(),
    };
  },
  renderer(token) {
    const { id, label } = token as unknown as { id: string; label: string };
    return (
      `<a href="blink://open/${encodeURIComponent(id)}" ` +
      `class="blink-wikilink" data-note-id="${escapeHtml(id)}">${escapeHtml(label)}</a>`
    );
  },
};

marked.use({ extensions: [wikiLinkExtension] });

/**
 * Read-mode renderer for the Blink v2 editor.
 *
 * Turns the current markdown document into rendered HTML typography that sits on
 * the same transparent glass as the editor. This module owns:
 *   - the pure `renderMarkdown` function (markdown source -> HTML string), and
 *   - a `Reader` controller that manages the `.blink-reader` DOM element,
 *     including the empty-note placeholder.
 *
 * SECURITY NOTE: `marked` does NOT sanitize raw HTML embedded in the markdown.
 * Blink notes are the user's own local content (no remote/untrusted input is
 * ever rendered here), so raw HTML is intentionally passed through rather than
 * pulling in a sanitizer dependency. If this surface ever renders third-party
 * content, add DOMPurify (or equivalent) before shipping.
 */

/**
 * Render markdown source to an HTML fragment string.
 *
 * `gfm: true` enables GitHub Flavored Markdown (tables, strikethrough, task
 * lists, autolinks). `async: false` forces a synchronous string return so the
 * caller can inject it directly. `breaks: false` keeps standard markdown
 * paragraph semantics (a single newline is not a hard break).
 */
export function renderMarkdown(source: string): string {
  return marked(source, { gfm: true, async: false, breaks: false });
}

/** True if the document is empty or whitespace-only. */
function isEmptyDoc(source: string): boolean {
  return source.trim().length === 0;
}

/**
 * Replace every text node under `root` with per-character spans (`.blink-tok`),
 * returned in document order, so a reveal can fade characters in place without
 * disturbing layout. Splits by code point to keep surrogate pairs intact.
 */
function wrapCharacters(root: HTMLElement): HTMLElement[] {
  const spans: HTMLElement[] = [];
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  const texts: Text[] = [];
  for (let n = walker.nextNode(); n; n = walker.nextNode()) texts.push(n as Text);
  for (const node of texts) {
    const value = node.nodeValue ?? "";
    if (!value) continue;
    const frag = document.createDocumentFragment();
    for (const cp of Array.from(value)) {
      const span = document.createElement("span");
      span.className = "blink-tok";
      span.textContent = cp;
      frag.append(span);
      spans.push(span);
    }
    node.replaceWith(frag);
  }
  return spans;
}

/**
 * Controller around the `.blink-reader` element. It renders the document, shows
 * a placeholder for empty notes, and exposes hide/show plus proportional
 * scroll helpers used when flipping between modes.
 */
export class Reader {
  readonly element: HTMLElement;
  private typeOnBase: string | null = null;
  private typeOnSuffix = "";
  private typeChars: HTMLElement[] = [];
  private typeCaret: HTMLSpanElement | null = null;
  private typeRevealed = 0;

  constructor(element: HTMLElement) {
    this.element = element;
  }

  /** Render `source` into the reader element (or a placeholder if empty). */
  render(source: string): void {
    this.resetTypeOn();
    this.renderSettled(source);
  }

  /**
   * Render for a mode flip. Any in-flight reveal simply settles to the full
   * source (a flip mid-reveal is user-initiated and rare) — no plain-text flash.
   */
  renderCurrent(source: string): void {
    this.resetTypeOn();
    this.renderSettled(source);
  }

  /**
   * Begin an IN-PLACE typed reveal. Render base + the full suffix as final
   * markdown up front, so nothing reflows when the reveal ends, then unveil the
   * suffix character by character where it actually sits — a caret riding the
   * edge. `base` is the already-settled content; `suffix` is the appended text.
   */
  beginTypeOn(base: string, suffix: string): void {
    this.typeOnBase = base;
    this.typeOnSuffix = suffix;
    this.typeRevealed = 0;

    this.element.innerHTML = isEmptyDoc(base) ? "" : renderMarkdown(base);
    const typing = document.createElement("div");
    typing.className = "blink-reader-typing";
    typing.innerHTML = renderMarkdown(suffix);
    this.element.append(typing);

    // Every appended character starts pending (hidden) in its final position.
    this.typeChars = wrapCharacters(typing);
    for (const ch of this.typeChars) ch.classList.add("is-pending");

    const caret = document.createElement("span");
    caret.className = "blink-typeon-caret";
    caret.setAttribute("aria-hidden", "true");
    this.typeCaret = caret;
    if (this.typeChars[0]) this.typeChars[0].before(caret);
    else typing.append(caret);

    this.updateTypeOn("");
  }

  /**
   * Reveal the suffix up to `text` (the portion typed so far). Progress is taken
   * proportionally against the raw suffix length and applied to the rendered
   * characters, so the caret walks the text in place with a soft fade.
   */
  updateTypeOn(text: string): void {
    if (this.typeOnBase === null) return;
    const total = this.typeChars.length;
    const fraction = this.typeOnSuffix.length ? text.length / this.typeOnSuffix.length : 1;
    const target = Math.min(total, Math.round(fraction * total));
    for (let i = this.typeRevealed; i < target; i++) {
      this.typeChars[i].classList.remove("is-pending");
    }
    if (target > this.typeRevealed) this.typeRevealed = target;

    if (this.typeCaret) {
      const anchor = target > 0 ? this.typeChars[target - 1] : null;
      if (anchor) anchor.after(this.typeCaret);
      else if (this.typeChars[0]) this.typeChars[0].before(this.typeCaret);
    }
    if (this.isVisible) this.typeCaret?.scrollIntoView({ block: "nearest" });
  }

  private resetTypeOn(): void {
    this.typeOnBase = null;
    this.typeOnSuffix = "";
    this.typeChars = [];
    this.typeCaret = null;
    this.typeRevealed = 0;
  }

  private renderSettled(source: string): void {
    if (isEmptyDoc(source)) {
      this.element.innerHTML =
        '<div class="blink-reader-empty">Empty note — double-click to write.</div>';
      return;
    }
    this.element.innerHTML = renderMarkdown(source);
  }

  show(): void {
    this.element.style.display = "block";
  }

  hide(): void {
    this.element.style.display = "none";
  }

  get isVisible(): boolean {
    return this.element.style.display !== "none";
  }

  /**
   * Proportional scroll position in [0, 1]: how far down the scrollable range
   * the reader currently is. Returns 0 when there is nothing to scroll.
   */
  getScrollFraction(): number {
    const max = this.element.scrollHeight - this.element.clientHeight;
    if (max <= 0) return 0;
    return this.element.scrollTop / max;
  }

  /** Restore a proportional scroll position captured from another surface. */
  setScrollFraction(fraction: number): void {
    const max = this.element.scrollHeight - this.element.clientHeight;
    this.element.scrollTop = max > 0 ? Math.round(fraction * max) : 0;
  }
}
