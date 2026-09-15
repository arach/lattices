import { expect, test } from 'bun:test';
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { verifyCompanionBundle } from '../bin/companion-installer';
import type { CompanionRelease } from '../bin/companion-release';
const release: CompanionRelease = { product: 'blink', version: '2.0.0', tag: 'blink-v2.0.0', assetURL: '', size: 1, bundleID: 'dev.arach.blink' };
test.skipIf(process.platform !== 'darwin')('real trust adapter rejects unsigned app and wrong identity', async () => {
  const root = await mkdtemp(join(tmpdir(), 'lat-trust-'));
  const app = join(root, 'Blink.app');
  try {
    await mkdir(join(app, 'Contents/MacOS'), { recursive: true });
    await writeFile(join(app, 'Contents/Info.plist'), `<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>dev.arach.blink</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleExecutable</key><string>Blink</string></dict></plist>`);
    await writeFile(join(app, 'Contents/MacOS/Blink'), '#!/bin/sh\nexit 0\n', { mode: 0o755 });
    await expect(verifyCompanionBundle(app, { ...release, bundleID: 'wrong.id' })).rejects.toThrow('wrong bundle identity');
    await expect(verifyCompanionBundle(app, release)).rejects.toThrow('codesign failed');
  } finally { await rm(root, { recursive: true, force: true }); }
});
