import { test, expect } from "bun:test";
import { homedir } from "node:os";
import { join, resolve } from "node:path";
import { parseCaptureDisplayArgs, remoteCapturePath } from "../bin/cli/capture.ts";

const now = new Date("2026-10-10T23:55:37.180Z");

test("a remote capture lands under the host's folder on this Mac", () => {
  expect(remoteCapturePath("archie", "display-0", "png", { now })).toBe(
    join(homedir(), ".lattices/captures/archie/archie-display-0-2026-10-10T23-55-37-180.png"),
  );
  expect(remoteCapturePath("archie", "window-7", "jpeg", { now })).toEndWith("archie-window-7-2026-10-10T23-55-37-180.jpg");
});

test("--filename names the file in that folder, --out puts it anywhere", () => {
  expect(remoteCapturePath("archie", "display-0", "png", { filename: "../desk" })).toBe(
    join(homedir(), ".lattices/captures/archie/desk.png"),
  );
  expect(remoteCapturePath("archie", "display-0", "png", { out: "shots/a.png" })).toBe(resolve("shots/a.png"));
});

test("capture display takes --out", () => {
  expect(parseCaptureDisplayArgs(["1", "--out", "/tmp/a.png"])).toMatchObject({ display: 1, out: "/tmp/a.png" });
});
