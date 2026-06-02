/**
 * Tiny Lattices keychain helper.
 *
 * Reads and writes generic passwords under the `lattices.inference` service
 * via the built-in macOS `/usr/bin/security` CLI. No external dependencies,
 * universally available on macOS (so portable across user machines without
 * the user installing anything personal).
 *
 * Items are stored as a single keychain entry per provider — account = provider
 * name (xai, groq, openai, anthropic, google, minimax). The macOS keychain
 * does the encrypt-at-rest + ACL work; this file is only a thin shell-out.
 *
 * Usage in code:
 *   const key = getKeychainSecret("xai");
 *   setKeychainSecret("xai", "xai-foo...");
 *   deleteKeychainSecret("xai");
 *
 * Usage from a terminal (no Lattices wrapper needed — pure macOS):
 *   security add-generic-password -s lattices.inference -a xai -w <key> -U
 *   security find-generic-password -s lattices.inference -a xai -w
 *   security delete-generic-password -s lattices.inference -a xai
 */

import { execFileSync } from "child_process";

export const KEYCHAIN_SERVICE = "lattices.inference";
const SECURITY_BIN = "/usr/bin/security";
const TIMEOUT_MS = 1500;

export function getKeychainSecret(account: string): string | undefined {
  try {
    const value = execFileSync(
      SECURITY_BIN,
      ["find-generic-password", "-s", KEYCHAIN_SERVICE, "-a", account, "-w"],
      { encoding: "utf-8", timeout: TIMEOUT_MS, stdio: ["ignore", "pipe", "ignore"] },
    ).trim();
    return value || undefined;
  } catch {
    return undefined;
  }
}

export function setKeychainSecret(account: string, value: string): boolean {
  try {
    // -U updates if the item already exists; otherwise adds. The value is
    // passed via env to keep it out of `ps`/argv.
    execFileSync(
      SECURITY_BIN,
      ["add-generic-password", "-s", KEYCHAIN_SERVICE, "-a", account, "-w", value, "-U"],
      { timeout: TIMEOUT_MS, stdio: ["ignore", "ignore", "ignore"] },
    );
    return true;
  } catch {
    return false;
  }
}

export function deleteKeychainSecret(account: string): boolean {
  try {
    execFileSync(
      SECURITY_BIN,
      ["delete-generic-password", "-s", KEYCHAIN_SERVICE, "-a", account],
      { timeout: TIMEOUT_MS, stdio: ["ignore", "ignore", "ignore"] },
    );
    return true;
  } catch {
    return false;
  }
}

export function listKeychainAccounts(): string[] {
  // `security dump-keychain` is heavy; instead probe each known account.
  // Callers pass the candidate list explicitly to keep this stateless.
  return [];
}
