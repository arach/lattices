import { describe, expect, test } from "bun:test";

import {
  assessNavigation,
  browserOpenMode,
  isChromeNavigationErrorPage,
  navigationIsReady,
  regularChromeLaunchArgs,
  shouldReuseCurrentTab,
} from "./navigation.ts";

describe("Action Browser open modes", () => {
  test("defaults to the controlled Action Chrome mode", () => {
    expect(browserOpenMode(undefined)).toBe("action");
    expect(browserOpenMode("action")).toBe("action");
  });

  test("builds an isolated launch handoff for regular Chrome", () => {
    expect(browserOpenMode("regular")).toBe("regular");
    expect(regularChromeLaunchArgs("Google Chrome", "https://example.com/")).toEqual([
      "/usr/bin/open",
      "-n",
      "-a",
      "Google Chrome",
      "https://example.com/",
    ]);
  });

  test("rejects unknown modes", () => {
    expect(() => browserOpenMode("personal")).toThrow("mode must be either action or regular");
  });
});

describe("Action Browser tab reuse", () => {
  test("reuses the session's current tab by default", () => {
    expect(shouldReuseCurrentTab({ currentTargetId: "tab-1" })).toBe(true);
  });

  test("creates a tab for the first open or when explicitly requested", () => {
    expect(shouldReuseCurrentTab({})).toBe(false);
    expect(shouldReuseCurrentTab({ currentTargetId: "tab-1", newTab: true })).toBe(false);
  });
});

describe("Action Browser navigation readiness", () => {
  test("does not accept the previous document while a reused tab is navigating", () => {
    expect(navigationIsReady({
      readyState: "complete",
      documentUrl: "https://previous.example/",
      expectedLoaderId: "new-loader",
      observedLoaderId: "old-loader",
    })).toBe(false);
  });

  test("accepts the ready document after Chrome commits the expected loader", () => {
    expect(navigationIsReady({
      readyState: "interactive",
      documentUrl: "https://next.example/",
      expectedLoaderId: "new-loader",
      observedLoaderId: "new-loader",
    })).toBe(true);
  });
});

describe("Action Browser navigation assessment", () => {
  test("rejects a CDP navigation failure and preserves requested and final URLs", () => {
    const result = assessNavigation({
      requestedUrl: "http://openscout.studio.local/demo",
      documentUrl: "http://openscout.studio.local/demo",
      targetUrl: "chrome-error://chromewebdata/",
      title: "openscout.studio.local",
      readyState: "complete",
      timedOut: false,
      timeoutMs: 15_000,
      navigateErrorText: "net::ERR_NAME_NOT_RESOLVED",
      pageText: "This site can’t be reached DNS_PROBE_FINISHED_NXDOMAIN",
    });

    expect(result.ok).toBe(false);
    expect(result.requestedUrl).toBe("http://openscout.studio.local/demo");
    expect(result.finalUrl).toBe("chrome-error://chromewebdata/");
    expect(result.diagnostics.errorCode).toBe("net::ERR_NAME_NOT_RESOLVED");
    expect(result.diagnostics.chromeErrorPage).toBe(true);
  });

  test("rejects a Chrome error page even when Page.navigate omits errorText", () => {
    const result = assessNavigation({
      requestedUrl: "https://missing.invalid/",
      documentUrl: "chrome-error://chromewebdata/",
      targetUrl: "chrome-error://chromewebdata/",
      title: "missing.invalid",
      readyState: "complete",
      timedOut: false,
      timeoutMs: 15_000,
      pageText: "This site can’t be reached ERR_NAME_NOT_RESOLVED",
    });

    expect(result.ok).toBe(false);
    expect(result.finalUrl).toBe("chrome-error://chromewebdata/");
    expect(result.diagnostics.errorCode).toBe("ERR_NAME_NOT_RESOLVED");
  });

  test("rejects a navigation readiness timeout", () => {
    const result = assessNavigation({
      requestedUrl: "https://example.com/slow",
      documentUrl: "https://example.com/slow",
      targetUrl: "https://example.com/slow",
      readyState: "loading",
      timedOut: true,
      timeoutMs: 250,
    });

    expect(result.ok).toBe(false);
    expect(result.error).toContain("Timed out after 250ms");
  });

  test("accepts a ready redirect and reports the observed final URL", () => {
    const result = assessNavigation({
      requestedUrl: "http://example.com/",
      documentUrl: "https://example.com/",
      targetUrl: "https://example.com/",
      title: "Example Domain",
      readyState: "complete",
      timedOut: false,
      timeoutMs: 15_000,
    });

    expect(result.ok).toBe(true);
    expect(result.finalUrl).toBe("https://example.com/");
    expect(result.diagnostics.pageText).toBeUndefined();
  });

  test("recognizes Chrome-owned navigation error URLs", () => {
    expect(isChromeNavigationErrorPage("chrome-error://chromewebdata/")).toBe(true);
    expect(isChromeNavigationErrorPage("chrome://settings/")).toBe(false);
    expect(isChromeNavigationErrorPage("https://example.com/")).toBe(false);
  });
});
