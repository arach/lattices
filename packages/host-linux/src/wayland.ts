// A minimal Wayland client for one job: pointer input through
// zwlr_virtual_pointer_manager_v1, which Hyprland and other wlroots
// compositors implement. Needs no root and no uinput, unlike ydotool.
//
// Wire format: each message is [object id u32][size << 16 | opcode u32][args],
// native-endian (little-endian on every platform this runs on). Strings are a
// u32 length (including the NUL) followed by the bytes, padded to 4.

import { connect, type Socket } from "node:net";
import { join } from "node:path";

const DISPLAY_ID = 1;
const VIRTUAL_POINTER_MANAGER = "zwlr_virtual_pointer_manager_v1";

export const BUTTONS = { left: 0x110, right: 0x111, middle: 0x112 } as const;
export type Button = keyof typeof BUTTONS;

// zwlr_virtual_pointer_v1 request opcodes.
const Ptr = { MotionAbsolute: 1, Button: 2, Axis: 3, Frame: 4, AxisSource: 5, Destroy: 8 } as const;

type Arg = { u: number } | { i: number } | { fixed: number } | { s: string };

export function encodeMessage(objectId: number, opcode: number, args: Arg[]): Buffer {
  const parts: Buffer[] = [];
  for (const arg of args) {
    if ("s" in arg) {
      const bytes = Buffer.from(arg.s + "\0", "utf8");
      const len = Buffer.alloc(4);
      len.writeUInt32LE(bytes.length);
      const pad = Buffer.alloc((4 - (bytes.length % 4)) % 4);
      parts.push(len, bytes, pad);
    } else {
      const b = Buffer.alloc(4);
      if ("u" in arg) b.writeUInt32LE(arg.u >>> 0);
      else if ("i" in arg) b.writeInt32LE(arg.i | 0);
      else b.writeInt32LE(Math.round(arg.fixed * 256));
      parts.push(b);
    }
  }
  const body = Buffer.concat(parts);
  const header = Buffer.alloc(8);
  header.writeUInt32LE(objectId);
  header.writeUInt32LE(((body.length + 8) << 16) | opcode, 4);
  return Buffer.concat([header, body]);
}

interface Global {
  name: number;
  iface: string;
  version: number;
}

class WaylandConnection {
  private socket: Socket;
  private buffer = Buffer.alloc(0);
  private nextId = 2;
  private registryId = 0;
  private callbacks = new Map<number, () => void>();
  readonly globals: Global[] = [];
  private failure: Error | null = null;

  private constructor(socket: Socket) {
    this.socket = socket;
    socket.on("data", (chunk: Buffer) => this.onData(chunk));
    socket.on("error", (err) => this.fail(err));
    socket.on("close", () => this.fail(new Error("Wayland connection closed")));
  }

  static open(): Promise<WaylandConnection> {
    const runtime = process.env.XDG_RUNTIME_DIR;
    const display = process.env.WAYLAND_DISPLAY ?? "wayland-0";
    if (!runtime) return Promise.reject(new Error("XDG_RUNTIME_DIR is not set"));
    const path = display.startsWith("/") ? display : join(runtime, display);
    return new Promise((resolve, reject) => {
      const socket = connect(path);
      socket.once("connect", () => resolve(new WaylandConnection(socket)));
      socket.once("error", reject);
    });
  }

  newId() {
    return this.nextId++;
  }

  send(objectId: number, opcode: number, args: Arg[] = []) {
    if (this.failure) throw this.failure;
    this.socket.write(encodeMessage(objectId, opcode, args));
  }

  /** Round trip: resolves once the compositor has processed everything sent so far. */
  roundtrip(timeoutMs = 2000): Promise<void> {
    const id = this.newId();
    this.send(DISPLAY_ID, 0, [{ u: id }]); // wl_display.sync
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.callbacks.delete(id);
        reject(this.failure ?? new Error("Wayland roundtrip timed out"));
      }, timeoutMs);
      this.callbacks.set(id, () => {
        clearTimeout(timer);
        if (this.failure) reject(this.failure);
        else resolve();
      });
    });
  }

  async loadGlobals() {
    this.registryId = this.newId();
    this.send(DISPLAY_ID, 1, [{ u: this.registryId }]); // wl_display.get_registry
    await this.roundtrip();
  }

  bind(global: Global, version: number): number {
    const id = this.newId();
    this.send(this.registryId, 0, [{ u: global.name }, { s: global.iface }, { u: version }, { u: id }]);
    return id;
  }

  close() {
    this.socket.end();
  }

  private fail(error: Error) {
    this.failure ??= error;
    for (const done of this.callbacks.values()) done();
    this.callbacks.clear();
  }

  private onData(chunk: Buffer) {
    this.buffer = Buffer.concat([this.buffer, chunk]);
    while (this.buffer.length >= 8) {
      const objectId = this.buffer.readUInt32LE(0);
      const word = this.buffer.readUInt32LE(4);
      const size = word >>> 16;
      const opcode = word & 0xffff;
      if (size < 8 || this.buffer.length < size) break;
      const body = this.buffer.subarray(8, size);
      this.buffer = this.buffer.subarray(size);
      this.onEvent(objectId, opcode, body);
    }
  }

  private onEvent(objectId: number, opcode: number, body: Buffer) {
    if (objectId === DISPLAY_ID && opcode === 0) {
      // wl_display.error(object, code, message)
      const message = readString(body, 8).value;
      this.fail(new Error(`Wayland protocol error: ${message}`));
      return;
    }
    if (objectId === this.registryId && opcode === 0) {
      // wl_registry.global(name, interface, version)
      const name = body.readUInt32LE(0);
      const iface = readString(body, 4);
      const version = body.readUInt32LE(iface.next);
      this.globals.push({ name, iface: iface.value, version });
      return;
    }
    const callback = this.callbacks.get(objectId);
    if (callback && opcode === 0) {
      // wl_callback.done
      this.callbacks.delete(objectId);
      callback();
    }
  }
}

function readString(body: Buffer, offset: number): { value: string; next: number } {
  const length = body.readUInt32LE(offset);
  const value = body.subarray(offset + 4, offset + 4 + Math.max(0, length - 1)).toString("utf8");
  return { value, next: offset + 4 + Math.ceil(length / 4) * 4 };
}

export interface Extent {
  /** Layout bounding box the absolute coordinates map onto. */
  x: number;
  y: number;
  w: number;
  h: number;
}

export type PointerStep =
  | { kind: "move"; x: number; y: number }
  | { kind: "down"; button: Button }
  | { kind: "up"; button: Button }
  | { kind: "scroll"; dx: number; dy: number }
  | { kind: "wait"; ms: number };

const now = () => Date.now() >>> 0;
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** Read the registry without creating a keyboard/pointer or sending input. */
export async function waylandGlobals(): Promise<string[]> {
  if (!process.env.WAYLAND_DISPLAY) throw new Error("WAYLAND_DISPLAY is not set");
  const conn = await WaylandConnection.open();
  try {
    await conn.loadGlobals();
    return conn.globals.map((g) => g.iface);
  } finally {
    conn.close();
  }
}

/** True when the compositor offers the virtual pointer protocol. */
export async function virtualPointerAvailable(): Promise<boolean> {
  try { return (await waylandGlobals()).includes(VIRTUAL_POINTER_MANAGER); }
  catch { return false; }
}

/**
 * A virtual pointer kept open across calls, for gestures that span requests:
 * the companion trackpad sends mouseDown, drags, then mouseUp separately, and a
 * pointer torn down in between would drop the held button.
 */
export class PointerSession {
  private constructor(private conn: WaylandConnection, private pointer: number) {}

  static async open(): Promise<PointerSession> {
    const conn = await WaylandConnection.open();
    try {
      await conn.loadGlobals();
      const manager = conn.globals.find((g) => g.iface === VIRTUAL_POINTER_MANAGER);
      if (!manager) throw new Error(`${VIRTUAL_POINTER_MANAGER} is not offered by this compositor`);
      const managerId = conn.bind(manager, Math.min(manager.version, 2));
      const pointer = conn.newId();
      conn.send(managerId, 0, [{ u: 0 }, { u: pointer }]);
      return new PointerSession(conn, pointer);
    } catch (error) {
      conn.close();
      throw error;
    }
  }

  async move(x: number, y: number, extent: Extent) {
    const ax = Math.max(0, Math.min(extent.w - 1, Math.round(x - extent.x)));
    const ay = Math.max(0, Math.min(extent.h - 1, Math.round(y - extent.y)));
    this.conn.send(this.pointer, Ptr.MotionAbsolute, [{ u: now() }, { u: ax }, { u: ay }, { u: extent.w }, { u: extent.h }]);
    this.conn.send(this.pointer, Ptr.Frame);
    await this.conn.roundtrip();
  }

  async button(button: Button, down: boolean) {
    this.conn.send(this.pointer, Ptr.Button, [{ u: now() }, { u: BUTTONS[button] }, { u: down ? 1 : 0 }]);
    this.conn.send(this.pointer, Ptr.Frame);
    await this.conn.roundtrip();
  }

  async scroll(dx: number, dy: number) {
    this.conn.send(this.pointer, Ptr.AxisSource, [{ u: 0 }]);
    if (dy) this.conn.send(this.pointer, Ptr.Axis, [{ u: now() }, { u: 0 }, { fixed: dy }]);
    if (dx) this.conn.send(this.pointer, Ptr.Axis, [{ u: now() }, { u: 1 }, { fixed: dx }]);
    this.conn.send(this.pointer, Ptr.Frame);
    await this.conn.roundtrip();
  }

  async close() {
    try {
      this.conn.send(this.pointer, Ptr.Destroy);
      await this.conn.roundtrip().catch(() => {});
    } finally {
      this.conn.close();
    }
  }
}

/** Run pointer steps through a fresh virtual pointer, then tear it down. */
export async function runPointer(steps: PointerStep[], extent: Extent): Promise<void> {
  const conn = await WaylandConnection.open();
  try {
    await conn.loadGlobals();
    const manager = conn.globals.find((g) => g.iface === VIRTUAL_POINTER_MANAGER);
    if (!manager) throw new Error(`${VIRTUAL_POINTER_MANAGER} is not offered by this compositor`);
    const managerId = conn.bind(manager, Math.min(manager.version, 2));
    const pointer = conn.newId();
    conn.send(managerId, 0, [{ u: 0 }, { u: pointer }]); // create_virtual_pointer(seat: null, id)

    for (const step of steps) {
      switch (step.kind) {
        case "move": {
          const x = Math.max(0, Math.min(extent.w - 1, Math.round(step.x - extent.x)));
          const y = Math.max(0, Math.min(extent.h - 1, Math.round(step.y - extent.y)));
          conn.send(pointer, Ptr.MotionAbsolute, [{ u: now() }, { u: x }, { u: y }, { u: extent.w }, { u: extent.h }]);
          conn.send(pointer, Ptr.Frame);
          break;
        }
        case "down":
        case "up":
          conn.send(pointer, Ptr.Button, [{ u: now() }, { u: BUTTONS[step.button] }, { u: step.kind === "down" ? 1 : 0 }]);
          conn.send(pointer, Ptr.Frame);
          break;
        case "scroll":
          conn.send(pointer, Ptr.AxisSource, [{ u: 0 }]); // wheel
          if (step.dy) conn.send(pointer, Ptr.Axis, [{ u: now() }, { u: 0 }, { fixed: step.dy }]);
          if (step.dx) conn.send(pointer, Ptr.Axis, [{ u: now() }, { u: 1 }, { fixed: step.dx }]);
          conn.send(pointer, Ptr.Frame);
          break;
        case "wait":
          await conn.roundtrip();
          await sleep(step.ms);
          break;
      }
    }
    await conn.roundtrip();
    conn.send(pointer, Ptr.Destroy);
    await conn.roundtrip();
  } finally {
    conn.close();
  }
}
