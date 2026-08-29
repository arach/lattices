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
  label?: string;
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
  start(input: { lease: DriveLease; label?: string }): Promise<void>;
  update(cue: AgentCursorCue): Promise<void>;
  stop(leaseId: string): Promise<void>;
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
      await this.io.start({ lease, label: label ?? lease.task });
      this.presenting.add(lease.leaseId);
    } catch {
      // Cursor presence is presentation. The native lease remains authoritative.
    }
  }

  /** Push the idle heartbeat so a live overlay does not expire mid-drive. */
  async renew(lease: DriveLease): Promise<void> {
    if (!this.presenting.has(lease.leaseId)) {
      return;
    }
    try {
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
    try {
      await this.io.update(cue);
    } catch {
      this.presenting.delete(cue.leaseId);
    }
  }

  /** Drop the local presentation handle without writing a stop marker. */
  forget(leaseId: string): void {
    this.presenting.delete(leaseId);
  }

  /** Stop the overlay and clear the lease's recorded style. */
  async release(leaseId: string): Promise<void> {
    this.presenting.delete(leaseId);
    this.styles.delete(leaseId);
    try {
      await this.io.stop(leaseId);
    } catch {
      // The native lease stop marker is the independent shutdown path.
    }
  }
}
