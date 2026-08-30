import { EditorSelection, StateEffect, StateField } from "@codemirror/state";
import type { Extension } from "@codemirror/state";
import {
  Decoration,
  EditorView,
  WidgetType,
} from "@codemirror/view";
import type { DecorationSet } from "@codemirror/view";

/** Reader hooks kept deliberately small so this module stays mode-agnostic. */
export interface TypeOnReader {
  beginTypeOn(base: string, suffix: string): void;
  updateTypeOn(text: string): void;
  render(text: string): void;
}

interface VisibleRange {
  from: number;
  to: number;
}

const setVisibleRange = StateEffect.define<VisibleRange | null>();

class TypeOnCaret extends WidgetType {
  toDOM(): HTMLElement {
    const caret = document.createElement("span");
    caret.className = "blink-typeon-caret";
    caret.setAttribute("aria-hidden", "true");
    return caret;
  }

  ignoreEvent(): boolean {
    return true;
  }
}

const caretWidget = new TypeOnCaret();

function revealDecorations(range: VisibleRange | null): DecorationSet {
  if (range === null) return Decoration.none;
  if (range.from < range.to) {
    // The full document is already in CodeMirror. Replace only its unrevealed
    // tail with a visual caret; user edits therefore always operate on the full
    // truth even if they arrive between animation frames.
    return Decoration.set([
      Decoration.replace({ widget: caretWidget }).range(range.from, range.to),
    ]);
  }
  return Decoration.set([
    Decoration.widget({ widget: caretWidget, side: 1 }).range(range.from),
  ]);
}

const revealField = StateField.define<DecorationSet>({
  create: () => Decoration.none,
  update(value, transaction) {
    // A real edit invalidates reveal offsets immediately. The main update
    // listener finishes the controller in the same dispatch and reports the
    // user's complete document to native.
    let next = transaction.docChanged ? Decoration.none : value;
    for (const effect of transaction.effects) {
      if (effect.is(setVisibleRange)) {
        next = revealDecorations(effect.value);
      }
    }
    return next;
  },
  provide: (field) => EditorView.decorations.from(field),
});

/** Include once in the EditorState used by the live view. */
export const typeOnExtension: Extension = revealField;

function graphemeEnds(text: string): number[] {
  const ends: number[] = [];
  let offset = 0;
  // Safari 16 (the bundle target) supports Intl.Segmenter. Keep a code-point
  // fallback so standalone/dev hosts still never split surrogate pairs.
  if (typeof Intl.Segmenter === "function") {
    const segmenter = new Intl.Segmenter(undefined, { granularity: "grapheme" });
    for (const { segment } of segmenter.segment(text)) {
      offset += segment.length;
      ends.push(offset);
    }
  } else {
    for (const scalar of Array.from(text)) {
      offset += scalar.length;
      ends.push(offset);
    }
  }
  return ends;
}

const CHARACTERS_PER_SECOND = 180;
const ATTRIBUTION_AFTER_MS = 4_000;

/**
 * Visual typed reveal over a CodeMirror document that is already complete.
 * Programmatic dispatches carry no user event and therefore never echo
 * contentChanged. A new reveal or user edit snaps the previous one to done.
 */
export class TypeOnController {
  private frame: number | undefined;
  private startedAt = 0;
  private base = "";
  private suffix = "";
  private ends: number[] = [];
  private revealed = 0;
  private active = false;
  private chipHideTimer: number | undefined;

  constructor(
    private readonly view: EditorView,
    private readonly reader: TypeOnReader
  ) {}

  start(base: string, suffix: string, source?: string | null): void {
    this.finish();
    this.clearChipTimer();
    this.setAttribution(source);

    if (suffix.length === 0) {
      this.scheduleChipHide();
      return;
    }

    this.base = base;
    this.suffix = suffix;
    this.ends = graphemeEnds(suffix);
    this.revealed = 0;
    this.active = true;
    document.body.setAttribute("data-type-on", "");
    // In the common append-at-caret case, put the real (temporarily hidden)
    // selection after the complete suffix. If the user types mid-reveal their
    // keystroke then follows the append rather than being inserted inside it.
    const selection = this.view.state.selection.main;
    if (selection.empty && selection.head === base.length) {
      this.view.dispatch({
        selection: EditorSelection.cursor(base.length + suffix.length),
      });
    }
    this.reader.beginTypeOn(base, suffix);
    this.applyFrame(0);
    this.startedAt = performance.now();
    this.frame = requestAnimationFrame((now) => this.tick(now));
  }

  /** Snap the reveal to the live full document and keep the chip for 4s. */
  finish(): void {
    if (!this.active) return;
    if (this.frame !== undefined) {
      cancelAnimationFrame(this.frame);
      this.frame = undefined;
    }
    this.active = false;
    document.body.removeAttribute("data-type-on");
    this.view.dispatch({ effects: setVisibleRange.of(null) });
    this.reader.render(this.view.state.doc.toString());
    this.scheduleChipHide();
  }

  private tick(now: number): void {
    if (!this.active) return;
    const count = Math.min(
      this.ends.length,
      Math.floor(((now - this.startedAt) * CHARACTERS_PER_SECOND) / 1000)
    );
    if (count > this.revealed) {
      this.revealed = count;
      this.applyFrame(count);
    }
    if (count >= this.ends.length) {
      this.finish();
    } else {
      this.frame = requestAnimationFrame((next) => this.tick(next));
    }
  }

  private applyFrame(count: number): void {
    const suffixOffset = count === 0 ? 0 : this.ends[count - 1];
    const visibleEnd = this.base.length + suffixOffset;
    const rangeEffect = setVisibleRange.of({
      from: visibleEnd,
      to: this.base.length + this.suffix.length,
    });
    this.view.dispatch({
      // Follow the visual append point in edit mode. When the editor is hidden
      // for read mode, its independent reader scroller owns the same job.
      effects: this.view.dom.offsetParent !== null
        ? [rangeEffect, EditorView.scrollIntoView(visibleEnd, { y: "nearest", yMargin: 20 })]
        : rangeEffect,
    });
    this.reader.updateTypeOn(this.suffix.slice(0, suffixOffset));
  }

  private setAttribution(source?: string | null): void {
    const chip = document.getElementById("attribution");
    if (!chip) return;
    const clean = source?.trim();
    if (!clean) {
      chip.classList.remove("is-visible");
      chip.textContent = "";
      return;
    }
    chip.textContent = `✳ ${clean} · just now`;
    chip.classList.add("is-visible");
  }

  private scheduleChipHide(): void {
    const chip = document.getElementById("attribution");
    if (!chip?.classList.contains("is-visible")) return;
    this.clearChipTimer();
    this.chipHideTimer = window.setTimeout(() => {
      chip.classList.remove("is-visible");
      this.chipHideTimer = undefined;
    }, ATTRIBUTION_AFTER_MS);
  }

  private clearChipTimer(): void {
    if (this.chipHideTimer !== undefined) {
      clearTimeout(this.chipHideTimer);
      this.chipHideTimer = undefined;
    }
  }
}
