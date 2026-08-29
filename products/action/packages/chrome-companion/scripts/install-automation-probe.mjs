#!/usr/bin/env bun

import {
  activateMiraProcess,
  connectCdp,
  dist,
  ensureExtensionsTarget,
  listExtensions,
  miraChromePid,
  pollPickerAndComplete,
  profileName,
  port,
  sheetDump,
  sleep,
  stageMiraWindow,
  uiState,
} from "./mira-chrome.mjs";

async function connect(page) {
  return connectCdp(page.webSocketDebuggerUrl);
}

async function ensureExtensionsPage() {
  return ensureExtensionsTarget();
}

async function trigger(mode, call) {
  if (mode === "choose-path") {
    return call("Runtime.evaluate", {
      expression: `new Promise((resolve) => {
        chrome.developerPrivate.choosePath(
          chrome.developerPrivate.SelectType.FOLDER,
          chrome.developerPrivate.FileType.LOAD,
          (path) => resolve({ path })
        );
      })`,
      awaitPromise: true,
      returnByValue: true,
      timeout: 20000,
    });
  }

  if (mode === "api") {
    return call("Runtime.evaluate", {
      expression: "new Promise((resolve) => chrome.developerPrivate.loadUnpacked({ failQuietly: false }, resolve))",
      awaitPromise: true,
      returnByValue: true,
      timeout: 20000,
    });
  }

  return call("Runtime.evaluate", {
    expression: `(() => {
      const toolbar = document.querySelector("extensions-manager")?.shadowRoot
        ?.querySelector("extensions-toolbar");
      const devToggle = toolbar?.shadowRoot?.querySelector("#devMode");
      if (devToggle && !devToggle.checked) {
        devToggle.click();
      }
      toolbar?.shadowRoot?.querySelector("#loadUnpacked")?.click();
      return true;
    })()`,
    returnByValue: true,
  });
}

async function main() {
  const mode = process.argv[2] || "dom";
  console.log(`Target profile: ${profileName} on CDP port ${port} (never personal Chrome)`);

  const page = await ensureExtensionsPage();
  const pid = miraChromePid();
  console.log(`mira Chrome pid: ${pid}`);

  const cdp = await stageMiraWindow(page, pid);
  activateMiraProcess(pid);
  await sleep(300);

  console.log(`triggering via ${mode}`);
  console.log("ui before:", uiState(pid));

  const triggerPromise = trigger(mode, cdp.call.bind(cdp));
  const pickerResult = await pollPickerAndComplete(pid, dist, 10000);

  try {
    const triggerResult = await triggerPromise;
    console.log("trigger result:", JSON.stringify(triggerResult.result?.value ?? triggerResult, null, 2));
  } catch (error) {
    console.log("trigger error:", error.message);
  }

  console.log("ui after:", uiState(pid));
  if (!pickerResult.completed) {
    console.log(sheetDump(pid));
  } else {
    console.log("picker:", pickerResult.state);
  }

  const extensions = await listExtensions(cdp.call.bind(cdp));
  console.log("extensions:", JSON.stringify(extensions, null, 2));
  cdp.close();
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});