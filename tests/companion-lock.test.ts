import { test, expect } from 'bun:test';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { acquireCompanionLock } from '../bin/companion-lock';

test.skipIf(process.platform !== 'darwin')('kernel lock rejects overlapping installers and permits retry after release', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'companion-lock-'));
  try {
    const path = join(dir, 'install.lock');
    const unlock = await acquireCompanionLock(path);
    try { await expect(acquireCompanionLock(path)).rejects.toThrow('active'); }
    finally { await unlock(); }
    const retry = await acquireCompanionLock(path);
    await retry();
    expect(true).toBe(true);
  } finally { await rm(dir, { recursive: true, force: true }); }
});
