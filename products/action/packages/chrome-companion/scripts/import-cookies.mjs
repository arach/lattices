#!/usr/bin/env bun

import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { join } from "node:path";

import {
  actionProfileUserDataDir,
  ensureActionProfile,
  listActionProfiles,
  sanitizeProfileName,
} from "./action-profiles.mjs";
import {
  importCookiesToActionProfile,
  listCookieEntries,
  listPersonalProfiles,
  parseCookieSelectors,
  readCookies,
  resolveSourceProfileDir,
  targetProfileDir,
  targetUserDataDir,
} from "./chrome-cookies.mjs";

const rootPath = fileURLToPath(new URL("..", import.meta.url));
const args = process.argv.slice(2);

function parseArgs(values) {
  const parsed = {
    command: "help",
    into: process.env.ACTION_CHROME_COMPANION_PROFILE
      || process.env.ACTION_BROWSER_PROFILE
      || "agent-browser",
    sourceProfile: undefined,
    domains: [],
    only: [],
    confirm: false,
    json: false,
    listSourceProfiles: false,
    listActionProfiles: false,
    launch: false,
    launchUrl: undefined,
  };

  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];
    if (value === "list" || value === "list-domains") {
      parsed.command = "list";
    } else if (value === "import") {
      parsed.command = "import";
    } else if (value === "help" || value === "--help" || value === "-h") {
      parsed.command = "help";
    } else if (value === "--into" || value === "--profile" || value === "--to") {
      parsed.into = values[++index];
    } else if (value === "--source") {
      parsed.sourceProfile = values[++index];
    } else if (value === "--domains") {
      parsed.domains = splitList(values[++index]);
    } else if (value === "--only" || value === "--names" || value === "--cookies") {
      parsed.only = splitList(values[++index]);
    } else if (value === "--confirm") {
      parsed.confirm = true;
    } else if (value === "--json") {
      parsed.json = true;
    } else if (value === "--list-profiles" || value === "--list-source-profiles") {
      parsed.listSourceProfiles = true;
    } else if (value === "--list-action-profiles") {
      parsed.listActionProfiles = true;
    } else if (value === "--launch") {
      parsed.launch = true;
    } else if (value === "--launch-url") {
      parsed.launch = true;
      parsed.launchUrl = values[++index];
    }
  }

  parsed.selectors = parseCookieSelectors(parsed.only);
  return parsed;
}

function splitList(raw) {
  return String(raw || "")
    .split(",")
    .map((entry) => entry.trim())
    .filter(Boolean);
}

function printHelp() {
  console.log(`Copy selected cookies from a regular Chrome profile into a named Action identity.

  # list your Chrome profiles: directory name, then display name
  bun scripts/import-cookies.mjs --list-profiles

  # list Action-owned identities
  bun scripts/import-cookies.mjs --list-action-profiles

  # dry-run: seed the "work" identity from the "Work" browser (dir "Profile 1")
  bun scripts/import-cookies.mjs list --into work --source "Profile 1" --domains github.com

  # import (requires --confirm)
  bun scripts/import-cookies.mjs import --into work --source "Profile 1" --domains github.com --confirm

  # narrow to specific cookie names
  bun scripts/import-cookies.mjs import --into mira --domains midjourney.com \\
    --only cf_clearance --confirm

Options:
  --into <name>          Action identity to seed (default: agent-browser or env)
  --source <profile>     Chrome profile DIR name, not its display name (Default, Profile 1, ...)
  --domains <sites>      Limit by host suffix (comma-separated)
  --only <cookies>       Cookie names, or host:name for one exact cookie
  --confirm              Actually write cookies (otherwise dry-run)
  --launch               After import, launch the Action profile in Chrome
  --launch-url <url>     Launch URL (implies --launch)
  --json                 Machine-readable output
  --list-profiles        List personal Chrome profiles
  --list-action-profiles List Action ChromeProfiles/*

Policy:
  Prefer named Action identities + selective domain seeds.
  Do not attach automation to your regular Chrome user-data-dir; that browser is
  driven with Action's native screen + accessibility tools instead.
`);
}

function ensureSelection(parsed) {
  if (!parsed.domains.length && !parsed.selectors.length) {
    throw new Error("Pass --domains and/or --only.");
  }
}

function printCookieList(cookies) {
  for (const cookie of cookies) {
    console.log(`${cookie.hostKey}  ${cookie.name}`);
  }
}

function stopActionChrome(userDataDir) {
  const result = spawnSync("pgrep", ["-f", `--user-data-dir=${userDataDir}`], {
    encoding: "utf8",
  });
  const pids = (result.stdout || "").trim().split("\n").filter(Boolean);
  for (const pid of pids) {
    spawnSync("kill", [pid]);
  }
  return pids;
}

function launchActionProfile(name, url) {
  const launch = spawnSync("bun", [
    "scripts/profile.mjs",
    "launch",
    name,
    ...(url ? ["--url", url] : []),
  ], {
    cwd: rootPath,
    stdio: "inherit",
  });
  if (launch.status !== 0) {
    throw new Error(`Failed to launch Action profile ${name}`);
  }
}

async function main() {
  const parsed = parseArgs(args);

  if (parsed.listSourceProfiles) {
    const profiles = listPersonalProfiles();
    console.log(parsed.json ? JSON.stringify(profiles, null, 2) : profiles.map((p) => `${p.dir}  ${p.name}`).join("\n"));
    return;
  }

  if (parsed.listActionProfiles) {
    const profiles = listActionProfiles();
    console.log(parsed.json ? JSON.stringify(profiles, null, 2) : profiles.map((p) => `${p.name}\t${p.userDataDir}`).join("\n") || "(none)");
    return;
  }

  if (parsed.command === "help" || args.length === 0) {
    printHelp();
    return;
  }

  const into = sanitizeProfileName(parsed.into);
  ensureActionProfile(into);
  const sourceProfilePath = resolveSourceProfileDir(parsed.sourceProfile);
  const destUserDataDir = targetUserDataDir(into);
  const destProfilePath = targetProfileDir(into);

  if (parsed.command === "list") {
    ensureSelection(parsed);
    const cookies = listCookieEntries(sourceProfilePath, {
      domains: parsed.domains,
      selectors: parsed.selectors,
    });
    if (parsed.json) {
      console.log(JSON.stringify({
        into,
        sourceProfilePath,
        destUserDataDir,
        destProfilePath,
        cookies,
      }, null, 2));
      return;
    }
    printCookieList(cookies);
    console.log(`\n${cookies.length} cookies from ${sourceProfilePath}`);
    console.log(`Would import into Action profile "${into}" (${destProfilePath})`);
    return;
  }

  if (parsed.command !== "import") {
    printHelp();
    process.exit(1);
  }

  ensureSelection(parsed);

  const matches = readCookies(sourceProfilePath, {
    domains: parsed.domains,
    selectors: parsed.selectors,
    decrypt: false,
  });

  if (matches.length === 0) {
    throw new Error("No matching cookies.");
  }

  if (!parsed.confirm) {
    if (parsed.json) {
      console.log(JSON.stringify({
        into,
        sourceProfilePath,
        destUserDataDir,
        count: matches.length,
        cookies: matches.map((cookie) => `${cookie.hostKey}:${cookie.name}`),
        confirmRequired: true,
      }, null, 2));
    } else {
      printCookieList(matches);
      console.log(`\n${matches.length} cookies ready. Re-run with --confirm to copy into "${into}".`);
    }
    return;
  }

  const stopped = stopActionChrome(destUserDataDir);
  if (stopped.length) {
    await Bun.sleep(1500);
  }

  const result = importCookiesToActionProfile({
    into,
    sourceProfile: parsed.sourceProfile,
    domains: parsed.domains,
    selectors: parsed.selectors,
  });

  if (parsed.launch) {
    launchActionProfile(into, parsed.launchUrl);
  }

  if (parsed.json) {
    console.log(JSON.stringify({ ok: true, ...result, launched: parsed.launch }, null, 2));
  } else {
    console.log(`Copied ${result.count} cookies into Action profile "${into}".`);
    console.log(`user-data-dir: ${result.destUserDataDir}`);
    if (parsed.launch) {
      console.log(`Launched profile "${into}".`);
    }
  }
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
