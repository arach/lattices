import { expect, test } from 'bun:test';
import { mkdtemp, mkdir, writeFile, readFile, rm, lstat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { commitCompanionExclusive } from '../bin/companion-commit';

test.skipIf(process.platform !== 'darwin')('native exclusive rename moves exactly the staged directory', async () => {
  const root = await mkdtemp(join(tmpdir(), 'lat-commit-'));
  try {
    const staged = join(root, 'staged.app'), final = join(root, 'Final.app');
    await mkdir(staged); await writeFile(join(staged, 'marker'), 'new');
    const inode = (await lstat(staged)).ino;
    await commitCompanionExclusive(staged, final);
    expect((await lstat(final)).ino).toBe(inode);
    expect(await readFile(join(final, 'marker'), 'utf8')).toBe('new');
    await expect(lstat(staged)).rejects.toThrow();
  } finally { await rm(root, { recursive: true, force: true }); }
});
test.skipIf(process.platform !== 'darwin')('native exclusive rename preserves existing destination without nesting', async () => {
  const root = await mkdtemp(join(tmpdir(), 'lat-commit-'));
  try {
    const staged = join(root, 'staged.app'), final = join(root, 'Final.app');
    await mkdir(staged); await mkdir(final);
    await writeFile(join(staged, 'marker'), 'new'); await writeFile(join(final, 'marker'), 'old');
    await expect(commitCompanionExclusive(staged, final)).rejects.toThrow();
    expect(await readFile(join(final, 'marker'), 'utf8')).toBe('old');
    expect(await readFile(join(staged, 'marker'), 'utf8')).toBe('new');
    await expect(lstat(join(final, 'staged.app'))).rejects.toThrow();
  } finally { await rm(root, { recursive: true, force: true }); }
});
