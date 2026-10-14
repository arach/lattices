/** Validate complete CSS URL tokens, including quoted inline SVGs containing url(#id). */
export function validateEditorCSS(css: string, files: readonly string[]) {
  const urls = /url\(\s*(?:"((?:\\.|[^"\\])*)"|'((?:\\.|[^'\\])*)'|([^\s)'"\\]+))\s*\)/gi;
  for (const match of css.matchAll(urls)) {
    const url = match[1] ?? match[2] ?? match[3];
    // Self-contained SVG decoration is not an external asset. In particular,
    // don't reinterpret its nested filter url(#grain) as a font/file request.
    if (/^data:image\/svg\+xml[;,]/i.test(url) || url.startsWith("#")) continue;
    if (!files.includes(url.replace(/^\.\//, ""))) {
      throw new Error(`CSS references an unbundled asset: ${url}`);
    }
  }
}
