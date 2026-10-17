export type NavigationDiagnostics = {
  requestedUrl: string;
  finalUrl?: string;
  documentUrl?: string;
  targetUrl?: string;
  title?: string;
  readyState?: string;
  timedOut: boolean;
  timeoutMs: number;
  navigateErrorText?: string;
  chromeErrorPage: boolean;
  errorCode?: string;
  pageText?: string;
};

export type NavigationOutcome =
  | {
    ok: true;
    requestedUrl: string;
    finalUrl: string;
    diagnostics: NavigationDiagnostics;
  }
  | {
    ok: false;
    error: string;
    requestedUrl: string;
    finalUrl: string;
    diagnostics: NavigationDiagnostics;
  };

type NavigationInput = {
  requestedUrl: string;
  documentUrl?: string;
  targetUrl?: string;
  title?: string;
  readyState?: string;
  timedOut: boolean;
  timeoutMs: number;
  navigateErrorText?: string;
  pageText?: string;
};

export type BrowserOpenMode = "action" | "regular";

export function browserOpenMode(value: unknown): BrowserOpenMode {
  if (value === undefined || value === "action") return "action";
  if (value === "regular") return "regular";
  throw new Error("mode must be either action or regular.");
}

export function regularChromeLaunchArgs(chromeAppName: string, url: string): string[] {
  return ["/usr/bin/open", "-n", "-a", chromeAppName, url];
}

export function shouldReuseCurrentTab(input: {
  currentTargetId?: string;
  newTab?: boolean;
}): boolean {
  return Boolean(input.currentTargetId) && input.newTab !== true;
}

export function navigationIsReady(input: {
  readyState?: string;
  documentUrl?: string;
  expectedLoaderId?: string;
  observedLoaderId?: string;
}): boolean {
  const documentReady = input.readyState === "complete" || input.readyState === "interactive";
  const hasDocument = Boolean(input.documentUrl && input.documentUrl !== "about:blank");
  const loaderReady = !input.expectedLoaderId || input.observedLoaderId === input.expectedLoaderId;
  return documentReady && hasDocument && loaderReady;
}

function nonEmpty(value: string | undefined): string | undefined {
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

export function isChromeNavigationErrorPage(url: string | undefined): boolean {
  const value = nonEmpty(url);
  return Boolean(
    value
    && (
      value.startsWith("chrome-error://")
      || value.startsWith("chrome://network-error/")
      || value.startsWith("chrome://interstitials/")
    )
  );
}

function extractErrorCode(...values: Array<string | undefined>): string | undefined {
  for (const value of values) {
    const match = value?.match(/(?:net::)?ERR_[A-Z0-9_]+|DNS_PROBE_FINISHED_[A-Z0-9_]+/);
    if (match) return match[0];
  }
  return undefined;
}

function chooseFinalUrl(input: NavigationInput): string {
  const documentUrl = nonEmpty(input.documentUrl);
  const targetUrl = nonEmpty(input.targetUrl);
  if (isChromeNavigationErrorPage(targetUrl)) return targetUrl!;
  if (documentUrl && documentUrl !== "about:blank") return documentUrl;
  if (targetUrl && targetUrl !== "about:blank") return targetUrl;
  return documentUrl ?? targetUrl ?? input.requestedUrl;
}

export function assessNavigation(input: NavigationInput): NavigationOutcome {
  const requestedUrl = input.requestedUrl;
  const finalUrl = chooseFinalUrl(input);
  const navigateErrorText = nonEmpty(input.navigateErrorText);
  const chromeErrorPage = isChromeNavigationErrorPage(finalUrl)
    || isChromeNavigationErrorPage(input.documentUrl)
    || isChromeNavigationErrorPage(input.targetUrl);
  const errorCode = extractErrorCode(navigateErrorText, input.pageText, input.title);
  const diagnostics: NavigationDiagnostics = {
    requestedUrl,
    finalUrl,
    documentUrl: nonEmpty(input.documentUrl),
    targetUrl: nonEmpty(input.targetUrl),
    title: nonEmpty(input.title),
    readyState: nonEmpty(input.readyState),
    timedOut: input.timedOut,
    timeoutMs: input.timeoutMs,
    navigateErrorText,
    chromeErrorPage,
    errorCode,
    pageText: nonEmpty(input.pageText),
  };

  if (navigateErrorText) {
    return {
      ok: false,
      error: `Navigation to ${requestedUrl} failed: ${navigateErrorText}`,
      requestedUrl,
      finalUrl,
      diagnostics,
    };
  }

  if (chromeErrorPage) {
    const detail = errorCode ?? finalUrl;
    return {
      ok: false,
      error: `Chrome displayed an internal navigation error page (${detail}).`,
      requestedUrl,
      finalUrl,
      diagnostics,
    };
  }

  if (input.timedOut) {
    return {
      ok: false,
      error: `Timed out after ${input.timeoutMs}ms waiting for ${requestedUrl} to become ready.`,
      requestedUrl,
      finalUrl,
      diagnostics,
    };
  }

  const { pageText: _pageText, ...successDiagnostics } = diagnostics;
  return { ok: true, requestedUrl, finalUrl, diagnostics: successDiagnostics };
}
