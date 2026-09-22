import { open } from 'node:fs/promises';

/** A kernel-held lock survives async work and releases on process exit, including
 * crashes. Keep the lock file: unlinking it would let a second inode bypass it. */
export async function acquireCompanionLock(path: string): Promise<() => Promise<void>> {
  if (process.platform !== 'darwin') throw new Error('Companion installation requires macOS.');
  const file = await open(path, 'a', 0o600);
  try {
    const { dlopen } = await import('bun:ffi');
    const native = dlopen('/usr/lib/libSystem.B.dylib', {
      flock: { args: ['i32', 'i32'], returns: 'i32' },
    });
    try {
      if (native.symbols.flock(file.fd, 2 | 4) !== 0) throw new Error('Another installation of this app is active.');
    } finally { native.close(); }
  } catch (error) { await file.close(); throw error; }
  return () => file.close();
}
