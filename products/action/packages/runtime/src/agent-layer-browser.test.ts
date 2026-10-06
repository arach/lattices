import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { parseSpacesBinding } from "./agent-layer-browser.js";

const bindings = `{
    ":no-bundle:????" = AllSpaces;
    "com.apple.finder" = "";
    "com.apple.tv" = AllSpaces;
    "com.google.chrome" = "EDAF663A-F1FE-4CC5-AD2C-B8AD7C1B16DC";
}`;

describe("parseSpacesBinding", () => {
  test("an app assigned to one Desktop returns that Desktop", () => {
    assert.equal(parseSpacesBinding(bindings, "com.google.Chrome"), "EDAF663A-F1FE-4CC5-AD2C-B8AD7C1B16DC");
  });

  test("All Desktops, None and unlisted apps aren't pinned", () => {
    assert.equal(parseSpacesBinding(bindings, "com.apple.tv"), undefined);
    assert.equal(parseSpacesBinding(bindings, "com.apple.finder"), undefined);
    assert.equal(parseSpacesBinding(bindings, "com.google.chrome.for.testing"), undefined);
  });
});
