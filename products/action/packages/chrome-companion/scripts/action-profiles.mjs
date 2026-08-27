import { existsSync, readdirSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

export const defaultActionProfileRoot = join(
  homedir(),
  "Library/Application Support/Action/ChromeProfiles",
);

export function actionProfileRoot() {
  return process.env.ACTION_CHROME_COMPANION_PROFILE_ROOT
    || process.env.ACTION_BROWSER_PROFILE_ROOT
    || defaultActionProfileRoot;
}

/** Chrome --user-data-dir for a named Action identity. */
export function actionProfileUserDataDir(profileName) {
  if (process.env.ACTION_CHROME_COMPANION_PROFILE_DIR && !profileName) {
    return process.env.ACTION_CHROME_COMPANION_PROFILE_DIR;
  }
  if (process.env.ACTION_BROWSER_PROFILE_DIR && !profileName) {
    return process.env.ACTION_BROWSER_PROFILE_DIR;
  }
  const name = sanitizeProfileName(profileName
    || process.env.ACTION_CHROME_COMPANION_PROFILE
    || process.env.ACTION_BROWSER_PROFILE
    || "agent-browser");
  return join(actionProfileRoot(), name);
}

/**
 * Directory that holds Cookies/Preferences for the default profile inside
 * a user-data-dir (Chrome layout: <user-data-dir>/Default).
 */
export function actionProfileDefaultDir(profileName) {
  const userData = actionProfileUserDataDir(profileName);
  // Absolute override that already points at .../Default is rare; detect Cookies.
  if (existsSync(join(userData, "Cookies"))) {
    return userData;
  }
  return join(userData, "Default");
}

export function sanitizeProfileName(name) {
  const cleaned = String(name || "").trim().replace(/[^A-Za-z0-9._-]/g, "-");
  if (!cleaned || cleaned === "." || cleaned === "..") {
    throw new Error(`Invalid Action profile name: ${name}`);
  }
  return cleaned;
}

export function listActionProfiles() {
  const root = actionProfileRoot();
  if (!existsSync(root)) {
    return [];
  }
  return readdirSync(root, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && !entry.name.startsWith("."))
    .map((entry) => {
      const name = entry.name;
      const userDataDir = join(root, name);
      const defaultDir = existsSync(join(userDataDir, "Cookies"))
        ? userDataDir
        : join(userDataDir, "Default");
      const metaPath = join(userDataDir, ".action-profile.json");
      let meta = null;
      if (existsSync(metaPath)) {
        try {
          meta = JSON.parse(readFileSync(metaPath, "utf8"));
        } catch {
          meta = null;
        }
      }
      return {
        name,
        userDataDir,
        defaultDir,
        cookiesPath: join(defaultDir, "Cookies"),
        hasCookiesDb: existsSync(join(defaultDir, "Cookies")),
        meta,
      };
    })
    .sort((left, right) => left.name.localeCompare(right.name));
}

export function ensureActionProfile(profileName, {
  debugPort = process.env.ACTION_BROWSER_DEBUG_PORT
    || process.env.ACTION_CHROME_COMPANION_DEBUG_PORT
    || "9334",
  extensionDist,
} = {}) {
  const name = sanitizeProfileName(profileName);
  const userDataDir = actionProfileUserDataDir(name);
  const defaultDir = join(userDataDir, "Default");
  mkdirSync(defaultDir, { recursive: true });
  const meta = {
    name,
    profileDir: userDataDir,
    defaultDir,
    extensionDist: extensionDist || null,
    debugPort: String(debugPort),
    updatedAt: new Date().toISOString(),
  };
  writeFileSync(
    join(userDataDir, ".action-profile.json"),
    `${JSON.stringify(meta, null, 2)}\n`,
  );
  return meta;
}
