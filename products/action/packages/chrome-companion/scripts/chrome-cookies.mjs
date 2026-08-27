import crypto from "node:crypto";
import { copyFileSync, existsSync, mkdtempSync, mkdirSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { Database } from "bun:sqlite";
import {
  actionProfileDefaultDir,
  actionProfileUserDataDir,
  sanitizeProfileName,
} from "./action-profiles.mjs";

const chromeEpochOffset = 11644473600;

export const defaultPersonalChromeRoot = join(
  homedir(),
  "Library/Application Support/Google/Chrome",
);

export function personalChromeRoot() {
  return process.env.ACTION_CHROME_SOURCE_USER_DATA || defaultPersonalChromeRoot;
}

export function readLocalState(root = personalChromeRoot()) {
  return JSON.parse(readFileSync(join(root, "Local State"), "utf8"));
}

export function listPersonalProfiles(root = personalChromeRoot()) {
  const info = readLocalState(root).profile?.info_cache ?? {};
  return Object.entries(info)
    .map(([dir, meta]) => ({
      dir,
      name: meta.name || dir,
      activeTime: meta.active_time || 0,
      path: join(root, dir),
    }))
    .sort((left, right) => right.activeTime - left.activeTime);
}

export function resolveSourceProfileDir(profileDir) {
  if (process.env.ACTION_CHROME_SOURCE_PROFILE_DIR) {
    return process.env.ACTION_CHROME_SOURCE_PROFILE_DIR;
  }
  const root = personalChromeRoot();
  if (profileDir) {
    return join(root, profileDir);
  }
  const profiles = listPersonalProfiles(root);
  if (profiles.length === 0) {
    throw new Error(`No Chrome profiles found under ${root}`);
  }
  return profiles[0].path;
}

export function cookiesDatabasePath(profileDir) {
  return join(profileDir, "Cookies");
}

export function copyCookiesDatabase(profileDir) {
  const source = cookiesDatabasePath(profileDir);
  const tempDir = mkdtempSync(join(tmpdir(), "action-chrome-cookies-"));
  const copyPath = join(tempDir, "Cookies");
  copyFileSync(source, copyPath);
  return { copyPath, tempDir };
}

export function getChromeSafeStoragePassword() {
  const result = spawnSync("security", [
    "find-generic-password",
    "-w",
    "-s",
    "Chrome Safe Storage",
    "-a",
    "Chrome",
  ], { encoding: "utf8" });

  if (result.status !== 0) {
    throw new Error(
      "Could not read Chrome Safe Storage from the macOS Keychain. " +
      "Approve the Keychain prompt and retry.",
    );
  }

  const password = result.stdout.trim();
  if (!password) {
    throw new Error("Chrome Safe Storage keychain entry was empty.");
  }
  return password;
}

function deriveCookieKey(password) {
  return crypto.pbkdf2Sync(password, "saltysalt", 1003, 16, "sha1");
}

export function decryptCookieValue(encryptedValue, password, { stripDomainHash = true } = {}) {
  const blob = Buffer.from(encryptedValue);
  if (blob.length < 4 || blob.slice(0, 3).toString() !== "v10") {
    throw new Error(`Unsupported cookie encryption prefix: ${blob.slice(0, 3).toString()}`);
  }

  const key = deriveCookieKey(password);
  const decipher = crypto.createDecipheriv("aes-128-cbc", key, Buffer.alloc(16, 0x20));
  let decrypted = Buffer.concat([decipher.update(blob.slice(3)), decipher.final()]);
  const paddingLength = decrypted[decrypted.length - 1];
  decrypted = decrypted.slice(0, -paddingLength);

  if (stripDomainHash && decrypted.length > 32) {
    decrypted = decrypted.slice(32);
  }

  return decrypted.toString("utf8");
}

export function chromeExpiresToUnix(expiresUtc) {
  if (!expiresUtc) {
    return undefined;
  }
  return Math.floor(expiresUtc / 1_000_000) - chromeEpochOffset;
}

export function sameSiteFromChrome(code) {
  switch (code) {
    case 0:
      return "None";
    case 1:
      return "Lax";
    case 2:
      return "Strict";
    default:
      return undefined;
  }
}

export function domainMatches(hostKey, filters) {
  if (!filters?.length) {
    return true;
  }

  const normalizedHost = hostKey.startsWith(".") ? hostKey.slice(1) : hostKey;
  return filters.some((filter) => {
    const normalizedFilter = filter.startsWith(".") ? filter.slice(1) : filter;
    return normalizedHost === normalizedFilter ||
      normalizedHost.endsWith(`.${normalizedFilter}`) ||
      hostKey === `.${normalizedFilter}` ||
      hostKey.endsWith(`.${normalizedFilter}`);
  });
}

export function hostKeyMatches(hostKey, filter) {
  if (!filter) {
    return true;
  }

  const normalizedHost = hostKey.startsWith(".") ? hostKey.slice(1) : hostKey;
  const normalizedFilter = filter.startsWith(".") ? filter.slice(1) : filter;
  return hostKey === filter ||
    normalizedHost === normalizedFilter ||
    normalizedHost.endsWith(`.${normalizedFilter}`) ||
    hostKey === `.${normalizedFilter}`;
}

export function parseCookieSelectors(specs = []) {
  return specs.map((spec) => {
    const separator = spec.indexOf(":");
    if (separator === -1) {
      return { name: spec };
    }
    return {
      hostKey: spec.slice(0, separator),
      name: spec.slice(separator + 1),
    };
  });
}

export function cookieSelectorMatches(row, selector) {
  if (selector.hostKey && !hostKeyMatches(row.hostKey, selector.hostKey)) {
    return false;
  }
  return row.name === selector.name;
}

export function cookieMatches(row, { domains = [], selectors = [] } = {}) {
  if (domains.length && !domainMatches(row.hostKey, domains)) {
    return false;
  }

  if (selectors.length) {
    return selectors.some((selector) => cookieSelectorMatches(row, selector));
  }

  return domains.length > 0;
}

export function listCookieDomains(profileDir) {
  const { copyPath } = copyCookiesDatabase(profileDir);
  const db = new Database(copyPath, { readonly: true });
  try {
    const rows = db.query(`
      SELECT host_key as hostKey, COUNT(*) as count
      FROM cookies
      GROUP BY host_key
      ORDER BY count DESC, host_key ASC
    `).all();
    return rows;
  } finally {
    db.close();
  }
}

export function listCookieEntries(profileDir, { domains = [], selectors = [] } = {}) {
  const { copyPath } = copyCookiesDatabase(profileDir);
  const db = new Database(copyPath, { readonly: true });

  try {
    const rows = db.query(`
      SELECT
        host_key as hostKey,
        name,
        path,
        is_secure as isSecure,
        is_httponly as isHttpOnly,
        has_expires as hasExpires,
        expires_utc as expiresUtc,
        samesite as sameSite
      FROM cookies
      ORDER BY host_key ASC, name ASC
    `).all();

    return rows
      .filter((row) => cookieMatches(row, { domains, selectors }))
      .map((row) => ({
        hostKey: row.hostKey,
        name: row.name,
        path: row.path || "/",
        secure: Boolean(row.isSecure),
        httpOnly: Boolean(row.isHttpOnly),
        sameSite: sameSiteFromChrome(row.sameSite),
        expires: row.hasExpires ? chromeExpiresToUnix(row.expiresUtc) : undefined,
        selector: `${row.hostKey}:${row.name}`,
      }));
  } finally {
    db.close();
  }
}

export function readCookies(profileDir, { domains = [], selectors = [], decrypt = false } = {}) {
  const { copyPath } = copyCookiesDatabase(profileDir);
  const db = new Database(copyPath, { readonly: true });
  const password = decrypt ? getChromeSafeStoragePassword() : undefined;

  try {
    const rows = db.query(`
      SELECT
        host_key as hostKey,
        top_frame_site_key as topFrameSiteKey,
        name,
        path,
        encrypted_value as encryptedValue,
        expires_utc as expiresUtc,
        is_secure as isSecure,
        is_httponly as isHttpOnly,
        has_expires as hasExpires,
        samesite as sameSite,
        source_scheme as sourceScheme,
        source_port as sourcePort
      FROM cookies
      ORDER BY host_key ASC, name ASC
    `).all();

    return rows
      .filter((row) => cookieMatches(row, { domains, selectors }))
      .map((row) => {
        const cookie = {
          hostKey: row.hostKey,
          name: row.name,
          path: row.path || "/",
          secure: Boolean(row.isSecure),
          httpOnly: Boolean(row.isHttpOnly),
          sameSite: sameSiteFromChrome(row.sameSite),
          expires: row.hasExpires ? chromeExpiresToUnix(row.expiresUtc) : undefined,
          domain: row.hostKey.startsWith(".") ? row.hostKey.slice(1) : row.hostKey,
        };

        if (decrypt) {
          cookie.value = decryptCookieValue(row.encryptedValue, password);
        }

        return cookie;
      });
  } finally {
    db.close();
  }
}

export function summarizeCookies(cookies) {
  const byHost = new Map();
  for (const cookie of cookies) {
    const entry = byHost.get(cookie.hostKey) ?? { hostKey: cookie.hostKey, count: 0, names: [], selectors: [] };
    entry.count += 1;
    entry.names.push(cookie.name);
    entry.selectors.push(`${cookie.hostKey}:${cookie.name}`);
    byHost.set(cookie.hostKey, entry);
  }
  return [...byHost.values()].sort((left, right) => right.count - left.count);
}

export function describeSelection({ domains = [], selectors = [] }) {
  if (selectors.length) {
    return selectors.map((selector) => (
      selector.hostKey ? `${selector.hostKey}:${selector.name}` : selector.name
    ));
  }
  return domains;
}

const cookieColumns = [
  "creation_utc",
  "host_key",
  "top_frame_site_key",
  "name",
  "value",
  "encrypted_value",
  "path",
  "expires_utc",
  "is_secure",
  "is_httponly",
  "last_access_utc",
  "has_expires",
  "is_persistent",
  "priority",
  "samesite",
  "source_scheme",
  "source_port",
  "last_update_utc",
  "source_type",
  "has_cross_site_ancestor",
];

/**
 * Directory containing the Chrome Cookies SQLite file for an Action profile.
 * Prefer actionProfileDefaultDir / actionProfileUserDataDir for new code.
 */
export function targetProfileDir(profileName = "mira") {
  if (process.env.ACTION_CHROME_COMPANION_PROFILE_DIR) {
    const override = process.env.ACTION_CHROME_COMPANION_PROFILE_DIR;
    if (existsSync(join(override, "Cookies"))) return override;
    return join(override, "Default");
  }
  return actionProfileDefaultDir(profileName);
}

export function targetUserDataDir(profileName = "mira") {
  if (process.env.ACTION_CHROME_COMPANION_PROFILE_DIR) {
    return process.env.ACTION_CHROME_COMPANION_PROFILE_DIR;
  }
  return actionProfileUserDataDir(profileName);
}

/** Ensure dest profile Default/ exists and has a cookies table matching source schema. */
export function ensureCookiesDatabase(destProfileDir, sourceCookiesPath) {
  mkdirSync(destProfileDir, { recursive: true });
  const destPath = join(destProfileDir, "Cookies");
  if (existsSync(destPath)) {
    return destPath;
  }
  if (!sourceCookiesPath || !existsSync(sourceCookiesPath)) {
    throw new Error(
      `Destination cookies database missing at ${destPath}. ` +
      "Launch the Action profile once (or run profile setup) so Chrome creates Default/, then retry.",
    );
  }
  const sourceDb = new Database(sourceCookiesPath, { readonly: true });
  try {
    const createSql = sourceDb
      .query("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'cookies'")
      .get()?.sql;
    if (!createSql) {
      throw new Error("Source cookies database has no cookies table.");
    }
    const destDb = new Database(destPath);
    try {
      destDb.exec(createSql);
      const indexes = sourceDb
        .query("SELECT sql FROM sqlite_master WHERE type = 'index' AND tbl_name = 'cookies' AND sql IS NOT NULL")
        .all();
      for (const index of indexes) {
        try {
          destDb.exec(index.sql);
        } catch {
          // Index names may collide; table is enough for INSERT OR REPLACE.
        }
      }
    } finally {
      destDb.close();
    }
  } finally {
    sourceDb.close();
  }
  return destPath;
}

export function copyCookiesToProfile(sourceProfileDir, destProfileDir, { domains = [], selectors = [] } = {}) {
  const { copyPath } = copyCookiesDatabase(sourceProfileDir);
  const destPath = ensureCookiesDatabase(destProfileDir, copyPath);
  const sourceDb = new Database(copyPath, { readonly: true });
  const destDb = new Database(destPath);
  const columnList = cookieColumns.join(", ");
  const placeholders = cookieColumns.map(() => "?").join(", ");
  const insert = destDb.prepare(
    `INSERT OR REPLACE INTO cookies (${columnList}) VALUES (${placeholders})`,
  );

  const rows = sourceDb.query(`SELECT ${columnList} FROM cookies`).all();
  const selected = rows.filter((row) => cookieMatches({
    hostKey: row.host_key,
    name: row.name,
  }, { domains, selectors }));

  destDb.exec("BEGIN");
  try {
    for (const row of selected) {
      insert.run(...cookieColumns.map((column) => row[column]));
    }
    destDb.exec("COMMIT");
  } catch (error) {
    destDb.exec("ROLLBACK");
    throw error;
  } finally {
    sourceDb.close();
    destDb.close();
  }

  return selected.map((row) => `${row.host_key}:${row.name}`);
}

export function importCookiesToActionProfile({
  into,
  sourceProfile,
  domains = [],
  selectors = [],
} = {}) {
  const name = sanitizeProfileName(into || process.env.ACTION_CHROME_COMPANION_PROFILE || "agent-browser");
  const sourceProfilePath = resolveSourceProfileDir(sourceProfile);
  const destProfilePath = targetProfileDir(name);
  const destUserDataDir = targetUserDataDir(name);
  const copied = copyCookiesToProfile(sourceProfilePath, destProfilePath, {
    domains,
    selectors,
  });
  return {
    into: name,
    sourceProfilePath,
    destUserDataDir,
    destProfilePath,
    cookies: copied,
    count: copied.length,
  };
}
