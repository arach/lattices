#!/usr/bin/env bun

import { access } from "node:fs/promises";
import {
  companionName,
  dist,
  ensureExtensionsTarget,
  launchMiraExtensions,
  listExtensions,
  miraChromePid,
  pollPickerAndComplete,
  profileName,
  stageMiraWindow,
  triggerLoadUnpacked,
  activateMiraExtensionsWindow,
  completePicker,
  sleep,
} from "./mira-chrome.mjs";

async function main() {
  await access(dist);
  console.log(`Installing ${companionName} from ${dist}`);
  console.log(`Target profile: ${profileName} (never personal Chrome)`);

  let page;
  try {
    page = await ensureExtensionsTarget();
  } catch {
    await launchMiraExtensions();
    page = await ensureExtensionsTarget();
  }

  const pid = miraChromePid();
  console.log(`mira Chrome pid: ${pid}`);

  const cdp = await stageMiraWindow(page, pid);

  const before = await listExtensions(cdp.call.bind(cdp));
  if (before.some((entry) => entry.name === companionName)) {
    console.log(`${companionName} is already installed.`);
    console.log(JSON.stringify(before, null, 2));
    cdp.close();
    return;
  }

  console.log("Triggering Load unpacked...");
  const triggerResult = await triggerLoadUnpacked(cdp.call.bind(cdp));
  console.log("extensions UI:", JSON.stringify(triggerResult, null, 2));
  activateMiraExtensionsWindow(pid);
  await sleep(800);

  const pickerResult = await pollPickerAndComplete(pid, dist, 20000);
  if (!pickerResult.completed) {
    console.log("Picker not detected; attempting go-to-folder path entry anyway.");
    completePicker(pid, dist);
  } else {
    console.log("picker:", pickerResult.state);
  }

  await sleep(2500);
  const extensions = await listExtensions(cdp.call.bind(cdp));
  console.log("extensions:", JSON.stringify(extensions, null, 2));
  cdp.close();

  if (!extensions.some((entry) => entry.name === companionName)) {
    throw new Error(`${companionName} was not installed`);
  }

  console.log(`Installed ${companionName} successfully.`);
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});