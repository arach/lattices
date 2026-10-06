import type { DriveLease, Point } from "@action/protocol";

/**
 * How a lease presents Action's pointer to the operator and to recorded pixels.
 *
 * `synthetic` draws Action's own cursor plus its identity badge. Every other
 * style leaves the normal macOS pointer alone and draws nothing.
 */
export type DriveCursorStyle = "synthetic" | "system";

export const DEFAULT_DRIVE_CURSOR_STYLE: DriveCursorStyle = "synthetic";

export interface AgentCursorCue {
  leaseId: string;
  agent?: string;
  point?: Point;
  /** `null` clears the badge; `undefined` keeps whatever is on screen. */
  label?: string | null;
  phase?: "idle" | "click" | "type" | "key" | "countdown";
  typingText?: string;
  keyLabel?: string;
  countdown?: number;
  cueId?: string;
  highlight?: {
    x: number;
    y: number;
    width: number;
    height: number;
  } | null;
}

/** Side-effecting cursor overlay calls, injected so the policy stays testable. */
export interface AgentCursorIO {
  start(input: { lease: DriveLease; label?: string; point?: Point }): Promise<void>;
  update(cue: AgentCursorCue): Promise<void>;
  stop(leaseId: string): Promise<void>;
  /** False once the overlay has quit, which it does on its own after an idle spell. */
  isLive(leaseId: string): Promise<boolean>;
}

export function parseDriveCursorStyle(raw: unknown): DriveCursorStyle {
  return raw === "system" ? "system" : DEFAULT_DRIVE_CURSOR_STYLE;
}

/**
 * Owns whether a drive lease is allowed to draw Action's synthetic cursor.
 *
 * The style is chosen once at `drive.begin` and must hold for every later call
 * on that lease, including the implicit lease touch inside `act.execute`. This
 * class is the only place that starts an overlay so no path can bypass it.
 */
export class DriveCursorPresenter {
  private readonly io: AgentCursorIO;
  private readonly styles = new Map<string, DriveCursorStyle>();
  private readonly presenting = new Set<string>();

  /** Per-lease choice from drive.begin: draw act cues or follow silently. */
  private readonly cuesEnabled = new Map<string, boolean>();
  /** Where each cursor was last sent, so a restarted overlay resumes there. */
  private readonly lastPoints = new Map<string, Point>();

  constructor(io: AgentCursorIO) {
    this.io = io;
  }

  /** Record the presentation contract the caller asked for at drive.begin. */
  recordStyle(leaseId: string, style: DriveCursorStyle): void {
    this.styles.set(leaseId, style);
  }

  styleFor(leaseId: string): DriveCursorStyle {
    return this.styles.get(leaseId) ?? DEFAULT_DRIVE_CURSOR_STYLE;
  }

  /** Record whether act cues should be drawn for this lease. */
  recordCues(leaseId: string, enabled: boolean): void {
    this.cuesEnabled.set(leaseId, enabled);
  }

  /** True unless the lease asked for a silent follower at drive.begin. */
  presentsCues(leaseId: string): boolean {
    return this.cuesEnabled.get(leaseId) ?? true;
  }

  /**
   * True only for the synthetic style. A lease with no recorded style keeps the
   * historical visible default; anything non-synthetic stays on the system
   * pointer with no cursor and no badge.
   */
  allowsAgentCursor(leaseId: string): boolean {
    return this.styleFor(leaseId) === "synthetic";
  }

  /** True when an overlay is actually live for this lease. */
  isPresenting(leaseId: string): boolean {
    return this.presenting.has(leaseId);
  }

  presentingLeaseIDs(): string[] {
    return [...this.presenting];
  }

  /** Start the cursor overlay for a lease that is allowed one, or renew a live one. */
  async ensure(lease: DriveLease, label?: string): Promise<void> {
    if (!this.allowsAgentCursor(lease.leaseId)) {
      return;
    }
    try {
      if (this.presenting.has(lease.leaseId)) {
        await this.renew(lease);
        return;
      }
      await this.start(lease, label);
    } catch {
      // Cursor presence is presentation. The native lease remains authoritative.
    }
  }

  /**
   * Push the idle heartbeat so a live overlay does not expire mid-drive. An
   * agent that thinks, edits, or deploys for longer than the overlay's idle
   * window comes back to an overlay that has already quit; start it again
   * where the cursor last was, or every later cue goes nowhere.
   */
  async renew(lease: DriveLease): Promise<void> {
    if (!this.presenting.has(lease.leaseId)) {
      return;
    }
    try {
      if (!(await this.io.isLive(lease.leaseId))) {
        await this.start(lease);
        return;
      }
      await this.io.update({
        leaseId: lease.leaseId,
        agent: lease.agent,
        label: lease.task,
        phase: "idle",
      });
    } catch {
      this.presenting.delete(lease.leaseId);
    }
  }

  /** Draw a cue on a live overlay. A lease without one is silently skipped. */
  async update(cue: AgentCursorCue): Promise<void> {
    if (!this.presenting.has(cue.leaseId)) {
      return;
    }
    if (cue.point) {
      this.lastPoints.set(cue.leaseId, cue.point);
    }
    try {
      await this.io.update(cue);
    } catch {
      this.presenting.delete(cue.leaseId);
    }
  }

  /** Drop the local presentation handle without writing a stop marker. */
  forget(leaseId: string): void {
    this.presenting.delete(leaseId);
    this.lastPoints.delete(leaseId);
  }

  /** Stop the overlay and clear the lease's recorded style and policies. */
  async release(leaseId: string): Promise<void> {
    this.presenting.delete(leaseId);
    this.styles.delete(leaseId);
    this.cuesEnabled.delete(leaseId);
    this.lastPoints.delete(leaseId);
    try {
      await this.io.stop(leaseId);
    } catch {
      // The native lease stop marker is the independent shutdown path.
    }
  }

  private async start(lease: DriveLease, label?: string): Promise<void> {
    await this.io.start({
      lease,
      label: label ?? lease.task,
      point: this.lastPoints.get(lease.leaseId),
    });
    this.presenting.add(lease.leaseId);
  }
}
