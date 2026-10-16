import type { AuthorizedRequest, BridgeSecurity } from "./security.ts";
import { openVisitFrame, sealVisitFrame } from "./security.ts";
import { parseVisitMessage, VisitSession, type VisitDependencies, type VisitDown, type VisitorOverlay } from "./visit.ts";

export const VISIT_SILENCE_MS = 6_000;
export interface VisitSocket {
  send(frame: Buffer): unknown;
  close(code: number, reason: string): void;
}

/** One physical seat can lend focus to only one visitor at a time. */
export class Visits {
  private owner: VisitChannel | null = null;
  readonly channels = new Set<VisitChannel>();
  constructor(readonly overlay: VisitorOverlay, readonly deps?: VisitDependencies) {
    overlay.onFailure = (error) => this.owner?.fail(error);
  }
  claim(channel: VisitChannel): VisitSession {
    if (this.owner) throw new Error("Another visit is active");
    this.owner = channel;
    return new VisitSession(this.overlay, this.deps);
  }
  release(channel: VisitChannel) { if (this.owner === channel) this.owner = null; }
  async stop() {
    await Promise.all([...this.channels].map((channel) => channel.finish(1001, "Host stopping")));
    await this.overlay.stop();
  }
}

export class VisitChannel {
  private upSeq = 0;
  private downSeq = 0;
  private key: Buffer;
  private session: VisitSession | null = null;
  private closed = false;
  private timer!: ReturnType<typeof setTimeout>;
  private queue: Promise<void> = Promise.resolve();
  private queued = 0;
  private queuedBytes = 0;
  private cleanup: Promise<void> | null = null;
  constructor(private ws: VisitSocket, private auth: AuthorizedRequest, security: BridgeSecurity, private visits: Visits,
    private silenceMs = VISIT_SILENCE_MS) {
    this.key = security.visitEncryptionKey(auth);
    visits.channels.add(this);
    this.arm();
  }

  get deviceID() { return this.auth.device.id; }

  private arm() {
    clearTimeout(this.timer);
    this.timer = setTimeout(() => void this.finish(1001, "Visit timed out"), this.silenceMs);
  }
  private send(value: VisitDown) {
    if (this.closed) return;
    try { this.ws.send(sealVisitFrame(this.key, Buffer.from(JSON.stringify(value)), "down", this.auth.device.id, this.auth.nonce, this.downSeq++)); }
    catch { void this.finish(1011, "Visit output failed"); }
  }

  fail(error: Error) { this.send({ t: "error", message: error.message }); void this.finish(1011, "Visitor overlay failed"); }

  receive(frame: string | Buffer) {
    if (this.closed) return;
    let message;
    try {
      if (typeof frame === "string" || frame.length > 512 * 1024) throw new Error("Binary visit frame required");
      const plaintext = openVisitFrame(this.key, frame, "up", this.auth.device.id, this.auth.nonce, this.upSeq);
      message = parseVisitMessage(JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(plaintext)));
      this.upSeq++;
      if (this.queued >= 256 || this.queuedBytes + frame.length > 2 * 1024 * 1024) throw new Error("Visit input backlog");
    } catch {
      void this.finish(1008, "Invalid visit frame");
      return;
    }
    this.arm();
    // Ping is independent of potentially slow keyboard input. Its pong keeps
    // the other side alive without reordering any desktop input operations.
    if (message.t === "ping") { this.send({ t: "pong" }); return; }
    const bytes = frame.length;
    this.queued++;
    this.queuedBytes += bytes;
    const input = message;
    this.queue = this.queue.then(async () => {
      if (this.closed) return;
      try {
        if (input.t === "enter") {
          if (this.session) throw new Error("Visit already entered");
          const session = this.visits.claim(this);
          this.session = session;
          try { this.send(await session.enter(input)); }
          catch (error) {
            await session.end();
            this.session = null;
            this.visits.release(this);
            throw error;
          }
        } else if (input.t === "leave") {
          // finish queues teardown after this operation; never await it here.
          void this.finish(1000, "Visit ended");
        } else {
          if (!this.session) throw new Error("Enter a visit first");
          const response = await this.session.perform(input);
          if (response) this.send(response);
          if (response?.t === "exit") void this.finish(1000, "Visitor returned home");
        }
      } catch (error) { this.send({ t: "error", message: (error as Error).message }); }
    }).finally(() => { this.queued--; this.queuedBytes -= bytes; });
  }

  /** Idempotent and waits for in-flight input before releasing the seat. */
  finish(code = 1000, reason = "Visit disconnected"): Promise<void> {
    if (this.cleanup) return this.cleanup;
    this.closed = true;
    clearTimeout(this.timer);
    this.ws.close(code, reason);
    this.cleanup = this.queue.then(async () => {
      try { await this.session?.end(); }
      finally {
        this.session = null;
        this.visits.release(this);
        this.visits.channels.delete(this);
      }
    });
    return this.cleanup;
  }
}
