// OCR with positions. tesseract's TSV output gives a box per word; words are
// grouped into lines, and each line is mapped back to screen coordinates so a
// caller can click what it read.

import { run } from "./exec.ts";
import type { Rect } from "./placement.ts";

export interface OcrLine {
  text: string;
  confidence: number;
  /** Box in image pixels. */
  frame: { x: number; y: number; width: number; height: number };
  /** Box in screen (layout) coordinates. */
  screenFrame: Rect;
}

export interface OcrRead {
  imageWidth: number;
  imageHeight: number;
  fullText: string;
  blockCount: number;
  blocks: OcrLine[];
  region: Rect;
}

/** Group tesseract TSV words into lines. `scale` is image pixels per screen unit. */
export function parseTsv(tsv: string, region: Rect, scale: number): OcrLine[] {
  const lines = new Map<string, { words: string[]; conf: number[]; x0: number; y0: number; x1: number; y1: number }>();
  const order: string[] = [];
  for (const row of tsv.split("\n").slice(1)) {
    const cols = row.split("\t");
    if (cols.length < 12 || cols[0] !== "5") continue; // level 5 = word
    const text = cols.slice(11).join("\t").trim();
    const conf = Number(cols[10]);
    if (!text || conf < 0) continue;
    const [left, top, width, height] = cols.slice(6, 10).map(Number);
    const key = `${cols[2]}.${cols[3]}.${cols[4]}`; // block.paragraph.line
    let line = lines.get(key);
    if (!line) {
      line = { words: [], conf: [], x0: left, y0: top, x1: left + width, y1: top + height };
      lines.set(key, line);
      order.push(key);
    }
    line.words.push(text);
    line.conf.push(conf);
    line.x0 = Math.min(line.x0, left);
    line.y0 = Math.min(line.y0, top);
    line.x1 = Math.max(line.x1, left + width);
    line.y1 = Math.max(line.y1, top + height);
  }
  return order.map((key) => {
    const l = lines.get(key)!;
    const frame = { x: l.x0, y: l.y0, width: l.x1 - l.x0, height: l.y1 - l.y0 };
    return {
      text: l.words.join(" "),
      confidence: l.conf.reduce((a, b) => a + b, 0) / l.conf.length / 100,
      frame,
      screenFrame: {
        x: Math.round(region.x + frame.x / scale),
        y: Math.round(region.y + frame.y / scale),
        w: Math.round(frame.width / scale),
        h: Math.round(frame.height / scale),
      },
    };
  });
}

export async function read(png: Buffer, region: Rect, imageWidth: number, imageHeight: number): Promise<OcrRead> {
  const tsv = await run("tesseract", ["stdin", "stdout", "--psm", "3", "tsv"], { input: png, timeoutMs: 30_000 });
  const scale = region.w > 0 ? imageWidth / region.w : 1;
  const blocks = parseTsv(tsv, region, scale);
  return {
    imageWidth,
    imageHeight,
    fullText: blocks.map((b) => b.text).join("\n"),
    blockCount: blocks.length,
    blocks,
    region,
  };
}

export function levenshtein(a: string, b: string): number {
  const prev = Array.from({ length: b.length + 1 }, (_, i) => i);
  for (let i = 1; i <= a.length; i++) {
    let diag = prev[0];
    prev[0] = i;
    for (let j = 1; j <= b.length; j++) {
      const up = prev[j];
      prev[j] = Math.min(prev[j] + 1, prev[j - 1] + 1, diag + (a[i - 1] === b[j - 1] ? 0 : 1));
      diag = up;
    }
  }
  return prev[b.length];
}

const normalize = (s: string) => s.toLowerCase().replace(/\s+/g, " ").trim();

/**
 * How well `needle` appears in `line`, 0-1: the best edit-distance match of
 * the needle against any window of the line of similar length. OCR misreads
 * characters ("Hetlo Renote"), so exact substring matching is too strict.
 */
export function matchScore(line: string, needle: string): number {
  const hay = normalize(line);
  const n = normalize(needle);
  if (!n) return 0;
  if (hay.includes(n)) return 1;
  let best = 0;
  for (const width of [n.length - 1, n.length, n.length + 1]) {
    if (width <= 0) continue;
    for (let start = 0; start + width <= Math.max(hay.length, width); start++) {
      const window = hay.slice(start, start + width);
      best = Math.max(best, 1 - levenshtein(window, n) / n.length);
    }
  }
  return Math.max(0, best);
}

/** Lines that contain `text`, allowing OCR misreads; best first. */
export function find(lines: OcrLine[], text: string, minScore = 0.75): (OcrLine & { score: number })[] {
  return lines
    .map((line) => ({ ...line, score: matchScore(line.text, text) }))
    .filter((line) => line.score >= minScore)
    .sort((a, b) => {
      const exact = Number(normalize(b.text) === normalize(text)) - Number(normalize(a.text) === normalize(text));
      return exact || b.score - a.score || a.text.length - b.text.length || b.confidence - a.confidence;
    });
}
