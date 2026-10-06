import { test, expect } from "bun:test";
import { validateEditorCSS } from "../bin/editor-bundle-assets";
test("quoted inline SVG consumes nested filter URL and still validates fonts", () => {
  expect(() => validateEditorCSS(`a{background:url("data:image/svg+xml,%3Csvg filter='url(%23grain)'/%3E")}b{src:url('./mono.woff2')}`, ["mono.woff2"])).not.toThrow();
});
test("missing and external assets remain rejected after inline SVG", () => {
  for (const url of ["missing.woff2", "https://example.com/font.woff2", "../font.woff2"]) {
    expect(() => validateEditorCSS(`a{background:url("data:image/svg+xml,%3Csvg/%3E");src:url("${url}")}`, [])).toThrow("unbundled asset");
  }
});
