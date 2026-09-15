import { lstat } from 'node:fs/promises';

/** Atomically place a staged app without replacing or nesting into any target.
 * Darwin's RENAME_EXCL (sys/stdio.h) closes the check-then-rename race.
 */
export async function commitCompanionExclusive(source: string, destination: string): Promise<void> {
  if (process.platform !== 'darwin') throw new Error('Atomic companion placement requires macOS.');
  if (source.includes('\0') || destination.includes('\0')) throw new Error('Invalid installation path.');
  const before = await lstat(source);
  if (!before.isDirectory() || before.isSymbolicLink()) throw new Error('Staged app is not a regular directory.');
  const { dlopen, ptr, read } = await import('bun:ffi');
  const native = dlopen('/usr/lib/libSystem.B.dylib', {
    renamex_np: { args: ['ptr', 'ptr', 'u32'], returns: 'i32' },
    __error: { args: [], returns: 'ptr' },
  });
  const from = Buffer.from(`${source}\0`), to = Buffer.from(`${destination}\0`);
  try {
    if (native.symbols.renamex_np(ptr(from), ptr(to), 0x00000004) !== 0) {
      const errorPointer = native.symbols.__error();
      const errno = errorPointer ? read.i32(errorPointer) : -1;
      throw new Error(`Atomic app placement failed (errno ${errno}); an existing destination was not replaced.`);
    }
  } finally { native.close(); }
}
