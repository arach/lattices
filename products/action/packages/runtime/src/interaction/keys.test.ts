import assert from "node:assert/strict";
import { describe, test } from "node:test";

import { parseKeyChord } from "./keys.js";

describe("parseKeyChord", () => {
  test("reads a chord however it is written", () => {
    const cmdL = { key: "l", modifiers: ["cmd"] };
    assert.deepEqual(parseKeyChord({ key: "cmd+l" }), cmdL);
    assert.deepEqual(parseKeyChord({ key: "Cmd-L" }), cmdL);
    assert.deepEqual(parseKeyChord({ key: "⌘L" }), cmdL);
    assert.deepEqual(parseKeyChord({ keys: ["cmd", "l"] }), cmdL);
    assert.deepEqual(parseKeyChord({ key: "l", modifiers: ["command"] }), cmdL);
  });

  test("orders modifiers and drops duplicates", () => {
    assert.deepEqual(parseKeyChord({ key: "shift+cmd+t", modifiers: ["cmd"] }), { key: "t", modifiers: ["shift", "cmd"] });
    assert.deepEqual(parseKeyChord({ key: "⌘⇧⌥⌃k" }), { key: "k", modifiers: ["ctrl", "opt", "shift", "cmd"] });
  });

  test("maps key aliases to the host's names", () => {
    assert.deepEqual(parseKeyChord({ key: "Enter" }), { key: "return", modifiers: [] });
    assert.deepEqual(parseKeyChord({ key: "esc" }), { key: "escape", modifiers: [] });
    assert.deepEqual(parseKeyChord({ key: "cmd+backspace" }), { key: "delete", modifiers: ["cmd"] });
    assert.deepEqual(parseKeyChord({ key: "ArrowDown" }), { key: "down", modifiers: [] });
    assert.deepEqual(parseKeyChord({ key: "PgUp" }), { key: "pageup", modifiers: [] });
    assert.deepEqual(parseKeyChord({ key: "F5" }), { key: "f5", modifiers: [] });
  });

  test("keeps a literal - or + key", () => {
    assert.deepEqual(parseKeyChord({ key: "cmd+-" }), { key: "-", modifiers: ["cmd"] });
    assert.deepEqual(parseKeyChord({ key: "-" }), { key: "-", modifiers: [] });
    assert.deepEqual(parseKeyChord({ key: "cmd+=" }), { key: "=", modifiers: ["cmd"] });
  });

  test("refuses what it would otherwise type as text", () => {
    assert.throws(() => parseKeyChord({ key: "hello" }), /unknown key "hello".*type act/);
    assert.throws(() => parseKeyChord({ key: "cmd+a+b" }), /two keys/);
    assert.throws(() => parseKeyChord({ key: "a", modifiers: ["hyper"] }), /unknown modifier/);
    assert.throws(() => parseKeyChord({ key: "cmd" }), /needs a key/);
    assert.throws(() => parseKeyChord({}), /needs a key/);
  });
});
