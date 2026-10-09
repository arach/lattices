// Daemon-socket pairing: the gate (who may call what), scope, and the signed
// upgrade, checked against the CLI's own signer in bin/host-pairing.ts.
import { describe, expect, test } from "bun:test";
import { generateKeyPairSync, randomBytes, randomUUID } from "node:crypto";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { PairingApprovals } from "../src/bridge/approval.ts";
import { BridgeSecurityError, HEADERS, type TrustedDevice } from "../src/bridge/security.ts";
import { DaemonPairing, gate, grantScope, scopeOf, type ConnAuth } from "../src/pairing.ts";
import { Router } from "../src/router.ts";
import { pairedHost, signUpgrade, signingKey } from "../../../bin/host-pairing.ts";

const device = (capabilities: string[]): TrustedDevice => ({
  id: "c1",
  name: "arts-mini",
  publicKey: "",
  fingerprint: "",
  platform: "darwin",
  capabilities,
  pairedAt: "",
  lastSeenAt: "",
});
const read = { method: "windows.list", access: "read" as const };
const mutate = { method: "windows.place", access: "mutate" as const };
const approve = { method: "clients.approve", access: "mutate" as const, loopbackOnly: true };
const pair = { method: "clients.pair", access: "read" as const };

describe("gate", () => {
  const local: ConnAuth = { local: true, client: null, pairingRequired: true };
  const unpaired: ConnAuth = { local: false, client: null, pairingRequired: true };
  const reader: ConnAuth = { local: false, client: device(["read"]), pairingRequired: true };
  const writer: ConnAuth = { local: false, client: device(["mutate", "read"]), pairingRequired: true };
  const noPairing: ConnAuth = { local: false, client: null, pairingRequired: false };

  test("loopback may call anything, including approval", () => {
    for (const m of [read, mutate, approve, pair]) expect(gate(local, m)).toBeNull();
  });

  test("an unpaired remote client may only pair", () => {
    expect(gate(unpaired, pair)).toBeNull();
    expect(gate(unpaired, read)).toStartWith("pairing_required");
    expect(gate(unpaired, mutate)).toStartWith("pairing_required");
  });

  test("scope: read clients read, mutate clients do both", () => {
    expect(gate(reader, read)).toBeNull();
    expect(gate(reader, mutate)).toStartWith("scope_denied");
    expect(gate(writer, read)).toBeNull();
    expect(gate(writer, mutate)).toBeNull();
  });

  test("approval is never grantable remotely, paired or not, pairing on or off", () => {
    for (const conn of [unpaired, reader, writer, noPairing]) expect(gate(conn, approve)).toStartWith("loopback_only");
  });

  test("--no-pairing admits remote clients fully, except loopback-only methods", () => {
    expect(gate(noPairing, read)).toBeNull();
    expect(gate(noPairing, mutate)).toBeNull();
  });

  test("scope grants: mutate implies read, anything else is read", () => {
    expect(grantScope(["mutate"])).toEqual(["mutate", "read"]);
    expect(grantScope(["read"])).toEqual(["read"]);
    expect(grantScope(["admin"])).toEqual(["read"]);
    expect(grantScope(undefined)).toEqual(["read"]);
    expect(scopeOf(["read"])).toBe("read");
    expect(scopeOf(["mutate", "read"])).toBe("mutate");
  });

  test("the router looks up endpoints through aliases for the gate", () => {
    const router = new Router(() => new Set());
    router.register({ method: "windows.place", description: "", access: "mutate", returns: "", handler: () => null });
    expect(router.lookup("window.tile")?.method).toBe("windows.place");
    expect(router.lookup("nope")).toBeUndefined();
  });
});

describe("DaemonPairing", () => {
  const setup = (now = () => new Date()) => {
    const approvals = new PairingApprovals(5_000, false);
    const pairing = new DaemonPairing("archie", { stateDir: mkdtempSync(join(tmpdir(), "lattices-pair-")), approvals, now });
    const key = generateKeyPairSync("x25519");
    const publicKey = Buffer.from(key.publicKey.export({ format: "jwk" }).x as string, "base64url").toString("base64");
    const clientID = randomUUID();
    const params = (scope: string) => ({ clientID, clientName: "arts-mini", publicKey, platform: "darwin", scope });
    const identity = { user: "arach@github", node: "arts-mini" };
    /** Pair, deciding as a person would once the request is pending. */
    const pairAs = async (scope: string, decision: boolean) => {
      const result = pairing.pair(params(scope), identity);
      await Bun.sleep(5);
      approvals.decide(clientID, decision);
      return result;
    };
    const headers = (hostPublicKey: string, opts: { timestamp?: string; nonce?: string; path?: string; id?: string } = {}) => {
      const timestamp = opts.timestamp ?? new Date().toISOString();
      const nonce = opts.nonce ?? randomBytes(16).toString("hex");
      const k = signingKey(key.privateKey, hostPublicKey);
      return new Headers({
        [HEADERS.deviceID]: opts.id ?? clientID,
        [HEADERS.timestamp]: timestamp,
        [HEADERS.nonce]: nonce,
        [HEADERS.signature]: signUpgrade(k, opts.path ?? "/", clientID, timestamp, nonce),
      });
    };
    return { approvals, pairing, clientID, identity, pairAs, headers, params };
  };

  test("pairing waits for a person; denial stores nothing", async () => {
    const { pairing, pairAs } = setup();
    const denied = await pairAs("mutate", false);
    expect(denied.disposition).toBe("denied");
    expect(pairing.clients()).toEqual([]);
  });

  test("approved pairing records name, node (from whois), scope and times", async () => {
    const { pairing, pairAs, clientID } = setup();
    const result = await pairAs("read", true);
    expect(result.disposition).toBe("approved");
    expect(result.scope).toBe("read");
    expect(result.hostFingerprint).toBe(pairing.security.fingerprint);
    const [client] = pairing.clients();
    expect(client).toMatchObject({ id: clientID, name: "arts-mini", node: "arts-mini", scope: "read" });
    expect(client!.createdAt).toBeTruthy();
    expect(client!.lastSeenAt).toBeTruthy();
  });

  test("a read client asking for mutate needs a second approval", async () => {
    const { pairing, pairAs } = setup();
    await pairAs("read", true);
    expect((await pairAs("mutate", false)).scope).toBe("read");
    expect((await pairAs("mutate", true)).scope).toBe("mutate");
    expect(pairing.clients()[0]!.scope).toBe("mutate");
  });

  test("the CLI's signed upgrade authenticates; tampering, replay and skew do not", async () => {
    const { pairing, pairAs, headers } = setup();
    const { hostPublicKey } = await pairAs("mutate", true);
    expect(pairing.authenticate("/", headers(hostPublicKey))?.name).toBe("arts-mini");
    // No client id: an unpaired connection, which the gate limits to pairing.
    expect(pairing.authenticate("/", new Headers())).toBeNull();

    const replayed = headers(hostPublicKey);
    pairing.authenticate("/", replayed);
    expect(() => pairing.authenticate("/", replayed)).toThrow("nonce was already used");

    expect(() => pairing.authenticate("/other", headers(hostPublicKey))).toThrow("signature is invalid");
    const stale = new Date(Date.now() - 10 * 60_000).toISOString();
    expect(() => pairing.authenticate("/", headers(hostPublicKey, { timestamp: stale }))).toThrow("outside the allowed window");
    const forged = headers(hostPublicKey);
    forged.set(HEADERS.signature, Buffer.alloc(32).toString("base64"));
    expect(() => pairing.authenticate("/", forged)).toThrow(BridgeSecurityError);
  });

  test("a revoked client is refused (403) until it pairs again", async () => {
    const { pairing, pairAs, headers, clientID } = setup();
    const { hostPublicKey } = await pairAs("mutate", true);
    expect(pairing.revoke(clientID)).toBe(true);
    try {
      pairing.authenticate("/", headers(hostPublicKey));
      throw new Error("expected refusal");
    } catch (err) {
      expect((err as BridgeSecurityError).status).toBe(403);
    }
  });

  test("a client key cannot be swapped without a new approval", async () => {
    const { pairing, approvals, pairAs, params, identity, clientID } = setup();
    await pairAs("mutate", true);
    const other = generateKeyPairSync("x25519");
    const otherKey = Buffer.from(other.publicKey.export({ format: "jwk" }).x as string, "base64url").toString("base64");
    const attempt = pairing.pair({ ...params("mutate"), publicKey: otherKey }, identity);
    await Bun.sleep(5);
    expect(approvals.list().map((p) => p.deviceID)).toEqual([clientID]);
    approvals.decide(clientID, false);
    expect((await attempt).disposition).toBe("denied");
  });
});

describe("client pairing store", () => {
  const hosts = {
    "100.64.0.7:9399": { host: "archie", hostPublicKey: "k", hostFingerprint: "F", scope: "mutate" as const, pairedAt: "" },
  };
  test("finds a pairing by address or by the host's tailnet name", () => {
    expect(pairedHost({ host: "100.64.0.7", port: 9399 }, hosts)?.host).toBe("archie");
    expect(pairedHost({ host: "archie", port: 9399 }, hosts)?.host).toBe("archie");
    expect(pairedHost({ host: "archie.tail1234.ts.net", port: 9399 }, hosts)?.host).toBe("archie");
    expect(pairedHost({ host: "archie", port: 19400 }, hosts)).toBeNull();
    expect(pairedHost({ host: "127.0.0.1", port: 9399 }, hosts)).toBeNull();
  });
});
