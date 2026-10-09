// Pairing needs a person, as on the Mac. A pending request is shown as a
// desktop notification with Approve / Deny buttons (notify-send -A), and can
// also be decided over the host's own RPC (bridge.pairing.approve / deny),
// e.g. `lats --host archie call bridge.pairing.approve '{"deviceID":"..."}'`.
// Undecided requests are denied after the timeout.

import { spawn } from "node:child_process";
import { hasCommand } from "../exec.ts";
import { fingerprint, type PairingRequest } from "./security.ts";

export interface PendingPairing {
  deviceID: string;
  deviceName: string;
  platform: string;
  fingerprint: string;
  kind: "pair" | "upgrade";
  capabilities: string[];
  requestedAt: string;
}

interface Waiter {
  info: PendingPairing;
  resolve: (approved: boolean) => void;
  timer: ReturnType<typeof setTimeout>;
  notification?: ReturnType<typeof spawn>;
}

export class PairingApprovals {
  private pending = new Map<string, Waiter>();

  constructor(private readonly timeoutMs = 120_000, private readonly notify = hasCommand("notify-send")) {}

  list(): PendingPairing[] {
    return [...this.pending.values()].map((w) => w.info);
  }

  decide(deviceID: string, approved: boolean): boolean {
    const waiter = this.pending.get(deviceID);
    if (!waiter) return false;
    this.finish(deviceID, approved);
    return true;
  }

  request(request: PairingRequest, kind: "pair" | "upgrade", capabilities: string[]): Promise<boolean> {
    // A second request from the same device replaces the first.
    if (this.pending.has(request.deviceID)) this.finish(request.deviceID, false);
    const info: PendingPairing = {
      deviceID: request.deviceID,
      deviceName: request.deviceName,
      platform: request.platform,
      fingerprint: fingerprint(request.devicePublicKey),
      kind,
      capabilities,
      requestedAt: new Date().toISOString(),
    };
    return new Promise<boolean>((resolve) => {
      const waiter: Waiter = { info, resolve, timer: setTimeout(() => this.finish(request.deviceID, false), this.timeoutMs) };
      this.pending.set(request.deviceID, waiter);
      if (this.notify) waiter.notification = this.showNotification(info);
    });
  }

  private finish(deviceID: string, approved: boolean) {
    const waiter = this.pending.get(deviceID);
    if (!waiter) return;
    this.pending.delete(deviceID);
    clearTimeout(waiter.timer);
    waiter.notification?.kill();
    waiter.resolve(approved);
  }

  private showNotification(info: PendingPairing) {
    const title = info.kind === "pair" ? `Pair ${info.deviceName}?` : `${info.deviceName} asks for more access`;
    const body =
      `Code ${info.fingerprint} — check it matches the code on the device.\n` +
      (info.kind === "pair" ? "It will be able to: " : "New: ") +
      info.capabilities.join(", ");
    const child = spawn(
      "notify-send",
      ["--app-name=lattices-host", "--urgency=critical", "--wait", "-A", "approve=Approve", "-A", "deny=Deny", title, body],
      { stdio: ["ignore", "pipe", "ignore"] }
    );
    let out = "";
    child.stdout?.on("data", (d) => (out += String(d)));
    child.on("close", () => {
      const choice = out.trim();
      if (choice === "approve") this.finish(info.deviceID, true);
      else if (choice === "deny") this.finish(info.deviceID, false);
      // Dismissed without a choice: leave it pending for the RPC or the timeout.
    });
    child.on("error", () => {});
    return child;
  }
}
